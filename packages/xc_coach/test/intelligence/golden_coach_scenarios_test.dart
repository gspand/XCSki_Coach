import 'package:xc_coach/intelligence/workout_selection/user_override_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:xc_coach/intelligence/load/stimulus_models.dart';
import 'package:xc_coach/intelligence/training_need/need_types.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/subjective_readiness_state.dart';
import 'package:xc_coach/intelligence/workout_selection/availability_context.dart';
import 'package:xc_coach/intelligence/workout_selection/coach_validation_mode.dart';
import 'package:xc_coach/intelligence/workout_selection/daily_coaching_decision.dart';
import 'package:xc_coach/intelligence/workout_selection/daily_decision_engine.dart';
import 'package:xc_coach/intelligence/workout_selection/golden_coach_scenarios.dart';
import 'package:xc_coach/intelligence/workout_selection/workout_prescription.dart';

void main() {
  group('Golden Coach Scenarios (10 Real-World Benchmarks)', () {
    const runner = GoldenCoachRunner();

    test(
      'Scenario 1: Fresh Weekend (3h Zeitfenster, gute Erholung) -> Langzeitausdauer',
      () {
        final record = runner.runScenario1FreshWeekend();
        final decision = record.decision;

        expect(decision.actionType, CoachingActionType.prescribedWorkout);
        final workout = decision.prescribedWorkout!;
        expect(workout.family, WorkoutFamilyType.longEndurance);
        expect(workout.totalDurationMinutes, greaterThanOrEqualTo(120));
        expect(
          workout.intendedStimuli.contains(StimulusType.fatigueResistance),
          isTrue,
        );
        expect(workout.recoveryCost, RecoveryCost.extreme);

        // Verbotene Handlungen in diesem Szenario:
        expect(decision.actionType == CoachingActionType.restDay, isFalse);
        expect(
          decision.actionType == CoachingActionType.activeRecovery,
          isFalse,
        );
      },
    );

    test(
      'Scenario 2: Time Crunched (45 min) -> Knackige kurze Einheit, keine gestauchte 2h-Einheit',
      () {
        final record = runner.runScenario2TimeCrunched();
        final decision = record.decision;

        expect(decision.actionType, CoachingActionType.prescribedWorkout);
        final workout = decision.prescribedWorkout!;
        expect(workout.totalDurationMinutes, lessThanOrEqualTo(45));
        expect(workout.family, isNot(WorkoutFamilyType.longEndurance));

        // Verbotene Handlungen:
        expect(workout.totalDurationMinutes > 45, isFalse);
      },
    );

    test(
      'Scenario 3: Block Training (Zweiter intensiver Tag in Folge bei Planung) -> Erlaubt',
      () {
        final record = runner.runScenario3BlockTraining();
        final decision = record.decision;

        // Im Blocktraining darf trotz harter Einheit am Vortag ein zweiter harter Reiz vorgeschrieben werden
        expect(decision.actionType, CoachingActionType.prescribedWorkout);
        final workout = decision.prescribedWorkout!;
        expect(
          workout.intendedStimuli.contains(StimulusType.vo2max) ||
              workout.intendedStimuli.contains(StimulusType.threshold) ||
              workout.intendedStimuli.contains(StimulusType.doublePolingPower),
          isTrue,
        );

        // Verbotene Handlung: Keine Blockierung durch starre 48h-Regel
        final rejected48h = decision.rejectedAlternatives.where(
          (a) =>
              a.reason.contains('48 h') &&
              a.intendedStimulus == StimulusType.vo2max,
        );
        expect(rejected48h.isEmpty, isTrue);
      },
    );

    test(
      'Scenario 4: Severe DOMS / Muskelkater in den Beinen -> Beinschonung',
      () {
        final record = runner.runScenario4SevereDoms();
        final decision = record.decision;

        if (decision.prescribedWorkout != null) {
          // Wenn Training, dann darf es KEIN intensives Skating oder Laufen sein
          final workout = decision.prescribedWorkout!;
          expect(
            workout.modality == XcModality.skiSkating &&
                workout.family == WorkoutFamilyType.thresholdIntervals,
            isFalse,
          );
          expect(workout.family == WorkoutFamilyType.longEndurance, isFalse);
        }

        // Verbotene Handlungen: Skating Schwellenintervalle oder Long Endurance müssen abgelehnt sein
        final rejectedLegWorkouts = decision.rejectedAlternatives.where(
          (a) =>
              a.modality == XcModality.skiSkating &&
              a.reason.contains('unteren Extremität'),
        );
        expect(rejectedLegWorkouts.isNotEmpty, isTrue);
      },
    );

    test(
      'Scenario 5: Poor Sleep & Combined Fatigue -> Ruhetag oder aktive Erholung',
      () {
        final record = runner.runScenario5PoorSleep();
        final decision = record.decision;

        // Bei kombinierter hoher Erschöpfung und schlechtem Schlaf: Erholung oder Ruhetag
        expect(
          decision.actionType == CoachingActionType.restDay ||
              decision.actionType == CoachingActionType.activeRecovery,
          isTrue,
        );

        // Verbotene Reize:
        expect(record.verifyProhibitedStimulus(StimulusType.vo2max), isTrue);
        expect(record.verifyProhibitedStimulus(StimulusType.threshold), isTrue);
      },
    );

    test(
      'Scenario 5b: Isoliert schlechter Schlaf (ohne Erschöpfung) -> Training prinzipiell zulässig',
      () {
        final record = runner.runScenario5bIsolatedPoorSleep();
        final decision = record.decision;

        // Isoliert schlechter Schlaf verbietet Training NICHT pauschal als Safety Gate
        expect(decision.actionType, CoachingActionType.prescribedWorkout);
        expect(decision.prescribedWorkout, isNotNull);
        expect(
          decision.dataLimitations.any((l) => l.contains('Schlafqualität')),
          isTrue,
        );
      },
    );

    test(
      'Scenario 6: Sickness / Fieber -> Strikt Ruhetag (Severe Safety Filter)',
      () {
        final record = runner.runScenario6Sickness();
        final decision = record.decision;

        expect(decision.actionType, CoachingActionType.restDay);
        expect(decision.prescribedWorkout, isNull);
        expect(decision.coachingReason, contains('Infekt'));

        // Verbotene Handlung: Jede Art von körperlicher Trainingsverschreibung
        expect(record.verifyProhibitedStimulus(StimulusType.recovery), isTrue);
      },
    );

    test('Scenario 7: Acute Joint Pain (Knie) -> Kein Skating/Lauf', () {
      final record = runner.runScenario7AcuteJointPain();
      final decision = record.decision;

      if (decision.prescribedWorkout != null) {
        expect(
          decision.prescribedWorkout!.modality,
          isNot(XcModality.skiSkating),
        );
        expect(decision.prescribedWorkout!.modality, isNot(XcModality.running));
      }

      // Skating muss wegen Knieschmerzen im Sicherheitsfilter abgelehnt sein
      final rejectedKnee = decision.rejectedAlternatives.where(
        (a) =>
            (a.modality == XcModality.skiSkating ||
                a.modality == XcModality.running) &&
            a.reason.contains('unteren Extremität'),
      );
      expect(rejectedKnee.isNotEmpty, isTrue);
    });

    test('Scenario 8: Missing Diagnostic -> Keine erfundenen Wattzahlen', () {
      final record = runner.runScenario8MissingDiagnostic();
      final decision = record.decision;

      expect(decision.actionType, CoachingActionType.prescribedWorkout);
      final workout = decision.prescribedWorkout!;

      // Es dürfen keine spezifischen Watt-Werte im WorkIntensity vorliegen, wenn keine Diagnostik vorliegt
      expect(workout.workIntensity.isDiagnosticGrounded, isFalse);
      expect(workout.workIntensity.minPowerWatt, isNull);
      expect(workout.workIntensity.maxPowerWatt, isNull);
      expect(workout.workIntensity.rpeTarget.isNotEmpty, isTrue);
    });

    test(
      'Scenario 9: Sparse Data Coverage -> Moderate/Low Confidence & transparenter Hinweis',
      () {
        final record = runner.runScenario9SparseDataCoverage();
        final decision = record.decision;

        expect(decision.confidence, isNot(NeedConfidence.high));
        expect(
          decision.dataLimitations.any((l) => l.contains('Datenabdeckung')),
          isTrue,
        );
        expect(
          decision.dataLimitations.any(
            (l) => l.contains('keine phantomhaften Trainingsdefizite'),
          ),
          isTrue,
        );
      },
    );

    test(
      'Scenario 10: Partial Workout & Meaningful Self-Regulation -> Positiv bewertet',
      () {
        final record = runner.runScenario10SelfRegulation();
        final eval = record.executionEvaluation!;

        expect(eval.athleteModified, isTrue);
        expect(eval.isMeaningfulSelfRegulation, isTrue);
        expect(eval.intervalCompliance, 0.50);
        expect(eval.overallEvaluationText, contains('Selbstregulation'));
        expect(record.nextDayImplication, contains('Erholung priorisieren'));
      },
    );

    test('CoachValidationRecord: Versions & JSON serialization round-trip', () {
      final record = runner.runScenario1FreshWeekend();
      expect(
        record.versions.coachCoreVersion,
        CoachCoreVersions.currentCoreVersion,
      );
      expect(
        record.versions.coachCoreVersion,
        contains('Validation Baseline v1'),
      );

      final json = record.toJson();
      expect(json['id'], isNotNull);
      expect(json['versions'], isNotNull);
      expect(json['before'], isNotNull);
      expect(json['decision'], isNotNull);

      final reconstructed = CoachValidationRecord.fromJson(json);
      expect(reconstructed.id, record.id);
      expect(
        reconstructed.versions.coachCoreVersion,
        record.versions.coachCoreVersion,
      );
      expect(reconstructed.decision.actionType, record.decision.actionType);
      expect(
        reconstructed.decision.coachingReason,
        record.decision.coachingReason,
      );
    });

    test(
      'Shadow Replay: Replays baseline record through candidate engine and detects diffs',
      () {
        final state = runner.builder.buildState(
          athleteId: GoldenCoachRunner.athleteId,
          asOf: GoldenCoachRunner.baseDate,
          goal: GoldenCoachRunner.defaultGoal50k,
          // Dieselbe Historie wie Szenario 1 — sonst vergleicht der Replay
          // zwei verschiedene Athleten und nennt das eine Divergenz.
          sessions: GoldenCoachRunner.scenario1History,
          subjectiveReadiness: SubjectiveReadinessState(
            recordedAt: GoldenCoachRunner.baseDate,
            perceivedRecovery: 8.5,
          ),
        );
        final availability = DayAvailability(
          date: GoldenCoachRunner.baseDate,
          availableMinutes: 180,
          environment: TrainingEnvironment.outdoorSnow,
          hasSnow: true,
          hasErcolina: true,
        );
        final needs = runner.needEngine.evaluate(state: state);
        final baselineRecord = runner.runScenario1FreshWeekend();

        final replayRunner = ShadowReplayRunner();
        final diff = replayRunner.replay(
          baselineRecord: baselineRecord,
          candidateEngine: const DailyDecisionEngine(),
          state: state,
          needResult: needs,
          availability: availability,
          userOverride: const UserOverrideContext(
            focusNeed: TrainingNeedType.longEndurance,
          ),
          candidateVersions: const CoachCoreVersions(
            coachCoreVersion: 'GIULIA XC Coach Core – Candidate v2',
            loadModelVersion: 'LoadModel-2.0',
            stimulusModelVersion: 'StimulusModel-2.0',
            athleteStateModelVersion: 'AthleteState-2.0',
            needEngineVersion: 'NeedEngine-2.0',
            workoutSelectionVersion: 'WorkoutSelection-2.0',
          ),
        );

        // Candidate version matches baseline decision on Scenario 1
        expect(diff.scenarioId, baselineRecord.id);
        expect(diff.actionMatches, isTrue);
        expect(diff.workoutMatches, isTrue);
        expect(diff.confidenceMatches, isTrue);
        expect(
          diff.replayedDecision.actionType,
          CoachingActionType.prescribedWorkout,
        );
        expect(
          diff.candidateVersions.coachCoreVersion,
          contains('Candidate v2'),
        );
        expect(diff.hasDivergence, isFalse);
      },
    );
  });
}
