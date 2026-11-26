/// Kandidatenmodelle für die Workout-Auswahl und Nachvollziehbarkeit abgelehnter Alternativen.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Kein "Black Box"-Algorithmus.
/// - Jede abgelehnte Alternative behält ihren Ablehnungsgrund und die Stufe
///   (Sicherheitsfilter, Machbarkeitsfilter, Erholungskontext, Look-Ahead).
/// - So kann der Coach dem Athleten transparent erklären:
///   «Wir haben Ercolina VO2max erwogen, aber wegen deiner Trizepsbeschwerden verworfen.»
library;

import '../../domain/xc_modality.dart';
import '../load/stimulus_models.dart';
import 'workout_prescription.dart';

/// Herkunft des Trainingskandidaten.
enum CandidateOrigin {
  catalogueTemplate('Bestehender Katalog-Baustein'),
  blueprint('Trainingsbibliothek-Blueprint'),
  workoutFamily('Parametrisierte Trainingsfamilie'),
  recoverySystem('Regenerationsprotokoll');

  const CandidateOrigin(this.label);
  final String label;
}

/// Stufe, in der ein Kandidat verworfen wurde.
enum RejectionStage {
  safetyFilter('Sicherheits- & Gesundheitsschutz'),
  exposureTolerance('Modalitätsspezifische Belastungstoleranz'),
  feasibilityFilter('Zeitbudget & Equipment-Verfügbarkeit'),
  recoveryContext('Erholungs- & Reizabstandslogik'),
  lookAheadDeferred('Vorausschauende Verschiebung (Look-Ahead)'),
  lowerNeedPriority('Geringere Passung zu aktuellen Bedarfen');

  const RejectionStage(this.label);
  final String label;
}

/// Dokumentation einer verworfenen Trainingsalternative für die Hoje-Karte / Erklärung.
class RejectedAlternative {
  const RejectedAlternative({
    required this.workoutTitle,
    required this.modality,
    required this.intendedStimulus,
    required this.rejectionStage,
    required this.reason,
    this.originalScore,
  });

  final String workoutTitle;
  final XcModality modality;
  final StimulusType intendedStimulus;
  final RejectionStage rejectionStage;
  final String reason;
  final double? originalScore;

  factory RejectedAlternative.fromJson(Map<String, dynamic> j) =>
      RejectedAlternative(
        workoutTitle: j['workoutTitle'] as String,
        modality: XcModality.values.byName(j['modality'] as String),
        intendedStimulus: StimulusType.values.byName(
          j['intendedStimulus'] as String,
        ),
        rejectionStage: RejectionStage.values.byName(
          j['rejectionStage'] as String,
        ),
        reason: j['reason'] as String,
        originalScore: (j['originalScore'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
    'workoutTitle': workoutTitle,
    'modality': modality.name,
    'intendedStimulus': intendedStimulus.name,
    'rejectionStage': rejectionStage.name,
    'reason': reason,
    'originalScore': originalScore,
  };
}

/// Ein evaluierter Trainingskandidat während des Auswahlprozesses.
class WorkoutCandidate {
  WorkoutCandidate({
    required this.prescription,
    required this.origin,
    this.score = 0.0,
    List<String>? matchReasons,
    this.isRejected = false,
    this.rejectionReason,
    this.rejectionStage,
  }) : matchReasons = matchReasons ?? [];

  final WorkoutPrescription prescription;
  final CandidateOrigin origin;
  double score;
  final List<String> matchReasons;
  bool isRejected;
  String? rejectionReason;
  RejectionStage? rejectionStage;

  void reject({required RejectionStage stage, required String reason}) {
    isRejected = true;
    rejectionStage = stage;
    rejectionReason = reason;
  }

  RejectedAlternative toRejectedAlternative() {
    return RejectedAlternative(
      workoutTitle: prescription.title,
      modality: prescription.modality,
      intendedStimulus: prescription.intendedStimuli.isNotEmpty
          ? prescription.intendedStimuli.first
          : StimulusType.aerobicBase,
      rejectionStage: rejectionStage ?? RejectionStage.lowerNeedPriority,
      reason: rejectionReason ?? 'Geringere Passung als die gewählte Einheit.',
      originalScore: score,
    );
  }
}
