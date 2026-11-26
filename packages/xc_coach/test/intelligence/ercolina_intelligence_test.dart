import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/intelligence/deterministic_analysis.dart';
import 'package:xc_coach/intelligence/models.dart';

import 'fake_intelligence_data.dart';

void main() {
  const analyzer = ErcolinaIntelligence();

  test('answers how watt was produced, not watt alone', () {
    final result = analyzer.analyze([intelligenceSession(at: 1, power: 200)]);

    expect(result.session, isNotNull);
    final production = result.findings.firstWhere(
      (item) => item.parameter == 'power_production',
    );
    expect(production.summary, contains('J je Zug'));
    expect(production.summary, contains('Zügen/min'));
    expect(production.evidence, hasLength(2));
  });

  test('detects fatigue and interval technique instability', () {
    final result = analyzer.analyze([
      intelligenceSession(
        at: 1,
        fatigue: -16,
        intervals: const [
          IntelligenceInterval(
            ordinal: 1,
            durationSeconds: 300,
            kind: 'work',
            averagePowerWatt: 220,
            leftPowerWatt: 112,
            rightPowerWatt: 108,
          ),
          IntelligenceInterval(
            ordinal: 2,
            durationSeconds: 300,
            kind: 'work',
            averagePowerWatt: 190,
            leftPowerWatt: 108,
            rightPowerWatt: 82,
          ),
        ],
      ),
    ]);

    expect(
      result.findings.firstWhere((item) => item.parameter == 'fatigue').summary,
      contains('fiel'),
    );
    expect(
      result.findings
          .firstWhere((item) => item.parameter == 'interval_stability')
          .summary,
      contains('verloren'),
    );
  });

  test('states which high-resolution technique data is absent', () {
    final result = analyzer.analyze([intelligenceSession(at: 1)]);

    expect(result.missing.join(' '), contains('Zuglänge'));
    expect(result.missing.join(' '), contains('Force-/Power-Kurve'));
  });
}
