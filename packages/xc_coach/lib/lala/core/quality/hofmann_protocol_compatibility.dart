import 'dart:math' as math;

import 'package:xc_coach/lala/core/models/test_stage.dart';

enum HistoricalProtocolCompatibilityClass { a, b, c }

/// Protocol-quality gate for the published Hofmann/Graz LTP1 ROI.
///
/// It counts recorded stages only. It never adds, interpolates, or moves data.
class HofmannProtocolCompatibility {
  const HofmannProtocolCompatibility._({
    required this.stages,
    required this.roiFraction,
    required this.roiEnd,
    required this.roiPointCount,
    required this.compatibilityClass,
    required this.compatibilityScore,
    required this.medianStageIncrement,
    required this.relativeStageIncrement,
    required this.roiSamplingDensity,
    required this.reasons,
  });

  factory HofmannProtocolCompatibility.forRoi({
    required List<TestStage> stages,
    required double roiFraction,
  }) {
    final maximumLoad = stages.last.load;
    final roiEnd = roiFraction * maximumLoad;
    final roiPoints = stages.where((stage) => stage.load <= roiEnd).toList();
    final increments = <double>[
      for (var index = 1; index < stages.length; index++)
        stages[index].load - stages[index - 1].load,
    ]..sort();
    final medianIncrement = increments.isEmpty
        ? null
        : increments[increments.length ~/ 2];
    final relativeIncrement = medianIncrement == null
        ? null
        : medianIncrement / maximumLoad;
    final roiWidth = roiEnd - stages.first.load;
    final density = roiWidth <= 0
        ? null
        : roiPoints.length / (roiWidth / maximumLoad);
    final compatibilityClass = roiPoints.length >= 6
        ? HistoricalProtocolCompatibilityClass.a
        : roiPoints.length >= 4
        ? HistoricalProtocolCompatibilityClass.b
        : HistoricalProtocolCompatibilityClass.c;
    final idealIncrement = roiWidth <= 0 ? 0.0 : roiWidth / 5;
    final resolutionScore = medianIncrement == null || idealIncrement <= 0
        ? 0.0
        : math.min(1.0, idealIncrement / medianIncrement) * 20;
    final score =
        math.min(60.0, roiPoints.length / 6 * 60) +
        math.min(20.0, stages.length / 6 * 20) +
        resolutionScore;
    final reasons = <String>[
      if (stages.first.load > roiEnd)
        'Die erste reale Belastungsstufe (${stages.first.load.toStringAsFixed(3)}) liegt oberhalb der ${_percent(roiFraction)}-ROI-Grenze (${roiEnd.toStringAsFixed(3)}).',
      if (roiPoints.length < 4)
        'Nur ${roiPoints.length} reale Messpunkte liegen in der ${_percent(roiFraction)}-ROI; mindestens vier sind fuer zwei Regressionen mit je zwei Punkten erforderlich.',
      if (stages.length < 6)
        'Der Test umfasst nur ${stages.length} Belastungsstufen; sechs sind das robuste Mindestziel mit drei Punkten pro Regression.',
      if (medianIncrement != null &&
          idealIncrement > 0 &&
          medianIncrement > idealIncrement)
        'Die mediane Stufenhoehe (${medianIncrement.toStringAsFixed(3)}) ist groesser als die fuer sechs ROI-Punkte erforderliche Aufloesung (${idealIncrement.toStringAsFixed(3)}).',
    ];
    return HofmannProtocolCompatibility._(
      stages: stages,
      roiFraction: roiFraction,
      roiEnd: roiEnd,
      roiPointCount: roiPoints.length,
      compatibilityClass: compatibilityClass,
      compatibilityScore: score,
      medianStageIncrement: medianIncrement,
      relativeStageIncrement: relativeIncrement,
      roiSamplingDensity: density,
      reasons: reasons,
    );
  }

  static Map<String, HofmannProtocolCompatibility> allPublishedRois(
    List<TestStage> stages,
  ) => <String, HofmannProtocolCompatibility>{
    'ROI_65': HofmannProtocolCompatibility.forRoi(
      stages: stages,
      roiFraction: .65,
    ),
    'ROI_67_5': HofmannProtocolCompatibility.forRoi(
      stages: stages,
      roiFraction: .675,
    ),
    'ROI_70': HofmannProtocolCompatibility.forRoi(
      stages: stages,
      roiFraction: .70,
    ),
  };

  final List<TestStage> stages;
  final double roiFraction;
  final double roiEnd;
  final int roiPointCount;
  final HistoricalProtocolCompatibilityClass compatibilityClass;
  final double compatibilityScore;
  final double? medianStageIncrement;
  final double? relativeStageIncrement;
  final double? roiSamplingDensity;
  final List<String> reasons;

  bool get historicalMethodSupported =>
      compatibilityClass != HistoricalProtocolCompatibilityClass.c;

  String get label => switch (compatibilityClass) {
    HistoricalProtocolCompatibilityClass.a =>
      'Historisch vollstaendig kompatibel',
    HistoricalProtocolCompatibilityClass.b => 'Eingeschraenkt kompatibel',
    HistoricalProtocolCompatibilityClass.c => 'Historisch nicht kompatibel',
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'protocol_compatibility': label,
    'compatibility_class': compatibilityClass.name.toUpperCase(),
    'reconstruction_compatibility': switch (compatibilityClass) {
      HistoricalProtocolCompatibilityClass.a => 'HIGH_COMPATIBILITY',
      HistoricalProtocolCompatibilityClass.b => 'LIMITED_COMPATIBILITY',
      HistoricalProtocolCompatibilityClass.c => 'NOT_COMPATIBLE',
    },
    'compatibility_score': compatibilityScore,
    'roi_point_count': roiPointCount,
    'roi_variant': 'ROI_${_percent(roiFraction)}',
    'historical_method_supported': historicalMethodSupported,
    'historical_method_reason': reasons,
    'literature_rule':
        'Tschakert 2022: first load step to 65-70% Pmax; two-line breakpoint requires >=4 real points, >=6 is robust.',
    'total_stage_count': stages.length,
    'first_stage_intensity': stages.first.load,
    'pmax': stages.last.load,
    'roi_end': roiEnd,
    'points_left_possible': math.max(0, roiPointCount - 2),
    'points_right_possible': math.max(0, roiPointCount - 2),
    'median_stage_increment': medianStageIncrement,
    'relative_stage_increment': relativeStageIncrement,
    'roi_sampling_density': roiSamplingDensity,
    'score_formula':
        'min(60, roi_points/6*60) + min(20, total_stages/6*20) + min(20, ideal_increment/median_increment*20), where ideal_increment=(roi_end-first_stage)/5. Score is descriptive and never overrides class C.',
  };
}

String _percent(double value) =>
    (value * 100).toStringAsFixed(value == .675 ? 1 : 0);
