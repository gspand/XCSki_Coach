import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'package:xc_coach/presentation/decision_card.dart';
import 'package:xc_ski_coach/coach_store.dart';
import 'package:xc_ski_coach/month_plan.dart';
import 'package:xc_ski_coach/schedule.dart';

void main() {
  testWidgets(
    'Month navigation, recommendation revision and planning belong to selected athlete',
    (tester) async {
      final store = CoachStore(GiuliaDatabase.inMemory())..createProfiles();
      addTearDown(store.db.dispose);
      final athlete = store.athletes.last;
      final decision = store.today.of(athlete.id).decision;
      await tester.pumpWidget(
        MaterialApp(
          home: MonthPlan(store: store, athlete: athlete),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(decision.decisionId), findsOneWidget);
      await tester.tap(find.byTooltip('Nächster Monat'));
      await tester.pumpAndSettle();
      expect(find.textContaining(decision.decisionId), findsNothing);
      await tester.ensureVisible(find.byTooltip('Einheit planen'));
      await tester.tap(find.byTooltip('Einheit planen'));
      await tester.pumpAndSettle();
      final screen = tester.widget<Schedule>(find.byType(Schedule));
      expect(screen.athlete.id, athlete.id);
      final now = DateTime.now();
      expect(
        screen.initialDay,
        CalendarDay.ofLocal(DateTime(now.year, now.month + 1, 1)),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
