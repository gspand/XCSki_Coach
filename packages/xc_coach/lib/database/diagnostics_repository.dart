import 'dart:convert';

import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_coach/database/platform_repository.dart';
import 'package:xc_coach/domain/diagnostics.dart';
import 'package:xc_coach/domain/platform.dart';
import 'package:xc_coach/lala/integration/lala_calculation_service.dart';
import 'package:xc_coach/measurement/contracts/measurement_sample.dart';
import 'package:xc_coach/measurement/contracts/test_session.dart';
import 'package:xc_coach/measurement/contracts/test_stage.dart';
import 'package:xc_coach/observation/observation.dart';

/// Persistence for diagnostic tests and their LaLa evaluations.
///
/// **Division of labour.** LaLa computes, Giulia writes it down. This class
/// contains no threshold logic, no interpolation and no zone arithmetic; it
/// calls [LalaCalculationService] and maps the result into rows.
///
/// **Immutability.** Measurements and results are inserted, never updated. The
/// schema enforces this with triggers, so a bug in this class cannot silently
/// rewrite a historical finding either.
///
/// **Re-evaluation.** Calling [evaluate] again appends a new calculation run
/// with the next `run_index`. The previous run, its thresholds and its zone
/// sets stay exactly as they were. That is what makes it possible to analyse a
/// 2026 test again in 2028 with a newer engine and compare both readings.
class DiagnosticsRepository {
  DiagnosticsRepository(
    this.database, {
    PlatformRepository? platform,
    this.calculator = const LalaCalculationService(),
  }) : platform = platform ?? PlatformRepository(database);

  final GiuliaDatabase database;
  final PlatformRepository platform;

  /// The only entry point into the scientific core. Injectable so a test can
  /// observe the adapter boundary without stubbing the mathematics.
  final LalaCalculationService calculator;

  // ------------------------------------------------------------------ tests

  /// Creates a test head.
  ///
  /// [deviceId] stays optional on purpose: a lactate step test on a treadmill
  /// with a handheld analyser is a complete test and must not be blocked by
  /// the absence of hardware.
  void createTest({
    required String id,
    required String organizationId,
    required String athleteId,
    required String sport,
    required String modality,
    required String protocol,
    required String protocolVersion,
    required String loadUnit,
    required MeasurementSource measurementSource,
    required int startedAtUtcUs,
    String? deviceId,
    String? sessionId,
    String? createdByUserId,
    String? supervisedByUserId,
    double? stageIncrementHint,
    String? notes,
    PerformanceTestStatus status = PerformanceTestStatus.running,
    String loadSemantics = 'load.protocol_target',
    String? stageAggregation,
  }) {
    _assertAthleteInOrganization(athleteId, organizationId);
    if (deviceId != null) {
      _assertDeviceInOrganization(deviceId, organizationId);
    }
    if (createdByUserId != null) {
      platform.assertCanRecordDiagnosticsFor(
        userId: createdByUserId,
        athleteId: athleteId,
      );
    }

    database.transaction(() {
      database.raw.execute(
        '''INSERT INTO performance_test(
             id, organization_id, athlete_id, session_id, device_id,
             supervised_by_user_id, created_by_user_id, protocol,
             protocol_version, sport, modality, measurement_source, status,
             load_unit, stage_increment_hint, started_at_utc_us, notes,
             load_semantics, stage_aggregation,
             created_at_utc_us, updated_at_utc_us)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          id,
          organizationId,
          athleteId,
          sessionId,
          deviceId,
          supervisedByUserId,
          createdByUserId,
          protocol,
          protocolVersion,
          sport,
          modality,
          measurementSource.name,
          status.name,
          loadUnit,
          stageIncrementHint,
          startedAtUtcUs,
          notes,
          loadSemantics,
          stageAggregation,
          startedAtUtcUs,
          startedAtUtcUs,
        ],
      );
      platform.enqueueSync(
        organizationId: organizationId,
        entity: 'performance_test',
        entityId: id,
        operation: 'insert',
        nowUtcUs: startedAtUtcUs,
      );
      platform.writeAudit(
        organizationId: organizationId,
        actorUserId: createdByUserId,
        action: 'create_performance_test',
        entity: 'performance_test',
        entityId: id,
        nowUtcUs: startedAtUtcUs,
        detail: '$sport/$modality/${measurementSource.name}',
      );
    });
  }

  /// Records one step. Steps are append-only; an unwanted step is excluded
  /// with a reason, not deleted.
  void addStage({
    required String testId,
    required PersistedTestStage stage,
    required int nowUtcUs,
  }) {
    final head = _testHead(testId);
    database.transaction(() {
      database.raw.execute(
        '''INSERT INTO test_stage(
             id, test_id, ordinal, target_power_w, duration_s, mean_power_w,
             heart_rate_bpm, stroke_rate_per_min, rpe, completed,
             started_at_utc_us, ended_at_utc_us, target_value, load_value,
             load_unit, speed_km_h, pace_s_per_km, cadence_per_min, excluded,
             exclusion_reason, notes, partial, work_j, peak_power_w,
             steady_end_power_w, stroke_count, left_work_share, sample_count,
             window_start_us, window_end_us)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                   ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          stage.id,
          testId,
          stage.stageIndex,
          // Ercolina provenance columns from v1. Filled only when the load
          // really is power; a treadmill speed must never appear in a column
          // named `target_power_w`.
          LoadUnits.isPower(head.loadUnit)
              ? (stage.targetValue ?? stage.loadValue)
              : null,
          stage.durationSeconds.toDouble(),
          stage.meanPowerWatt,
          stage.heartRateBpm,
          stage.strokeRatePerMinute,
          stage.rpe?.toDouble(),
          stage.excluded ? 0 : 1,
          stage.startedAtUtcUs,
          stage.endedAtUtcUs,
          stage.targetValue,
          stage.loadValue,
          head.loadUnit,
          stage.speedKilometresPerHour,
          stage.paceSecondsPerKilometre,
          stage.cadencePerMinute,
          stage.excluded ? 1 : 0,
          stage.exclusionReason,
          stage.notes,
          stage.partial ? 1 : 0,
          stage.workJoule,
          stage.peakPowerWatt,
          stage.steadyEndPowerWatt,
          stage.strokeCount,
          stage.leftWorkShare,
          stage.rawSampleCount,
          stage.windowStartUs,
          stage.windowEndUs,
        ],
      );
      platform.enqueueSync(
        organizationId: head.organizationId,
        entity: 'test_stage',
        entityId: stage.id,
        operation: 'insert',
        nowUtcUs: nowUtcUs,
      );
    });
  }

  /// Adds the values a human contributes after a measured step: the lactate
  /// sample is a separate row, but perceived exertion, a note and the decision
  /// to drop a step belong to the step itself.
  ///
  /// Only permitted while the test is still running. Once a test is closed its
  /// steps are the record of what was measured, and a run may already have
  /// been calculated from them.
  void annotateStage({
    required String stageId,
    required int nowUtcUs,
    int? rpe,
    String? notes,
    bool? excluded,
    String? exclusionReason,
  }) {
    final rows = database.raw.select(
      'SELECT test_id FROM test_stage WHERE id = ?',
      [stageId],
    );
    if (rows.isEmpty) throw StateError('Unknown test stage $stageId');
    final testId = rows.first['test_id'] as String;
    final head = _testHead(testId);
    if (head.status != PerformanceTestStatus.running) {
      throw const DiagnosticsDataException(
        'Eine Stufe kann nur ergänzt werden, solange der Test läuft.',
      );
    }

    database.transaction(() {
      database.raw.execute(
        '''UPDATE test_stage
              SET rpe = COALESCE(?, rpe),
                  notes = COALESCE(?, notes),
                  excluded = COALESCE(?, excluded),
                  exclusion_reason = COALESCE(?, exclusion_reason),
                  completed = CASE WHEN COALESCE(?, excluded) = 1 THEN 0
                                   ELSE completed END
            WHERE id = ?''',
        [
          rpe?.toDouble(),
          notes,
          excluded == null ? null : (excluded ? 1 : 0),
          exclusionReason,
          excluded == null ? null : (excluded ? 1 : 0),
          stageId,
        ],
      );
      platform.enqueueSync(
        organizationId: head.organizationId,
        entity: 'test_stage',
        entityId: stageId,
        operation: 'update',
        nowUtcUs: nowUtcUs,
      );
    });
  }

  /// Writes down what the radio link did during a test.
  ///
  /// A dropped connection is a property of the measurement, not of the screen
  /// that displayed it. Recording it means a later reader can tell whether a
  /// step was measured under a stable link.
  void recordConnectivityEvent({
    required String id,
    required String testId,
    required String state,
    required int occurredAtUtcUs,
    String? stageId,
    String? deviceId,
    String? detail,
  }) {
    final head = _testHead(testId);
    database.raw.execute(
      '''INSERT INTO test_connectivity_event(
           id, test_id, stage_id, device_id, occurred_at_utc_us, state, detail)
         VALUES (?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        testId,
        stageId,
        deviceId ?? head.deviceId,
        occurredAtUtcUs,
        state,
        detail,
      ],
    );
  }

  /// Connectivity events of a test, oldest first.
  List<TestConnectivityEvent> connectivityEventsOfTest(String testId) =>
      database.raw
          .select(
            '''SELECT id, stage_id, device_id, occurred_at_utc_us, state, detail
                 FROM test_connectivity_event WHERE test_id = ?
                ORDER BY occurred_at_utc_us, id''',
            [testId],
          )
          .map(
            (row) => TestConnectivityEvent(
              id: row['id'] as String,
              stageId: row['stage_id'] as String?,
              deviceId: row['device_id'] as String?,
              occurredAtUtcUs: row['occurred_at_utc_us'] as int,
              state: row['state'] as String,
              detail: row['detail'] as String?,
            ),
          )
          .toList(growable: false);

  /// Records one lactate measurement.
  ///
  /// [PersistedLactateSample.stageId] may be null for rest, warm-up and
  /// recovery samples. A raw measurement is never overwritten by a later
  /// interpretation — the schema rejects the attempt.
  void addLactateSample({
    required String testId,
    required PersistedLactateSample sample,
    required int nowUtcUs,
    ObservationSource source = ObservationSource.manual,
  }) {
    final head = _testHead(testId);
    database.transaction(() {
      database.raw.execute(
        '''INSERT INTO lactate_sample(
             id, test_id, stage_id, athlete_id, sampled_at_utc_us,
             lactate_mmol_l, context, sample_site, entered_by_user_id,
             recorded_at_utc_us, note)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          sample.id,
          testId,
          sample.stageId,
          head.athleteId,
          sample.sampledAtUtcUs,
          sample.lactateMmolPerLitre,
          sample.context.name,
          sample.site.name,
          sample.enteredByUserId,
          nowUtcUs,
          sample.note,
        ],
      );
      // Parallelschreibpfad in die Beobachtungen.
      //
      // Zwischenstand, mit Absicht: Die Auswertung liest weiter aus
      // `lactate_sample`, aber jeder neue Wert steht ab sofort auch als
      // Beobachtung da. Nur so lässt sich der Umstieg an echten Daten
      // nachweisen statt nur an migrierten. Fällt der Altbestand später weg,
      // fällt hier der obere Teil weg — nicht dieser.
      database.raw.execute(
        '''INSERT INTO observation(
             id, athlete_id, observed_at_utc_us, type, value, text_value,
             unit, source, quality, recorded_by_user_id, occasion,
             sample_site, test_id, test_stage_id, legacy_lactate_sample_id)
           VALUES (?, ?, ?, 'lactate', ?, ?, 'mmol/l', ?, 'recorded',
                   ?, ?, ?, ?, ?, ?)''',
        [
          'obs-lactate-${sample.id}',
          head.athleteId,
          sample.sampledAtUtcUs,
          sample.lactateMmolPerLitre,
          sample.note,
          // Woher der Wert kommt. Voreinstellung `manual`, weil ein Mensch am
          // Bildschirm der Normalfall ist — ein Laktatmessgerät, das seinen
          // Speicher überträgt, ist es nicht, und die Beobachtung soll den
          // Unterschied tragen.
          source.name,
          sample.enteredByUserId,
          sample.context.name,
          sample.site.name,
          testId,
          sample.stageId,
          sample.id,
        ],
      );
      platform.enqueueSync(
        organizationId: head.organizationId,
        entity: 'lactate_sample',
        entityId: sample.id,
        operation: 'insert',
        nowUtcUs: nowUtcUs,
      );
    });
  }

  /// Marks the measurement phase as finished. Only the head row changes;
  /// no measured value is touched.
  void completeTest({
    required String testId,
    required int endedAtUtcUs,
    PerformanceTestStatus status = PerformanceTestStatus.completed,
    String? notes,
  }) {
    final head = _testHead(testId);
    database.raw.execute(
      '''UPDATE performance_test
            SET ended_at_utc_us = ?, status = ?, notes = COALESCE(?, notes),
                updated_at_utc_us = ?
          WHERE id = ?''',
      [endedAtUtcUs, status.name, notes, endedAtUtcUs, testId],
    );
    platform.enqueueSync(
      organizationId: head.organizationId,
      entity: 'performance_test',
      entityId: testId,
      operation: 'update',
      nowUtcUs: endedAtUtcUs,
    );
  }

  /// Corrects a documented transcription error without rewriting the original
  /// raw stage or lactate sample. A fresh calculation run can then evaluate
  /// the corrected working values while earlier runs retain their original
  /// fingerprint and result.
  /// Records the diagnostician's own assessment on a test.
  ///
  /// GIULIA states no verdict — «mittelmäßig» or «ausbaufähig» is a judgement,
  /// and a judgement needs an author who knows the athlete. This is where that
  /// author writes, and the report prints it under their heading.
  ///
  /// Unlike a stage correction, this is a plain update rather than an
  /// insert-only history: the text is commentary on the test, not a measured
  /// fact, and a coach rewording a sentence is not an event anybody needs to
  /// audit. The measurements and the calculation runs stay untouched — nothing
  /// here can change a threshold.
  void recordTestNotes({
    required String testId,
    required String actorUserId,
    required String? notes,
  }) {
    final rows = database.raw.select(
      'SELECT athlete_id FROM xc_performance_test WHERE id = ?',
      [testId],
    );
    if (rows.isEmpty) throw StateError('Unknown test $testId');
    platform.assertCanRecordDiagnosticsFor(
      userId: actorUserId,
      athleteId: rows.single['athlete_id'] as String,
    );
    final trimmed = notes?.trim();
    database.raw.execute('UPDATE performance_test SET notes = ? WHERE id = ?', [
      trimmed == null || trimmed.isEmpty ? null : trimmed,
      testId,
    ]);
  }

  void correctStageData({
    required String id,
    required String stageId,
    required String actorUserId,
    required String reason,
    required int correctedAtUtcUs,
    double? loadValue,
    int? heartRateBpm,
    int? rpe,
    double? lactateMmolPerLitre,
  }) {
    final rows = database.raw.select(
      '''SELECT s.test_id, t.organization_id, t.athlete_id
           FROM test_stage s JOIN xc_performance_test t ON t.id = s.test_id
          WHERE s.id = ?''',
      [stageId],
    );
    if (rows.isEmpty) throw StateError('Unknown test stage $stageId');
    final row = rows.single;
    final testId = row['test_id'] as String;
    final organizationId = row['organization_id'] as String;
    platform.assertCanRecordDiagnosticsFor(
      userId: actorUserId,
      athleteId: row['athlete_id'] as String,
    );
    if (reason.trim().isEmpty) {
      throw const DiagnosticsDataException(
        'Eine Korrektur braucht eine kurze Begründung.',
      );
    }
    if (loadValue == null &&
        heartRateBpm == null &&
        rpe == null &&
        lactateMmolPerLitre == null) {
      throw const DiagnosticsDataException(
        'Mindestens ein korrigierter Wert ist erforderlich.',
      );
    }
    database.raw.execute(
      '''INSERT INTO diagnostic_stage_correction(
           id, organization_id, test_id, stage_id, corrected_load_value,
           corrected_heart_rate_bpm, corrected_rpe, corrected_lactate_mmol_l,
           reason, corrected_by_user_id, corrected_at_utc_us)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        organizationId,
        testId,
        stageId,
        loadValue,
        heartRateBpm,
        rpe,
        lactateMmolPerLitre,
        reason.trim(),
        actorUserId,
        correctedAtUtcUs,
      ],
    );
    platform.enqueueSync(
      organizationId: organizationId,
      entity: 'diagnostic_stage_correction',
      entityId: id,
      operation: 'insert',
      nowUtcUs: correctedAtUtcUs,
    );
    platform.writeAudit(
      organizationId: organizationId,
      actorUserId: actorUserId,
      action: 'correct_diagnostic_stage',
      entity: 'test_stage',
      entityId: stageId,
      nowUtcUs: correctedAtUtcUs,
      detail: reason.trim(),
    );
  }

  // ------------------------------------------------------------------ reads

  /// Rebuilds the evaluable test from its rows. This is the DB → domain half
  /// of the integration boundary.
  MeasurementSession loadTestData(String testId) {
    final head = _testHead(testId);

    final stages = database.raw
        .select(
          '''SELECT s.id, s.ordinal, COALESCE(c.corrected_load_value, s.load_value) AS load_value, s.duration_s, s.started_at_utc_us,
                    ended_at_utc_us, target_value, heart_rate_bpm, speed_km_h,
                    pace_s_per_km, cadence_per_min, stroke_rate_per_min,
                    mean_power_w, rpe, excluded, exclusion_reason, notes,
                    partial, work_j, peak_power_w, steady_end_power_w,
                    stroke_count, left_work_share, sample_count,
                    window_start_us, window_end_us,
                    COALESCE(c.corrected_heart_rate_bpm, s.heart_rate_bpm) AS corrected_hr,
                    COALESCE(c.corrected_rpe, s.rpe) AS corrected_rpe
                  FROM test_stage s
                LEFT JOIN diagnostic_stage_correction c ON c.id = (
                  SELECT latest.id FROM diagnostic_stage_correction latest
                   WHERE latest.stage_id = s.id
                   ORDER BY latest.corrected_at_utc_us DESC, latest.id DESC LIMIT 1)
                    WHERE s.test_id = ? ORDER BY s.ordinal''',
          [testId],
        )
        .map(
          (row) => PersistedTestStage(
            id: row['id'] as String,
            stageIndex: row['ordinal'] as int,
            loadValue: (row['load_value'] as num?)?.toDouble() ?? 0,
            durationSeconds: ((row['duration_s'] as num?) ?? 0).round(),
            startedAtUtcUs: row['started_at_utc_us'] as int?,
            endedAtUtcUs: row['ended_at_utc_us'] as int?,
            targetValue: (row['target_value'] as num?)?.toDouble(),
            heartRateBpm: row['corrected_hr'] as int?,
            speedKilometresPerHour: (row['speed_km_h'] as num?)?.toDouble(),
            paceSecondsPerKilometre: row['pace_s_per_km'] as int?,
            cadencePerMinute: (row['cadence_per_min'] as num?)?.toDouble(),
            strokeRatePerMinute: (row['stroke_rate_per_min'] as num?)
                ?.toDouble(),
            meanPowerWatt: (row['mean_power_w'] as num?)?.toDouble(),
            rpe: (row['corrected_rpe'] as num?)?.round(),
            excluded: (row['excluded'] as int) == 1,
            exclusionReason: row['exclusion_reason'] as String?,
            notes: row['notes'] as String?,
            partial: (row['partial'] as int) == 1,
            workJoule: (row['work_j'] as num?)?.toDouble(),
            peakPowerWatt: (row['peak_power_w'] as num?)?.toDouble(),
            steadyEndPowerWatt: (row['steady_end_power_w'] as num?)?.toDouble(),
            strokeCount: row['stroke_count'] as int?,
            leftWorkShare: (row['left_work_share'] as num?)?.toDouble(),
            rawSampleCount: row['sample_count'] as int?,
            windowStartUs: row['window_start_us'] as int?,
            windowEndUs: row['window_end_us'] as int?,
          ),
        )
        .toList(growable: false);

    final samples = database.raw
        .select(
          '''SELECT l.id, l.stage_id,
              COALESCE(c.corrected_lactate_mmol_l, l.lactate_mmol_l) AS lactate_mmol_l,
              l.sampled_at_utc_us, l.context,
                    sample_site, entered_by_user_id, note
            FROM lactate_sample l
          LEFT JOIN diagnostic_stage_correction c ON c.id = (
            SELECT latest.id FROM diagnostic_stage_correction latest
             WHERE latest.stage_id = l.stage_id
             ORDER BY latest.corrected_at_utc_us DESC, latest.id DESC LIMIT 1)
              WHERE l.test_id = ?
              ORDER BY l.sampled_at_utc_us, l.id''',
          [testId],
        )
        .map(
          (row) => PersistedLactateSample(
            id: row['id'] as String,
            stageId: row['stage_id'] as String?,
            lactateMmolPerLitre: (row['lactate_mmol_l'] as num).toDouble(),
            sampledAtUtcUs: row['sampled_at_utc_us'] as int,
            context: LactateSampleContext.values.byName(
              row['context'] as String,
            ),
            site: LactateSampleSite.values.byName(row['sample_site'] as String),
            enteredByUserId: row['entered_by_user_id'] as String?,
            note: row['note'] as String?,
          ),
        )
        .toList(growable: false);

    return MeasurementSession(
      testId: testId,
      organizationId: head.organizationId,
      athleteId: head.athleteId,
      sport: head.sport,
      modality: head.modality,
      protocol: head.protocol,
      protocolVersion: head.protocolVersion,
      loadUnit: head.loadUnit,
      measurementSource: head.measurementSource,
      startedAtUtcUs: head.startedAtUtcUs,
      deviceId: head.deviceId,
      stageIncrementHint: head.stageIncrementHint,
      stages: stages,
      samples: samples,
      // The mass that was true **on the day of the test**, not today's.
      //
      // `athlete_attribute` is time-effective for exactly this reason: a
      // threshold of 226 W is 3,65 W/kg at 62 kg and 3,42 W/kg at 66 kg, and
      // reading last winter's test against this spring's mass would invent a
      // change in relative power that no measurement produced.
      bodyMassKg: platform.attributeAt(
        athleteId: head.athleteId,
        attribute: AthleteAttribute.bodyMassKg,
        asOfUtcUs: head.startedAtUtcUs,
      ),
    );
  }

  /// Tests of one athlete, newest first.
  List<PerformanceTestHead> testsOfAthlete(String athleteId) => database.raw
      .select(
        '''SELECT id FROM xc_performance_test WHERE athlete_id = ?
            ORDER BY started_at_utc_us DESC, id''',
        [athleteId],
      )
      .map((row) => _testHead(row['id'] as String))
      .toList(growable: false);

  // ------------------------------------------------------------- evaluation

  /// Evaluates a test with the current LaLa engine and writes the run down.
  ///
  /// Never destructive: previous runs of the same test remain untouched and
  /// fully readable. Returns the id of the newly created run.
  String evaluate({
    required String testId,
    required int nowUtcUs,
    String? triggeredByUserId,
    String? runId,
    String? expertLt1MethodId,
    String? expertLt2MethodId,
  }) {
    final head = _testHead(testId);
    if (triggeredByUserId != null) {
      platform.assertCanRecordDiagnosticsFor(
        userId: triggeredByUserId,
        athleteId: head.athleteId,
      );
    }

    final data = loadTestData(testId);
    final outcome = calculator.evaluate(
      data: data,
      // Deterministic: derived from the caller's clock reading, never from
      // `DateTime.now()` inside the mapping, so a run is reproducible.
      generatedAt: DateTime.fromMicrosecondsSinceEpoch(nowUtcUs, isUtc: true),
      expertLt1MethodId: expertLt1MethodId,
      expertLt2MethodId: expertLt2MethodId,
    );

    final index = _nextRunIndex(testId);
    final identifier = runId ?? '$testId-run-$index';

    return database.transaction(() {
      _insertRun(
        id: identifier,
        head: head,
        runIndex: index,
        outcome: outcome,
        nowUtcUs: nowUtcUs,
        expertLt1MethodId: expertLt1MethodId,
        expertLt2MethodId: expertLt2MethodId,
        triggeredByUserId: triggeredByUserId,
      );
      _insertThresholds(
        runId: identifier,
        head: head,
        outcome: outcome,
        nowUtcUs: nowUtcUs,
      );
      _insertZoneSets(
        runId: identifier,
        head: head,
        outcome: outcome,
        nowUtcUs: nowUtcUs,
      );

      platform.writeAudit(
        organizationId: head.organizationId,
        actorUserId: triggeredByUserId,
        action: 'evaluate_lactate_test',
        entity: 'lala_calculation_run',
        entityId: identifier,
        nowUtcUs: nowUtcUs,
        detail: jsonEncode(<String, Object?>{
          'testId': testId,
          'runIndex': index,
          'engineVersion': outcome.engineVersion,
          'lt1MethodId': outcome.selectedLt1MethodId,
          'lt2MethodId': outcome.selectedLt2MethodId,
          'inputFingerprint': outcome.inputFingerprint,
          'outputFingerprint': outcome.outputFingerprint,
        }),
      );
      return identifier;
    });
  }

  /// All runs of a test, oldest first. History, not a current value.
  List<CalculationRunRecord> runsOfTest(String testId) => database.raw
      .select(
        '''SELECT id, run_index, lala_engine_version, engine_source_commit,
                  created_at_utc_us, selected_lt1_method_id,
                  selected_lt2_method_id, expert_lt1_method_id,
                  expert_lt2_method_id, input_fingerprint, output_fingerprint,
                  core_input_hash, stage_count, triggered_by_user_id
             FROM lala_calculation_run WHERE test_id = ?
            ORDER BY run_index''',
        [testId],
      )
      .map(
        (row) => CalculationRunRecord(
          id: row['id'] as String,
          testId: testId,
          runIndex: row['run_index'] as int,
          engineVersion: row['lala_engine_version'] as String,
          engineSourceCommit: row['engine_source_commit'] as String,
          createdAtUtcUs: row['created_at_utc_us'] as int,
          selectedLt1MethodId: row['selected_lt1_method_id'] as String?,
          selectedLt2MethodId: row['selected_lt2_method_id'] as String?,
          expertLt1MethodId: row['expert_lt1_method_id'] as String?,
          expertLt2MethodId: row['expert_lt2_method_id'] as String?,
          inputFingerprint: row['input_fingerprint'] as String,
          outputFingerprint: row['output_fingerprint'] as String,
          coreInputHash: row['core_input_hash'] as String,
          stageCount: row['stage_count'] as int,
          triggeredByUserId: row['triggered_by_user_id'] as String?,
        ),
      )
      .toList(growable: false);

  /// Most recent run, or `null` when the test was never evaluated.
  CalculationRunRecord? latestRunOfTest(String testId) {
    final runs = runsOfTest(testId);
    return runs.isEmpty ? null : runs.last;
  }

  /// Persisted threshold rows of one run, in engine order.
  List<PersistedThresholdResult> thresholdsOfRun(String runId) => database.raw
      .select(
        '''SELECT id, threshold_type, method, method_version,
                  lala_engine_version, status, load_value, load_unit, power_w,
                  heart_rate_bpm, lactate_mmol_l, is_selected_standard,
                  effective_at_utc_us, computed_at_utc_us, input_data_hash,
                  interpretation, used_stage_numbers, excluded_stage_numbers
             FROM xc_threshold_result WHERE calculation_run_id = ?
            ORDER BY archive_rowid''',
        [runId],
      )
      .map(
        (row) => PersistedThresholdResult(
          id: row['id'] as String,
          thresholdType: row['threshold_type'] as String,
          methodId: row['method'] as String,
          methodVersion: row['method_version'] as String,
          engineVersion: row['lala_engine_version'] as String,
          status: row['status'] as String,
          loadValue: (row['load_value'] as num?)?.toDouble(),
          loadUnit: row['load_unit'] as String?,
          powerWatt: (row['power_w'] as num?)?.toDouble(),
          heartRateBpm: row['heart_rate_bpm'] as int?,
          lactateMmolPerLitre: (row['lactate_mmol_l'] as num?)?.toDouble(),
          isSelectedStandard: (row['is_selected_standard'] as int) == 1,
          effectiveAtUtcUs: row['effective_at_utc_us'] as int,
          computedAtUtcUs: row['computed_at_utc_us'] as int,
          inputDataHash: row['input_data_hash'] as String?,
          interpretation: row['interpretation'] as String?,
          usedStageNumbers: _decodeIntList(row['used_stage_numbers']),
          excludedStageNumbers: _decodeIntList(row['excluded_stage_numbers']),
        ),
      )
      .toList(growable: false);

  static List<int> _decodeIntList(Object? raw) {
    if (raw is! String || raw.isEmpty) return const <int>[];
    return <int>[
      for (final value in jsonDecode(raw) as List<Object?>)
        (value as num).round(),
    ];
  }

  /// Zone sets of one run. Several models coexist; none supersedes another.
  List<PersistedZoneSet> zoneSetsOfRun(String runId) => database.raw
      .select(
        '''SELECT id, zone_model_id, zone_model_name, method_version, quality,
                  load_unit, sport_type, lala_engine_version,
                  effective_from_utc_us, created_at_utc_us
             FROM xc_training_zone_set WHERE calculation_run_id = ?
            ORDER BY archive_rowid''',
        [runId],
      )
      .map(
        (row) => PersistedZoneSet(
          id: row['id'] as String,
          modelId: row['zone_model_id'] as String,
          modelName: row['zone_model_name'] as String,
          modelVersion: row['method_version'] as String,
          quality: row['quality'] as String,
          loadUnit: row['load_unit'] as String,
          sportType: row['sport_type'] as String,
          engineVersion: row['lala_engine_version'] as String,
          effectiveFromUtcUs: row['effective_from_utc_us'] as int,
          createdAtUtcUs: row['created_at_utc_us'] as int,
          zoneCount:
              database.raw.select(
                    'SELECT COUNT(*) AS n FROM training_zone WHERE zone_set_id = ?',
                    [row['id']],
                  ).first['n']
                  as int,
        ),
      )
      .toList(growable: false);

  /// The individual zones of one set, in engine order.
  ///
  /// Exact and display bounds are returned side by side. The UI shows the
  /// display value; the exact value stays available so a later reader can
  /// verify that the rounding did not invent the boundary.
  List<PersistedTrainingZone> zonesOfSet(String zoneSetId) => database.raw
      .select(
        '''SELECT id, ordinal, name, code, physiological_domain,
                  lower_load_exact, upper_load_exact, lower_load_display,
                  upper_load_display, lower_heart_rate_exact,
                  upper_heart_rate_exact, lower_heart_rate_display,
                  upper_heart_rate_display, lower_pace_seconds,
                  upper_pace_seconds, provisional_boundary, boundary_rationale,
                  unit
             FROM training_zone WHERE zone_set_id = ? ORDER BY ordinal''',
        [zoneSetId],
      )
      .map(
        (row) => PersistedTrainingZone(
          id: row['id'] as String,
          ordinal: row['ordinal'] as int,
          name: row['name'] as String,
          code: row['code'] as String?,
          physiologicalDomain: row['physiological_domain'] as String?,
          loadUnit: row['unit'] as String,
          lowerLoadExact: (row['lower_load_exact'] as num?)?.toDouble(),
          upperLoadExact: (row['upper_load_exact'] as num?)?.toDouble(),
          lowerLoadDisplay: (row['lower_load_display'] as num?)?.toDouble(),
          upperLoadDisplay: (row['upper_load_display'] as num?)?.toDouble(),
          lowerHeartRateExact: (row['lower_heart_rate_exact'] as num?)
              ?.toDouble(),
          upperHeartRateExact: (row['upper_heart_rate_exact'] as num?)
              ?.toDouble(),
          lowerHeartRateDisplay: row['lower_heart_rate_display'] as int?,
          upperHeartRateDisplay: row['upper_heart_rate_display'] as int?,
          lowerPaceSeconds: row['lower_pace_seconds'] as int?,
          upperPaceSeconds: row['upper_pace_seconds'] as int?,
          provisionalBoundary: (row['provisional_boundary'] as int) == 1,
          boundaryRationale: row['boundary_rationale'] as String?,
        ),
      )
      .toList(growable: false);

  /// Quality issues the engine attached to a zone set, as persisted.
  ///
  /// Read back from `issues_json` rather than recomputed: what the UI warns
  /// about must be what the engine actually said at evaluation time.
  List<PersistedZoneIssue> issuesOfZoneSet(String zoneSetId) {
    final rows = database.raw.select(
      'SELECT issues_json FROM xc_training_zone_set WHERE id = ?',
      [zoneSetId],
    );
    if (rows.isEmpty) return const <PersistedZoneIssue>[];
    final raw = rows.first['issues_json'] as String?;
    if (raw == null || raw.isEmpty) return const <PersistedZoneIssue>[];
    return <PersistedZoneIssue>[
      for (final entry in jsonDecode(raw) as List<Object?>)
        PersistedZoneIssue(
          severity: (entry as Map<String, Object?>)['severity'] as String,
          message: entry['message'] as String,
          consequence: entry['consequence'] as String?,
        ),
    ];
  }

  // -------------------------------------------------------------- internals

  void _insertRun({
    required String id,
    required PerformanceTestHead head,
    required int runIndex,
    required LalaCalculationOutcome outcome,
    required int nowUtcUs,
    String? expertLt1MethodId,
    String? expertLt2MethodId,
    String? triggeredByUserId,
  }) {
    database.raw.execute(
      '''INSERT INTO lala_calculation_run(
           id, organization_id, test_id, athlete_id, triggered_by_user_id,
           run_index, lala_engine_version, engine_source_commit,
           created_at_utc_us, selected_lt1_method_id, selected_lt2_method_id,
           expert_lt1_method_id, expert_lt2_method_id,
           input_fingerprint, output_fingerprint, core_input_hash, stage_count,
           sport, load_unit, audit_record_json)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        head.organizationId,
        head.id,
        head.athleteId,
        triggeredByUserId,
        runIndex,
        outcome.engineVersion,
        outcome.engineSourceCommit,
        nowUtcUs,
        outcome.selectedLt1MethodId,
        outcome.selectedLt2MethodId,
        expertLt1MethodId,
        expertLt2MethodId,
        outcome.inputFingerprint,
        outcome.outputFingerprint,
        outcome.coreInputHash,
        outcome.stageCount,
        outcome.sport,
        outcome.loadUnit,
        _encodeAuditRecord(outcome),
      ],
    );
    platform.enqueueSync(
      organizationId: head.organizationId,
      entity: 'lala_calculation_run',
      entityId: id,
      operation: 'insert',
      nowUtcUs: nowUtcUs,
    );
  }

  void _insertThresholds({
    required String runId,
    required PerformanceTestHead head,
    required LalaCalculationOutcome outcome,
    required int nowUtcUs,
  }) {
    var ordinal = 0;
    for (final result in outcome.thresholds) {
      final id = '$runId-th-${ordinal++}';
      final isPower = LoadUnits.isPower(outcome.loadUnit);
      final isSelected =
          result.methodId == outcome.selectedLt1MethodId ||
          result.methodId == outcome.selectedLt2MethodId;

      database.raw.execute(
        '''INSERT INTO threshold_result(
             id, athlete_id, test_id, calculation_run_id, organization_id,
             threshold_type, method, method_version, lala_engine_version,
             status, load_value, load_unit, power_w, heart_rate_bpm,
             lactate_mmol_l, is_selected_standard, interpretation,
             used_stage_numbers, excluded_stage_numbers, method_details_json,
             input_data_hash, effective_at_utc_us, computed_at_utc_us)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          id,
          head.athleteId,
          head.id,
          runId,
          head.organizationId,
          result.thresholdType.name,
          result.methodId,
          result.algorithmVersion,
          outcome.engineVersion,
          result.status.name,
          result.thresholdLoad,
          outcome.loadUnit,
          // The legacy watt column is filled only when the unit really is
          // watt. A speed in a column named `power_w` would be a lie that
          // survives longer than anyone's memory of it.
          isPower ? result.thresholdLoad : null,
          result.interpolatedHeartRate?.round(),
          result.interpolatedLactate,
          isSelected ? 1 : 0,
          result.interpretation,
          jsonEncode(result.usedStageNumbers),
          jsonEncode(result.excludedStageNumbers),
          jsonEncode(_plain(result.methodDetails)),
          result.inputDataHash,
          // Effective at test time, computed at run time. Both are needed:
          // history is ordered by the former, provenance by the latter.
          head.startedAtUtcUs,
          nowUtcUs,
        ],
      );
    }
    platform.enqueueSync(
      organizationId: head.organizationId,
      entity: 'threshold_result',
      entityId: runId,
      operation: 'insert',
      nowUtcUs: nowUtcUs,
    );
  }

  void _insertZoneSets({
    required String runId,
    required PerformanceTestHead head,
    required LalaCalculationOutcome outcome,
    required int nowUtcUs,
  }) {
    final basis = LoadUnits.isPower(outcome.loadUnit) ? 'power' : 'speed';
    var setOrdinal = 0;
    for (final set in outcome.zoneSets) {
      final setId = '$runId-zs-${setOrdinal++}';
      database.raw.execute(
        '''INSERT INTO training_zone_set(
             id, athlete_id, organization_id, calculation_run_id, basis,
             method, method_version, zone_model_id, zone_model_name,
             lala_engine_version, quality, load_unit, sport_type, issues_json,
             derived_from_test_id, effective_from_utc_us, created_at_utc_us)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          setId,
          head.athleteId,
          head.organizationId,
          runId,
          basis,
          set.modelId,
          set.modelVersion,
          set.modelId,
          set.modelName,
          outcome.engineVersion,
          set.quality.name,
          set.loadUnit,
          set.sportType,
          jsonEncode(<Object?>[
            for (final issue in set.issues)
              <String, Object?>{
                'severity': issue.severity.name,
                'message': issue.message,
                'consequence': issue.consequence,
              },
          ]),
          head.id,
          head.startedAtUtcUs,
          nowUtcUs,
        ],
      );

      var zoneOrdinal = 0;
      for (final zone in set.zones) {
        database.raw.execute(
          '''INSERT INTO training_zone(
               id, zone_set_id, ordinal, name, code, physiological_domain,
               lower_bound, upper_bound, unit, lower_load_exact,
               upper_load_exact, lower_load_display, upper_load_display,
               lower_heart_rate_exact, upper_heart_rate_exact,
               lower_heart_rate_display, upper_heart_rate_display,
               lower_pace_seconds, upper_pace_seconds, provisional_boundary,
               boundary_rationale)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            '$setId-z-$zoneOrdinal',
            setId,
            zoneOrdinal,
            zone.displayName,
            zone.code,
            zone.physiologicalDomain.name,
            zone.lowerLoadDisplay,
            zone.upperLoadDisplay,
            set.loadUnit,
            zone.lowerLoadExact,
            zone.upperLoadExact,
            zone.lowerLoadDisplay,
            zone.upperLoadDisplay,
            zone.lowerHeartRateExact,
            zone.upperHeartRateExact,
            zone.lowerHeartRateDisplay,
            zone.upperHeartRateDisplay,
            zone.lowerPaceSeconds,
            zone.upperPaceSeconds,
            zone.provisionalBoundary ? 1 : 0,
            zone.boundaryRationale,
          ],
        );
        zoneOrdinal++;
      }

      platform.enqueueSync(
        organizationId: head.organizationId,
        entity: 'training_zone_set',
        entityId: setId,
        operation: 'insert',
        nowUtcUs: nowUtcUs,
      );
    }
  }

  String _encodeAuditRecord(LalaCalculationOutcome outcome) {
    final record = outcome.analysis.auditRecord;
    return jsonEncode(<String, Object?>{
      'testId': record.testId,
      'inputHash': record.inputHash,
      'methodIds': record.methodIds,
      'algorithmVersions': <Object?>[
        for (final version in record.algorithmVersions)
          <String, Object?>{
            'methodId': version.methodId,
            'semanticVersion': version.semanticVersion,
          },
      ],
      'includedStageNumbers': record.includedStageNumbers,
      'excludedStageNumbers': record.excludedStageNumbers,
      'validationErrors': record.validationErrors,
      'validationWarnings': record.validationWarnings,
      'qualityMessages': record.qualityMessages,
      'resultSummary': _plain(record.resultSummary),
    });
  }

  int _nextRunIndex(String testId) {
    final rows = database.raw.select(
      'SELECT COALESCE(MAX(run_index), 0) AS n FROM lala_calculation_run WHERE test_id = ?',
      [testId],
    );
    return (rows.first['n'] as int) + 1;
  }

  PerformanceTestHead _testHead(String testId) {
    final rows = database.raw.select(
      '''SELECT id, organization_id, athlete_id, device_id, session_id, sport,
                modality, protocol, protocol_version, load_unit,
                measurement_source, status, stage_increment_hint,
                started_at_utc_us, ended_at_utc_us, created_by_user_id, notes,
                load_semantics, stage_aggregation
           FROM xc_performance_test WHERE id = ?''',
      [testId],
    );
    if (rows.isEmpty) throw StateError('Unknown performance test $testId');
    final row = rows.first;
    return PerformanceTestHead(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      athleteId: row['athlete_id'] as String,
      deviceId: row['device_id'] as String?,
      sessionId: row['session_id'] as String?,
      sport: row['sport'] as String,
      modality: row['modality'] as String,
      protocol: row['protocol'] as String,
      protocolVersion: row['protocol_version'] as String,
      loadUnit: row['load_unit'] as String,
      measurementSource: MeasurementSource.values.byName(
        row['measurement_source'] as String,
      ),
      status: PerformanceTestStatus.values.byName(row['status'] as String),
      stageIncrementHint: (row['stage_increment_hint'] as num?)?.toDouble(),
      startedAtUtcUs: row['started_at_utc_us'] as int,
      endedAtUtcUs: row['ended_at_utc_us'] as int?,
      createdByUserId: row['created_by_user_id'] as String?,
      notes: row['notes'] as String?,
      loadSemantics: row['load_semantics'] as String,
      stageAggregation: row['stage_aggregation'] as String?,
    );
  }

  void _assertAthleteInOrganization(String athleteId, String organizationId) {
    if (platform.organizationOfAthlete(athleteId) != organizationId) {
      throw const PlatformAccessException(
        'The athlete does not belong to the recording organization.',
      );
    }
  }

  void _assertDeviceInOrganization(String deviceId, String organizationId) {
    final rows = database.raw.select(
      'SELECT organization_id FROM device WHERE id = ?',
      [deviceId],
    );
    if (rows.isEmpty) throw StateError('Unknown device $deviceId');
    if (rows.first['organization_id'] != organizationId) {
      throw const PlatformAccessException(
        'The device belongs to a different organization.',
      );
    }
  }

  /// Converts engine detail maps into JSON-safe structures without changing
  /// any numeric value.
  static Object? _plain(Object? value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries) '${entry.key}': _plain(entry.value),
      };
    }
    if (value is Iterable) {
      return <Object?>[for (final item in value) _plain(item)];
    }
    return value.toString();
  }
}

// ------------------------------------------------------------------ records

class PerformanceTestHead {
  const PerformanceTestHead({
    required this.id,
    required this.organizationId,
    required this.athleteId,
    required this.sport,
    required this.modality,
    required this.protocol,
    required this.protocolVersion,
    required this.loadUnit,
    required this.measurementSource,
    required this.status,
    required this.startedAtUtcUs,
    this.deviceId,
    this.sessionId,
    this.stageIncrementHint,
    this.endedAtUtcUs,
    this.createdByUserId,
    this.notes,
    this.loadSemantics = 'load.protocol_target',
    this.stageAggregation,
  });

  final String id;
  final String organizationId;
  final String athleteId;

  /// Null for every test performed without Ercolina.
  final String? deviceId;

  final String? sessionId;
  final String sport;
  final String modality;
  final String protocol;
  final String protocolVersion;
  final String loadUnit;
  final MeasurementSource measurementSource;
  final PerformanceTestStatus status;
  final double? stageIncrementHint;
  final int startedAtUtcUs;
  final int? endedAtUtcUs;
  final String? createdByUserId;
  final String? notes;

  /// What the load axis of this test means — the prescribed load, the measured
  /// mean, or the measured end phase. Two tests may only be compared
  /// numerically when this agrees, so it is a property of the test and not
  /// something a reader may assume.
  final String loadSemantics;

  /// Identifier of the rule that turned raw device samples into step values.
  /// Null for a test that was entered by hand.
  final String? stageAggregation;
}

/// What the radio link did during a test.
class TestConnectivityEvent {
  const TestConnectivityEvent({
    required this.id,
    required this.occurredAtUtcUs,
    required this.state,
    this.stageId,
    this.deviceId,
    this.detail,
  });

  final String id;
  final String? stageId;
  final String? deviceId;
  final int occurredAtUtcUs;
  final String state;
  final String? detail;
}

class CalculationRunRecord {
  const CalculationRunRecord({
    required this.id,
    required this.testId,
    required this.runIndex,
    required this.engineVersion,
    required this.engineSourceCommit,
    required this.createdAtUtcUs,
    required this.inputFingerprint,
    required this.outputFingerprint,
    required this.coreInputHash,
    required this.stageCount,
    this.selectedLt1MethodId,
    this.selectedLt2MethodId,
    this.expertLt1MethodId,
    this.expertLt2MethodId,
    this.triggeredByUserId,
  });

  final String id;
  final String testId;

  /// 1-based, strictly increasing per test. Run 1 is never rewritten.
  final int runIndex;

  final String engineVersion;
  final String engineSourceCommit;
  final int createdAtUtcUs;
  final String? selectedLt1MethodId;
  final String? selectedLt2MethodId;
  final String? expertLt1MethodId;
  final String? expertLt2MethodId;
  final String inputFingerprint;
  final String outputFingerprint;
  final String coreInputHash;
  final int stageCount;
  final String? triggeredByUserId;
}

class PersistedThresholdResult {
  const PersistedThresholdResult({
    required this.id,
    required this.thresholdType,
    required this.methodId,
    required this.methodVersion,
    required this.engineVersion,
    required this.status,
    required this.isSelectedStandard,
    required this.effectiveAtUtcUs,
    required this.computedAtUtcUs,
    this.loadValue,
    this.loadUnit,
    this.powerWatt,
    this.heartRateBpm,
    this.lactateMmolPerLitre,
    this.inputDataHash,
    this.interpretation,
    this.usedStageNumbers = const <int>[],
    this.excludedStageNumbers = const <int>[],
  });

  final String id;
  final String thresholdType;
  final String methodId;
  final String methodVersion;
  final String engineVersion;
  final String status;
  final double? loadValue;
  final String? loadUnit;
  final double? powerWatt;
  final int? heartRateBpm;
  final double? lactateMmolPerLitre;
  final bool isSelectedStandard;
  final int effectiveAtUtcUs;
  final int computedAtUtcUs;
  final String? inputDataHash;

  /// The engine's own wording. Never replaced by a UI-authored sentence.
  final String? interpretation;

  final List<int> usedStageNumbers;
  final List<int> excludedStageNumbers;

  /// A result that actually produced a threshold value.
  bool get hasValue => loadValue != null;
}

class PersistedZoneSet {
  const PersistedZoneSet({
    required this.id,
    required this.modelId,
    required this.modelName,
    required this.modelVersion,
    required this.quality,
    required this.loadUnit,
    required this.sportType,
    required this.engineVersion,
    required this.effectiveFromUtcUs,
    required this.createdAtUtcUs,
    required this.zoneCount,
  });

  final String id;
  final String modelId;
  final String modelName;
  final String modelVersion;
  final String quality;
  final String loadUnit;
  final String sportType;
  final String engineVersion;
  final int effectiveFromUtcUs;
  final int createdAtUtcUs;
  final int zoneCount;
}

/// One persisted training zone.
///
/// Exact and display bounds are separate fields on purpose. The rounded value
/// is for the athlete, the exact one for reproducibility; collapsing them
/// would make a later verification impossible.
class PersistedTrainingZone {
  const PersistedTrainingZone({
    required this.id,
    required this.ordinal,
    required this.name,
    required this.loadUnit,
    required this.provisionalBoundary,
    this.code,
    this.physiologicalDomain,
    this.lowerLoadExact,
    this.upperLoadExact,
    this.lowerLoadDisplay,
    this.upperLoadDisplay,
    this.lowerHeartRateExact,
    this.upperHeartRateExact,
    this.lowerHeartRateDisplay,
    this.upperHeartRateDisplay,
    this.lowerPaceSeconds,
    this.upperPaceSeconds,
    this.boundaryRationale,
  });

  final String id;
  final int ordinal;
  final String name;
  final String? code;
  final String? physiologicalDomain;
  final String loadUnit;
  final double? lowerLoadExact;
  final double? upperLoadExact;
  final double? lowerLoadDisplay;
  final double? upperLoadDisplay;
  final double? lowerHeartRateExact;
  final double? upperHeartRateExact;
  final int? lowerHeartRateDisplay;
  final int? upperHeartRateDisplay;
  final int? lowerPaceSeconds;
  final int? upperPaceSeconds;

  /// The engine marked this boundary as not fully supported by the data.
  final bool provisionalBoundary;

  final String? boundaryRationale;
}

/// A quality remark the engine attached to a zone set.
class PersistedZoneIssue {
  const PersistedZoneIssue({
    required this.severity,
    required this.message,
    this.consequence,
  });

  final String severity;
  final String message;
  final String? consequence;
}
