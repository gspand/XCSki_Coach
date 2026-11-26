import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/training_plan.dart';
import '../intelligence/workout_selection/daily_coaching_decision.dart';

enum QualitativeIntensityLevel {
  easy('Locker · kontrolliert'),
  moderate('Moderat · zügig'),
  controlledHard('Kontrolliert hart'),
  veryHard('Sehr hart · fordernd'),
  allOut('Maximal'),
  recovery('Sehr locker · regenerativ');

  const QualitativeIntensityLevel(this.label);
  final String label;
}

/// All clients publish the same projection of a decision.
extension DecisionCard on DailyCoachingDecision {
  String get decisionId =>
      '$athleteId/${CalendarDay.ofLocal(decisionDate.toLocal()).key}';
  static const algorithmVersion = 'xc-day-1';

  String get decisionVersion {
    final fields = toJson()..remove('decisionDate');
    // Source timestamps remain evidence. Only computation-clock fields and
    // generated candidate/need identifiers are independent of the content.
    (fields['prescribedWorkout'] as Map?)?.remove('id');
    (fields['primaryNeed'] as Map?)?.remove('id');
    for (final key in ['secondaryNeeds', 'safetyConstraintsApplied']) {
      for (final item in fields[key] as List) {
        (item as Map).remove('id');
      }
    }
    final female = fields['femaleContext'] as Map?;
    for (final key in ['cycleContext', 'healthContext']) {
      (female?[key] as Map?)?.remove('asOf');
    }
    return sha256
        .convert(
          utf8.encode(jsonEncode([algorithmVersion, decisionId, fields])),
        )
        .toString();
  }

  String get displayTitle => switch (actionType) {
    CoachingActionType.restDay => 'Ruhetag',
    CoachingActionType.activeRecovery =>
      prescribedWorkout?.title ?? 'Aktive Erholung',
    CoachingActionType.diagnosticSession =>
      prescribedWorkout?.title ?? 'Leistungsdiagnostik',
    CoachingActionType.prescribedWorkout =>
      prescribedWorkout?.title ?? 'Training',
  };
  int get displayMinutes => actionType == CoachingActionType.restDay
      ? 0
      : prescribedWorkout?.totalDurationMinutes ?? 0;
  String get displayModality =>
      prescribedWorkout?.modality.label ??
      (actionType == CoachingActionType.restDay ||
              actionType == CoachingActionType.activeRecovery
          ? 'Regeneration'
          : 'Offen');
  String get displayStructure =>
      prescribedWorkout?.structureDescription ??
      (actionType == CoachingActionType.restDay
          ? 'Keine Trainingsbelastung vorgesehen.'
          : 'Keine feste Einheit vorgegeben.');

  QualitativeIntensityLevel get displayIntensity {
    if (actionType == CoachingActionType.restDay ||
        actionType == CoachingActionType.activeRecovery) {
      return QualitativeIntensityLevel.recovery;
    }
    final zone = prescribedWorkout?.workIntensity.zoneLabel.toLowerCase() ?? '';
    if (zone.contains('vo2') || zone.contains('hit') || zone.contains('power'))
      return QualitativeIntensityLevel.veryHard;
    if (zone.contains('schwelle') || zone.contains('eb'))
      return QualitativeIntensityLevel.controlledHard;
    if (zone.contains('kraft') || zone.contains('zügig'))
      return QualitativeIntensityLevel.moderate;
    return QualitativeIntensityLevel.easy;
  }
}
