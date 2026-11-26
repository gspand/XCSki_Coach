/// Ein Weg, gespeicherte Laktatwerte zu holen — als Loch, nicht als Gerät.
///
/// Dasselbe Muster wie beim [MeasuredTestAccess](measured_test.dart): LaLa
/// nennt weder Lactate Scout noch Funk. Es fragt nur, ob es einen Weg gibt,
/// gespeicherte Werte zu holen, und wie er heisst.
///
/// ```text
///   BLE-Transport  ─▶  Scout-Adapter  ─▶  ExternalMeasurement  ─▶  LaLa
///   (ausserhalb)       (ausserhalb)       (neutral)                (hier)
/// ```
///
/// Stünde hier ein `ScoutTransport`, zöge das Produkt LaLa den Funk mit — für
/// ein Gerät, das der Arbeitsbereich mitbringt und nicht das Produkt. Wer den
/// Transport hat, füllt das Loch; wer nicht, dem fehlt der Knopf, und der
/// Test wird von Hand eingetragen wie eh und je.
library;

import 'dart:async';

import '../../external_data/normalization/external_data.dart';

enum LactateImportProgress {
  searching('Scout wird gesucht …'),
  connecting('Verbindung wird hergestellt …'),
  reading('Speicher wird vollständig gelesen …'),
  preparing('Messwerte werden geprüft …');

  const LactateImportProgress(this.label);
  final String label;
}

typedef LactateImportProgressCallback =
    void Function(LactateImportProgress progress);

/// Ob und wie dieses Produkt gespeicherte Werte holen kann.
class LactateImportAccess {
  const LactateImportAccess({required this.sourceLabel, required this.fetch});

  /// Wie das Gerät heisst — steht auf dem Knopf und später am Test.
  final String sourceLabel;

  /// Holt, was im Speicher steht.
  ///
  /// Eine leere Liste ist ein gültiges Ergebnis und kein Fehler: Ein Gerät,
  /// aus dem nichts kommt, ist ein leeres Gerät. Was schiefgeht, wirft.
  final Future<LactateImportBatch> Function({
    LactateImportProgressCallback? onProgress,
  })
  fetch;
}

/// Ein Speicherabruf samt den Dingen, die ein Mensch darüber wissen muss.
class LactateImportBatch {
  const LactateImportBatch({
    required this.measurements,
    this.warnings = const [],
    this.rawExport,
    this.deviceName,
    this.rejectedMeasurements = 0,
    this.transferComplete = false,
  });

  final List<ExternalMeasurement> measurements;

  /// Unsicherheiten des Transports, keine erfundenen Eigenschaften der Werte.
  /// Ein fehlender Nullrecord etwa bedeutet «möglicherweise unvollständig».
  final List<String> warnings;

  /// Unveränderte Funkpakete für eine spätere Protokollanalyse.
  final String? rawExport;

  final String? deviceName;
  final int rejectedMeasurements;
  final bool transferComplete;
}
