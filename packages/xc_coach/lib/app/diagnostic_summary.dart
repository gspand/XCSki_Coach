/// Ein veröffentlichtes Diagnostikergebnis — ohne die Auswertung dahinter.
///
/// ## Warum es das gibt
///
/// LaLa **deutet**; die Plattform darf das Ergebnis **zeigen**. Zwischen
/// beidem liegt eine Grenze, die bisher fehlte: Das Athletenprofil griff für
/// eine Schwellenanzeige auf LaLas Normen, Kaderrang und Methodenregister zu
/// — und zog damit die ganze Diagnostik in jedes Produkt, das einen Verlauf
/// zeigt.
///
/// ```text
///   LaLa rechnet  →  Ergebnis  →  Plattform zeigt es
/// ```
///
/// Dieselbe Grenze braucht später das Teilen: Eine Trainerin fährt einen Test,
/// gibt das Ergebnis frei, und GIULIA Athlete zeigt es — ohne selbst
/// Diagnostik zu besitzen. **Nicht messen dürfen und nicht sehen dürfen sind
/// zwei verschiedene Rechte.**
library;

import '../domain/diagnostic_catalogue.dart';

/// Welche Schwelle.
enum SummaryThreshold {
  lt1('LTP1'),
  lt2('LTP2');

  const SummaryThreshold(this.label);
  final String label;
}

/// Eine Schwelle, wie sie angezeigt wird.
class ThresholdSummary {
  const ThresholdSummary({
    required this.type,
    required this.loadValue,
    required this.loadUnit,
    this.heartRateBpm,
    this.lactateMmolPerLitre,
  });

  final SummaryThreshold type;
  final double loadValue;
  final String loadUnit;
  final int? heartRateBpm;
  final double? lactateMmolPerLitre;

  String get loadLabel {
    final rounded = loadValue.round();
    final shown = (loadValue - rounded).abs() < .05
        ? '$rounded'
        : loadValue.toStringAsFixed(1).replaceAll('.', ',');
    return '$shown $loadUnit';
  }
}

/// Ein Test, auf das Anzeigbare eingedampft.
class DiagnosticSummary {
  const DiagnosticSummary({
    required this.testId,
    required this.startedAtUtcUs,
    required this.sport,
    required this.thresholds,
    this.diagnosticSport,
  });

  final String testId;
  final int startedAtUtcUs;
  final String sport;

  /// Die TEST-Sportart, auch für ältere Ercolina-Tests mit `generic`.
  final DiagnosticSport? diagnosticSport;

  /// Was dabei herauskam. Leer, solange nichts ausgewertet ist — und dann
  /// steht auch nichts da.
  final List<ThresholdSummary> thresholds;

  ThresholdSummary? of(SummaryThreshold type) {
    for (final threshold in thresholds) {
      if (threshold.type == type) return threshold;
    }
    return null;
  }

  bool get hasResult => thresholds.isNotEmpty;
}
