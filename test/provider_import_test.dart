import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_coach/domain/normalized_session.dart';
import 'package:xc_coach/domain/training_sessions.dart';
import 'package:xc_ski_coach/coach_store.dart';
import 'package:xc_ski_coach/provider_import.dart';

void main() {
  test(
    'additional authorized profiles share the same account-ownership checks',
    () {
      final store = CoachStore(GiuliaDatabase.inMemory())
        ..createProfiles(profiles: {'a': 'Anton', 'b': 'Bea', 'c': 'Chris'});
      addTearDown(store.db.dispose);
      final client = MockClient(
        (_) async => throw StateError('Kein Netzaufruf erwartet.'),
      );
      final first = ProviderImport(store, 'a', client);
      first.bind('giuliaGarmin', 'fixture-owner');
      expect(
        () => ProviderImport(
          store,
          'c',
          client,
        ).bind('giuliaGarmin', 'fixture-owner'),
        throwsStateError,
      );
      expect(
        () => ProviderImport(
          store,
          'missing',
          client,
        ).bind('giuliaGarmin', 'fixture-unused'),
        throwsStateError,
      );
      expect(store.athletes, hasLength(3));
    },
  );

  test('blocked providers never start a request', () async {
    final store = CoachStore(GiuliaDatabase.inMemory())..createProfiles();
    addTearDown(store.db.dispose);
    var calls = 0;
    final provider = ProviderImport(
      store,
      'own-athlete',
      MockClient((request) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    for (final name in ['strava', '../strava', 'Strava']) {
      await expectLater(provider.connect(name), throwsUnsupportedError);
      await expectLater(provider.sync(name), throwsUnsupportedError);
      expect(() => provider.bind(name, 'fixture'), throwsUnsupportedError);
    }
    expect(calls, 0);
  });

  test(
    'profile-bound login, completed Garmin pagination, retries and account isolation',
    () async {
      final store = CoachStore(GiuliaDatabase.inMemory())..createProfiles();
      addTearDown(store.db.dispose);
      var fail = true;
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/auth/login'))
          return http.Response('{"access_token":"test-only"}', 200);
        expect(request.headers['Authorization'], 'Bearer test-only');
        if (path.endsWith('/auth/me'))
          return http.Response('{"id":"user-a"}', 200);
        if (path.endsWith('/account'))
          return http.Response(
            '{"connected":true,"account":{"user_id":"athlete-a"}}',
            200,
          );
        if (path.endsWith('/activities')) {
          final pageTwo = request.url.queryParameters['cursor'] == 'page-two';
          if (pageTwo && fail) return http.Response('{}', 503);
          return http.Response(
            jsonEncode({
              'has_more': !pageTwo,
              'next_cursor': 'page-two',
              'activities': [
                {
                  'providerActivityId': pageTwo ? 'b' : 'a',
                  'activityType': 'cross_country_skiing',
                  'title': 'Klassisch',
                  'startedAt': pageTwo
                      ? '2026-11-02T07:00:00Z'
                      : '2026-11-01T07:00:00Z',
                  'elapsedTime': 3600,
                  'distance': 14.5,
                },
              ],
            }),
            200,
          );
        }
        failTest('Unexpected request');
      });
      final jan = ProviderImport(store, 'own-athlete', client);
      await jan.login('example@test.invalid', 'test');
      await expectLater(jan.sync('garmin'), throwsStateError);
      expect(store.platform.appState('xc.garmin.until.own-athlete'), isNull);
      fail = false;
      expect(await jan.sync('garmin'), 2);
      final sessions = store.storage.loadNormalizedSessions('own-athlete');
      expect(sessions.length, 2);
      final same = sessions.first.copyWith(
        id: 'mirror',
        source: NormalizedSessionSource.strava,
      );
      expect(trainingSessions([...sessions, same]), hasLength(2));
      final karina = ProviderImport(store, 'karina-puercher', client);
      await expectLater(
        karina.login('example@test.invalid', 'test'),
        throwsStateError,
      );
      expect(karina.signedIn, isFalse);
      expect(store.storage.loadNormalizedSessions('karina-puercher'), isEmpty);
      expect(
        store.db.raw.select(
          "SELECT 1 FROM app_state WHERE value LIKE '%test-only%'",
        ),
        isEmpty,
      );
    },
  );
}

Never failTest(String text) => throw StateError(text);
