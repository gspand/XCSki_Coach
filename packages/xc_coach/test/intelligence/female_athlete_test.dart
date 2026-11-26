import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/domain/normalized_session.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:xc_coach/intelligence/female_athlete/cycle_evidence_engine.dart';
import 'package:xc_coach/intelligence/female_athlete/female_athlete_models.dart';
import 'package:xc_coach/intelligence/training_need/need_types.dart';
import 'package:xc_coach/intelligence/training_need/training_need.dart';
import 'package:xc_coach/intelligence/training_need/training_need_result.dart';
import 'package:xc_coach/intelligence/workout_selection/availability_context.dart';
import 'package:xc_coach/intelligence/workout_selection/daily_coaching_decision.dart';
import 'package:xc_coach/intelligence/workout_selection/daily_decision_engine.dart';
import 'package:xc_coach/intelligence/workout_selection/workout_prescription.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/goal_context.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/subjective_readiness_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/xc_athlete_state_builder.dart';

void main() {
  final now = DateTime.utc(2026, 10, 4, 9, 0);

  const builder = XCAthleteStateBuilder();
  final baseState = builder.buildState(
    athleteId: 'ath_female_1',
    asOf: now,
    goal: const GoalContext(
      name: 'Engadin Skimarathon',
      modality: XcModality.skiSkating,
      targetDistanceMetres: 50000.0,
      priority: 'A',
    ),
    subjectiveReadiness: SubjectiveReadinessState(
      recordedAt: now,
      perceivedRecovery: 7.5,
    ),
  );

  final needResult = TrainingNeedResult(
    asOf: now,
    athleteId: 'ath_female_1',
    developmentNeeds: const [
      TrainingNeed(
        id: 'need_base',
        type: TrainingNeedType.aerobicBase,
        category: NeedCategory.development,
        priority: NeedPriority.high,
        reasons: ['Aerobe Basis ausbauen.'],
        confidence: NeedConfidence.high,
      ),
    ],
  );

  final availability = DayAvailability(
    date: now,
    availableMinutes: 90,
    environment: TrainingEnvironment.outdoorSnow,
    hasSnow: true,
    hasErcolina: true,
  );

  const engine = DailyDecisionEngine();
  const cycleEngine = CycleEvidenceEngine();

  group('Female Athlete Intelligence – Wissenschaftlich konservative Leitplanken', () {
    test('A. No cycle data / Opt-out -> Identical coach decision to base engine', () {
      final decWithout = engine.decide(
        state: baseState,
        needResult: needResult,
        availability: availability,
        femaleContext: null,
      );

      final optOutContext = const FemaleAthleteContext(
        cycleContext: CycleContext(
          optIn: FemaleCycleTrackingOptIn.disabled,
          hormonalStatus: HormonalStatus.unknown,
        ),
        evidence: CycleResponseEvidence(insufficientHistory: true),
        healthContext: FemaleAthleteHealthContext(),
      );

      final decWithOptOut = engine.decide(
        state: baseState,
        needResult: needResult,
        availability: availability,
        femaleContext: optOutContext,
      );

      expect(decWithOptOut.prescribedWorkout?.id, equals(decWithout.prescribedWorkout?.id));
      expect(decWithOptOut.actionType, equals(decWithout.actionType));
      expect(decWithOptOut.safetyConstraintsApplied.length, equals(decWithout.safetyConstraintsApplied.length));
    });

    test('B. Cycle day known, no symptoms, no personal evidence -> NO workout change', () {
      final baselineDec = engine.decide(
        state: baseState,
        needResult: needResult,
        availability: availability,
      );

      final femaleCtx = FemaleAthleteContext(
        cycleContext: CycleContext(
          optIn: FemaleCycleTrackingOptIn.enabled,
          hormonalStatus: HormonalStatus.naturalCycle,
          currentCycleDay: 8,
          estimatedPhase: CyclePhaseEstimate.lateFollicular,
          phaseConfidence: 0.35,
          inferenceMethod: CycleInferenceMethod.calendarEstimate,
          asOf: now,
        ),
        evidence: const CycleResponseEvidence(insufficientHistory: true),
        healthContext: const FemaleAthleteHealthContext(),
      );

      final cycleDec = engine.decide(
        state: baseState,
        needResult: needResult,
        availability: availability,
        femaleContext: femaleCtx,
      );

      expect(cycleDec.prescribedWorkout?.id, equals(baselineDec.prescribedWorkout?.id));
      expect(cycleDec.actionType, equals(baselineDec.actionType));
    });

    test('C. Luteal phase estimate alone -> NEVER prohibits or cancels HIT / intervals', () {
      final vo2NeedResult = TrainingNeedResult(
        asOf: now,
        athleteId: 'ath_female_1',
        developmentNeeds: const [
          TrainingNeed(
            id: 'need_vo2',
            type: TrainingNeedType.vo2max,
            category: NeedCategory.development,
            priority: NeedPriority.high,
            reasons: ['VO2max-Reiz an der Reihe.'],
            confidence: NeedConfidence.high,
          ),
        ],
      );

      final lutealCtx = FemaleAthleteContext(
        cycleContext: CycleContext(
          optIn: FemaleCycleTrackingOptIn.enabled,
          hormonalStatus: HormonalStatus.naturalCycle,
          currentCycleDay: 22,
          estimatedPhase: CyclePhaseEstimate.earlyMidLuteal,
          phaseConfidence: 0.35,
          inferenceMethod: CycleInferenceMethod.calendarEstimate,
          asOf: now,
        ),
        evidence: const CycleResponseEvidence(insufficientHistory: true),
        healthContext: const FemaleAthleteHealthContext(),
      );

      final dec = engine.decide(
        state: baseState,
        needResult: vo2NeedResult,
        availability: availability,
        femaleContext: lutealCtx,
      );

      expect(dec.actionType, equals(CoachingActionType.prescribedWorkout));
      expect(
        dec.prescribedWorkout?.family,
        isIn([WorkoutFamilyType.vo2maxIntervals, WorkoutFamilyType.thresholdIntervals, WorkoutFamilyType.easyBase]),
      );
      expect(dec.safetyConstraintsApplied.any((s) => s.reason.contains('Luteal')), isFalse);
    });

    test('D. Menstruation (Day 1) alone without symptoms -> NO automatic rest day', () {
      final mensesNoSymptomsCtx = FemaleAthleteContext(
        cycleContext: CycleContext(
          optIn: FemaleCycleTrackingOptIn.enabled,
          hormonalStatus: HormonalStatus.naturalCycle,
          currentCycleDay: 1,
          estimatedPhase: CyclePhaseEstimate.earlyFollicularMenstrual,
          phaseConfidence: 0.85,
          inferenceMethod: CycleInferenceMethod.bleedingBased,
          asOf: now,
        ),
        evidence: const CycleResponseEvidence(insufficientHistory: true),
        healthContext: const FemaleAthleteHealthContext(),
        todaysSymptoms: DailyCycleSymptomReport(
          date: now,
          cramps: SymptomSeverity.none,
          headache: SymptomSeverity.none,
          giSymptoms: SymptomSeverity.none,
          unusualFatigue: SymptomSeverity.none,
        ),
      );

      final dec = engine.decide(
        state: baseState,
        needResult: needResult,
        availability: availability,
        femaleContext: mensesNoSymptomsCtx,
      );

      expect(dec.actionType, equals(CoachingActionType.prescribedWorkout));
      expect(dec.prescribedWorkout, isNotNull);
    });

    test('E. Severe acute symptoms -> Safety rest/recovery triggered regardless of phase', () {
      final severeSymptomsCtx = FemaleAthleteContext(
        cycleContext: CycleContext(
          optIn: FemaleCycleTrackingOptIn.enabled,
          hormonalStatus: HormonalStatus.naturalCycle,
          currentCycleDay: 1,
          estimatedPhase: CyclePhaseEstimate.earlyFollicularMenstrual,
          phaseConfidence: 0.85,
          asOf: now,
        ),
        evidence: const CycleResponseEvidence(insufficientHistory: true),
        healthContext: const FemaleAthleteHealthContext(),
        todaysSymptoms: DailyCycleSymptomReport(
          date: now,
          cramps: SymptomSeverity.severe,
          headache: SymptomSeverity.moderate,
          unusualFatigue: SymptomSeverity.severe,
          notes: 'Starke Unterleibskrämpfe und Übelkeit',
        ),
      );

      final dec = engine.decide(
        state: baseState,
        needResult: needResult,
        availability: availability,
        femaleContext: severeSymptomsCtx,
      );

      expect(dec.actionType, isIn([CoachingActionType.restDay, CoachingActionType.activeRecovery]));
      expect(dec.safetyConstraintsApplied.any((s) => s.reason.contains('Symptome')), isTrue);
    });

    test('F. Less than 3 cycles or inconsistent observations -> Insufficient history confidence', () {
      final periods = [
        RecordedCyclePeriod(id: 'p1', startDate: now.subtract(const Duration(days: 28))),
        RecordedCyclePeriod(id: 'p2', startDate: now.subtract(const Duration(days: 56))),
      ];

      final evidence = cycleEngine.analyzePatterns(
        athleteId: 'ath_female_1',
        periods: periods,
        symptomReports: [],
        sessions: [],
        asOfDate: now,
      );

      expect(evidence.insufficientHistory, isTrue);
      expect(evidence.patterns, isEmpty);
    });

    test('G. >= 3 cycles with consistent lower Ercolina power on symptom days -> Personal pattern formed', () {
      final periods = [
        RecordedCyclePeriod(id: 'p1', startDate: now.subtract(const Duration(days: 28))),
        RecordedCyclePeriod(id: 'p2', startDate: now.subtract(const Duration(days: 56))),
        RecordedCyclePeriod(id: 'p3', startDate: now.subtract(const Duration(days: 84))),
        RecordedCyclePeriod(id: 'p4', startDate: now.subtract(const Duration(days: 112))),
      ];

      final symptoms = <DailyCycleSymptomReport>[];
      final sessions = <NormalizedSession>[];

      // 4 symptom days with Ercolina sessions at 130 W
      for (int i = 0; i < 4; i++) {
        final d = now.subtract(Duration(days: 28 * (i + 1)));
        symptoms.add(
          DailyCycleSymptomReport(
            date: d,
            cramps: SymptomSeverity.moderate,
          ),
        );
        sessions.add(
          NormalizedSession(
            id: 'erc_sym_$i',
            athleteId: 'ath_female_1',
            source: NormalizedSessionSource.ercolina,
            sourceId: 'src_$i',
            startedAtUtcUs: d.microsecondsSinceEpoch,
            durationSeconds: 1800,
            movingTimeSeconds: 1800,
            modality: XcModality.ercolinaDoublePoling,
            isIndoor: true,
            title: 'Ercolina DP Standard',
            externalMetrics: const SessionExternalMetrics(
              sessionAveragePowerWatt: 130.0,
            ),
          ),
        );
      }

      // 4 non-symptom days with Ercolina sessions at 155 W (> 15% difference!)
      for (int i = 0; i < 4; i++) {
        final d = now.subtract(Duration(days: 28 * (i + 1) - 10));
        symptoms.add(
          DailyCycleSymptomReport(
            date: d,
            cramps: SymptomSeverity.none,
          ),
        );
        sessions.add(
          NormalizedSession(
            id: 'erc_norm_$i',
            athleteId: 'ath_female_1',
            source: NormalizedSessionSource.ercolina,
            sourceId: 'src_norm_$i',
            startedAtUtcUs: d.microsecondsSinceEpoch,
            durationSeconds: 1800,
            movingTimeSeconds: 1800,
            modality: XcModality.ercolinaDoublePoling,
            isIndoor: true,
            title: 'Ercolina DP Standard',
            externalMetrics: const SessionExternalMetrics(
              sessionAveragePowerWatt: 155.0,
            ),
          ),
        );
      }

      final evidence = cycleEngine.analyzePatterns(
        athleteId: 'ath_female_1',
        periods: periods,
        symptomReports: symptoms,
        sessions: sessions,
        asOfDate: now,
      );

      expect(evidence.insufficientHistory, isFalse);
      expect(evidence.patterns.isNotEmpty, isTrue);
      final p = evidence.patterns.first;
      expect(p.outcome, equals(PatternOutcome.lowerErcolinaPower));
      expect(p.confidence, equals(PatternConfidence.repeated));
    });

    test('H. Hormonal contraception user -> NO natural cycle phases inferred', () {
      final hcContext = cycleEngine.buildCycleContext(
        optIn: FemaleCycleTrackingOptIn.enabled,
        hormonalStatus: HormonalStatus.combinedHormonalContraceptive,
        periods: [RecordedCyclePeriod(id: 'p1', startDate: now.subtract(const Duration(days: 14)))],
        asOfDate: now,
      );

      expect(hcContext.hormonalStatus.isHormonalContraceptive, isTrue);
      expect(hcContext.estimatedPhase, equals(CyclePhaseEstimate.activePillPhase));
    });

    test('I. Health signal trigger on prolonged cycle absence (> 90 days) without diagnosing RED-S', () {
      final periods = [
        RecordedCyclePeriod(id: 'p1', startDate: now.subtract(const Duration(days: 110))),
      ];

      final health = cycleEngine.evaluateHealthSignals(
        athleteId: 'ath_female_1',
        hormonalStatus: HormonalStatus.naturalCycle,
        periods: periods,
        symptomReports: [],
        ironRecords: [],
        asOfDate: now,
      );

      expect(health.hasActiveHealthSignals, isTrue);
      final signal = health.activeSignals.firstWhere(
        (s) => s.type == HealthSignalType.prolongedAbsence,
      );
      expect(signal.title, contains('Ausbleiben'));
      expect(signal.medicalDisclaimer, contains('keine medizinischen Diagnosen'));
    });
  });
}
