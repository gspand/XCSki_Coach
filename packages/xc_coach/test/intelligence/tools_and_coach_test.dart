import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/intelligence/coach.dart';
import 'package:xc_coach/intelligence/models.dart';
import 'package:xc_coach/intelligence/tools.dart';

import 'fake_intelligence_data.dart';

void main() {
  const dayUs = Duration.microsecondsPerDay;
  final now = 40 * dayUs;

  test('context builder calls data-specific tools for a lactate question', () {
    final calls = <IntelligenceToolCall>[];
    final tools = GiuliaIntelligenceTools(
      data: FakeIntelligenceData(
        tests: [
          intelligenceTest(id: 'new', at: 2),
          intelligenceTest(id: 'old', at: 1),
        ],
      ),
      observer: calls.add,
    );
    final context = GiuliaContextBuilder(tools).build(
      question: 'Warum war mein Laktat heute höher?',
      athleteId: 'anna',
      nowUtcUs: now,
    );

    expect(context.intent, IntelligenceIntent.lactate);
    expect(
      calls.map((call) => call.name),
      containsAll([
        'getAthleteProfile',
        'getLatestTest',
        'getLactateCurve',
        'compareTests',
        'getTrends',
        'getRelevantAcademyKnowledge',
      ]),
    );
    expect(
      calls.map((call) => call.name),
      isNot(contains('getReadinessContext')),
    );
    expect(context.structured.toJson()['tools'], isNotEmpty);
  });

  test('readiness answer has the required four-part structure', () {
    final coach = GroundedGiuliaCoach(
      GiuliaContextBuilder(
        GiuliaIntelligenceTools(
          data: FakeIntelligenceData(
            sessions: [intelligenceSession(at: now - dayUs, rpe: 9)],
            observations: [
              IntelligenceObservation(
                type: IntelligenceObservationType.rpe,
                observedAtUtcUs: now - dayUs,
                value: 9,
              ),
            ],
          ),
        ),
      ),
    );
    final answer = coach.answer(
      question: 'Soll ich morgen Intervalle machen?',
      athleteId: 'anna',
      nowUtcUs: now,
    );

    expect(answer.kind, CoachAnswerKind.recommendation);
    expect(answer.recommendation, isNotEmpty);
    expect(answer.reasoning, isNotEmpty);
    expect(answer.evidence, isNotEmpty);
    expect(answer.uncertainty, isNotEmpty);
    expect(answer.context.calls, isNotEmpty);
  });

  test('coach never converts incomparable tests into a numeric claim', () {
    final coach = GroundedGiuliaCoach(
      GiuliaContextBuilder(
        GiuliaIntelligenceTools(
          data: FakeIntelligenceData(
            tests: [
              intelligenceTest(
                id: 'run',
                at: 2,
                sport: 'running',
                unit: 'km/h',
              ),
              intelligenceTest(id: 'bike', at: 1),
            ],
          ),
        ),
      ),
    );
    final answer = coach.answer(
      question: 'Vergleiche meine letzten Tests.',
      athleteId: 'anna',
      nowUtcUs: now,
    );

    expect(answer.kind, CoachAnswerKind.limitation);
    expect(
      answer.reasoning.join(' '),
      contains('unterschiedlichen Sportarten'),
    );
    expect(answer.evidence, isEmpty);
  });

  test('threshold values pass through unchanged from the data tool', () {
    final source = FakeIntelligenceData(
      tests: [intelligenceTest(id: 'test', at: 1, lt2: 247.125)],
    );
    final tools = GiuliaIntelligenceTools(data: source);

    final threshold = tools
        .getThresholds('anna', selectedOnly: true)
        .firstWhere((item) => item.type == 'lt2');

    expect(threshold.load, 247.125);
    expect(tools.trace.single.output, isA<List<Map<String, Object?>>>());
  });
}
