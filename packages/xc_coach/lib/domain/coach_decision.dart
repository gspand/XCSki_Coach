/// Eine nachvollziehbare Entscheidung über den Plan.
///
/// Kein Plan ändert sich still: Jede Änderung – von einer Person oder später
/// von GIULIA – trägt Zeitpunkt, betroffene Einheiten, die verwendeten Fakten,
/// die Änderung selbst und die Begründung. Entscheidungen werden nur angefügt.
library;

enum CoachDecisionType {
  planned,
  rescheduled,
  modified,
  skipped,
  sessionLinked,

  /// TRAIN hat die Session aus dieser geplanten Einheit gestartet.
  sessionStarted,

  /// Die aus der Einheit gestartete Session wurde abgeschlossen.
  sessionCompleted,
}

enum CoachDecisionAuthor { user, giulia }

/// Ein Fakt, auf den sich eine Entscheidung stützt.
class CoachFactRef {
  const CoachFactRef({
    required this.kind,
    required this.id,
    required this.label,
    this.value,
    this.unit,
  });

  factory CoachFactRef.fromJson(Map<String, Object?> json) => CoachFactRef(
    kind: json['kind'] as String,
    id: json['id'] as String,
    label: json['label'] as String,
    value: json['value'],
    unit: json['unit'] as String?,
  );

  /// `test`, `session`, `plannedWorkout`, `attribute` …
  final String kind;
  final String id;
  final String label;
  final Object? value;
  final String? unit;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'id': id,
    'label': label,
    'value': value,
    'unit': unit,
  };
}

class CoachDecision {
  CoachDecision({
    required this.id,
    required this.organizationId,
    required this.athleteId,
    required this.decidedAtUtcUs,
    required this.type,
    required this.author,
    required this.plannedWorkoutIds,
    required this.change,
    required this.reason,
    this.facts = const [],
    this.decidedByUserId,
    this.dataQuality,
  }) {
    if (reason.trim().isEmpty) {
      throw ArgumentError('Eine Entscheidung braucht eine Begründung.');
    }
    if (author == CoachDecisionAuthor.giulia && facts.isEmpty) {
      throw ArgumentError(
        'GIULIA darf den Plan nur mit benannten Fakten ändern.',
      );
    }
  }

  final String id;
  final String organizationId;
  final String athleteId;
  final int decidedAtUtcUs;
  final CoachDecisionType type;
  final CoachDecisionAuthor author;
  final String? decidedByUserId;
  final List<String> plannedWorkoutIds;
  final List<CoachFactRef> facts;

  /// Was geändert wurde, z. B. `{'status': {'from': 'planned', 'to': 'skipped'}}`.
  final Map<String, Object?> change;
  final String reason;

  /// Datenqualität, wenn sie sich benennen lässt (`high`, `low` …).
  final String? dataQuality;
}
