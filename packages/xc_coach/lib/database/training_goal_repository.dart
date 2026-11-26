/// Trainingsziele und Wochenverfügbarkeit eines Athleten in SQLite.
library;

import 'dart:convert';

import '../domain/training_plan.dart';
import '../intelligence/planning/planning_models.dart';
import 'giulia_database.dart';

class SqliteTrainingGoalRepository {
  const SqliteTrainingGoalRepository(this.database);

  final GiuliaDatabase database;

  /// Aktive Ziele, das wichtigste zuerst.
  List<TrainingGoal> goalsOf(String athleteId) => database.raw
      .select(
        '''SELECT * FROM training_goal
            WHERE athlete_id = ? AND archived_at_utc_us IS NULL
            ORDER BY priority, goal_date''',
        [athleteId],
      )
      .map(_goal)
      .whereType<TrainingGoal>()
      .toList(growable: false);

  /// Legt ein Ziel an oder überschreibt es (gleiche [TrainingGoal.id]).
  void saveGoal(
    TrainingGoal goal, {
    required String id,
    required String organizationId,
    required String athleteId,
    required int nowUtcUs,
  }) => database.raw.execute(
    '''INSERT INTO training_goal(
         id, organization_id, athlete_id, name, kind, modality, goal_date,
         distance_km, target_seconds, priority, created_at_utc_us,
         updated_at_utc_us)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET
         name = excluded.name, kind = excluded.kind,
         modality = excluded.modality, goal_date = excluded.goal_date,
         distance_km = excluded.distance_km,
         target_seconds = excluded.target_seconds,
         priority = excluded.priority,
         updated_at_utc_us = excluded.updated_at_utc_us,
         sync_state = 'pending'
       WHERE training_goal.athlete_id = excluded.athlete_id''',
    [
      id,
      organizationId,
      athleteId,
      goal.name,
      goal.kind.name,
      goal.modality.name,
      goal.day?.key,
      goal.distanceKm,
      goal.targetSeconds,
      goal.priority.name,
      nowUtcUs,
      nowUtcUs,
    ],
  );

  void archiveGoal(String id, {required int nowUtcUs}) => database.raw.execute(
    '''UPDATE training_goal
          SET archived_at_utc_us = ?, updated_at_utc_us = ?,
              sync_state = 'pending'
        WHERE id = ?''',
    [nowUtcUs, nowUtcUs, id],
  );

  /// Null, solange der Athlet nichts eingetragen hat.
  WeeklyAvailability? availabilityOf(String athleteId) {
    final rows = database.raw.select(
      'SELECT * FROM training_availability WHERE athlete_id = ? ORDER BY weekday',
      [athleteId],
    );
    if (rows.isEmpty) return null;
    return WeeklyAvailability([
      for (final row in rows)
        WeekdayAvailability(
          weekday: row['weekday'] as int,
          minutes: row['minutes'] as int,
          modalities: {
            for (final name
                in jsonDecode(row['modalities_json'] as String) as List)
              ?TrainingModality.values
                  .where((item) => item.name == name)
                  .firstOrNull,
          },
          restDay: (row['rest_day'] as int) != 0,
          longDay: (row['long_day'] as int) != 0,
        ),
    ]);
  }

  void saveAvailability(
    WeeklyAvailability availability, {
    required String organizationId,
    required String athleteId,
    required int nowUtcUs,
  }) => database.transaction(() {
    for (final day in availability.days) {
      database.raw.execute(
        '''INSERT INTO training_availability(
             organization_id, athlete_id, weekday, minutes, modalities_json,
             rest_day, long_day, updated_at_utc_us)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(athlete_id, weekday) DO UPDATE SET
             minutes = excluded.minutes,
             modalities_json = excluded.modalities_json,
             rest_day = excluded.rest_day, long_day = excluded.long_day,
             updated_at_utc_us = excluded.updated_at_utc_us,
             sync_state = 'pending' ''',
        [
          organizationId,
          athleteId,
          day.weekday,
          day.minutes,
          jsonEncode([for (final item in day.modalities) item.name]),
          day.restDay ? 1 : 0,
          day.longDay ? 1 : 0,
          nowUtcUs,
        ],
      );
    }
  });

  static TrainingGoal? _goal(Map<String, Object?> row) {
    final modality = TrainingModality.values
        .where((item) => item.name == row['modality'])
        .firstOrNull;
    if (modality == null) return null;
    final date = row['goal_date'] as String?;
    return TrainingGoal(
      id: row['id'] as String,
      name: row['name'] as String,
      kind:
          GoalKind.values
              .where((item) => item.name == row['kind'])
              .firstOrNull ??
          GoalKind.general,
      priority:
          GoalPriority.values
              .where((item) => item.name == row['priority'])
              .firstOrNull ??
          GoalPriority.a,
      day: date == null ? null : CalendarDay.parse(date),
      modality: modality,
      distanceKm: (row['distance_km'] as num?)?.toDouble(),
      targetSeconds: row['target_seconds'] as int?,
    );
  }
}
