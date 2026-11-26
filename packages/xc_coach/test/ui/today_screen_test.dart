import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:xc_coach/intelligence/training_need/training_need_engine.dart';
import 'package:xc_coach/intelligence/training_need/training_need_result.dart';
import 'package:xc_coach/intelligence/workout_selection/availability_context.dart';
import 'package:xc_coach/intelligence/workout_selection/golden_coach_scenarios.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/goal_context.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/subjective_readiness_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/xc_athlete_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/xc_athlete_state_builder.dart';
import 'package:xc_coach/ui/design_system.dart';
import 'package:xc_coach/ui/today/evidence_bottom_sheet.dart';
import 'package:xc_coach/ui/today/quick_check_in_sheet.dart';
import 'package:xc_coach/ui/today/safe_alternatives_sheet.dart';
import 'package:xc_coach/ui/today/today_screen.dart';

void main() {
  const builder = XCAthleteStateBuilder();
  const needEngine = TrainingNeedEngine();
  final baseDate = DateTime.utc(2026, 10, 3, 9, 0);

  final defaultAvailability = DayAvailability(
    date: baseDate,
    availableMinutes: 90,
    environment: TrainingEnvironment.outdoorSnow,
    hasSnow: true,
    hasErcolina: true,
  );

  Widget createWidgetUnderTest({
    required XCAthleteState state,
    required TrainingNeedResult needs,
    DayAvailability? availability,
    Size screenSize = const Size(390, 1600),
    VoidCallback? onOpenDevelopment,
  }) {
    return MaterialApp(
      theme: ThemeData.light(
        useMaterial3: true,
      ).copyWith(scaffoldBackgroundColor: GiuliaTokens.surface0),
      home: MediaQuery(
        data: MediaQueryData(size: screenSize),
        child: TodayScreen(
          initialState: state,
          initialNeeds: needs,
          initialAvailability: availability ?? defaultAvailability,
          athleteName: 'Jan',
          onOpenDevelopment: onOpenDevelopment,
        ),
      ),
    );
  }

  group('TodayScreen Tests', () {
    testWidgets(
      'COACH Today shows compact load snapshot and opens evaluation',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        var opened = false;
        final state = builder.buildState(
          athleteId: 'test_athlete',
          asOf: baseDate,
          lastStravaSync: baseDate,
          lastGarminSync: baseDate,
        );

        await tester.pumpWidget(
          createWidgetUnderTest(
            state: state,
            needs: needEngine.evaluate(state: state),
            onOpenDevelopment: () => opened = true,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('coach-today-load-snapshot')),
          findsOneWidget,
        );
        expect(find.text('ERMÜDUNG'), findsOneWidget);
        expect(find.text('BELASTUNG'), findsOneWidget);
        expect(find.text('FORM*'), findsOneWidget);
        await tester.tap(find.byKey(const Key('open-full-athlete-evaluation')));
        expect(opened, isTrue);
      },
    );

    testWidgets(
      'renders on iPhone with hero workout card, why-today, and action buttons',
      (tester) async {
        tester.view.physicalSize = const Size(390, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final state = builder.buildState(
          athleteId: 'test_athlete',
          asOf: baseDate,
          goal: const GoalContext(
            name: 'Vasaloppet 2027',
            modality: XcModality.skiClassic,
            priority: 'A',
          ),
          subjectiveReadiness: SubjectiveReadinessState(
            recordedAt: baseDate,
            perceivedRecovery: 8.5,
            sleepQuality: 8.0,
          ),
          lastStravaSync: baseDate,
          lastGarminSync: baseDate,
          confirmedRestDays: List.generate(
            28,
            (i) => baseDate.subtract(Duration(days: i)),
          ).toSet(),
        );
        final needs = needEngine.evaluate(state: state);

        await tester.pumpWidget(
          createWidgetUnderTest(state: state, needs: needs),
        );
        await tester.pumpAndSettle();

        // Header greeting
        expect(find.text('Guten Morgen, Jan'), findsOneWidget);

        // Hero Card elements
        expect(find.textContaining('MIN'), findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);

        // Level 2: Warum heute?
        expect(find.text('Warum heute?'), findsOneWidget);
        expect(find.text('Mehr erfahren & Evidenz'), findsOneWidget);

        // Level 3: Alternativen & Quick check-in
        expect(find.text('Heute anders trainieren?'), findsOneWidget);
        expect(find.text('Tagesform & Erholung'), findsOneWidget);
        expect(find.text('Als Nächstes'), findsOneWidget);

        // Safety notes card informs athlete about qualitative pacing when diagnostics are missing on snow
        expect(find.text('Heute beachten'), findsOneWidget);
        expect(
          find.textContaining(
            'Keine sportspezifische Skating-Schwelle gemessen',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('renders responsive split layout on iPad', (tester) async {
      tester.view.physicalSize = const Size(820, 1180);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final state = builder.buildState(
        athleteId: 'test_athlete',
        asOf: baseDate,
        goal: const GoalContext(
          name: 'Vasaloppet 2027',
          modality: XcModality.skiClassic,
          priority: 'A',
        ),
        subjectiveReadiness: SubjectiveReadinessState(
          recordedAt: baseDate,
          perceivedRecovery: 8.5,
          sleepQuality: 8.0,
        ),
        lastStravaSync: baseDate,
        lastGarminSync: baseDate,
      );
      final needs = needEngine.evaluate(state: state);

      await tester.pumpWidget(
        createWidgetUnderTest(
          state: state,
          needs: needs,
          screenSize: const Size(820, 1180),
        ),
      );
      await tester.pumpAndSettle();

      // Greeting
      expect(find.text('Guten Morgen, Jan'), findsOneWidget);

      // In iPad layout, Hero card and WhyToday card are rendered
      expect(find.text('Warum heute?'), findsOneWidget);
      expect(find.text('Heute anders trainieren?'), findsOneWidget);
    });

    testWidgets('tap on "Mehr erfahren & Evidenz" opens EvidenceBottomSheet', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final state = builder.buildState(
        athleteId: 'test_athlete',
        asOf: baseDate,
        goal: const GoalContext(
          name: 'Vasaloppet 2027',
          modality: XcModality.skiClassic,
          priority: 'A',
        ),
        subjectiveReadiness: SubjectiveReadinessState(
          recordedAt: baseDate,
          perceivedRecovery: 8.5,
          sleepQuality: 8.0,
        ),
        lastStravaSync: baseDate,
        lastGarminSync: baseDate,
      );
      final needs = needEngine.evaluate(state: state);

      await tester.pumpWidget(
        createWidgetUnderTest(state: state, needs: needs),
      );
      await tester.pumpAndSettle();

      final moreInfoButton = find.text('Mehr erfahren & Evidenz');
      expect(moreInfoButton, findsOneWidget);

      await tester.tap(moreInfoButton);
      await tester.pumpAndSettle();

      // Bottom Sheet header
      expect(find.byType(EvidenceBottomSheet), findsOneWidget);
      expect(find.text('Warum empfiehlt GIULIA das?'), findsOneWidget);
    });

    testWidgets('tap on "Anpassen" opens QuickCheckInSheet', (tester) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final state = builder.buildState(
        athleteId: 'test_athlete',
        asOf: baseDate,
        goal: const GoalContext(
          name: 'Vasaloppet 2027',
          modality: XcModality.skiClassic,
          priority: 'A',
        ),
        subjectiveReadiness: SubjectiveReadinessState(
          recordedAt: baseDate,
          perceivedRecovery: 8.5,
          sleepQuality: 8.0,
        ),
        lastStravaSync: baseDate,
        lastGarminSync: baseDate,
      );
      final needs = needEngine.evaluate(state: state);

      await tester.pumpWidget(
        createWidgetUnderTest(state: state, needs: needs),
      );
      await tester.pumpAndSettle();

      final adjustButton = find.text('Anpassen');
      expect(adjustButton, findsOneWidget);
      await tester.ensureVisible(adjustButton);
      await tester.pumpAndSettle();

      await tester.tap(adjustButton);
      await tester.pumpAndSettle();

      expect(find.byType(QuickCheckInSheet), findsOneWidget);
      expect(find.text('Wie fühlst du dich heute?'), findsOneWidget);
    });

    testWidgets('tap on "Heute anders trainieren?" opens SafeAlternativesSheet', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final state = builder.buildState(
        athleteId: 'test_athlete',
        asOf: baseDate,
        goal: const GoalContext(
          name: 'Vasaloppet 2027',
          modality: XcModality.skiClassic,
          priority: 'A',
        ),
        subjectiveReadiness: SubjectiveReadinessState(
          recordedAt: baseDate,
          perceivedRecovery: 8.5,
          sleepQuality: 8.0,
        ),
        lastStravaSync: baseDate,
        lastGarminSync: baseDate,
      );
      final needs = needEngine.evaluate(state: state);

      await tester.pumpWidget(
        createWidgetUnderTest(
          state: state,
          needs: needs,
          screenSize: const Size(390, 2400),
        ),
      );
      await tester.pumpAndSettle();

      final alternativesCard = find.text('Heute anders trainieren?');
      expect(alternativesCard, findsOneWidget);
      await tester.ensureVisible(alternativesCard);
      await tester.pumpAndSettle();

      await tester.tap(alternativesCard);
      await tester.pumpAndSettle();

      expect(find.byType(SafeAlternativesSheet), findsOneWidget);
      expect(
        find.text(
          'Wähle eine Option. GIULIA prüft die Sicherheit und berechnet die Empfehlung neu.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders rest day state when safety constraint is severe', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Sickness triggers severe safety constraint
      final state = builder.buildState(
        athleteId: GoldenCoachRunner.athleteId,
        asOf: GoldenCoachRunner.baseDate,
        goal: GoldenCoachRunner.defaultGoal50k,
        subjectiveReadiness: SubjectiveReadinessState(
          recordedAt: GoldenCoachRunner.baseDate,
          illnessSymptoms: const ['Fieber', 'Halsschmerzen'],
        ),
      );
      final needs = needEngine.evaluate(state: state);

      await tester.pumpWidget(
        createWidgetUnderTest(
          state: state,
          needs: needs,
          availability: DayAvailability(
            date: GoldenCoachRunner.baseDate,
            availableMinutes: 60,
            environment: TrainingEnvironment.outdoorSnow,
            hasSnow: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In illness case, engine prescribes rest day
      expect(find.text('AKTIVE ODER PASSIVE ERHOLUNG'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);

      // "Heute beachten" card MUST be displayed
      expect(find.text('Heute beachten'), findsOneWidget);
    });

    testWidgets('shows data limitation note when coverage is low', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final state = builder.buildState(
        athleteId: GoldenCoachRunner.athleteId,
        asOf: GoldenCoachRunner.baseDate,
        goal: GoldenCoachRunner.defaultGoal50k,
        sessions: const [], // 28 unknown days
      );
      final needs = needEngine.evaluate(state: state);

      await tester.pumpWidget(
        createWidgetUnderTest(
          state: state,
          needs: needs,
          availability: DayAvailability(
            date: GoldenCoachRunner.baseDate,
            availableMinutes: 60,
            environment: TrainingEnvironment.outdoorSnow,
            hasSnow: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // "Heute beachten" card displayed due to data limitations.
      //
      // Seit die Entscheidung ihre Dosisanpassung begruendet («Dauer an die
      // aktuelle Langlauf Skating-Exposition angepasst»), ist der
      // Warum-Abschnitt eine Zeile laenger und diese Karte liegt unterhalb
      // des Viewports. Die Zusage des Tests ist, dass sie *existiert* —
      // nicht, dass sie ohne Scrollen sichtbar ist.
      final hinweis = find.text('Heute beachten');
      await tester.scrollUntilVisible(hinweis, 200);
      expect(hinweis, findsOneWidget);
    });
  });
}
