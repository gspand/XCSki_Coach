import 'package:xc_coach/lala/core/training_zones/zone_definitions.dart';

/// Ein Trainingsbereich mit exakten und gerundeten Anzeigegrenzen.
/// Die exakten Werte bleiben erhalten, damit spaetere Neuberechnungen und
/// die wissenschaftliche Nachvollziehbarkeit nicht an der Rundung scheitern.
class TrainingZone {
  const TrainingZone({
    required this.code,
    required this.displayName,
    required this.shortMeaning,
    required this.physiologicalDomain,
    required this.purpose,
    required this.preferredTrainingMethods,
    required this.preferredControlMetrics,
    required this.boundaryRationale,
    this.lowerLoadExact,
    this.upperLoadExact,
    this.lowerLoadDisplay,
    this.upperLoadDisplay,
    this.lowerHeartRateExact,
    this.upperHeartRateExact,
    this.lowerHeartRateDisplay,
    this.upperHeartRateDisplay,
    this.lowerPaceSeconds,
    this.upperPaceSeconds,
    this.typicalDuration,
    this.typicalIntervalLength,
    this.typicalLactate,
    this.typicalRpe,
    this.provisionalBoundary = false,
    this.manuallyAdjusted = false,
    this.adjustmentReason,
  });

  final String code;
  final String displayName;
  final String shortMeaning;
  final PhysiologicalDomain physiologicalDomain;
  final String purpose;
  final List<String> preferredTrainingMethods;

  /// Erste Metrik ist die primaere Steuergroesse dieser Zone.
  final List<ControlMetric> preferredControlMetrics;

  /// Klartextbegruendung der Obergrenze fuer die Ergebnisebene.
  final String boundaryRationale;

  final double? lowerLoadExact;
  final double? upperLoadExact;
  final double? lowerLoadDisplay;
  final double? upperLoadDisplay;

  final double? lowerHeartRateExact;
  final double? upperHeartRateExact;
  final int? lowerHeartRateDisplay;
  final int? upperHeartRateDisplay;

  /// Pace an der Untergrenze, also der langsamere Wert in Sekunden je Kilometer.
  final int? lowerPaceSeconds;
  final int? upperPaceSeconds;

  final String? typicalDuration;
  final String? typicalIntervalLength;
  final String? typicalLactate;
  final String? typicalRpe;

  /// Wahr, wenn die Obergrenze nur aus einer vereinfachten Schaetzung stammt.
  final bool provisionalBoundary;

  final bool manuallyAdjusted;
  final String? adjustmentReason;

  ControlMetric get primaryControlMetric => preferredControlMetrics.first;

  bool get isOpenEnded => upperLoadDisplay == null;

  bool contains(double load) {
    final lower = lowerLoadExact ?? 0;
    if (load < lower) {
      return false;
    }
    final upper = upperLoadExact;
    return upper == null || load <= upper;
  }

  TrainingZone copyWith({
    double? lowerLoadDisplay,
    double? upperLoadDisplay,
    int? lowerHeartRateDisplay,
    int? upperHeartRateDisplay,
    bool? manuallyAdjusted,
    String? adjustmentReason,
  }) => TrainingZone(
    code: code,
    displayName: displayName,
    shortMeaning: shortMeaning,
    physiologicalDomain: physiologicalDomain,
    purpose: purpose,
    preferredTrainingMethods: preferredTrainingMethods,
    preferredControlMetrics: preferredControlMetrics,
    boundaryRationale: boundaryRationale,
    lowerLoadExact: lowerLoadExact,
    upperLoadExact: upperLoadExact,
    lowerLoadDisplay: lowerLoadDisplay ?? this.lowerLoadDisplay,
    upperLoadDisplay: upperLoadDisplay ?? this.upperLoadDisplay,
    lowerHeartRateExact: lowerHeartRateExact,
    upperHeartRateExact: upperHeartRateExact,
    lowerHeartRateDisplay: lowerHeartRateDisplay ?? this.lowerHeartRateDisplay,
    upperHeartRateDisplay: upperHeartRateDisplay ?? this.upperHeartRateDisplay,
    lowerPaceSeconds: lowerPaceSeconds,
    upperPaceSeconds: upperPaceSeconds,
    typicalDuration: typicalDuration,
    typicalIntervalLength: typicalIntervalLength,
    typicalLactate: typicalLactate,
    typicalRpe: typicalRpe,
    provisionalBoundary: provisionalBoundary,
    manuallyAdjusted: manuallyAdjusted ?? this.manuallyAdjusted,
    adjustmentReason: adjustmentReason ?? this.adjustmentReason,
  );
}

enum ZoneIssueSeverity { info, warning, blocking }

class ZoneQualityIssue {
  const ZoneQualityIssue({
    required this.severity,
    required this.message,
    required this.consequence,
  });

  final ZoneIssueSeverity severity;
  final String message;
  final String consequence;
}

/// Ein einzelner Schwellenanker mit den zugehoerigen Begleitwerten.
class ThresholdAnchor {
  const ThresholdAnchor({required this.load, this.heartRate, this.lactate});

  final double load;
  final int? heartRate;
  final double? lactate;
}

/// Die gemeinsame physiologische Datengrundlage einer Diagnostik.
///
/// Aus genau diesem Satz werden alle Trainingszonenmodelle erzeugt. Ein
/// Modellwechsel veraendert diesen Satz nie.
class PhysiologicalAnchorSet {
  const PhysiologicalAnchorSet({
    required this.sportType,
    required this.loadUnit,
    required this.upperSource,
    this.lt1,
    this.upper,
    this.criticalPower,
    this.wPrime,
    this.maximalAerobicPower,
    this.maximalPower,
    this.maximalHeartRate,
    this.version = 1,
  });

  final String sportType;

  /// 'W' fuer Leistung, sonst Geschwindigkeit in km/h.
  final String loadUnit;

  final ThresholdSource upperSource;
  final ThresholdAnchor? lt1;
  final ThresholdAnchor? upper;

  final double? criticalPower;
  final double? wPrime;
  final double? maximalAerobicPower;
  final double? maximalPower;
  final int? maximalHeartRate;

  final int version;

  bool get isSpeedBased => loadUnit.toLowerCase() != 'w';
  bool get upperConfirmed => isConfirmedSource(upperSource);

  /// Wahr, wenn die fuer die oberen Zonen des 7-Zonen-Modells noetigen
  /// Maximalwerte vorliegen.
  bool get hasExtendedAnchors =>
      maximalAerobicPower != null && maximalPower != null;

  double? resolveLoadAnchor(ZoneAnchorRef ref) => switch (ref) {
    ZoneAnchorRef.zero => 0,
    ZoneAnchorRef.lt1 => lt1?.load,
    ZoneAnchorRef.upperThreshold => upper?.load,
    ZoneAnchorRef.criticalPower => criticalPower ?? upper?.load,
    ZoneAnchorRef.maximalAerobicPower => maximalAerobicPower ?? maximalPower,
    ZoneAnchorRef.maximalPower => maximalPower,
    _ => null,
  };

  double? resolveHeartRateAnchor(ZoneAnchorRef ref) => switch (ref) {
    ZoneAnchorRef.zero => 0,
    ZoneAnchorRef.lt1HeartRate => lt1?.heartRate?.toDouble(),
    ZoneAnchorRef.upperHeartRate => upper?.heartRate?.toDouble(),
    ZoneAnchorRef.maximalHeartRate => maximalHeartRate?.toDouble(),
    _ => null,
  };

  PhysiologicalAnchorSet copyWith({
    ThresholdSource? upperSource,
    ThresholdAnchor? lt1,
    ThresholdAnchor? upper,
    double? criticalPower,
    double? wPrime,
    double? maximalAerobicPower,
    double? maximalPower,
    int? maximalHeartRate,
    int? version,
  }) => PhysiologicalAnchorSet(
    sportType: sportType,
    loadUnit: loadUnit,
    upperSource: upperSource ?? this.upperSource,
    lt1: lt1 ?? this.lt1,
    upper: upper ?? this.upper,
    criticalPower: criticalPower ?? this.criticalPower,
    wPrime: wPrime ?? this.wPrime,
    maximalAerobicPower: maximalAerobicPower ?? this.maximalAerobicPower,
    maximalPower: maximalPower ?? this.maximalPower,
    maximalHeartRate: maximalHeartRate ?? this.maximalHeartRate,
    version: version ?? this.version,
  );
}

class GeneratedTrainingZoneSet {
  const GeneratedTrainingZoneSet({
    required this.modelId,
    required this.modelName,
    required this.modelVersion,
    required this.sportType,
    required this.loadUnit,
    required this.anchors,
    required this.zones,
    required this.issues,
    required this.generatedAt,
    required this.quality,
    this.modelNotice,
    this.manuallyAdjusted = false,
    this.revision = 1,
  });

  final String modelId;
  final String modelName;
  final String modelVersion;
  final String sportType;
  final String loadUnit;
  final PhysiologicalAnchorSet anchors;
  final List<TrainingZone> zones;
  final List<ZoneQualityIssue> issues;
  final DateTime generatedAt;
  final ZoneSetQuality quality;

  /// Modellspezifischer Hinweis, etwa beim klassischen Prozentmodell.
  final String? modelNotice;

  final bool manuallyAdjusted;
  final int revision;

  bool get provisional =>
      quality == ZoneSetQuality.provisional ||
      quality == ZoneSetQuality.plausible;

  bool get confirmed => quality == ZoneSetQuality.confirmed;

  bool get isUsable => zones.isNotEmpty;

  ThresholdSource get thresholdSource => anchors.upperSource;

  String get statusLabel => zoneQualityLabels[quality]!;

  TrainingZone? zone(String code) =>
      zones.where((zone) => zone.code == code).firstOrNull;

  /// Ordnet eine Belastung der passenden Zone dieses Modells zu.
  TrainingZone? zoneForLoad(double load) =>
      zones.where((zone) => zone.contains(load)).firstOrNull ??
      (zones.isEmpty ? null : zones.last);
}
