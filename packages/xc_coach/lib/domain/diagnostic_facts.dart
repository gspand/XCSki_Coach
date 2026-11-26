/// Maschinenlesbare Fakten eines gespeicherten Leistungstests — für COACH.
///
/// Kein zweites Physiologiemodell: Jeder Wert stammt aus dem gespeicherten
/// Test und dessen jüngster Auswertung. Was dort fehlt, bleibt null.
library;

import 'diagnostic_catalogue.dart';
import 'diagnostics.dart';

/// Eine Zone, wie die Auswertung sie gespeichert hat.
class DiagnosticZoneFact {
  const DiagnosticZoneFact({
    required this.ordinal,
    required this.name,
    required this.loadUnit,
    this.lowerLoad,
    this.upperLoad,
    this.lowerHeartRateBpm,
    this.upperHeartRateBpm,
  });

  final int ordinal;
  final String name;
  final String loadUnit;
  final double? lowerLoad;
  final double? upperLoad;
  final int? lowerHeartRateBpm;
  final int? upperHeartRateBpm;

  Map<String, Object?> toJson() => {
    'ordinal': ordinal,
    'name': name,
    'loadUnit': loadUnit,
    'lowerLoad': lowerLoad,
    'upperLoad': upperLoad,
    'lowerHeartRateBpm': lowerHeartRateBpm,
    'upperHeartRateBpm': upperHeartRateBpm,
  };
}

/// Ein Test, auf das eingedampft, was COACH lesen darf.
class DiagnosticTestFact {
  const DiagnosticTestFact({
    required this.testId,
    required this.athleteId,
    required this.storedSport,
    required this.sport,
    required this.modality,
    required this.testType,
    required this.protocolId,
    required this.measurementSource,
    required this.status,
    required this.performedAtUtcUs,
    required this.loadUnit,
    required this.zones,
    this.ltp1Load,
    this.ltp2Load,
    this.heartRateAtLtp1,
    this.heartRateAtLtp2,
    this.lactateAtLtp1,
    this.lactateAtLtp2,
  });

  final String testId;
  final String athleteId;

  /// Der gespeicherte Wert von `performance_test.sport`.
  final String storedSport;

  /// Die TEST-Sportart, oder null, wenn der Test zu keiner passt.
  final DiagnosticSport? sport;

  /// Der gespeicherte Testtyp (`performance_test.modality`).
  final String modality;
  final DiagnosticTestType? testType;
  final String protocolId;
  final MeasurementSource measurementSource;
  final PerformanceTestStatus status;
  final int performedAtUtcUs;

  /// Einheit von [ltp1Load]/[ltp2Load]: W (Leistung) oder km/h (Tempo).
  final String loadUnit;

  final double? ltp1Load;
  final double? ltp2Load;
  final int? heartRateAtLtp1;
  final int? heartRateAtLtp2;
  final double? lactateAtLtp1;
  final double? lactateAtLtp2;

  /// Zonen des ersten gespeicherten Zonenmodells der jüngsten Auswertung.
  final List<DiagnosticZoneFact> zones;

  bool get isEvaluated => ltp1Load != null || ltp2Load != null;

  /// Leistung oder Tempo an der Schwelle — je nach Einheit.
  double? get powerOrSpeedAtLtp1 => ltp1Load;
  double? get powerOrSpeedAtLtp2 => ltp2Load;

  Map<String, Object?> toJson() => {
    'testId': testId,
    'athleteId': athleteId,
    'sport': sport?.storageKey ?? storedSport,
    'testType': testType?.modality ?? modality,
    'protocol': protocolId,
    'measurementSource': measurementSource.name,
    'status': status.name,
    'performedAtUtcUs': performedAtUtcUs,
    'loadUnit': loadUnit,
    'ltp1': ltp1Load,
    'ltp2': ltp2Load,
    'heartRateAtLtp1': heartRateAtLtp1,
    'heartRateAtLtp2': heartRateAtLtp2,
    'powerOrSpeedAtLtp1': powerOrSpeedAtLtp1,
    'powerOrSpeedAtLtp2': powerOrSpeedAtLtp2,
    'zones': [for (final zone in zones) zone.toJson()],
  };
}
