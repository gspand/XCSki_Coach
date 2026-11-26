/// Einheitliches Evidenz- und Frischemodell für den GIULIA XC Coach.
///
/// Grundprinzip:
/// State -> Evidence -> Session/Diagnostic -> Source
/// Jede sportwissenschaftliche Aussage im XCAthleteState muss über dieses Modell
/// lückenlos rückwärts nachvollziehbar sein.
library;

import '../../domain/xc_modality.dart';

/// Zeitliche Gültigkeit und Frische einer sportwissenschaftlichen Information.
enum FreshnessLevel {
  /// Frisch und unmittelbar handlungsleitend (z. B. Diagnostik <= 6 Wochen alt).
  fresh('fresh', 'Frisch / Aktuell'),

  /// Noch aussagekräftig, aber Übergangsphase (z. B. Diagnostik 6-12 Wochen alt).
  maturing('maturing', 'Reif / Gültig'),

  /// Veraltet, sollte baldmöglichst durch Re-Test/aktuelle Daten erneuert werden.
  stale('stale', 'Veraltet / Auffrischung nötig'),

  /// Rein historischer Referenzwert (z. B. Diagnostik vor > 1 Jahr).
  /// Darf nicht als aktuelle physiologische Realität verwendet werden!
  historical('historical', 'Historisch / Reine Referenz');

  const FreshnessLevel(this.key, this.label);
  final String key;
  final String label;
}

/// Strukturierte Einzel-Evidenz für jede Zustandsaussage im XCAthleteState.
class Evidence<T> {
  const Evidence({
    required this.id,
    required this.value,
    required this.measuredAtUtcUs,
    required this.source,
    this.sourceId,
    this.modality = XcModality.unknown,
    required this.method,
    required this.confidence,
    required this.freshness,
    required this.provenance,
    this.conditions,
    this.unit,
  });

  /// Eindeutige Kennung dieser Evidenz.
  final String id;

  /// Der gemessene oder abgeleitete Wert.
  final T value;

  /// Zeitstempel der Erfassung in Mikrosekunden (UTC).
  final int measuredAtUtcUs;

  /// Datenquelle (z. B. 'ercolina', 'strava', 'garmin', 'diagnostic_lab', 'manual').
  final String source;

  /// Eindeutige ID der Ursprungs-Session oder des Labortests.
  final String? sourceId;

  /// Sportart / Bewegungsform.
  final XcModality modality;

  /// Erfassungs- oder Berechnungsmethode (z. B. 'lactate_step_test_3min', 'pw_hr_drift', 'ercolina_sensor_v2').
  final String method;

  /// Daten- und Signalkonfidenz (0.0 bis 1.0).
  final double confidence;

  /// Zeitliche Frische bezogen auf den Abfragezeitpunkt.
  final FreshnessLevel freshness;

  /// Provenienz-Kette.
  final String provenance;

  /// Spezifische Test- oder Messbedingungen (z. B. 'Kaltes Neuschnee-Wachs, -5°C', 'Stufe 4 Ercolina').
  final String? conditions;

  /// Physikalische oder statistische Einheit (z. B. 'W', 'bpm', 'mmol/l', 'min').
  final String? unit;

  DateTime get measuredAt =>
      DateTime.fromMicrosecondsSinceEpoch(measuredAtUtcUs, isUtc: true);

  /// Vollständige Rückverfolgbarkeitskette als Text.
  String get traceChain =>
      'Wert: $value${unit != null ? " $unit" : ""} '
      '| Methode: $method '
      '| Session/Test: ${sourceId ?? "keine"} '
      '| Quelle: $source '
      '| Frische: ${freshness.label} '
      '| Konfidenz: ${(confidence * 100).toStringAsFixed(0)}%';

  Map<String, dynamic> toJson() => {
    'id': id,
    'value': value,
    'measuredAtUtcUs': measuredAtUtcUs,
    'source': source,
    if (sourceId != null) 'sourceId': sourceId,
    'modality': modality.key,
    'method': method,
    'confidence': confidence,
    'freshness': freshness.key,
    'provenance': provenance,
    if (conditions != null) 'conditions': conditions,
    if (unit != null) 'unit': unit,
  };

  factory Evidence.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic raw) valueParser,
  ) =>
      Evidence<T>(
        id: (json['id'] ?? '').toString(),
        value: valueParser(json['value']),
        measuredAtUtcUs: (json['measuredAtUtcUs'] as num?)?.toInt() ?? 0,
        source: (json['source'] ?? 'unknown').toString(),
        sourceId: json['sourceId']?.toString(),
        modality: XcModality.values.firstWhere(
          (m) => m.key == json['modality'],
          orElse: () => XcModality.unknown,
        ),
        method: (json['method'] ?? 'unspecified').toString(),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.8,
        freshness: FreshnessLevel.values.firstWhere(
          (f) => f.key == json['freshness'],
          orElse: () => FreshnessLevel.maturing,
        ),
        provenance: (json['provenance'] ?? 'unknown').toString(),
        conditions: json['conditions']?.toString(),
        unit: json['unit']?.toString(),
      );
}

/// Bewertet die Frische einer Messung relativ zum Berechnungsstichtag.
FreshnessLevel evaluateFreshness(
  DateTime measuredAt, {
  required DateTime asOf,
  Duration freshDuration = const Duration(days: 42), // 6 Wochen
  Duration maturingDuration = const Duration(days: 90), // ~3 Monate
  Duration staleDuration = const Duration(days: 365), // 1 Jahr
}) {
  final age = asOf.difference(measuredAt);
  if (age < Duration.zero) return FreshnessLevel.fresh;
  if (age <= freshDuration) return FreshnessLevel.fresh;
  if (age <= maturingDuration) return FreshnessLevel.maturing;
  if (age <= staleDuration) return FreshnessLevel.stale;
  return FreshnessLevel.historical;
}
