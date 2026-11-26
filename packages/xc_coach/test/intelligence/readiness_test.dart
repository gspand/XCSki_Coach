import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/intelligence/deterministic_analysis.dart';
import 'package:xc_coach/intelligence/models.dart';

import 'fake_intelligence_data.dart';

void main() {
  const analyzer = ReadinessAnalyzer();
  const loadAnalyzer = TrainingLoadAnalyzer();
  const dayUs = Duration.microsecondsPerDay;
  final now = 40 * dayUs;

  ReadinessContext assess(
    List<IntelligenceSession> sessions, {
    List<IntelligenceObservation> observations = const [],
    IntelligenceThreshold? lt2,
  }) {
    final load = loadAnalyzer.analyze(
      sessions: sessions,
      nowUtcUs: now,
      lt2: lt2,
    );
    return analyzer.analyze(
      sessions: sessions,
      observations: observations,
      load: load,
      nowUtcUs: now,
      lt2: lt2,
    );
  }

  const threshold = IntelligenceThreshold(
    type: 'lt2',
    methodId: 'method',
    methodVersion: '1',
    engineVersion: '1',
    status: 'success',
    loadUnit: 'W',
    selected: true,
    load: 240,
  );

  test('refuses pseudo-readiness without training data', () {
    final result = assess(const []);

    expect(result.recommendation, ReadinessRecommendation.insufficient);
    expect(result.confidence, IntelligenceConfidence.insufficient);
    expect(result.missing, contains('Trainingshistorie'));
    expect(result.evidence, isEmpty);
  });

  test('does not recommend intervals shortly after a hard session', () {
    final sessions = [
      intelligenceSession(
        at: now - 12 * Duration.microsecondsPerHour,
        intervals: const [
          IntelligenceInterval(
            ordinal: 1,
            durationSeconds: 600,
            kind: 'work',
            averagePowerWatt: 250,
          ),
        ],
      ),
    ];
    final result = assess(sessions, lt2: threshold);

    expect(result.recommendation, ReadinessRecommendation.easy);
    expect(result.headline, contains('keine harten Intervalle'));
    expect(
      result.evidence.any((item) => item.label.contains('intensiv')),
      isTrue,
    );
  });

  test('classifies an imported running session against a km/h LTP2', () {
    const runningThreshold = IntelligenceThreshold(
      type: 'lt2',
      methodId: 'method',
      methodVersion: '1',
      engineVersion: '1',
      status: 'success',
      loadUnit: 'km/h',
      selected: true,
      load: 14,
    );
    final session = intelligenceSession(
      at: now - 12 * Duration.microsecondsPerHour,
      intervals: const [
        IntelligenceInterval(
          ordinal: 0,
          durationSeconds: 1200,
          kind: 'work',
          averageSpeedKmh: 14.5,
        ),
      ],
    );

    final load = loadAnalyzer.analyze(
      sessions: [session],
      nowUtcUs: now,
      lt2: runningThreshold,
    );
    final readiness = assess([session], lt2: runningThreshold);

    expect(load.intensityClassifiedSeconds7Days, 1200);
    expect(load.highIntensitySeconds7Days, 1200);
    expect(readiness.recommendation, ReadinessRecommendation.easy);
  });

  test('very high RPE yields recovery without a medical claim', () {
    final result = assess(
      [intelligenceSession(at: now - dayUs, rpe: 9)],
      observations: [
        IntelligenceObservation(
          type: IntelligenceObservationType.rpe,
          observedAtUtcUs: now - dayUs,
          value: 9,
        ),
      ],
      lt2: threshold,
    );

    expect(result.recommendation, ReadinessRecommendation.recovery);
    expect(result.reasons.single, contains('sehr hoch'));
  });

  test('reports missing subjective recovery instead of inventing it', () {
    final result = assess([
      intelligenceSession(at: now - 3 * dayUs),
    ], lt2: threshold);

    expect(result.missing.join(' '), contains('subjektive Erholung'));
    expect(result.confidence, isNot(IntelligenceConfidence.high));
  });
}
