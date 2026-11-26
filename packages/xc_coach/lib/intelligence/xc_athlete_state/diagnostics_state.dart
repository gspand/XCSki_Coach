/// Sportartspezifische physiologische Leistungsdiagnostik im XCAthleteState.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Laufen, Radfahren, Skating und Ercolina/Doppelstock bleiben strikt getrennt.
/// - Historische Lauf-/Radtests dürfen als historische Evidence existieren,
///   aber NIEMALS aktuelle Skating- oder Skilanglauf-Schwellen vortäuschen!
/// - Wenn für Skating keine Diagnostik vorliegt, ist der Wert explizit UNKNOWN.
library;

import '../../domain/xc_modality.dart';
import 'evidence_model.dart';

/// Einzelne sportartspezifische diagnostische Referenz.
class DiagnosticReference {
  const DiagnosticReference({
    required this.modality,
    required this.date,
    required this.protocol,
    this.lt1Ltp1Bpm,
    this.lt1Ltp1Watt,
    this.lt1Ltp1PaceSecPerKm,
    this.lt2Ltp2Bpm,
    this.lt2Ltp2Watt,
    this.lt2Ltp2PaceSecPerKm,
    this.vo2maxMlPerKgMin,
    this.maxHeartRateBpm,
    required this.source,
    this.sourceId,
    required this.freshness,
    this.confidence = 0.95,
    this.notes,
  });

  final XcModality modality;
  final DateTime date;

  /// Testprotokoll (z. B. 'Stufentest 3min-Stufen', 'Rampentest', '4x4 min Ercolina CP-Test').
  final String protocol;

  /// Aerobe Schwelle / LTP1 (Herzfrequenz).
  final double? lt1Ltp1Bpm;

  /// Aerobe Schwelle / LTP1 (Leistung).
  final double? lt1Ltp1Watt;

  /// Aerobe Schwelle / LTP1 (Pace in s/km, nur für Laufen).
  final double? lt1Ltp1PaceSecPerKm;

  /// Anaerobe Schwelle / LTP2 / LTHR (Herzfrequenz).
  final double? lt2Ltp2Bpm;

  /// Anaerobe Schwelle / LTP2 / Critical Power (Leistung).
  final double? lt2Ltp2Watt;

  /// Anaerobe Schwelle / LTP2 (Pace in s/km, nur für Laufen).
  final double? lt2Ltp2PaceSecPerKm;

  /// Maximaler Sauerstoffaufnahme in ml/kg/min (NUR wenn spirometrisch gemessen!).
  final double? vo2maxMlPerKgMin;

  /// Ausbelastungs-Herzfrequenz während des Tests.
  final double? maxHeartRateBpm;

  final String source;
  final String? sourceId;
  final FreshnessLevel freshness;
  final double confidence;
  final String? notes;

  bool get isFreshOrMaturing =>
      freshness == FreshnessLevel.fresh || freshness == FreshnessLevel.maturing;

  Map<String, dynamic> toJson() => {
    'modality': modality.key,
    'date': date.toIso8601String().split('T').first,
    'protocol': protocol,
    if (lt1Ltp1Bpm != null) 'lt1Ltp1Bpm': lt1Ltp1Bpm,
    if (lt1Ltp1Watt != null) 'lt1Ltp1Watt': lt1Ltp1Watt,
    if (lt1Ltp1PaceSecPerKm != null)
      'lt1Ltp1PaceSecPerKm': lt1Ltp1PaceSecPerKm,
    if (lt2Ltp2Bpm != null) 'lt2Ltp2Bpm': lt2Ltp2Bpm,
    if (lt2Ltp2Watt != null) 'lt2Ltp2Watt': lt2Ltp2Watt,
    if (lt2Ltp2PaceSecPerKm != null)
      'lt2Ltp2PaceSecPerKm': lt2Ltp2PaceSecPerKm,
    if (vo2maxMlPerKgMin != null) 'vo2maxMlPerKgMin': vo2maxMlPerKgMin,
    if (maxHeartRateBpm != null) 'maxHeartRateBpm': maxHeartRateBpm,
    'source': source,
    if (sourceId != null) 'sourceId': sourceId,
    'freshness': freshness.key,
    'confidence': confidence,
    if (notes != null) 'notes': notes,
  };

  factory DiagnosticReference.fromJson(Map<String, dynamic> json) =>
      DiagnosticReference(
        modality: XcModality.values.firstWhere(
          (m) => m.key == json['modality'],
          orElse: () => XcModality.unknown,
        ),
        date: DateTime.parse((json['date'] ?? '2026-01-01').toString()),
        protocol: (json['protocol'] ?? 'unspecified').toString(),
        lt1Ltp1Bpm: (json['lt1Ltp1Bpm'] as num?)?.toDouble(),
        lt1Ltp1Watt: (json['lt1Ltp1Watt'] as num?)?.toDouble(),
        lt1Ltp1PaceSecPerKm:
            (json['lt1Ltp1PaceSecPerKm'] as num?)?.toDouble(),
        lt2Ltp2Bpm: (json['lt2Ltp2Bpm'] as num?)?.toDouble(),
        lt2Ltp2Watt: (json['lt2Ltp2Watt'] as num?)?.toDouble(),
        lt2Ltp2PaceSecPerKm:
            (json['lt2Ltp2PaceSecPerKm'] as num?)?.toDouble(),
        vo2maxMlPerKgMin: (json['vo2maxMlPerKgMin'] as num?)?.toDouble(),
        maxHeartRateBpm: (json['maxHeartRateBpm'] as num?)?.toDouble(),
        source: (json['source'] ?? 'unknown').toString(),
        sourceId: json['sourceId']?.toString(),
        freshness: FreshnessLevel.values.firstWhere(
          (f) => f.key == json['freshness'],
          orElse: () => FreshnessLevel.maturing,
        ),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.95,
        notes: json['notes']?.toString(),
      );
}

/// Diagnostischer Gesamtzustand des Athleten nach Sportarten getrennt.
class DiagnosticsState {
  const DiagnosticsState({
    this.references = const {},
  });

  /// Referenzen je Sportart (Schlüssel: XcModality).
  final Map<XcModality, DiagnosticReference> references;

  bool hasReferenceFor(XcModality modality) =>
      references.containsKey(modality);

  DiagnosticReference? getReference(XcModality modality) =>
      references[modality];

  DiagnosticReference? get skating => references[XcModality.skiSkating];
  DiagnosticReference? get classic => references[XcModality.skiClassic];
  DiagnosticReference? get ercolina =>
      references[XcModality.ercolinaDoublePoling];
  DiagnosticReference? get rollerSki =>
      references[XcModality.rollerSkiDoublePoling] ??
      references[XcModality.rollerSkiSkating];
  DiagnosticReference? get running => references[XcModality.running];
  DiagnosticReference? get cycling => references[XcModality.cycling];

  bool get hasCurrentSkatingDiagnostics =>
      skating != null && skating!.isFreshOrMaturing;

  bool get hasCurrentErcolinaDiagnostics =>
      ercolina != null && ercolina!.isFreshOrMaturing;

  Map<String, dynamic> toJson() => {
    'references': references.map(
      (modality, ref) => MapEntry(modality.key, ref.toJson()),
    ),
  };

  factory DiagnosticsState.fromJson(Map<String, dynamic> json) {
    final rawRefs = json['references'] as Map<String, dynamic>? ?? {};
    final parsed = <XcModality, DiagnosticReference>{};
    for (final entry in rawRefs.entries) {
      final modality = XcModality.values.firstWhere(
        (m) => m.key == entry.key,
        orElse: () => XcModality.unknown,
      );
      if (entry.value is Map<String, dynamic>) {
        parsed[modality] = DiagnosticReference.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }
    return DiagnosticsState(references: parsed);
  }
}
