/// Durable snapshot repository for GIULIA's central Athlete State.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../database/giulia_database.dart';
import '../intelligence/athlete_state_engine.dart';
import '../intelligence/athlete_state_models.dart';
import '../intelligence/models.dart';

class AthleteStateRepository {
  const AthleteStateRepository({
    required this.database,
    required this.data,
    required this.organizationId,
    this.engine = const AthleteStateEngine(),
  });

  final GiuliaDatabase database;
  final IntelligenceDataSource data;
  final String organizationId;
  final AthleteStateEngine engine;

  /// Returns the persisted current state. Recalculation only occurs after a
  /// relevant write marked it dirty or when a rolling window is older than six
  /// hours. A normal chat therefore reads one snapshot rather than rebuilding
  /// the athlete from raw activities.
  AthleteState currentOrRefresh(String athleteId, {required int nowUtcUs}) {
    final current = _readCurrent(athleteId);
    final dirty = database.raw.select(
      'SELECT 1 FROM athlete_state_refresh_queue WHERE athlete_id = ?',
      [athleteId],
    ).isNotEmpty;
    final stale =
        current == null ||
        nowUtcUs - current.asOfUtcUs >= const Duration(hours: 6).inMicroseconds;
    if (!dirty && !stale) return current;
    return refresh(athleteId, nowUtcUs: nowUtcUs);
  }

  AthleteState refresh(String athleteId, {required int nowUtcUs}) {
    final sessions = data.getRecentTraining(athleteId, limit: 10000);
    final tests = data.getTests(athleteId, limit: 100);
    final observations = data.getObservations(
      athleteId,
      fromUtcUs: nowUtcUs - 28 * Duration.microsecondsPerDay,
    );
    final inputFingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'originPolicy': 'xc-origin-v1',
              'sessions': [for (final item in sessions) item.toJson()],
              'tests': [for (final item in tests) item.toJson()],
              'observations': [for (final item in observations) item.toJson()],
            }),
          ),
        )
        .toString();
    final state = engine.build(
      athleteId: athleteId,
      asOfUtcUs: nowUtcUs,
      inputFingerprint: inputFingerprint,
      sessions: sessions,
      tests: tests,
      observations: observations,
    );
    final snapshotId =
        'athlete-state-xc-origin-v1-${sha256.convert(utf8.encode('$organizationId:$athleteId:$nowUtcUs:'
        '${state.featureEngineVersion}:$inputFingerprint')).toString().substring(0, 28)}';
    database.transaction(() {
      database.raw.execute(
        '''INSERT OR IGNORE INTO athlete_state_snapshot(
             id, organization_id, athlete_id, as_of_utc_us,
             calculated_at_utc_us, feature_engine_version,
             input_fingerprint, state_json)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          snapshotId,
          organizationId,
          athleteId,
          nowUtcUs,
          nowUtcUs,
          state.featureEngineVersion,
          inputFingerprint,
          jsonEncode(state.toJson()),
        ],
      );
      database.raw.execute(
        '''INSERT INTO athlete_state_current(
             athlete_id, organization_id, snapshot_id, updated_at_utc_us)
           VALUES (?, ?, ?, ?)
           ON CONFLICT(athlete_id) DO UPDATE SET
             organization_id = excluded.organization_id,
             snapshot_id = excluded.snapshot_id,
             updated_at_utc_us = excluded.updated_at_utc_us''',
        [athleteId, organizationId, snapshotId, nowUtcUs],
      );
      database.raw.execute(
        'DELETE FROM athlete_state_refresh_queue WHERE athlete_id = ?',
        [athleteId],
      );
    });
    return state;
  }

  AthleteState? _readCurrent(String athleteId) {
    final rows = database.raw.select(
      '''SELECT snapshot.state_json
           FROM athlete_state_current current
           JOIN athlete_state_snapshot snapshot
             ON snapshot.id = current.snapshot_id
          WHERE current.athlete_id = ? AND snapshot.id GLOB 'athlete-state-xc-origin-v1-*'
            AND current.organization_id = ?''',
      [athleteId, organizationId],
    );
    if (rows.isEmpty) return null;
    final decoded = jsonDecode(rows.single['state_json'] as String);
    return AthleteState.fromJson(Map<String, Object?>.from(decoded as Map));
  }
}
