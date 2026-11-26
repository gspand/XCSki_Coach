import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/intelligence/deterministic_analysis.dart';
import 'package:xc_coach/intelligence/models.dart';

import 'fake_intelligence_data.dart';

void main() {
  const analyzer = LongitudinalIntelligence();

  test('compares only the shared diagnostic axis', () {
    final result = analyzer.compare(
      intelligenceTest(id: 'a', at: 1, lt1: 180, lt2: 240),
      intelligenceTest(id: 'b', at: 2, lt1: 190, lt2: 252),
    );

    expect(result.comparable, isTrue);
    final lt1 = result.trends.firstWhere((item) => item.parameter == 'lt1');
    expect(lt1.delta, 10);
    expect(lt1.deltaPercent, closeTo(5.555, .01));
    expect(lt1.direction, TrendDirection.improving);
    expect(
      lt1.evidence.every(
        (item) => item.source == IntelligenceSource.lalaEngine,
      ),
      isTrue,
    );
  });

  test('blocks sport-specific threshold comparison', () {
    final result = analyzer.compare(
      intelligenceTest(id: 'bike', at: 1),
      intelligenceTest(id: 'run', at: 2, sport: 'running', unit: 'km/h'),
    );

    expect(result.comparable, isFalse);
    expect(result.confidence, IntelligenceConfidence.insufficient);
    expect(result.caveats.single, contains('unterschiedlichen Sportarten'));
    expect(result.trends, isEmpty);
  });

  test('keeps a method change transparent', () {
    final result = analyzer.compare(
      intelligenceTest(id: 'a', at: 1),
      intelligenceTest(id: 'b', at: 2, lt2Method: 'other-method'),
    );

    expect(result.comparable, isTrue);
    expect(result.caveats.join(' '), contains('unterschiedlichen Methoden'));
    expect(
      result.trends.firstWhere((item) => item.parameter == 'lt2').confidence,
      IntelligenceConfidence.low,
    );
  });

  test('compares lactate only at an actually shared load', () {
    final result = analyzer.compare(
      intelligenceTest(
        id: 'a',
        at: 1,
        lactate: const [1.3, 1.5, 2.3, 4.2, 7.1],
      ),
      intelligenceTest(
        id: 'b',
        at: 2,
        lactate: const [1.2, 1.4, 1.9, 3.6, 6.5],
      ),
    );
    final trend = result.trends.firstWhere(
      (item) => item.parameter == 'lactate_at_common_load',
    );

    expect(trend.delta, closeTo(-.6, 1e-9));
    expect(trend.direction, TrendDirection.improving);
    expect(trend.evidence, hasLength(2));
    expect(trend.caveat, contains('Tagesunterschied'));
  });

  test('names a three-test plateau without claiming deterioration', () {
    final trends = analyzer.trends([
      intelligenceTest(id: 'c', at: 3, lt1: 181, lt2: 241),
      intelligenceTest(id: 'b', at: 2, lt1: 180, lt2: 240),
      intelligenceTest(id: 'a', at: 1, lt1: 180, lt2: 240),
    ]);

    final lt1 = trends.firstWhere((item) => item.parameter == 'lt1');
    expect(lt1.direction, TrendDirection.stable);
    expect(lt1.summary, contains('Plateau'));
  });
}
