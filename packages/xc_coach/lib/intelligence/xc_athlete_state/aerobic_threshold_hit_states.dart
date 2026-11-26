/// Aerobe Basis, Schwellenzustand und High-Intensity State im XCAthleteState.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Trennt aerobe Grundlagenausdauer, Schwellenkapazität und VO2max strikt.
/// - Keine Schwellenschätzung aus Training ohne ausreichende Belege.
/// - Keine Durchschnitts-HF als VO2max-Messung.
library;

import 'evidence_model.dart';

/// Evidenz zur aeroben Leistungsfähigkeit (Grundlagenausdauer / Fettstoffwechsel / Kapillarisierung).
class AerobicState {
  const AerobicState({
    this.diagnosticLt1Evidence,
    this.lowIntensityDurationSeconds7d = 0,
    this.lowIntensityDurationSeconds28d = 0,
    this.lowIntensityDurationSeconds90d = 0,
    this.aerobicSessionCount28d = 0,
    this.hrResponseTrend,
    this.freshness = FreshnessLevel.maturing,
    this.confidence = 0.8,
  });

  /// Diagnostische Evidenz zur aeroben Schwelle (LT1 / LTP1).
  final Evidence<double>? diagnosticLt1Evidence;

  /// Trainingsumfang bei niedriger Intensität (Zone 1/2) in Sekunden.
  final int lowIntensityDurationSeconds7d;
  final int lowIntensityDurationSeconds28d;
  final int lowIntensityDurationSeconds90d;

  /// Anzahl reiner Grundlageneinheiten in den letzten 28 Tagen.
  final int aerobicSessionCount28d;

  /// Trend der kardiovaskulären Effizienz (z. B. 'Effizienz stabil bei 140 bpm').
  final String? hrResponseTrend;

  final FreshnessLevel freshness;
  final double confidence;

  double get lowIntensityHours28d =>
      lowIntensityDurationSeconds28d / 3600.0;

  Map<String, dynamic> toJson() => {
    if (diagnosticLt1Evidence != null)
      'diagnosticLt1Evidence': diagnosticLt1Evidence!.toJson(),
    'lowIntensityDurationSeconds7d': lowIntensityDurationSeconds7d,
    'lowIntensityDurationSeconds28d': lowIntensityDurationSeconds28d,
    'lowIntensityDurationSeconds90d': lowIntensityDurationSeconds90d,
    'aerobicSessionCount28d': aerobicSessionCount28d,
    if (hrResponseTrend != null) 'hrResponseTrend': hrResponseTrend,
    'freshness': freshness.key,
    'confidence': confidence,
  };

  factory AerobicState.fromJson(Map<String, dynamic> json) => AerobicState(
    diagnosticLt1Evidence: json['diagnosticLt1Evidence'] != null
        ? Evidence<double>.fromJson(
            json['diagnosticLt1Evidence'] as Map<String, dynamic>,
            (raw) => (raw as num).toDouble(),
          )
        : null,
    lowIntensityDurationSeconds7d:
        (json['lowIntensityDurationSeconds7d'] as num?)?.toInt() ?? 0,
    lowIntensityDurationSeconds28d:
        (json['lowIntensityDurationSeconds28d'] as num?)?.toInt() ?? 0,
    lowIntensityDurationSeconds90d:
        (json['lowIntensityDurationSeconds90d'] as num?)?.toInt() ?? 0,
    aerobicSessionCount28d:
        (json['aerobicSessionCount28d'] as num?)?.toInt() ?? 0,
    hrResponseTrend: json['hrResponseTrend']?.toString(),
    freshness: FreshnessLevel.values.firstWhere(
      (f) => f.key == json['freshness'],
      orElse: () => FreshnessLevel.maturing,
    ),
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0.8,
  );
}

/// Evidenz zur Schwellenleistungsfähigkeit (LTP2 / Laktat-Gleichgewicht / LT2).
class ThresholdState {
  const ThresholdState({
    this.diagnosticLt2Evidence,
    this.recentThresholdSessionIds = const [],
    this.thresholdSessionCount28d = 0,
    this.observedThresholdPowerWatt,
    this.observedThresholdHrBpm,
    this.freshness = FreshnessLevel.maturing,
    this.confidence = 0.8,
  });

  /// Diagnostische Evidenz zur anaeroben Schwelle (LT2 / LTP2).
  final Evidence<double>? diagnosticLt2Evidence;

  /// Jüngste Sessions mit nachgewiesenem Schwellenreiz.
  final List<String> recentThresholdSessionIds;

  final int thresholdSessionCount28d;
  final double? observedThresholdPowerWatt;
  final double? observedThresholdHrBpm;

  final FreshnessLevel freshness;
  final double confidence;

  bool get hasThresholdData =>
      diagnosticLt2Evidence != null || thresholdSessionCount28d > 0;

  Map<String, dynamic> toJson() => {
    if (diagnosticLt2Evidence != null)
      'diagnosticLt2Evidence': diagnosticLt2Evidence!.toJson(),
    'recentThresholdSessionIds': recentThresholdSessionIds,
    'thresholdSessionCount28d': thresholdSessionCount28d,
    if (observedThresholdPowerWatt != null)
      'observedThresholdPowerWatt': observedThresholdPowerWatt,
    if (observedThresholdHrBpm != null)
      'observedThresholdHrBpm': observedThresholdHrBpm,
    'freshness': freshness.key,
    'confidence': confidence,
  };

  factory ThresholdState.fromJson(Map<String, dynamic> json) =>
      ThresholdState(
        diagnosticLt2Evidence: json['diagnosticLt2Evidence'] != null
            ? Evidence<double>.fromJson(
                json['diagnosticLt2Evidence'] as Map<String, dynamic>,
                (raw) => (raw as num).toDouble(),
              )
            : null,
        recentThresholdSessionIds:
            (json['recentThresholdSessionIds'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                const [],
        thresholdSessionCount28d:
            (json['thresholdSessionCount28d'] as num?)?.toInt() ?? 0,
        observedThresholdPowerWatt:
            (json['observedThresholdPowerWatt'] as num?)?.toDouble(),
        observedThresholdHrBpm:
            (json['observedThresholdHrBpm'] as num?)?.toDouble(),
        freshness: FreshnessLevel.values.firstWhere(
          (f) => f.key == json['freshness'],
          orElse: () => FreshnessLevel.maturing,
        ),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.8,
      );
}

/// Evidenz zur hochintensiven Leistungsfähigkeit (VO2max / HIT).
class HighIntensityState {
  const HighIntensityState({
    this.diagnosticVo2maxEvidence,
    this.recentHitSessionIds = const [],
    this.hitSessionCount28d = 0,
    this.intervalStructure,
    this.accumulatedZ5DurationSeconds28d = 0,
    this.powerResponseWatt,
    this.repeatabilityScore,
    this.rpeMean,
    this.freshness = FreshnessLevel.maturing,
    this.confidence = 0.8,
  });

  /// Spirometrisch gemessene VO2max (NUR falls echter Labortest!).
  final Evidence<double>? diagnosticVo2maxEvidence;

  final List<String> recentHitSessionIds;
  final int hitSessionCount28d;
  final String? intervalStructure;

  /// Akkumulierte Zeit in Zone 5 (> 90% HRmax) der letzten 28 Tage in Sekunden.
  final int accumulatedZ5DurationSeconds28d;

  final double? powerResponseWatt;
  final double? repeatabilityScore;
  final double? rpeMean;

  final FreshnessLevel freshness;
  final double confidence;

  double get accumulatedZ5Minutes28d =>
      accumulatedZ5DurationSeconds28d / 60.0;

  Map<String, dynamic> toJson() => {
    if (diagnosticVo2maxEvidence != null)
      'diagnosticVo2maxEvidence': diagnosticVo2maxEvidence!.toJson(),
    'recentHitSessionIds': recentHitSessionIds,
    'hitSessionCount28d': hitSessionCount28d,
    if (intervalStructure != null) 'intervalStructure': intervalStructure,
    'accumulatedZ5DurationSeconds28d': accumulatedZ5DurationSeconds28d,
    if (powerResponseWatt != null) 'powerResponseWatt': powerResponseWatt,
    if (repeatabilityScore != null) 'repeatabilityScore': repeatabilityScore,
    if (rpeMean != null) 'rpeMean': rpeMean,
    'freshness': freshness.key,
    'confidence': confidence,
  };

  factory HighIntensityState.fromJson(Map<String, dynamic> json) =>
      HighIntensityState(
        diagnosticVo2maxEvidence: json['diagnosticVo2maxEvidence'] != null
            ? Evidence<double>.fromJson(
                json['diagnosticVo2maxEvidence'] as Map<String, dynamic>,
                (raw) => (raw as num).toDouble(),
              )
            : null,
        recentHitSessionIds: (json['recentHitSessionIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        hitSessionCount28d:
            (json['hitSessionCount28d'] as num?)?.toInt() ?? 0,
        intervalStructure: json['intervalStructure']?.toString(),
        accumulatedZ5DurationSeconds28d:
            (json['accumulatedZ5DurationSeconds28d'] as num?)?.toInt() ?? 0,
        powerResponseWatt:
            (json['powerResponseWatt'] as num?)?.toDouble(),
        repeatabilityScore:
            (json['repeatabilityScore'] as num?)?.toDouble(),
        rpeMean: (json['rpeMean'] as num?)?.toDouble(),
        freshness: FreshnessLevel.values.firstWhere(
          (f) => f.key == json['freshness'],
          orElse: () => FreshnessLevel.maturing,
        ),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.8,
      );
}
