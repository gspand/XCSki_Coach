/// Sicherheits-Einschränkungen (Safety Constraints) der GIULIA Training Need Engine.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE & MEDIZINISCHE LEITPLANKEN:
/// - Keine medizinischen Diagnosen stellen («Du hast Übertraining» oder «Du hast Sehnenentzündung» ist verboten).
/// - Safety ist stärker als Training Need: Wenn ein Sicherheitsrisiko vorliegt,
///   schützt die Engine den Athleten und sperrt potenziell schädliche Reize.
/// - Symptome (Schmerz, Infektzeichen, extreme Erschöpfung) werden als strukturierte
///   Einschränkungen formuliert.
library;

import 'need_types.dart';

/// Schweregrad einer Sicherheits-Einschränkung.
enum SafetyConstraintSeverity {
  /// Leichte Auffälligkeit (z. B. leichter Muskelkater, suboptimale Erholung).
  mild('Leicht', 1),

  /// Moderate Einschränkung (z. B. lokalisierter Schmerz, beginnendes Krankheitsgefühl).
  moderate('Moderat', 2),

  /// Schwerwiegende Einschränkung (z. B. akute Infektsymptome, deutlicher Schmerz unter Belastung).
  severe('Schwerwiegend', 3),

  /// Kritischer Sicherheitsstopp (z. B. Fieber, schwere Erschöpfung, Verletzung).
  critical('Kritisch', 4);

  const SafetyConstraintSeverity(this.label, this.level);
  final String label;
  final int level;

  bool operator >(SafetyConstraintSeverity other) => level > other.level;
  bool operator >=(SafetyConstraintSeverity other) => level >= other.level;
}

/// Strukturierte Einschränkung für die Trainingsplanung.
class SafetyConstraint {
  const SafetyConstraint({
    required this.id,
    required this.severity,
    required this.reason,
    required this.evidence,
    this.affectedTrainingTypes = const [],
    this.confidence = 0.90,
    this.recordedAt,
  });

  /// Eindeutige Kennung der Einschränkung.
  final String id;

  /// Schweregrad.
  final SafetyConstraintSeverity severity;

  /// Sportwissenschaftlich/vorsorglich formulierte Begründung (KEINE medizinische Diagnose!).
  final String reason;

  /// Das zugrundeliegende Signal oder die Athletenangabe.
  final String evidence;

  /// Liste der betroffenen Bedarfsarten, die eingeschränkt oder temporär gemieden werden sollten.
  final List<TrainingNeedType> affectedTrainingTypes;

  /// Zuverlässigkeit der Meldung (z. B. 1.0 bei direkter Athletenmeldung).
  final double confidence;

  /// Zeitpunkt des Vorfalls/der Erfassung.
  final DateTime? recordedAt;

  /// Gibt an, ob ein spezifischer Reiz durch diese Constraint blockiert oder gemieden werden soll.
  bool restricts(TrainingNeedType type) {
    if (severity == SafetyConstraintSeverity.critical) {
      // Kritische Constraints blockieren jedes fordernde Training!
      return type != TrainingNeedType.recovery;
    }
    return affectedTrainingTypes.contains(type);
  }

  factory SafetyConstraint.fromJson(Map<String, dynamic> j) => SafetyConstraint(
    id: j['id'] as String,
    severity: SafetyConstraintSeverity.values.byName(j['severity'] as String),
    reason: j['reason'] as String,
    evidence: j['evidence'] as String,
    affectedTrainingTypes: (j['affectedTrainingTypes'] as List? ?? const [])
        .cast<String>()
        .map((k) => TrainingNeedType.values.firstWhere((t) => t.key == k))
        .toList(),
    confidence: (j['confidence'] as num).toDouble(),
    recordedAt: j['recordedAt'] == null
        ? null
        : DateTime.parse(j['recordedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'severity': severity.name,
    'reason': reason,
    'evidence': evidence,
    'affectedTrainingTypes': affectedTrainingTypes.map((t) => t.key).toList(),
    'confidence': confidence,
    if (recordedAt != null) 'recordedAt': recordedAt!.toIso8601String(),
  };
}
