/// Typen und Taxonomien der GIULIA Training Need Engine (Schritt 4).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Training Need ist NICHT Training Load (hohe ChronicLoad schützt nicht vor spezifischem Trainingsbedarf).
/// - Ordinales Prioritätsmodell ohne dekorative Scheinpräzision (keine künstlichen 0.783 Scores).
/// - Trennung zwischen Trainingsbedarf (TrainingNeed) und Informationsbedarf (InformationNeed / AssessmentNeed).
library;

/// Die 16 kanonischen Bedarfsdomänen für Skilanglauf und Rollski/Ercolina.
enum TrainingNeedType {
  /// Grundlegende aerobe Ausdauerfähigkeit (Zone 1 / Zone 2).
  aerobicBase('Aerobe Grundlage', 'aerobic_base'),

  /// Langer spezifischer Dauerumfang (Einheiten >= 90 min).
  longEndurance('Langzeitausdauer', 'long_endurance'),

  /// Schwellenkapazität (LTP2 / anaerobe Schwelle / Critical Power).
  threshold('Schwellenkapazität (LT2)', 'threshold'),

  /// Maximale Sauerstoffaufnahme / kardiopulmonales Plafond.
  vo2max('VO2max Kapazität', 'vo2max'),

  /// Neuromuskuläre Schnelligkeit, Antritt und Sprint-Koordination.
  speedNeuromuscular('Schnelligkeit & Neuromuskulär', 'speed_neuromuscular'),

  /// Spezifische Bewegungs- und Muskelreize für Langlauf Skating.
  skatingSpecificity('Skating-Spezifität', 'skating_specificity'),

  /// Spezifische Bewegungs- und Muskelreize für Langlauf Klassisch.
  classicSpecificity('Klassisch-Spezifität', 'classic_specificity'),

  /// Maximale Vortriebskraft und Spitzenleistung im Doppelstockzug (Ercolina/Schnee).
  doublePolingPower('Doppelstock-Kraft & Power', 'double_poling_power'),

  /// Ermüdungswiderstand und Ausdauerleistung der Oberkörper-Zugmuskulatur.
  doublePolingEndurance('Doppelstock-Ausdauer', 'double_poling_endurance'),

  /// Maximalkraft der relevanten Muskelketten (Rumpf, Latissimus, Beinextensoren).
  maxStrength('Maximalkraft', 'max_strength'),

  /// Explosivkraft und Schnellkraftentwicklung.
  explosiveStrength('Explosivkraft', 'explosive_strength'),

  /// Lokale muskuläre Ausdauer (Kraftausdauer).
  muscularEndurance('Muskuläre Ausdauer', 'muscular_endurance'),

  /// Technische Ökonomie, Gleitbalance und geländeabhängige Technikwechsel.
  technique('Technik & Bewegungsökonomie', 'technique'),

  /// Physiologische und mechanische Belastungsstabilität über lange Zeitdauer (Durability).
  durability('Durability & Ermüdungsresistenz', 'durability'),

  /// Wettkampfspezifische Belastungsmuster (Geländewechsel, Renntempo-Segmente).
  raceSpecificity('Wettkampfspezifität', 'race_specificity'),

  /// Physiologische und muskuläre Regeneration / Erholungsbedarf.
  recovery('Regeneration & Entlastung', 'recovery');

  const TrainingNeedType(this.label, this.key);
  final String label;
  final String key;
}

/// Differenzierung der Bedarfsart nach zeitlicher und strategischer Perspektive.
enum NeedCategory {
  /// Was muss langfristig aufgebaut oder verbessert werden?
  development('Development Need', 'development'),

  /// Was ist bereits gut entwickelt und muss erhalten werden?
  maintenance('Maintenance Need', 'maintenance'),

  /// Welcher Reiz wäre im aktuellen Tages-/Wochenkontext eine sinnvolle Gelegenheit?
  immediateOpportunity('Immediate Opportunity', 'immediate_opportunity'),

  /// Was spricht momentan gegen bestimmte Trainingsformen (z. B. Belastungsgrenzen)?
  constraint('Constraint', 'constraint');

  const NeedCategory(this.label, this.key);
  final String label;
  final String key;
}

/// Ordinales Prioritätsmodell (ohne mathematische Scheingenauigkeit).
enum NeedPriority {
  critical(5, 'CRITICAL', 'Kritisch'),
  high(4, 'HIGH', 'Hoch'),
  moderate(3, 'MODERATE', 'Moderat'),
  low(2, 'LOW', 'Niedrig'),
  maintenance(1, 'MAINTENANCE', 'Erhaltend'),
  unknown(0, 'UNKNOWN', 'Unbekannt');

  const NeedPriority(this.rank, this.nameKey, this.label);
  final int rank;
  final String nameKey;
  final String label;

  bool operator >(NeedPriority other) => rank > other.rank;
  bool operator >=(NeedPriority other) => rank >= other.rank;
  bool operator <(NeedPriority other) => rank < other.rank;
  bool operator <=(NeedPriority other) => rank <= other.rank;
}

/// Konfidenz eines Bedarfs (wie sicher ist die Evidenzbasis dahinter).
enum NeedConfidence {
  high('Hoch (belastbare Evidenz)', 0.90),
  moderate('Moderat (plausible Indikatoren)', 0.65),
  low('Niedrig (begrenzte Datenlage)', 0.40),
  unknown('Sehr unsicher (Datenlücken vorhanden)', 0.20);

  const NeedConfidence(this.label, this.numericFactor);
  final String label;
  final double numericFactor;
}

/// Typen von Informations- und Diagnostikbedarfen (Assessment Needs).
enum AssessmentNeedType {
  /// Fehlende oder veraltete Skating-Leistungsdiagnostik (LT1/LT2).
  skatingThresholdAssessment('Skating-Schwellendiagnostik erforderlich', 'skating_threshold'),

  /// Fehlende oder unkalibrierte Ercolina-Doppelstock-Referenz.
  ercolinaDpAssessment('Ercolina DP Kalibrierung / Leistungstest', 'ercolina_dp'),

  /// Unbekannte physiologische Entkopplung bei langen Dauerbelastungen.
  durabilityAssessment('Durability / Entkopplungs-Assessment', 'durability'),

  /// Grundlegende aerobe Leistungsdiagnostik fehlt.
  generalAerobicAssessment('Aerobe Leistungsdiagnostik', 'general_aerobic'),

  /// Keine Beobachtungsdaten zur Skilanglauf-Technik vorhanden.
  techniqueAssessment('Technik-Beobachtung / Video-Feedback', 'technique'),

  /// Fehlende subjektive Rückmeldungen (Schlaf, Erholung, DOMS).
  readinessAssessment('Subjektives Readiness-Feedback erfassen', 'readiness'),

  /// Hohe Zahl unaufgeklärter Tage in den letzten 4 Wochen.
  dataCoverageAssessment('Trainingshistorie synchronisieren / Lücken klären', 'data_coverage');

  const AssessmentNeedType(this.label, this.key);
  final String label;
  final String key;
}
