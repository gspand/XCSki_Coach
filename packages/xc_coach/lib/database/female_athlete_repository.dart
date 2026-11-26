/// SQLite-Persistenz für Female Athlete Daten:
/// - Profil & Opt-In
/// - Perioden / Blutungs-Episoden
/// - Tägliche Symptom-Check-Ins
/// - Gesundheitssignale (Health Signals)
/// - Echte Labor-Eisendaten
library;

import 'giulia_database.dart';
import '../intelligence/female_athlete/female_athlete_models.dart';

class FemaleAthleteProfileData {
  const FemaleAthleteProfileData({
    required this.athleteId,
    this.optIn = FemaleCycleTrackingOptIn.undecided,
    this.hormonalStatus = HormonalStatus.unknown,
    this.isRegularCycle,
    this.typicalCycleLengthDays,
    this.contraceptiveDetails,
    this.contraceptiveStartedAtUtcUs,
    required this.updatedAtUtcUs,
  });

  final String athleteId;
  final FemaleCycleTrackingOptIn optIn;
  final HormonalStatus hormonalStatus;
  final bool? isRegularCycle;
  final double? typicalCycleLengthDays;
  final String? contraceptiveDetails;
  final int? contraceptiveStartedAtUtcUs;
  final int updatedAtUtcUs;
}

class SqliteFemaleAthleteRepository {
  const SqliteFemaleAthleteRepository(this.database);

  final GiuliaDatabase database;

  // ==========================================
  // Profil & Opt-In
  // ==========================================

  FemaleAthleteProfileData? getProfile(String athleteId) {
    final rows = database.raw.select(
      'SELECT * FROM female_athlete_profile WHERE athlete_id = ?',
      [athleteId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return FemaleAthleteProfileData(
      athleteId: row['athlete_id'] as String,
      optIn: FemaleCycleTrackingOptIn.values.byName(
        row['opt_in'] as String? ?? 'undecided',
      ),
      hormonalStatus: HormonalStatus.values.byName(
        row['hormonal_status'] as String? ?? 'unknown',
      ),
      isRegularCycle: row['is_regular_cycle'] != null
          ? (row['is_regular_cycle'] as int) == 1
          : null,
      typicalCycleLengthDays:
          (row['typical_cycle_length_days'] as num?)?.toDouble(),
      contraceptiveDetails: row['contraceptive_details'] as String?,
      contraceptiveStartedAtUtcUs:
          row['contraceptive_started_at_utc_us'] as int?,
      updatedAtUtcUs: row['updated_at_utc_us'] as int,
    );
  }

  void saveProfile(FemaleAthleteProfileData data) {
    database.raw.execute(
      '''INSERT INTO female_athlete_profile (
           athlete_id, opt_in, hormonal_status, is_regular_cycle,
           typical_cycle_length_days, contraceptive_details,
           contraceptive_started_at_utc_us, updated_at_utc_us
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(athlete_id) DO UPDATE SET
           opt_in = excluded.opt_in,
           hormonal_status = excluded.hormonal_status,
           is_regular_cycle = excluded.is_regular_cycle,
           typical_cycle_length_days = excluded.typical_cycle_length_days,
           contraceptive_details = excluded.contraceptive_details,
           contraceptive_started_at_utc_us = excluded.contraceptive_started_at_utc_us,
           updated_at_utc_us = excluded.updated_at_utc_us''',
      [
        data.athleteId,
        data.optIn.name,
        data.hormonalStatus.name,
        data.isRegularCycle != null ? (data.isRegularCycle! ? 1 : 0) : null,
        data.typicalCycleLengthDays,
        data.contraceptiveDetails,
        data.contraceptiveStartedAtUtcUs,
        data.updatedAtUtcUs,
      ],
    );
  }

  void deleteCycleData(String athleteId) {
    database.transaction(() {
      database.raw.execute('DELETE FROM female_athlete_profile WHERE athlete_id = ?', [athleteId]);
      database.raw.execute('DELETE FROM cycle_period_record WHERE athlete_id = ?', [athleteId]);
      database.raw.execute('DELETE FROM daily_cycle_symptom_record WHERE athlete_id = ?', [athleteId]);
      database.raw.execute('DELETE FROM female_athlete_health_signal_record WHERE athlete_id = ?', [athleteId]);
      database.raw.execute('DELETE FROM iron_lab_record WHERE athlete_id = ?', [athleteId]);
    });
  }

  // ==========================================
  // Zyklus-Perioden / Blutungen
  // ==========================================

  void savePeriod(String athleteId, RecordedCyclePeriod period, {required int nowUtcUs}) {
    database.raw.execute(
      '''INSERT INTO cycle_period_record (
           id, athlete_id, start_date, end_date, average_bleeding,
           cycle_length_days, is_spotting_only, has_perceived_ovulation,
           has_objective_ovulation, provenance, created_at_utc_us
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           start_date = excluded.start_date,
           end_date = excluded.end_date,
           average_bleeding = excluded.average_bleeding,
           cycle_length_days = excluded.cycle_length_days,
           is_spotting_only = excluded.is_spotting_only,
           has_perceived_ovulation = excluded.has_perceived_ovulation,
           has_objective_ovulation = excluded.has_objective_ovulation,
           provenance = excluded.provenance''',
      [
        period.id,
        athleteId,
        period.startDate.toIso8601String().split('T').first,
        period.endDate?.toIso8601String().split('T').first,
        period.averageBleeding.name,
        period.cycleLengthDays,
        period.isSpottingOnly ? 1 : 0,
        period.hasPerceivedOvulation ? 1 : 0,
        period.hasObjectiveOvulation ? 1 : 0,
        period.provenance.name,
        nowUtcUs,
      ],
    );
  }

  List<RecordedCyclePeriod> loadPeriods(String athleteId, {int limit = 50}) {
    final rows = database.raw.select(
      '''SELECT * FROM cycle_period_record
         WHERE athlete_id = ?
         ORDER BY start_date DESC
         LIMIT ?''',
      [athleteId, limit],
    );
    return rows.map((r) => RecordedCyclePeriod(
      id: r['id'] as String,
      startDate: DateTime.parse(r['start_date'] as String),
      endDate: r['end_date'] != null ? DateTime.parse(r['end_date'] as String) : null,
      averageBleeding: BleedingIntensity.values.byName(r['average_bleeding'] as String? ?? 'medium'),
      cycleLengthDays: r['cycle_length_days'] as int?,
      isSpottingOnly: (r['is_spotting_only'] as int) == 1,
      hasPerceivedOvulation: (r['has_perceived_ovulation'] as int) == 1,
      hasObjectiveOvulation: (r['has_objective_ovulation'] as int) == 1,
      provenance: CycleDataProvenance.values.byName(r['provenance'] as String? ?? 'userReported'),
    )).toList();
  }

  // ==========================================
  // Tägliche Symptom-Reports
  // ==========================================

  void saveSymptomReport(String athleteId, DailyCycleSymptomReport report, {required int nowUtcUs}) {
    final dateStr = report.date.toIso8601String().split('T').first;
    final id = 'symptom_${athleteId}_$dateStr';
    database.raw.execute(
      '''INSERT INTO daily_cycle_symptom_record (
           id, athlete_id, date, bleeding, cramps, unusual_fatigue,
           energy_level, sleep_disturbance, mood_changes, headache,
           gi_symptoms, breast_tenderness, perceived_readiness,
           notes, recorded_at_utc_us
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(athlete_id, date) DO UPDATE SET
           bleeding = excluded.bleeding,
           cramps = excluded.cramps,
           unusual_fatigue = excluded.unusual_fatigue,
           energy_level = excluded.energy_level,
           sleep_disturbance = excluded.sleep_disturbance,
           mood_changes = excluded.mood_changes,
           headache = excluded.headache,
           gi_symptoms = excluded.gi_symptoms,
           breast_tenderness = excluded.breast_tenderness,
           perceived_readiness = excluded.perceived_readiness,
           notes = excluded.notes,
           recorded_at_utc_us = excluded.recorded_at_utc_us''',
      [
        id,
        athleteId,
        dateStr,
        report.bleeding.name,
        report.cramps.name,
        report.unusualFatigue.name,
        report.energyLevel,
        report.sleepDisturbance.name,
        report.moodChanges.name,
        report.headache.name,
        report.giSymptoms.name,
        report.breastTenderness.name,
        report.perceivedReadiness,
        report.notes,
        nowUtcUs,
      ],
    );
  }

  DailyCycleSymptomReport? getSymptomReportForDate(String athleteId, DateTime date) {
    final dateStr = date.toIso8601String().split('T').first;
    final rows = database.raw.select(
      '''SELECT * FROM daily_cycle_symptom_record
         WHERE athlete_id = ? AND date = ?''',
      [athleteId, dateStr],
    );
    if (rows.isEmpty) return null;
    return _mapSymptomRow(rows.first);
  }

  List<DailyCycleSymptomReport> loadSymptomReports(String athleteId, {int limit = 90}) {
    final rows = database.raw.select(
      '''SELECT * FROM daily_cycle_symptom_record
         WHERE athlete_id = ?
         ORDER BY date DESC
         LIMIT ?''',
      [athleteId, limit],
    );
    return rows.map(_mapSymptomRow).toList();
  }

  DailyCycleSymptomReport _mapSymptomRow(Map<String, dynamic> r) {
    return DailyCycleSymptomReport(
      date: DateTime.parse(r['date'] as String),
      bleeding: BleedingIntensity.values.byName(r['bleeding'] as String? ?? 'none'),
      cramps: SymptomSeverity.values.byName(r['cramps'] as String? ?? 'none'),
      unusualFatigue: SymptomSeverity.values.byName(r['unusual_fatigue'] as String? ?? 'none'),
      energyLevel: (r['energy_level'] as num?)?.toDouble(),
      sleepDisturbance: SymptomSeverity.values.byName(r['sleep_disturbance'] as String? ?? 'none'),
      moodChanges: SymptomSeverity.values.byName(r['mood_changes'] as String? ?? 'none'),
      headache: SymptomSeverity.values.byName(r['headache'] as String? ?? 'none'),
      giSymptoms: SymptomSeverity.values.byName(r['gi_symptoms'] as String? ?? 'none'),
      breastTenderness: SymptomSeverity.values.byName(r['breast_tenderness'] as String? ?? 'none'),
      perceivedReadiness: (r['perceived_readiness'] as num?)?.toDouble(),
      notes: r['notes'] as String?,
      recordedAtUtcUs: r['recorded_at_utc_us'] as int?,
    );
  }

  // ==========================================
  // Health Signals
  // ==========================================

  void saveHealthSignal(String athleteId, FemaleAthleteHealthSignal signal, {required int nowUtcUs}) {
    database.raw.execute(
      '''INSERT INTO female_athlete_health_signal_record (
           id, athlete_id, signal_type, title, description,
           medical_disclaimer, detected_at, recommendation_action, created_at_utc_us
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           title = excluded.title,
           description = excluded.description,
           detected_at = excluded.detected_at,
           recommendation_action = excluded.recommendation_action''',
      [
        'xc-origin-v1-$athleteId-${signal.id}',
        athleteId,
        signal.type.name,
        signal.title,
        signal.description,
        signal.medicalDisclaimer,
        signal.detectedAt.toIso8601String().split('T').first,
        signal.recommendationAction,
        nowUtcUs,
      ],
    );
  }

  List<FemaleAthleteHealthSignal> loadHealthSignals(String athleteId, {int limit = 20}) {
    final rows = database.raw.select(
      '''SELECT * FROM female_athlete_health_signal_record
         WHERE id GLOB 'xc-origin-v1-*' AND athlete_id = ?
         ORDER BY detected_at DESC
         LIMIT ?''',
      [athleteId, limit],
    );
    return rows.map((r) => FemaleAthleteHealthSignal(
      id: (r['id'] as String).substring('xc-origin-v1-$athleteId-'.length),
      type: HealthSignalType.values.byName(r['signal_type'] as String),
      title: r['title'] as String,
      description: r['description'] as String,
      medicalDisclaimer: r['medical_disclaimer'] as String,
      detectedAt: DateTime.parse(r['detected_at'] as String),
      recommendationAction: r['recommendation_action'] as String,
    )).toList();
  }

  // ==========================================
  // Labor Eisendaten
  // ==========================================

  void saveIronRecord(String athleteId, IronLabRecord record, {required int nowUtcUs}) {
    database.raw.execute(
      '''INSERT INTO iron_lab_record (
           id, athlete_id, measured_at, ferritin_ug_l, hemoglobin_g_dl,
           transferrin_sat_percent, reference_range, source, confidence,
           created_at_utc_us
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           measured_at = excluded.measured_at,
           ferritin_ug_l = excluded.ferritin_ug_l,
           hemoglobin_g_dl = excluded.hemoglobin_g_dl,
           transferrin_sat_percent = excluded.transferrin_sat_percent,
           reference_range = excluded.reference_range,
           source = excluded.source,
           confidence = excluded.confidence''',
      [
        record.id,
        athleteId,
        record.measuredAt.toIso8601String().split('T').first,
        record.ferritinUgL,
        record.hemoglobinGDl,
        record.transferrinSaturationPercent,
        record.referenceRange,
        record.source,
        record.confidence,
        nowUtcUs,
      ],
    );
  }

  List<IronLabRecord> loadIronRecords(String athleteId, {int limit = 20}) {
    final rows = database.raw.select(
      '''SELECT * FROM iron_lab_record
         WHERE lower(trim(source)) NOT LIKE 'strava%' AND athlete_id = ?
         ORDER BY measured_at DESC
         LIMIT ?''',
      [athleteId, limit],
    );
    return rows.map((r) => IronLabRecord(
      id: r['id'] as String,
      measuredAt: DateTime.parse(r['measured_at'] as String),
      ferritinUgL: (r['ferritin_ug_l'] as num?)?.toDouble(),
      hemoglobinGDl: (r['hemoglobin_g_dl'] as num?)?.toDouble(),
      transferrinSaturationPercent: (r['transferrin_sat_percent'] as num?)?.toDouble(),
      referenceRange: r['reference_range'] as String?,
      source: r['source'] as String? ?? 'Labordiagnostik',
      confidence: (r['confidence'] as num?)?.toDouble() ?? 1.0,
    )).toList();
  }
}
