/// Deterministische Workout-Auswahl- und Coaching-Entscheidungs-Engine (Schritt 5).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Beantwortet die zentrale Frage: «Was soll der Athlet heute trainieren – und warum?»
/// - Architektur der Pipeline:
///   1. Hard Constraints & Safety Filter (Infekte, Schmerzen, Überlastung)
///   2. User Override Context (Athleten-Vorgaben, Ruhetagswunsch, muskuläre Schwere)
///   3. Feasibility Filter (Zeitbudget heute, Equipment, Umgebung)
///   4. Look-Ahead Scheduling (Verschiebung langer Einheiten auf spätere Zeitfenster)
///   5. Contextual Stimulus Spacing & RecentStimulusContext (Kein starres 48h-Gate;
///      zwei intensive Tage in Folge möglich, wenn Blocktraining aktiv und Evidenz erlaubt)
///   6. Multi-Objective Scoring (Need-Match, Spezifität zum Wettkampfziel, Vorlieben)
///      -> Begründungen ohne interne Fantasiepunkte ("+30 Pkt" gehört nicht in Athletentext!)
///   7. Evidenzbasierte Intensitätsauflösung (Diagnostik-Referenz statt erfundener Zahlen)
///   8. Transparente Begründung, Heute-Karte und lückenloser Rückwärts-Trace.
library;

import '../../domain/training_plan.dart';
import '../../domain/xc_modality.dart';
import '../female_athlete/female_athlete_models.dart';
import '../load/stimulus_models.dart';
import '../training_need/need_types.dart';
import '../training_need/safety_constraint.dart';
import '../training_need/training_need.dart';
import '../training_need/training_need_result.dart';
import '../xc_athlete_state/data_coverage_state.dart';
import '../xc_athlete_state/ski_exposure_state.dart';
import '../xc_athlete_state/xc_athlete_state.dart';
import 'availability_context.dart';
import 'daily_coaching_decision.dart';
import 'intensity_prescription.dart';
import 'user_override_context.dart';
import '../training_need/transfer_model.dart';
import 'modality_dose.dart';
import 'workout_candidate.dart';
import 'workout_family.dart';
import 'workout_prescription.dart';

/// Kontextueller Reiz- und Erholungsabstand der jüngsten Trainingseinheiten.
class RecentStimulusContext {
  const RecentStimulusContext({
    required this.hoursSinceVo2,
    required this.hoursSinceThreshold,
    required this.hoursSinceLongEndurance,
    this.lastIntenseModality,
    this.plannedTrainingBlockContext,
    this.perceivedRecovery,
    this.unusualFatigue = false,
  });

  final int hoursSinceVo2;
  final int hoursSinceThreshold;
  final int hoursSinceLongEndurance;
  final XcModality? lastIntenseModality;
  final String? plannedTrainingBlockContext;
  final double? perceivedRecovery;
  final bool unusualFatigue;

  /// Gibt an, ob ein expliziter Trainingsblock aktiv ist.
  bool get hasPlannedTrainingBlock =>
      plannedTrainingBlockContext != null &&
      plannedTrainingBlockContext!.isNotEmpty;

  /// Rückwärtskompatibler Getter.
  bool get allowConsecutiveHardDays => hasPlannedTrainingBlock;
  bool get isBlockTraining => hasPlannedTrainingBlock;

  /// Bewertet kontextuell, ob ein intensiver Folgereiz im aktuellen Belastungs- und Erholungskontext
  /// sportwissenschaftlich sinnvoll und vertretbar ist.
  bool isConsecutiveHardPermissible({
    required StimulusType proposedStimulus,
    required XcModality proposedModality,
    required bool isUpperBodyDominant,
    required bool isLowerBodyDominant,
  }) {
    // Wenn starke Erschöpfung oder hohe vegetative Ermüdung vorliegt, keinen zweiten intensiven Reiz setzen
    if (perceivedRecovery != null && perceivedRecovery! <= 3.0) return false;
    if (unusualFatigue) return false;

    // Positiver Trainingsblock-Kontext (z. B. Blocktraining-Wochenende)
    if (hasPlannedTrainingBlock) return true;

    // Kein lokaler Muskelketten-Überlapp (z. B. gestern Ercolina-Doppelstock Oberkörper, heute Skating Unterkörper)
    final hadUpperBodyLast =
        lastIntenseModality == XcModality.ercolinaDoublePoling;
    if (hadUpperBodyLast &&
        !isUpperBodyDominant &&
        (perceivedRecovery ?? 7.0) >= 6.0) {
      return true;
    }

    // Bei guter Erholung und genügend Reizabstand (> 36 h bei VO2max, > 20 h bei Schwellenbereich)
    final minSpacingHours = proposedStimulus == StimulusType.vo2max ? 36 : 20;
    final relevantHours = proposedStimulus == StimulusType.vo2max
        ? hoursSinceVo2
        : hoursSinceThreshold;
    if (relevantHours >= minSpacingHours && (perceivedRecovery ?? 7.0) >= 6.5) {
      return true;
    }

    return false;
  }
}

class DailyDecisionEngine {
  const DailyDecisionEngine({
    this.intensityResolver = const IntensityResolver(),
    this.doseModel = const ModalityDoseModel(),
    this.transferEvaluator = const TrainingTransferEvaluator(),
  });

  final IntensityResolver intensityResolver;

  /// Bewertet Transfer und Spezifität einer Modalität zum Ziel.
  final TrainingTransferEvaluator transferEvaluator;

  /// Die plausible Dosis je Modalität — eine Stelle, benannt und versioniert.
  final ModalityDoseModel doseModel;

  /// Die plausible Obergrenze dieser Modalität in Minuten.
  ///
  /// Hier stand eine Lauf-Sonderlogik mit den Faktoren 1,25 und 1,4 und einem
  /// Rückgabewert von 360 Minuten für *jede* andere Modalität. Beides ist in
  /// [ModalityDoseModel] zusammengefasst, das alle Modalitäten gleich
  /// behandelt und fehlende Daten nicht großzügiger macht als bekannte
  /// geringe Exposition.
  int computeMaxSafeModalityMinutes(
    XcModality modality,
    SkiModalityExposure exposure,
    DataCoverageState dataCoverage,
  ) => doseModel
      .doseFor(modality: modality, exposure: exposure, coverage: dataCoverage)
      .ceilingMinutes;

  DailyCoachingDecision decide({
    required XCAthleteState state,
    required TrainingNeedResult needResult,
    required DayAvailability availability,
    DayLookAheadContext? lookAhead,
    UserOverrideContext? userOverride,
    FemaleAthleteContext? femaleContext,
    PlannedWorkout? plannedWorkout,
  }) {
    final asOf = state.asOf;
    final athleteId = state.athleteId;
    final safetyConstraints = List<SafetyConstraint>.from(
      needResult.safetyConstraints,
    );
    final dataLimitations = <String>[if (availability.assumption != null) availability.assumption!];
    final backwardTrace = <String, String>{};
    final rejectedAlternatives = <RejectedAlternative>[];

    // Effektives Zeitbudget unter Berücksichtigung von User Override
    final effectiveAvailableMinutes =
        (userOverride?.maxAvailableMinutes != null &&
            userOverride!.maxAvailableMinutes! < availability.availableMinutes)
        ? userOverride.maxAvailableMinutes!
        : availability.availableMinutes;

    // -------------------------------------------------------------------------
    // 0. DATENLIMITIERUNGEN & TRANSPARENZ
    // -------------------------------------------------------------------------
    var decisionConfidence = NeedConfidence.high;
    if (state.dataCoverage.unknownDays28d > 3) {
      decisionConfidence = state.dataCoverage.unknownDays28d > 5
          ? NeedConfidence.moderate
          : NeedConfidence.high;
      dataLimitations.add(
        'Datenabdeckung der letzten 28 Tage unvollständig (${state.dataCoverage.unknownDays28d} Tage ohne Synchronisation). Trainingsentscheidung basiert auf beobachteter Historie; es werden keine phantomhaften Trainingsdefizite angenommen.',
      );
    }
    if (!state.diagnostics.hasCurrentSkatingDiagnostics &&
        (state.goal?.modality == XcModality.skiSkating ||
            availability.hasSnow)) {
      dataLimitations.add(
        'Keine sportspezifische Skating-Schwelle gemessen; Intensitäten werden qualitativ über RPE, Sprechtest und % HRmax gesteuert.',
      );
    }

    // Subjektiver Schlafkontext als Information, NICHT als pauschales Sicherheits-Gate
    if (state.subjectiveReadiness.sleepQuality != null &&
        state.subjectiveReadiness.sleepQuality! <= 3.0) {
      dataLimitations.add(
        'Athlet berichtet über schlechte Schlafqualität (${state.subjectiveReadiness.sleepQuality!.toStringAsFixed(1)}/10). Intensitätssteuerung und Tagesform aufmerksam beobachten.',
      );
    }

    // Modalitätsspezifische Exposition (Laufen): Hinweis auf dünne oder fehlende Historie
    final runExposure = state.skiExposure.exposureOf(XcModality.running);
    if (runExposure.sessionCount90d <= 3 &&
        availability.isModalityFeasible(XcModality.running)) {
      if (runExposure.sessionCount90d == 0) {
        dataLimitations.add(
          'Keine Laufhistorie in den letzten 90 Tagen vorhanden. Zur Vermeidung von Überlastungsschäden der Sehnen und Gelenke wird die maximale Laufdauer strikt limitiert.',
        );
      } else {
        dataLimitations.add(
          'Sehr geringe Laufexposition (${runExposure.sessionCount90d} Einheiten in 90 Tagen). Laufdauer wird orthopädisch konservativ dosiert.',
        );
      }
    }

    // -------------------------------------------------------------------------
    // 1. HARD SAFETY CONSTRAINTS & INFEKTSCHUTZ (STÄRKER ALS JEDER PLAN)
    // -------------------------------------------------------------------------
    final severeConstraints = safetyConstraints
        .where((c) => c.severity >= SafetyConstraintSeverity.severe)
        .toList();
    if (state.subjectiveReadiness.hasIllnessSymptoms ||
        severeConstraints.isNotEmpty) {
      backwardTrace['Regel'] = 'XC-SCHUTZ-1 · Vorrang einer gemeldeten Einschränkung (Produktregel)';
      final symptomList = state.subjectiveReadiness.illnessSymptoms.join(', ');
      final reason = symptomList.isNotEmpty
          ? 'Athlet berichtet über Infekt-/Krankheitssymptome ($symptomList). Körperliche Ruhe hat absolute Priorität zum Schutz vor myokardialen und systemischen Risiken.'
          : (severeConstraints.first.reason);

      backwardTrace['decision'] =
          'RestDay -> Ursache: Severe Safety Constraint -> $reason';

      return DailyCoachingDecision(
        decisionDate: asOf,
        athleteId: athleteId,
        actionType: CoachingActionType.restDay,
        coachingReason: reason,
        safetyConstraintsApplied: safetyConstraints,
        dataLimitations: dataLimitations,
        confidence: NeedConfidence.high,
        backwardTrace: backwardTrace,
      );
    }

    // -------------------------------------------------------------------------
    // 1b. AKUTE SCHWERE ZYKLUSSYMPTOME (STÄRKER ALS JEDER PLAN)
    // -------------------------------------------------------------------------
    final activeSymptoms = femaleContext?.isTrackingActive == true ? femaleContext?.todaysSymptoms : null;
    if (activeSymptoms != null && activeSymptoms.isSevere) {
      backwardTrace['Regel'] = 'XC-SYMPTOM-1 · Heute gemeldete Beschwerden (vorsorgliche Produktregel)';
      final symptomDesc = activeSymptoms.describeActiveSymptoms().join(', ');
      final reason =
          'Akute ausgeprägte Beschwerden gemeldet ($symptomDesc). Zum Schutz des Körpers steht Erholung an erster Stelle.';
      backwardTrace['decision'] =
          'RestDay -> Ursache: Akute schwere Symptome -> $symptomDesc';

      final symptomConstraint = SafetyConstraint(
        id: 'safety_severe_cycle_symptoms',
        severity: SafetyConstraintSeverity.severe,
        reason: 'Akute schwere Zyklus-Symptome: $symptomDesc',
        evidence:
            'Selbstauskunft Athletin am ${asOf.toIso8601String().split('T').first}',
      );

      return DailyCoachingDecision(
        decisionDate: asOf,
        athleteId: athleteId,
        actionType: CoachingActionType.restDay,
        coachingReason: reason,
        safetyConstraintsApplied: [...safetyConstraints, symptomConstraint],
        dataLimitations: dataLimitations,
        confidence: NeedConfidence.high,
        backwardTrace: backwardTrace,
      );
    }

    // -------------------------------------------------------------------------
    // 2. USER OVERRIDE: ERZWUNGENER RUHETAG
    // -------------------------------------------------------------------------
    if (userOverride != null && userOverride.forcedRestDay) {
      backwardTrace['Regel'] = 'XC-RUHE-1 · Persönlicher Ruhetagswunsch';
      backwardTrace['decision'] =
          'RestDay -> Ursache: User Override (Athlet wünscht Ruhetag)';
      return DailyCoachingDecision(
        decisionDate: asOf,
        athleteId: athleteId,
        actionType: CoachingActionType.restDay,
        coachingReason:
            'Vom Athleten erbetener Ruhetag. Regeneration und Entspannung stehen heute im Vordergrund.',
        safetyConstraintsApplied: safetyConstraints,
        dataLimitations: dataLimitations,
        confidence: NeedConfidence.high,
        backwardTrace: backwardTrace,
      );
    }

    // -------------------------------------------------------------------------
    // 3. RECOVERY NEED (AKUTE ERSCHÖPFUNG / ÜBERLASTUNGSSCHUTZ)
    //    WICHTIG: Schlechter Schlaf allein ist kein Trainingsverbot, sondern Evidence
    //    im Verbund mit Erschöpfung oder hoher Vorbelastung!
    // -------------------------------------------------------------------------
    final hasCriticalRecovery = needResult.immediateOpportunities.any(
      (n) =>
          n.type == TrainingNeedType.recovery &&
          n.priority >= NeedPriority.high,
    );
    final isSeverelyFatigued =
        (state.subjectiveReadiness.perceivedRecovery != null &&
            state.subjectiveReadiness.perceivedRecovery! <= 3.0 &&
            state.subjectiveReadiness.unusualFatigue == true) ||
        (state.subjectiveReadiness.perceivedRecovery != null &&
            state.subjectiveReadiness.perceivedRecovery! <= 2.0) ||
        (activeSymptoms != null &&
            activeSymptoms.hasRelevantSymptoms &&
            (activeSymptoms.energyLevel != null &&
                activeSymptoms.energyLevel! <= 3.0));

    if (hasCriticalRecovery || isSeverelyFatigued) {
      backwardTrace['Regel'] = 'XC-ERHOLUNG-1 · Zeitfenster und subjektive Erholung (Trainerheuristik)';
      final recNeed = needResult.immediateOpportunities.firstWhere(
        (n) => n.type == TrainingNeedType.recovery,
        orElse: () => const TrainingNeed(
          id: 'need_rec_adhoc',
          type: TrainingNeedType.recovery,
          category: NeedCategory.immediateOpportunity,
          priority: NeedPriority.high,
          reasons: ['Subjektive Erschöpfung oder hohe Vorbelastung'],
          confidence: NeedConfidence.high,
        ),
      );

      final canActiveRec =
          effectiveAvailableMinutes >= 20 &&
          !state.subjectiveReadiness.hasPainSymptoms;
      if (canActiveRec) {
        final recPrescription = WorkoutFamily.standardFamilies
            .firstWhere((f) => f.type == WorkoutFamilyType.activeRecovery)
            .buildPrescription(
              availableMinutes: effectiveAvailableMinutes.clamp(20, 35),
              diagnostics: state.diagnostics,
              intensityResolver: intensityResolver,
            );

        backwardTrace['decision'] =
            'ActiveRecovery -> Bedarf: ${recNeed.type.label} -> Evidenz: ${recNeed.reasons.join("; ")}';

        return DailyCoachingDecision(
          decisionDate: asOf,
          athleteId: athleteId,
          actionType: CoachingActionType.activeRecovery,
          prescribedWorkout: recPrescription,
          primaryNeed: recNeed,
          coachingReason:
              'Hohe Vorbelastung oder verminderte Erholung gemeldet. Der Coach schlägt für heute aktive Erholung vor.',
          safetyConstraintsApplied: safetyConstraints,
          dataLimitations: dataLimitations,
          confidence: decisionConfidence,
          backwardTrace: backwardTrace,
        );
      } else {
        backwardTrace['decision'] =
            'RestDay -> Bedarf: ${recNeed.type.label} -> Evidenz: ${recNeed.reasons.join("; ")}';

        return DailyCoachingDecision(
          decisionDate: asOf,
          athleteId: athleteId,
          actionType: CoachingActionType.restDay,
          coachingReason:
              'Hohe Vorbelastung oder verminderte Erholung gemeldet. Der Coach schlägt für heute einen Ruhetag vor.',
          primaryNeed: recNeed,
          safetyConstraintsApplied: safetyConstraints,
          dataLimitations: dataLimitations,
          confidence: decisionConfidence,
          backwardTrace: backwardTrace,
        );
      }
    }

    // -------------------------------------------------------------------------
    // 4. CANDIDATE GENERATION AUS ERLAUBTEN VARIANTEN
    // -------------------------------------------------------------------------
    final candidates = <WorkoutCandidate>[];

    for (final family in WorkoutFamily.standardFamilies) {
      if (family.type == WorkoutFamilyType.activeRecovery) continue;

      // Zwei getrennte Obergrenzen: wie viel Zeit da ist, und was diese
      // Modalitaet fuer diesen Athleten derzeit hergibt. Beide sind Grenzen,
      // keine Ziele — die Variante waehlt die Familie innerhalb davon.
      final dose = doseModel.doseFor(
        modality: family.modality,
        exposure: state.skiExposure.exposureOf(family.modality),
        coverage: state.dataCoverage,
      );

      final prescription = family.buildPrescription(
        availableMinutes: effectiveAvailableMinutes,
        doseCeilingMinutes: dose.ceilingMinutes,
        diagnostics: state.diagnostics,
        intensityResolver: intensityResolver,
      );

      candidates.add(
        WorkoutCandidate(
          prescription: prescription,
          origin: CandidateOrigin.workoutFamily,
        ),
      );
    }

    // -------------------------------------------------------------------------
    // 5. FILTERSTUFE A: SICHERHEITSEINSCHRÄNKUNGEN & LOKALE ERMÜDUNG (OVERRIDE / PAIN)
    // -------------------------------------------------------------------------
    final painSymptoms = state.subjectiveReadiness.painSymptoms
        .map((s) => s.toLowerCase())
        .toList();
    final hasUpperBodyPain = painSymptoms.any(
      (p) =>
          p.contains('trizeps') ||
          p.contains('schulter') ||
          p.contains('arm') ||
          p.contains('ellenbogen') ||
          p.contains('latissimus') ||
          p.contains('brust'),
    );
    final hasLowerBodyPain = painSymptoms.any(
      (p) =>
          p.contains('knie') ||
          p.contains('achilles') ||
          p.contains('schienbein') ||
          p.contains('sprunggelenk') ||
          p.contains('quadrizeps') ||
          p.contains('oberschenkel') ||
          p.contains('wade') ||
          p.contains('bein') ||
          p.contains('doms') ||
          p.contains('muskelkater'),
    );

    final heavyArms = userOverride?.heavyArms ?? false;
    final heavyLegs = userOverride?.heavyLegs ?? false;

    for (final candidate in candidates) {
      final fam = WorkoutFamily.standardFamilies.firstWhere(
        (f) => f.type == candidate.prescription.family &&
            f.modality == candidate.prescription.modality,
        orElse: () => WorkoutFamily.standardFamilies.first,
      );

      if ((hasUpperBodyPain || heavyArms) &&
          (candidate.prescription.modality == XcModality.ercolinaDoublePoling ||
              fam.isUpperBodyDominant)) {
        final reason = hasUpperBodyPain
            ? 'Akute Beschwerden im Oberkörper/Armbereich (${state.subjectiveReadiness.painSymptoms.join(", ")}) schließen Doppelstock- und Zuggerätbelastung heute aus.'
            : 'Vom Athleten gemeldete starke muskuläre Ermüdung im Oberkörper schließt Ercolina-Belastung heute aus.';
        candidate.reject(stage: RejectionStage.safetyFilter, reason: reason);
      } else if ((hasLowerBodyPain || heavyLegs) &&
          (candidate.prescription.modality == XcModality.skiSkating ||
              candidate.prescription.modality == XcModality.running)) {
        final reason = hasLowerBodyPain
            ? 'Akute Beschwerden in der unteren Extremität (${state.subjectiveReadiness.painSymptoms.join(", ")}) schließen Skating und Laufen heute aus.'
            : 'Vom Athleten gemeldete muskuläre Ermüdung in den Beinen schließt Skating und Laufen heute aus.';
        candidate.reject(stage: RejectionStage.safetyFilter, reason: reason);
      }
    }

    // -------------------------------------------------------------------------
    // 6. FILTERSTUFE B: LOOK-AHEAD SCHEDULING (VERSCHIEBUNG LANGER EINHEITEN)
    // -------------------------------------------------------------------------
    final hasLongEnduranceNeed = needResult.developmentNeeds.any(
      (n) => n.type == TrainingNeedType.longEndurance,
    );
    final isShortDay = effectiveAvailableMinutes < 90;
    final hasUpcomingLongDay =
        lookAhead != null && lookAhead.hasUpcomingLongWindow(120);

    if (hasLongEnduranceNeed && isShortDay && hasUpcomingLongDay) {
      final nextLongDay = lookAhead.findNextLongWindow(120);
      final nextDayDesc = nextLongDay != null
          ? 'in ${nextLongDay.availableMinutes} min Zeitfenster'
          : 'am Wochenende';

      for (final candidate in candidates.where((c) => !c.isRejected)) {
        if (candidate.prescription.family == WorkoutFamilyType.longEndurance ||
            candidate.prescription.primaryNeedAddressed ==
                TrainingNeedType.longEndurance) {
          candidate.reject(
            stage: RejectionStage.lookAheadDeferred,
            reason:
                'Lange Ausdauereinheit heute auf Grund des kurzen Zeitfensters ($effectiveAvailableMinutes min) verschoben; wird für ein größeres Zeitfenster ($nextDayDesc) reserviert.',
          );
        }
      }
    }

    // -------------------------------------------------------------------------
    // 7. FILTERSTUFE C: MACHBARKEIT (ZEITBUDGET, EQUIPMENT, UMGEBUNG, USER EXCLUSION)
    // -------------------------------------------------------------------------
    for (final candidate in candidates.where((c) => !c.isRejected)) {
      final p = candidate.prescription;

      // 7.1 Vom User explizit ausgeschlossene Modalität
      if (userOverride != null &&
          userOverride.excludedModalities.contains(p.modality)) {
        candidate.reject(
          stage: RejectionStage.feasibilityFilter,
          reason:
              'Modalität ${p.modality.label} heute vom Athleten explizit ausgeschlossen.',
        );
        continue;
      }

      // 7.2 Zeitbudget
      if (p.totalDurationMinutes > effectiveAvailableMinutes) {
        candidate.reject(
          stage: RejectionStage.feasibilityFilter,
          reason:
              'Erfordert ${p.totalDurationMinutes} min, heute stehen jedoch nur $effectiveAvailableMinutes min zur Verfügung.',
        );
        continue;
      }

      // 7.3 Machbarkeit von Modalität und Equipment
      if (!availability.isModalityFeasible(p.modality)) {
        candidate.reject(
          stage: RejectionStage.feasibilityFilter,
          reason:
              'Modalität ${p.modality.label} heute mangels Schnee, Equipment oder Umgebung nicht machbar.',
        );
        continue;
      }
    }

    // -------------------------------------------------------------------------
    // 7b. FILTERSTUFE C2: MODALITÄTSSPEZIFISCHE EXPOSITION & BELASTUNGSTOLERANZ
    // -------------------------------------------------------------------------
    for (final candidate in candidates.where((c) => !c.isRejected)) {
      final p = candidate.prescription;
      // Die plausible Dosis begrenzt, **wie weit über die kleinste Einheit
      // hinaus** gegangen wird — sie verbietet nicht die kleinste Einheit
      // selbst.
      //
      // Ohne diese Unterscheidung verwarf dieser Filter eine
      // Fünfundvierzig-Minuten-Intervalleinheit, weil die Dauertoleranz bei
      // vierzig Minuten lag: fünf Minuten, und das Produkt bietet nichts
      // Kürzeres dieser Art an. Eine Einheit abzulehnen, die die Bibliothek
      // als kleinste Form dieses Reizes kennt, heisst, einen Reiz
      // unerreichbar zu machen — das ist keine Dosisentscheidung, sondern
      // ein Loch im Angebot. Die Dauertoleranz beschreibt lange Arbeit, nicht
      // die Struktur eines Intervalls.
      final maxSafe = _ceilingForPrescription(p, state);

      if (p.totalDurationMinutes > maxSafe) {
        final exp = state.skiExposure.exposureOf(p.modality);
        final reason =
            'Aufgrund deiner geringen ${p.modality.label}-Exposition '
            '(${exp.sessionCount90d} Einheiten in 90 Tagen) ist eine Dauer von '
            '${p.totalDurationMinutes} min orthopädisch unzulässig '
            '(maximal zulässig: $maxSafe min).';
        candidate.reject(
          stage: RejectionStage.exposureTolerance,
          reason: reason,
        );
      }
    }

    // -------------------------------------------------------------------------
    // 8. FILTERSTUFE D: RECENT STIMULUS CONTEXT & KONTEXTUELLE REIZSPATIERUNG
    //    (KEIN STARRES 48-H-GATE: BLOCKTRAINING ODER UNTERSCHIEDLICHE MUSKELKETTEN ERLAUBT)
    // -------------------------------------------------------------------------
    final lastVo2 =
        state.stimulusHistory.entries[StimulusType.vo2max]?.lastObservedAt;
    final hoursSinceVo2 = lastVo2 != null
        ? asOf.difference(lastVo2).inHours
        : 999;

    final lastThresh =
        state.stimulusHistory.entries[StimulusType.threshold]?.lastObservedAt;
    final hoursSinceThresh = lastThresh != null
        ? asOf.difference(lastThresh).inHours
        : 999;

    final lastLong = state
        .stimulusHistory
        .entries[StimulusType.fatigueResistance]
        ?.lastObservedAt;
    final hoursSinceLong = lastLong != null
        ? asOf.difference(lastLong).inHours
        : 999;

    final mostRecentIntenseType =
        lastVo2 != null && (lastThresh == null || lastVo2.isAfter(lastThresh))
        ? StimulusType.vo2max
        : StimulusType.threshold;
    final lastIntenseModality =
        state.stimulusHistory.entries[mostRecentIntenseType]?.sourceModality;

    final stimulusContext = RecentStimulusContext(
      hoursSinceVo2: hoursSinceVo2,
      hoursSinceThreshold: hoursSinceThresh,
      hoursSinceLongEndurance: hoursSinceLong,
      lastIntenseModality: lastIntenseModality,
      plannedTrainingBlockContext:
          userOverride?.plannedTrainingBlockContext ??
          (userOverride?.hasPlannedTrainingBlock == true
              ? 'Explicit planned training block'
              : null),
      perceivedRecovery: state.subjectiveReadiness.perceivedRecovery,
      unusualFatigue: state.subjectiveReadiness.unusualFatigue == true,
    );

    for (final candidate in candidates.where((c) => !c.isRejected)) {
      final p = candidate.prescription;
      final fam = WorkoutFamily.standardFamilies.firstWhere(
        (f) => f.type == candidate.prescription.family &&
            f.modality == candidate.prescription.modality,
        orElse: () => WorkoutFamily.standardFamilies.first,
      );

      if (p.intendedStimuli.contains(StimulusType.vo2max) &&
          hoursSinceVo2 < 48) {
        final isPermissible = stimulusContext.isConsecutiveHardPermissible(
          proposedStimulus: StimulusType.vo2max,
          proposedModality: p.modality,
          isUpperBodyDominant: fam.isUpperBodyDominant,
          isLowerBodyDominant: fam.isLowerBodyDominant,
        );
        if (!isPermissible) {
          candidate.reject(
            stage: RejectionStage.recoveryContext,
            reason:
                'Letzter VO2max-Reiz vor < 48 h ($hoursSinceVo2 h her). Ausreichend Erholung zur kardiovaskulären Superkompensation einhalten.',
          );
        }
      } else if (p.intendedStimuli.contains(StimulusType.threshold) &&
          hoursSinceThresh < 24) {
        final isPermissible = stimulusContext.isConsecutiveHardPermissible(
          proposedStimulus: StimulusType.threshold,
          proposedModality: p.modality,
          isUpperBodyDominant: fam.isUpperBodyDominant,
          isLowerBodyDominant: fam.isLowerBodyDominant,
        );
        if (!isPermissible) {
          candidate.reject(
            stage: RejectionStage.recoveryContext,
            reason:
                'Schwellenreiz vor < 24 h ($hoursSinceThresh h her) absolviert. Ohne Blocktraining-Vorgabe wird ein zweiter harter Reiz zur Vermeidung von Überlastung vermieden.',
          );
        }
      }
    }

    // -------------------------------------------------------------------------
    // 9. MULTI-OBJECTIVE SCORING (OHNE PSEUDO-PUNKTE IM ATHLETENTEXT)
    // -------------------------------------------------------------------------
    final targetModality =
        userOverride?.preferredModality ??
        state.goal?.modality ??
        XcModality.skiSkating;

    for (final candidate in candidates.where((c) => !c.isRejected)) {
      final p = candidate.prescription;
      var score = 0.0;
      final matchReasons = <String>[];

      // A. Passung zu Entwicklungsbedarfen (Development Needs)
      final devNeed = needResult.developmentNeeds
          .where((n) => n.type == p.primaryNeedAddressed)
          .firstOrNull;
      if (devNeed != null) {
        final prioPoints = devNeed.priority == NeedPriority.critical
            ? 60.0
            : (devNeed.priority == NeedPriority.high ? 45.0 : 30.0);
        score += prioPoints;
        matchReasons.add(
          'Erfüllt primären Entwicklungsbedarf: ${devNeed.type.label}',
        );
      }

      // B. Passung zu Erhaltungsbedarfen (Maintenance Needs)
      final maintNeed = needResult.maintenanceNeeds
          .where((n) => n.type == p.primaryNeedAddressed)
          .firstOrNull;
      if (maintNeed != null) {
        score += 20.0;
        matchReasons.add(
          'Dient dem Erhalt vorhandener Fähigkeiten: ${maintNeed.type.label}',
        );
      }

      // C. Transfer und Spezifität zur Zielmodalität
      //
      // Hier standen drei feste Boni: 25 für die Zielmodalität, 15 für
      // Rollski und Ercolina, 5 für alles andere. Das beantwortete «wie nah
      // ist das am Ziel» mit einer Liste statt mit einem Modell — und
      // unabhaengig vom Bedarf. [TrainingTransferEvaluator] war dafuer
      // laengst da und hatte keinen einzigen Aufrufer.
      //
      // Jetzt zaehlt der Transfer in der Dimension, die der Bedarf verlangt.
      // Cross-Training bleibt fuer aerobe Bedarfe eine ernsthafte
      // Moeglichkeit und verliert nur dort, wo Spezifitaet gefragt ist.
      final transfer = transferEvaluator.evaluateTransfer(
        trainingModality: p.modality,
        targetModality: targetModality,
        needType: p.primaryNeedAddressed,
      );
      score += _specificityPoints(
        transfer: transfer,
        need: p.primaryNeedAddressed,
        modality: p.modality,
        target: targetModality,
      );
      matchReasons.add(_transferReason(transfer, p.modality, targetModality));

      // D. Vorliebenbonus
      final preferred =
          userOverride?.preferredModality ?? availability.preferredModality;
      if (preferred != null && p.modality == preferred) {
        score += 15.0;
        matchReasons.add('Entspricht Athleten-Präferenz');
      }

      // E. Die Dauer ist kein Selbstzweck.
      //
      // Hier gab es zehn Punkte dafuer, dass eine Einheit 75 bis 100 Prozent
      // des Zeitfensters fuellte — «Nutzt verfuegbares Zeitfenster optimal
      // aus» stand dann in der Begruendung, die der Athlet liest. Damit
      // gewann die laengere Einheit, weil sie laenger war.
      //
      // Es gibt keinen Dauerbonus mehr. Die Dauer ist bereits zweifach
      // begrenzt: durch die Verfuegbarkeit und durch die plausible Dosis
      // dieser Modalitaet. Eine Einheit, die kuerzer ist als das Zeitfenster,
      // ist dadurch nicht schlechter — die uebrige Zeit bleibt frei. Dass die
      // Dosis begrenzt hat, steht in der Begruendung, aber ohne Punkte.
      final dose = doseModel.doseFor(
        modality: p.modality,
        exposure: state.skiExposure.exposureOf(p.modality),
        coverage: state.dataCoverage,
      );
      // Der Athlet liest einen Satz, nicht die Ableitung. Die vollstaendige
      // Begruendung samt Signalen gehoert in die Spur, die Replay und Debug
      // lesen — nicht in den Text auf dem Bildschirm.
      backwardTrace['dose_${p.modality.key}'] =
          '${dose.ceilingMinutes} min (${dose.evidence.name}, '
          '${dose.confidence.name}) — ${dose.reason} '
          '[${dose.signals.join(", ")}]';
      if (dose.ceilingMinutes < effectiveAvailableMinutes &&
          p.totalDurationMinutes >= dose.ceilingMinutes) {
        matchReasons.add(
          'Dauer an die aktuelle ${p.modality.label}-Exposition angepasst',
        );
      }

      // E2. Die Exposition gehoert in die Rangfolge, nicht nur in den Deckel.
      //
      // Vorher trennte der Dauerbonus die Faelle: Eine Modalitaet mit viel
      // Exposition durfte lang werden und bekam dafuer Punkte, eine kaum
      // trainierte blieb kurz und ging leer aus. Faellt der Bonus weg,
      // stehen beide gleich da — und eine Modalitaet, die der Athlet seit
      // Monaten nicht angefasst hat, kann einen aeroben Bedarf gewinnen,
      // nur weil sie ihn *abstrakt* erfuellt.
      //
      // Darum zaehlt die Belastbarkeit selbst: Was belegt ist, rangiert vor
      // dem, was nur moeglich waere. Das ist keine Sicherheitsgrenze — die
      // Modalitaet bleibt waehlbar, sie gewinnt nur nicht ohne Grundlage.
      score += switch (dose.evidence) {
        ExposureEvidence.established => 20.0,
        ExposureEvidence.limited => 8.0,
        ExposureEvidence.none => 0.0,
        ExposureEvidence.unknown => 0.0,
      };
      if (dose.evidence == ExposureEvidence.unknown) {
        // Nur bei echter Unkenntnis einen Satz — «nicht beobachtet» steht
        // schon in der angepassten Dauer und braucht keine zweite Zeile.
        matchReasons.add(
          'Belastbarkeit für ${p.modality.label} derzeit nicht beurteilbar',
        );
      }

      // F. User Override Trainingsfokus (z. B. Blocktraining-Ziel)
      if (userOverride?.focusNeed != null &&
          p.primaryNeedAddressed == userOverride!.focusNeed) {
        score += 50.0;
        matchReasons.add(
          'Entspricht dem geplanten Schwerpunkt (${userOverride.focusNeed!.label})',
        );
      }

      // F2. Passung zur heutigen Trainingsplanung (Plan alignment)
      if (plannedWorkout != null) {
        final planSport = plannedWorkout.sport.toLowerCase();
        final matchesSport =
            (planSport.contains('skat') &&
                p.modality == XcModality.skiSkating) ||
            (planSport.contains('classic') &&
                p.modality == XcModality.skiClassic) ||
            (planSport.contains('ercolina') &&
                p.modality == XcModality.ercolinaDoublePoling) ||
            (planSport.contains('run') && p.modality == XcModality.running) ||
            (planSport.contains('bike') && p.modality == XcModality.cycling);

        if (matchesSport) {
          score += 40.0;
          matchReasons.add(
            'Entspricht der für heute im Wochenplan vorgesehenen Einheit (${plannedWorkout.goal})',
          );
        }
      }

      // G. Schlaf- und Erholungs-Dämpfung bei intensiven Einheiten (Evidence, kein harter Crash)
      if (state.subjectiveReadiness.sleepQuality != null &&
          state.subjectiveReadiness.sleepQuality! <= 3.5) {
        if (p.intendedStimuli.contains(StimulusType.vo2max) ||
            p.intendedStimuli.contains(StimulusType.threshold)) {
          score -=
              15.0; // Dämpft intensiven Reiz leicht ab, lässt ihn aber prinzipiell wählbar
        }
      }

      // H. Wiederholt bestätigte persönliche CycleResponseEvidence (Ebene 5)
      // WICHTIG: Nur wenn das Muster 'repeated' oder 'strongPersonalEvidence' ist UND
      // die Athletin heute dieselben Beschwerden/Kontexte meldet!
      if (femaleContext != null &&
          femaleContext.isTrackingActive &&
          activeSymptoms != null &&
          activeSymptoms.hasRelevantSymptoms) {
        for (final pattern in femaleContext.evidence.patterns) {
          if (pattern.confidence.isActionable) {
            if (pattern.outcome == PatternOutcome.higherRpeForSameLoad ||
                pattern.outcome == PatternOutcome.lowerErcolinaPower ||
                pattern.outcome == PatternOutcome.sessionAbortionOrStruggle) {
              // Intensive Einheiten (VO2max / HIT) leicht dämpfen, lockere Einheiten priorisieren
              if (p.intendedStimuli.contains(StimulusType.vo2max) ||
                  p.intendedStimuli.contains(StimulusType.threshold)) {
                score -= 20.0;
              } else if (p.intendedStimuli.contains(StimulusType.aerobicBase) ||
                  p.intendedStimuli.contains(StimulusType.recovery)) {
                score += 15.0;
                matchReasons.add(
                  'Berücksichtigt bestätigtes persönliches Erholungs-Muster bei aktiven Symptomen',
                );
              }
            }
          }
        }
      }

      candidate.score = score;
      candidate.matchReasons.addAll(matchReasons);
    }

    // Sammle abgelehnte Kandidaten für Dokumentation
    for (final c in candidates.where((c) => c.isRejected)) {
      rejectedAlternatives.add(c.toRejectedAlternative());
    }

    // -------------------------------------------------------------------------
    // 10. AUSWAHL DES GEWINNERS & BILDUNG DER DECISION
    // -------------------------------------------------------------------------
    final validCandidates = candidates.where((c) => !c.isRejected).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    if (validCandidates.isEmpty) {
      return DailyCoachingDecision(
        decisionDate: asOf,
        athleteId: athleteId,
        actionType: CoachingActionType.restDay,
        coachingReason:
            'Aufgrund der heutigen Einschränkungen (Zeitbudget, Umfeld oder Erholungskontext) ist heute ein vollständiger Ruhetag die sinnvollste Entscheidung.',
        safetyConstraintsApplied: safetyConstraints,
        rejectedAlternatives: rejectedAlternatives,
        dataLimitations: dataLimitations,
        confidence: decisionConfidence,
        backwardTrace: {
          'decision':
              'RestDay -> Keine machbaren Trainingskandidaten nach Filterung',
        },
      );
    }

    // Wenn heute im Wochenplan eine machbare Einheit vorgesehen ist, hat diese
    // Vorgabe Priorität gegenüber freier Neuberechnung, damit Plan, Coach und HEUTE
    // zu 100% konsistent sind (sofern kein akuter Sicherheits- oder Zeitfilter greift).
    WorkoutCandidate? plannedWinner;
    if (plannedWorkout != null) {
      final planSport = plannedWorkout.sport.toLowerCase();
      plannedWinner = validCandidates.where((c) {
        final p = c.prescription;
        final matchesSport =
            (planSport.contains('skat') &&
                p.modality == XcModality.skiSkating) ||
            (planSport.contains('classic') &&
                p.modality == XcModality.skiClassic) ||
            (planSport.contains('ercolina') &&
                p.modality == XcModality.ercolinaDoublePoling) ||
            (planSport.contains('run') && p.modality == XcModality.running) ||
            (planSport.contains('bike') && p.modality == XcModality.cycling);
        return matchesSport;
      }).firstOrNull;
    }

    final winner = plannedWinner ?? validCandidates.first;

    for (final runnerUp in validCandidates) {
      if (runnerUp == winner) continue;
      runnerUp.reject(
        stage: RejectionStage.lowerNeedPriority,
        reason:
            'Geringere Passung zu den heutigen Prioritäten und Randbedingungen.',
      );
      rejectedAlternatives.add(runnerUp.toRejectedAlternative());
    }

    final primaryNeed =
        needResult.developmentNeeds
            .where((n) => n.type == winner.prescription.primaryNeedAddressed)
            .firstOrNull ??
        needResult.maintenanceNeeds
            .where((n) => n.type == winner.prescription.primaryNeedAddressed)
            .firstOrNull;

    final coachingReason = winner.matchReasons.isNotEmpty
        ? winner.matchReasons.join('. ')
        : 'Optimale Passung zu den aktuellen Trainingsbedarfen und Rahmenbedingungen.';

    backwardTrace['decision'] =
        '${winner.prescription.title} (${winner.prescription.modality.label})';
    if (primaryNeed != null) {
      backwardTrace['need'] =
          '${primaryNeed.type.label} (${primaryNeed.priority.label}) -> ${primaryNeed.reasons.firstOrNull ?? ""}';
      if (primaryNeed.sourceEvidenceIds.isNotEmpty) {
        backwardTrace['evidence'] = primaryNeed.sourceEvidenceIds.join(', ');
      }
    }

    return DailyCoachingDecision(
      decisionDate: asOf,
      athleteId: athleteId,
      actionType: CoachingActionType.prescribedWorkout,
      prescribedWorkout: winner.prescription,
      primaryNeed: primaryNeed,
      secondaryNeeds: needResult.developmentNeeds
          .where((n) => n != primaryNeed)
          .toList(),
      coachingReason: coachingReason,
      safetyConstraintsApplied: safetyConstraints,
      rejectedAlternatives: rejectedAlternatives,
      dataLimitations: dataLimitations,
      confidence: decisionConfidence,
      backwardTrace: backwardTrace,
      femaleContext: femaleContext,
    );
  }
}

/// Punkte aus Transfer und Spezifität, je nach Bedarf.
///
/// Die Größenordnung entspricht den drei festen Boni, die hier vorher standen
/// (25 / 15 / 5) — damit die übrigen Gewichte des Scorings gültig bleiben.
/// Neu ist, *woraus* sie entstehen: aus der Dimension, die der Bedarf
/// verlangt, statt aus einer Liste von Modalitäten.
double _transferPoints(TrainingTransfer transfer, TrainingNeedType need) {
  double points(TransferLevel level) => switch (level) {
    TransferLevel.high => 25.0,
    TransferLevel.moderate => 15.0,
    TransferLevel.low => 7.0,
    TransferLevel.minimal => 2.0,
    // Unbekannter Transfer ist kein Argument — in keine Richtung.
    TransferLevel.unknown => 5.0,
  };

  return switch (need) {
    // Technik und Wettkampfspezifität fragen nach dem Bewegungsablauf.
    TrainingNeedType.technique || TrainingNeedType.skatingSpecificity =>
      (points(transfer.movementSpecificity) +
              points(transfer.technicalSpecificity)) /
          2,
    // Doppelstock fragt nach der Muskelkette.
    TrainingNeedType.doublePolingPower ||
    TrainingNeedType.doublePolingEndurance =>
      (points(transfer.muscularSpecificity) +
              points(transfer.movementSpecificity)) /
          2,
    // Alles Übrige ist in erster Linie eine physiologische Frage — darum
    // bleibt Cross-Training für aerobe Bedarfe eine ernsthafte Möglichkeit.
    _ =>
      points(transfer.physiologicalTransfer) * 0.7 +
          points(transfer.muscularSpecificity) * 0.3,
  };
}

/// Die strukturelle Untergrenze der Spezifität.
///
/// ## Warum es sie gibt
///
/// [TrainingTransferEvaluator] war toter Code, und das Anschliessen hat eine
/// Lücke in seinem Inhalt sichtbar gemacht: Für ein **klassisches** Ziel gibt
/// er Laufen `physiologicalTransfer: high`, Skating, Skiroller und Ercolina
/// dagegen nur `moderate`. Sein Skating-Zweig ist ausgearbeitet, sein
/// Klassik-Zweig nicht. Allein auf seine Zahlen gestellt, gewann deshalb ein
/// Lauf gegen Skiroller — bei einem Langlaufziel.
///
/// Diese Zahlen zu ändern wäre eine sportwissenschaftliche Aussage, die ich
/// nicht erfinde. Stattdessen gilt eine strukturelle Wahrheit, die schon im
/// Modell steht: [XcModality.sportGroup]. Die Zielmodalität ist per
/// Definition maximal spezifisch, und eine Modalität derselben Sportgruppe
/// ist dem Ziel näher als eine fremde. Der Transfer kann darüber hinaus
/// erhöhen, aber nicht darunter fallen.
double _sportGroupFloor(XcModality modality, XcModality target) {
  if (modality == target) return 25.0;
  if (modality.sportGroup == target.sportGroup) return 15.0;
  return 0.0;
}

double _specificityPoints({
  required TrainingTransfer transfer,
  required TrainingNeedType need,
  required XcModality modality,
  required XcModality target,
}) {
  final fromTransfer = _transferPoints(transfer, need);
  final floor = _sportGroupFloor(modality, target);
  return fromTransfer > floor ? fromTransfer : floor;
}

/// Ein Satz über Transfer, ohne Punktzahlen im Athletentext.
String _transferReason(
  TrainingTransfer transfer,
  XcModality modality,
  XcModality target,
) {
  if (modality == target) {
    return 'Höchste Wettkampfspezifität (${modality.label})';
  }
  if (modality.sportGroup == target.sportGroup) {
    return 'Hohe skispezifische Verwandtschaft (${modality.label})';
  }
  if (transfer.physiologicalTransfer.isSubstantial) {
    return 'Kardiovaskuläres Cross-Training (${modality.label})';
  }
  return 'Geringer Übertrag auf das Ziel (${modality.label})';
}

/// Die Obergrenze einer Verschreibung: die plausible Dosis, ohne Ausnahme.
///
/// Hier stand eine Untergrenze — «die kleinste angebotene Form eines Reizes
/// bleibt erreichbar» —, die eine Fünfundvierzig-Minuten-Einheit auch dann
/// durchliess, wenn die Dosis dreissig Minuten ergab. Damit war
/// `doseCeilingMinutes` keine Obergrenze, sondern ein Vorschlag.
///
/// Jetzt gilt: Gibt es für einen Reiz keine Einheit innerhalb der plausiblen
/// Dosis, ist dieser Kandidat heute **nicht zulässig** — und das ist eine
/// Aussage über das Angebot, nicht über den Athleten. Eine fehlende kurze
/// Variante ist eine Lücke im Katalog und wird als solche gemeldet, nicht
/// durch Überschreiben der Dosis verdeckt.
int _ceilingForPrescription(WorkoutPrescription p, XCAthleteState state) =>
    const ModalityDoseModel()
        .doseFor(
          modality: p.modality,
          exposure: state.skiExposure.exposureOf(p.modality),
          coverage: state.dataCoverage,
        )
        .ceilingMinutes;
