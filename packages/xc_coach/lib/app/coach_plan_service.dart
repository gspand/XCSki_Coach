/// Plan-Änderungen aus der Oberfläche – immer mit Entscheidung.
library;

import '../domain/coach_decision.dart';
import '../domain/training_plan.dart';
import '../database/training_plan_repository.dart';
import '../workout_engine/workout_engine.dart';
import '../workout_engine/ercolina_canonical_blueprints.dart';
import '../workout_engine/workout_library.dart';

class CoachPlanService {
  CoachPlanService({
    required this.repository,
    required this.organizationId,
    required this.userId,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc().microsecondsSinceEpoch);

  final SqliteTrainingPlanRepository repository;
  final String organizationId;
  final String userId;
  final int Function() _clock;
  int _sequence = 0;

  String _id(String prefix, int now) => '$prefix-$now-${_sequence++}';

  /// Plant eine Einheit der Bibliothek für [day].
  PlannedWorkout planBlueprint({
    required String athleteId,
    required CalendarDay day,
    required String sport,
    required WorkoutBlueprint blueprint,
  }) {
    final now = _clock();
    final work = blueprint.steps.where(
      (step) => step.kind == WorkoutStepKind.work,
    );
    final main = (work.isEmpty ? blueprint.steps : work).fold<BlueprintStep?>(
      null,
      (best, step) => best == null || step.seconds > best.seconds ? step : best,
    );
    final workout = PlannedWorkout(
      id: _id('plan', now),
      organizationId: organizationId,
      athleteId: athleteId,
      day: day,
      sport: sport,
      goal: blueprint.purpose,
      durationSeconds: blueprint.duration.inSeconds,
      intensity: main?.intensity.name,
      blueprintId: blueprint.id,
      structure: [
        for (final step in blueprint.steps)
          PlannedStep(
            kind: step.kind.name,
            seconds: step.seconds,
            intensity: step.intensity.name,
          ),
      ],
      createdByUserId: userId,
      createdAtUtcUs: now,
      updatedAtUtcUs: now,
    );
    repository.plan(
      workout,
      decision: CoachDecision(
        id: _id('decision', now),
        organizationId: organizationId,
        athleteId: athleteId,
        decidedAtUtcUs: now,
        type: CoachDecisionType.planned,
        author: CoachDecisionAuthor.user,
        decidedByUserId: userId,
        plannedWorkoutIds: [workout.id],
        change: {'added': workout.toJson()},
        reason: 'Vom Nutzer geplant: ${blueprint.name}.',
      ),
    );
    return workout;
  }

  void skip(PlannedWorkout workout) {
    final now = _clock();
    repository.skip(
      workout.id,
      decision: CoachDecision(
        id: _id('decision', now),
        organizationId: organizationId,
        athleteId: workout.athleteId,
        decidedAtUtcUs: now,
        type: CoachDecisionType.skipped,
        author: CoachDecisionAuthor.user,
        decidedByUserId: userId,
        plannedWorkoutIds: [workout.id],
        change: {
          'status': {'from': workout.status.name, 'to': 'skipped'},
        },
        reason: 'Vom Nutzer als ausgelassen markiert.',
      ),
    );
  }

  PlanActual link(PlannedWorkout workout, ActualSession session) {
    final now = _clock();
    final comparison = PlanActual(planned: workout, actual: session);
    return repository.linkSession(
      workout.id,
      session,
      decision: CoachDecision(
        id: _id('decision', now),
        organizationId: organizationId,
        athleteId: workout.athleteId,
        decidedAtUtcUs: now,
        type: CoachDecisionType.sessionLinked,
        author: CoachDecisionAuthor.user,
        decidedByUserId: userId,
        plannedWorkoutIds: [workout.id],
        facts: [
          CoachFactRef(
            kind: 'session',
            id: session.sessionId,
            label: 'Dauer',
            value: session.durationSeconds,
            unit: 's',
          ),
        ],
        change: {
          'status': {
            'from': workout.status.name,
            'to': comparison.statusAfterLink.name,
          },
          'sessionId': session.sessionId,
          'durationDeltaSeconds': comparison.durationDeltaSeconds,
        },
        reason: 'Session vom Nutzer der geplanten Einheit zugeordnet.',
      ),
    );
  }
}

/// Die ausfuehrbare Einheit zu einer ID.
///
/// Zwei Bibliotheken, eine Aufloesung: die handgeschriebene [workoutLibrary]
/// und die kanonische Geraetebibliothek E0-E15. Letztere gewinnt nicht, sie
/// kommt danach — eine ID existiert immer nur in einer von beiden.
WorkoutBlueprint? blueprintById(String? id) {
  if (id == null) return null;
  return workoutLibrary.where((workout) => workout.id == id).firstOrNull ??
      canonicalBlueprintById(id);
}
