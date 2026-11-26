import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'package:xc_coach/intelligence/planning/planning_models.dart';
import 'package:xc_coach/intelligence/training_need/need_types.dart';
import 'package:xc_coach/intelligence/training_need/training_need.dart';
import 'package:xc_coach/intelligence/training_need/training_need_result.dart';
import 'package:xc_coach/ui/plan/plan_view_model.dart';

void main() {
  group('PlanViewModel Unit Tests', () {
    final today = CalendarDay(2026, 10, 4); // Sonntag (oder beliebiger Tag)

    test('Primary goal formatting and countdown', () {
      final goal = TrainingGoal(
        name: 'Engadin Skimarathon',
        day: CalendarDay(2027, 3, 14),
        modality: TrainingModality.skiSkating,
        distanceKm: 42.0,
        targetSeconds: 7200,
      );

      final vm = PlanViewModel.build(
        today: today,
        primaryGoal: goal,
        weekWorkouts: const [],
        availability: null,
      );

      expect(vm.goal.isConfigured, isTrue);
      expect(vm.goal.name, 'Engadin Skimarathon');
      expect(vm.goal.detail, contains('42 km'));
      expect(vm.goal.detail, contains('Langlauf Skating'));
      expect(vm.goal.detail, contains('2h 00m'));
      expect(vm.goal.countdownText, contains('Noch'));
      expect(vm.goal.targetPaceText, contains('21.0 km/h'));
    });

    test('Empty goal fallback', () {
      final vm = PlanViewModel.build(
        today: today,
        primaryGoal: null,
        weekWorkouts: const [],
        availability: null,
      );

      expect(vm.goal.isConfigured, isFalse);
      expect(vm.goal.name, 'Kein Hauptziel festgelegt');
      expect(vm.goal.countdownText, 'Ziel definieren');
    });

    test('7-day week generation starting on Monday', () {
      final vm = PlanViewModel.build(
        today: today,
        primaryGoal: null,
        weekWorkouts: const [],
        availability: null,
      );

      expect(vm.days.length, 7);
      expect(vm.days.first.weekdayName, 'Mo');
      expect(vm.days.last.weekdayName, 'So');

      final todayItem = vm.days.firstWhere((d) => d.day == today);
      expect(todayItem.status, DayPlanStatus.today);
      expect(todayItem.isTentative, isFalse);
    });

    test('Distinguishes past, today and future tentative states', () {
      final monday = today.weekStart;
      final pastDay = monday; // Da today Sonntag ist, ist Montag in der Vergangenheit
      final futureDay = monday.addDays(7); // Nächste Woche

      final completedWorkout = PlannedWorkout(
        id: 'w1',
        organizationId: 'org1',
        athleteId: 'a1',
        day: pastDay,
        sport: 'ercolina',
        goal: '5x5min EB',
        durationSeconds: 3600,
        status: PlannedWorkoutStatus.completed,
        createdAtUtcUs: 0,
        updatedAtUtcUs: 0,
      );

      final skippedWorkout = PlannedWorkout(
        id: 'w2',
        organizationId: 'org1',
        athleteId: 'a1',
        day: monday.addDays(1),
        sport: 'langlauf',
        goal: 'Lange Ausdauer',
        durationSeconds: 5400,
        status: PlannedWorkoutStatus.skipped,
        createdAtUtcUs: 0,
        updatedAtUtcUs: 0,
      );

      final vm = PlanViewModel.build(
        today: today,
        primaryGoal: null,
        weekWorkouts: [completedWorkout, skippedWorkout],
        availability: null,
      );

      final pastItem = vm.days.firstWhere((d) => d.day == pastDay);
      expect(pastItem.status, DayPlanStatus.completed);
      expect(pastItem.isTentative, isFalse);

      final skippedItem = vm.days.firstWhere((d) => d.day == monday.addDays(1));
      expect(skippedItem.status, DayPlanStatus.skipped);
      expect(skippedItem.missedNotice, isNotNull);
    });

    test('Week focus derivation from real Core Need data', () {
      const primaryNeed = TrainingNeed(
        id: 'need-long-endurance',
        type: TrainingNeedType.longEndurance,
        category: NeedCategory.development,
        priority: NeedPriority.high,
        reasons: ['Vorbereitung auf Renndistanz.'],
        confidence: NeedConfidence.high,
      );

      final needs = TrainingNeedResult(
        asOf: DateTime.utc(2026, 10, 4),
        athleteId: 'a1',
        developmentNeeds: const [primaryNeed],
      );

      final vm = PlanViewModel.build(
        today: today,
        primaryGoal: null,
        weekWorkouts: const [],
        availability: null,
        needs: needs,
      );

      expect(vm.weekFocus.title, primaryNeed.type.label);
      expect(vm.weekFocus.reasoning, contains('Vorbereitung auf Renndistanz.'));
    });

    test('Adaptation banner visibility', () {
      final vm = PlanViewModel.build(
        today: today,
        primaryGoal: null,
        weekWorkouts: const [],
        availability: null,
        recentAdaptationReasons: ['Intensität wegen hoher Vorbelastung reduziert.'],
      );

      expect(vm.activeAdaptationBanner, 'Intensität wegen hoher Vorbelastung reduziert.');
    });
  });
}
