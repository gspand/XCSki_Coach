import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:http/io_client.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_ski_coach/coach_store.dart';
import 'package:xc_ski_coach/garmin_personal.dart';
import 'package:xc_ski_coach/giulia_garmin.dart';

class _LiveHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CoachStore store;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    store = CoachStore(GiuliaDatabase.inMemory())..createProfiles();
  });
  tearDown(() => store.db.dispose());
  const vault = FlutterSecureStorage();
  test(
    'GIULIA binds callback to the initiating session and stores only committed activity IDs in the receipt',
    () async {
      var complete = 0, acks = 0, wrongState = true;
      final client = MockClient((r) async {
        expect(r.url.host, 'bikepacking.skybasevario.com');
        final path = r.url.path;
        dynamic data;
        if (path.endsWith('/install')) {
          data = {'token': 'test-installation'};
        } else {
          expect(r.headers['Authorization'], 'Bearer test-installation');
          if (path.endsWith('/session')) {
            data = {
              'session_id': 's1',
              'authorization_url': 'https://connect.garmin.com/auth?state=s1',
            };
          } else if (path.endsWith('/complete')) {
            complete++;
            expect(jsonDecode(r.body), {'state': 's1', 'code': 'fixture'});
            data = {'connected': true};
          } else if (path.endsWith('/account')) {
            data = {
              'connected': true,
              'account': {'user_id': 'business41'},
            };
          } else if (path.endsWith('/ack')) {
            acks++;
            expect(
              store.storage.loadNormalizedSessions('karina-puercher'),
              hasLength(1),
            );
            expect(jsonDecode(r.body)['receipts'], ['receipt']);
            data = {'ok': true};
          } else if (path.endsWith('/history')) {
            data = {'feeds': []};
          } else if (path.endsWith('/settings')) {
            expect(r.headers['X-XC-Account'], 'business41');
            data = {'cycle': false};
          } else {
            expect(path.endsWith('/inbox'), true);
            data = {
              'records': acks > 0
                  ? []
                  : [
                      {
                        'receipt': 'receipt',
                        'kind': 'activity',
                        'type': 'activities',
                        'data': {
                          'providerActivityId': '42',
                          'elapsedTime': 300,
                          'title': 'Skating',
                          'startedAt': '2026-11-26T08:00:00Z',
                          'activityType': 'cross_country_skiing',
                        },
                      },
                    ],
            };
          }
        }
        return http.Response(jsonEncode(data), 200);
      });
      final g = GiuliaGarmin(store, 'karina-puercher', client, vault);
      Future<Uri> response(Uri _) async => Uri.parse(
        'xcski://garmin/callback?state=${wrongState ? 'wrong' : 's1'}&code=fixture',
      );
      await expectLater(g.connect(response), throwsA(isA<GarminFailure>()));
      expect(complete, 0);
      wrongState = false;
      await g.connect(response);
      expect(complete, 1);
      final time = DateTime.utc(2026, 11, 26, 10);
      final prior = store.today.of('karina-puercher', now: time);
      expect(await g.synchronize(), 1);
      final updated = store.today.of('karina-puercher', now: time);
      expect(identical(updated, prior), isFalse);
      expect(updated.state.eliteAnalysis.allTime!.durationSeconds, 300);
      expect(updated.state.eliteAnalysis.allTime!.sessionCount, 1);
      expect(store.storage.latestDailyDecision('karina-puercher'), isNotNull);
      expect(acks, 1);
      expect(await g.synchronize(), 0);
      expect(store.storage.loadNormalizedSessions('own-athlete'), isEmpty);
      expect(acks, 1);
      expect(
        (await GiuliaGarmin(
          store,
          'own-athlete',
          client,
          vault,
        ).status())['connected'],
        false,
      );
    },
  );
  test(
    'live GIULIA creates a private test installation and returns a Garmin PKCE authorization URL',
    () async {
      final c = IOClient(_LiveHttp().createHttpClient(null));
      addTearDown(c.close);
      final g = GiuliaGarmin(store, 'own-athlete', c, vault);
      var opened = false;
      await expectLater(
        g.connect((uri) async {
          expect(uri.host.endsWith('.garmin.com'), isTrue);
          expect(uri.queryParameters['code_challenge_method'], 'S256');
          expect(
            uri.queryParameters['redirect_uri'],
            'https://bikepacking.skybasevario.com/giulia/api/garmin/callback',
          );
          final page = await c
              .get(uri, headers: {'Accept': 'text/html'})
              .timeout(const Duration(seconds: 25));
          expect(
            page.statusCode,
            200,
            reason:
                'Garmin authorization page must be reachable without user credentials',
          );
          expect(page.headers['content-type'], contains('text/html'));
          opened = true;
          throw const GarminFailure(
            'Test endet vor der persönlichen Anmeldung.',
          );
        }),
        throwsA(isA<GarminFailure>()),
      );
      expect(opened, isTrue);
      final status = await g.status();
      expect(status['configured'], true);
      expect(status['connected'], false);
    },
    skip: Platform.environment['XC_GIULIA_SMOKE'] != '1',
  );
}
