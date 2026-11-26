import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/intelligence/athlete_state_engine.dart';
import 'package:xc_coach/intelligence/athlete_state_models.dart';
import 'package:xc_coach/intelligence/models.dart';

import 'fake_intelligence_data.dart';

void main() {
  const dayUs = Duration.microsecondsPerDay;
  final now = 400 * dayUs;

  test('builds transparent 7/28/90/180/365-day state dimensions', () {
    final sessions = [
      _session('recent', now - dayUs, provider: 'garmin', power: 250),
      _session('reference', now - 14 * dayUs, provider: 'strava'),
      _session('long-term', now - 120 * dayUs, provider: 'garmin'),
    ];
    final diagnostic = intelligenceTest(
      id: 'lala-test',
      at: now - 30 * dayUs,
      lt1: 180,
      lt2: 240,
      maximum: 300,
    );

    final state = const AthleteStateEngine().build(
      athleteId: 'anna',
      asOfUtcUs: now,
      inputFingerprint: 'fixture',
      sessions: sessions,
      tests: [diagnostic],
      observations: const [],
    );

    expect(state.windows.map((item) => item.days), [7, 28, 90, 180, 365]);
    expect(state.window(7)?.activityCount, 1);
    expect(state.window(28)?.activityCount, 2);
    expect(state.window(365)?.activityCount, 3);
    expect(state.window(7)?.highIntensitySeconds, 3600);
    expect(
      state.dimensions.map((item) => item.key),
      containsAll([
        'aerobic_base',
        'threshold_performance',
        'high_intensity_capacity',
        'training_tolerance',
        'fatigue',
        'current_load',
        'long_term_capacity',
        'data_quality',
      ]),
    );
    final cycling = state.sports.single;
    expect(cycling.anchor('lt1')?.value, 180);
    expect(cycling.anchor('lt2')?.value, 240);
    expect(cycling.anchor('lt2')?.providerId, 'giulia_diagnostic');
    expect(cycling.anchor('lt2')?.authorityRank, 1000);
    expect(
      state.dimension('fatigue')?.assessment,
      contains('nicht zuverlässig'),
    );
    expect(state.dataQuality.providerActivityCounts, {
      'garmin': 2,
      'strava': 1,
    });
  });

  test('round-trips the complete persisted representation', () {
    final state = const AthleteStateEngine().build(
      athleteId: 'anna',
      asOfUtcUs: now,
      inputFingerprint: 'round-trip',
      sessions: [_session('one', now - dayUs, provider: 'garmin')],
      tests: const [],
      observations: const [],
    );

    final restored = AthleteState.fromJson(state.toJson());

    expect(restored.inputFingerprint, 'round-trip');
    expect(restored.windows, hasLength(5));
    expect(restored.dimension('current_load')?.values['activities7Days'], 1);
  });
}

IntelligenceSession _session(
  String id,
  int at, {
  required String provider,
  double power = 160,
}) => IntelligenceSession(
  id: id,
  startedAtUtcUs: at,
  durationSeconds: 3600,
  sport: 'cycling',
  completed: true,
  providerId: provider,
  averagePowerWatt: power,
  peakPowerWatt: power + 40,
  distanceMetres: 30000,
  workJoule: power * 3600,
  averageHeartRateBpm: 145,
  intervals: [
    IntelligenceInterval(
      ordinal: 0,
      durationSeconds: 3600,
      kind: 'work',
      averagePowerWatt: power,
    ),
  ],
);
