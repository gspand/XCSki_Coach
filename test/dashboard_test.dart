import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/app/canonical_today.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'package:xc_ski_coach/coach_store.dart';
import 'package:xc_ski_coach/dashboard.dart';
import 'package:xc_ski_coach/garmin_personal.dart';
import 'package:xc_ski_coach/main.dart';
import 'package:xc_ski_coach/workout_header.dart';
import 'package:xc_ski_coach/health_trend.dart';

void main() {
  testWidgets(
    'phone dashboard opens coach and shows dated Garmin data only on the correct profile',
    (tester) async {
      final store = CoachStore(GiuliaDatabase.inMemory())..createProfiles();
      addTearDown(store.db.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 780);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final archive = GarminArchive(store, 'own-athlete')
        ..save('2026-11-20', 'hrv', {
          'hrvSummary': {'lastNightAvg': 73},
        });
      archive.setCycle(true);
      archive.save('2026-11-20', 'cycle', {'dayInCycle': 9});
      await tester.pumpWidget(MaterialApp(home: CoachHome(store: store)));
      await tester.pumpAndSettle();
      final overview = tester.widget<WorkoutHeader>(find.byType(WorkoutHeader));
      final heading = tester
          .widget<Text>(find.byKey(const ValueKey('daily-workout-title')))
          .data;
      await tester.tap(find.text('Training ansehen'));
      await tester.pumpAndSettle();
      expect(find.byType(SkiDashboard), findsNothing);
      final detail = tester.widget<WorkoutHeader>(find.byType(WorkoutHeader));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('daily-workout-title')))
            .data,
        heading,
      );
      expect(detail.workout.durationMinutes, overview.workout.durationMinutes);
      expect(
        detail.workout.qualitativeIntensity,
        overview.workout.qualitativeIntensity,
      );
      expect(detail.planNote, overview.planNote);
      await tester.tap(find.text('Übersicht').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('73 ms'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Zyklustag'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('athlete-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Karina').last);
      await tester.pumpAndSettle();
      expect(find.text('73 ms'), findsNothing);
      expect(find.text('Zyklustag'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'weekly Garmin plots preserve gaps, profile boundaries and cycle consent',
    () {
      final store = CoachStore(GiuliaDatabase.inMemory())..createProfiles();
      addTearDown(store.db.dispose);
      final a = GarminArchive(store, 'own-athlete')
        ..save('2026-11-22', 'hrv', {
          'hrvSummary': {'lastNightAvg': 54},
        })
        ..save('2026-11-24', 'hrv', {
          'hrvSummary': {'lastNightAvg': 62},
        });
      const end = CalendarDay(2026, 11, 26);
      expect(HealthMeasure.hrv.series(a, end), [
        null,
        null,
        54,
        null,
        62,
        null,
        null,
      ]);
      expect(
        HealthMeasure.hrv.series(GarminArchive(store, 'karina-puercher'), end),
        everyElement(isNull),
      );
      expect(HealthMeasure.cycle.series(a, end), everyElement(isNull));
    },
  );
  final path = Platform.environment['XC_PREVIEW_ARCHIVE'];
  testWidgets(
    'real archive renders both dashboards and opens the correct planning day',
    (tester) async {
      final s = CoachStore(GiuliaDatabase.readOnly(path!));
      addTearDown(s.db.dispose);
      final engine = CanonicalTodayService(
        stateService: s.state,
        goalRepository: s.goals,
        planRepository: s.plans,
      );
      final day = CalendarDay.ofLocal(DateTime.now());
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final a in s.athletes) {
        CalendarDay? picked;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SkiDashboard(
                key: ValueKey(a.id),
                store: s,
                athlete: a.id,
                name: a.name,
                day: day,
                today: engine.of(a.id),
                onWorkout: () {},
                onPlan: () {},
                onGoals: () {},
                onSchedule: (d) => picked = d,
                onChanged: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Nächste Woche'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Einheit planen'));
        expect(picked, day.addDays(7));
        expect(tester.takeException(), isNull);
      }
    },
    skip: path == null,
  );
}
