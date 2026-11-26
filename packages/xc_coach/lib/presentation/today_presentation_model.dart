/// Reines Presenter-Modell für HEUTE (Entscheidungsebene).
///
/// WICHTIGE ARCHITEKTUR-REGEL:
/// - Presentation entscheidet NICHT.
/// - Formatiert die gefrorene [DailyCoachingDecision].
/// - Übersetzt die Entscheidung in Action + 3-4 Gründe («Warum heute?»),
///   die semantisch auf die 4 Bereiche in ATHLET verweisen können.
library;

import '../domain/xc_modality.dart';
import '../intelligence/training_need/need_types.dart';
import '../intelligence/workout_selection/daily_coaching_decision.dart';
import 'canonical_terminology.dart';

class DecisionWhyReason {
  const DecisionWhyReason({
    required this.text,
    required this.targetSectionAnchor, // z. B. 'load_and_recovery', 'performance', 'xc_specificity'
  });

  final String text;
  final String targetSectionAnchor;
}

class TodayPresentationModel {
  const TodayPresentationModel({
    required this.actionTitle,
    required this.actionSubtitle,
    required this.modalityLabel,
    required this.modality,
    required this.durationMinutes,
    required this.intensityLabel,
    required this.structureDescription,
    required this.isRestDay,
    required this.isActiveRecovery,
    required this.isErcolinaStartable,
    required this.templateId,
    required this.whyReasons,
    required this.safetyWarnings,
    required this.confidenceLabel,
    required this.dataLimitations,
  });

  final String actionTitle;
  final String actionSubtitle;
  final String modalityLabel;
  final XcModality modality;
  final int durationMinutes;
  final String intensityLabel;
  final String structureDescription;
  final bool isRestDay;
  final bool isActiveRecovery;
  final bool isErcolinaStartable;
  final String? templateId;
  final List<DecisionWhyReason> whyReasons;
  final List<String> safetyWarnings;
  final String confidenceLabel;
  final List<String> dataLimitations;

  factory TodayPresentationModel.fromDecision({
    required DailyCoachingDecision decision,
  }) {
    final workout = decision.prescribedWorkout;
    final isRest = decision.actionType == CoachingActionType.restDay;
    final isRec = decision.actionType == CoachingActionType.activeRecovery;

    final actionTitle = isRest
        ? 'Ruhetag'
        : (workout?.title ?? 'Training');

    final actionSubtitle = isRest
        ? 'Regeneration und Anpassung'
        : (isRec ? 'Aktive Wiederherstellung' : 'Gezielte Trainingseinheit');

    final modality = workout?.modality ?? XcModality.skiSkating;
    final modalityLabel = isRest ? 'Erholung' : modality.label;
    final duration = workout?.totalDurationMinutes ?? 0;

    final String intensityLabel;
    if (isRest || isRec) {
      intensityLabel = 'Sehr locker · regenerativ';
    } else if (workout != null) {
      final desc = workout.workIntensity.zoneLabel.toLowerCase();
      if (desc.contains('vo2') || desc.contains('hit') || desc.contains('power')) {
        intensityLabel = 'Sehr hart · fordernd';
      } else if (desc.contains('schwelle') || desc.contains('eb')) {
        intensityLabel = 'Kontrolliert hart';
      } else if (desc.contains('kraft') || desc.contains('zügig')) {
        intensityLabel = 'Moderat · zügig';
      } else {
        intensityLabel = 'Locker · kontrolliert';
      }
    } else {
      intensityLabel = 'Locker · kontrolliert';
    }

    final structure = workout?.structureDescription ??
        (isRest ? 'Keine Trainingsbelastung vorgesehen.' : 'Gleichmäßiges Tempo');

    final isErcolina = modality == XcModality.ercolinaDoublePoling;

    // Warum heute? Aufbereitet in max 3–4 Gründe mit Verweisen
    final reasons = <DecisionWhyReason>[];
    reasons.add(DecisionWhyReason(
      text: decision.coachingReason,
      targetSectionAnchor: 'load_and_recovery',
    ));

    if (decision.primaryNeed != null) {
      final needDesc = decision.primaryNeed!.reasons.isNotEmpty
          ? decision.primaryNeed!.reasons.first
          : decision.primaryNeed!.type.label;
      reasons.add(DecisionWhyReason(
        text: 'Bedarf: $needDesc',
        targetSectionAnchor: 'performance',
      ));
    }

    if (decision.safetyConstraintsApplied.isNotEmpty) {
      final sc = decision.safetyConstraintsApplied.first;
      reasons.add(DecisionWhyReason(
        text: 'Schutzregel: ${sc.reason}',
        targetSectionAnchor: 'load_and_recovery',
      ));
    }

    final safety = [
      for (final sc in decision.safetyConstraintsApplied) sc.reason,
    ];

    final confLabel = switch (decision.confidence) {
      NeedConfidence.high => CanonicalTerminology.confidenceHigh,
      NeedConfidence.moderate => CanonicalTerminology.confidenceModerate,
      NeedConfidence.low => CanonicalTerminology.confidenceLow,
      NeedConfidence.unknown => CanonicalTerminology.confidenceUnknown,
    };

    return TodayPresentationModel(
      actionTitle: actionTitle,
      actionSubtitle: actionSubtitle,
      modalityLabel: modalityLabel,
      modality: modality,
      durationMinutes: duration,
      intensityLabel: intensityLabel,
      structureDescription: structure,
      isRestDay: isRest,
      isActiveRecovery: isRec,
      isErcolinaStartable: isErcolina,
      templateId: workout?.templateId,
      whyReasons: reasons,
      safetyWarnings: safety,
      confidenceLabel: confLabel,
      dataLimitations: decision.dataLimitations,
    );
  }
}
