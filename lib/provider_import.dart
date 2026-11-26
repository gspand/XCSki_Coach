import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xc_coach/domain/normalized_session.dart';
import 'package:xc_coach/domain/normalized_session_adapters.dart';
import 'coach_store.dart';

/// An authenticated session belongs to one local profile. The password and
/// proxy bearer never enter the training archive or a launch configuration.
class ProviderImport {
  ProviderImport(this.store, this.athleteId, this.httpClient);
  final CoachStore store;
  final String athleteId;
  final http.Client httpClient;
  static const api = 'https://api.skybasevario.com/bikepacking_diary/api';
  static const auth = 'https://bikepacking.skybasevario.com/sync';
  String? _token;
  bool get signedIn => _token != null;

  Future<Map<String, dynamic>> _request(
    String method,
    Uri uri, {
    Map<String, String>? body,
    String? bearer,
  }) async {
    final headers = {
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if ((bearer ?? _token) != null)
        'Authorization': 'Bearer ${bearer ?? _token}',
    };
    final res =
        await (method == 'GET'
                ? httpClient.get(uri, headers: headers)
                : httpClient.post(
                    uri,
                    headers: headers,
                    body: body == null ? null : jsonEncode(body),
                  ))
            .timeout(const Duration(seconds: 60));
    if (res.statusCode == 404 || res.statusCode == 503) {
      throw StateError(
        'Der Verbindungsdienst stellt diese Funktion derzeit nicht bereit.',
      );
    }
    if (res.statusCode == 401) {
      throw StateError(
        'Anmeldung erforderlich. Bitte das eigene Outdoor-Diary-Konto verwenden.',
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('Abruf fehlgeschlagen (HTTP ${res.statusCode}).');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  void bind(String provider, String account) {
    if (!const {
      'garmin',
      'diary',
      'garminPersonal',
      'giuliaGarmin',
    }.contains(provider)) {
      throw UnsupportedError(
        'Dieser Anbieter ist für XC Ski Coach nicht freigegeben.',
      );
    }
    if (account.isEmpty) {
      throw const FormatException('Das Konto hat keine eindeutige Kennung.');
    }
    final key = 'xc.account.$provider.$athleteId';
    if (!store.athletes.any((profile) => profile.id == athleteId)) {
      throw StateError('Dieses Profil ist nicht freigegeben.');
    }
    store.db.transaction(() {
      final prefix = 'xc.account.$provider.';
      final bindings = store.db.raw.select(
        'SELECT key,value FROM app_state WHERE substr(key,1,length(?))=?',
        [prefix, prefix],
      );
      for (final row in bindings) {
        if ((row['key'] == key && row['value'] != account) ||
            (row['key'] != key && row['value'] == account)) {
          throw StateError(
            'Dieses Konto passt nicht zur gespeicherten Profilzuordnung.',
          );
        }
      }
      store.platform.setAppState(
        key: key,
        value: account,
        nowUtcUs: DateTime.now().microsecondsSinceEpoch,
      );
    });
  }

  Future<void> login(String email, String password) async {
    _token = null;
    final session = await _request(
      'POST',
      Uri.parse('$auth/auth/login'),
      body: {'email': email.trim(), 'password': password},
    );
    final token = session['access_token'] as String;
    final user = await _request(
      'GET',
      Uri.parse('$auth/auth/me'),
      bearer: token,
    );
    bind('diary', (user['id'] ?? '').toString());
    _token = token;
  }

  Future<Uri> connect(String provider) async {
    if (provider != 'garmin') throw UnsupportedError('Datenquelle gesperrt.');
    final data = await _request('POST', Uri.parse('$api/garmin/session'));
    final uri = Uri.parse(data['authorization_url'] as String);
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('Ungültige Anmeldeadresse.');
    }
    return uri;
  }

  Future<int> sync(String provider) async {
    if (provider != 'garmin') throw UnsupportedError('Datenquelle gesperrt.');
    final state = await _request('GET', Uri.parse('$api/garmin/account'));
    if (state['connected'] != true && state['status'] != 'connected') {
      throw StateError('Bitte zuerst das Konto über den Browser verbinden.');
    }
    final account = state['account'];
    if (account is Map && account['user_id'] != null) {
      bind('garmin', account['user_id'].toString());
    }
    final now = DateTime.now().toUtc();
    final key = 'xc.garmin.until.$athleteId';
    final last = DateTime.tryParse(store.platform.appState(key) ?? '');
    final from = last?.subtract(const Duration(days: 2)) ?? DateTime.utc(1970);
    var count = 0;
    String? cursor;
    final cursors = <String>{};
    do {
      final uri = Uri.parse('$api/garmin/activities').replace(
        queryParameters: {
          'after': from.toIso8601String(),
          'before': now.toIso8601String(),
          'cursor': ?cursor,
        },
      );
      final batch = await _request('GET', uri);
      final activities = batch['activities'] as List;
      store.db.transaction(() {
        for (final row in activities.cast<Map<String, dynamic>>()) {
          store.storage.saveNormalizedSession(
            garminSession(row, athleteId),
            nowUtcUs: now.microsecondsSinceEpoch,
          );
        }
      });
      count += activities.length;
      if ((batch['errors'] as List?)?.isNotEmpty == true) {
        throw StateError(
          'Garmin meldet unvollständige Aktivitäten. Der Zeitraum bleibt für den nächsten Abruf offen.',
        );
      }
      if (batch['has_more'] != true) break;
      cursor = batch['next_cursor'] as String?;
      if (cursor == null || cursor.isEmpty || !cursors.add(cursor)) {
        throw const FormatException(
          'Garmin hat keinen neuen Seitenzeiger geliefert.',
        );
      }
    } while (true);
    // The Diary acknowledgement belongs to its trip importer. XC maintains
    // its own watermark and leaves the remote trip import queue intact.
    store.platform.setAppState(
      key: key,
      value: now.toIso8601String(),
      nowUtcUs: now.microsecondsSinceEpoch,
    );
    return count;
  }
}

NormalizedSession garminSession(Map<String, dynamic> raw, String athlete) {
  for (final key in [
    'provider',
    'providerId',
    'originProvider',
    'sourceProvider',
  ]) {
    if (raw[key]?.toString().trim().toLowerCase() == 'strava') {
      throw const FormatException(
        'Die Aktivität stammt aus einer gesperrten Quelle.',
      );
    }
  }
  final sourceId =
      (raw['providerActivityId'] ?? raw['externalActivityId'] ?? '').toString();
  if (sourceId.isEmpty) {
    throw const FormatException('Garmin-Aktivität ohne Kennung.');
  }
  final start = DateTime.parse(raw['startedAt'] as String);
  final title = raw['title'] as String? ?? 'Garmin-Aktivität';
  final sport = raw['activityType'] as String? ?? '';
  final classification = EvidenceBasedModalityClassifier.classify(
    sport: sport,
    title: title,
  );
  final moving = (raw['movingTime'] as num?)?.round();
  final elapsed = (raw['elapsedTime'] as num?)?.round();
  if (elapsed == null ||
      elapsed <= 0 ||
      (moving != null && (moving < 0 || moving > elapsed))) {
    throw const FormatException('Ungültige Garmin-Dauer.');
  }
  final hr = (raw['averageHr'] as num?)?.toDouble();
  final power = (raw['averagePower'] as num?)?.toDouble();
  return NormalizedSession(
    id: 'garmin_${athlete}_$sourceId',
    athleteId: athlete,
    source: NormalizedSessionSource.garmin,
    sourceId: sourceId,
    startedAtUtcUs: start.toUtc().microsecondsSinceEpoch,
    durationSeconds: elapsed,
    movingTimeSeconds: moving ?? elapsed,
    modality: classification.modality,
    technique: classification.technique,
    classificationProvenance: classification.provenance,
    isIndoor: sport.contains('indoor'),
    title: title,
    distanceMetres: (raw['distance'] as num?)?.toDouble() == null
        ? null
        : (raw['distance'] as num) * 1000.0,
    elevationGainMetres: (raw['elevationGain'] as num?)?.toDouble(),
    elevationLossMetres: (raw['elevationLoss'] as num?)?.toDouble(),
    internalMetrics: SessionInternalMetrics(
      averageHeartRateBpm: hr,
      peakHeartRateBpm: (raw['maxHr'] as num?)?.round(),
    ),
    externalMetrics: SessionExternalMetrics(
      averagePowerWatt: power,
      normalizedPowerWatt: (raw['normalizedPower'] as num?)?.toDouble(),
      strokeOrCadenceRate: (raw['averageCadence'] as num?)?.toDouble(),
    ),
    dataQuality: SessionDataQuality(
      confidence: 0.95,
      hasHeartRate: hr != null,
      hasPower: power != null,
      hasGps:
          raw['hasGps'] == true ||
          ((raw['track'] as List?)?.isNotEmpty ?? false),
    ),
    rawMetadata: {'originalSportType': sport, 'garmin': raw},
  );
}

NormalizedSession garminPersonalActivity(
  Map<String, dynamic> activity,
  String athlete,
) {
  final timestamp = activity['beginTimestamp'];
  final start = timestamp is num
      ? DateTime.fromMillisecondsSinceEpoch(timestamp.round(), isUtc: true)
      : DateTime.parse(
          "${(activity['startTimeGMT'] as String).replaceFirst(' ', 'T')}Z",
        );
  final distance = activity['distance'] as num?;
  return garminSession({
    'providerActivityId': activity['activityId'],
    'activityType': activity['activityType']?['typeKey'],
    'title': activity['activityName'],
    'startedAt': start.toIso8601String(),
    'elapsedTime': activity['elapsedDuration'] ?? activity['duration'],
    'movingTime': activity['movingDuration'],
    'distance': distance == null ? null : distance / 1000,
    'elevationGain': activity['elevationGain'],
    'elevationLoss': activity['elevationLoss'],
    'averageHr': activity['averageHR'],
    'maxHr': activity['maxHR'],
    'averagePower': activity['avgPower'],
    'normalizedPower': activity['normPower'],
    'averageCadence':
        activity['avgStrokeCadence'] ??
        activity['averageRunningCadenceInStepsPerMinute'] ??
        activity['averageBikingCadenceInRevPerMinute'],
    'hasGps': activity['hasPolyline'],
    'personalApi': activity,
  }, athlete);
}
