import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:xc_coach/intelligence/planning/planning_models.dart';
import 'package:xc_coach/intelligence/training_need/goal_feasibility.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/diagnostics_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/evidence_model.dart';

void main() {
  group('GoalFeasibilityEngine', () {
    const engine = GoalFeasibilityEngine();

    test('Marathon in 2:15:00 is objectively infeasible for recreational/non-world-class runners', () {
      final goal = TrainingGoal(
        name: 'Berlin Marathon',
        modality: TrainingModality.running,
        distanceKm: 42.195,
        targetSeconds: 2 * 3600 + 15 * 60, // 2:15:00 -> 3:11 min/km (18.75 km/h)
        priority: GoalPriority.a,
        day: const CalendarDay(2027, 9, 26),
      );

      // Athlet hat z.B. LTP2 bei 13.5 km/h (4:26 min/km)
      final diagnostics = DiagnosticsState(
        references: {
          XcModality.running: DiagnosticReference(
            modality: XcModality.running,
            date: DateTime(2026, 9, 1),
            protocol: 'Stufentest Laufen',
            lt2Ltp2Watt: 250,
            lt2Ltp2PaceSecPerKm: 266, // 4:26 min/km -> 13.5 km/h
            source: 'test_run_1',
            freshness: FreshnessLevel.fresh,
          ),
        },
      );

      final verdict = engine.evaluateGoal(
        goal: goal,
        diagnostics: diagnostics,
        now: DateTime(2026, 10, 4),
      );

      expect(verdict.status, equals(FeasibilityStatus.infeasible));
      expect(verdict.isAchievable, isFalse);
      expect(verdict.targetPaceMinPerKm, isNotNull);
      expect(verdict.headline, contains('Physiologisch nicht erreichbar'));
      expect(verdict.reasoning, contains('biologisch unmöglich'));
    });

    test('Marathon in 3:30:00 with adequate threshold is realistic', () {
      final goal = TrainingGoal(
        name: 'Frankfurt Marathon',
        modality: TrainingModality.running,
        distanceKm: 42.195,
        targetSeconds: 3 * 3600 + 30 * 60, // 3:30:00 -> 4:58 min/km (12.05 km/h)
        priority: GoalPriority.a,
        day: const CalendarDay(2027, 10, 25),
      );

      // Athlet hat LT2 bei 13.5 km/h (4:26 min/km)
      final diagnostics = DiagnosticsState(
        references: {
          XcModality.running: DiagnosticReference(
            modality: XcModality.running,
            date: DateTime(2026, 9, 1),
            protocol: 'Stufentest Laufen',
            lt2Ltp2Watt: 250,
            lt2Ltp2PaceSecPerKm: 266,
            source: 'test_run_1',
            freshness: FreshnessLevel.fresh,
          ),
        },
      );

      final verdict = engine.evaluateGoal(
        goal: goal,
        diagnostics: diagnostics,
        now: DateTime(2026, 10, 4),
      );

      expect(verdict.isAchievable, isTrue);
      expect(verdict.status == FeasibilityStatus.realistic || verdict.status == FeasibilityStatus.ambitious, isTrue);
    });

    test('Engadin Skimarathon with realistic duration is realistic', () {
      final goal = TrainingGoal(
        name: 'Engadin Skimarathon',
        modality: TrainingModality.skiSkating,
        distanceKm: 42.0,
        targetSeconds: 2 * 3600 + 10 * 60, // 2:10:00 (19.4 km/h)
        priority: GoalPriority.a,
        day: const CalendarDay(2027, 3, 8),
      );

      final verdict = engine.evaluateGoal(
        goal: goal,
        now: DateTime(2026, 10, 4),
      );

      expect(verdict.isAchievable, isTrue);
    });
  });
}
