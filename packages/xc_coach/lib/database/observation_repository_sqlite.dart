/// Beobachtungen in SQLite schreiben und lesen.
library;

import '../observation/observation.dart';
import '../observation/observation_repository.dart';
import 'giulia_database.dart';

class SqliteObservationRepository implements ObservationRepository {
  const SqliteObservationRepository(this.database);

  final GiuliaDatabase database;

  @override
  void record(Observation observation) => database.raw.execute(
    '''INSERT INTO observation(
         id, athlete_id, observed_at_utc_us, type, value, text_value, unit,
         source, quality, recorded_by_user_id, time_since_load_end_s,
         occasion, sample_site, session_id, interval_record_id, test_id,
         test_stage_id)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
    [
      observation.id,
      observation.athleteId,
      observation.observedAtUtcUs,
      observation.type.name,
      observation.value,
      observation.text,
      observation.unit,
      observation.source.name,
      observation.quality.name,
      observation.recordedByUserId,
      observation.timeSinceLoadEndSeconds,
      observation.occasion,
      observation.sampleSite,
      observation.context.sessionId,
      observation.context.intervalRecordId,
      observation.context.testId,
      observation.context.testStageId,
    ],
  );

  @override
  List<Observation> ofTest(String testId) => _query('test_id = ?', [testId]);

  @override
  List<Observation> ofSession(String sessionId) =>
      _query('session_id = ?', [sessionId]);

  @override
  List<Observation> ofAthlete(
    String athleteId, {
    int? fromUtcUs,
    int? toUtcUs,
    ObservationType? type,
  }) => _query(
    'athlete_id = ? AND observed_at_utc_us >= ? AND observed_at_utc_us <= ?'
    '${type == null ? '' : ' AND type = ?'}',
    [
      athleteId,
      fromUtcUs ?? -9223372036854775808,
      toUtcUs ?? 9223372036854775807,
      if (type != null) type.name,
    ],
  );

  List<Observation> _query(String where, List<Object?> parameters) => database
      .raw
      .select(
        '''SELECT id, athlete_id, observed_at_utc_us, type, value, text_value,
                  unit, source, quality, recorded_by_user_id,
                  time_since_load_end_s, occasion, sample_site, session_id,
                  interval_record_id, test_id, test_stage_id
             FROM xc_observation
            WHERE $where
            ORDER BY observed_at_utc_us, id''',
        parameters,
      )
      .map(_fromRow)
      .toList(growable: false);

  Observation _fromRow(Map<String, Object?> row) => Observation(
    id: row['id'] as String,
    athleteId: row['athlete_id'] as String,
    observedAtUtcUs: row['observed_at_utc_us'] as int,
    type: _typeFrom(row['type'] as String),
    value: (row['value'] as num?)?.toDouble(),
    text: row['text_value'] as String?,
    unit: row['unit'] as String?,
    source: _enumFrom(
      ObservationSource.values,
      row['source'] as String?,
      ObservationSource.manual,
    ),
    quality: _enumFrom(
      ObservationQuality.values,
      row['quality'] as String?,
      ObservationQuality.recorded,
    ),
    recordedByUserId: row['recorded_by_user_id'] as String?,
    timeSinceLoadEndSeconds: row['time_since_load_end_s'] as int?,
    occasion: row['occasion'] as String?,
    sampleSite: row['sample_site'] as String?,
    context: ObservationContext(
      sessionId: row['session_id'] as String?,
      intervalRecordId: row['interval_record_id'] as String?,
      testId: row['test_id'] as String?,
      testStageId: row['test_stage_id'] as String?,
    ),
  );

  /// Ein unbekannter Typ wird zur Bemerkung: Er behält seinen Text, geht aber
  /// in keine Auswertung ein. Die vorsichtige Richtung.
  static ObservationType _typeFrom(String stored) {
    for (final type in ObservationType.values) {
      if (type.name == stored) return type;
    }
    return ObservationType.note;
  }

  static T _enumFrom<T extends Enum>(
    List<T> values,
    String? stored,
    T fallback,
  ) {
    for (final value in values) {
      if (value.name == stored) return value;
    }
    return fallback;
  }
}
