/// Provider-independent authority order for externally observed athlete data.
library;

enum ExternalMetric {
  activityIdentity,
  sport,
  timing,
  distance,
  elevation,
  power,
  heartRate,
  trainingLoad,
  recovery,
  hrv,
  restingHeartRate,
  sleep,
  physiologicalThreshold,
}

class SourceAuthorityPolicy {
  const SourceAuthorityPolicy();

  int rank(String providerId, ExternalMetric metric) {
    final provider = providerId.trim().toLowerCase();
    if (provider == 'lala' || provider == 'giulia_diagnostic') {
      return switch (metric) {
        ExternalMetric.physiologicalThreshold => 1000,
        ExternalMetric.heartRate || ExternalMetric.power => 900,
        _ => 500,
      };
    }
    if (provider == 'garmin' || provider == 'garmin_connect') {
      return switch (metric) {
        ExternalMetric.activityIdentity ||
        ExternalMetric.sport ||
        ExternalMetric.timing => 100,
        ExternalMetric.distance ||
        ExternalMetric.elevation ||
        ExternalMetric.power ||
        ExternalMetric.heartRate => 95,
        ExternalMetric.trainingLoad ||
        ExternalMetric.recovery ||
        ExternalMetric.hrv ||
        ExternalMetric.restingHeartRate ||
        ExternalMetric.sleep => 90,
        ExternalMetric.physiologicalThreshold => 30,
      };
    }
    if (provider == 'strava') {
      return switch (metric) {
        ExternalMetric.activityIdentity ||
        ExternalMetric.sport ||
        ExternalMetric.timing ||
        ExternalMetric.distance ||
        ExternalMetric.elevation => 60,
        ExternalMetric.power || ExternalMetric.heartRate => 50,
        ExternalMetric.trainingLoad => 35,
        ExternalMetric.recovery ||
        ExternalMetric.hrv ||
        ExternalMetric.restingHeartRate ||
        ExternalMetric.sleep ||
        ExternalMetric.physiologicalThreshold => 10,
      };
    }
    if (provider == 'transcribed' || provider == 'manual') return 20;
    return 40;
  }

  bool shouldReplace({
    required String currentProviderId,
    required String candidateProviderId,
    required ExternalMetric metric,
  }) => rank(candidateProviderId, metric) > rank(currentProviderId, metric);
}

String normalizeExternalSport(String value) {
  final sport = value.trim().toLowerCase();
  if (sport.contains('cycl') || sport.contains('bike')) return 'cycling';
  if (sport.contains('run') || sport.contains('walk')) return 'running';
  if (sport.contains('ski') || sport.contains('ercolina') || sport.contains('poling')) return 'skiing';
  if (sport.contains('row')) return 'rowing';
  if (sport.contains('strength') || sport.contains('kraft')) return 'strength';
  return sport.isEmpty ? 'generic' : sport;
}

