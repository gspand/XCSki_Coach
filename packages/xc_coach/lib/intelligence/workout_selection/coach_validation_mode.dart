/// Audit- und Validierungsdatensatz für den Coach (Coach Validation Mode).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE & ARCHITEKTONISCHE LEITPLANKEN:
/// - Baseline-Version: «GIULIA XC Coach Core – Validation Baseline v1»
/// - Struktur jeder Realeinheit:
///   1. BEFORE: Snapshot von State, DataCoverage, Goal, Needs, Subjective Evidence, Availability, Safety, RecentStimuli
///   2. DECISION: Selected Workout, intended Stimuli, Prescription, Intensity Guidance, Reasons, rejected Alternatives, Confidence, Data Limitations
///   3. ATHLETE ACTION: accepted / modified / choseAlternative / skipped (+ optionaler Grund)
///   4. OBSERVATION: Ausschließlich echte Beobachtungsdaten (Ercolina/Garmin/Strava, HR, Power, Intervalle, RPE, Laktat falls vorhanden)
///      -> Niemals Prescription-Werte als Messwerte übernehmen!
///      -> Erhalt von Raw Data (Stroke-Level, Sensorqualität, Streams, Metadaten)
///   5. AFTER: Execution Evaluation, observed Stimuli, Load, neuer AthleteState, veränderte TrainingNeeds
///   6. NEXT DECISION: Konsequenz für Folgetag und treibende Evidenz
/// - VERSIONIERUNG: Eindeutige Kennung aller Sub-Modelle für Regressions- und Schattenprüfungen.
/// - SHADOW REPLAY: Historische Datensätze können durch zukünftige Coach-Versionen erneut berechnet
///   werden, um Entscheidungsunterschiede deterministisch zu vergleichen.
library;

import '../../domain/xc_modality.dart';
import '../load/stimulus_models.dart';
import '../training_need/need_types.dart';
import '../training_need/training_need_result.dart';
import '../xc_athlete_state/xc_athlete_state.dart';
import 'availability_context.dart';
import 'daily_coaching_decision.dart';
import 'daily_decision_engine.dart';
import 'user_override_context.dart';
import 'workout_execution_evaluation.dart';

/// Feste Versionierung des Cores für deterministische Audits und Vergleiche.
class CoachCoreVersions {
  const CoachCoreVersions({
    this.coachCoreVersion = baselineCoreVersion,
    this.loadModelVersion = 'v1.0.0',
    this.stimulusModelVersion = 'v1.0.0',
    this.athleteStateModelVersion = 'v1.0.0',
    this.needEngineVersion = 'v1.0.0',
    this.workoutSelectionVersion = 'v1.0.0',
  });

  static const baselineCoreVersion = 'GIULIA XC Coach Core – Validation Baseline v1';
  static const currentCoreVersion = baselineCoreVersion;
  static const currentLoadModelVersion = 'v1.0.0';
  static const currentStimulusModelVersion = 'v1.0.0';
  static const currentAthleteStateModelVersion = 'v1.0.0';
  static const currentNeedEngineVersion = 'v1.0.0';
  static const currentWorkoutSelectionVersion = 'v1.0.0';

  final String coachCoreVersion;
  final String loadModelVersion;
  final String stimulusModelVersion;
  final String athleteStateModelVersion;
  final String needEngineVersion;
  final String workoutSelectionVersion;

  Map<String, String> toMap() => {
    'coachCoreVersion': coachCoreVersion,
    'loadModelVersion': loadModelVersion,
    'stimulusModelVersion': stimulusModelVersion,
    'athleteStateModelVersion': athleteStateModelVersion,
    'needEngineVersion': needEngineVersion,
    'workoutSelectionVersion': workoutSelectionVersion,
  };

  static Map<String, String> asMap() => const CoachCoreVersions().toMap();

  factory CoachCoreVersions.fromMap(Map<String, dynamic> map) => CoachCoreVersions(
    coachCoreVersion: map['coachCoreVersion']?.toString() ?? baselineCoreVersion,
    loadModelVersion: map['loadModelVersion']?.toString() ?? 'v1.0.0',
    stimulusModelVersion: map['stimulusModelVersion']?.toString() ?? 'v1.0.0',
    athleteStateModelVersion: map['athleteStateModelVersion']?.toString() ?? 'v1.0.0',
    needEngineVersion: map['needEngineVersion']?.toString() ?? 'v1.0.0',
    workoutSelectionVersion: map['workoutSelectionVersion']?.toString() ?? 'v1.0.0',
  );
}

/// Reaktion des Athleten auf die vorgeschriebene Trainingsempfehlung.
enum AthleteActionType {
  accepted('Akzeptiert wie vorgeschrieben'),
  modified('Selbstregulierend modifiziert / verkürzt'),
  choseAlternative('Alternative Einheit gewählt'),
  skipped('Ausgelassen / Ruhetag eingelegt');

  const AthleteActionType(this.label);
  final String label;
}

class AthleteActionRecord {
  const AthleteActionRecord({
    required this.actionType,
    this.reason,
    this.timestamp,
  });

  final AthleteActionType actionType;
  final String? reason;
  final DateTime? timestamp;

  Map<String, dynamic> toJson() => {
    'actionType': actionType.name,
    'reason': reason,
    'timestamp': timestamp?.toIso8601String(),
  };
}

/// Tatsächlich beobachtete Daten einer durchgeführten Trainingseinheit.
///
/// WICHTIG: Enthält NIEMALS kopierte Prescription-Werte, sondern ausschließlich
/// reale Sensorsignale und Beobachtungen!
class ObservedSessionData {
  const ObservedSessionData({
    required this.sessionId,
    required this.source,
    required this.modality,
    required this.durationSeconds,
    this.movingTimeSeconds,
    this.distanceMetres,
    this.elevationGainMetres,
    this.averageHeartRateBpm,
    this.peakHeartRateBpm,
    this.timeInHrZonesSeconds = const {},
    this.averagePowerWatt,
    this.workJoule,
    this.strokeRate,
    this.strokeCount,
    this.leftRightSymmetryPercent,
    this.observedRpe,
    this.observedLactateMmolL,
    this.athleteFeedback,
    this.rawSensorQuality,
    this.calibrationState,
    this.rawStrokeDataRef,
    this.rawStreamDataRef,
    this.rawMetadata = const {},
  });

  final String sessionId;
  final String source;
  final XcModality modality;
  final int durationSeconds;
  final int? movingTimeSeconds;
  final double? distanceMetres;
  final double? elevationGainMetres;

  final double? averageHeartRateBpm;
  final int? peakHeartRateBpm;
  final Map<String, int> timeInHrZonesSeconds;

  final double? averagePowerWatt;
  final double? workJoule;
  final double? strokeRate;
  final int? strokeCount;
  final double? leftRightSymmetryPercent;

  final double? observedRpe;
  final double? observedLactateMmolL;
  final String? athleteFeedback;

  /// Erhalt der Sensor- und Kalibrierungsqualitäten (insb. Ercolina)
  final double? rawSensorQuality;
  final String? calibrationState;
  final String? rawStrokeDataRef;
  final String? rawStreamDataRef;
  final Map<String, dynamic> rawMetadata;

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'source': source,
    'modality': modality.name,
    'durationSeconds': durationSeconds,
    'movingTimeSeconds': movingTimeSeconds,
    'distanceMetres': distanceMetres,
    'elevationGainMetres': elevationGainMetres,
    'averageHeartRateBpm': averageHeartRateBpm,
    'peakHeartRateBpm': peakHeartRateBpm,
    'timeInHrZonesSeconds': timeInHrZonesSeconds,
    'averagePowerWatt': averagePowerWatt,
    'workJoule': workJoule,
    'strokeRate': strokeRate,
    'strokeCount': strokeCount,
    'leftRightSymmetryPercent': leftRightSymmetryPercent,
    'observedRpe': observedRpe,
    'observedLactateMmolL': observedLactateMmolL,
    'athleteFeedback': athleteFeedback,
    'rawSensorQuality': rawSensorQuality,
    'calibrationState': calibrationState,
    'rawStrokeDataRef': rawStrokeDataRef,
    'rawStreamDataRef': rawStreamDataRef,
    'rawMetadata': rawMetadata,
  };
}

/// Strukturierter Audit- und Validierungsdatensatz für reale Trainingseinheiten.
class CoachValidationRecord {
  const CoachValidationRecord({
    required this.scenarioId,
    required this.timestamp,
    this.versions = const CoachCoreVersions(),
    required this.inputSnapshot,
    required this.decision,
    this.athleteAction,
    this.observedSession,
    this.executionEvaluation,
    required this.nextDayImplication,
    this.afterSnapshot = const {},
  });

  /// Eindeutige Kennung (z. B. "session_2026_10_04_engadin" oder "golden_01_fresh_weekend").
  final String scenarioId;

  /// Alias für scenarioId
  String get id => scenarioId;

  /// Zeitstempel der Generierung.
  final DateTime timestamp;

  /// Sub-Modell-Versionen (für deterministische Vergleiche und Regressionstests).
  final CoachCoreVersions versions;

  /// 1. BEFORE: Vollständiger Eingangs-Snapshot (State, Needs, Availability, Overrides).
  final Map<String, dynamic> inputSnapshot;

  /// 2. DECISION: Tägliche Coaching-Entscheidung samt Gründen, Alternativen & Zielen.
  final DailyCoachingDecision decision;

  /// 3. ATHLETE ACTION: Akzeptiert, modifiziert, Alternative gewählt oder ausgelassen.
  final AthleteActionRecord? athleteAction;

  /// 4. OBSERVATION: Reale Beobachtungsdaten (nie Prescription-Werte!).
  final ObservedSessionData? observedSession;

  /// 5. AFTER: Mehrdimensionale Evaluation und Feedback zur Ausführung.
  final WorkoutExecutionEvaluation? executionEvaluation;

  /// Snapshot von verändertem State und TrainingNeeds nach Belastung.
  final Map<String, dynamic> afterSnapshot;

  /// 6. NEXT DECISION: Auswirkung auf den Folgetag und treibende Evidenz.
  final String nextDayImplication;

  /// Prüft, ob ein Reiz heute strikt verboten war und nicht verschrieben wurde.
  bool verifyProhibitedStimulus(StimulusType prohibited) {
    if (decision.prescribedWorkout == null) return true;
    return !decision.prescribedWorkout!.intendedStimuli.contains(prohibited);
  }

  /// Prüft, ob ein intendierter Reiz tatsächlich enthalten ist.
  bool verifyRequiredStimulus(StimulusType requiredStimulus) {
    if (decision.prescribedWorkout == null) return false;
    return decision.prescribedWorkout!.intendedStimuli.contains(requiredStimulus);
  }

  /// Prüft, ob die Modalität übereinstimmt.
  bool verifyModality(XcModality expectedModality) {
    if (decision.prescribedWorkout == null) return false;
    return decision.prescribedWorkout!.modality == expectedModality;
  }

  Map<String, dynamic> toJson() => {
    'id': scenarioId,
    'scenarioId': scenarioId,
    'timestamp': timestamp.toIso8601String(),
    'versions': versions.toMap(),
    'before': inputSnapshot,
    'decision': decision.toJson(),
    'athleteAction': athleteAction?.toJson(),
    'observation': observedSession?.toJson(),
    'after': {
      'executionEvaluation': executionEvaluation?.toJson(),
      ...afterSnapshot,
    },
    'nextDecision': {
      'nextDayImplication': nextDayImplication,
    },
  };

  factory CoachValidationRecord.fromJson(Map<String, dynamic> json) =>
      CoachValidationRecord(
        scenarioId: json['scenarioId']?.toString() ?? json['id']?.toString() ?? '',
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'].toString())
            : DateTime.now(),
        versions: json['versions'] is Map<String, dynamic>
            ? CoachCoreVersions.fromMap(json['versions'] as Map<String, dynamic>)
            : const CoachCoreVersions(),
        inputSnapshot: json['before'] as Map<String, dynamic>? ?? const {},
        decision: json['decision'] is Map<String, dynamic>
            ? DailyCoachingDecision.fromJson(json['decision'] as Map<String, dynamic>)
            : DailyCoachingDecision(
                decisionDate: DateTime.now(),
                athleteId: '',
                actionType: CoachingActionType.restDay,
                coachingReason: '',
                confidence: NeedConfidence.high,
              ),
        nextDayImplication: (json['nextDecision'] as Map<String, dynamic>?)?['nextDayImplication']?.toString() ?? '',
        afterSnapshot: json['after'] as Map<String, dynamic>? ?? const {},
      );
}

/// Schatten-Ausführung (Shadow Replay) für Modellvergleiche zwischen Versionen.
class ShadowReplayRunner {
  const ShadowReplayRunner();

  /// Führt die historischen Eingangsdaten eines Records durch eine gegebene Engine aus
  /// und vergleicht das Ergebnis mit der historischen Baseline-Entscheidung.
  ShadowReplayDiff replay({
    required CoachValidationRecord baselineRecord,
    required DailyDecisionEngine candidateEngine,
    XCAthleteState? state,
    TrainingNeedResult? needResult,
    DayAvailability? availability,
    DayLookAheadContext? lookAhead,
    UserOverrideContext? userOverride,
    CoachCoreVersions? candidateVersions,
  }) {
    final effectiveState = state ??
        XCAthleteState(
          athleteId: 'replay_athlete',
          asOf: baselineRecord.timestamp,
        );
    final effectiveNeeds = needResult ??
        TrainingNeedResult(
          asOf: baselineRecord.timestamp,
          athleteId: 'replay_athlete',
        );
    final effectiveAvailability = availability ??
        DayAvailability(
          date: baselineRecord.timestamp,
          availableMinutes: (baselineRecord.inputSnapshot['availableMinutes'] as num?)?.toInt() ?? 120,
          hasSnow: baselineRecord.inputSnapshot['hasSnow'] == true,
          hasErcolina: baselineRecord.inputSnapshot['hasErcolina'] == true,
        );

    final replayedDecision = candidateEngine.decide(
      state: effectiveState,
      needResult: effectiveNeeds,
      availability: effectiveAvailability,
      lookAhead: lookAhead,
      userOverride: userOverride,
    );

    final baseline = baselineRecord.decision;
    final actionMatches = baseline.actionType == replayedDecision.actionType;
    final workoutMatches = baseline.prescribedWorkout?.id == replayedDecision.prescribedWorkout?.id;
    final confidenceMatches = baseline.confidence == replayedDecision.confidence;
    final safetyMatches = baseline.safetyConstraintsApplied.length == replayedDecision.safetyConstraintsApplied.length;

    return ShadowReplayDiff(
      scenarioId: baselineRecord.scenarioId,
      baselineVersion: baselineRecord.versions.coachCoreVersion,
      candidateVersions: candidateVersions ?? const CoachCoreVersions(),
      baselineDecision: baseline,
      replayedDecision: replayedDecision,
      actionMatches: actionMatches,
      workoutMatches: workoutMatches,
      confidenceMatches: confidenceMatches,
      safetyMatches: safetyMatches,
    );
  }
}

/// Ergebnis des Schattenvergleichs zwischen zwei Modell-Versionen.
class ShadowReplayDiff {
  const ShadowReplayDiff({
    required this.scenarioId,
    required this.baselineVersion,
    required this.candidateVersions,
    required this.baselineDecision,
    required this.replayedDecision,
    required this.actionMatches,
    required this.workoutMatches,
    required this.confidenceMatches,
    required this.safetyMatches,
  });

  final String scenarioId;
  final String baselineVersion;
  final CoachCoreVersions candidateVersions;
  final DailyCoachingDecision baselineDecision;
  final DailyCoachingDecision replayedDecision;

  final bool actionMatches;
  final bool workoutMatches;
  final bool confidenceMatches;
  final bool safetyMatches;

  bool get hasDivergence => !actionMatches || !workoutMatches || !confidenceMatches || !safetyMatches;

  Map<String, dynamic> toJson() => {
    'scenarioId': scenarioId,
    'baselineVersion': baselineVersion,
    'candidateVersion': candidateVersions.coachCoreVersion,
    'actionMatches': actionMatches,
    'workoutMatches': workoutMatches,
    'confidenceMatches': confidenceMatches,
    'safetyMatches': safetyMatches,
    'hasDivergence': hasDivergence,
    'baselineWorkout': baselineDecision.prescribedWorkout?.title,
    'replayedWorkout': replayedDecision.prescribedWorkout?.title,
  };
}
