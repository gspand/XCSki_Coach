/// Konkrete Trainingsverschreibung (Workout Prescription) des Coaches.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Keine Pseudo-Präzision bei Erholungszeiten (keine starren «24 h Erholung empfohlen»).
/// - Modellierung des Erholungsbedarfs über qualitative Stufen und betroffene Körpersysteme:
///   systemisch (kardiovaskulär/vegetativ), Oberkörper, Unterkörper, neuromuskulär.
/// - Trennt Aufwärmen, Belastungsblöcke und Abwärmen.
/// - Verbindet das Training eindeutig mit dem primären Reiz und dem adressierten Bedarf.
library;

import '../../domain/xc_modality.dart';
import '../load/stimulus_models.dart';
import '../training_need/need_types.dart';
import 'intensity_prescription.dart';

/// Beanspruchtes physiologisches oder muskuläres System.
enum TrainedSystem {
  systemic('Systemisch (kardiovaskulär & vegetativ)'),
  upperBody('Oberkörper & Schultergürtel (Doppelstockkette)'),
  lowerBody('Unterkörper (Bein- & Gesäßmuskulatur)'),
  neuromuscular('Neuromuskulär & Schnellkraft');

  const TrainedSystem(this.label);
  final String label;
}

/// Ermüdungs- und Erholungsanforderung einer Einheit.
enum RecoveryCost {
  low('Gering (rasche Wiederherstellung)'),
  moderate('Moderat (normale Anpassungsphase)'),
  high('Hoch (ausgeprägte Ermüdung des beanspruchten Systems)'),
  extreme('Sehr hoch (erschöpfende Langzeit- oder Maximalbelastung)');

  const RecoveryCost(this.label);
  final String label;

  /// Richtwert für die Mindesterholungszeit des beanspruchten Subsystems.
  int get requiredRestHours {
    switch (this) {
      case RecoveryCost.low:
        return 12;
      case RecoveryCost.moderate:
        return 24;
      case RecoveryCost.high:
        return 48;
      case RecoveryCost.extreme:
        return 72;
    }
  }
}

/// Detaillierter Erholungsbedarf mit systemspezifischer Zuordnung.
class RecoveryDemand {
  const RecoveryDemand({
    required this.cost,
    required this.affectedSystems,
    required this.qualitativeDescription,
  });

  final RecoveryCost cost;
  final Set<TrainedSystem> affectedSystems;
  final String qualitativeDescription;

  factory RecoveryDemand.fromJson(Map<String, dynamic> j) => RecoveryDemand(
    cost: RecoveryCost.values.byName(j['cost'] as String),
    affectedSystems: (j['affectedSystems'] as List? ?? const [])
        .cast<String>()
        .map(TrainedSystem.values.byName)
        .toList()
        .toSet(),
    qualitativeDescription: j['qualitativeDescription'] as String,
  );

  Map<String, dynamic> toJson() => {
    'cost': cost.name,
    'affectedSystems': affectedSystems.map((s) => s.name).toList(),
    'qualitativeDescription': qualitativeDescription,
  };
}

/// Spezifische Trainingsfamilie (z. B. Schwellenintervalle, Grundlagenausdauer, etc.).
enum WorkoutFamilyType {
  easyBase('Lockerer Dauerlauf / Grundlagenausdauer (Z1/Z2)'),
  longEndurance('Langzeitausdauer / Long Distance (Z2)'),
  thresholdIntervals('Schwellenintervalle / EB (Z3)'),
  vo2maxIntervals('VO2max Intervalle / HIT (Z4)'),
  speedNeuromuscular('Schnelligkeit & Neuromuskuläre Ansteuerung'),
  techniqueFocus('Techniktraining & Koordination'),
  doublePolingSpecific('Spezifisches Doppelstocktraining (Ercolina)'),
  activeRecovery('Aktive Regeneration (Z1)'),
  assessmentWorkout('Diagnostik & Leistungsüberprüfung'),
  strengthCore('Kraft & Rumpfstabilität');

  const WorkoutFamilyType(this.label);
  final String label;
}

class WorkoutPrescription {
  const WorkoutPrescription({
    required this.id,
    required this.title,
    required this.modality,
    required this.family,
    required this.totalDurationMinutes,
    required this.warmupMinutes,
    required this.workMinutes,
    required this.cooldownMinutes,
    required this.structureDescription,
    required this.workIntensity,
    required this.recoveryIntensity,
    required this.intendedStimuli,
    required this.primaryNeedAddressed,
    this.secondaryStimuli = const [],
    this.recoveryCost = RecoveryCost.moderate,
    this.recoveryDemand,
    this.terrainGuidance,
    this.templateId,
    this.blueprintId,
    this.progressionVariant,
    this.regressionVariant,
    this.isAssessmentWorkout = false,
    this.notes = const [],
  });

  final String id;
  final String title;
  final XcModality modality;
  final WorkoutFamilyType family;

  final int totalDurationMinutes;
  final int warmupMinutes;
  final int workMinutes;
  final int cooldownMinutes;

  /// Genaue Intervall- oder Dauerlaufstruktur in Textform.
  final String structureDescription;

  /// Vorgabe für die Arbeitsabschnitte (Multi-Anchor).
  final IntensityPrescription workIntensity;

  /// Vorgabe für Trabpausen oder lockere Abschnitte.
  final IntensityPrescription recoveryIntensity;

  /// Primär intendierte physiologische Reize.
  final List<StimulusType> intendedStimuli;

  /// Sekundäre Reize, die als Nebeneffekt gesetzt werden.
  final List<StimulusType> secondaryStimuli;

  /// Welcher Bedarf aus dem TrainingNeedResult wird primär erfüllt?
  final TrainingNeedType primaryNeedAddressed;

  final RecoveryCost recoveryCost;

  /// Spezifischer Erholungsbedarf nach Systemen.
  final RecoveryDemand? recoveryDemand;

  /// Geländevorgabe für die Durchführung.
  final String? terrainGuidance;

  /// Verweis auf die Vorlage aus workoutCatalogue (falls vorhanden).
  final String? templateId;

  /// Verweis auf den Blueprint aus workoutLibrary (falls vorhanden).
  final String? blueprintId;

  /// Optionale leichtere Alternative (Regression).
  final String? regressionVariant;

  /// Optionale forderndere Alternative (Progression).
  final String? progressionVariant;

  /// Handelt es sich um eine Test- / Diagnostikeinheit?
  final bool isAssessmentWorkout;

  final List<String> notes;

  RecoveryDemand get effectiveRecoveryDemand {
    if (recoveryDemand != null) return recoveryDemand!;
    final systems = <TrainedSystem>{TrainedSystem.systemic};
    if (modality == XcModality.ercolinaDoublePoling) {
      systems.add(TrainedSystem.upperBody);
    } else if (modality == XcModality.skiSkating ||
        modality == XcModality.running) {
      systems.add(TrainedSystem.lowerBody);
    }
    return RecoveryDemand(
      cost: recoveryCost,
      affectedSystems: systems,
      qualitativeDescription: 'Erholungsbedarf: ${recoveryCost.label}',
    );
  }

  factory WorkoutPrescription.fromJson(Map<String, dynamic> j) =>
      WorkoutPrescription(
        id: j['id'] as String,
        title: j['title'] as String,
        structureDescription: j['structureDescription'] as String,
        terrainGuidance: j['terrainGuidance'] as String?,
        templateId: j['templateId'] as String?,
        blueprintId: j['blueprintId'] as String?,
        progressionVariant: j['progressionVariant'] as String?,
        regressionVariant: j['regressionVariant'] as String?,
        totalDurationMinutes: j['totalDurationMinutes'] as int,
        warmupMinutes: j['warmupMinutes'] as int,
        workMinutes: j['workMinutes'] as int,
        cooldownMinutes: j['cooldownMinutes'] as int,
        modality: XcModality.values.byName(j['modality'] as String),
        family: WorkoutFamilyType.values.byName(j['family'] as String),
        primaryNeedAddressed: TrainingNeedType.values.byName(
          j['primaryNeedAddressed'] as String,
        ),
        recoveryCost: RecoveryCost.values.byName(j['recoveryCost'] as String),
        workIntensity: IntensityPrescription.fromJson(
          j['workIntensity'] as Map<String, dynamic>,
        ),
        recoveryIntensity: IntensityPrescription.fromJson(
          j['recoveryIntensity'] as Map<String, dynamic>,
        ),
        intendedStimuli: (j['intendedStimuli'] as List? ?? const [])
            .cast<String>()
            .map(StimulusType.values.byName)
            .toList(),
        secondaryStimuli: (j['secondaryStimuli'] as List? ?? const [])
            .cast<String>()
            .map(StimulusType.values.byName)
            .toList(),
        notes: (j['notes'] as List? ?? const []).cast<String>(),
        isAssessmentWorkout: j['isAssessmentWorkout'] == true,
        recoveryDemand: j['recoveryDemand'] == null
            ? null
            : RecoveryDemand.fromJson(
                j['recoveryDemand'] as Map<String, dynamic>,
              ),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'modality': modality.name,
    'family': family.name,
    'totalDurationMinutes': totalDurationMinutes,
    'warmupMinutes': warmupMinutes,
    'workMinutes': workMinutes,
    'cooldownMinutes': cooldownMinutes,
    'structureDescription': structureDescription,
    'workIntensity': workIntensity.toJson(),
    'recoveryIntensity': recoveryIntensity.toJson(),
    'intendedStimuli': intendedStimuli.map((s) => s.name).toList(),
    'secondaryStimuli': secondaryStimuli.map((s) => s.name).toList(),
    'primaryNeedAddressed': primaryNeedAddressed.name,
    'recoveryCost': recoveryCost.name,
    'recoveryDemand': effectiveRecoveryDemand.toJson(),
    'terrainGuidance': terrainGuidance ?? workIntensity.terrainGuidance,
    'templateId': templateId,
    'blueprintId': blueprintId,
    'progressionVariant': progressionVariant,
    'regressionVariant': regressionVariant,
    'isAssessmentWorkout': isAssessmentWorkout,
    'notes': notes,
  };
}
