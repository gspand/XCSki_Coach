/// Mehrdimensionale Auswertungslogik für durchgeführte Trainingseinheiten.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Success != Plan Compliance:
///   Ein Athlet, der ein Intervalltraining nach 3 von 5 Wiederholungen abbricht,
///   weil die Herzfrequenz übermäßig ansteigt oder die Technik zerfällt, hat
///   NICHT «versagt», sondern sinnvolle Selbstregulation bewiesen.
/// - Compliance wird mehrdimensional erfasst:
///   Dauer, Intervalle, Intensität, Struktur und Modalität getrennt.
library;

class WorkoutExecutionEvaluation {
  const WorkoutExecutionEvaluation({
    required this.prescribedWorkoutId,
    required this.actualSessionId,
    required this.durationCompliance,
    required this.modalityCompliance,
    this.intervalCompliance,
    this.intensityCompliance,
    this.structuralCompliance = 1.0,
    this.athleteModified = false,
    this.athleteModificationReason,
    this.isMeaningfulSelfRegulation = false,
    this.overallEvaluationText = '',
  });

  /// ID der vorgeschriebenen Einheit.
  final String prescribedWorkoutId;

  /// ID der tatsächlich beobachteten Session (NormalizedSession.id).
  final String actualSessionId;

  /// Erfüllungsgrad der Gesamtdauer (z. B. 0.85 = 85 %).
  final double durationCompliance;

  /// Übereinstimmung der Sportart / Modalität.
  final bool modalityCompliance;

  /// Erfüllungsgrad der Intervall-Wiederholungen (z. B. 3 von 4 = 0.75).
  final double? intervalCompliance;

  /// Einhaltung des Ziel-Intensitätsbereichs (z. B. Zeit im Zielbereich).
  final double? intensityCompliance;

  /// Einhaltung der Trainingsstruktur (Aufwärmen, Hauptteil, Abwärmen).
  final double structuralCompliance;

  /// Hat der Athlet die Einheit bewusst modifiziert oder vorzeitig beendet?
  final bool athleteModified;

  /// Grund der Modifikation (z. B. «Starke Ermüdung», «Zeitnot»).
  final String? athleteModificationReason;

  /// Bewertet eine vorzeitige Beendigung oder Drosselung als sinnvolle Selbstregulation
  /// statt als Plan-Fehlschlag.
  final bool isMeaningfulSelfRegulation;

  /// Sportwissenschaftliches Feedback zur Ausführung.
  final String overallEvaluationText;

  Map<String, dynamic> toJson() => {
    'prescribedWorkoutId': prescribedWorkoutId,
    'actualSessionId': actualSessionId,
    'durationCompliance': durationCompliance,
    'modalityCompliance': modalityCompliance,
    'intervalCompliance': intervalCompliance,
    'intensityCompliance': intensityCompliance,
    'structuralCompliance': structuralCompliance,
    'athleteModified': athleteModified,
    'athleteModificationReason': athleteModificationReason,
    'isMeaningfulSelfRegulation': isMeaningfulSelfRegulation,
    'overallEvaluationText': overallEvaluationText,
  };
}
