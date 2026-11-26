import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:xc_coach/intelligence/load/stimulus_models.dart';
import 'package:xc_coach/intelligence/training_need/need_types.dart';
import 'package:xc_coach/intelligence/training_need/safety_constraint.dart';
import 'package:xc_coach/intelligence/workout_selection/daily_coaching_decision.dart';
import 'package:xc_coach/intelligence/workout_selection/intensity_prescription.dart';
import 'package:xc_coach/intelligence/workout_selection/workout_prescription.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/xc_athlete_state.dart';
import 'package:xc_coach/ui/today/today_view_model.dart';

void main() {
  group('TodayViewModel Unit Tests', () {
    final now = DateTime.utc(2026, 10, 3, 9, 0);

    test('Formats prescribed workout decision into 4-tier hierarchy', () {
      const workInt = IntensityPrescription(
        modality: XcModality.skiSkating,
        targetType: IntensityTargetType.multiAnchor,
        zoneLabel: 'Z2 Grundlagenausdauer',
        rationale: 'Aerobe Grundlage Z2',
        rpeTarget: 'RPE 2.0–3.0',
        perceivedEffortGuidance: 'Sehr locker bis locker',
        talkTestBreathingCues: 'Sprechen in ganzen Sätzen problemlos möglich',
        terrainGuidance: 'Flach bis leicht kupiertes Gelände',
      );
      const recInt = IntensityPrescription(
        modality: XcModality.skiSkating,
        targetType: IntensityTargetType.multiAnchor,
        zoneLabel: 'Z1 Aktive Erholung',
        rationale: 'Auslaufen',
      );

      final decision = DailyCoachingDecision(
        decisionDate: now,
        athleteId: 'ath_1',
        actionType: CoachingActionType.prescribedWorkout,
        prescribedWorkout: const WorkoutPrescription(
          id: 'skate_base_60',
          title: 'Skating Grundlagenausdauer (60 min)',
          family: WorkoutFamilyType.easyBase,
          modality: XcModality.skiSkating,
          totalDurationMinutes: 60,
          warmupMinutes: 10,
          workMinutes: 40,
          cooldownMinutes: 10,
          structureDescription: '10 min Einlaufen, 40 min GA1, 10 min Auslaufen',
          workIntensity: workInt,
          recoveryIntensity: recInt,
          intendedStimuli: [StimulusType.aerobicBase],
          primaryNeedAddressed: TrainingNeedType.aerobicBase,
          recoveryDemand: RecoveryDemand(
            cost: RecoveryCost.moderate,
            affectedSystems: const {TrainedSystem.systemic, TrainedSystem.lowerBody},
            qualitativeDescription: 'Moderat',
          ),
        ),
        coachingReason: 'Dein Ziel verlangt mehr skispezifische Ausdauer.',
        confidence: NeedConfidence.high,
        backwardTrace: {'decision': 'skate_base_60', 'need': 'aerobic_base'},
      );

      final state = XCAthleteState(athleteId: 'ath_1', asOf: now);
      final vm = TodayViewModel.fromDecision(
        decision: decision,
        state: state,
        athleteName: 'Jan',
      );

      // Greeting & Punchline
      expect(vm.greetingName, 'Guten Morgen, Jan');
      expect(vm.coachPunchline, contains('Ausdauer'));

      // Level 1: Action
      expect(vm.heroTitle, 'Skating Grundlagenausdauer (60 min)');
      expect(vm.modalityLabel, 'Langlauf Skating');
      expect(vm.durationMinutes, 60);
      expect(vm.qualitativeIntensity, QualitativeIntensityLevel.easy);
      expect(vm.phases.summaryText, 'Warm-up 10m · Hauptteil 40m · Cool-down 10m');
      expect(vm.terrainGuidance, 'Flach bis leicht kupiertes Gelände');
      expect(vm.talkTestCue, contains('ganzen Sätzen'));
      expect(vm.isErcolinaStartable, isFalse);

      // Level 2: Why
      expect(vm.whyTodayText, contains('skispezifische Ausdauer'));

      // Level 3: Context
      expect(vm.importantNotes.isEmpty, isTrue);
      expect(vm.hasActiveSafetyConstraint, isFalse);
      expect(vm.confidenceLabel, 'Sehr gute Datenlage');
      expect(vm.safeAlternatives.isNotEmpty, isTrue);

      // Level 4: Evidence
      expect(vm.evidenceTrace['decision'], 'skate_base_60');
    });

    test('Formats rest day with severe health safety constraint', () {
      final decision = DailyCoachingDecision(
        decisionDate: now,
        athleteId: 'ath_1',
        actionType: CoachingActionType.restDay,
        coachingReason: 'Athlet berichtet über Infektsymptome. Ruhe hat Vorrang.',
        safetyConstraintsApplied: const [
          SafetyConstraint(
            id: 'safety_infekt',
            reason: 'Infektsymptome (Fieber, Halskratzen) erfordern strikte Ruhe.',
            severity: SafetyConstraintSeverity.severe,
            evidence: 'subjective_symptoms',
          ),
        ],
        confidence: NeedConfidence.high,
      );

      final state = XCAthleteState(athleteId: 'ath_1', asOf: now);
      final vm = TodayViewModel.fromDecision(
        decision: decision,
        state: state,
        athleteName: 'Jan',
      );

      expect(vm.isRestDay, isTrue);
      expect(vm.heroTitle, 'Ruhetag');
      expect(vm.coachPunchline, contains('Gesundheit'));
      expect(vm.hasActiveSafetyConstraint, isTrue);
      expect(vm.importantNotes.first, contains('Infektsymptome'));
      expect(vm.durationMinutes, 0);
    });

    test('Includes transparent data limitation note when coverage is low', () {
      const workInt = IntensityPrescription(
        modality: XcModality.skiSkating,
        targetType: IntensityTargetType.multiAnchor,
        zoneLabel: 'Z2 Grundlagenausdauer',
        rationale: 'GA1',
        rpeTarget: 'RPE 2–3',
        perceivedEffortGuidance: 'Locker',
        talkTestBreathingCues: 'Ruhig',
      );
      const recInt = IntensityPrescription(
        modality: XcModality.skiSkating,
        targetType: IntensityTargetType.multiAnchor,
        zoneLabel: 'Z1 Aktive Erholung',
        rationale: 'Auslaufen',
      );

      final decision = DailyCoachingDecision(
        decisionDate: now,
        athleteId: 'ath_1',
        actionType: CoachingActionType.prescribedWorkout,
        prescribedWorkout: const WorkoutPrescription(
          id: 'skate_base_45',
          title: 'Skating Grundlagenausdauer (45 min)',
          family: WorkoutFamilyType.easyBase,
          modality: XcModality.skiSkating,
          totalDurationMinutes: 45,
          warmupMinutes: 5,
          workMinutes: 35,
          cooldownMinutes: 5,
          structureDescription: '5 min Einlaufen, 35 min GA1, 5 min Auslaufen',
          workIntensity: workInt,
          recoveryIntensity: recInt,
          intendedStimuli: [StimulusType.aerobicBase],
          primaryNeedAddressed: TrainingNeedType.aerobicBase,
          recoveryDemand: RecoveryDemand(
            cost: RecoveryCost.low,
            affectedSystems: const {TrainedSystem.systemic},
            qualitativeDescription: 'Gering',
          ),
        ),
        coachingReason: 'Beobachtete Datenbasis.',
        dataLimitations: const [
          'Datenabdeckung der letzten 28 Tage unvollständig (20 Tage ohne Synchronisation).',
        ],
        confidence: NeedConfidence.low,
      );

      final state = XCAthleteState(athleteId: 'ath_1', asOf: now);
      final vm = TodayViewModel.fromDecision(decision: decision, state: state);

      expect(vm.confidenceLabel, 'Begrenzte Datenlage');
      expect(vm.dataLimitations.length, 1);
      expect(vm.dataLimitations.first, contains('Datenabdeckung'));
    });
  });
}
