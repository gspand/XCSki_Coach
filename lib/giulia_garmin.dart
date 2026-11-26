import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'coach_store.dart';
import 'garmin_personal.dart';
import 'provider_import.dart';
import 'garmin_push.dart';

/// GIULIA associates each OAuth session with the installation that created it.
/// XC uses a separate installation per athlete. The GIULIA app keeps its own.
class GiuliaGarmin {
  GiuliaGarmin(this.store, this.athlete, this.client, this.vault);
  final CoachStore store;
  final String athlete;
  final http.Client client;
  final FlutterSecureStorage vault;
  static const base = 'https://bikepacking.skybasevario.com/giulia/api';
  static const deviceVault = FlutterSecureStorage(
    mOptions: MacOsOptions(
      usesDataProtectionKeychain: false,
      accountName: 'XC Ski Coach · Garmin',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );
  GarminArchive get archive => GarminArchive(store, athlete);
  String get _vaultKey => 'xc.giulia.installation.$athlete';

  Future<GarminJson> _request(
    String method,
    String path, {
    String? token,
    String? subject,
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    final req =
        http.Request(
            method,
            Uri.parse('$base$path').replace(queryParameters: query),
          )
          ..followRedirects = false
          ..headers['Accept'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (subject != null) req.headers['X-XC-Account'] = subject;
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await client
        .send(req)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 45));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw GarminFailure(switch (res.statusCode) {
        401 => 'GIULIA erkennt diese Geräteverbindung nicht mehr.',
        403 || 410 =>
          'Die Garmin-Freigabe ist abgelaufen oder gehört zu einer anderen Anmeldung.',
        409 => 'Die Verbindung muss bei Garmin erneut freigegeben werden.',
        503 => 'Garmin ist beim GIULIA-Dienst derzeit nicht verfügbar.',
        _ =>
          'GIULIA konnte die Anfrage nicht abschließen (HTTP ${res.statusCode}).',
      }, res.statusCode);
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as GarminJson;
  }

  Future<String> _installation() async {
    final saved = await vault.read(key: _vaultKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final issued = await _request('POST', '/install');
    final token = issued['token'];
    if (token is! String || token.isEmpty)
      throw const GarminFailure(
        'GIULIA hat keinen Geräteschlüssel ausgegeben.',
      );
    await vault.write(key: _vaultKey, value: token);
    if (await vault.read(key: _vaultKey) != token)
      throw const GarminFailure(
        'Der Geräteschlüssel konnte nicht sicher gespeichert werden.',
      );
    return token;
  }

  Future<GarminJson> status() async {
    final token = await vault.read(key: _vaultKey);
    if (token == null) return {'connected': false};
    try {
      return await _request('GET', '/garmin/account', token: token);
    } on GarminFailure catch (e) {
      if (e.status != 401) rethrow;
      await vault.delete(key: _vaultKey);
      return {'connected': false};
    }
  }

  Future<GarminJson> connect(Future<Uri> Function(Uri) openGarmin) async {
    final token = await _installation();
    final session = await _request(
      'POST',
      '/xc/garmin/session',
      token: token,
      body: {
        'cycle':
            archive.cycleEnabled && archive.setting('pushCycleAllowed') == '1',
      },
    );
    final state = session['session_id'];
    final url = Uri.parse(session['authorization_url'] as String);
    if (state is! String ||
        state.isEmpty ||
        url.queryParameters['state'] != state ||
        url.scheme != 'https' ||
        !(url.host == 'garmin.com' || url.host.endsWith('.garmin.com'))) {
      throw const GarminFailure('Ungültige Garmin-Anmeldeadresse.');
    }
    final result = await openGarmin(url);
    final code = result.queryParameters['code'];
    if (result.scheme != 'xcski' ||
        result.host != 'garmin' ||
        result.path != '/callback' ||
        result.queryParameters['state'] != state ||
        code == null ||
        code.isEmpty) {
      throw const GarminFailure(
        'Die Rückmeldung passt nicht zu dieser Garmin-Anmeldung.',
      );
    }
    final connection = await _request(
      'POST',
      '/garmin/complete',
      token: token,
      body: {'state': state, 'code': code},
    );
    if (connection['connected'] != true)
      throw const GarminFailure(
        'Garmin hat die Verbindung noch nicht bestätigt.',
      );
    return connection;
  }

  Future<void> disconnect() async {
    final token = await vault.read(key: _vaultKey);
    if (token != null) await _request('POST', '/garmin/logout', token: token);
  }

  static final _running = <(CoachStore, String), Future<int>>{};

  Future<int> synchronize() {
    final key = (store, athlete);
    return _running[key] ??= _sync().whenComplete(() {
      _running.remove(key);
    });
  }

  Future<void> configureCycle(bool enabled) async {
    final key = (store, athlete);
    final pending = _running[key];
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
      return configureCycle(enabled);
    }
    final work = _changeCycle(enabled).then((_) => 0).whenComplete(() {
      _running.remove(key);
    });
    _running[key] = work;
    await work;
  }

  Future<void> _changeCycle(bool enabled) async {
    final token = await vault.read(key: _vaultKey);
    final state = await status();
    if (state['connected'] == true) {
      final subject = _bind(state);
      await _request(
        'POST',
        '/xc/garmin/settings',
        token: token,
        subject: subject,
        body: {'cycle': enabled},
      );
    }
    archive.setCycle(enabled);
    archive.set('pushCycleAllowed', enabled ? '1' : '0');
  }

  String _bind(GarminJson state) {
    final subject = state['account']?['user_id'] as String? ?? '';
    ProviderImport(store, athlete, client).bind('giuliaGarmin', subject);
    return subject;
  }

  Future<int> _sync() async {
    final token = await vault.read(key: _vaultKey);
    if (token == null) return 0;
    final state = await status();
    if (state['connected'] != true) return 0;
    final subject = _bind(state);
    final granted =
        archive.setting('pushCycleAllowed') == '1' && archive.cycleEnabled;
    final settings = await _request(
      'POST',
      '/xc/garmin/settings',
      token: token,
      subject: subject,
      body: {},
    );
    if (settings['permissions'] is List)
      archive.set('pushPermissions', jsonEncode(settings['permissions']));
    if (settings['cycle'] != granted) {
      await _request(
        'POST',
        '/xc/garmin/settings',
        token: token,
        subject: subject,
        body: {
          'cycle':
              archive.setting('pushCycleAllowed') == '1' &&
              archive.cycleEnabled,
        },
      );
    }
    var count = 0;
    while (true) {
      final page = await _request(
        'GET',
        '/xc/garmin/inbox',
        token: token,
        subject: subject,
      );
      final rows = (page['records'] as List).cast<GarminJson>();
      if (rows.isEmpty) break;
      final receipts = <String>[];
      store.db.transaction(() {
        for (final row in rows) {
          receipts.add(row['receipt'] as String);
          switch (row['kind']) {
            case 'activity':
              _activity(row['data'] as GarminJson);
            case 'cycle':
              if (archive.setting('pushCycleAllowed') == '1')
                storeGarminPush(archive, row);
            case 'detail':
            case 'health':
              storeGarminPush(archive, row);
            default:
              throw const FormatException('Unbekannter Garmin-Datensatz.');
          }
        }
        archive.set(
          'lastPushReceived',
          DateTime.now().toUtc().toIso8601String(),
        );
      });
      store.today.invalidate(athlete);
      await _request(
        'POST',
        '/xc/garmin/ack',
        token: token,
        subject: subject,
        body: {'receipts': receipts},
      );
      count += rows.length;
    }
    archive.set('lastPushCheck', DateTime.now().toUtc().toIso8601String());
    archive.set('pushError', '');
    try {
      final history = await _request(
        'POST',
        '/xc/garmin/history',
        token: token,
        subject: subject,
        body: {},
      );
      final feeds = history['feeds'];
      if (feeds is List) archive.set('historyFeeds', jsonEncode(feeds));
      archive.set('historyError', '');
    } catch (_) {
      archive.set(
        'historyError',
        'Status des historischen Abrufs derzeit nicht erreichbar.',
      );
    }
    return count;
  }

  void _activity(GarminJson row) {
    final session = garminSession(row, athlete);
    final time = DateTime.now().microsecondsSinceEpoch;
    final key = 'xc.giulia.garmin.$athlete.activity.${session.sourceId}';
    final old = store.platform.appState(key);
    if (old != null) {
      final previous = jsonDecode(old) as GarminJson;
      if ((previous['samples'] as List?)?.isNotEmpty == true &&
          (row['samples'] as List?)?.isNotEmpty != true) {
        row = {
          ...previous,
          ...row,
          for (final name in ['track', 'samples', 'laps', 'pauses', 'sessions'])
            name: previous[name],
        };
      }
    }
    store.platform.setAppState(
      key: key,
      value: jsonEncode(row),
      nowUtcUs: time,
    );
    final prior = store.db.raw.select(
      r"SELECT json_type(data_json, '$.rawMetadata.garmin.personalApi') AS personal FROM normalized_session_record WHERE athlete_id=? AND source='garmin' AND source_id=?",
      [athlete, session.sourceId],
    );
    if (prior.isEmpty || prior.first['personal'] == null)
      store.storage.saveNormalizedSession(
        garminSession(row, athlete),
        nowUtcUs: time,
      );
  }
}
