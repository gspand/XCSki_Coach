import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_ski_coach/coach_store.dart';

void main() {
  test(
    'redacts private settings before publication and includes committed WAL writes',
    () {
      final temp = Directory.systemTemp.createTempSync('xc-archive-test-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final source = '${temp.path}/source.db';
      final copy = '${temp.path}/copy.db';
      initializeArchive(source, null);
      final open = GiuliaDatabase.open(source);
      addTearDown(open.dispose);
      open.raw.execute('PRAGMA wal_autocheckpoint=0');
      const sentinel = 'SYNTHETIC-ARCHIVE-CANARY';
      for (final entry in {
        'giulia.device_key.test': sentinel,
        'profiles.pin.karina-puercher': sentinel,
        'new.provider.key': sentinel,
        'xc.provider.settings': sentinel,
        'profile.own-athlete.reference_w': '197',
        'app.language': 'de',
      }.entries) {
        open.raw.execute('INSERT OR REPLACE INTO app_state VALUES (?,?,100)', [
          entry.key,
          entry.value,
        ]);
      }
      open.raw.execute(
        'INSERT INTO strava_sync_state (athlete_id, api_base_url, session_id, session_secret, access_token, refresh_token, strava_athlete_id, strava_athlete_name, last_error, updated_at_utc_us) VALUES (?,?,?,?,?,?,?,?,?,100)',
        [
          'own-athlete',
          sentinel,
          sentinel,
          sentinel,
          sentinel,
          sentinel,
          'historical-id',
          'historical-name',
          sentinel,
        ],
      );
      expect(File('$source-wal').lengthSync(), greaterThan(0));
      initializeArchive(copy, source);
      final result = GiuliaDatabase.open(copy);
      try {
        expect(
          result.raw.select(
            "SELECT COUNT(*) AS n FROM app_state WHERE value=?",
            [sentinel],
          ).single['n'],
          0,
        );
        expect(
          result.raw
              .select(
                "SELECT value FROM app_state WHERE key='profile.own-athlete.reference_w'",
              )
              .single['value'],
          '197',
        );
        expect(
          result.raw
              .select("SELECT value FROM app_state WHERE key='app.language'")
              .single['value'],
          'de',
        );
        final row = result.raw.select('SELECT * FROM strava_sync_state').single;
        for (final key in [
          'api_base_url',
          'session_id',
          'session_secret',
          'access_token',
          'refresh_token',
        ]) {
          expect(row[key], '');
        }
        expect(row['last_error'], isNull);
        expect(row['strava_athlete_name'], 'historical-name');
        expect(
          result.raw
              .select('SELECT count(*) AS n FROM sync_outbox')
              .single['n'],
          0,
        );
        expect(
          open.raw
              .select('SELECT access_token FROM strava_sync_state')
              .single['access_token'],
          sentinel,
        );
        for (final suffix in ['', '-wal', '-journal']) {
          final file = File('$copy$suffix');
          if (file.existsSync()) {
            expect(
              latin1.decode(file.readAsBytesSync()),
              isNot(contains(sentinel)),
              reason: 'Published $suffix bytes',
            );
          }
        }
        expect(() => initializeArchive(copy, source), throwsStateError);
      } finally {
        result.dispose();
      }
    },
  );

  test(
    'an unknown archive table is rejected without publishing a partial target',
    () {
      final temp = Directory.systemTemp.createTempSync('xc-archive-test-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final source = '${temp.path}/source.db';
      initializeArchive(source, null);
      final db = GiuliaDatabase.open(source);
      db.raw.execute('CREATE TABLE foreign_settings(value TEXT)');
      db.dispose();
      final target = '${temp.path}/copy.db';
      expect(() => initializeArchive(target, source), throwsFormatException);
      expect(File(target).existsSync(), isFalse);
      expect(temp.listSync().whereType<Directory>(), isEmpty);
    },
  );
  test('archive with another athlete is rejected before publication', () {
    final temp = Directory.systemTemp.createTempSync('xc-archive-test-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final source = '${temp.path}/source.db';
    initializeArchive(source, null);
    final db = GiuliaDatabase.open(source);
    CoachStore(db).platform.createAthlete(
      id: 'other-athlete',
      organizationId: organization,
      name: 'Synthetic',
      nowUtcUs: 1,
    );
    db.dispose();
    final target = '${temp.path}/copy.db';
    expect(() => initializeArchive(target, source), throwsFormatException);
    expect(File(target).existsSync(), isFalse);
  });
  test(
    'retains a private indoor session and samples without device secrets or unowned data',
    () {
      final temp = Directory.systemTemp.createTempSync('xc-archive-test-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final source = '${temp.path}/source.db';
      initializeArchive(source, null);
      final db = GiuliaDatabase.open(source);
      void put(String key, Object data) => db.raw.execute(
        'INSERT OR REPLACE INTO app_state VALUES (?,?,99)',
        [key, jsonEncode(data)],
      );
      const id = 'ride-1795092000000000';
      const shared = 'ride-1795092000000001';
      const hidden = 'HIDDEN-DEVICE-CREDENTIAL';
      final ride = {
        'id': id,
        's': '2026-11-20T12:00:00Z',
        'd': 1,
        'm': 2,
        'kj': 0.2,
        'p': [
          [10, null, 90, 54],
        ],
        'l': <int>[],
        't': hidden,
        'secret': hidden,
      };
      put('indoor_rides.own-athlete', [
        ride,
        {...ride, 'id': shared},
      ]);
      put('indoor_rides.karina-puercher', [
        {...ride, 'id': shared},
      ]);
      put('indoor_ride.samples.$id', [
        [10, null, 90, 54],
      ]);
      put('indoor_ride.samples.$shared', [
        [10, null, 90, 54],
      ]);
      put('weekly_goal.karina-puercher', {
        'type': 'minutes',
        'target': 240,
        'password': hidden,
      });
      put('route.unowned', {'name': hidden});
      put('profile.own-athlete.estimate', {
        'watt': 2,
        'best_w': 2,
        'window_s': 3,
        'started_us': 4,
        'session': 'other',
      });
      db.dispose();
      final copy = '${temp.path}/copy.db';
      initializeArchive(copy, source);
      final second = '${temp.path}/second.db';
      initializeArchive(second, copy);
      for (final candidate in [copy, second]) {
        final r = GiuliaDatabase.open(candidate);
        try {
          final entries = {
            for (final v in r.raw.select(
              "SELECT key,value FROM app_state WHERE key LIKE 'xc.legacy.%'",
            ))
              v['key']: jsonDecode(v['value'] as String),
          };
          expect(entries.length, 3);
          expect(entries['xc.legacy.giulia.karina-puercher.weekly_goal'], {
            'type': 'minutes',
            'target': 240,
          });
          expect(entries['xc.legacy.giulia.own-athlete.indoor_samples.$id'], [
            [10, null, 90, 54],
          ]);
          final rides =
              entries['xc.legacy.giulia.own-athlete.indoor_rides'] as List;
          expect(rides.single['id'], id);
          expect(
            latin1.decode(File(candidate).readAsBytesSync()),
            isNot(contains(hidden)),
          );
        } finally {
          r.dispose();
        }
      }
    },
  );
}
