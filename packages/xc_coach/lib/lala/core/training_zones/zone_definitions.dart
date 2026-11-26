/// Die drei physiologischen Intensitaetsdomaenen. Jede Trainingszone jedes
/// Modells wird intern einer dieser Domaenen zugeordnet, damit unabhaengig
/// vom gewaehlten Modell nachvollziehbar bleibt, wo eine Belastung liegt.
enum PhysiologicalDomain { moderate, heavy, severe }

/// Herkunft der oberen Schwelle, nach absteigender Verlaesslichkeit.
enum ThresholdSource {
  confirmedMlss,
  confirmedLtp2,
  estimatedLtp2,
  provisionalConsensus,
}

/// Steuergroessen einer Trainingszone.
enum ControlMetric { power, speed, pace, heartRate, rpe, lactate, intervalTime }

/// Qualitaetskennzeichnung eines erzeugten Zonensatzes.
enum ZoneSetQuality {
  provisional,
  plausible,
  confirmed,
  limited,
  notCalculable,
}

/// Referenzgroessen, an denen eine Zonengrenze verankert werden kann.
enum ZoneAnchorRef {
  zero,
  lt1,
  upperThreshold,
  criticalPower,
  maximalAerobicPower,
  maximalPower,
  lt1HeartRate,
  upperHeartRate,
  maximalHeartRate,
}

/// Regel fuer eine Zonenobergrenze.
///
/// Entweder ein Anteil eines Ankers oder eine Interpolation zwischen zwei
/// Ankern. Die Regel ist reine Beschreibung; aufgeloest wird sie erst mit
/// einem konkreten Ankersatz.
class BoundaryRule {
  const BoundaryRule({
    required this.anchor,
    required this.rationale,
    this.factor = 1.0,
    this.blendTo,
    this.blendFactor = 0.0,
    this.requiresExtendedAnchors = false,
  });

  final ZoneAnchorRef anchor;

  /// Anteil des Ankerwertes, wenn keine Interpolation genutzt wird.
  final double factor;

  /// Zweiter Anker fuer die Interpolation zwischen [anchor] und [blendTo].
  final ZoneAnchorRef? blendTo;

  /// Anteil des Abstandes zwischen [anchor] und [blendTo].
  final double blendFactor;

  /// Kennzeichnet Grenzen, die zusaetzliche Maximaltests voraussetzen.
  final bool requiresExtendedAnchors;

  /// Klartextbegruendung ohne konkreten Zahlenwert.
  final String rationale;
}

/// Definition einer einzelnen Zone innerhalb eines Modells.
class ZoneDefinition {
  const ZoneDefinition({
    required this.code,
    required this.displayName,
    required this.shortMeaning,
    required this.domain,
    required this.purpose,
    required this.preferredControlMetrics,
    required this.typicalTrainingMethods,
    this.upperLoadRule,
    this.upperHeartRateRule,
    this.typicalDuration,
    this.typicalIntervalLength,
    this.typicalLactate,
    this.typicalRpe,
  });

  final String code;
  final String displayName;
  final String shortMeaning;
  final PhysiologicalDomain domain;
  final String purpose;

  /// Erste Metrik ist die primaere Steuergroesse.
  final List<ControlMetric> preferredControlMetrics;
  final List<String> typicalTrainingMethods;

  /// Null bedeutet: nach oben offene Zone.
  final BoundaryRule? upperLoadRule;
  final BoundaryRule? upperHeartRateRule;

  final String? typicalDuration;
  final String? typicalIntervalLength;
  final String? typicalLactate;
  final String? typicalRpe;
}

const Map<PhysiologicalDomain, String>
domainLabels = <PhysiologicalDomain, String>{
  PhysiologicalDomain.moderate: 'Moderate Domain (unterhalb von LTP1)',
  PhysiologicalDomain.heavy: 'Heavy Domain (zwischen LTP1 und oberer Schwelle)',
  PhysiologicalDomain.severe: 'Severe Domain (oberhalb der oberen Schwelle)',
};

const Map<PhysiologicalDomain, String> domainShortLabels =
    <PhysiologicalDomain, String>{
      PhysiologicalDomain.moderate: 'unter der ersten Schwelle',
      PhysiologicalDomain.heavy: 'zwischen den Schwellen',
      PhysiologicalDomain.severe: 'ueber der oberen Schwelle',
    };

const Map<ControlMetric, String> controlMetricLabels = <ControlMetric, String>{
  ControlMetric.power: 'Leistung',
  ControlMetric.speed: 'Geschwindigkeit',
  ControlMetric.pace: 'Pace',
  ControlMetric.heartRate: 'Herzfrequenz',
  ControlMetric.rpe: 'RPE',
  ControlMetric.lactate: 'Laktat',
  ControlMetric.intervalTime: 'Intervallzeit',
};

const Map<ThresholdSource, String> thresholdSourceLabels =
    <ThresholdSource, String>{
      ThresholdSource.confirmedMlss: 'bestaetigtes MLSS',
      ThresholdSource.confirmedLtp2: 'bestaetigter LTP2',
      ThresholdSource.estimatedLtp2: 'geschaetzter LTP2',
      ThresholdSource.provisionalConsensus: 'vorlaeufiger LT2-Konsenswert',
    };

const Map<ZoneSetQuality, String> zoneQualityLabels = <ZoneSetQuality, String>{
  ZoneSetQuality.provisional: 'vorlaeufig',
  ZoneSetQuality.plausible: 'plausibel',
  ZoneSetQuality.confirmed: 'bestaetigt',
  ZoneSetQuality.limited: 'eingeschraenkt',
  ZoneSetQuality.notCalculable: 'nicht berechenbar',
};

const String heartRateReactionNote =
    'Die Herzfrequenz reagiert verzoegert und wird durch Temperatur, '
    'Dehydrierung, Ermuedung, Hoehe, Stress und Tagesform beeinflusst. Bei '
    'kurzen hochintensiven Belastungen ist sie deshalb keine Zielgroesse, '
    'sondern nur eine Kontrollgroesse.';

const String sharedAnchorNote =
    'Alle dargestellten Modelle beruhen auf denselben physiologischen '
    'Schwellen. Sie unterscheiden sich nur in der Anzahl, Benennung und '
    'praktischen Unterteilung der Trainingsbereiche.';

const String extendedAnchorNote =
    'Die oberen Zonen basieren derzeit auf einer vereinfachten Schaetzung. '
    'Fuer eine genauere Bestimmung sind zusaetzliche Maximaltests '
    'erforderlich.';

bool isConfirmedSource(ThresholdSource source) =>
    source == ThresholdSource.confirmedMlss ||
    source == ThresholdSource.confirmedLtp2;
