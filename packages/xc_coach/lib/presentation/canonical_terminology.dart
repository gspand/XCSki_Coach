/// Kanonische Vokabulare und Terminologie für die GIULIA Athlete Experience.
///
/// WICHTIGE ARCHITEKTUR-REGEL:
/// - Presentation entscheidet NICHT.
/// - Diese Datei ist die einzige Quelle für Beschriftungen, Einheiten,
///   und Konfidenzbegriffe in Athletensprache.
/// - Es werden keine neuen Schwellenwerte oder Regeln erfunden.
library;

abstract final class CanonicalTerminology {
  // --- Belastung & Erholung ---
  static const String acuteLoad = 'Kurzfristige Belastung';
  static const String acuteLoadSub = '7-Tage-Gewichtung (akute Ermüdungskomponente)';

  static const String chronicLoad = 'Langfristige Belastung';
  static const String chronicLoadSub = '42-Tage-Gewichtung (aufgebaute Grundfitness)';

  static const String loadBalance = 'Belastungsbalance';
  static const String loadBalanceSub = 'Verhältnis aus langfristiger und kurzfristiger Belastung';

  static const String subjectiveReadiness = 'Dein aktuelles Befinden';
  static const String dataCoverage = 'Datenlage';
  static const String recentStimuli = 'Letzte Trainingsreize';

  // --- Die 4 Hauptbereiche in ATHLET ---
  static const String sectionLoadAndRecovery = 'Belastung & Erholung';
  static const String sectionPerformance = 'Leistungsfähigkeit';
  static const String sectionXcSpecificity = 'Langlauf-Spezifität';
  static const String sectionDiagnosticsAndData = 'Diagnostik & Daten';

  // --- Konfidenz & Datenqualität ---
  static const String confidenceHigh = 'Sehr gute Datenlage';
  static const String confidenceModerate = 'Gute Datenlage';
  static const String confidenceLow = 'Begrenzte Datenlage';
  static const String confidenceUnknown = 'Noch zu wenig Daten';

  // --- Einheiten & Formate ---
  static const String unitTrimp = 'TRIMP';
  static const String unitPoints = 'Punkte';
  static const String unitWatt = 'W';
  static const String unitBpm = 'bpm';
  static const String unitMinutes = 'min';
  static const String unitHours = 'Std.';
  static const String unitKm = 'km';
  static const String unitMmol = 'mmol/l';
  static const String unitPercent = '%';
  static const String unitStrokesPerMin = 'Züge/min';

  // --- Unbekannte Werte (strikte Ehrlichkeit) ---
  static const String unknownValue = '—';
  static const String unknownState = 'Noch nicht erfasst';
  static const String unknownDiagnostic = 'Keine aktuelle Leistungsdiagnostik vorhanden';
}
