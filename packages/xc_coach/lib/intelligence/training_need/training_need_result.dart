/// Gesamtergebnis der GIULIA Training Need Engine (Schritt 4).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Strikte Strukturierung in Development Needs, Maintenance Needs,
///   Information Needs (Assessment Needs) und Current Constraints.
/// - Jeder Need ist rückverfolgbar:
///   Need -> Reason -> AthleteState Evidence -> Session/Diagnostic -> Source.
/// - Liefert das transparente [toFactSheetText()].
library;

import '../xc_athlete_state/goal_context.dart';
import 'assessment_need.dart';
import 'safety_constraint.dart';
import 'training_need.dart';

class TrainingNeedResult {
  const TrainingNeedResult({
    required this.asOf,
    required this.athleteId,
    this.goal,
    this.developmentNeeds = const [],
    this.maintenanceNeeds = const [],
    this.immediateOpportunities = const [],
    this.informationNeeds = const [],
    this.safetyConstraints = const [],
    this.traceMap = const {},
  });

  final DateTime asOf;
  final String athleteId;
  final GoalContext? goal;

  /// Langfristig aufzubauende oder zu verbessernde Fähigkeiten.
  final List<TrainingNeed> developmentNeeds;

  /// Bereits gut ausgeprägte Fähigkeiten, die erhalten werden müssen.
  final List<TrainingNeed> maintenanceNeeds;

  /// Situativ günstige Trainingsgelegenheiten im aktuellen Wochenkontext.
  final List<TrainingNeed> immediateOpportunities;

  /// Diagnostischer Informationsbedarf ("Ich weiß noch nicht genug").
  final List<AssessmentNeed> informationNeeds;

  /// Aktuelle Sicherheits- und Gesundheitseinschränkungen.
  final List<SafetyConstraint> safetyConstraints;

  /// Rückverfolgbarkeitsketten für jeden Need (Schlüssel: needId oder needTypeKey).
  final Map<String, String> traceMap;

  bool get hasSafetyConstraints => safetyConstraints.isNotEmpty;

  /// Liefert die lückenlose Rückverfolgbarkeitskette für einen Bedarf:
  /// Need -> Reason -> AthleteState Evidence -> Session/Diagnostic -> Source.
  String traceEvidenceFor(String needKey) {
    if (traceMap.containsKey(needKey)) {
      return traceMap[needKey]!;
    }
    // Suche nach type.key
    for (final entry in traceMap.entries) {
      if (entry.key.toLowerCase().contains(needKey.toLowerCase())) {
        return entry.value;
      }
    }
    return 'Bedarf "$needKey": Keine spezifische Evidenzkette registriert';
  }

  /// Erstellt das von der Facharchitektur geforderte, ungeschönte Need Fact Sheet.
  String toFactSheetText() {
    final buffer = StringBuffer();
    buffer.writeln('=== GIULIA TRAINING NEEDS ===');
    buffer.writeln();

    // 1. Goal
    buffer.writeln('Goal:');
    if (goal != null) {
      final days = goal!.daysUntilGoal(asOf: asOf);
      final distStr = goal!.targetDistanceKm != null ? '${goal!.targetDistanceKm!.toStringAsFixed(0)} km ' : '';
      final daysStr = days != null ? ' · $days Tage' : '';
      buffer.writeln('$distStr${goal!.name}$daysStr');
    } else {
      buffer.writeln('Kein spezifisches Wettkampfziel hinterlegt');
    }
    buffer.writeln();

    // 2. Development Needs
    buffer.writeln('DEVELOPMENT NEEDS');
    if (developmentNeeds.isEmpty) {
      buffer.writeln('Keine akuten Entwicklungsbedarfe identifiziert.');
    } else {
      for (final need in developmentNeeds) {
        buffer.writeln();
        buffer.writeln(need.priority.nameKey);
        buffer.writeln(need.type.label);
        buffer.writeln('Reason:');
        for (final r in need.reasons) {
          buffer.writeln('- $r');
        }
      }
    }
    buffer.writeln();

    // 3. Maintenance Needs
    buffer.writeln('MAINTENANCE NEEDS');
    if (maintenanceNeeds.isEmpty) {
      buffer.writeln('Keine isolierten Erhaltungsbedarfe deklariert.');
    } else {
      for (final need in maintenanceNeeds) {
        buffer.writeln();
        buffer.writeln(need.priority.nameKey);
        buffer.writeln(need.type.label);
        buffer.writeln('Reason:');
        for (final r in need.reasons) {
          buffer.writeln('- $r');
        }
      }
    }
    buffer.writeln();

    // 4. Information Needs (Assessment Needs)
    buffer.writeln('INFORMATION NEEDS');
    if (informationNeeds.isEmpty) {
      buffer.writeln('Datenbasis vollständig, keine offenen Diagnostiklücken.');
    } else {
      for (final info in informationNeeds) {
        buffer.writeln();
        buffer.writeln(info.priority.nameKey);
        buffer.writeln(info.type.label);
        buffer.writeln('Reason:');
        for (final r in info.reasons) {
          buffer.writeln('- $r');
        }
      }
    }
    buffer.writeln();

    // 5. Current Constraints & Safety
    buffer.writeln('CURRENT CONSTRAINTS');
    if (safetyConstraints.isEmpty) {
      buffer.writeln('- Keine akuten Einschränkungen gemeldet');
    } else {
      for (final sc in safetyConstraints) {
        buffer.writeln('- [${sc.severity.label}] ${sc.reason} (Evidenz: ${sc.evidence})');
      }
    }

    return buffer.toString().trimRight();
  }

  Map<String, dynamic> toJson() => {
    'asOf': asOf.toIso8601String(),
    'athleteId': athleteId,
    if (goal != null) 'goal': goal!.toJson(),
    'developmentNeeds': developmentNeeds.map((n) => n.toJson()).toList(),
    'maintenanceNeeds': maintenanceNeeds.map((n) => n.toJson()).toList(),
    'immediateOpportunities':
        immediateOpportunities.map((n) => n.toJson()).toList(),
    'informationNeeds': informationNeeds.map((i) => i.toJson()).toList(),
    'safetyConstraints': safetyConstraints.map((c) => c.toJson()).toList(),
  };
}
