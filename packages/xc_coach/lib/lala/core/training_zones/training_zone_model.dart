import 'package:xc_coach/lala/core/training_zones/zone_definitions.dart';

enum ZoneModelType {
  thresholdAnchored,
  domain,
  standardFive,
  cyclingSeven,
  olympiatoppen,
  classicPercent,
  custom,
}

class TrainingZoneModel {
  const TrainingZoneModel({
    required this.id,
    required this.name,
    required this.displayName,
    required this.version,
    required this.modelType,
    required this.description,
    required this.scientificDescription,
    required this.zones,
    this.sportTypes = const <String>[],
    this.recommendedSports = const <String>[],
    this.notice,
    this.active = true,
  });

  final String id;
  final String name;
  final String displayName;
  final String version;
  final ZoneModelType modelType;

  /// Leere Liste bedeutet: fuer alle Sportarten verfuegbar.
  final List<String> sportTypes;
  final List<String> recommendedSports;

  final String description;
  final String scientificDescription;

  /// Hinweis, der beim Oeffnen des Modells angezeigt wird.
  final String? notice;

  final List<ZoneDefinition> zones;
  final bool active;

  int get zoneCount => zones.length;

  bool availableFor(String sportKey) =>
      sportTypes.isEmpty || sportTypes.contains(sportKey);
}

const List<ControlMetric> _longSteadyControl = <ControlMetric>[
  ControlMetric.power,
  ControlMetric.heartRate,
  ControlMetric.rpe,
];

const List<ControlMetric> _thresholdControl = <ControlMetric>[
  ControlMetric.power,
  ControlMetric.rpe,
  ControlMetric.heartRate,
];

const List<ControlMetric> _vo2Control = <ControlMetric>[
  ControlMetric.power,
  ControlMetric.intervalTime,
  ControlMetric.rpe,
];

const List<ControlMetric> _sprintControl = <ControlMetric>[
  ControlMetric.power,
  ControlMetric.speed,
  ControlMetric.intervalTime,
];

// ---------------------------------------------------------------------------
// Schwellenverankertes REG-SB-Modell
// ---------------------------------------------------------------------------

const TrainingZoneModel thresholdAnchoredModel = TrainingZoneModel(
  id: 'threshold-anchored-reg-sb',
  name: 'threshold-anchored-reg-sb',
  displayName: 'Schwellenverankertes REG-SB-Modell',
  version: '2.0.1',
  modelType: ZoneModelType.thresholdAnchored,
  description:
      'Die zentrale professionelle Trainingsansicht mit sechs Bereichen von '
      'REG bis SB.',
  scientificDescription:
      'LTP1 markiert den Uebergang von der moderaten in die schwere '
      'Intensitaetsdomaene, LTP2 beziehungsweise das MLSS die obere Grenze '
      'der noch stabilen Laktatkinetik. Die Grenze GA1/GA2 entspricht exakt '
      'LTP1, die Grenze EB/SB exakt der oberen Schwelle. Nur die '
      'Binnengrenzen werden ueber versionierte Faktoren gebildet.',
  zones: <ZoneDefinition>[
    ZoneDefinition(
      code: 'REG',
      displayName: 'Regeneration',
      shortMeaning: 'Regeneration',
      domain: PhysiologicalDomain.moderate,
      purpose: 'Regeneration und aktive Erholung',
      preferredControlMetrics: <ControlMetric>[
        ControlMetric.heartRate,
        ControlMetric.rpe,
        ControlMetric.power,
      ],
      typicalTrainingMethods: <String>[
        'sehr lockeres Ausdauertraining',
        'Ein- und Ausrollen',
        'aktive Regeneration',
      ],
      typicalDuration: '20 bis 60 Minuten',
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1,
        factor: 0.70,
        rationale:
            'Die Obergrenze liegt bei 70 Prozent von LTP1, damit die Einheit '
            'wirklich regenerativ bleibt und die lange Grundlage einen '
            'eigenstaendigen Bereich behaelt.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1HeartRate,
        factor: 0.70,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'GAL',
      displayName: 'Lange lockere Grundlagenausdauer',
      shortMeaning: 'lange Grundlagenausdauer',
      domain: PhysiologicalDomain.moderate,
      purpose: 'lange, ermuedungsarme Grundlagenausdauer',
      preferredControlMetrics: _longSteadyControl,
      typicalTrainingMethods: <String>[
        'lange Radausfahrten',
        'lange ruhige Laeufe',
        'lange Langlaufeinheiten',
        'Fettstoffwechseltraining',
      ],
      typicalDuration: '2 bis 6 Stunden',
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1,
        factor: 0.825,
        rationale:
            'Der Bereich bleibt bewusst deutlich unter LTP1, damit sehr lange '
            'Einheiten ermuedungsarm bleiben.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1HeartRate,
        factor: 0.875,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'GA1',
      displayName: 'Extensive Grundlagenausdauer',
      shortMeaning: 'extensive Grundlage',
      domain: PhysiologicalDomain.moderate,
      purpose: 'Entwicklung der aeroben Grundlagenausdauer',
      preferredControlMetrics: _longSteadyControl,
      typicalTrainingMethods: <String>[
        'extensive Dauermethode',
        'laengere konstante Belastungen',
        'lockeres Fahrtspiel',
      ],
      typicalDuration: '60 bis 180 Minuten',
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1,
        rationale:
            'Diese Grenze entspricht exakt Ihrem individuell bestimmten LTP1. '
            'Bis hierher bleibt die Beanspruchung in der moderaten Domaene.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1HeartRate,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'GA2',
      displayName: 'Intensive aerobe Ausdauer',
      shortMeaning: 'intensive aerobe Ausdauer',
      domain: PhysiologicalDomain.heavy,
      purpose: 'intensive aerobe Ausdauer und Belastungstoleranz',
      preferredControlMetrics: _thresholdControl,
      typicalTrainingMethods: <String>[
        'intensive Dauermethode',
        'laengere Intervalle',
        'Tempowechsel',
        'Fahrtspiel',
      ],
      typicalDuration: '30 bis 90 Minuten',
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperThreshold,
        factor: 0.92,
        rationale:
            'GA2 beginnt direkt oberhalb von LTP1 und endet unterhalb der '
            'oberen Schwelle. Das ist noch kein Schwellentraining.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1HeartRate,
        blendTo: ZoneAnchorRef.upperHeartRate,
        blendFactor: 0.75,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'EB',
      displayName: 'Entwicklungsbereich',
      shortMeaning: 'Schwellen- und Entwicklungsbereich',
      domain: PhysiologicalDomain.heavy,
      purpose: 'Entwicklung der Leistung nahe der oberen Schwelle',
      preferredControlMetrics: _thresholdControl,
      typicalTrainingMethods: <String>[
        'Schwellenintervalle',
        'Tempodauertraining',
        'wettkampfspezifische Einheiten',
      ],
      typicalIntervalLength: '8 bis 20 Minuten',
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperThreshold,
        rationale:
            'Diese Grenze entspricht exakt Ihrer oberen Schwelle. Oberhalb '
            'davon steigt das Laktat auch bei konstanter Belastung weiter an.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperHeartRate,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'SB',
      displayName: 'Spitzenbereich',
      shortMeaning: 'hochintensive Belastung',
      domain: PhysiologicalDomain.severe,
      purpose: 'VO2max, hochintensive Leistung und anaerobe Kapazitaet',
      preferredControlMetrics: _vo2Control,
      typicalTrainingMethods: <String>[
        'VO2max-Intervalle',
        'kurze intensive Intervalle',
        'Sprinttraining',
      ],
      typicalIntervalLength: '30 Sekunden bis 5 Minuten',
    ),
  ],
);

// ---------------------------------------------------------------------------
// 3-Zonen-Domaenenmodell
// ---------------------------------------------------------------------------

const TrainingZoneModel domainThreeZoneModel = TrainingZoneModel(
  id: 'domain-three-zone',
  name: 'domain-three-zone',
  displayName: '3-Zonen-Domaenenmodell',
  version: '1.0.0',
  modelType: ZoneModelType.domain,
  description: 'Fuer wissenschaftliche Trainingsverteilung.',
  scientificDescription:
      'Die drei Zonen entsprechen exakt den physiologischen '
      'Intensitaetsdomaenen. Die Trennungen liegen ohne Zwischenfaktoren auf '
      'LTP1 und auf der oberen Schwelle. Das Modell ist die Grundlage fuer '
      'polarisierte, pyramidale und schwellenorientierte Auswertungen.',
  zones: <ZoneDefinition>[
    ZoneDefinition(
      code: 'Z1',
      displayName: 'Moderate',
      shortMeaning: 'unter der ersten Schwelle',
      domain: PhysiologicalDomain.moderate,
      purpose: 'aerobe Grundlage mit stabilem Laktat auf Ruheniveau',
      preferredControlMetrics: _longSteadyControl,
      typicalTrainingMethods: <String>[
        'extensive Dauermethode',
        'lange ruhige Einheiten',
      ],
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1,
        rationale: 'Die Grenze entspricht exakt LTP1.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1HeartRate,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'Z2',
      displayName: 'Heavy',
      shortMeaning: 'zwischen den Schwellen',
      domain: PhysiologicalDomain.heavy,
      purpose: 'erhoehtes, aber noch stabilisierbares Laktat',
      preferredControlMetrics: _thresholdControl,
      typicalTrainingMethods: <String>[
        'intensive Dauermethode',
        'Schwellenintervalle',
      ],
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperThreshold,
        rationale: 'Die Grenze entspricht exakt der oberen Schwelle.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperHeartRate,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'Z3',
      displayName: 'Severe',
      shortMeaning: 'ueber der oberen Schwelle',
      domain: PhysiologicalDomain.severe,
      purpose: 'kein Laktatgleichgewicht mehr moeglich',
      preferredControlMetrics: _vo2Control,
      typicalTrainingMethods: <String>[
        'VO2max-Intervalle',
        'hochintensive Wettkampfbelastungen',
      ],
    ),
  ],
);

// ---------------------------------------------------------------------------
// 5-Zonen-Standardmodell
// ---------------------------------------------------------------------------

const TrainingZoneModel standardFiveZoneModel = TrainingZoneModel(
  id: 'standard-five-zone',
  name: 'standard-five-zone',
  displayName: '5-Zonen-Standardmodell',
  version: '1.0.0',
  modelType: ZoneModelType.standardFive,
  description: 'Fuer einfache internationale Trainingssteuerung.',
  scientificDescription:
      'Die international gebraeuchliche Fuenfteilung wird nicht aus '
      'FTP-Prozentwerten, sondern aus LTP1 und der oberen Schwelle '
      'abgeleitet. Die Binnenaufteilung innerhalb der Domaenen ist ein '
      'versionierter Modellparameter.',
  zones: <ZoneDefinition>[
    ZoneDefinition(
      code: 'Z1',
      displayName: 'Regeneration',
      shortMeaning: 'Recovery',
      domain: PhysiologicalDomain.moderate,
      purpose: 'aktive Erholung',
      preferredControlMetrics: <ControlMetric>[
        ControlMetric.heartRate,
        ControlMetric.rpe,
        ControlMetric.power,
      ],
      typicalTrainingMethods: <String>['lockeres Ausfahren', 'Regeneration'],
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1,
        factor: 0.80,
        rationale: 'Unterer Bereich unterhalb von LTP1.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1HeartRate,
        factor: 0.85,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'Z2',
      displayName: 'Ausdauer',
      shortMeaning: 'Endurance',
      domain: PhysiologicalDomain.moderate,
      purpose: 'aerobe Grundlagenausdauer',
      preferredControlMetrics: _longSteadyControl,
      typicalTrainingMethods: <String>[
        'extensive Dauermethode',
        'lange Einheiten',
      ],
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1,
        rationale:
            'Mittlerer und oberer Bereich unterhalb von LTP1. Die Obergrenze '
            'entspricht exakt LTP1.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1HeartRate,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'Z3',
      displayName: 'Tempo',
      shortMeaning: 'Tempo',
      domain: PhysiologicalDomain.heavy,
      purpose: 'intensive aerobe Ausdauer unterhalb der Schwelle',
      preferredControlMetrics: _thresholdControl,
      typicalTrainingMethods: <String>[
        'intensive Dauermethode',
        'Tempodauerlauf',
      ],
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1,
        blendTo: ZoneAnchorRef.upperThreshold,
        blendFactor: 0.65,
        rationale:
            'Unterer und mittlerer Bereich zwischen LTP1 und der oberen '
            'Schwelle.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1HeartRate,
        blendTo: ZoneAnchorRef.upperHeartRate,
        blendFactor: 0.65,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'Z4',
      displayName: 'Schwelle',
      shortMeaning: 'Threshold',
      domain: PhysiologicalDomain.heavy,
      purpose: 'Training an der oberen Schwelle',
      preferredControlMetrics: _thresholdControl,
      typicalTrainingMethods: <String>[
        'Schwellenintervalle',
        'wettkampfspezifische Einheiten',
      ],
      typicalIntervalLength: '8 bis 20 Minuten',
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperThreshold,
        rationale:
            'Oberer Bereich zwischen den Schwellen bis exakt zur oberen '
            'Schwelle.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperHeartRate,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'Z5',
      displayName: 'Hochintensiv',
      shortMeaning: 'High Intensity',
      domain: PhysiologicalDomain.severe,
      purpose: 'VO2max und hochintensive Leistungsfaehigkeit',
      preferredControlMetrics: _vo2Control,
      typicalTrainingMethods: <String>['VO2max-Intervalle', 'kurze Intervalle'],
      typicalIntervalLength: '30 Sekunden bis 5 Minuten',
    ),
  ],
);

// ---------------------------------------------------------------------------
// 7-Zonen-Radmodell
// ---------------------------------------------------------------------------

const TrainingZoneModel cyclingSevenZoneModel = TrainingZoneModel(
  id: 'cycling-seven-zone',
  name: 'cycling-seven-zone',
  displayName: '7-Zonen-Radmodell',
  version: '1.0.0',
  modelType: ZoneModelType.cyclingSeven,
  description: 'Fuer detaillierte Watt- und Intervallsteuerung.',
  scientificDescription:
      'Die unteren vier Zonen werden an LTP1 und der oberen Schwelle '
      'verankert. Die Zonen Z5 bis Z7 benoetigen zusaetzlich die maximale '
      'aerobe Leistung und die Maximalleistung. Das Modell beruht bewusst '
      'nicht ausschliesslich auf der FTP.',
  sportTypes: <String>['cycling'],
  recommendedSports: <String>['cycling'],
  zones: <ZoneDefinition>[
    ZoneDefinition(
      code: 'Z1',
      displayName: 'Active Recovery',
      shortMeaning: 'aktive Erholung',
      domain: PhysiologicalDomain.moderate,
      purpose: 'Regeneration',
      preferredControlMetrics: <ControlMetric>[
        ControlMetric.heartRate,
        ControlMetric.rpe,
        ControlMetric.power,
      ],
      typicalTrainingMethods: <String>['Ausrollen', 'Regenerationsfahrt'],
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1,
        factor: 0.60,
        rationale: 'Sehr weit unterhalb von LTP1.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1HeartRate,
        factor: 0.75,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'Z2',
      displayName: 'Endurance',
      shortMeaning: 'Grundlagenausdauer',
      domain: PhysiologicalDomain.moderate,
      purpose: 'aerobe Grundlage',
      preferredControlMetrics: _longSteadyControl,
      typicalTrainingMethods: <String>['lange Ausfahrten'],
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1,
        rationale: 'Die Obergrenze entspricht exakt LTP1.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1HeartRate,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'Z3',
      displayName: 'Tempo',
      shortMeaning: 'Tempo',
      domain: PhysiologicalDomain.heavy,
      purpose: 'intensive aerobe Dauerbelastung',
      preferredControlMetrics: _thresholdControl,
      typicalTrainingMethods: <String>['Tempoblocks', 'Fahrtspiel'],
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperThreshold,
        factor: 0.95,
        rationale: 'Zwischen LTP1 und deutlich unterhalb der oberen Schwelle.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1HeartRate,
        blendTo: ZoneAnchorRef.upperHeartRate,
        blendFactor: 0.80,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'Z4',
      displayName: 'Threshold',
      shortMeaning: 'Schwellenbereich',
      domain: PhysiologicalDomain.heavy,
      purpose: 'Training im direkten Bereich um die obere Schwelle',
      preferredControlMetrics: _thresholdControl,
      typicalTrainingMethods: <String>['Schwellenintervalle'],
      typicalIntervalLength: '8 bis 20 Minuten',
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperThreshold,
        factor: 1.05,
        rationale:
            'Direkter Bereich um die obere Schwelle. Die Schwelle selbst '
            'liegt in der Mitte dieser Zone.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperHeartRate,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'Z5',
      displayName: 'VO2max',
      shortMeaning: 'maximale Sauerstoffaufnahme',
      domain: PhysiologicalDomain.severe,
      purpose: 'Entwicklung der maximalen Sauerstoffaufnahme',
      preferredControlMetrics: _vo2Control,
      typicalTrainingMethods: <String>['VO2max-Intervalle'],
      typicalIntervalLength: '3 bis 8 Minuten',
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.maximalAerobicPower,
        rationale:
            'Oberhalb der oberen Schwelle bis zur maximalen aeroben Leistung.',
        requiresExtendedAnchors: true,
      ),
    ),
    ZoneDefinition(
      code: 'Z6',
      displayName: 'Anaerobic Capacity',
      shortMeaning: 'anaerobe Kapazitaet',
      domain: PhysiologicalDomain.severe,
      purpose: 'anaerobe Kapazitaet oberhalb des VO2max-Bereichs',
      preferredControlMetrics: _sprintControl,
      typicalTrainingMethods: <String>['kurze harte Intervalle'],
      typicalIntervalLength: '30 Sekunden bis 2 Minuten',
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.maximalAerobicPower,
        blendTo: ZoneAnchorRef.maximalPower,
        blendFactor: 0.60,
        rationale:
            'Zwischen maximaler aerober Leistung und neuromuskulaerer '
            'Maximalleistung.',
        requiresExtendedAnchors: true,
      ),
    ),
    ZoneDefinition(
      code: 'Z7',
      displayName: 'Neuromuscular Power',
      shortMeaning: 'Sprint und Maximalkraft',
      domain: PhysiologicalDomain.severe,
      purpose: 'neuromuskulaere Maximalleistung und Sprint',
      preferredControlMetrics: _sprintControl,
      typicalTrainingMethods: <String>['Sprints', 'Antritte'],
      typicalIntervalLength: '5 bis 20 Sekunden',
    ),
  ],
);

// ---------------------------------------------------------------------------
// Olympiatoppen-orientiertes Modell
// ---------------------------------------------------------------------------

const TrainingZoneModel olympiatoppenModel = TrainingZoneModel(
  id: 'olympiatoppen-oriented',
  name: 'olympiatoppen-oriented',
  displayName: 'Olympiatoppen-orientiertes Modell',
  version: '1.0.0',
  modelType: ZoneModelType.olympiatoppen,
  description: 'Für leistungsorientiertes Ausdauertraining mit I1 bis I5.',
  scientificDescription:
      'Das Modell orientiert sich an der norwegischen Intensitätslogik und '
      'ergänzt jede Zone um Laktat, RPE, typische Intervalllänge und '
      'Gesamtdauer. Die Zonengrenzen werden an LTP1 und der oberen Schwelle '
      'ausgerichtet.',
  notice:
      'Dieses Modell ist an der norwegischen Intensitätslogik orientiert und '
      'nicht mit einer offiziellen Version identisch.',
  sportTypes: <String>['cycling', 'running', 'crossCountry', 'rowing'],
  recommendedSports: <String>['crossCountry', 'running'],
  zones: <ZoneDefinition>[
    ZoneDefinition(
      code: 'I1',
      displayName: 'Lockeres Ausdauertraining',
      shortMeaning: 'sehr locker',
      domain: PhysiologicalDomain.moderate,
      purpose: 'Regeneration und aerobe Grundlage',
      preferredControlMetrics: _longSteadyControl,
      typicalTrainingMethods: <String>['lockere Dauermethode'],
      typicalDuration: '60 bis 180 Minuten',
      typicalLactate: '0,7 bis 1,5 mmol/l',
      typicalRpe: '9 bis 11',
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1,
        factor: 0.85,
        rationale: 'Deutlich unterhalb von LTP1.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1HeartRate,
        factor: 0.90,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'I2',
      displayName: 'Extensives Ausdauertraining',
      shortMeaning: 'ruhig bis zügig',
      domain: PhysiologicalDomain.moderate,
      purpose: 'aerobe Kapazität mit hohem Umfang',
      preferredControlMetrics: _longSteadyControl,
      typicalTrainingMethods: <String>['extensive Dauermethode'],
      typicalDuration: '45 bis 120 Minuten',
      typicalLactate: '1,5 bis 2,5 mmol/l',
      typicalRpe: '12 bis 13',
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1,
        rationale: 'Die Obergrenze entspricht exakt LTP1.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1HeartRate,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'I3',
      displayName: 'Intensives Ausdauertraining',
      shortMeaning: 'unter der Schwelle',
      domain: PhysiologicalDomain.heavy,
      purpose: 'Belastungstoleranz zwischen den Schwellen',
      preferredControlMetrics: _thresholdControl,
      typicalTrainingMethods: <String>['längere Intervalle'],
      typicalIntervalLength: '8 bis 15 Minuten',
      typicalDuration: '30 bis 60 Minuten Nettobelastung',
      typicalLactate: '2,5 bis 4,0 mmol/l',
      typicalRpe: '14 bis 15',
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1,
        blendTo: ZoneAnchorRef.upperThreshold,
        blendFactor: 0.85,
        rationale: 'Unterhalb der oberen Schwelle.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.lt1HeartRate,
        blendTo: ZoneAnchorRef.upperHeartRate,
        blendFactor: 0.85,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'I4',
      displayName: 'Schwellentraining',
      shortMeaning: 'an der Schwelle',
      domain: PhysiologicalDomain.heavy,
      purpose: 'Verschiebung der oberen Schwelle',
      preferredControlMetrics: _thresholdControl,
      typicalTrainingMethods: <String>['Schwellenintervalle'],
      typicalIntervalLength: '5 bis 10 Minuten',
      typicalDuration: '20 bis 40 Minuten Nettobelastung',
      typicalLactate: '4,0 bis 6,0 mmol/l',
      typicalRpe: '16 bis 17',
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperThreshold,
        rationale: 'Die Obergrenze entspricht exakt der oberen Schwelle.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperHeartRate,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'I5',
      displayName: 'Maximales Ausdauertraining',
      shortMeaning: 'über der Schwelle',
      domain: PhysiologicalDomain.severe,
      purpose: 'maximale Sauerstoffaufnahme',
      preferredControlMetrics: _vo2Control,
      typicalTrainingMethods: <String>['VO2max-Intervalle'],
      typicalIntervalLength: '2 bis 5 Minuten',
      typicalDuration: '12 bis 25 Minuten Nettobelastung',
      typicalLactate: 'über 6,0 mmol/l',
      typicalRpe: '18 bis 20',
    ),
  ],
);

// ---------------------------------------------------------------------------
// Klassisches LTP2-Prozentmodell
// ---------------------------------------------------------------------------

const TrainingZoneModel classicPercentModel = TrainingZoneModel(
  id: 'classic-ltp2-percent',
  name: 'classic-ltp2-percent',
  displayName: 'Klassisches LTP2-Prozentmodell',
  version: '1.1.0',
  modelType: ZoneModelType.classicPercent,
  description: 'Fuer Vergleich mit aelteren Diagnostiken.',
  scientificDescription:
      'Alle Grenzen werden ausschliesslich als Prozentwerte der LTP2-Leistung '
      'beziehungsweise der Herzfrequenz an LTP2 gebildet. LTP1 wird nicht '
      'abgebildet.',
  notice:
      'Dieses Modell bildet die Trainingsbereiche aus festen Prozentwerten '
      'des LTP2. Fuer neue Diagnostiken wird das schwellenverankerte '
      'REG-SB-Modell empfohlen.',
  zones: <ZoneDefinition>[
    ZoneDefinition(
      code: 'REG',
      displayName: 'Regeneration',
      shortMeaning: 'Regeneration',
      domain: PhysiologicalDomain.moderate,
      purpose: 'Regeneration',
      preferredControlMetrics: _longSteadyControl,
      typicalTrainingMethods: <String>['lockeres Ausdauertraining'],
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperThreshold,
        factor: 0.55,
        rationale:
            'Fester Prozentwert der LTP2-Leistung, nicht an LTP1 '
            'verankert.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperHeartRate,
        factor: 0.70,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'GAL',
      displayName: 'Lange Grundlagenausdauer',
      shortMeaning: 'lange Grundlagenausdauer',
      domain: PhysiologicalDomain.moderate,
      purpose: 'lange Grundlagenausdauer',
      preferredControlMetrics: _longSteadyControl,
      typicalTrainingMethods: <String>['lange Einheiten'],
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperThreshold,
        factor: 0.65,
        rationale: 'Fester Prozentwert der LTP2-Leistung.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperHeartRate,
        factor: 0.80,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'GA1',
      displayName: 'Extensive Grundlagenausdauer',
      shortMeaning: 'extensive Grundlage',
      domain: PhysiologicalDomain.moderate,
      purpose: 'aerobe Grundlagenausdauer',
      preferredControlMetrics: _longSteadyControl,
      typicalTrainingMethods: <String>['extensive Dauermethode'],
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperThreshold,
        factor: 0.75,
        rationale: 'Fester Prozentwert der LTP2-Leistung.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperHeartRate,
        factor: 0.87,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'GA2',
      displayName: 'Intensive Ausdauer',
      shortMeaning: 'intensive Ausdauer',
      domain: PhysiologicalDomain.heavy,
      purpose: 'intensive Ausdauer',
      preferredControlMetrics: _thresholdControl,
      typicalTrainingMethods: <String>['intensive Dauermethode'],
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperThreshold,
        factor: 0.90,
        rationale: 'Fester Prozentwert der LTP2-Leistung.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperHeartRate,
        factor: 0.95,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'EB',
      displayName: 'Entwicklungsbereich',
      shortMeaning: 'Schwellenbereich',
      domain: PhysiologicalDomain.heavy,
      purpose: 'Schwellentraining',
      preferredControlMetrics: _thresholdControl,
      typicalTrainingMethods: <String>['Schwellenintervalle'],
      upperLoadRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperThreshold,
        rationale: '100 Prozent der LTP2-Leistung.',
      ),
      upperHeartRateRule: BoundaryRule(
        anchor: ZoneAnchorRef.upperHeartRate,
        rationale: '',
      ),
    ),
    ZoneDefinition(
      code: 'SB',
      displayName: 'Spitzenbereich',
      shortMeaning: 'hochintensiv',
      domain: PhysiologicalDomain.severe,
      purpose: 'hochintensive Belastung',
      preferredControlMetrics: _vo2Control,
      typicalTrainingMethods: <String>['VO2max-Intervalle'],
    ),
  ],
);

const List<TrainingZoneModel> builtInZoneModels = <TrainingZoneModel>[
  thresholdAnchoredModel,
  domainThreeZoneModel,
  standardFiveZoneModel,
  cyclingSevenZoneModel,
  olympiatoppenModel,
  classicPercentModel,
];

/// Registry aus eingebauten und benutzerdefinierten Labor-Modellen.
///
/// Benutzerdefinierte Modelle werden versioniert abgelegt. Bereits erzeugte
/// Zonensaetze bleiben davon unberuehrt, weil sie ihre Modellversion selbst
/// speichern.
class ZoneModelRegistry {
  ZoneModelRegistry();

  final List<TrainingZoneModel> _custom = <TrainingZoneModel>[];

  List<TrainingZoneModel> get all => <TrainingZoneModel>[
    ...builtInZoneModels,
    ..._custom,
  ].where((model) => model.active).toList(growable: false);

  void register(TrainingZoneModel model) {
    _custom.removeWhere(
      (existing) =>
          existing.id == model.id && existing.version == model.version,
    );
    _custom.add(model);
  }

  TrainingZoneModel byId(String id) => all.firstWhere(
    (model) => model.id == id,
    orElse: () => thresholdAnchoredModel,
  );
}

final ZoneModelRegistry zoneModelRegistry = ZoneModelRegistry();

List<TrainingZoneModel> get availableZoneModels => zoneModelRegistry.all;

TrainingZoneModel zoneModelById(String id) => zoneModelRegistry.byId(id);

/// Normalisiert die frei eingegebene Sportart auf einen internen Schluessel.
String sportKeyOf(String sportType) {
  final value = sportType.toLowerCase();
  if (value.contains('langlauf') ||
      value.contains('ski') ||
      value.contains('roller') ||
      value.contains('nordic')) {
    return 'crossCountry';
  }
  if (value.contains('rad') ||
      value.contains('bike') ||
      value.contains('cycl') ||
      value.contains('ergometer')) {
    return 'cycling';
  }
  if (value.contains('ruder') || value.contains('row')) {
    return 'rowing';
  }
  if (value.contains('lauf') || value.contains('run')) {
    return 'running';
  }
  return 'generic';
}

/// Das empfohlene Standardmodell ist immer das schwellenverankerte Modell.
TrainingZoneModel defaultModelForSport(String sportType) =>
    thresholdAnchoredModel;

/// Weitere sinnvolle Darstellungen fuer eine Sportart, ohne das Standardmodell.
List<TrainingZoneModel> alternativeModelsForSport(String sportType) {
  final key = sportKeyOf(sportType);
  final order = switch (key) {
    'cycling' => <String>[
      cyclingSevenZoneModel.id,
      domainThreeZoneModel.id,
      standardFiveZoneModel.id,
      classicPercentModel.id,
    ],
    'running' => <String>[
      standardFiveZoneModel.id,
      domainThreeZoneModel.id,
      olympiatoppenModel.id,
      classicPercentModel.id,
    ],
    'crossCountry' || 'rowing' => <String>[
      olympiatoppenModel.id,
      domainThreeZoneModel.id,
      standardFiveZoneModel.id,
      classicPercentModel.id,
    ],
    _ => <String>[
      domainThreeZoneModel.id,
      standardFiveZoneModel.id,
      classicPercentModel.id,
    ],
  };

  final models = availableZoneModels;
  final result = <TrainingZoneModel>[];
  for (final id in order) {
    final model = models.where((m) => m.id == id).firstOrNull;
    if (model != null && model.availableFor(key)) {
      result.add(model);
    }
  }
  for (final model in models) {
    if (model.id != thresholdAnchoredModel.id &&
        model.availableFor(key) &&
        !result.contains(model)) {
      result.add(model);
    }
  }
  return List.unmodifiable(result);
}

/// Alle fuer eine Sportart angebotenen Modelle, empfohlenes Modell zuerst.
List<TrainingZoneModel> modelsForSport(String sportType) => <TrainingZoneModel>[
  defaultModelForSport(sportType),
  ...alternativeModelsForSport(sportType),
];
