/// Read-only assembly of existing GIULIA facts for the Intelligence tools.
///
/// Scientific values are read from immutable LaLa result rows. Session values
/// are read through the same [SessionReportReader] used by the product screens.
/// This adapter does not run a second threshold method and writes nothing.
library;

import 'dart:convert';

import '../database/giulia_database.dart';
import '../database/platform_repository.dart';
import '../database/session_repository.dart';
import '../domain/diagnostic_comparability.dart';
import '../intelligence/athlete_state_models.dart';
import '../intelligence/models.dart';
import 'athlete_state_repository.dart';
import 'session_report.dart';

class GiuliaIntelligenceDataSource
    implements IntelligenceDataSource, AthleteStateDataSource {
  GiuliaIntelligenceDataSource({
    required this.database,
    required this.platform,
    required this.organizationId,
    required this.userId,
  }) : _reports = SessionReportReader(
         SessionRepository(database, platform: platform),
       );

  final GiuliaDatabase database;
  final PlatformRepository platform;
  final String organizationId;
  final String userId;
  final SessionReportReader _reports;

  @override
  AthleteState? getAthleteState(String athleteId, {required int nowUtcUs}) {
    if (!_mayRead(athleteId)) return null;
    return AthleteStateRepository(
      database: database,
      data: this,
      organizationId: organizationId,
    ).currentOrRefresh(athleteId, nowUtcUs: nowUtcUs);
  }

  @override
  IntelligenceAthlete? getAthleteProfile(String athleteId) {
    if (!_mayRead(athleteId)) return null;
    final rows = database.raw.select(
      '''SELECT id, name, birth_year, sex FROM athlete
          WHERE id = ? AND organization_id = ? AND archived_at_utc_us IS NULL''',
      [athleteId, organizationId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return IntelligenceAthlete(
      id: row['id'] as String,
      name: row['name'] as String,
      birthYear: row['birth_year'] as int?,
      sex: row['sex'] as String?,
      bodyMassKg: _attribute(athleteId, 'bodyMassKg'),
      maxHeartRateBpm: _attribute(athleteId, 'maxHeartRateBpm')?.round(),
      restingHeartRateBpm: _attribute(
        athleteId,
        'restingHeartRateBpm',
      )?.round(),
    );
  }

  @override
  List<IntelligenceSession> getRecentTraining(
    String athleteId, {
    int? fromUtcUs,
    int limit = 40,
  }) {
    if (!_mayRead(athleteId)) return const [];
    final rows = database.raw.select(
      '''SELECT training.id, training.started_at_utc_us,
                training.ended_at_utc_us, training.movement_type,
                imported.provider_id
           FROM xc_session training
           LEFT JOIN external_activity_import imported
             ON imported.session_id = training.id
          WHERE training.athlete_id = ? AND training.organization_id = ?
            AND training.started_at_utc_us >= ?
            AND NOT EXISTS (
              SELECT 1 FROM xc_canonical_source source
               WHERE source.session_id = training.id AND source.preference > 1
            )
          ORDER BY training.started_at_utc_us DESC
          LIMIT ?''',
      [athleteId, organizationId, fromUtcUs ?? -9223372036854775808, limit],
    );
    return [for (final row in rows) ?_session(row)];
  }

  @override
  List<IntelligenceTest> getTests(String athleteId, {int limit = 10}) {
    if (!_mayRead(athleteId)) return const [];
    final rows = database.raw.select(
      '''SELECT id, started_at_utc_us, sport, load_unit, load_semantics,
                protocol, status
           FROM xc_performance_test
          WHERE athlete_id = ? AND organization_id = ?
          ORDER BY started_at_utc_us DESC, id
          LIMIT ?''',
      [athleteId, organizationId, limit],
    );
    return [for (final row in rows) _test(row)];
  }

  @override
  List<IntelligenceObservation> getObservations(
    String athleteId, {
    int? fromUtcUs,
  }) {
    if (!_mayRead(athleteId)) return const [];
    final rows = database.raw.select(
      '''SELECT observed_at_utc_us, type, value, text_value, unit, quality,
                session_id, test_id
           FROM xc_observation
          WHERE athlete_id = ? AND observed_at_utc_us >= ?
          ORDER BY observed_at_utc_us, id''',
      [athleteId, fromUtcUs ?? -9223372036854775808],
    );
    return [
      for (final row in rows)
        IntelligenceObservation(
          type: _observationType(row['type'] as String),
          observedAtUtcUs: row['observed_at_utc_us'] as int,
          value: _double(row['value']),
          text: row['text_value'] as String?,
          unit: row['unit'] as String?,
          quality: (row['quality'] as String?) ?? 'recorded',
          sessionId: row['session_id'] as String?,
          testId: row['test_id'] as String?,
        ),
    ];
  }

  IntelligenceSession? _session(Map<String, Object?> row) {
    final id = row['id'] as String;
    final report = _reports.of(id);
    if (report == null) return null;
    final heartRate = database.raw
        .select(
          '''SELECT CAST(ROUND(AVG(bpm)) AS INTEGER) AS average_bpm,
                MAX(bpm) AS peak_bpm
           FROM heart_rate_sample WHERE session_id = ?''',
          [id],
        )
        .first;
    final rpeRows = database.raw.select(
      '''SELECT value FROM xc_observation
          WHERE session_id = ? AND type = 'rpe' AND quality <> 'rejected'
            AND value IS NOT NULL
          ORDER BY observed_at_utc_us DESC, id DESC LIMIT 1''',
      [id],
    );
    final recap = report.recap;
    final sides = report.sidePower;
    final external = _sessionMetrics(id);
    final externalPower = _double(external['averagePowerWatt']);
    final externalPeakPower = _double(external['peakPowerWatt']);
    final externalDuration = (external['activeSeconds'] as num?)?.round();
    final intervals = <IntelligenceInterval>[
      for (final interval in report.intervals)
        IntelligenceInterval(
          ordinal: interval.ordinal,
          durationSeconds: interval.duration.inSeconds,
          kind: interval.kind.name,
          averagePowerWatt: interval.averagePowerWatt,
          peakPowerWatt: interval.peakPowerWatt,
          leftPowerWatt: interval.leftWatt,
          rightPowerWatt: interval.rightWatt,
          targetMinWatt: interval.targetMinWatt,
          targetMaxWatt: interval.targetMaxWatt,
        ),
    ];
    if (intervals.isEmpty && externalDuration != null && externalDuration > 0) {
      intervals.add(
        IntelligenceInterval(
          ordinal: 0,
          durationSeconds: externalDuration,
          kind: 'work',
          averagePowerWatt: externalPower,
          peakPowerWatt: externalPeakPower,
          averageSpeedKmh: _double(external['averageSpeedKmh']),
          peakSpeedKmh: _double(external['peakSpeedKmh']),
        ),
      );
    }
    return IntelligenceSession(
      id: id,
      startedAtUtcUs: row['started_at_utc_us'] as int,
      durationSeconds: externalDuration ?? report.activeTime.inSeconds,
      sport:
          (row['movement_type'] as String?) ??
          (report.hasStrokes ? 'ercolina' : 'generic'),
      completed: row['ended_at_utc_us'] != null,
      providerId: row['provider_id'] as String?,
      averagePowerWatt: recap?.averagePowerWatt ?? externalPower,
      peakPowerWatt: report.peakPowerWatt ?? externalPeakPower,
      averageSpeedKmh: _double(external['averageSpeedKmh']),
      peakSpeedKmh: _double(external['peakSpeedKmh']),
      distanceMetres: _double(external['distanceMetres']),
      workJoule: report.workJoule == 0
          ? _double(external['workJoule'])
          : report.workJoule,
      averageHeartRateBpm: heartRate['average_bpm'] as int?,
      peakHeartRateBpm: heartRate['peak_bpm'] as int?,
      rpe: rpeRows.isEmpty ? null : _double(rpeRows.first['value']),
      strokeCount: report.hasStrokes ? report.strokeCount : null,
      strokeRatePerMinute: recap?.strokeRatePerMinute,
      workPerStrokeJoule: report.workPerStroke?.total,
      leftPowerWatt: sides?.left,
      rightPowerWatt: sides?.right,
      symmetryPercent: recap?.symmetryPercent,
      fatiguePercent: report.fatiguePercent,
      powerVariationPercent: report.powerVariationPercent,
      intervals: intervals,
    );
  }

  Map<String, Object?> _sessionMetrics(String sessionId) {
    final rows = database.raw.select(
      'SELECT metrics_json FROM session_metrics WHERE session_id = ?',
      [sessionId],
    );
    if (rows.isEmpty) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(rows.first['metrics_json'] as String);
      return decoded is Map<String, Object?>
          ? decoded
          : const <String, Object?>{};
    } on FormatException {
      return const <String, Object?>{};
    }
  }

  IntelligenceTest _test(Map<String, Object?> head) {
    final testId = head['id'] as String;
    final runRows = database.raw.select(
      '''SELECT id, lala_engine_version FROM lala_calculation_run
          WHERE test_id = ? ORDER BY run_index DESC LIMIT 1''',
      [testId],
    );
    final runId = runRows.isEmpty ? null : runRows.first['id'] as String;
    final engineVersion = runRows.isEmpty
        ? null
        : runRows.first['lala_engine_version'] as String;
    final stages = _stages(testId);
    final thresholds = runId == null
        ? const <IntelligenceThreshold>[]
        : _thresholds(runId);
    final zones = runId == null ? const <IntelligenceZone>[] : _zones(runId);
    final usableStages = stages
        .where((stage) => !stage.point.excluded)
        .map(
          (stage) =>
              (load: stage.point.load, durationSeconds: stage.durationSeconds),
        );
    final quality = <String>[];
    final excluded = stages.where((stage) => stage.point.excluded).length;
    final partial = stages.where((stage) => stage.point.partial).length;
    final missingHeartRate = stages
        .where((stage) => stage.point.heartRateBpm == null)
        .length;
    if (stages.length < 4) {
      quality.add('Weniger als vier Stufen tragen einen Laktatwert.');
    }
    if (excluded > 0) quality.add('$excluded Stufen wurden ausgeschlossen.');
    if (partial > 0) quality.add('$partial Stufen sind unvollständig.');
    if (missingHeartRate > 0) {
      quality.add('$missingHeartRate Stufen haben keine Herzfrequenz.');
    }
    if (thresholds
        .where((item) => item.selected && item.load != null)
        .isEmpty) {
      quality.add(
        'Der jüngste Calculation Run lieferte keine ausgewählte Schwelle.',
      );
    }
    if (zones.any((zone) => zone.provisional)) {
      quality.add('Mindestens eine Zonengrenze ist als vorläufig markiert.');
    }

    return IntelligenceTest(
      id: testId,
      startedAtUtcUs: head['started_at_utc_us'] as int,
      sport: (head['sport'] as String?) ?? 'generic',
      loadUnit: (head['load_unit'] as String?) ?? 'W',
      loadSemantics:
          (head['load_semantics'] as String?) ?? 'load.protocol_target',
      protocol: head['protocol'] as String,
      status: (head['status'] as String?) ?? 'unknown',
      curve: [for (final stage in stages) stage.point],
      thresholds: thresholds,
      zones: zones,
      structure: DiagnosticStepStructure.fromStages(usableStages),
      engineVersion: engineVersion,
      qualityNotes: quality,
    );
  }

  List<({IntelligenceCurvePoint point, int durationSeconds})> _stages(
    String testId,
  ) {
    final rows = database.raw.select(
      '''SELECT stage.ordinal,
                COALESCE(correction.corrected_load_value, stage.load_value,
                         stage.mean_power_w, stage.target_power_w) AS load_value,
                CAST(ROUND(stage.duration_s) AS INTEGER) AS duration_s,
                COALESCE(correction.corrected_heart_rate_bpm,
                         stage.heart_rate_bpm) AS heart_rate_bpm,
                COALESCE(correction.corrected_rpe, stage.rpe) AS rpe,
                stage.excluded, stage.partial,
                COALESCE(correction.corrected_lactate_mmol_l,
                         observation.value) AS lactate
           FROM test_stage stage
           LEFT JOIN diagnostic_stage_correction correction ON correction.id = (
             SELECT latest.id FROM diagnostic_stage_correction latest
              WHERE latest.stage_id = stage.id
              ORDER BY latest.corrected_at_utc_us DESC, latest.id DESC LIMIT 1)
           LEFT JOIN xc_observation observation ON observation.id = (
             SELECT latest_observation.id FROM xc_observation latest_observation
              WHERE latest_observation.test_stage_id = stage.id
                AND latest_observation.type = 'lactate'
                AND latest_observation.quality <> 'rejected'
              ORDER BY latest_observation.observed_at_utc_us DESC,
                       latest_observation.id DESC LIMIT 1)
          WHERE stage.test_id = ?
          ORDER BY stage.ordinal''',
      [testId],
    );
    return [
      for (final row in rows)
        if (_double(row['load_value']) case final load?)
          if (_double(row['lactate']) case final lactate?)
            (
              point: IntelligenceCurvePoint(
                stageNumber: row['ordinal'] as int,
                load: load,
                lactateMmolPerLitre: lactate,
                heartRateBpm: row['heart_rate_bpm'] as int?,
                rpe: _double(row['rpe']),
                excluded: (row['excluded'] as int? ?? 0) == 1,
                partial: (row['partial'] as int? ?? 0) == 1,
              ),
              durationSeconds: row['duration_s'] as int? ?? 0,
            ),
    ];
  }

  List<IntelligenceThreshold> _thresholds(String runId) => database.raw
      .select(
        '''SELECT threshold_type, method, method_version, lala_engine_version,
                  status, load_value, power_w, load_unit, heart_rate_bpm,
                  lactate_mmol_l, is_selected_standard, interpretation
             FROM xc_threshold_result
            WHERE calculation_run_id = ? ORDER BY archive_rowid''',
        [runId],
      )
      .map(
        (row) => IntelligenceThreshold(
          type: row['threshold_type'] as String,
          methodId: row['method'] as String,
          methodVersion: row['method_version'] as String,
          engineVersion: (row['lala_engine_version'] as String?) ?? 'unknown',
          status: (row['status'] as String?) ?? 'unknown',
          load: _double(row['load_value']) ?? _double(row['power_w']),
          loadUnit: (row['load_unit'] as String?) ?? 'W',
          heartRateBpm: row['heart_rate_bpm'] as int?,
          lactateMmolPerLitre: _double(row['lactate_mmol_l']),
          selected: (row['is_selected_standard'] as int? ?? 0) == 1,
          interpretation: row['interpretation'] as String?,
        ),
      )
      .toList(growable: false);

  List<IntelligenceZone> _zones(String runId) => database.raw
      .select(
        '''SELECT zone_set.zone_model_id, zone_set.zone_model_name,
                  zone_set.method_version, zone_set.lala_engine_version,
                  zone_set.quality, zone.name, zone.code, zone.unit,
                  COALESCE(zone.lower_load_exact, zone.lower_bound) AS lower_load,
                  COALESCE(zone.upper_load_exact, zone.upper_bound) AS upper_load,
                  zone.lower_heart_rate_display, zone.upper_heart_rate_display,
                  zone.provisional_boundary, zone.boundary_rationale
             FROM xc_training_zone_set zone_set
             JOIN training_zone zone ON zone.zone_set_id = zone_set.id
            WHERE zone_set.calculation_run_id = ?
            ORDER BY zone_set.archive_rowid, zone.ordinal''',
        [runId],
      )
      .map(
        (row) => IntelligenceZone(
          modelId: (row['zone_model_id'] as String?) ?? 'unknown',
          modelName:
              (row['zone_model_name'] as String?) ?? 'Unbenanntes Modell',
          modelVersion: row['method_version'] as String,
          engineVersion: (row['lala_engine_version'] as String?) ?? 'unknown',
          quality: (row['quality'] as String?) ?? 'unknown',
          name: row['name'] as String,
          code: (row['code'] as String?) ?? '${row['name']}',
          loadUnit: row['unit'] as String,
          lowerLoad: _double(row['lower_load']),
          upperLoad: _double(row['upper_load']),
          lowerHeartRateBpm: row['lower_heart_rate_display'] as int?,
          upperHeartRateBpm: row['upper_heart_rate_display'] as int?,
          provisional: (row['provisional_boundary'] as int? ?? 0) == 1,
          rationale: row['boundary_rationale'] as String?,
        ),
      )
      .toList(growable: false);

  double? _attribute(String athleteId, String attribute) {
    final rows = database.raw.select(
      '''SELECT value_numeric FROM athlete_attribute
          WHERE lower(trim(source)) NOT LIKE 'strava%' AND athlete_id = ? AND attribute = ?
          ORDER BY effective_from_utc_us DESC, recorded_at_utc_us DESC
          LIMIT 1''',
      [athleteId, attribute],
    );
    return rows.isEmpty ? null : _double(rows.first['value_numeric']);
  }

  bool _mayRead(String athleteId) =>
      platform.canViewAthlete(userId: userId, athleteId: athleteId) &&
      platform.organizationOfAthlete(athleteId) == organizationId;

  static IntelligenceObservationType _observationType(String stored) =>
      switch (stored) {
        'lactate' => IntelligenceObservationType.lactate,
        'rpe' => IntelligenceObservationType.rpe,
        _ => IntelligenceObservationType.note,
      };

  static double? _double(Object? value) => (value as num?)?.toDouble();
}
