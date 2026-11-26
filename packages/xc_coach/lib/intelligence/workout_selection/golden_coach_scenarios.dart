/// Zehn kanonische Golden Coach Scenarios für den GIULIA XC Coach.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Jeder Benchmark-Test bildet eine reale Coaching-Situation ab.
/// - Definiert für jedes Szenario die erlaubten und strikt verbotenen Handlungen.
/// - Dient als ständige Regressionsabsicherung vor Modellverschlechterungen.
library;

import '../../domain/normalized_session.dart';
import '../../domain/xc_modality.dart';
import '../training_need/need_types.dart';
import '../training_need/training_need_engine.dart';
import '../xc_athlete_state/goal_context.dart';
import '../xc_athlete_state/subjective_readiness_state.dart';
import '../xc_athlete_state/xc_athlete_state_builder.dart';
import 'availability_context.dart';
import 'coach_validation_mode.dart';
import 'daily_decision_engine.dart';
import 'user_override_context.dart';
import 'workout_execution_evaluation.dart';

class GoldenCoachRunner {
  const GoldenCoachRunner({
    this.builder = const XCAthleteStateBuilder(),
    this.needEngine = const TrainingNeedEngine(),
    this.decisionEngine = const DailyDecisionEngine(),
  });

  final XCAthleteStateBuilder builder;
  final TrainingNeedEngine needEngine;
  final DailyDecisionEngine decisionEngine;

  static const athleteId = 'golden_athlete_01';
  static final baseDate = DateTime.utc(2026, 10, 3, 9, 0);

  static const defaultGoal50k = GoalContext(
    name: 'Engadin Skimarathon',
    modality: XcModality.skiSkating,
    targetDistanceMetres: 50000.0,
    targetDurationSeconds: 8100,
    priority: 'A',
  );

  /// Die Historie von Szenario 1: wiederholte lange Skating-Einheiten.
  ///
  /// Steht hier und nicht im Szenario, weil der Shadow-Replay denselben
  /// Zustand braucht. Baute er ihn ohne diese Einheiten, verglich er zwei
  /// verschiedene Athleten und nannte das eine Divergenz der Engine.
  static final List<NormalizedSession> scenario1History = <NormalizedSession>[
    for (final (index, minutes) in <int>[135, 128, 140, 95, 110].indexed)
      NormalizedSession(
        id: 'sess_s1_$index',
        athleteId: athleteId,
        source: NormalizedSessionSource.manual,
        sourceId: 'src_s1_$index',
        startedAtUtcUs: baseDate
            .subtract(Duration(days: 4 + index * 6))
            .microsecondsSinceEpoch,
        durationSeconds: minutes * 60,
        movingTimeSeconds: minutes * 60,
        modality: XcModality.skiSkating,
        technique: XcTechnique.skatingG3,
        isIndoor: false,
        title: 'Skating Grundlage',
      ),
  ];

  // ---------------------------------------------------------------------------
  // 1. Planned long endurance (3h window, recovered, repeated ski exposure)
  // ---------------------------------------------------------------------------
  CoachValidationRecord runScenario1FreshWeekend() {
    // Dieses Szenario hatte keine Exposition: kein Athlet, der je etwas
    // gefahren hat, nur ein Zeitfenster von drei Stunden. Damit verschrieb
    // die Engine eine Zweistundeneinheit — allein, weil die Zeit da war.
    // Genau das ist der Fehler, den [ModalityDoseModel] behebt, und darum
    // kann der Test nicht mehr davon ausgehen.
    //
    // Ein frisches Wochenende mit drei Stunden *ist* ein Langausdauerfall —
    // fuer einen Athleten, der lange Einheiten faehrt. Also faehrt er hier
    // welche: wiederholte Skating-Einheiten, die die Dosis tragen.
    final state = builder.buildState(
      athleteId: athleteId,
      asOf: baseDate,
      goal: defaultGoal50k,
      sessions: scenario1History,
      subjectiveReadiness: SubjectiveReadinessState(
        recordedAt: baseDate,
        perceivedRecovery: 8.5,
      ),
    );

    final availability = DayAvailability(
      date: baseDate,
      availableMinutes: 180,
      environment: TrainingEnvironment.outdoorSnow,
      hasSnow: true,
      hasErcolina: true,
    );

    final needs = needEngine.evaluate(state: state);
    final decision = decisionEngine.decide(
      state: state,
      needResult: needs,
      availability: availability,
      // A long session is planned, not inferred solely from spare time.
      userOverride: const UserOverrideContext(
        focusNeed: TrainingNeedType.longEndurance,
      ),
    );

    return CoachValidationRecord(
      scenarioId: 'golden_01_fresh_weekend',
      timestamp: baseDate,
      inputSnapshot: {
        'availableMinutes': 180,
        'hasSnow': true,
        'perceivedRecovery': 8.5,
        'focusNeed': TrainingNeedType.longEndurance.name,
      },
      decision: decision,
      nextDayImplication:
          'Hoher Erholungsbedarf nach 2–3 h Langdistanz; Folgetag erfordert Regeneration oder Ruhetag.',
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Time Crunched (45 min)
  // ---------------------------------------------------------------------------
  CoachValidationRecord runScenario2TimeCrunched() {
    final state = builder.buildState(
      athleteId: athleteId,
      asOf: baseDate,
      goal: defaultGoal50k,
    );

    final availability = DayAvailability(
      date: baseDate,
      availableMinutes: 45,
      environment: TrainingEnvironment.outdoorSnow,
      hasSnow: true,
      hasErcolina: true,
    );

    final needs = needEngine.evaluate(state: state);
    final decision = decisionEngine.decide(
      state: state,
      needResult: needs,
      availability: availability,
    );

    return CoachValidationRecord(
      scenarioId: 'golden_02_time_crunched',
      timestamp: baseDate,
      inputSnapshot: {'availableMinutes': 45},
      decision: decision,
      nextDayImplication:
          'Geringe bis moderate Ermüdung; Folgetag voll belastbar.',
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Block Training (Zwei intensive Tage in Folge geplant)
  // ---------------------------------------------------------------------------
  CoachValidationRecord runScenario3BlockTraining() {
    // Vortag: Intensiver VO2max Reiz
    final yesterdayVo2 = NormalizedSession(
      id: 'sess_block_day1',
      athleteId: athleteId,
      source: NormalizedSessionSource.ercolina,
      sourceId: 'src_b1',
      startedAtUtcUs: baseDate
          .subtract(const Duration(hours: 22))
          .microsecondsSinceEpoch,
      durationSeconds: 2400,
      movingTimeSeconds: 2400,
      modality: XcModality.ercolinaDoublePoling,
      technique: XcTechnique.classicDoublePoling,
      isIndoor: true,
      title: 'Block Day 1 - VO2max HIT',
      externalMetrics: const SessionExternalMetrics(
        sessionAveragePowerWatt: 195.0,
      ),
      internalMetrics: const SessionInternalMetrics(
        averageHeartRateBpm: 165.0,
        peakHeartRateBpm: 184,
        rpe: 8.5,
        timeInHrZonesSeconds: {'z5': 360},
      ),
    );

    final state = builder.buildState(
      athleteId: athleteId,
      asOf: baseDate,
      goal: defaultGoal50k,
      sessions: [...scenario1History, yesterdayVo2],
      subjectiveReadiness: SubjectiveReadinessState(
        recordedAt: baseDate,
        perceivedRecovery: 7.0, // Gute vegetative Verfassung für Tag 2
      ),
    );

    final availability = DayAvailability(
      date: baseDate,
      availableMinutes: 60,
      environment: TrainingEnvironment.outdoorSnow,
      hasSnow: true,
      hasErcolina: true,
    );

    final needs = needEngine.evaluate(state: state);
    final decision = decisionEngine.decide(
      state: state,
      needResult: needs,
      availability: availability,
      userOverride: const UserOverrideContext(
        plannedTrainingBlockContext: 'Wochenend-Schwellenblock',
        focusNeed: TrainingNeedType.threshold,
      ),
    );

    return CoachValidationRecord(
      scenarioId: 'golden_03_block_training',
      timestamp: baseDate,
      inputSnapshot: {
        'plannedTrainingBlockContext': 'Wochenend-Schwellenblock',
        'yesterdayStimulus': 'VO2max',
      },
      decision: decision,
      nextDayImplication:
          'Nach zwei intensiven Tagen in Folge zwingend 48 h Entlastung / Regeneration.',
    );
  }

  // ---------------------------------------------------------------------------
  // 4. Severe Muscular Soreness (DOMS)
  // ---------------------------------------------------------------------------
  CoachValidationRecord runScenario4SevereDoms() {
    final state = builder.buildState(
      athleteId: athleteId,
      asOf: baseDate,
      goal: defaultGoal50k,
      subjectiveReadiness: SubjectiveReadinessState(
        recordedAt: baseDate,
        painSymptoms: const ['Starker Muskelkater Quadrizeps (DOMS)'],
        perceivedRecovery: 4.0,
      ),
    );

    final availability = DayAvailability(
      date: baseDate,
      availableMinutes: 60,
      environment: TrainingEnvironment.outdoorSnow,
      hasSnow: true,
      hasErcolina: true,
    );

    final needs = needEngine.evaluate(state: state);
    final decision = decisionEngine.decide(
      state: state,
      needResult: needs,
      availability: availability,
    );

    return CoachValidationRecord(
      scenarioId: 'golden_04_severe_doms',
      timestamp: baseDate,
      inputSnapshot: {
        'painSymptoms': ['DOMS Beine'],
      },
      decision: decision,
      nextDayImplication:
          'Beinmuskulatur geschont; Regeneration der Mikrotraumata im Vordergrund.',
    );
  }

  // ---------------------------------------------------------------------------
  // 5. Poor Sleep & Combined Fatigue (Schlechter Schlaf + Erschöpfung)
  // ---------------------------------------------------------------------------
  CoachValidationRecord runScenario5PoorSleep() {
    final state = builder.buildState(
      athleteId: athleteId,
      asOf: baseDate,
      goal: defaultGoal50k,
      subjectiveReadiness: SubjectiveReadinessState(
        recordedAt: baseDate,
        sleepQuality: 2.5,
        perceivedRecovery: 2.5,
        unusualFatigue: true,
      ),
    );

    final availability = DayAvailability(
      date: baseDate,
      availableMinutes: 60,
      environment: TrainingEnvironment.outdoorSnow,
      hasSnow: true,
    );

    final needs = needEngine.evaluate(state: state);
    final decision = decisionEngine.decide(
      state: state,
      needResult: needs,
      availability: availability,
    );

    return CoachValidationRecord(
      scenarioId: 'golden_05_poor_sleep_combined',
      timestamp: baseDate,
      inputSnapshot: {
        'sleepQuality': 2.5,
        'perceivedRecovery': 2.5,
        'unusualFatigue': true,
      },
      decision: decision,
      nextDayImplication:
          'Vegetatives Nervensystem geschont; Re-Evaluation am Folgetag.',
    );
  }

  /// 5b. Isoliert schlechter Schlaf (ohne Erschöpfung): Kein pauschales Trainings- oder HIT-Verbot!
  CoachValidationRecord runScenario5bIsolatedPoorSleep() {
    final state = builder.buildState(
      athleteId: athleteId,
      asOf: baseDate,
      goal: defaultGoal50k,
      subjectiveReadiness: SubjectiveReadinessState(
        recordedAt: baseDate,
        sleepQuality: 2.5,
        perceivedRecovery: 7.0, // Erholung sonst gut
        unusualFatigue: false,
      ),
    );

    final availability = DayAvailability(
      date: baseDate,
      availableMinutes: 60,
      environment: TrainingEnvironment.outdoorSnow,
      hasSnow: true,
      hasErcolina: true,
    );

    final needs = needEngine.evaluate(state: state);
    final decision = decisionEngine.decide(
      state: state,
      needResult: needs,
      availability: availability,
    );

    return CoachValidationRecord(
      scenarioId: 'golden_05b_isolated_poor_sleep',
      timestamp: baseDate,
      inputSnapshot: {
        'sleepQuality': 2.5,
        'perceivedRecovery': 7.0,
        'unusualFatigue': false,
      },
      decision: decision,
      nextDayImplication:
          'Einheit planmäßig absolviert; Schlafhistorie als Trend beobachten.',
    );
  }

  // ---------------------------------------------------------------------------
  // 6. Sickness / Elevated Body Temperature
  // ---------------------------------------------------------------------------
  CoachValidationRecord runScenario6Sickness() {
    final state = builder.buildState(
      athleteId: athleteId,
      asOf: baseDate,
      goal: defaultGoal50k,
      subjectiveReadiness: SubjectiveReadinessState(
        recordedAt: baseDate,
        illnessSymptoms: const ['Fieber', 'Halsschmerzen'],
      ),
    );

    final availability = DayAvailability(
      date: baseDate,
      availableMinutes: 60,
      environment: TrainingEnvironment.outdoorSnow,
      hasSnow: true,
    );

    final needs = needEngine.evaluate(state: state);
    final decision = decisionEngine.decide(
      state: state,
      needResult: needs,
      availability: availability,
    );

    return CoachValidationRecord(
      scenarioId: 'golden_06_sickness',
      timestamp: baseDate,
      inputSnapshot: {
        'illnessSymptoms': ['Fieber'],
      },
      decision: decision,
      nextDayImplication:
          'Vollständige Sportpause bis zur Symptomfreiheit plus 24 h Puffer.',
    );
  }

  // ---------------------------------------------------------------------------
  // 7. Acute Joint Pain (Knee)
  // ---------------------------------------------------------------------------
  CoachValidationRecord runScenario7AcuteJointPain() {
    final state = builder.buildState(
      athleteId: athleteId,
      asOf: baseDate,
      goal: defaultGoal50k,
      subjectiveReadiness: SubjectiveReadinessState(
        recordedAt: baseDate,
        painSymptoms: const ['Knieschmerzen rechts Patellarsehne'],
      ),
    );

    final availability = DayAvailability(
      date: baseDate,
      availableMinutes: 60,
      environment: TrainingEnvironment.outdoorSnow,
      hasSnow: true,
      hasErcolina: true,
    );

    final needs = needEngine.evaluate(state: state);
    final decision = decisionEngine.decide(
      state: state,
      needResult: needs,
      availability: availability,
    );

    return CoachValidationRecord(
      scenarioId: 'golden_07_acute_joint_pain',
      timestamp: baseDate,
      inputSnapshot: {
        'painSymptoms': ['Knieschmerzen'],
      },
      decision: decision,
      nextDayImplication: 'Kniegelenk entlastet; Oberkörper/Ercolina möglich.',
    );
  }

  // ---------------------------------------------------------------------------
  // 8. Missing Diagnostic (No Invented Watts)
  // ---------------------------------------------------------------------------
  CoachValidationRecord runScenario8MissingDiagnostic() {
    final state = builder.buildState(
      athleteId: athleteId,
      asOf: baseDate,
      goal: defaultGoal50k,
      diagnostics: const [], // Keine Diagnostik
    );

    final availability = DayAvailability(
      date: baseDate,
      availableMinutes: 60,
      environment: TrainingEnvironment.outdoorSnow,
      hasSnow: true,
      hasErcolina: true,
    );

    final needs = needEngine.evaluate(state: state);
    final decision = decisionEngine.decide(
      state: state,
      needResult: needs,
      availability: availability,
    );

    return CoachValidationRecord(
      scenarioId: 'golden_08_missing_diagnostic',
      timestamp: baseDate,
      inputSnapshot: {'hasDiagnostics': false},
      decision: decision,
      nextDayImplication:
          'Intensitätssteuerung über RPE/HF verfeinert; Diagnostik empfohlen.',
    );
  }

  // ---------------------------------------------------------------------------
  // 9. Sparse Data Coverage
  // ---------------------------------------------------------------------------
  CoachValidationRecord runScenario9SparseDataCoverage() {
    final state = builder.buildState(
      athleteId: athleteId,
      asOf: baseDate,
      goal: defaultGoal50k,
      sessions:
          const [], // Keine synchronisierten Sessions in 28 Tagen -> 28 unbekannte Tage
    );

    final availability = DayAvailability(
      date: baseDate,
      availableMinutes: 60,
      environment: TrainingEnvironment.outdoorSnow,
      hasSnow: true,
    );

    final needs = needEngine.evaluate(state: state);
    final decision = decisionEngine.decide(
      state: state,
      needResult: needs,
      availability: availability,
    );

    return CoachValidationRecord(
      scenarioId: 'golden_09_sparse_data_coverage',
      timestamp: baseDate,
      inputSnapshot: {'unknownDays28d': 24},
      decision: decision,
      nextDayImplication:
          'Verlässlichkeit der Langzeittrends eingeschränkt; Fokus auf beobachtete Daten.',
    );
  }

  // ---------------------------------------------------------------------------
  // 10. Partial Workout & Meaningful Self-Regulation
  // ---------------------------------------------------------------------------
  CoachValidationRecord runScenario10SelfRegulation() {
    // Athlet hat ein Schwellentraining nach 2 von 4 Intervallen wegen starker Erschöpfung abgebrochen
    final evaluation = const WorkoutExecutionEvaluation(
      prescribedWorkoutId: 'fam_skate_thresh_4x8',
      actualSessionId: 'sess_aborted_by_athlete',
      durationCompliance: 0.60,
      intervalCompliance: 0.50, // 2 von 4
      modalityCompliance: true,
      athleteModified: true,
      athleteModificationReason:
          'Hohe vegetative Erschöpfung, Puls schoss unkontrolliert hoch',
      isMeaningfulSelfRegulation: true,
      overallEvaluationText:
          'Vorzeitiger Abbruch zeugt von exzellenter Selbstregulation und schützt vor Übertraining.',
    );

    final state = builder.buildState(
      athleteId: athleteId,
      asOf: baseDate,
      goal: defaultGoal50k,
    );

    final availability = DayAvailability(
      date: baseDate,
      availableMinutes: 45,
      environment: TrainingEnvironment.indoorErcolina,
      hasErcolina: true,
    );

    final needs = needEngine.evaluate(state: state);
    final decision = decisionEngine.decide(
      state: state,
      needResult: needs,
      availability: availability,
    );

    return CoachValidationRecord(
      scenarioId: 'golden_10_self_regulation',
      timestamp: baseDate,
      inputSnapshot: {'evaluation': evaluation.toJson()},
      decision: decision,
      executionEvaluation: evaluation,
      nextDayImplication:
          'Trotz geringerer Plan-Compliance hohe physiologische Belastung; am Folgetag Erholung priorisieren.',
    );
  }
}
