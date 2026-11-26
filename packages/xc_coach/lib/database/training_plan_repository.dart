/// Plan und Coach-Entscheidungen in SQLite.
///
/// Jede Änderung an einer geplanten Einheit wird zusammen mit ihrer
/// Entscheidung geschrieben, in einer Transaktion. Ohne Entscheidung gibt es
/// keine Änderung.
library;

import 'dart:convert';

import '../domain/coach_decision.dart';
import '../domain/training_plan.dart';
import 'giulia_database.dart';

class SqliteTrainingPlanRepository implements TrainingPlanReader {
  const SqliteTrainingPlanRepository(this.database);

  final GiuliaDatabase database;

  @override
  TrainingPlan planOf(String athleteId, {CalendarDay? from, CalendarDay? to}) {
    final rows = database.raw.select(
      '''SELECT * FROM xc_planned_workout
          WHERE athlete_id = ? AND planned_date >= ? AND planned_date <= ?
          ORDER BY planned_date, created_at_utc_us''',
      [athleteId, from?.key ?? '0000-00-00', to?.key ?? '9999-99-99'],
    );
    return TrainingPlan(
      athleteId: athleteId,
      workouts: [for (final row in rows) _workout(row)],
    );
  }

  PlannedWorkout? byId(String id) {
    final rows = database.raw.select(
      'SELECT * FROM xc_planned_workout WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : _workout(rows.first);
  }

  /// Die geplante Einheit, die [sessionId] erfüllt, oder null.
  PlannedWorkout? bySession(String sessionId) {
    final rows = database.raw.select(
      'SELECT * FROM xc_planned_workout WHERE session_id = ?',
      [sessionId],
    );
    return rows.isEmpty ? null : _workout(rows.first);
  }

  @override
  List<CoachDecision> decisionsOf(String athleteId, {int limit = 20}) =>
      database.raw
          .select(
            '''SELECT * FROM coach_decision WHERE athlete_id = ?
                AND id NOT IN (SELECT id FROM xc_restricted_decision)
                ORDER BY decided_at_utc_us DESC, rowid DESC LIMIT ?''',
            [athleteId, limit],
          )
          .map(_decision)
          .toList(growable: false);

  /// Legt eine neue Einheit an.
  void plan(PlannedWorkout workout, {required CoachDecision decision}) {
    _requireDecision(decision, workout, CoachDecisionType.planned);
    database.transaction(() {
      database.raw.execute(
        '''INSERT INTO planned_workout(
             id, organization_id, athlete_id, planned_date, sport, goal,
             duration_seconds, intensity, blueprint_id, structure_json, status,
             session_id, created_by_user_id, created_at_utc_us,
             updated_at_utc_us)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          workout.id,
          workout.organizationId,
          workout.athleteId,
          workout.day.key,
          workout.sport,
          workout.goal,
          workout.durationSeconds,
          workout.intensity,
          workout.blueprintId,
          jsonEncode([for (final step in workout.structure) step.toJson()]),
          workout.status.name,
          workout.sessionId,
          workout.createdByUserId,
          workout.createdAtUtcUs,
          workout.updatedAtUtcUs,
        ],
      );
      _insertDecision(decision);
    });
  }

  /// Markiert eine offene Einheit als ausgelassen.
  void skip(String plannedWorkoutId, {required CoachDecision decision}) {
    final workout = _require(plannedWorkoutId);
    _requireDecision(decision, workout, CoachDecisionType.skipped);
    if (!workout.isOpen) {
      throw StateError('Nur eine offene Einheit kann ausgelassen werden.');
    }
    if (workout.isStarted) {
      throw StateError(
        'Eine begonnene Einheit ist nicht ausgelassen; sie hat eine Session.',
      );
    }
    database.transaction(() {
      _setStatus(
        workout.id,
        PlannedWorkoutStatus.skipped,
        null,
        decision.decidedAtUtcUs,
      );
      _insertDecision(decision);
    });
  }

  /// Ordnet eine bereits beendete Session nachträglich zu – nur auf
  /// ausdrückliche Bestätigung. Der Status folgt aus dem Plan-Ist-Vergleich.
  PlanActual linkSession(
    String plannedWorkoutId,
    ActualSession session, {
    required CoachDecision decision,
  }) {
    final workout = _require(plannedWorkoutId);
    _requireDecision(decision, workout, CoachDecisionType.sessionLinked);
    if (!workout.isOpen || workout.isStarted) {
      throw StateError('Nur eine offene, nicht begonnene Einheit.');
    }
    if (session.athleteId != workout.athleteId) {
      throw ArgumentError('Die Session gehört zu einem anderen Athleten.');
    }
    final row = _ownedSession(workout, session.sessionId);
    if (row['ended_at_utc_us'] == null) {
      throw StateError('Nur eine beendete Session kann zugeordnet werden.');
    }
    final comparison = PlanActual(planned: workout, actual: session);
    database.transaction(() {
      _setStatus(
        workout.id,
        comparison.statusAfterLink,
        session.sessionId,
        decision.decidedAtUtcUs,
      );
      _insertDecision(decision);
    });
    return PlanActual(planned: _require(workout.id), actual: session);
  }

  /// Hält fest, dass TRAIN [sessionId] aus dieser Einheit gestartet hat –
  /// sofort beim Start, damit die Verbindung jeden Abbruch überlebt. Der
  /// Status bleibt offen, bis die Session beendet ist.
  void attachStartedSession(
    String plannedWorkoutId,
    String sessionId, {
    required CoachDecision decision,
  }) {
    final workout = _require(plannedWorkoutId);
    if (workout.sessionId == sessionId) return;
    _requireDecision(decision, workout, CoachDecisionType.sessionStarted);
    if (!workout.isOpen || workout.isStarted) {
      throw StateError('Diese Einheit ist bereits begonnen oder erledigt.');
    }
    final row = _ownedSession(workout, sessionId);
    if (row['ended_at_utc_us'] != null) {
      throw StateError('Die Session ist bereits beendet.');
    }
    final sport = (row['movement_type'] as String?) ?? '';
    if (!sameSport(workout.sport, sport)) {
      throw ArgumentError(
        'Die Session ($sport) passt nicht zur geplanten Sportart '
        '(${workout.sport}).',
      );
    }
    database.transaction(() {
      _setStatus(
        workout.id,
        PlannedWorkoutStatus.planned,
        sessionId,
        decision.decidedAtUtcUs,
      );
      _insertDecision(decision);
    });
  }

  /// Schließt die aus einer Einheit gestartete Session ab: Status aus dem
  /// Plan-Ist-Vergleich. Null, wenn die Session aus keiner Einheit stammt.
  PlanActual? completeStartedSession(
    ActualSession session, {
    required CoachDecision Function(PlannedWorkout workout, PlanActual result)
    decision,
  }) {
    final workout = bySession(session.sessionId);
    if (workout == null || !workout.isStarted) return null;
    if (session.athleteId != workout.athleteId) {
      throw ArgumentError('Die Session gehört zu einem anderen Athleten.');
    }
    final comparison = PlanActual(planned: workout, actual: session);
    final recorded = decision(workout, comparison);
    _requireDecision(recorded, workout, CoachDecisionType.sessionCompleted);
    database.transaction(() {
      _setStatus(
        workout.id,
        comparison.statusAfterLink,
        session.sessionId,
        recorded.decidedAtUtcUs,
      );
      _insertDecision(recorded);
    });
    return PlanActual(planned: _require(workout.id), actual: session);
  }

  Map<String, Object?> _ownedSession(PlannedWorkout workout, String sessionId) {
    final rows = database.raw.select(
      '''SELECT athlete_id, movement_type, ended_at_utc_us FROM xc_session
          WHERE id = ?''',
      [sessionId],
    );
    if (rows.isEmpty || rows.first['athlete_id'] != workout.athleteId) {
      throw ArgumentError('Die Session gehört zu einem anderen Athleten.');
    }
    return rows.first;
  }

  PlannedWorkout _require(String id) =>
      byId(id) ?? (throw StateError('Geplante Einheit $id fehlt.'));

  void _requireDecision(
    CoachDecision decision,
    PlannedWorkout workout,
    CoachDecisionType type,
  ) {
    if (decision.type != type ||
        decision.athleteId != workout.athleteId ||
        !decision.plannedWorkoutIds.contains(workout.id)) {
      throw ArgumentError(
        'Die Entscheidung passt nicht zu dieser Änderung des Plans.',
      );
    }
  }

  void _setStatus(
    String id,
    PlannedWorkoutStatus status,
    String? sessionId,
    int nowUtcUs,
  ) => database.raw.execute(
    '''UPDATE planned_workout
          SET status = ?, session_id = COALESCE(?, session_id),
              updated_at_utc_us = ?, sync_state = 'pending'
        WHERE id = ?''',
    [status.name, sessionId, nowUtcUs, id],
  );

  void _insertDecision(CoachDecision decision) => database.raw.execute(
    '''INSERT INTO coach_decision(
         id, organization_id, athlete_id, decided_at_utc_us, decision_type,
         decided_by, decided_by_user_id, planned_workout_ids_json, facts_json,
         change_json, reason, data_quality)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
    [
      decision.author == CoachDecisionAuthor.giulia ? 'xc-origin-v1-${decision.id}' : decision.id,
      decision.organizationId,
      decision.athleteId,
      decision.decidedAtUtcUs,
      decision.type.name,
      decision.author.name,
      decision.decidedByUserId,
      jsonEncode(decision.plannedWorkoutIds),
      jsonEncode([for (final fact in decision.facts) fact.toJson()]),
      jsonEncode(decision.change),
      decision.reason,
      decision.dataQuality,
    ],
  );

  static PlannedWorkout _workout(Map<String, Object?> row) => PlannedWorkout(
    id: row['id'] as String,
    organizationId: row['organization_id'] as String,
    athleteId: row['athlete_id'] as String,
    day: CalendarDay.parse(row['planned_date'] as String),
    sport: row['sport'] as String,
    goal: row['goal'] as String,
    durationSeconds: row['duration_seconds'] as int,
    intensity: row['intensity'] as String?,
    blueprintId: row['blueprint_id'] as String?,
    structure: [
      for (final step in jsonDecode(row['structure_json'] as String) as List)
        PlannedStep.fromJson(Map<String, Object?>.from(step as Map)),
    ],
    status: PlannedWorkoutStatus.values.byName(row['status'] as String),
    sessionId: row['session_id'] as String?,
    createdByUserId: row['created_by_user_id'] as String?,
    createdAtUtcUs: row['created_at_utc_us'] as int,
    updatedAtUtcUs: row['updated_at_utc_us'] as int,
  );

  static CoachDecision _decision(Map<String, Object?> row) => CoachDecision(
    id: (row['id'] as String).replaceFirst(RegExp(r'^xc-origin-v1-'), ''),
    organizationId: row['organization_id'] as String,
    athleteId: row['athlete_id'] as String,
    decidedAtUtcUs: row['decided_at_utc_us'] as int,
    type: CoachDecisionType.values.byName(row['decision_type'] as String),
    author: CoachDecisionAuthor.values.byName(row['decided_by'] as String),
    decidedByUserId: row['decided_by_user_id'] as String?,
    plannedWorkoutIds: [
      for (final id
          in jsonDecode(row['planned_workout_ids_json'] as String) as List)
        id as String,
    ],
    facts: [
      for (final fact in jsonDecode(row['facts_json'] as String) as List)
        CoachFactRef.fromJson(Map<String, Object?>.from(fact as Map)),
    ],
    change: Map<String, Object?>.from(
      jsonDecode(row['change_json'] as String) as Map,
    ),
    reason: row['reason'] as String,
    dataQuality: row['data_quality'] as String?,
  );
}
