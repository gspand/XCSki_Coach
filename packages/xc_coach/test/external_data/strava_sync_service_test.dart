import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:xc_coach/database/coach_storage_repository.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_coach/external_data/strava/strava_client.dart';
import 'package:xc_coach/external_data/strava/strava_sync_service.dart';

void main() {
  test(
    'all disabled connector operations avoid HTTP, even with credentials',
    () async {
      final database = GiuliaDatabase.inMemory();
      addTearDown(database.dispose);
      final storage = SqliteCoachStorageRepository(database);
      final transport = MockClient(
        (request) => throw StateError('Unexpected network call'),
      );
      final client = StravaClient(
        client: transport,
        runtimeBearer: 'fixture',
        config: const StravaConfig(accessToken: 'fixture'),
      );
      expect(await client.startOAuthFlow(), isNull);
      expect(await client.checkConnection(), isFalse);
      expect(await client.pollSessionStatus('fixture'), isFalse);
      await expectLater(client.getActivities(), throwsUnsupportedError);
      await expectLater(
        client.getActivityStreams('fixture'),
        throwsUnsupportedError,
      );
      final service = StravaSyncService(storage: storage, client: client);
      expect(await service.startConnect('athlete'), isNull);
      expect(await service.checkConnectionStatus('athlete'), isFalse);
      for (final full in [false, true]) {
        final result = await service.syncActivities(
          athleteId: 'athlete',
          allTime: full,
        );
        expect(result.isSuccess, isFalse);
        expect(result.activitiesFetched, 0);
        expect(result.sessionsSaved, 0);
      }
      expect(storage.getStravaSyncState('athlete'), isNull);
    },
  );
}
