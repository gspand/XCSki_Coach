library;

import '../../database/coach_storage_repository.dart';
import 'strava_client.dart';

class StravaSyncResult {
  const StravaSyncResult({
    required this.activitiesFetched,
    required this.sessionsSaved,
    required this.coveredFrom,
    required this.coveredTo,
    this.errorMessage,
  });

  final int activitiesFetched;
  final int sessionsSaved;
  final DateTime coveredFrom;
  final DateTime coveredTo;
  final String? errorMessage;

  bool get isSuccess => errorMessage == null;
}

class StravaSyncService {
  StravaSyncService({required this.storage, StravaClient? client})
    : _client = client ?? StravaClient();

  final SqliteCoachStorageRepository storage;
  final StravaClient _client;

  StravaClient get client => _client;

  StravaSyncState getOrCreateSyncState(
    String athleteId, {
    String? athleteName,
  }) => StravaSyncState(athleteId: athleteId, config: const StravaConfig());

  void initForAthlete(String athleteId, {String? athleteName}) {}
  Future<({Uri authorizationUrl, String sessionId, String sessionSecret})?>
  startConnect(String athleteId) async => null;
  Future<bool> checkConnectionStatus(String athleteId) async => false;
  Future<void> disconnect(String athleteId) async {
    storage.disconnectStrava(
      athleteId,
      nowUtcUs: DateTime.now().microsecondsSinceEpoch,
    );
  }

  Future<StravaSyncResult> syncActivities({
    required String athleteId,
    String? athleteName,
    bool allTime = false,
  }) async {
    final now = DateTime.now().toUtc();
    return StravaSyncResult(
      activitiesFetched: 0,
      sessionsSaved: 0,
      coveredFrom: now,
      coveredTo: now,
      errorMessage: 'Strava ist für XC Ski Coach nicht freigegeben.',
    );
  }
}
