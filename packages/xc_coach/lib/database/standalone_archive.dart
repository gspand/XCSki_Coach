import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'legacy_training_archive.dart';
import 'schema.dart';

String _identifier(String name) => '"${name.replaceAll('"', '""')}"';

/// Builds a new training-only archive from a consistent read transaction.
/// [destination] is exclusively owned staging space, published by the caller.
/// The source is attached read-only, including any committed WAL transactions.
void copyGiuliaTrainingArchive(
  String source,
  String destination, {
  required Set<String> allowedAthletes,
}) {
  final file = File(destination);
  file.createSync(exclusive: true);
  final target = sqlite3.open(file.absolute.uri.toString(), uri: true);
  try {
    target.execute('PRAGMA temp_store = MEMORY');
    target.execute('PRAGMA trusted_schema = OFF');
    target.execute('PRAGMA foreign_keys = OFF');
    final original = File(
      source,
    ).absolute.uri.replace(queryParameters: {'mode': 'ro'});
    target.execute('ATTACH DATABASE ? AS original', [original.toString()]);
    target.execute('BEGIN');
    try {
      final version =
          target.select('PRAGMA original.user_version').single.values.first
              as int;
      if (version < 1 ||
          version > giuliaSchemaVersion ||
          target
              .select(
                "SELECT 1 FROM original.sqlite_schema WHERE type='table' AND name='normalized_session_record'",
              )
              .isEmpty) {
        throw const FormatException(
          'Dieses Trainingsarchiv hat kein unterstütztes GIULIA-Schema.',
        );
      }
      final archivedAthletes = target
          .select('SELECT id FROM original.athlete')
          .map((row) => row['id'])
          .toSet();
      if (archivedAthletes.length != allowedAthletes.length ||
          !archivedAthletes.containsAll(allowedAthletes)) {
        throw const FormatException(
          'Das Archiv muss ausschließlich die beiden privaten Athletenprofile enthalten.',
        );
      }
      // Build trusted definitions for precisely the source version. Never
      // execute a trigger, virtual table or index definition from the input.
      for (final migration in giuliaMigrations.take(version)) {
        target.execute(migration);
      }
      final secondary = target.select(
        "SELECT type,name,sql FROM main.sqlite_schema WHERE type IN ('trigger','index') AND sql IS NOT NULL",
      );
      for (final row in secondary) {
        target.execute(
          'DROP ${row['type']} main.${_identifier(row['name'] as String)}',
        );
      }

      const tables =
          "sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name";
      final expected = target
          .select('SELECT name FROM main.$tables')
          .map((r) => r['name'] as String)
          .toList();
      final actual = target
          .select('SELECT name FROM original.$tables')
          .map((r) => r['name'] as String)
          .toList();
      if (expected.join('|') != actual.join('|')) {
        throw const FormatException(
          'Abweichende Archivtabellen; zur verlustfreien Übernahme ist eine Schemaanpassung erforderlich.',
        );
      }
      for (final name in expected) {
        final table = _identifier(name);
        List<String> columns(String db) => target
            .select('PRAGMA $db.table_info($table)')
            .map((r) => r['name'] as String)
            .toList();
        final cols = columns('main');
        final sourceCols = columns('original');
        if (sourceCols.length != cols.length ||
            !sourceCols.toSet().containsAll(cols)) {
          throw FormatException('Abweichende Spalten in $name.');
        }
        // Remove rows inserted by the trusted schema's bootstrap migrations.
        target.execute('DELETE FROM main.$table');
        // Foreign jobs have no XC authority.
        if (name == 'sync_outbox') {
          continue;
        }
        var predicate = '';
        if (name == 'app_state') {
          // Import only reviewed local settings. Other app namespaces can
          // contain installation credentials, shared device keys or profile PINs.
          predicate = """WHERE
            (key='app.language' AND value IN ('de','en','it','fr'))
            OR (key='repair.lactate_scout.v14' AND value='done')
            OR (key='training.active_athlete' AND value IN (SELECT id FROM original.athlete))
            OR (key IN (SELECT 'profile.'||id||'.reference_w' FROM original.athlete)
                AND value != '' AND value NOT GLOB '*[^0-9]*' AND length(value)<=4)
          """;
        }
        String projection(String col) {
          if (name == 'strava_sync_state') {
            if (const {
              'api_base_url',
              'session_id',
              'session_secret',
              'access_token',
              'refresh_token',
            }.contains(col)) {
              return "''";
            }
            if (col == 'last_error') return 'NULL';
          }
          return _identifier(col);
        }

        target.execute(
          'INSERT INTO main.$table (${cols.map(_identifier).join(',')}) '
          'SELECT ${cols.map(projection).join(',')} FROM original.$table $predicate',
        );
      }
      copyLegacyTrainingSettings(target, allowedAthletes);
      for (final row in secondary) {
        target.execute(row['sql'] as String);
      }
      // Preserve AUTOINCREMENT high-water marks, including intervening deletes.
      if (target
          .select(
            "SELECT 1 FROM original.sqlite_schema WHERE name='sqlite_sequence'",
          )
          .isNotEmpty) {
        target.execute('DELETE FROM main.sqlite_sequence');
        target.execute(
          'INSERT INTO main.sqlite_sequence(name,seq) SELECT name,seq FROM original.sqlite_sequence '
          'WHERE name IN (SELECT name FROM main.sqlite_schema WHERE type=\'table\')',
        );
      }
      target.execute('PRAGMA main.user_version = $version');
      if (target.select('PRAGMA main.foreign_key_check').isNotEmpty) {
        throw const FormatException(
          'Das Trainingsarchiv enthält ungültige Verweise.',
        );
      }
      target.execute('COMMIT');
    } catch (_) {
      target.execute('ROLLBACK');
      rethrow;
    }
  } finally {
    target.dispose();
  }
}
