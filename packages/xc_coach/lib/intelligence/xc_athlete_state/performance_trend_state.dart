/// Leistungsentwicklungs-Trends und standardisierte Vergleiche (Performance Trend State).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Nur echte «Apples-to-Apples»-Vergleiche:
///   * gleiche Modalität
///   * ähnlicher Workout-Typ und Dauer
///   * vergleichbare Ercolina-Bremse / Bedingungen
/// - Keine simplen Heuristiken wie «Herzfrequenz niedriger = fitter» ohne Kontext
///   (Hitze, Vorbelastung, kardiale Ermüdung, Dehydration beeinflussen HF).
library;

import '../../domain/xc_modality.dart';

/// Vergleich zweier standardisierter oder hinreichend ähnlicher Einheiten.
class ComparableSessionComparison {
  const ComparableSessionComparison({
    required this.sessionAId,
    required this.sessionBId,
    required this.modality,
    required this.comparisonType,
    this.powerDeltaWatt,
    this.hrDeltaAtComparablePower,
    this.rpeDeltaAtComparableWork,
    required this.confidence,
    required this.evidenceSummary,
  });

  /// Ältere Referenz-Session.
  final String sessionAId;

  /// Neuere Vergleichs-Session.
  final String sessionBId;

  final XcModality modality;

  /// Art des Vergleichs (z. B. 'ercolina_4x4_hit_repeat', 'steady_state_aerobic').
  final String comparisonType;

  /// Leistungsdifferenz B minus A in Watt.
  final double? powerDeltaWatt;

  /// Herzfrequenzdifferenz bei vergleichbarer Leistung (B minus A).
  final double? hrDeltaAtComparablePower;

  /// RPE-Differenz bei vergleichbarer Gesamtarbeit.
  final double? rpeDeltaAtComparableWork;

  final double confidence;
  final String evidenceSummary;

  Map<String, dynamic> toJson() => {
    'sessionAId': sessionAId,
    'sessionBId': sessionBId,
    'modality': modality.key,
    'comparisonType': comparisonType,
    if (powerDeltaWatt != null) 'powerDeltaWatt': powerDeltaWatt,
    if (hrDeltaAtComparablePower != null)
      'hrDeltaAtComparablePower': hrDeltaAtComparablePower,
    if (rpeDeltaAtComparableWork != null)
      'rpeDeltaAtComparableWork': rpeDeltaAtComparableWork,
    'confidence': confidence,
    'evidenceSummary': evidenceSummary,
  };

  factory ComparableSessionComparison.fromJson(Map<String, dynamic> json) =>
      ComparableSessionComparison(
        sessionAId: (json['sessionAId'] ?? '').toString(),
        sessionBId: (json['sessionBId'] ?? '').toString(),
        modality: XcModality.values.firstWhere(
          (m) => m.key == json['modality'],
          orElse: () => XcModality.unknown,
        ),
        comparisonType: (json['comparisonType'] ?? 'unspecified').toString(),
        powerDeltaWatt: (json['powerDeltaWatt'] as num?)?.toDouble(),
        hrDeltaAtComparablePower:
            (json['hrDeltaAtComparablePower'] as num?)?.toDouble(),
        rpeDeltaAtComparableWork:
            (json['rpeDeltaAtComparableWork'] as num?)?.toDouble(),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.75,
        evidenceSummary: (json['evidenceSummary'] ?? '').toString(),
      );
}

/// Gesamtzustand der erkannten Leistungstrends.
class PerformanceTrendState {
  const PerformanceTrendState({
    this.comparisons = const [],
  });

  final List<ComparableSessionComparison> comparisons;

  List<ComparableSessionComparison> trendsFor(XcModality modality) =>
      comparisons.where((c) => c.modality == modality).toList(growable: false);

  Map<String, dynamic> toJson() => {
    'comparisons': comparisons.map((c) => c.toJson()).toList(),
  };

  factory PerformanceTrendState.fromJson(Map<String, dynamic> json) =>
      PerformanceTrendState(
        comparisons: (json['comparisons'] as List<dynamic>?)
                ?.map((e) => ComparableSessionComparison.fromJson(
                    e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}
