/// Sportart und Testtyp einer Leistungsdiagnostik — als Daten.
///
/// TEST kennt vier Einstiege (Running, Cycling, XC Ski, Ercolina), aber nur
/// **ein** Diagnostiksystem. Sportart und Testtyp sind Parameter desselben
/// gespeicherten Tests (`performance_test.sport`, `.modality`, `.protocol`,
/// `.measurement_source`), keine eigenen Implementierungen.
///
/// Die Einordnung liest nur, was gespeichert ist. Ältere Ercolina-Tests
/// tragen die Sportart `generic`; sie werden über ihr Protokoll bzw. die
/// Messquelle trotzdem eindeutig als Ercolina erkannt.
library;

import 'diagnostics.dart';

/// Die Sportarten, unter denen TEST Diagnostik anbietet.
enum DiagnosticSport {
  running(
    storageKey: 'running',
    title: 'Running',
    label: 'Laufen',
    loadUnits: [LoadUnits.kilometresPerHour],
  ),
  cycling(
    storageKey: 'cycling',
    title: 'Cycling',
    label: 'Radfahren',
    loadUnits: [LoadUnits.watt],
  ),

  /// Gespeichert als `langlauf`: Diesen Schlüssel ordnet die Auswertung
  /// bereits dem Skilanglauf zu.
  xcSki(
    storageKey: 'langlauf',
    title: 'XC Ski',
    label: 'Skilanglauf',
    loadUnits: [LoadUnits.kilometresPerHour, LoadUnits.watt],
  ),
  ercolina(
    storageKey: 'ercolina',
    title: 'Ercolina',
    label: 'Ercolina',
    loadUnits: [LoadUnits.watt],
  );

  const DiagnosticSport({
    required this.storageKey,
    required this.title,
    required this.label,
    required this.loadUnits,
  });

  /// Der Wert in `performance_test.sport` für neue Tests.
  final String storageKey;

  /// Der Name des Einstiegs in TEST.
  final String title;

  /// Die deutsche Bezeichnung im Fliesstext.
  final String label;

  /// Belastungseinheiten, in denen ein Protokoll dieser Sportart läuft.
  final List<String> loadUnits;

  /// Ordnet einen gespeicherten Test ein, oder null, wenn er zu keiner der
  /// vier Sportarten gehört. Es wird nichts geraten: Was nicht eindeutig
  /// passt, bleibt ohne Sportart.
  static DiagnosticSport? classify({
    required String? sport,
    String? protocol,
    MeasurementSource? measurementSource,
  }) {
    final key = (sport ?? '').trim().toLowerCase();
    final protocolId = (protocol ?? '').trim().toLowerCase();
    if (key == 'ercolina' ||
        protocolId.startsWith('ercolina_') ||
        protocolId.startsWith('custom_ercolina_') ||
        measurementSource == MeasurementSource.ercolina) {
      return DiagnosticSport.ercolina;
    }
    // Dieselbe Reihenfolge wie die Auswertung (`sportKeyOf`), damit TEST und
    // Zonenmodell eine Sportart nie verschieden lesen.
    if (_containsAny(key, const ['langlauf', 'ski', 'roller', 'nordic'])) {
      return DiagnosticSport.xcSki;
    }
    if (_containsAny(key, const ['rad', 'bike', 'cycl', 'ergometer'])) {
      return DiagnosticSport.cycling;
    }
    if (_containsAny(key, const ['ruder', 'row'])) return null;
    if (_containsAny(key, const ['lauf', 'run'])) {
      return DiagnosticSport.running;
    }
    return null;
  }

  static bool _containsAny(String value, List<String> needles) =>
      needles.any(value.contains);
}

/// Der Testtyp — gespeichert in `performance_test.modality`.
enum DiagnosticTestType {
  lactateStep(modality: 'step_test', label: 'Laktat-Stufentest');

  const DiagnosticTestType({required this.modality, required this.label});

  final String modality;
  final String label;

  static DiagnosticTestType? ofModality(String? modality) {
    for (final type in values) {
      if (type.modality == modality) return type;
    }
    return null;
  }
}

/// Der Sportartschlüssel, unter dem zwei Tests verglichen werden.
///
/// Ein alter Ercolina-Test (`generic`) und ein neuer (`ercolina`) sind
/// dieselbe Sportart; Laufen und Radfahren bleiben verschieden. Tests ohne
/// Einordnung behalten ihren gespeicherten Schlüssel.
String diagnosticComparisonSport({
  required String sport,
  String? protocol,
  MeasurementSource? measurementSource,
}) =>
    DiagnosticSport.classify(
      sport: sport,
      protocol: protocol,
      measurementSource: measurementSource,
    )?.storageKey ??
    sport;

/// Der Sportartschlüssel einer Trainingseinheit, passend zu
/// [diagnosticComparisonSport]: Schwellen gelten nur für dieselbe Sportart.
String sessionSportKey(String sport) =>
    DiagnosticSport.classify(sport: sport)?.storageKey ??
    sport.trim().toLowerCase();
