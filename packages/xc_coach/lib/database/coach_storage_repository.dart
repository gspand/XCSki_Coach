/// Dauerhafter Speicher für das End-to-End Coaching-System von GIULIA:
/// - Strava Sync-Status & Tokens
/// - Kanonische NormalizedSessions
/// - Athleten Check-Ins & Overrides
/// - Coach Entscheidungen & Validation Records
/// - Coach Chat-Verlauf
library;

import '../domain/xc_modality.dart';
import '../presentation/decision_card.dart';
import '../intelligence/training_need/need_types.dart';
import 'dart:convert';

import '../domain/normalized_session.dart';
import '../domain/normalized_session_stream_analysis.dart';
import '../external_data/strava/strava_client.dart';
import '../intelligence/workout_selection/coach_validation_mode.dart';
import '../intelligence/workout_selection/daily_coaching_decision.dart';
import '../intelligence/workout_selection/user_override_context.dart';
import '../intelligence/xc_athlete_state/subjective_readiness_state.dart';
import 'giulia_database.dart';

class StravaSyncState {
  const StravaSyncState({
    required this.athleteId,
    required this.config,
    this.lastSyncAtUtcUs,
    this.coveredFromUtcUs,
    this.coveredToUtcUs,
    this.lastError,
  });

  final String athleteId;
  final StravaConfig config;
  final int? lastSyncAtUtcUs;
  final int? coveredFromUtcUs;
  final int? coveredToUtcUs;
  final String? lastError;

  bool get isConnected => config.isConnected;

  StravaSyncState copyWith({
    StravaConfig? config,
    int? lastSyncAtUtcUs,
    int? coveredFromUtcUs,
    int? coveredToUtcUs,
    String? lastError,
  }) => StravaSyncState(
    athleteId: athleteId,
    config: config ?? this.config,
    lastSyncAtUtcUs: lastSyncAtUtcUs ?? this.lastSyncAtUtcUs,
    coveredFromUtcUs: coveredFromUtcUs ?? this.coveredFromUtcUs,
    coveredToUtcUs: coveredToUtcUs ?? this.coveredToUtcUs,
    lastError: lastError,
  );
}

typedef CoachChatMessage = ({
  String id,
  String sender,
  String text,
  Map<String, dynamic>? structured,
  int createdAtUtcUs,
});

class SqliteCoachStorageRepository {
  const SqliteCoachStorageRepository(this.database);

  final GiuliaDatabase database;

  // ==========================================
  // STRAVA SYNC STATE
  // ==========================================

  // Historical credentials do not enter the standalone application's runtime.
  StravaSyncState? getStravaSyncState(String athleteId) => null;

  void saveStravaSyncState(StravaSyncState state, {required int nowUtcUs}) {
    throw UnsupportedError('Strava ist für XC Ski Coach nicht freigegeben.');
  }

  void disconnectStrava(String athleteId, {required int nowUtcUs}) {
    database.raw.execute(
      '''DELETE FROM strava_sync_state WHERE athlete_id = ?''',
      [athleteId],
    );
  }

  // ==========================================
  // NORMALIZED SESSIONS
  // ==========================================

  /// Ob diese Quelleinheit schon im Coach-Bestand liegt.
  ///
  /// Der Backfill laeuft bei jedem Start. Ohne diese Frage muesste er fuer
  /// jede Sitzung die Zuege lesen, nur um festzustellen, dass sie laengst
  /// normalisiert ist.
  bool hasNormalizedSession({
    required String athleteId,
    required NormalizedSessionSource source,
    required String sourceId,
  }) => database.raw.select(
    'SELECT 1 FROM xc_normalized_session '
    'WHERE athlete_id = ? AND source = ? AND source_id = ? LIMIT 1',
    [athleteId, source.key, sourceId],
  ).isNotEmpty;

  Map<String,dynamic>? savedStreams(String athleteId, NormalizedSessionSource source, String sourceId) {
    final rows=database.raw.select("SELECT json_extract(data_json, '\$.rawMetadata.streams') AS streams FROM xc_normalized_session WHERE athlete_id=? AND source=? AND source_id=?",[athleteId,source.key,sourceId]);
    final raw=rows.firstOrNull?['streams'] as String?;
    return raw==null ? null : jsonDecode(raw) as Map<String,dynamic>;
  }

  void saveNormalizedSession(
    NormalizedSession session, {
    required int nowUtcUs,
  }) {
    if (!session.eligibleForCoach ||
        (session.sourceId.startsWith('fit:') &&
          database.raw.select(
            "SELECT 1 FROM app_state WHERE key=? AND value IN ('recordingDevice','garminConnect')",
            ['xc.fitOrigin.${session.athleteId}.${session.sourceId}']).isEmpty) ||
        (session.source == NormalizedSessionSource.ercolina &&
         database.raw.select('SELECT 1 FROM xc_restricted_session WHERE session_id = ? LIMIT 1', [session.sourceId]).isNotEmpty)) {
      throw UnsupportedError('Strava ist für XC Ski Coach nicht freigegeben.');
    }
    database.raw.execute(
      '''INSERT INTO normalized_session_record(
           id, athlete_id, source, source_id, started_at_utc_us,
           duration_seconds, moving_time_seconds, modality, technique,
           provenance, is_indoor, title, data_json, created_at_utc_us,
           analysis_json
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(athlete_id, source, source_id) DO UPDATE SET
           started_at_utc_us = excluded.started_at_utc_us,
           duration_seconds = excluded.duration_seconds,
           moving_time_seconds = excluded.moving_time_seconds,
           modality = excluded.modality,
           technique = excluded.technique,
           provenance = excluded.provenance,
           is_indoor = excluded.is_indoor,
           title = excluded.title,
           data_json = excluded.data_json,
           analysis_json = excluded.analysis_json''',
      [
        session.id,
        session.athleteId,
        session.source.key,
        session.sourceId,
        session.startedAtUtcUs,
        session.durationSeconds,
        session.movingTimeSeconds,
        session.modality.key,
        session.technique.key,
        session.classificationProvenance.key,
        session.isIndoor ? 1 : 0,
        session.title,
        jsonEncode(session.toJson()),
        nowUtcUs,
        jsonEncode(compactNormalizedSessionForAnalysis(session.toJson())),
      ],
    );
  }

  List<NormalizedSession> loadNormalizedSessions(
    String athleteId, {
    int? fromUtcUs,
    int? toUtcUs,
    int? limit = 500,
  }) {
    final rows = database.raw.select(
      '''SELECT COALESCE(analysis_json, data_json) AS analysis_json
           FROM xc_normalized_session
          WHERE athlete_id = ?
            AND started_at_utc_us >= ?
            AND started_at_utc_us <= ?
          ORDER BY started_at_utc_us DESC
          LIMIT ?''',
      [athleteId, fromUtcUs ?? 0, toUtcUs ?? 9223372036854775807, limit ?? -1],
    );

    return rows
        .map(
          (r) =>
              jsonDecode(r['analysis_json'] as String) as Map<String, dynamic>,
        )
        .map(NormalizedSession.fromJson)
        .toList(growable: false);
  }

  // ==========================================
  // ATHLETE CHECK-IN (SUBJECTIVE READINESS)
  // ==========================================

  void saveCheckIn({
    required String athleteId,
    required SubjectiveReadinessState readiness,
    required int recordedAtUtcUs,
  }) {
    database.raw.execute(
      '''INSERT INTO athlete_check_in(
           id, athlete_id, recorded_at_utc_us, readiness_json, created_at_utc_us
         ) VALUES (?, ?, ?, ?, ?)''',
      [
        'checkin-$recordedAtUtcUs',
        athleteId,
        recordedAtUtcUs,
        jsonEncode(readiness.toJson()),
        recordedAtUtcUs,
      ],
    );
  }

  SubjectiveReadinessState? latestCheckIn(String athleteId, {DateTime? onDay}) {
    final local = onDay?.toLocal();
    final start = local == null ? 0 : DateTime(local.year,local.month,local.day).microsecondsSinceEpoch;
    final end = local == null ? 9223372036854775807 : DateTime(local.year,local.month,local.day+1).microsecondsSinceEpoch;
    final rows = database.raw.select(
      '''SELECT readiness_json FROM athlete_check_in
          WHERE athlete_id = ? AND recorded_at_utc_us >= ? AND recorded_at_utc_us < ?
          ORDER BY recorded_at_utc_us DESC LIMIT 1''',
      [athleteId,start,end],
    );
    if (rows.isEmpty) return null;
    final json =
        jsonDecode(rows.first['readiness_json'] as String)
            as Map<String, dynamic>;
    return SubjectiveReadinessState.fromJson(json);
  }

  // ==========================================
  // USER OVERRIDES
  // ==========================================

  void saveUserOverride({
    required String athleteId,
    required UserOverrideContext override,
    required int recordedAtUtcUs,
  }) {
    database.raw.execute(
      '''INSERT INTO athlete_user_override(
           id, athlete_id, recorded_at_utc_us, override_json, created_at_utc_us
         ) VALUES (?, ?, ?, ?, ?)''',
      [
        'override-$recordedAtUtcUs',
        athleteId,
        recordedAtUtcUs,
        jsonEncode(override.toJson()),
        recordedAtUtcUs,
      ],
    );
  }

  UserOverrideContext? latestUserOverride(String athleteId, {DateTime? onDay}) {
    final local = onDay?.toLocal();
    final start = local == null ? 0 : DateTime(local.year,local.month,local.day).microsecondsSinceEpoch;
    final end = local == null ? 9223372036854775807 : DateTime(local.year,local.month,local.day+1).microsecondsSinceEpoch;
    final rows = database.raw.select(
      '''SELECT override_json FROM athlete_user_override
          WHERE athlete_id = ? AND recorded_at_utc_us >= ? AND recorded_at_utc_us < ?
          ORDER BY recorded_at_utc_us DESC LIMIT 1''',
      [athleteId,start,end],
    );
    if (rows.isEmpty) return null;
    final json =
        jsonDecode(rows.first['override_json'] as String)
            as Map<String, dynamic>;
    return UserOverrideContext(
      preferredModality: XcModality.values.where((m) => m.name == json['preferredModality']).firstOrNull,
      excludedModalities: XcModality.values.where((m) => (json['excludedModalities'] as List?)?.contains(m.name) == true).toList(),
      focusNeed: TrainingNeedType.values.where((n) => n.name == json['focusNeed']).firstOrNull,
      forcedRestDay: json['forcedRestDay'] == true,
      maxAvailableMinutes: (json['maxAvailableMinutes'] as num?)?.toInt(),
      heavyLegs: json['heavyLegs'] == true,
      heavyArms: json['heavyArms'] == true,
      plannedTrainingBlockContext: json['plannedTrainingBlockContext']
          ?.toString(),
      notes: json['notes']?.toString(),
    );
  }

  // ==========================================
  // DAILY COACHING DECISION RECORDS
  // ==========================================

  void saveDailyDecision({
    required String athleteId,
    required DailyCoachingDecision decision,
    required int decidedAtUtcUs,
  }) {
    if (athleteId != decision.athleteId) {
      throw ArgumentError('Entscheidung gehört zu einem anderen Profil.');
    }
    final version = decision.decisionVersion;
    database.transaction(() {
      final previous = database.raw.select(
        """SELECT decision_json FROM coach_decision_record WHERE athlete_id = ?
           AND id GLOB 'xc-origin-v1-*' ORDER BY rowid DESC LIMIT 1""",
        [athleteId],
      );
      if (previous.isNotEmpty &&
          (jsonDecode(previous.single['decision_json'] as String) as Map)['decisionVersion'] == version) return;
      final document = {...decision.toJson(), 'decisionId': decision.decisionId,
        'decisionVersion': version, 'algorithmVersion': DecisionCard.algorithmVersion};
      database.raw.execute(
        """INSERT INTO coach_decision_record(
           id, athlete_id, decided_at_utc_us, decision_json, created_at_utc_us
         ) VALUES ('xc-origin-v1-' || lower(hex(randomblob(16))), ?, ?, ?, ?)""",
        [athleteId, decidedAtUtcUs, jsonEncode(document), decidedAtUtcUs],
      );
    });
  }

  DailyCoachingDecision? latestDailyDecision(String athleteId) {
    final rows = database.raw.select(
      '''SELECT decision_json FROM coach_decision_record
          WHERE athlete_id = ? AND id GLOB 'xc-origin-v1-*'
          ORDER BY decided_at_utc_us DESC, rowid DESC LIMIT 1''',
      [athleteId],
    );
    if (rows.isEmpty) return null;
    final json =
        jsonDecode(rows.first['decision_json'] as String)
            as Map<String, dynamic>;
    return DailyCoachingDecision.fromJson(json);
  }

  // ==========================================
  // COACH VALIDATION RECORDS (E2E FIELD TRIAL)
  // ==========================================

  void saveValidationRecord({
    required String athleteId,
    required CoachValidationRecord record,
    required int createdAtUtcUs,
  }) {
    database.raw.execute(
      '''INSERT INTO coach_validation_record_store(
           id, athlete_id, created_at_utc_us, record_json
         ) VALUES (?, ?, ?, ?)''',
      ['xc-origin-v1-${record.id}', athleteId, createdAtUtcUs, jsonEncode(record.toJson())],
    );
  }

  List<CoachValidationRecord> loadValidationRecords(
    String athleteId, {
    int limit = 50,
  }) {
    final rows = database.raw.select(
      '''SELECT record_json FROM coach_validation_record_store
          WHERE athlete_id = ? AND id GLOB 'xc-origin-v1-*'
          ORDER BY created_at_utc_us DESC LIMIT ?''',
      [athleteId, limit],
    );
    return rows
        .map(
          (r) => jsonDecode(r['record_json'] as String) as Map<String, dynamic>,
        )
        .map(CoachValidationRecord.fromJson)
        .toList(growable: false);
  }

  // ==========================================
  // COACH CHAT MESSAGES
  // ==========================================

  void saveChatMessage({
    required String athleteId,
    required String sender,
    required String text,
    Map<String, dynamic>? structured,
    required int createdAtUtcUs,
  }) {
    database.raw.execute(
      '''INSERT INTO coach_chat_message(
           id, athlete_id, sender, text, structured_json, created_at_utc_us
         ) VALUES (?, ?, ?, ?, ?, ?)''',
      [
        'xc-origin-v1-msg-$athleteId-$createdAtUtcUs',
        athleteId,
        sender,
        text,
        structured != null ? jsonEncode(structured) : null,
        createdAtUtcUs,
      ],
    );
  }

  List<CoachChatMessage> loadChatMessages(String athleteId, {int limit = 50}) {
    final rows = database.raw.select(
      '''SELECT id, sender, text, structured_json, created_at_utc_us
           FROM coach_chat_message
          WHERE athlete_id = ? AND id GLOB 'xc-origin-v1-*'
          ORDER BY created_at_utc_us DESC LIMIT ?''',
      [athleteId, limit],
    );
    return rows.reversed
        .map((r) {
          final s = r['structured_json'] as String?;
          return (
            id: r['id'] as String,
            sender: r['sender'] as String,
            text: r['text'] as String,
            structured: s != null
                ? jsonDecode(s) as Map<String, dynamic>
                : null,
            createdAtUtcUs: r['created_at_utc_us'] as int,
          );
        })
        .toList(growable: false);
  }
}
