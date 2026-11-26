library;

import 'package:http/http.dart' as http;
import 'strava_activity.dart';

class StravaConfig {
  const StravaConfig({
    this.apiBaseUrl = 'https://bikepacking.skybasevario.com/api',
    this.syncBaseUrl = 'https://bikepacking.skybasevario.com/sync',
    this.sessionId = '',
    this.sessionSecret = '',
    this.accessToken = '',
    this.refreshToken = '',
    this.athleteId = '',
    this.athleteName = '',
  });

  final String apiBaseUrl;
  final String syncBaseUrl;
  final String sessionId;
  final String sessionSecret;
  final String accessToken;
  final String refreshToken;
  final String athleteId;
  final String athleteName;

  static StravaConfig defaultForAthlete({
    required String athleteId,
    String? athleteName,
  }) => const StravaConfig();

  bool get isConnected =>
      accessToken.trim().isNotEmpty || sessionId.trim().isNotEmpty;

  StravaConfig copyWith({
    String? apiBaseUrl,
    String? syncBaseUrl,
    String? sessionId,
    String? sessionSecret,
    String? accessToken,
    String? refreshToken,
    String? athleteId,
    String? athleteName,
  }) => StravaConfig(
    apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
    syncBaseUrl: syncBaseUrl ?? this.syncBaseUrl,
    sessionId: sessionId ?? this.sessionId,
    sessionSecret: sessionSecret ?? this.sessionSecret,
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    athleteId: athleteId ?? this.athleteId,
    athleteName: athleteName ?? this.athleteName,
  );

  Map<String, dynamic> toJson() => {
    'api_base_url': apiBaseUrl,
    'sync_base_url': syncBaseUrl,
    'session_id': sessionId,
    'session_secret': sessionSecret,
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'athlete_id': athleteId,
    'athlete_name': athleteName,
  };

  factory StravaConfig.fromJson(Map<String, dynamic> json) => StravaConfig(
    apiBaseUrl:
        (json['api_base_url'] ?? 'https://bikepacking.skybasevario.com/api')
            .toString(),
    syncBaseUrl:
        (json['sync_base_url'] ?? 'https://bikepacking.skybasevario.com/sync')
            .toString(),
    sessionId: (json['session_id'] ?? '').toString(),
    sessionSecret: (json['session_secret'] ?? '').toString(),
    accessToken: (json['access_token'] ?? '').toString(),
    refreshToken: (json['refresh_token'] ?? '').toString(),
    athleteId: (json['athlete_id'] ?? '').toString(),
    athleteName: (json['athlete_name'] ?? '').toString(),
  );
}

/// The standalone product has no approved Strava connector.
class StravaClient {
  StravaClient({
    http.Client? client,
    this.runtimeBearer,
    this.config = const StravaConfig(),
  });
  final String? runtimeBearer;
  StravaConfig config;

  Future<({Uri authorizationUrl, String sessionId, String sessionSecret})?>
  startOAuthFlow() async => null;
  Future<bool> checkConnection() async => false;
  Future<bool> pollSessionStatus(String sessionId) async => false;
  Future<void> disconnect() async {
    config = const StravaConfig();
  }

  Future<List<StravaActivity>> getActivities({
    DateTime? after,
    DateTime? before,
    int page = 1,
    int perPage = 50,
  }) async =>
      throw UnsupportedError('Strava ist für XC Ski Coach nicht freigegeben.');
  Future<Map<String, dynamic>?> getActivityStreams(String activityId) async =>
      throw UnsupportedError('Strava ist für XC Ski Coach nicht freigegeben.');
}
