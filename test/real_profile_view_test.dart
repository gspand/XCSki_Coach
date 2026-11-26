import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/app/canonical_today.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_coach/ui/design_system.dart';
import 'package:xc_coach/ui/today/today_screen.dart';
import 'package:xc_ski_coach/coach_store.dart';

void main() {
  final file = Platform.environment['XC_PREVIEW_ARCHIVE'];
  testWidgets(
    'real private profiles render their own canonical recommendation read-only',
    (tester) async {
      final store = CoachStore(GiuliaDatabase.readOnly(file!));
      addTearDown(store.db.dispose);
      final engine = CanonicalTodayService(
        stateService: store.state,
        storage: store.storage,
        persistDecisions: false,
        goalRepository: store.goals,
        planRepository: store.plans,
      );
      for (final athlete in store.athletes) {
        final today = engine.of(athlete.id);
        await tester.pumpWidget(
          MaterialApp(
            theme: giuliaLightTheme(mode: ProductMode.coach),
            home: TodayScreen(
              key: ValueKey(athlete.id),
              initialState: today.state,
              initialDecision: today.decision,
              initialNeeds: today.needs,
              initialAvailability: today.availability,
              initialFemaleContext: today.femaleContext,
              athleteName: athlete.name,
              athleteId: athlete.id,
              showAppBar: false,
              showAthleteSwitcher: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TodayScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
    skip: file == null,
  );
}
