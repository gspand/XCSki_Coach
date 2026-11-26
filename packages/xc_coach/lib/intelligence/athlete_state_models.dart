/// Persisted, structured athlete context used by all GIULIA AI functions.
///
/// The state is not a diagnosis and deliberately has no opaque global fitness
/// score. It consists of observable time windows, sport-specific calibrated
/// anchors, multidimensional assessments, provenance and explicit gaps.
library;

import 'models.dart';

class AthleteStateEvidence {
  const AthleteStateEvidence({
    required this.metric,
    required this.value,
    required this.providerId,
    required this.authorityRank,
    this.unit,
    this.sourceId,
    this.observedAtUtcUs,
  });

  final String metric;
  final num value;
  final String? unit;
  final String providerId;
  final int authorityRank;
  final String? sourceId;
  final int? observedAtUtcUs;

  Map<String, Object?> toJson() => {
    'metric': metric,
    'value': value,
    if (unit != null) 'unit': unit,
    'providerId': providerId,
    'authorityRank': authorityRank,
    if (sourceId != null) 'sourceId': sourceId,
    if (observedAtUtcUs != null) 'observedAtUtcUs': observedAtUtcUs,
  };

  factory AthleteStateEvidence.fromJson(Map<String, Object?> json) =>
      AthleteStateEvidence(
        metric: json['metric'] as String,
        value: json['value'] as num,
        unit: json['unit'] as String?,
        providerId: json['providerId'] as String,
        authorityRank: json['authorityRank'] as int,
        sourceId: json['sourceId'] as String?,
        observedAtUtcUs: json['observedAtUtcUs'] as int?,
      );
}

class AthleteTrainingWindow {
  const AthleteTrainingWindow({
    required this.days,
    required this.activityCount,
    required this.activeDays,
    required this.activeWeeks,
    required this.durationSeconds,
    required this.distanceMetres,
    required this.workJoule,
    required this.longestGapDays,
    required this.sportDurationSeconds,
    required this.lowIntensitySeconds,
    required this.thresholdIntensitySeconds,
    required this.highIntensitySeconds,
    required this.classifiedIntensitySeconds,
  });

  final int days;
  final int activityCount;
  final int activeDays;
  final int activeWeeks;
  final int durationSeconds;
  final double distanceMetres;
  final double workJoule;
  final double longestGapDays;
  final Map<String, int> sportDurationSeconds;
  final int lowIntensitySeconds;
  final int thresholdIntensitySeconds;
  final int highIntensitySeconds;
  final int classifiedIntensitySeconds;

  double get durationHours => durationSeconds / Duration.secondsPerHour;

  Map<String, Object?> toJson() => {
    'days': days,
    'activityCount': activityCount,
    'activeDays': activeDays,
    'activeWeeks': activeWeeks,
    'durationSeconds': durationSeconds,
    'distanceMetres': distanceMetres,
    'workJoule': workJoule,
    'longestGapDays': longestGapDays,
    'sportDurationSeconds': sportDurationSeconds,
    'intensitySeconds': {
      'low': lowIntensitySeconds,
      'threshold': thresholdIntensitySeconds,
      'high': highIntensitySeconds,
      'classified': classifiedIntensitySeconds,
    },
  };

  factory AthleteTrainingWindow.fromJson(Map<String, Object?> json) {
    final intensity = _map(json['intensitySeconds']);
    final sports = _map(json['sportDurationSeconds']);
    return AthleteTrainingWindow(
      days: json['days'] as int,
      activityCount: json['activityCount'] as int,
      activeDays: json['activeDays'] as int,
      activeWeeks: json['activeWeeks'] as int,
      durationSeconds: json['durationSeconds'] as int,
      distanceMetres: (json['distanceMetres'] as num).toDouble(),
      workJoule: (json['workJoule'] as num).toDouble(),
      longestGapDays: (json['longestGapDays'] as num).toDouble(),
      sportDurationSeconds: {
        for (final entry in sports.entries)
          entry.key: (entry.value as num).round(),
      },
      lowIntensitySeconds: (intensity['low'] as num).round(),
      thresholdIntensitySeconds: (intensity['threshold'] as num).round(),
      highIntensitySeconds: (intensity['high'] as num).round(),
      classifiedIntensitySeconds: (intensity['classified'] as num).round(),
    );
  }
}

class AthleteStateDimension {
  const AthleteStateDimension({
    required this.key,
    required this.label,
    required this.assessment,
    required this.confidence,
    required this.values,
    required this.evidence,
    this.missing = const [],
    this.caveat,
  });

  final String key;
  final String label;
  final String assessment;
  final IntelligenceConfidence confidence;
  final Map<String, num> values;
  final List<AthleteStateEvidence> evidence;
  final List<String> missing;
  final String? caveat;

  Map<String, Object?> toJson() => {
    'key': key,
    'label': label,
    'assessment': assessment,
    'confidence': confidence.name,
    'values': values,
    'evidence': [for (final item in evidence) item.toJson()],
    'missing': missing,
    if (caveat != null) 'caveat': caveat,
  };

  factory AthleteStateDimension.fromJson(Map<String, Object?> json) =>
      AthleteStateDimension(
        key: json['key'] as String,
        label: json['label'] as String,
        assessment: json['assessment'] as String,
        confidence: IntelligenceConfidence.values.byName(
          json['confidence'] as String,
        ),
        values: {
          for (final entry in _map(json['values']).entries)
            entry.key: entry.value as num,
        },
        evidence: [
          for (final item in json['evidence'] as List<Object?>)
            AthleteStateEvidence.fromJson(_map(item)),
        ],
        missing: [
          for (final item in json['missing'] as List<Object?>) item as String,
        ],
        caveat: json['caveat'] as String?,
      );
}

class SportAthleteState {
  const SportAthleteState({
    required this.sport,
    required this.activityCount365Days,
    required this.durationSeconds90Days,
    required this.durationSeconds365Days,
    required this.confidence,
    required this.anchors,
    required this.missing,
  });

  final String sport;
  final int activityCount365Days;
  final int durationSeconds90Days;
  final int durationSeconds365Days;
  final IntelligenceConfidence confidence;
  final List<AthleteStateEvidence> anchors;
  final List<String> missing;

  AthleteStateEvidence? anchor(String metric) =>
      anchors.where((item) => item.metric == metric).firstOrNull;

  Map<String, Object?> toJson() => {
    'sport': sport,
    'activityCount365Days': activityCount365Days,
    'durationSeconds90Days': durationSeconds90Days,
    'durationSeconds365Days': durationSeconds365Days,
    'confidence': confidence.name,
    'anchors': [for (final item in anchors) item.toJson()],
    'missing': missing,
  };

  factory SportAthleteState.fromJson(Map<String, Object?> json) =>
      SportAthleteState(
        sport: json['sport'] as String,
        activityCount365Days: json['activityCount365Days'] as int,
        durationSeconds90Days: json['durationSeconds90Days'] as int,
        durationSeconds365Days: json['durationSeconds365Days'] as int,
        confidence: IntelligenceConfidence.values.byName(
          json['confidence'] as String,
        ),
        anchors: [
          for (final item in json['anchors'] as List<Object?>)
            AthleteStateEvidence.fromJson(_map(item)),
        ],
        missing: [
          for (final item in json['missing'] as List<Object?>) item as String,
        ],
      );
}

class AthleteStateDataQuality {
  const AthleteStateDataQuality({
    required this.historyDays,
    required this.activityCount,
    required this.activitiesWithHeartRate,
    required this.activitiesWithExternalLoad,
    required this.diagnosticTestCount,
    required this.providerActivityCounts,
    required this.missing,
    required this.confidence,
  });

  final int historyDays;
  final int activityCount;
  final int activitiesWithHeartRate;
  final int activitiesWithExternalLoad;
  final int diagnosticTestCount;
  final Map<String, int> providerActivityCounts;
  final List<String> missing;
  final IntelligenceConfidence confidence;

  Map<String, Object?> toJson() => {
    'historyDays': historyDays,
    'activityCount': activityCount,
    'activitiesWithHeartRate': activitiesWithHeartRate,
    'activitiesWithExternalLoad': activitiesWithExternalLoad,
    'diagnosticTestCount': diagnosticTestCount,
    'providerActivityCounts': providerActivityCounts,
    'missing': missing,
    'confidence': confidence.name,
  };

  factory AthleteStateDataQuality.fromJson(Map<String, Object?> json) =>
      AthleteStateDataQuality(
        historyDays: json['historyDays'] as int,
        activityCount: json['activityCount'] as int,
        activitiesWithHeartRate: json['activitiesWithHeartRate'] as int,
        activitiesWithExternalLoad: json['activitiesWithExternalLoad'] as int,
        diagnosticTestCount: json['diagnosticTestCount'] as int,
        providerActivityCounts: {
          for (final entry in _map(json['providerActivityCounts']).entries)
            entry.key: (entry.value as num).round(),
        },
        missing: [
          for (final item in json['missing'] as List<Object?>) item as String,
        ],
        confidence: IntelligenceConfidence.values.byName(
          json['confidence'] as String,
        ),
      );
}

class AthleteState {
  const AthleteState({
    required this.athleteId,
    required this.asOfUtcUs,
    required this.featureEngineVersion,
    required this.inputFingerprint,
    required this.windows,
    required this.dimensions,
    required this.sports,
    required this.dataQuality,
  });

  final String athleteId;
  final int asOfUtcUs;
  final String featureEngineVersion;
  final String inputFingerprint;
  final List<AthleteTrainingWindow> windows;
  final List<AthleteStateDimension> dimensions;
  final List<SportAthleteState> sports;
  final AthleteStateDataQuality dataQuality;

  AthleteTrainingWindow? window(int days) =>
      windows.where((item) => item.days == days).firstOrNull;

  AthleteStateDimension? dimension(String key) =>
      dimensions.where((item) => item.key == key).firstOrNull;

  Map<String, Object?> toJson() => {
    'athleteId': athleteId,
    'asOfUtcUs': asOfUtcUs,
    'featureEngineVersion': featureEngineVersion,
    'inputFingerprint': inputFingerprint,
    'windows': [for (final item in windows) item.toJson()],
    'dimensions': [for (final item in dimensions) item.toJson()],
    'sports': [for (final item in sports) item.toJson()],
    'dataQuality': dataQuality.toJson(),
  };

  factory AthleteState.fromJson(Map<String, Object?> json) => AthleteState(
    athleteId: json['athleteId'] as String,
    asOfUtcUs: json['asOfUtcUs'] as int,
    featureEngineVersion: json['featureEngineVersion'] as String,
    inputFingerprint: json['inputFingerprint'] as String,
    windows: [
      for (final item in json['windows'] as List<Object?>)
        AthleteTrainingWindow.fromJson(_map(item)),
    ],
    dimensions: [
      for (final item in json['dimensions'] as List<Object?>)
        AthleteStateDimension.fromJson(_map(item)),
    ],
    sports: [
      for (final item in json['sports'] as List<Object?>)
        SportAthleteState.fromJson(_map(item)),
    ],
    dataQuality: AthleteStateDataQuality.fromJson(_map(json['dataQuality'])),
  );
}

abstract interface class AthleteStateDataSource {
  AthleteState? getAthleteState(String athleteId, {required int nowUtcUs});
}

Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value! as Map);
