import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../domain/normalized_session_stream_analysis.dart';
import 'schema.dart';

/// Single owner of the local SQLite connection.
///
/// Migrations are applied by `PRAGMA user_version`, so an existing training
/// archive is upgraded in place instead of being recreated. Every repository
/// shares this connection to keep cross-entity writes transactional.
class GiuliaDatabase {
  GiuliaDatabase.open(String path) : raw = sqlite3.open(path) {
    _prepare();
  }

  GiuliaDatabase.inMemory() : raw = sqlite3.openInMemory() {
    _prepare();
  }

  /// Read an existing archive without migrations or write-side preparation.
  GiuliaDatabase.readOnly(String path)
    : raw = sqlite3.open(path, mode: OpenMode.readOnly) {
    _createEligibleViews();
  }

  /// Bounded pages for exports. The caller supplies a stable ORDER BY and
  /// exports a completed session, so concurrent recording cannot reorder it.
  Iterable<Map<String, Object?>> readPages(
    String query,
    List<Object?> parameters,
  ) sync* {
    const pageSize = 256;
    for (var offset = 0; ; offset += pageSize) {
      final rows = raw.select('$query LIMIT ? OFFSET ?', [
        ...parameters,
        pageSize,
        offset,
      ]);
      yield* rows;
      if (rows.length < pageSize) return;
    }
  }

  final Database raw;
  bool _closed = false;
  int _transactionDepth = 0;

  int get version =>
      raw.select('PRAGMA user_version').first.values.first! as int;

  void _prepare() {
    raw.execute('PRAGMA foreign_keys = ON');
    raw.execute('PRAGMA busy_timeout = 5000');
    // WAL keeps readers (reports/UI) from blocking the high-frequency writer.
    // FULL means a committed checkpoint survives an operating-system crash;
    // NORMAL would trade that promise for throughput, which is the wrong
    // trade-off for irreplaceable measurement data.
    raw.select('PRAGMA journal_mode = WAL');
    raw.execute('PRAGMA synchronous = FULL');
    // Athlete deletion is not implemented yet, but when it is, SQLite should
    // not leave deleted personal data in reusable pages.
    raw.execute('PRAGMA secure_delete = ON');
    _migrate();
    _createEligibleViews();
    _backfillNormalizedSessionAnalysis();
  }

  // Connection-local read models also work on immutable archives. Keep the
  // original provider rows intact for export and provenance auditing.
  void _createEligibleViews() {
    raw.execute('''
      CREATE TEMP VIEW xc_restricted_session AS
        SELECT session_id FROM main.external_activity_import e
        WHERE lower(trim(provider_id)) = 'strava' OR (source_id GLOB 'fit:*' AND NOT EXISTS (
          SELECT 1 FROM main.app_state a WHERE a.key = 'xc.fitOrigin.' || e.athlete_id || '.' || e.source_id
            AND a.value IN ('recordingDevice','garminConnect')))
        UNION
        SELECT session_id FROM main.canonical_activity_source WHERE lower(trim(provider_id)) = 'strava';
      CREATE TEMP VIEW xc_session AS
        SELECT * FROM main.session WHERE id NOT IN (SELECT session_id FROM xc_restricted_session);
      CREATE TEMP VIEW xc_canonical_source AS
        SELECT source.*, row_number() OVER (
          PARTITION BY canonical_activity_id
          ORDER BY (source.session_id = c.preferred_session_id) DESC,
                   source.authority_rank DESC, source.linked_at_utc_us, source.session_id
        ) AS preference
        FROM main.canonical_activity_source source
        JOIN main.canonical_activity c ON c.id = source.canonical_activity_id
        WHERE source.session_id NOT IN (SELECT session_id FROM xc_restricted_session);
      CREATE TEMP VIEW xc_restricted_test AS
        SELECT test_id AS id FROM main.external_measurement_import WHERE lower(trim(provider_id)) = 'strava'
        UNION
        SELECT id FROM main.performance_test WHERE session_id IN (SELECT session_id FROM xc_restricted_session)
          OR notes LIKE '%Belastung und Herzfrequenz aus strava, Aktivität %'
          OR notes LIKE 'Importiert aus strava.%'
          OR (notes LIKE '%Belastung und Herzfrequenz aus garmin, Aktivität fit:%'
              AND notes NOT LIKE '%Direkte FIT-Quelle: recordingDevice.%'
              AND notes NOT LIKE '%Direkte FIT-Quelle: garminConnect.%');
      CREATE TEMP VIEW xc_performance_test AS
        SELECT * FROM main.performance_test WHERE id NOT IN (SELECT id FROM xc_restricted_test);
      CREATE TEMP VIEW xc_observation AS
        SELECT * FROM main.observation WHERE lower(trim(source)) <> 'strava' AND
          (session_id IS NULL OR session_id NOT IN (SELECT session_id FROM xc_restricted_session)) AND
          (test_id IS NULL OR test_id NOT IN (SELECT id FROM xc_restricted_test));
      CREATE TEMP VIEW xc_personal_record AS
        SELECT rowid AS archive_rowid, * FROM main.personal_record WHERE (session_id IS NULL OR session_id NOT IN (SELECT session_id FROM xc_restricted_session)) AND
          (test_id IS NULL OR test_id NOT IN (SELECT id FROM xc_restricted_test));
      CREATE TEMP VIEW xc_coach_note AS
        SELECT rowid AS archive_rowid, * FROM main.coach_note WHERE (session_id IS NULL OR session_id NOT IN (SELECT session_id FROM xc_restricted_session)) AND
          (test_id IS NULL OR test_id NOT IN (SELECT id FROM xc_restricted_test));
      CREATE TEMP VIEW xc_athlete_metric AS
        SELECT rowid AS archive_rowid, * FROM main.athlete_metric WHERE (session_id IS NULL OR session_id NOT IN (SELECT session_id FROM xc_restricted_session)) AND
          (test_id IS NULL OR test_id NOT IN (SELECT id FROM xc_restricted_test));
      CREATE TEMP VIEW xc_threshold_result AS
        SELECT rowid AS archive_rowid, * FROM main.threshold_result WHERE (test_id IS NULL OR test_id NOT IN (SELECT id FROM xc_restricted_test));
      CREATE TEMP VIEW xc_training_zone_set AS
        SELECT rowid AS archive_rowid, * FROM main.training_zone_set WHERE (derived_from_test_id IS NULL OR derived_from_test_id NOT IN (SELECT id FROM xc_restricted_test)) AND
          (calculation_run_id IS NULL OR calculation_run_id NOT IN (SELECT id FROM main.lala_calculation_run WHERE test_id IN (SELECT id FROM xc_restricted_test)));
      CREATE TEMP VIEW xc_restricted_decision AS
        SELECT id FROM main.coach_decision d WHERE
          (decided_by = 'giulia' AND id NOT GLOB 'xc-origin-v1-*') OR
          EXISTS (SELECT 1 FROM json_each(d.facts_json) fact
            WHERE (json_extract(fact.value, '\$.kind') = 'session' AND
                    (json_extract(fact.value, '\$.id') IN (SELECT session_id FROM xc_restricted_session)
                     OR json_extract(fact.value, '\$.id') IN (SELECT id FROM main.normalized_session_record WHERE source='strava')))
              OR (json_extract(fact.value, '\$.kind') = 'test' AND
                     json_extract(fact.value, '\$.id') IN (SELECT id FROM xc_restricted_test)));
      CREATE TEMP VIEW xc_planned_workout AS
        SELECT * FROM main.planned_workout p WHERE
          (session_id IS NULL OR session_id NOT IN (SELECT session_id FROM xc_restricted_session)) AND
          id NOT IN (SELECT w.value FROM main.coach_decision d, json_each(d.planned_workout_ids_json) w
                       WHERE d.id IN (SELECT id FROM xc_restricted_decision));
      CREATE TEMP VIEW xc_normalized_session AS
        SELECT rowid AS archive_rowid, * FROM main.normalized_session_record n
        WHERE source IN ('manual', 'garmin', 'ercolina') AND id NOT GLOB 'strava_*' AND
          json_extract(COALESCE(analysis_json, data_json), '\$.source') = source AND
          json_extract(COALESCE(analysis_json, data_json), '\$.rawMetadata.originalProvider') IS NOT 'strava' AND
          json_type(COALESCE(analysis_json, data_json), '\$.rawMetadata.sufferScore') IS NULL AND
          (source <> 'ercolina' OR source_id NOT IN (SELECT session_id FROM xc_restricted_session)) AND
          (source_id NOT GLOB 'fit:*' OR EXISTS (
             SELECT 1 FROM main.app_state a WHERE a.key = 'xc.fitOrigin.' || n.athlete_id || '.' || n.source_id
               AND a.value IN ('recordingDevice','garminConnect')));
    ''');
  }

  /// Builds the compact analysis projection once for existing archives.
  ///
  /// Eligible rows are read in small batches so a large multi-year archive does
  /// not exist twice in memory. The source JSON is never changed or deleted.
  void _backfillNormalizedSessionAnalysis() {
    if (version < 26) return;
    final pending = raw.select(
      'SELECT 1 FROM xc_normalized_session '
      'WHERE analysis_json IS NULL LIMIT 1',
    );
    if (pending.isEmpty) return;

    raw.execute('BEGIN IMMEDIATE');
    try {
      var lastRowId = 0;
      while (true) {
        final rows = raw.select(
          '''SELECT archive_rowid AS rowid, id, moving_time_seconds,
                    json_remove(data_json, '\$.rawMetadata.streams')
                      AS compact_json,
                    json_extract(data_json, '\$.rawMetadata.streams.time')
                      AS time_json,
                    json_extract(data_json, '\$.rawMetadata.streams.heartrate')
                      AS heartrate_json,
                    json_extract(data_json, '\$.rawMetadata.streams.watts')
                      AS watts_json
               FROM xc_normalized_session
              WHERE analysis_json IS NULL AND archive_rowid > ?
              ORDER BY archive_rowid
              LIMIT 24''',
          [lastRowId],
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          lastRowId = row['rowid'] as int;
          final decoded = jsonDecode(row['compact_json'] as String);
          if (decoded is! Map<String, dynamic>) continue;
          final streams = <String, dynamic>{};
          for (final key in const ['time', 'heartrate', 'watts']) {
            final encoded = row['${key}_json'] as String?;
            if (encoded != null) streams[key] = jsonDecode(encoded);
          }
          if (streams.isNotEmpty) {
            final features = buildNormalizedStreamFeatures(
              streams,
              movingTimeSeconds: row['moving_time_seconds'] as int,
            );
            if (features.isNotEmpty) {
              final rawMetadata = decoded['rawMetadata'];
              final metadata = rawMetadata is Map
                  ? <String, dynamic>{
                      for (final entry in rawMetadata.entries)
                        entry.key.toString(): entry.value,
                    }
                  : <String, dynamic>{};
              metadata[normalizedStreamFeaturesKey] = features;
              decoded['rawMetadata'] = metadata;
            }
          }
          raw.execute(
            'UPDATE normalized_session_record SET analysis_json = ? '
            'WHERE id = ?',
            [jsonEncode(decoded), row['id']],
          );
        }
      }
      raw.execute('COMMIT');
    } catch (_) {
      raw.execute('ROLLBACK');
      rethrow;
    }
  }

  void _migrate() {
    var current = version;
    if (current > giuliaSchemaVersion) {
      throw StateError(
        'Database version $current is newer than the supported '
        'version $giuliaSchemaVersion. Refusing to downgrade training data.',
      );
    }
    while (current < giuliaSchemaVersion) {
      raw.execute('BEGIN IMMEDIATE');
      try {
        raw.execute(giuliaMigrations[current]);
        current++;
        raw.execute('PRAGMA user_version = $current');
        raw.execute('COMMIT');
      } catch (_) {
        raw.execute('ROLLBACK');
        rethrow;
      }
    }
  }

  /// Runs [action] inside one transaction so a partially written aggregate can
  /// never become visible to analysis or synchronization.
  T transaction<T>(T Function() action) {
    final depth = _transactionDepth;
    final savepoint = 'giulia_nested_$depth';
    if (depth == 0) {
      raw.execute('BEGIN IMMEDIATE');
    } else {
      raw.execute('SAVEPOINT $savepoint');
    }
    // BEGIN/SAVEPOINT can fail; only own a nesting level once it exists.
    _transactionDepth++;
    try {
      final result = action();
      if (depth == 0) {
        raw.execute('COMMIT');
      } else {
        raw.execute('RELEASE SAVEPOINT $savepoint');
      }
      return result;
    } catch (_) {
      if (depth == 0) {
        raw.execute('ROLLBACK');
      } else {
        raw.execute('ROLLBACK TO SAVEPOINT $savepoint');
        raw.execute('RELEASE SAVEPOINT $savepoint');
      }
      rethrow;
    } finally {
      _transactionDepth--;
    }
  }

  void dispose() {
    if (_closed) return;
    raw.dispose();
    _closed = true;
  }
}
