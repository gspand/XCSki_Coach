/// Wissenschaftlich fundierte, konservative Domänenmodelle für das
/// Female Athlete & Menstrual Cycle Intelligence Modul in GIULIA.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - KEIN pauschales "Cycle Syncing".
/// - Keine universellen Regeln wie "Ovulation = Verletzungsgefahr" oder "Luteal = schlechte Performance".
/// - Getrennte Architekturebenen:
///   1. [CycleContext]: Was wissen wir über den reproduktiven/hormonellen Kontext?
///   2. [CycleResponseEvidence]: Welche individuellen Zusammenhänge wurden bei DIESER Athletin wiederholt beobachtet?
///   3. [FemaleAthleteHealthContext]: Welche gesundheitsrelevanten Signale (RED-S, Amenorrhoe, Heavy Bleeding) existieren unabhängig vom Training?
/// - Keine Kausalitätsbehauptungen ("Correlation != Causation").
/// - Wissenschaftliche Basis:
///   * McNulty et al., Sports Medicine 2020 (PMID: 32661839)
///   * Elliott-Sale et al., Sports Medicine 2020 (PMID: 32666247)
///   * Janse de Jonge et al., MSSE 2019 (PMID: 31246715)
///   * UEFA Consensus Statement on Menstrual Cycle Tracking, 2025 (PMID: 41001255)
///   * IOC REDs Consensus Statement, BJSM 2023
///   * Taim et al., Sports Medicine 2023 (PMID: 37389782)
///   * Ihalainen et al., 2024 (PMID: 39802676)
///   * Stitelmann et al., Sports Medicine 2026 (PMID: 41790346)
library;

/// Status der freiwilligen Einwilligung (Opt-in) für Zyklus- und Female-Athlete-Daten.
enum FemaleCycleTrackingOptIn {
  enabled('Aktiviert'),
  undecided('Später entscheiden'),
  disabled('Deaktiviert');

  const FemaleCycleTrackingOptIn(this.label);
  final String label;

  bool get isEnabled => this == FemaleCycleTrackingOptIn.enabled;
}

/// Hormoneller Status der Athletin.
/// Natürlicher Zyklus wird strikt von hormoneller Kontrazeption getrennt.
enum HormonalStatus {
  naturalCycle('Natürlicher Menstruationszyklus'),
  combinedHormonalContraceptive('Kombinierte hormonelle Kontrazeption (Pille/Pflaster/Ring)'),
  progestinOnlyContraceptive('Reine Gestagen-Kontrazeption (Minipille/Implantat/Depot)'),
  hormonalIUD('Hormonspirale (LNG-IUS)'),
  copperIUD('Kupferspirale (hormonfrei)'),
  otherHormonalContraception('Sonstige hormonelle Kontrazeption'),
  noCycle('Kein Zyklus / Amenorrhoe berichtet'),
  pregnancy('Schwangerschaft'),
  postpartum('Postpartale Phase'),
  perimenopause('Perimenopause'),
  menopause('Menopause'),
  unknown('Unbekannt'),
  preferNotToSay('Keine Angabe');

  const HormonalStatus(this.label);
  final String label;

  bool get isNatural => this == HormonalStatus.naturalCycle || this == HormonalStatus.copperIUD;
  bool get isHormonalContraceptive =>
      this == HormonalStatus.combinedHormonalContraceptive ||
      this == HormonalStatus.progestinOnlyContraceptive ||
      this == HormonalStatus.hormonalIUD ||
      this == HormonalStatus.otherHormonalContraception;
}

/// Blutungsausprägung.
enum BleedingIntensity {
  none('Keine Blutung'),
  spotting('Schmierblutung / Spotting'),
  light('Leicht'),
  medium('Mittel'),
  heavy('Stark');

  const BleedingIntensity(this.label);
  final String label;
}

/// Methode, mit der eine Zyklusphase geschätzt oder ermittelt wurde.
enum CycleInferenceMethod {
  calendarEstimate('Kalender-Schätzung (niedrige Verlässlichkeit)'),
  bleedingBased('Auf Basis verifizierter Blutungstage'),
  lhTestSupported('LH-Test unterstützt (Ovulationstest)'),
  basalTemperatureSupported('Basaltemperatur unterstützt'),
  clinicallyMeasured('Klinisch / labordiagnostisch gemessen'),
  hormoneMeasured('Hormonell im Labor gemessen');

  const CycleInferenceMethod(this.label);
  final String label;

  bool get isObjective =>
      this == CycleInferenceMethod.lhTestSupported ||
      this == CycleInferenceMethod.basalTemperatureSupported ||
      this == CycleInferenceMethod.clinicallyMeasured ||
      this == CycleInferenceMethod.hormoneMeasured;
}

/// Schätzung der groben Zyklusphase (strikte wissenschaftliche Einordnung: Konfidenz beachten!).
enum CyclePhaseEstimate {
  earlyFollicularMenstrual('Frühe Follikelphase / Menstruation'),
  lateFollicular('Späte Follikelphase'),
  ovulatoryWindow('Periovulatorisches Fenster'),
  earlyMidLuteal('Frühe bis mittlere Lutealphase'),
  lateLutealPremenstrual('Späte Lutealphase / Prämenstruell'),
  activePillPhase('Aktive Pillen-/Hormonphase'),
  hormoneFreeInterval('Hormonfreies Intervall (Absetzblutung)'),
  uncertainOrUnknown('Ungewiss oder unbekannt');

  const CyclePhaseEstimate(this.label);
  final String label;
}

/// Datenherkunft / Provenance für wissenschaftliche Nachvollziehbarkeit.
enum CycleDataProvenance {
  userReported('Selbstauskunft durch Athletin'),
  wearable('Sensor / Wearable'),
  imported('Importierte Datenquelle'),
  labMeasured('Labordiagnostisch gemessen'),
  clinicallyConfirmed('Ärztlich / klinisch bestätigt'),
  inferred('Algorithmic Inferred');

  const CycleDataProvenance(this.label);
  final String label;
}

/// Einzelne dokumentierte Zyklussymptome mit Schweregrad.
enum SymptomSeverity {
  none(0, 'Keine'),
  mild(1, 'Leicht'),
  moderate(2, 'Mäßig'),
  severe(3, 'Stark');

  const SymptomSeverity(this.score, this.label);
  final int score;
  final String label;
}

/// Konkrete Ausprägungen des täglichen Zyklus- und Befindlichkeits-Checks.
class DailyCycleSymptomReport {
  const DailyCycleSymptomReport({
    required this.date,
    this.bleeding = BleedingIntensity.none,
    this.cramps = SymptomSeverity.none,
    this.unusualFatigue = SymptomSeverity.none,
    this.energyLevel, // 1 (völlig erschöpft) bis 10 (hervorragend)
    this.sleepDisturbance = SymptomSeverity.none,
    this.moodChanges = SymptomSeverity.none,
    this.headache = SymptomSeverity.none,
    this.giSymptoms = SymptomSeverity.none,
    this.breastTenderness = SymptomSeverity.none,
    this.perceivedReadiness, // 1 bis 10
    this.notes,
    this.recordedAtUtcUs,
  });

  final DateTime date;
  final BleedingIntensity bleeding;
  final SymptomSeverity cramps;
  final SymptomSeverity unusualFatigue;
  final double? energyLevel;
  final SymptomSeverity sleepDisturbance;
  final SymptomSeverity moodChanges;
  final SymptomSeverity headache;
  final SymptomSeverity giSymptoms;
  final SymptomSeverity breastTenderness;
  final double? perceivedReadiness;
  final String? notes;
  final int? recordedAtUtcUs;

  bool get hasRelevantSymptoms =>
      cramps.score >= 2 ||
      unusualFatigue.score >= 2 ||
      headache.score >= 2 ||
      giSymptoms.score >= 2 ||
      (energyLevel != null && energyLevel! <= 3.0) ||
      (perceivedReadiness != null && perceivedReadiness! <= 3.0);

  bool get isSevere =>
      cramps == SymptomSeverity.severe ||
      unusualFatigue == SymptomSeverity.severe ||
      headache == SymptomSeverity.severe ||
      giSymptoms == SymptomSeverity.severe;

  List<String> describeActiveSymptoms() {
    final list = <String>[];
    if (bleeding != BleedingIntensity.none) list.add('Blutung (${bleeding.label})');
    if (cramps != SymptomSeverity.none) list.add('Krämpfe (${cramps.label})');
    if (unusualFatigue != SymptomSeverity.none) list.add('Müdigkeit (${unusualFatigue.label})');
    if (headache != SymptomSeverity.none) list.add('Kopfschmerzen (${headache.label})');
    if (giSymptoms != SymptomSeverity.none) list.add('Magen-Darm (${giSymptoms.label})');
    if (breastTenderness != SymptomSeverity.none) list.add('Brustspannen (${breastTenderness.label})');
    if (moodChanges != SymptomSeverity.none) list.add('Stimmungsschwankungen (${moodChanges.label})');
    return list;
  }

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String().split('T').first,
    'bleeding': bleeding.name,
    'cramps': cramps.name,
    'unusualFatigue': unusualFatigue.name,
    if (energyLevel != null) 'energyLevel': energyLevel,
    'sleepDisturbance': sleepDisturbance.name,
    'moodChanges': moodChanges.name,
    'headache': headache.name,
    'giSymptoms': giSymptoms.name,
    'breastTenderness': breastTenderness.name,
    if (perceivedReadiness != null) 'perceivedReadiness': perceivedReadiness,
    if (notes != null) 'notes': notes,
    if (recordedAtUtcUs != null) 'recordedAtUtcUs': recordedAtUtcUs,
  };

  factory DailyCycleSymptomReport.fromJson(Map<String, dynamic> json) => DailyCycleSymptomReport(
    date: DateTime.parse(json['date'] as String),
    bleeding: BleedingIntensity.values.byName(json['bleeding'] as String? ?? 'none'),
    cramps: SymptomSeverity.values.byName(json['cramps'] as String? ?? 'none'),
    unusualFatigue: SymptomSeverity.values.byName(json['unusualFatigue'] as String? ?? 'none'),
    energyLevel: (json['energyLevel'] as num?)?.toDouble(),
    sleepDisturbance: SymptomSeverity.values.byName(json['sleepDisturbance'] as String? ?? 'none'),
    moodChanges: SymptomSeverity.values.byName(json['moodChanges'] as String? ?? 'none'),
    headache: SymptomSeverity.values.byName(json['headache'] as String? ?? 'none'),
    giSymptoms: SymptomSeverity.values.byName(json['giSymptoms'] as String? ?? 'none'),
    breastTenderness: SymptomSeverity.values.byName(json['breastTenderness'] as String? ?? 'none'),
    perceivedReadiness: (json['perceivedReadiness'] as num?)?.toDouble(),
    notes: json['notes'] as String?,
    recordedAtUtcUs: json['recordedAtUtcUs'] as int?,
  );
}

/// Einzelne dokumentierte Zyklusepisode / Periode.
class RecordedCyclePeriod {
  const RecordedCyclePeriod({
    required this.id,
    required this.startDate,
    this.endDate,
    this.averageBleeding = BleedingIntensity.medium,
    this.cycleLengthDays,
    this.isSpottingOnly = false,
    this.hasPerceivedOvulation = false,
    this.hasObjectiveOvulation = false,
    this.provenance = CycleDataProvenance.userReported,
  });

  final String id;
  final DateTime startDate;
  final DateTime? endDate;
  final BleedingIntensity averageBleeding;
  final int? cycleLengthDays;
  final bool isSpottingOnly;
  final bool hasPerceivedOvulation;
  final bool hasObjectiveOvulation;
  final CycleDataProvenance provenance;

  Map<String, dynamic> toJson() => {
    'id': id,
    'startDate': startDate.toIso8601String().split('T').first,
    if (endDate != null) 'endDate': endDate!.toIso8601String().split('T').first,
    'averageBleeding': averageBleeding.name,
    if (cycleLengthDays != null) 'cycleLengthDays': cycleLengthDays,
    'isSpottingOnly': isSpottingOnly,
    'hasPerceivedOvulation': hasPerceivedOvulation,
    'hasObjectiveOvulation': hasObjectiveOvulation,
    'provenance': provenance.name,
  };

  factory RecordedCyclePeriod.fromJson(Map<String, dynamic> json) => RecordedCyclePeriod(
    id: json['id'] as String,
    startDate: DateTime.parse(json['startDate'] as String),
    endDate: json['endDate'] != null ? DateTime.parse(json['endDate'] as String) : null,
    averageBleeding: BleedingIntensity.values.byName(json['averageBleeding'] as String? ?? 'medium'),
    cycleLengthDays: json['cycleLengthDays'] as int?,
    isSpottingOnly: json['isSpottingOnly'] as bool? ?? false,
    hasPerceivedOvulation: json['hasPerceivedOvulation'] as bool? ?? false,
    hasObjectiveOvulation: json['hasObjectiveOvulation'] as bool? ?? false,
    provenance: CycleDataProvenance.values.byName(json['provenance'] as String? ?? 'userReported'),
  );
}

/// EBENE A: Reproduktiver / hormoneller Kontext zum Zeitpunkt der Betrachtung.
class CycleContext {
  const CycleContext({
    this.optIn = FemaleCycleTrackingOptIn.undecided,
    this.hormonalStatus = HormonalStatus.unknown,
    this.currentCycleDay,
    this.estimatedPhase = CyclePhaseEstimate.uncertainOrUnknown,
    this.phaseConfidence = 0.0,
    this.inferenceMethod = CycleInferenceMethod.calendarEstimate,
    this.lastBleedingStart,
    this.averageCycleLengthDays,
    this.observedCyclesCount = 0,
    this.isRegularCycle,
    this.contraceptiveMethodDetails,
    this.contraceptiveStartOrChangeDate,
    this.asOf,
    this.cycleInferenceVersion = 'v1.0.0',
  });

  final FemaleCycleTrackingOptIn optIn;
  final HormonalStatus hormonalStatus;
  final int? currentCycleDay;
  final CyclePhaseEstimate estimatedPhase;
  final double phaseConfidence; // 0.0 bis 1.0 (Kalender allein ist maximal 0.3)
  final CycleInferenceMethod inferenceMethod;
  final DateTime? lastBleedingStart;
  final double? averageCycleLengthDays;
  final int observedCyclesCount;
  final bool? isRegularCycle;
  final String? contraceptiveMethodDetails;
  final DateTime? contraceptiveStartOrChangeDate;
  final DateTime? asOf;
  final String cycleInferenceVersion;

  bool get isTrackingActive => optIn.isEnabled && hormonalStatus != HormonalStatus.preferNotToSay;
  bool get hasSufficientHistory => observedCyclesCount >= 3;

  Map<String, dynamic> toJson() => {
    'optIn': optIn.name,
    'hormonalStatus': hormonalStatus.name,
    if (currentCycleDay != null) 'currentCycleDay': currentCycleDay,
    'estimatedPhase': estimatedPhase.name,
    'phaseConfidence': phaseConfidence,
    'inferenceMethod': inferenceMethod.name,
    if (lastBleedingStart != null) 'lastBleedingStart': lastBleedingStart!.toIso8601String().split('T').first,
    if (averageCycleLengthDays != null) 'averageCycleLengthDays': averageCycleLengthDays,
    'observedCyclesCount': observedCyclesCount,
    if (isRegularCycle != null) 'isRegularCycle': isRegularCycle,
    if (contraceptiveMethodDetails != null) 'contraceptiveMethodDetails': contraceptiveMethodDetails,
    if (contraceptiveStartOrChangeDate != null)
      'contraceptiveStartOrChangeDate': contraceptiveStartOrChangeDate!.toIso8601String().split('T').first,
    if (asOf != null) 'asOf': asOf!.toIso8601String(),
    'cycleInferenceVersion': cycleInferenceVersion,
  };

  factory CycleContext.fromJson(Map<String, dynamic> json) => CycleContext(
    optIn: FemaleCycleTrackingOptIn.values.byName(json['optIn'] as String? ?? 'undecided'),
    hormonalStatus: HormonalStatus.values.byName(json['hormonalStatus'] as String? ?? 'unknown'),
    currentCycleDay: json['currentCycleDay'] as int?,
    estimatedPhase: CyclePhaseEstimate.values.byName(json['estimatedPhase'] as String? ?? 'uncertainOrUnknown'),
    phaseConfidence: (json['phaseConfidence'] as num?)?.toDouble() ?? 0.0,
    inferenceMethod: CycleInferenceMethod.values.byName(json['inferenceMethod'] as String? ?? 'calendarEstimate'),
    lastBleedingStart: json['lastBleedingStart'] != null ? DateTime.parse(json['lastBleedingStart'] as String) : null,
    averageCycleLengthDays: (json['averageCycleLengthDays'] as num?)?.toDouble(),
    observedCyclesCount: json['observedCyclesCount'] as int? ?? 0,
    isRegularCycle: json['isRegularCycle'] as bool?,
    contraceptiveMethodDetails: json['contraceptiveMethodDetails'] as String?,
    contraceptiveStartOrChangeDate: json['contraceptiveStartOrChangeDate'] != null
        ? DateTime.parse(json['contraceptiveStartOrChangeDate'] as String)
        : null,
    asOf: json['asOf'] != null ? DateTime.parse(json['asOf'] as String) : null,
    cycleInferenceVersion: json['cycleInferenceVersion'] as String? ?? 'v1.0.0',
  );
}

/// Evidenzstufe für persönliche Muster (Within-Athlete).
enum PatternConfidence {
  insufficient('Zu wenig Daten (< 3 Zyklen oder uneinheitlich)'),
  emerging('Möglicherweise vorhanden (frühe Beobachtung)'),
  repeated('Mehrfach beobachtet (über Zyklen hinweg)'),
  strongPersonalEvidence('Starke persönliche Evidenz (wiederholt, konsistent, ohne Confounder)');

  const PatternConfidence(this.label);
  final String label;

  bool get isActionable =>
      this == PatternConfidence.repeated || this == PatternConfidence.strongPersonalEvidence;
}

/// Relevantes Leistungs- oder Erholungs-Outcome für persönliche Muster.
enum PatternOutcome {
  higherRpeForSameLoad('Erhöhte RPE bei gleicher Belastung'),
  lowerErcolinaPower('Verminderte Arbeitsleistung / Watt auf Ercolina'),
  alteredHeartRateResponse('Erhöhte HF bei gleicher submaximaler Leistung'),
  delayedRecoveryNextDay('Verlangsamte Regeneration am Folgetag'),
  impairedSleepQuality('Beeinträchtigte Schlafqualität'),
  sessionAbortionOrStruggle('Häufigerer Abbruch oder Anpassung harter Reize');

  const PatternOutcome(this.label);
  final String label;
}

/// Einzelnes innerhalb derselben Athletin longitudinal beobachtetes Muster.
class PersonalCyclePattern {
  const PersonalCyclePattern({
    required this.id,
    required this.outcome,
    required this.contextDescription,
    required this.symptomOrPhaseTrigger,
    required this.magnitudeDescriptor,
    required this.observationsCount,
    required this.cyclesObservedCount,
    required this.consistencyScore, // 0.0 bis 1.0
    required this.confidence,
    this.confoundersConsidered = const [],
    this.evidenceIds = const [],
    required this.firstObserved,
    required this.lastObserved,
    this.modelVersion = 'v1.0.0',
  });

  final String id;
  final PatternOutcome outcome;
  final String contextDescription;
  final String symptomOrPhaseTrigger;
  final String magnitudeDescriptor; // z. B. "+1.5 RPE-Punkte", "-8 W Dauerleistung"
  final int observationsCount;
  final int cyclesObservedCount;
  final double consistencyScore;
  final PatternConfidence confidence;
  final List<String> confoundersConsidered; // z. B. "AcuteLoad < 1.3", "Schlaf kontrolliert"
  final List<String> evidenceIds;
  final DateTime firstObserved;
  final DateTime lastObserved;
  final String modelVersion;

  Map<String, dynamic> toJson() => {
    'id': id,
    'outcome': outcome.name,
    'contextDescription': contextDescription,
    'symptomOrPhaseTrigger': symptomOrPhaseTrigger,
    'magnitudeDescriptor': magnitudeDescriptor,
    'observationsCount': observationsCount,
    'cyclesObservedCount': cyclesObservedCount,
    'consistencyScore': consistencyScore,
    'confidence': confidence.name,
    'confoundersConsidered': confoundersConsidered,
    'evidenceIds': evidenceIds,
    'firstObserved': firstObserved.toIso8601String().split('T').first,
    'lastObserved': lastObserved.toIso8601String().split('T').first,
    'modelVersion': modelVersion,
  };

  factory PersonalCyclePattern.fromJson(Map<String, dynamic> json) => PersonalCyclePattern(
    id: json['id'] as String,
    outcome: PatternOutcome.values.byName(json['outcome'] as String),
    contextDescription: json['contextDescription'] as String,
    symptomOrPhaseTrigger: json['symptomOrPhaseTrigger'] as String,
    magnitudeDescriptor: json['magnitudeDescriptor'] as String,
    observationsCount: json['observationsCount'] as int,
    cyclesObservedCount: json['cyclesObservedCount'] as int,
    consistencyScore: (json['consistencyScore'] as num).toDouble(),
    confidence: PatternConfidence.values.byName(json['confidence'] as String),
    confoundersConsidered: (json['confoundersConsidered'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
    evidenceIds: (json['evidenceIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    firstObserved: DateTime.parse(json['firstObserved'] as String),
    lastObserved: DateTime.parse(json['lastObserved'] as String),
    modelVersion: json['modelVersion'] as String? ?? 'v1.0.0',
  );
}

/// EBENE B: Gesamtheit der longitudinalen individuellen Evidenz.
class CycleResponseEvidence {
  const CycleResponseEvidence({
    this.patterns = const [],
    this.comparedSessionsCount = 0,
    this.insufficientHistory = true,
    this.dataLimitations = const [],
  });

  final List<PersonalCyclePattern> patterns;
  final int comparedSessionsCount;
  final bool insufficientHistory;
  final List<String> dataLimitations;

  bool get hasActionablePatterns =>
      patterns.any((p) => p.confidence.isActionable);

  Map<String, dynamic> toJson() => {
    'patterns': [for (final p in patterns) p.toJson()],
    'comparedSessionsCount': comparedSessionsCount,
    'insufficientHistory': insufficientHistory,
    'dataLimitations': dataLimitations,
  };

  factory CycleResponseEvidence.fromJson(Map<String, dynamic> json) => CycleResponseEvidence(
    patterns: (json['patterns'] as List<dynamic>?)
            ?.map((e) => PersonalCyclePattern.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
    comparedSessionsCount: json['comparedSessionsCount'] as int? ?? 0,
    insufficientHistory: json['insufficientHistory'] as bool? ?? true,
    dataLimitations: (json['dataLimitations'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
  );
}

/// Relevante Typen von Gesundheitssignalen.
enum HealthSignalType {
  prolongedAbsence('Längeres Ausbleiben der Menstruation / sekundäre Amenorrhoe'),
  markedIrregularity('Ausgeprägte Zyklusunregelmäßigkeit / Variabilität'),
  heavyBleeding('Ungewöhnlich starke oder belastende Blutungen'),
  severePainOrSymptoms('Starke, den Alltag beeinträchtigende Schmerzen / Dysmenorrhoe'),
  lowEnergyAvailabilitySuspected('Mögliche unzureichende Energieverfügbarkeit (LEA / RED-S Verdachtsmuster)'),
  ironMarkersInvestigationSuggested('Empfehlung zur labordiagnostischen Abklärung des Eisenstatus');

  const HealthSignalType(this.label);
  final String label;
}

/// Spezifisches Signal zur weiblichen Gesundheit (Health Signal != Training Need).
class FemaleAthleteHealthSignal {
  const FemaleAthleteHealthSignal({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.medicalDisclaimer,
    required this.detectedAt,
    this.recommendationAction = 'Ärztliche bzw. gynäkologische Abklärung empfohlen',
  });

  final String id;
  final HealthSignalType type;
  final String title;
  final String description;
  final String medicalDisclaimer;
  final DateTime detectedAt;
  final String recommendationAction;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'description': description,
    'medicalDisclaimer': medicalDisclaimer,
    'detectedAt': detectedAt.toIso8601String().split('T').first,
    'recommendationAction': recommendationAction,
  };

  factory FemaleAthleteHealthSignal.fromJson(Map<String, dynamic> json) => FemaleAthleteHealthSignal(
    id: json['id'] as String,
    type: HealthSignalType.values.byName(json['type'] as String),
    title: json['title'] as String,
    description: json['description'] as String,
    medicalDisclaimer: json['medicalDisclaimer'] as String,
    detectedAt: DateTime.parse(json['detectedAt'] as String),
    recommendationAction: json['recommendationAction'] as String? ??
        'Ärztliche bzw. gynäkologische Abklärung empfohlen',
  );
}

/// Labor-Eisendaten (nur wenn echt gemessen!).
class IronLabRecord {
  const IronLabRecord({
    required this.id,
    required this.measuredAt,
    this.ferritinUgL,
    this.hemoglobinGDl,
    this.transferrinSaturationPercent,
    this.referenceRange,
    this.source = 'Labordiagnostik',
    this.confidence = 1.0,
  });

  final String id;
  final DateTime measuredAt;
  final double? ferritinUgL;
  final double? hemoglobinGDl;
  final double? transferrinSaturationPercent;
  final String? referenceRange;
  final String source;
  final double confidence;

  Map<String, dynamic> toJson() => {
    'id': id,
    'measuredAt': measuredAt.toIso8601String().split('T').first,
    if (ferritinUgL != null) 'ferritinUgL': ferritinUgL,
    if (hemoglobinGDl != null) 'hemoglobinGDl': hemoglobinGDl,
    if (transferrinSaturationPercent != null)
      'transferrinSaturationPercent': transferrinSaturationPercent,
    if (referenceRange != null) 'referenceRange': referenceRange,
    'source': source,
    'confidence': confidence,
  };

  factory IronLabRecord.fromJson(Map<String, dynamic> json) => IronLabRecord(
    id: json['id'] as String,
    measuredAt: DateTime.parse(json['measuredAt'] as String),
    ferritinUgL: (json['ferritinUgL'] as num?)?.toDouble(),
    hemoglobinGDl: (json['hemoglobinGDl'] as num?)?.toDouble(),
    transferrinSaturationPercent: (json['transferrinSaturationPercent'] as num?)?.toDouble(),
    referenceRange: json['referenceRange'] as String?,
    source: json['source'] as String? ?? 'Labordiagnostik',
    confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
  );
}

/// EBENE C: Relevanter gesundheitlicher Kontext für die Athletin.
class FemaleAthleteHealthContext {
  const FemaleAthleteHealthContext({
    this.activeSignals = const [],
    this.ironRecords = const [],
    this.energyAvailabilityNotes,
    this.asOf,
  });

  final List<FemaleAthleteHealthSignal> activeSignals;
  final List<IronLabRecord> ironRecords;
  final String? energyAvailabilityNotes;
  final DateTime? asOf;

  bool get hasActiveHealthSignals => activeSignals.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'activeSignals': [for (final s in activeSignals) s.toJson()],
    'ironRecords': [for (final r in ironRecords) r.toJson()],
    if (energyAvailabilityNotes != null) 'energyAvailabilityNotes': energyAvailabilityNotes,
    if (asOf != null) 'asOf': asOf!.toIso8601String(),
  };

  factory FemaleAthleteHealthContext.fromJson(Map<String, dynamic> json) =>
      FemaleAthleteHealthContext(
        activeSignals: (json['activeSignals'] as List<dynamic>?)
                ?.map((e) => FemaleAthleteHealthSignal.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        ironRecords: (json['ironRecords'] as List<dynamic>?)
                ?.map((e) => IronLabRecord.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        energyAvailabilityNotes: json['energyAvailabilityNotes'] as String?,
        asOf: json['asOf'] != null ? DateTime.parse(json['asOf'] as String) : null,
      );
}

/// Gesamter weiblicher Athletenkontext zur Weitergabe an den Coach.
class FemaleAthleteContext {
  const FemaleAthleteContext({
    required this.cycleContext,
    required this.evidence,
    required this.healthContext,
    this.todaysSymptoms,
  });

  final CycleContext cycleContext;
  final CycleResponseEvidence evidence;
  final FemaleAthleteHealthContext healthContext;
  final DailyCycleSymptomReport? todaysSymptoms;

  bool get isTrackingActive => cycleContext.isTrackingActive;

  Map<String, dynamic> toJson() => {
    'cycleContext': cycleContext.toJson(),
    'evidence': evidence.toJson(),
    'healthContext': healthContext.toJson(),
    if (todaysSymptoms != null) 'todaysSymptoms': todaysSymptoms!.toJson(),
  };

  factory FemaleAthleteContext.fromJson(Map<String, dynamic> json) => FemaleAthleteContext(
    cycleContext: CycleContext.fromJson(json['cycleContext'] as Map<String, dynamic>),
    evidence: CycleResponseEvidence.fromJson(json['evidence'] as Map<String, dynamic>),
    healthContext: FemaleAthleteHealthContext.fromJson(json['healthContext'] as Map<String, dynamic>),
    todaysSymptoms: json['todaysSymptoms'] != null
        ? DailyCycleSymptomReport.fromJson(json['todaysSymptoms'] as Map<String, dynamic>)
        : null,
  );
}
