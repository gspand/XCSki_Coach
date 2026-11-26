/// XC-spezifische Trainingsreize und Stimulus Ledger für GIULIA.
///
/// Trennt die physiologische und neuromuskuläre Trainingswirkung (Stimulus)
/// strikt von der Belastungsmenge (Load). Eine 3-stündige Skating-Einheit
/// und eine 45-minütige Ercolina-VO2max-Einheit können ähnliche Belastungswerte
/// erzeugen, setzen aber völlig andere Anpassungsreize.
library;

import '../../domain/xc_modality.dart';

/// Die sportwissenschaftliche Taxonomie für Skilanglauf-Trainingsreize.
enum StimulusType {
  recovery('recovery', 'Aktive Erholung / Regeneration'),
  aerobicBase('aerobic_base', 'Grundlagenausdauer (Fettstoffwechsel / Kapillarisierung)'),
  longEndurance('long_endurance', 'Langer Skiumfang / Spezifische Dauerbelastung'),
  threshold('threshold', 'Schwellenausdauer / Laktat-Gleichgewicht (LTP2)'),
  vo2max('vo2max', 'Maximale Sauerstoffaufnahme (HIT / Polarisiert)'),
  speedNeuromuscular('speed_neuromuscular', 'Neuromuskulärer Antritt / Schnelligkeit'),
  maxStrength('max_strength', 'Maximalkraft'),
  explosiveStrength('explosive_strength', 'Schnellkraft / Reaktivkraft'),
  muscularEndurance('muscular_endurance', 'Kraftausdauer'),
  doublePolingPower('double_poling_power', 'Doppelstock-Spitzenkraft & Schnellkraft'),
  doublePolingEndurance('double_poling_endurance', 'Doppelstock-Kraftausdauer'),
  technique('technique', 'Technikschulung / Ökonomisierung'),
  fatigueResistance('fatigue_resistance', 'Ermüdungswiderstand über lange Belastungsdauer'),
  raceSpecific('race_specific', 'Wettkampfspezifische Belastung / Taktik');

  const StimulusType(this.key, this.label);
  final String key;
  final String label;
}

/// Herkunft und Verifikationsstatus eines Trainingsreizes.
enum StimulusOrigin {
  /// Geplanter Reiz der Einheit (aus Workout Prescription / Vorlage).
  planned('planned', 'Geplanter Soll-Reiz'),

  /// Beobachteter Reiz nach Durchführung anhand tatsächlicher Messdaten.
  observed('observed', 'Beobachteter Ist-Reiz'),

  /// Geplanter Reiz, der durch physiologische Ist-Daten verifiziert wurde.
  verified('verified', 'Verifizierter Soll/Ist-Reiz');

  const StimulusOrigin(this.key, this.label);
  final String key;
  final String label;
}

/// Ein einzelner nachgewiesener oder geplanter Trainingsreiz einer Einheit.
class TrainingStimulus {
  const TrainingStimulus({
    required this.type,
    required this.modality,
    this.technique = XcTechnique.unknown,
    required this.evidence,
    required this.confidence,
    this.primaryEnergySystem,
    this.origin = StimulusOrigin.observed,
    this.plannedType,
    this.complianceRate,
  });

  final StimulusType type;
  final XcModality modality;
  final XcTechnique technique;

  /// Wissenschaftlich und datenbasiert begründete Evidenz (z. B. «Dauer 160 min im Grundbereich», «Ercolina 4x4min bei 115% CP»).
  final String evidence;

  /// Konfidenz dieses Reizes (0.0 bis 1.0).
  final double confidence;

  /// Primär beanspruchtes Energiesystem (z. B. 'aerobic_lipolytic', 'aerobic_glycolytic', 'anaerobic_lactic', 'atp_pc').
  final String? primaryEnergySystem;

  /// Herkunft des Reizes (geplant, beobachtet oder verifiziert).
  final StimulusOrigin origin;

  /// Ursprünglich geplanter Reiztyp (bei Soll/Ist-Abgleich).
  final StimulusType? plannedType;

  /// Grad der Erfüllung des geplanten Reizes (0.0 bis 1.0).
  final double? complianceRate;

  bool get isObserved =>
      origin == StimulusOrigin.observed || origin == StimulusOrigin.verified;
  bool get isPlanned =>
      origin == StimulusOrigin.planned || origin == StimulusOrigin.verified;

  Map<String, dynamic> toJson() => {
    'type': type.key,
    'modality': modality.key,
    'technique': technique.key,
    'evidence': evidence,
    'confidence': confidence,
    if (primaryEnergySystem != null) 'primaryEnergySystem': primaryEnergySystem,
    'origin': origin.key,
    if (plannedType != null) 'plannedType': plannedType!.key,
    if (complianceRate != null) 'complianceRate': complianceRate,
  };

  factory TrainingStimulus.fromJson(Map<String, dynamic> json) =>
      TrainingStimulus(
        type: StimulusType.values.firstWhere(
          (t) => t.key == json['type'],
          orElse: () => StimulusType.aerobicBase,
        ),
        modality: XcModality.values.firstWhere(
          (m) => m.key == json['modality'],
          orElse: () => XcModality.unknown,
        ),
        technique: XcTechnique.values.firstWhere(
          (t) => t.key == json['technique'],
          orElse: () => XcTechnique.unknown,
        ),
        evidence: (json['evidence'] ?? '').toString(),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.8,
        primaryEnergySystem: json['primaryEnergySystem']?.toString(),
        origin: StimulusOrigin.values.firstWhere(
          (o) => o.key == json['origin'],
          orElse: () => StimulusOrigin.observed,
        ),
        plannedType: json['plannedType'] != null
            ? StimulusType.values.firstWhere(
                (t) => t.key == json['plannedType'],
                orElse: () => StimulusType.aerobicBase,
              )
            : null,
        complianceRate: (json['complianceRate'] as num?)?.toDouble(),
      );
}

/// Verzeichnis aller in einer Trainingseinheit gesetzten oder geplanten Reize.
class StimulusLedger {
  const StimulusLedger({
    required this.sessionId,
    required this.athleteId,
    required this.startedAtUtcUs,
    required this.stimuli,
  });

  final String sessionId;
  final String athleteId;
  final int startedAtUtcUs;
  final List<TrainingStimulus> stimuli;

  List<TrainingStimulus> get observedStimuli =>
      stimuli.where((s) => s.isObserved).toList(growable: false);

  List<TrainingStimulus> get plannedStimuli =>
      stimuli.where((s) => s.isPlanned).toList(growable: false);

  bool hasStimulus(StimulusType type) => stimuli.any((s) => s.type == type);

  bool hasObservedStimulus(StimulusType type) =>
      stimuli.any((s) => s.type == type && s.isObserved);

  bool hasPlannedStimulus(StimulusType type) =>
      stimuli.any((s) => s.type == type && s.isPlanned);

  List<TrainingStimulus> stimuliOfType(StimulusType type) =>
      stimuli.where((s) => s.type == type).toList(growable: false);

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'athleteId': athleteId,
    'startedAtUtcUs': startedAtUtcUs,
    'stimuli': stimuli.map((s) => s.toJson()).toList(),
  };

  factory StimulusLedger.fromJson(Map<String, dynamic> json) => StimulusLedger(
    sessionId: (json['sessionId'] ?? '').toString(),
    athleteId: (json['athleteId'] ?? '').toString(),
    startedAtUtcUs: (json['startedAtUtcUs'] as num?)?.toInt() ?? 0,
    stimuli: (json['stimuli'] as List<dynamic>?)
            ?.map((e) => TrainingStimulus.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
  );
}
