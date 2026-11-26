import 'package:xc_coach/app/canonical_today.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'package:xc_coach/presentation/decision_card.dart';
import 'package:xc_coach/intelligence/workout_selection/daily_coaching_decision.dart';

/// Only the released day card crosses the iPhone–watch boundary.
Map<String, Object> watchSnapshot(CanonicalToday today, String name) {
  final decision = today.decision;
  final local = decision.decisionDate.toLocal();
  final plan = today.plannedWorkout;
  return {
    'schema': 2,
    'kind': 'plan',
    'athleteId': decision.athleteId,
    'athlete': name,
    'decisionId': decision.decisionId,
    'decisionVersion': decision.decisionVersion,
    'algorithmVersion': DecisionCard.algorithmVersion,
    'planVersion': plan == null
        ? 'unplanned'
        : '${plan.id}/${plan.updatedAtUtcUs}',
    'date': CalendarDay.ofLocal(local).key,
    'timeZone': local.timeZoneName,
    'utcOffsetMinutes': local.timeZoneOffset.inMinutes,
    'generatedAtMs': local.millisecondsSinceEpoch,
    'validUntilMs': DateTime(
      local.year,
      local.month,
      local.day + 1,
    ).millisecondsSinceEpoch,
    'title': decision.displayTitle,
    'minutes': decision.displayMinutes,
    'intensity': decision.displayIntensity.label,
    // The phone's explanation can include symptoms and private notes.
    // A release of the workout does not include those fields.
    'reason': switch (decision.actionType) {
      CoachingActionType.restDay => 'Heute ist Zeit für Erholung vorgesehen.',
      CoachingActionType.activeRecovery =>
        'Heute steht aktive Erholung im Plan.',
      CoachingActionType.diagnosticSession =>
        'Die Einheit dient der Leistungsdiagnostik.',
      CoachingActionType.prescribedWorkout =>
        decision.prescribedWorkout?.workIntensity.workoutIntent.isNotEmpty ==
                true
            ? decision.prescribedWorkout!.workIntensity.workoutIntent
            : 'Die Einheit entspricht dem heutigen Trainingsbedarf.',
    },
    'structure': decision.displayStructure,
  };
}
