/// View Model für den neuen GIULIA HEUTE-Screen.
///
/// WICHTIGE ARCHITEKTUR-LEITPLANKEN:
/// - Das ViewModel berechnet KEINE eigene Trainingslogik und trifft KEINE Entscheidungen.
/// - Es formatiert ausschließlich die Daten aus dem gefrorenen Core:
///   [DailyCoachingDecision], [XCAthleteState], [TrainingNeedResult] und [DayAvailability].
/// - Übersetzt Fach- und State-Daten in ruhige, verständliche deutsche Aussagen
///   für die 4 Ebenen: ACTION, WHY, CONTEXT, EVIDENCE.
library;

import '../../domain/xc_modality.dart';
import '../../intelligence/training_need/need_types.dart';
import '../../intelligence/training_need/safety_constraint.dart';
import '../../intelligence/workout_selection/availability_context.dart';
import '../../intelligence/workout_selection/daily_coaching_decision.dart';
import '../../intelligence/xc_athlete_state/xc_athlete_state.dart';
import '../../presentation/today_presentation_model.dart';

import '../../presentation/decision_card.dart';
export '../../presentation/decision_card.dart' show QualitativeIntensityLevel;

/// Strukturierte Phasenaufteilung einer Einheit.
class WorkoutPhaseView {
  const WorkoutPhaseView({
    required this.warmupMinutes,
    required this.workMinutes,
    required this.cooldownMinutes,
  });

  final int warmupMinutes;
  final int workMinutes;
  final int cooldownMinutes;

  String get summaryText =>
      'Warm-up ${warmupMinutes}m · Hauptteil ${workMinutes}m · Cool-down ${cooldownMinutes}m';
}

/// Repräsentation einer sicheren Alternative für «Heute anders trainieren?».
class SafeAlternativeView {
  const SafeAlternativeView({
    required this.title,
    required this.modality,
    required this.modalityLabel,
    required this.durationMinutes,
    required this.filterStageText,
    required this.reasonText,
    required this.isRestDay,
  });

  final String title;
  final XcModality modality;
  final String modalityLabel;
  final int durationMinutes;
  final String filterStageText;
  final String reasonText;
  final bool isRestDay;
}

/// Strukturierte Ansicht des Tages für den TodayScreen.
class TodayViewModel {
  const TodayViewModel({
    this.decisionId,
    this.decisionVersion,
    required this.greetingName,
    required this.coachPunchline,
    required this.actionType,
    required this.heroTitle,
    required this.modalityLabel,
    required this.modality,
    required this.durationMinutes,
    required this.qualitativeIntensity,
    required this.structureText,
    required this.phases,
    required this.terrainGuidance,
    required this.talkTestCue,
    required this.effortGuidance,
    required this.secondaryIntensityCue,
    required this.whyTodayText,
    this.whyReasons = const [],
    required this.importantNotes,
    required this.hasActiveSafetyConstraint,
    required this.dataLimitations,
    required this.confidenceLabel,
    required this.isErcolinaStartable,
    required this.safeAlternatives,
    required this.nextDaysOutlook,
    required this.evidenceTrace,
  });

  /// Begrüßung: «Guten Morgen, Jan»
  final String greetingName;
  final String? decisionId;
  final String? decisionVersion;

  /// Ruhige Coach-Zeile: «Heute bauen wir weiter an deiner Ausdauer.»
  final String coachPunchline;

  /// Aktionstyp: Workout, Aktive Erholung oder Ruhetag
  final CoachingActionType actionType;

  // --- EBENE 1: ACTION ---
  final String heroTitle;
  final String modalityLabel;
  final XcModality modality;
  final int durationMinutes;
  final QualitativeIntensityLevel qualitativeIntensity;
  final String structureText;
  final WorkoutPhaseView phases;
  final String? terrainGuidance;
  final String talkTestCue;
  final String effortGuidance;
  final String? secondaryIntensityCue;
  final bool isErcolinaStartable;

  // --- EBENE 2: WHY ---
  final String whyTodayText;
  final List<DecisionWhyReason> whyReasons;

  // --- EBENE 3: CONTEXT ---
  final List<String> importantNotes;
  final bool hasActiveSafetyConstraint;
  final List<String> dataLimitations;
  final String confidenceLabel;
  final List<SafeAlternativeView> safeAlternatives;
  final List<String> nextDaysOutlook;

  // --- EBENE 4: EVIDENCE ---
  final Map<String, String> evidenceTrace;

  bool get isRestDay => actionType == CoachingActionType.restDay;
  bool get isActiveRecovery => actionType == CoachingActionType.activeRecovery;

  /// Factory, die aus der reinen Decision und den Kontextobjekten formatiert.
  factory TodayViewModel.fromDecision({
    required DailyCoachingDecision decision,
    required XCAthleteState state,
    DayAvailability? availability,
    String athleteName = 'Athlet',
  }) {
    final workout = decision.prescribedWorkout;
    final isRest = decision.actionType == CoachingActionType.restDay;
    final isRec = decision.actionType == CoachingActionType.activeRecovery;

    // 1. Coach Punchline (ruhige, intelligente Coaching-Aussage)
    final String punchline;
    if (isRest) {
      if (decision.safetyConstraintsApplied.any((c) => c.severity == SafetyConstraintSeverity.severe || c.severity == SafetyConstraintSeverity.critical)) {
        punchline = 'Heute steht deine Gesundheit und Regeneration an erster Stelle.';
      } else {
        punchline = 'Heute darf es ruhig sein. Zeit für vollständige Erholung.';
      }
    } else if (isRec) {
      punchline = 'Heute steht aktive Regeneration auf dem Programm.';
    } else if (workout != null) {
      if (workout.totalDurationMinutes >= 120) {
        punchline = 'Heute bauen wir an deiner Langzeitausdauer.';
      } else if (workout.workIntensity.zoneLabel.contains('VO2max') ||
          workout.workIntensity.zoneLabel.contains('HIT')) {
        punchline = 'Heute steht Qualität vor Umfang.';
      } else if (workout.workIntensity.zoneLabel.contains('Schwelle') ||
          workout.workIntensity.zoneLabel.contains('EB')) {
        punchline = 'Heute setzen wir einen gezielten Schwellenreiz.';
      } else {
        punchline = 'Heute bauen wir weiter an deiner aeroben Ausdauer.';
      }
    } else {
      punchline = 'Dein Training für heute.';
    }

    // 2. Qualitative Intensität & Phasen
    final phases = WorkoutPhaseView(
      warmupMinutes: workout?.warmupMinutes ?? 0,
      workMinutes: workout?.workMinutes ?? (workout?.totalDurationMinutes ?? 0),
      cooldownMinutes: workout?.cooldownMinutes ?? 0,
    );

    // 3. Sekundäre Intensitäts-Cues (nur wenn valide vorhanden!)
    String? secondaryCue;
    if (workout != null) {
      if (workout.workIntensity.minPowerWatt != null &&
          workout.workIntensity.isDiagnosticGrounded) {
        final minW = workout.workIntensity.minPowerWatt!;
        final maxW = workout.workIntensity.maxPowerWatt ?? minW;
        secondaryCue = '${minW.round()}–${maxW.round()} W (Ercolina)';
      } else if (workout.workIntensity.minHrBpm != null) {
        final minH = workout.workIntensity.minHrBpm!;
        final maxH = workout.workIntensity.maxHrBpm ?? minH;
        secondaryCue = '$minH–$maxH bpm';
      }
    }

    // 4. Wichtig heute (Safety / Empfindlichkeiten / Datenlücken)
    final importantNotes = <String>[];
    bool hasActiveSafety = false;
    for (final sc in decision.safetyConstraintsApplied) {
      importantNotes.add(sc.reason);
      hasActiveSafety = true;
    }

    if (decision.femaleContext != null && decision.femaleContext!.isTrackingActive) {
      final sym = decision.femaleContext!.todaysSymptoms;
      if (sym != null && sym.hasRelevantSymptoms) {
        importantNotes.add('Zyklussymptome berücksichtigt: ${sym.describeActiveSymptoms().join(", ")}');
      }
    }

    // 5. Konfidenz-Label (ordinale Begriffe statt roher Prozentwerte)
    final String confidenceLabel;
    switch (decision.confidence) {
      case NeedConfidence.high:
        confidenceLabel = 'Sehr gute Datenlage';
      case NeedConfidence.moderate:
        confidenceLabel = 'Gute Datenlage';
      case NeedConfidence.low:
        confidenceLabel = 'Begrenzte Datenlage';
      case NeedConfidence.unknown:
        confidenceLabel = 'Noch zu wenig Daten';
    }

    // 6. Sichere Alternativen
    final safeAlternatives = <SafeAlternativeView>[];
    for (final alt in decision.rejectedAlternatives.take(3)) {
      safeAlternatives.add(
        SafeAlternativeView(
          title: alt.workoutTitle,
          modality: alt.modality,
          modalityLabel: alt.modality.label,
          durationMinutes: 45, // Standardzeit
          filterStageText: alt.rejectionStage.label,
          reasonText: alt.reason,
          isRestDay: false,
        ),
      );
    }
    // Immer auch Ruhetag als Option anbieten, falls heute trainiert werden soll
    if (!isRest) {
      safeAlternatives.add(
        const SafeAlternativeView(
          title: 'Vollständiger Ruhetag',
          modality: XcModality.skiSkating,
          modalityLabel: 'Regeneration',
          durationMinutes: 0,
          filterStageText: 'Athleten-Wahl',
          reasonText: 'Aktiver oder passiver Ruhetag zur Entlastung.',
          isRestDay: true,
        ),
      );
    }

    // 7. Look-ahead / Ausblick
    final nextDays = <String>[
      'Morgen: voraussichtlich locker oder offen',
      if (availability != null && availability.availableMinutes >= 150)
        'Wochenende: Längeres Zeitfenster · Langzeitausdauer möglich'
      else
        'Wochenende: Grundlagentraining und Erholung geplant',
    ];

    final isErcolina = workout?.modality == XcModality.ercolinaDoublePoling;

    final presentation = TodayPresentationModel.fromDecision(decision: decision);

    return TodayViewModel(
      greetingName: 'Guten Morgen, $athleteName',
      coachPunchline: punchline,
      actionType: decision.actionType,
      decisionId: decision.decisionId,
      decisionVersion: decision.decisionVersion,
      heroTitle: decision.displayTitle,
      modalityLabel: decision.displayModality,
      modality: workout?.modality ?? XcModality.skiSkating,
      durationMinutes: decision.displayMinutes,
      qualitativeIntensity: decision.displayIntensity,
      structureText: decision.displayStructure,
      phases: phases,
      terrainGuidance: workout?.workIntensity.terrainGuidance,
      talkTestCue: workout?.workIntensity.talkTestBreathingCues ??
          'Vollständige körperliche Entspannung.',
      effortGuidance: workout?.workIntensity.perceivedEffortGuidance ??
          workout?.workIntensity.rpeTarget ??
          'RPE 1 (Ruhe)',
      secondaryIntensityCue: secondaryCue,
      whyTodayText: decision.coachingReason,
      whyReasons: presentation.whyReasons,
      importantNotes: importantNotes,
      hasActiveSafetyConstraint: hasActiveSafety,
      dataLimitations: decision.dataLimitations,
      confidenceLabel: confidenceLabel,
      isErcolinaStartable: isErcolina,
      safeAlternatives: safeAlternatives,
      nextDaysOutlook: nextDays,
      evidenceTrace: decision.backwardTrace,
    );
  }
}
