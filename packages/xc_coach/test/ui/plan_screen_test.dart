import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'package:xc_coach/intelligence/planning/planning_models.dart';
import 'package:xc_coach/ui/design_system.dart';
import 'package:xc_coach/ui/plan/plan_screen.dart';
import 'package:xc_coach/ui/plan/plan_view_model.dart';

void main() {
  group('PlanScreen Widget Tests', () {
    final today = CalendarDay(2026, 10, 4);

    final goal = TrainingGoal(
      name: 'Engadin Skimarathon',
      day: CalendarDay(2027, 3, 14),
      modality: TrainingModality.skiSkating,
      distanceKm: 42.0,
      targetSeconds: 7200,
    );

    testWidgets('Renders on iPhone layout with goal, week row and week focus', (tester) async {
      tester.view.physicalSize = const Size(393, 852); // iPhone 14/15 Pro
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final vm = PlanViewModel.build(
        today: today,
        primaryGoal: goal,
        weekWorkouts: const [],
        availability: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: giuliaLightTheme(),
          home: PlanScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PLAN'), findsOneWidget);
      expect(find.text('Engadin Skimarathon'), findsOneWidget);
      expect(find.text('SAISONZIEL'), findsOneWidget);
      expect(find.text('DIESE WOCHE'), findsOneWidget);

      // Check weekdays in row
      expect(find.text('Mo'), findsOneWidget);
      expect(find.text('Di'), findsOneWidget);
      expect(find.text('So'), findsOneWidget);

      // Scroll to focus card
      await tester.scrollUntilVisible(
        find.text('SCHWERPUNKT DIESER WOCHE'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('SCHWERPUNKT DIESER WOCHE'), findsOneWidget);
    });

    testWidgets('Renders on iPad layout with split two-column view', (tester) async {
      tester.view.physicalSize = const Size(1024, 1366); // iPad 12.9
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final vm = PlanViewModel.build(
        today: today,
        primaryGoal: goal,
        weekWorkouts: const [],
        availability: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: giuliaLightTheme(),
          home: PlanScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PLAN'), findsOneWidget);
      expect(find.text('Engadin Skimarathon'), findsOneWidget);
      expect(find.text('DIESE WOCHE'), findsOneWidget);

      // Selected day detail panel is shown in right column
      expect(find.text('Noch keine Tagesempfehlung'), findsWidgets);
      expect(vm.activeDay.durationMinutes, 0);
    });

    testWidgets('Shows adaptation banner when plan was adjusted', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final vm = PlanViewModel.build(
        today: today,
        primaryGoal: goal,
        weekWorkouts: const [],
        availability: null,
        recentAdaptationReasons: ['Einheit wegen Müdigkeit von gestern reduziert.'],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: giuliaLightTheme(),
          home: PlanScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PLAN ANGEPASST'), findsOneWidget);
      expect(find.text('Einheit wegen Müdigkeit von gestern reduziert.'), findsOneWidget);
    });
  });
}
