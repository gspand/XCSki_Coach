/// Compact, lossless-for-analysis features extracted from large activity
/// streams.
///
/// The original streams remain in `normalized_session_record.data_json` as
/// source evidence. Normal UI and coaching reads use these features instead,
/// so opening an athlete does not deserialize years of GPS and sample arrays.
library;

const String normalizedStreamFeaturesKey = 'streamFeatures';
const String heartRateSecondsByBpmKey = 'heartRateSecondsByBpm';
const String observedPeakPowerWattKey = 'observedPeakPowerWatt';

/// Returns a copy of a normalized-session JSON object without its large raw
/// streams, augmented with the two stream-derived facts currently consumed by
/// the athlete-state builder.
Map<String, dynamic> compactNormalizedSessionForAnalysis(
  Map<String, dynamic> source,
) {
  final compact = Map<String, dynamic>.from(source);
  final raw = source['rawMetadata'];
  if (raw is! Map) return compact;

  final metadata = <String, dynamic>{
    for (final entry in raw.entries) entry.key.toString(): entry.value,
  };
  // Full provider payload stays in data_json. Avoid decoding GPS tracks
  // from multi-year Garmin history on each recommendation.
  metadata.remove('garmin');
  final streams = metadata.remove('streams');
  if (streams is Map) {
    final movingTimeSeconds =
        (source['movingTimeSeconds'] as num?)?.toInt() ?? 0;
    final features = buildNormalizedStreamFeatures(
      streams,
      movingTimeSeconds: movingTimeSeconds,
    );
    if (features.isNotEmpty) {
      metadata[normalizedStreamFeaturesKey] = features;
    }
  }
  compact['rawMetadata'] = metadata;
  return compact;
}

/// Extracts a compact heart-rate time histogram and observed peak power.
///
/// Heart-rate intervals use the same gap-preserving rule as the historical
/// direct-stream analysis: intervals larger than five times the median (and
/// at least ten seconds) are omitted. Nothing is interpolated across gaps.
Map<String, dynamic> buildNormalizedStreamFeatures(
  Map<dynamic, dynamic> streams, {
  required int movingTimeSeconds,
}) {
  final features = <String, dynamic>{};

  final heartRates = _streamNumbers(streams['heartrate']);
  final times = _streamNumbers(streams['time']);
  final sampleCount = heartRates.length < times.length
      ? heartRates.length
      : times.length;
  if (sampleCount >= 2 && movingTimeSeconds > 0) {
    final positiveIntervals = <int>[];
    for (var index = 0; index < sampleCount - 1; index++) {
      final interval = (times[index + 1] - times[index]).round();
      if (interval > 0) positiveIntervals.add(interval);
    }
    if (positiveIntervals.isNotEmpty) {
      positiveIntervals.sort();
      final medianInterval = positiveIntervals[positiveIntervals.length ~/ 2];
      final largestContinuousInterval = medianInterval * 5 > 10
          ? medianInterval * 5
          : 10;
      final secondsByBpm = <String, int>{};
      var classifiedSeconds = 0;
      for (var index = 0; index < sampleCount - 1; index++) {
        var interval = (times[index + 1] - times[index]).round();
        final heartRate = heartRates[index];
        if (interval <= 0 ||
            interval > largestContinuousInterval ||
            !heartRate.isFinite ||
            heartRate <= 0) {
          continue;
        }
        final remaining = movingTimeSeconds - classifiedSeconds;
        if (remaining <= 0) break;
        if (interval > remaining) interval = remaining;
        final key = heartRate.toString();
        secondsByBpm.update(
          key,
          (value) => value + interval,
          ifAbsent: () => interval,
        );
        classifiedSeconds += interval;
      }
      if (secondsByBpm.isNotEmpty) {
        features[heartRateSecondsByBpmKey] = secondsByBpm;
      }
    }
  }

  final watts = _streamNumbers(streams['watts']);
  double? peakPower;
  for (final value in watts) {
    if (!value.isFinite || value <= 0) continue;
    if (peakPower == null || value > peakPower) peakPower = value;
  }
  if (peakPower != null) {
    features[observedPeakPowerWattKey] = peakPower;
  }

  return features;
}

/// Reconstructs the exact zone totals for the athlete's current HRmax from
/// the compact per-BPM histogram.
Map<String, int> heartRateZonesFromStreamFeatures(
  dynamic rawFeatures, {
  required int? maxHeartRateBpm,
}) {
  if (maxHeartRateBpm == null || maxHeartRateBpm <= 0 || rawFeatures is! Map) {
    return const {};
  }
  final rawHistogram = rawFeatures[heartRateSecondsByBpmKey];
  if (rawHistogram is! Map) return const {};

  final zones = <String, int>{};
  for (final entry in rawHistogram.entries) {
    final heartRate = double.tryParse(entry.key.toString());
    final seconds = entry.value is num ? (entry.value as num).toInt() : null;
    if (heartRate == null ||
        !heartRate.isFinite ||
        heartRate <= 0 ||
        seconds == null ||
        seconds <= 0) {
      continue;
    }
    final ratio = heartRate / maxHeartRateBpm;
    final zone = ratio < .60
        ? 'z1'
        : ratio < .70
        ? 'z2'
        : ratio < .80
        ? 'z3'
        : ratio < .90
        ? 'z4'
        : 'z5';
    zones.update(zone, (value) => value + seconds, ifAbsent: () => seconds);
  }
  return Map.unmodifiable(zones);
}

double? peakPowerFromStreamFeatures(dynamic rawFeatures) {
  if (rawFeatures is! Map) return null;
  final value = rawFeatures[observedPeakPowerWattKey];
  return value is num && value.isFinite && value > 0 ? value.toDouble() : null;
}

List<double> _streamNumbers(dynamic stream) {
  final dynamic data = stream is Map ? stream['data'] : stream;
  if (data is! List) return const [];
  return data.whereType<num>().map((value) => value.toDouble()).toList();
}
