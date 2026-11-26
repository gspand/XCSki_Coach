import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xc_coach/domain/training_plan.dart';

import 'coach_store.dart';
import 'provider_import.dart';

typedef GarminJson = Map<String, dynamic>;

const garminKeyPage =
    'https://connect.garmin.com/app/settings/personalApiToken';

class GarminFailure implements Exception {
  const GarminFailure(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

class GarminArchive {
  GarminArchive(this.store, this.athlete);
  final CoachStore store;
  final String athlete;
  String get prefix => 'xc.personal.$athlete.';
  String? setting(String name) => store.platform.appState('$prefix$name');
  void set(String name, String value) => store.platform.setAppState(
    key: '$prefix$name',
    value: value,
    nowUtcUs: DateTime.now().microsecondsSinceEpoch,
  );
  bool get cycleEnabled => setting('cycleEnabled') == '1';
  void setCycle(bool enabled) {
    store.db.transaction(() {
      set('cycleEnabled', enabled ? '1' : '0');
      if (!enabled) {
        store.db.raw.execute('DELETE FROM app_state WHERE key GLOB ?', [
          '${prefix}day.*.cycle*',
        ]);
        store.db.raw.execute('DELETE FROM app_state WHERE key GLOB ?', [
          '${prefix}undated.cyclePush.*',
        ]);
      }
    });
  }

  void save(String day, String series, dynamic value) =>
      set('day.$day.$series', jsonEncode(value));
  dynamic read(String day, String series) {
    if (series.startsWith('cycle') && !cycleEnabled) return null;
    final raw = setting('day.$day.$series');
    return raw == null ? null : jsonDecode(raw);
  }

  List<String> undatedKeys() {
    final start = '${prefix}undated.';
    return store.db.raw
        .select('SELECT key FROM app_state WHERE key GLOB ? ORDER BY key', [
          '$start*',
        ])
        .map((r) => (r['key'] as String).substring(start.length))
        .where((key) => cycleEnabled || !key.startsWith('cycle'))
        .toList();
  }

  List<String> dates() => store.db.raw
      .select(
        'SELECT DISTINCT substr(key, ?, 10) AS day FROM app_state WHERE key GLOB ? ORDER BY day DESC',
        [prefix.length + 5, '${prefix}day.*'],
      )
      .map((r) => r['day'] as String)
      .toList();
  List<String> series(String day) {
    final start = '${prefix}day.$day.';
    return store.db.raw
        .select('SELECT key FROM app_state WHERE key GLOB ? ORDER BY key', [
          '$start*',
        ])
        .map((row) => (row['key'] as String).substring(start.length))
        .where((key) => cycleEnabled || !key.startsWith('cycle'))
        .toList();
  }
}

const garminSeries = <String, String>{
  'connectMetrics': 'Garmin-Tageswerte',
  'cycleConnectMetrics': 'Garmin-Zykluswerte',
  'summary': 'Tagesübersicht',
  'dailyV2': 'Gesundheitsübersicht',
  'sleep': 'Schlaf',
  'hrv': 'Herzfrequenzvariabilität',
  'battery': 'Body Battery',
  'heart': 'Herzfrequenz',
  'oxygen': 'Sauerstoffsättigung',
  'cycle': 'Zyklusübersicht',
  'cycleLog': 'Zyklusprotokoll',
  'zones': 'Herzfrequenzzonen',
  'fitnessAge': 'Fitnessalter',
  'vo2': 'VO₂max',
  'nutrition': 'Ernährungsprotokoll',
  'hydration': 'Flüssigkeitsaufnahme',
  'weight': 'Gewicht',
  'weightGoal': 'Gewichtsziel',
  'steps': 'Schritte',
  'stress': 'Stress',
  'movement': 'Alltagsaktivität',
};

class GarminSyncResult {
  int activities = 0;
  int records = 0;
  final unavailable = <String>{};
}

class GarminPersonal {
  GarminPersonal(this.archive, this.client);
  final GarminArchive archive;
  final http.Client client;
  String? _token;
  String? _account;

  Future<dynamic> _request(
    String path, {
    Map<String, String>? query,
    String? apiKey,
  }) async {
    final uri = Uri.https('personal.connectapi.garmin.com', path, query);
    final req = http.Request(apiKey == null ? 'GET' : 'POST', uri)
      ..followRedirects = false
      ..headers['Accept'] = apiKey == null ? 'application/json' : '*/*'
      ..headers['Authorization'] = apiKey == null
          ? 'Bearer $_token'
          : 'ApiKey $apiKey';
    final res = await client
        .send(req)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 30));
    switch (res.statusCode) {
      case 200:
      case 201:
        if (res.bodyBytes.isEmpty) return null;
        final body = utf8.decode(res.bodyBytes).trim();
        return apiKey != null ? body : jsonDecode(body);
      case 204:
        return null;
      case 401:
        throw const GarminFailure(
          'Garmin hat den Schlüssel abgelehnt. Bitte Gültigkeit prüfen.',
          401,
        );
      case 403:
        throw const GarminFailure(
          'Garmin hat diese Daten nicht freigegeben.',
          403,
        );
      case 404:
        throw const GarminFailure(
          'Bei Garmin sind hier keine Daten verfügbar.',
          404,
        );
      case 429:
        final retry = res.headers['retry-after'];
        final seconds = int.tryParse(retry ?? '');
        final now = DateTime.now().toUtc();
        var retryAt = now.add(
          Duration(seconds: seconds != null && seconds > 0 ? seconds : 900),
        );
        if (retry != null && seconds == null) {
          try {
            final date = HttpDate.parse(retry);
            if (date.isAfter(now)) retryAt = date;
          } on FormatException {
            /* Use the local retry interval. */
          } on HttpException {
            /* Invalid Retry-After header. */
          }
        }
        archive.set('retryAfter', retryAt.toIso8601String());
        throw const GarminFailure(
          'Garmins Abruflimit ist erreicht. Bitte später erneut synchronisieren.',
          429,
        );
      default:
        throw GarminFailure(
          'Garmin konnte den Abruf nicht abschließen (HTTP ${res.statusCode}).',
          res.statusCode,
        );
    }
  }

  /// Resolve identity before binding or writing any private measurements.
  Future<({String account, String name})> identify(
    String key,
    CalendarDay day,
  ) async {
    _token = null;
    _account = null;
    final response = await _request(
      '/personalapitoken-service/personal-api/personal-api-key/token',
      apiKey: key.trim(),
    );
    final token = response;
    if (token is! String || token.isEmpty) {
      throw const GarminFailure('Garmin hat keinen Zugangstoken geliefert.');
    }
    _token = token;
    final settings = await _identityData(
      '/userprofile-service/userprofile/settings',
      null,
    );
    final name = settings is Map
        ? settings['displayName'] as String? ?? ''
        : '';
    final summary = await _identityData(
      '/usersummary-service/v2/dailysummaries',
      {'startDate': day.addDays(-6).key, 'endDate': day.key},
    );
    final rows = summary is Map ? summary['data'] : null;
    var id = rows is List && rows.isNotEmpty
        ? rows.last['userProfilePk']
        : null;
    if (id == null) {
      final list = await _request(
        '/activitylist-service/activities/search/activities',
        query: {'limit': '1'},
      );
      if (list is List && list.isNotEmpty) id = list.first['ownerId'];
    }
    if (id is! int || id <= 0) {
      throw const GarminFailure(
        'Garmin hat keine eindeutige Profil-ID geliefert. Bitte zuerst die Uhr mit Garmin Connect synchronisieren.',
      );
    }
    _account = id.toString();
    return (account: _account!, name: name.isEmpty ? 'Garmin-Konto $id' : name);
  }

  Future<dynamic> _optional(String path, Map<String, String>? query) async {
    try {
      return await _request(path, query: query);
    } on GarminFailure catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<dynamic> _identityData(String path, Map<String, String>? query) async {
    try {
      return await _optional(path, query);
    } on GarminFailure catch (e) {
      if (e.status == 403) return null;
      rethrow;
    }
  }

  void bind() {
    final account = _account;
    if (account == null) {
      throw const GarminFailure('Bitte zuerst Garmin verbinden.');
    }
    ProviderImport(
      archive.store,
      archive.athlete,
      client,
    ).bind('garminPersonal', account);
  }

  Future<GarminSyncResult> sync({
    required CalendarDay start,
    required CalendarDay end,
    required bool extended,
    bool fullActivityHistory = true,
    bool checkpointActivities = false,
    void Function(String)? progress,
    bool Function()? cancelled,
  }) async {
    final retryAt = DateTime.tryParse(archive.setting('retryAfter') ?? '');
    if (retryAt != null && DateTime.now().isBefore(retryAt)) {
      throw const GarminFailure('Garmins Abruflimit ist noch aktiv.', 429);
    }
    final account = _account;
    if (account == null ||
        archive.store.platform.appState(
              'xc.account.garminPersonal.${archive.athlete}',
            ) !=
            account) {
      throw const GarminFailure(
        'Dieses Garmin-Konto wurde für das Profil noch nicht bestätigt.',
      );
    }
    if (end.isBefore(start)) throw ArgumentError('Ungültiger Zeitraum.');
    final result = GarminSyncResult();
    progress?.call('Aktivitäten werden abgerufen …');
    void checkCancellation() {
      if (cancelled?.call() == true) {
        throw const GarminFailure(
          'Abruf beendet. Bereits importierte Daten sind gespeichert.',
        );
      }
    }

    final ids = <String>{};
    var offset = 0;
    var activityEnd = end.key;
    if (checkpointActivities &&
        (archive.setting('activityPage') ?? '').isNotEmpty) {
      final saved = jsonDecode(archive.setting('activityPage')!) as Map;
      offset = saved['offset'] as int;
      activityEnd = saved['end'] as String;
      // Recheck the page boundary after a restart. Older uploads or edits
      // may have shifted Garmin's offset since the last committed page.
      final prior = await _request(
        '/activitylist-service/activities/search/activities',
        query: {'start': '${offset - 1}', 'limit': '1', 'endDate': activityEnd},
      );
      if (prior is! List ||
          prior.length != 1 ||
          prior.first['activityId'].toString() != saved['last']) {
        offset = 0;
        activityEnd = end.key;
      }
    }
    while (true) {
      checkCancellation();
      final items =
          await _request(
                '/activitylist-service/activities/search/activities',
                query: {
                  'start': '$offset',
                  'limit': '99',
                  if (!fullActivityHistory) 'startDate': start.key,
                  'endDate': activityEnd,
                },
              )
              as List;
      checkCancellation();
      if (items.isEmpty) break;
      archive.store.db.transaction(() {
        for (final payload in items.cast<GarminJson>()) {
          if (payload['ownerId']?.toString() != account) {
            throw const GarminFailure(
              'Eine Aktivität gehört zu einem anderen Garmin-Konto.',
            );
          }
          final id = payload['activityId']?.toString();
          if (id == null || !ids.add(id)) {
            throw const GarminFailure(
              'Die Garmin-Aktivitätsliste hat sich geändert. Bitte erneut abrufen.',
            );
          }
          archive.store.storage.saveNormalizedSession(
            garminPersonalActivity(payload, archive.athlete),
            nowUtcUs: DateTime.now().microsecondsSinceEpoch,
          );
        }
        if (checkpointActivities) {
          archive.set(
            'activityPage',
            jsonEncode({
              'offset': offset + items.length,
              'end': activityEnd,
              'last': items.last['activityId'].toString(),
            }),
          );
        }
      });
      archive.store.today.invalidate(archive.athlete);
      result.activities += items.length;
      offset += items.length;
      if (items.length < 99) break;
    }
    if (checkpointActivities) {
      archive.store.db.transaction(() {
        archive.set('activityPage', '');
        archive.set('activityCheckedThrough', activityEnd);
      });
    }
    for (var day = end; !day.isBefore(start); day = day.addDays(-1)) {
      final d = day.key;
      progress?.call('Gesundheitsdaten · $d');
      final date = {'date': d};
      final range = {'startDate': d, 'endDate': d};
      final requests = <String, (String, Map<String, String>?)>{
        'dailyV2': ('/usersummary-service/v2/dailysummaries', range),
        'summary': (
          '/usersummary-service/usersummary/daily',
          {'calendarDate': d},
        ),
        'sleep': ('/sleep-service/sleep/dailySleep', date),
        'hrv': ('/hrv-service/hrv/$d', null),
        'battery': (
          '/wellness-service/wellness/bodyBattery/reports/daily',
          range,
        ),
        if (archive.cycleEnabled) ...{
          'cycle': ('/periodichealth-service/menstrualcycle/summary/$d', null),
          'cycleLog': (
            '/periodichealth-service/menstrualcycle/dayview/$d',
            {'todayDate': CalendarDay.ofLocal(DateTime.now()).key},
          ),
        },
        if (extended) ...{
          'heart': ('/wellness-service/wellness/dailyHeartRate', date),
          'oxygen': (
            '/wellness-service/wellness/daily/spo2acclimation/$d',
            null,
          ),
          if (day == end)
            'zones': ('/biometric-service/heartRateZones/v2', null),
          'fitnessAge': ('/fitnessage-service/fitnessage/v2/$d', null),
          'vo2': ('/metrics-service/metrics/maxmet/daily/$d/$d', null),
          'nutrition': ('/nutrition-service/food/logs/$d', null),
          'hydration': (
            '/usersummary-service/stats/hydration/daily/$d/$d',
            null,
          ),
          'weight': ('/weight-service/weight/all/$d/$d', null),
          'weightGoal': (
            '/goal-service/goal/user/effective/weightgoal/$d/$d',
            null,
          ),
          'steps': ('/usersummary-service/stats/steps/daily/$d/$d', null),
          'stress': ('/usersummary-service/stats/stress/daily/$d/$d', null),
          'movement': (
            '/wellnessactivity-service/activity/summary/range/$d/$d',
            null,
          ),
        },
      };
      for (final e in requests.entries) {
        checkCancellation();
        if (result.unavailable.contains(e.key)) continue;
        try {
          var value = await _optional(e.value.$1, e.value.$2);
          checkCancellation();
          if (e.key == 'dailyV2' && value != null) {
            final rows = value['data'] as List;
            value = rows.isEmpty ? null : rows.single;
          }
          if (e.key == 'sleep' &&
              value is Map &&
              value['dailySleepDTO'] is Map) {
            // Some devices deliver an envelope with additional sleep time series.
            final sleep = value['dailySleepDTO'] as Map;
            value = {...value, ...sleep};
          }
          if (value == null ||
              (value is List && value.isEmpty) ||
              (value is Map && value.isEmpty)) {
            continue;
          }
          if (value is Map) {
            final owner =
                value['userProfileId'] ??
                value['userProfilePK'] ??
                value['userProfilePk'];
            if (owner != null && owner.toString() != account) {
              throw const GarminFailure(
                'Gesundheitsdaten gehören zu einem anderen Garmin-Konto.',
              );
            }
            final reported =
                value['calendarDate'] ??
                (e.key == 'hrv' && value['hrvSummary'] is Map
                    ? value['hrvSummary']['calendarDate']
                    : null);
            if (reported != null && reported != d) {
              throw const GarminFailure(
                'Garmin hat einen abweichenden Messtag gemeldet.',
              );
            }
          }
          if (e.key.startsWith('cycle') && !archive.cycleEnabled) continue;
          archive.save(d, e.key, value);
          result.records++;
        } on GarminFailure catch (error) {
          if (error.status != 403) rethrow;
          result.unavailable.add(e.key);
        }
      }
    }
    archive.set('lastSync', DateTime.now().toUtc().toIso8601String());
    archive.store.today.invalidate(archive.athlete);
    return result;
  }
}
