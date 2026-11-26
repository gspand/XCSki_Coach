/// Reproduzierbare Herzfrequenz-Auswertung einer aufgezeichneten Einheit.
///
/// Die Berechnung füllt keine Funklücken auf. Ein Messwert gilt nur bis zum
/// nächsten Wert, wenn dieser innerhalb der aus dem tatsächlichen Sampling
/// bestimmten Kontinuitätsgrenze liegt. Damit werden weder der Mittelwert noch
/// die Zonenzeit durch minutenlang gehaltene Werte verfälscht.
library;

import 'dart:math' as math;

import '../core/models.dart';

class HeartRateZoneDuration {
  const HeartRateZoneDuration({
    required this.ordinal,
    required this.duration,
    required this.lowerBpm,
    this.upperBpm,
  });

  /// Nullbasiert: 0 entspricht Z1, 4 entspricht Z5.
  final int ordinal;
  final Duration duration;
  final int lowerBpm;
  final int? upperBpm;

  String get label => 'Z${ordinal + 1}';
}

class HeartRateAnalysis {
  const HeartRateAnalysis({
    required this.samples,
    required this.averageBpm,
    required this.minimumBpm,
    required this.maximumBpm,
    required this.measuredDuration,
    required this.continuityGap,
    required this.sessionStartUtcUs,
    required this.sessionEndUtcUs,
    required this.rejectedContactSamples,
    required this.rrIntervalCount,
    required this.discontinuitiesUtcUs,
    required this.zones,
    this.profileMaximumBpm,
  });

  /// Gültige Werte, zeitlich sortiert. `contactDetected == false` ist entfernt.
  final List<HeartRateSample> samples;
  final double averageBpm;
  final int minimumBpm;
  final int maximumBpm;

  /// Zeit, für die wirklich ein kontinuierliches HF-Signal belegt ist.
  final Duration measuredDuration;

  /// Größere Abstände werden im Diagramm und in der Integration als Lücke
  /// behandelt, nicht mit dem letzten Wert überbrückt.
  final Duration continuityGap;
  final int sessionStartUtcUs;
  final int sessionEndUtcUs;
  final int rejectedContactSamples;
  final int rrIntervalCount;

  /// Zeitstempel des ersten wieder gültigen Werts nach explizit fehlendem
  /// Gurtkontakt. Auch eine kurze Kontaktlücke wird nicht überzeichnet.
  final Set<int> discontinuitiesUtcUs;
  final int? profileMaximumBpm;
  final List<HeartRateZoneDuration> zones;

  Duration get wallDuration =>
      Duration(microseconds: math.max(0, sessionEndUtcUs - sessionStartUtcUs));

  double? get coverage {
    final total = wallDuration.inMicroseconds;
    if (total <= 0) return null;
    return (measuredDuration.inMicroseconds / total).clamp(0.0, 1.0);
  }

  Duration get classifiedDuration => Duration(
    microseconds: zones.fold<int>(
      0,
      (sum, zone) => sum + zone.duration.inMicroseconds,
    ),
  );

  bool get hasZones => profileMaximumBpm != null && zones.isNotEmpty;

  bool isContinuous(HeartRateSample previous, HeartRateSample current) =>
      current.recordedAtUs - previous.recordedAtUs <=
          continuityGap.inMicroseconds &&
      !discontinuitiesUtcUs.contains(current.recordedAtUs);
}

/// Wertet die wirklich gespeicherten HF-Messpunkte aus.
///
/// Der Mittelwert ist zeitgewichtet. Bei nur einem Punkt bleibt er der eine
/// Messwert; daraus entsteht aber keine gemessene Dauer und keine Zonenzeit.
HeartRateAnalysis? analyzeHeartRate(
  Iterable<HeartRateSample> input, {
  required int sessionStartUtcUs,
  required int sessionEndUtcUs,
  int? profileMaximumBpm,
}) {
  final original = input.toList(growable: false);
  final ordered = original.toList(growable: false)
    ..sort((a, b) => a.recordedAtUs.compareTo(b.recordedAtUs));
  final valid = <HeartRateSample>[];
  final discontinuities = <int>{};
  var contactBarrier = false;
  for (final sample in ordered) {
    if (sample.contactDetected == false) {
      contactBarrier = true;
      continue;
    }
    if (sample.bpm < 20 ||
        sample.bpm > 250 ||
        sample.recordedAtUs < sessionStartUtcUs ||
        sample.recordedAtUs > sessionEndUtcUs) {
      continue;
    }
    if (valid.isNotEmpty && contactBarrier) {
      discontinuities.add(sample.recordedAtUs);
    }
    valid.add(sample);
    contactBarrier = false;
  }
  if (valid.isEmpty) return null;

  final intervals = <int>[];
  for (var index = 0; index + 1 < valid.length; index++) {
    final interval = valid[index + 1].recordedAtUs - valid[index].recordedAtUs;
    if (interval > 0) intervals.add(interval);
  }
  intervals.sort();
  final typicalUs = intervals.length >= 3
      ? intervals[intervals.length ~/ 2]
      : Duration.microsecondsPerSecond;
  final continuityUs = math.max(
    10 * Duration.microsecondsPerSecond,
    typicalUs * 5,
  );

  var weightedBpmUs = 0.0;
  var measuredUs = 0;
  final zoneUs = List<int>.filled(5, 0);
  final maximum = profileMaximumBpm != null && profileMaximumBpm > 0
      ? profileMaximumBpm
      : null;

  for (var index = 0; index + 1 < valid.length; index++) {
    final current = valid[index];
    final next = valid[index + 1];
    final intervalUs = next.recordedAtUs - current.recordedAtUs;
    if (intervalUs <= 0 ||
        intervalUs > continuityUs ||
        discontinuities.contains(next.recordedAtUs)) {
      continue;
    }
    final from = math.max(current.recordedAtUs, sessionStartUtcUs);
    final to = math.min(next.recordedAtUs, sessionEndUtcUs);
    final coveredUs = to - from;
    if (coveredUs <= 0) continue;
    measuredUs += coveredUs;
    weightedBpmUs += current.bpm * coveredUs;
    if (maximum != null) {
      final ratio = current.bpm / maximum;
      final zone = ratio < .60
          ? 0
          : ratio < .70
          ? 1
          : ratio < .80
          ? 2
          : ratio < .90
          ? 3
          : 4;
      zoneUs[zone] += coveredUs;
    }
  }

  final average = measuredUs > 0
      ? weightedBpmUs / measuredUs
      : valid.fold<int>(0, (sum, sample) => sum + sample.bpm) / valid.length;
  final minimum = valid.map((sample) => sample.bpm).reduce(math.min);
  final peak = valid.map((sample) => sample.bpm).reduce(math.max);
  final boundaries = maximum == null
      ? const <int>[]
      : <int>[
          (maximum * .60).ceil(),
          (maximum * .70).ceil(),
          (maximum * .80).ceil(),
          (maximum * .90).ceil(),
        ];

  return HeartRateAnalysis(
    samples: List.unmodifiable(valid),
    averageBpm: average,
    minimumBpm: minimum,
    maximumBpm: peak,
    measuredDuration: Duration(microseconds: measuredUs),
    continuityGap: Duration(microseconds: continuityUs),
    sessionStartUtcUs: sessionStartUtcUs,
    sessionEndUtcUs: sessionEndUtcUs,
    rejectedContactSamples: original
        .where((sample) => sample.contactDetected == false)
        .length,
    rrIntervalCount: valid.fold<int>(
      0,
      (sum, sample) => sum + sample.rrIntervalsMs.length,
    ),
    discontinuitiesUtcUs: Set.unmodifiable(discontinuities),
    profileMaximumBpm: maximum,
    zones: maximum == null
        ? const <HeartRateZoneDuration>[]
        : List.unmodifiable([
            HeartRateZoneDuration(
              ordinal: 0,
              duration: Duration(microseconds: zoneUs[0]),
              lowerBpm: 0,
              upperBpm: boundaries[0] - 1,
            ),
            for (var zone = 1; zone < 4; zone++)
              HeartRateZoneDuration(
                ordinal: zone,
                duration: Duration(microseconds: zoneUs[zone]),
                lowerBpm: boundaries[zone - 1],
                upperBpm: boundaries[zone] - 1,
              ),
            HeartRateZoneDuration(
              ordinal: 4,
              duration: Duration(microseconds: zoneUs[4]),
              lowerBpm: boundaries[3],
            ),
          ]),
  );
}
