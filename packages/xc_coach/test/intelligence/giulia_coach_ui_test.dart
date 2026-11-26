import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/database/coach_storage_repository.dart';
import 'package:xc_coach/database/platform_repository.dart';
import 'package:xc_coach/intelligence/coach.dart';
import 'package:xc_coach/intelligence/models.dart';
import 'package:xc_coach/ui/design_system.dart';
import 'package:xc_coach/ui/intelligence/giulia_coach.dart';

import '../support/platform_fixture.dart';

void main() {
  testWidgets('integrated card opens the four-part grounded answer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: giuliaLightTheme(),
        home: const Scaffold(
          body: GiuliaCoachCard(
            coach: _Coach(),
            athletes: [AthleteSummary(id: 'anna', name: 'Anna')],
            questions: ['Was soll ich heute trainieren?'],
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('giulia-intelligence-card')), findsOneWidget);
    await tester.tap(find.byKey(const Key('giulia-intelligence-card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('giulia-athlete-state-entry')), findsOneWidget);
    expect(
      find.byKey(const Key('giulia-analyze-athlete-state')),
      findsOneWidget,
    );
    await tester.tap(
      find.widgetWithText(ActionChip, 'Was soll ich heute trainieren?'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('giulia-answer')), findsOneWidget);
    expect(find.text('EMPFEHLUNG'), findsOneWidget);
    expect(find.text('BEGRÜNDUNG'), findsOneWidget);
    expect(find.text('RELEVANTE DATEN'), findsOneWidget);
    expect(find.text('SICHERHEIT / UNSICHERHEIT'), findsOneWidget);
    expect(find.textContaining('Sicherheit mittel'), findsOneWidget);
  });

  testWidgets('conversation survives closing and reopens at the answer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = PlatformFixture();
    addTearDown(fixture.dispose);
    final organizationId = fixture.organization('club');
    fixture.athlete('anna', organizationId);
    final storage = SqliteCoachStorageRepository(fixture.database);

    Widget screen() => MaterialApp(
      theme: giuliaLightTheme(),
      home: GiuliaCoachScreen(
        coach: const _Coach(),
        athletes: const [AthleteSummary(id: 'anna', name: 'Anna')],
        questions: const ['Was soll ich heute trainieren?'],
        storage: storage,
      ),
    );

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(ActionChip, 'Was soll ich heute trainieren?'),
    );
    await tester.pumpAndSettle();

    expect(storage.loadChatMessages('anna'), hasLength(2));
    expect(find.byKey(const Key('giulia-answer')), findsOneWidget);
    final answerRect = tester.getRect(find.byKey(const Key('giulia-answer')));
    expect(answerRect.top, lessThan(874));
    expect(answerRect.bottom, greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('giulia-answer')), findsOneWidget);
    expect(find.text('Heute kontrolliert trainieren'), findsOneWidget);
    expect(find.text('Lockere Ausdauer ist die robuste Wahl.'), findsOneWidget);
    expect(find.textContaining('Sicherheit mittel'), findsOneWidget);
    expect(find.byKey(const Key('academy-link-lt1')), findsOneWidget);
  });
}

class _Coach implements GiuliaCoach {
  const _Coach();

  @override
  CoachAnswer answer({
    required String question,
    required String athleteId,
    required int nowUtcUs,
  }) => CoachAnswer(
    kind: CoachAnswerKind.recommendation,
    title: 'Heute kontrolliert trainieren',
    recommendation: 'Lockere Ausdauer ist die robuste Wahl.',
    reasoning: const ['Die letzte harte Einheit liegt erst einen Tag zurück.'],
    evidence: const [
      IntelligenceEvidence(
        label: 'Letztes RPE',
        value: 8,
        source: IntelligenceSource.subjective,
      ),
    ],
    uncertainty: const ['Eine subjektive Erholungsangabe fehlt.'],
    confidence: IntelligenceConfidence.moderate,
    knowledge: const [
      AcademyKnowledge(
        articleId: 'lt1',
        title: 'Aerobe Schwelle und ruhige Grundlagenarbeit verstehen',
        summary: 'Grundlagenwissen zur aeroben Schwelle.',
        evidenceLabel: 'wissenschaftlich eingeordnet',
      ),
    ],
    context: StructuredCoachContext(
      question: question,
      athleteId: athleteId,
      calls: const [
        IntelligenceToolCall(
          name: 'getReadinessContext',
          arguments: {},
          output: {},
        ),
      ],
    ),
  );
}
