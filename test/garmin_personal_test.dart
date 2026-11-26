import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:xc_ski_coach/coach_store.dart';
import 'package:xc_ski_coach/garmin_personal.dart';

void main() {
  const date = CalendarDay(2026, 11, 26),
      jan = 'own-athlete',
      karina = 'karina-puercher';
  late CoachStore store;
  late List<String> paths;
  late Map<String, dynamic> activity;
  var failHrv = false, denyCycle = false;
  setUp(() {
    store = CoachStore(GiuliaDatabase.inMemory())..createProfiles();
    paths = [];
    failHrv = false;
    denyCycle = false;
    activity = {
      'ownerId': 41,
      'activityId': 12,
      'activityName': 'Loipenrunde',
      'activityType': {'typeKey': 'skate_skiing'},
      'startTimeGMT': '2026-11-26 06:00:00',
      'duration': 3600,
      'distance': 12500.5,
      'averageHR': 134,
      'hasPolyline': true,
    };
  });
  tearDown(() => store.db.dispose());
  GarminPersonal connection(String athlete) {
    return GarminPersonal(
      GarminArchive(store, athlete),
      MockClient((r) async {
        final p = r.url.path;
        paths.add(p);
        expect(r.url.host, 'personal.connectapi.garmin.com');
        if (r.method == 'POST') {
          expect(r.headers['Authorization'], 'ApiKey test');
          expect(r.headers['Accept'], '*/*');
          return http.Response('eyJ.test.sig\n', 200);
        }
        expect(r.headers['Authorization'], 'Bearer eyJ.test.sig');
        dynamic body;
        if (p.endsWith('/settings')) {
          body = {'displayName': 'Testkonto'};
        } else if (p.endsWith('/v2/dailysummaries')) {
          body = {
            'data': [
              {
                'calendarDate': date.key,
                'userProfilePk': 41,
                'bodyBattery': {'latestValue': 82},
              },
            ],
          };
        } else if (p.endsWith('/activities')) {
          body = [activity];
        } else if (p.endsWith('/dailySleep')) {
          body = {
            'dailySleepDTO': {
              'calendarDate': date.key,
              'sleepTimeSeconds': 26400,
            },
            'sleepMovement': [],
          };
        } else if (p.contains('/hrv/')) {
          if (failHrv) return http.Response('', 429);
          body = {
            'hrvSummary': {'calendarDate': date.key, 'lastNightAvg': 52},
          };
        } else if (p.contains('/menstrualcycle/')) {
          if (denyCycle) return http.Response('', 403);
          body = {'dayInCycle': 7};
        } else {
          return http.Response('', 404);
        }
        return http.Response(jsonEncode(body), 200);
      }),
    );
  }

  test(
    'raw token, confirmed account, units, UTC, repeated import, opt-in and local removal',
    () async {
      final g = connection(karina);
      expect((await g.identify('test', date)).account, '41');
      await expectLater(
        g.sync(start: date, end: date, extended: false),
        throwsA(isA<GarminFailure>()),
      );
      g.bind();
      final result = await g.sync(start: date, end: date, extended: true);
      expect(result.activities, 1);
      expect(paths.where((p) => p.contains('menstrualcycle')), isEmpty);
      expect(g.archive.dates(), [date.key]);
      expect(
        g.archive.read(date.key, 'dailyV2')['bodyBattery']['latestValue'],
        82,
      );
      final a = store.storage.loadNormalizedSessions(karina).single;
      expect(a.modality, XcModality.skiSkating);
      expect(a.distanceMetres, 12500.5);
      expect(
        DateTime.fromMicrosecondsSinceEpoch(a.startedAtUtcUs, isUtc: true).hour,
        6,
      );
      expect(a.averagePowerWatt, isNull);
      expect(a.dataQuality.hasGps, isTrue);
      g.archive.setCycle(true);
      await g.sync(start: date, end: date, extended: false);
      expect(g.archive.read(date.key, 'cycle')['dayInCycle'], 7);
      expect(store.storage.loadNormalizedSessions(karina), hasLength(1));
      expect(GarminArchive(store, jan).dates(), isEmpty);
      g.archive.setCycle(false);
      g.archive.setCycle(true);
      expect(g.archive.read(date.key, 'cycle'), isNull);
      expect(g.archive.read(date.key, 'cycleLog'), isNull);
      expect(g.archive.read(date.key, 'sleep')['sleepTimeSeconds'], 26400);
      expect(
        store.db.raw.select(
          "SELECT 1 FROM app_state WHERE value LIKE '%eyJ.test.sig%'",
        ),
        isEmpty,
      );
    },
  );
  test(
    'same Garmin account cannot be assigned to two athletes; wrong owner rolls back',
    () async {
      final g = connection(karina);
      await g.identify('test', date);
      g.bind();
      final other = connection(jan);
      await other.identify('test', date);
      expect(other.bind, throwsStateError);
      activity['ownerId'] = 42;
      await expectLater(
        g.sync(start: date, end: date, extended: false),
        throwsA(isA<GarminFailure>()),
      );
      expect(store.storage.loadNormalizedSessions(karina), isEmpty);
      expect(g.archive.dates(), isEmpty);
    },
  );
  test(
    'partial failure is retryable; permission errors do not suppress other sources',
    () async {
      final g = connection(karina);
      await g.identify('test', date);
      g.bind();
      g.archive.setCycle(true);
      failHrv = true;
      await expectLater(
        g.sync(start: date, end: date, extended: false),
        throwsA(isA<GarminFailure>()),
      );
      expect(g.archive.setting('lastSync'), isNull);
      expect(g.archive.read(date.key, 'sleep'), isNotNull);
      expect(
        DateTime.parse(
          g.archive.setting('retryAfter')!,
        ).isAfter(DateTime.now()),
        true,
      );
      g.archive.set('retryAfter', DateTime.utc(2020).toIso8601String());
      denyCycle = true;
      failHrv = false;
      final r = await g.sync(start: date, end: date, extended: false);
      expect(r.unavailable, containsAll(['cycle', 'cycleLog']));
      expect(g.archive.setting('lastSync'), isNotNull);
      expect(g.archive.series(date.key), contains('hrv'));
    },
  );
}
