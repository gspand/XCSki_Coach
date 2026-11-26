/// Tägliche Coaching-Entscheidung (Daily Coaching Decision) und Hoje-Karte.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Beantwortet glasklar: «Was soll der Athlet heute trainieren – und warum?»
/// - Erklärt:
///   1. Gewählte Einheit oder Ruhetag
///   2. Primären und sekundären Trainingsbedarf, der adressiert wird
///   3. Begründung und Passung zum Wettkampfziel
///   4. Sicherheits- und Ermüdungseinschränkungen
///   5. Abgelehnte Alternativen (Warum kein VO2max? Warum keine Ercolina?)
///   6. Datenunsicherheiten (z. B. unvollständige Synchronisation)
///   7. Rückwärts-Trace bis zur Quelle (State -> Need -> Evidence -> Source)
library;

import '../female_athlete/female_athlete_models.dart';
import '../training_need/need_types.dart';
import '../training_need/safety_constraint.dart';
import '../training_need/training_need.dart';
import 'workout_candidate.dart';
import 'workout_prescription.dart';

/// Art der getroffenen Coaching-Handlung.
enum CoachingActionType {
  prescribedWorkout('Gezielte Trainingseinheit'),
  restDay('Vollständiger Ruhetag (Passiv)'),
  activeRecovery('Aktive Regeneration'),
  diagnosticSession('Diagnostik- / Leistungstest-Einheit');

  const CoachingActionType(this.label);
  final String label;
}

class DailyCoachingDecision {
  const DailyCoachingDecision({
    required this.decisionDate,
    required this.athleteId,
    required this.actionType,
    this.prescribedWorkout,
    this.primaryNeed,
    this.secondaryNeeds = const [],
    required this.coachingReason,
    this.safetyConstraintsApplied = const [],
    this.rejectedAlternatives = const [],
    this.dataLimitations = const [],
    required this.confidence,
    this.backwardTrace = const {},
    this.femaleContext,
  });

  final DateTime decisionDate;
  final String athleteId;
  final CoachingActionType actionType;
  final WorkoutPrescription? prescribedWorkout;
  final TrainingNeed? primaryNeed;
  final List<TrainingNeed> secondaryNeeds;

  /// Sportwissenschaftlich fundierte Hauptbegründung für den heutigen Tag.
  final String coachingReason;

  /// Relevante Sicherheits- und Gesundheitsschutzregeln, die heute gegriffen haben.
  final List<SafetyConstraint> safetyConstraintsApplied;

  /// Optionaler weiblicher Athletenkontext (Zyklus, Symptome, Evidenz).
  final FemaleAthleteContext? femaleContext;

  /// Transparente Liste verworfener Alternativen samt Ablehnungsgrund.
  final List<RejectedAlternative> rejectedAlternatives;

  /// Explizit benannte Unsicherheiten oder Datenlücken.
  final List<String> dataLimitations;

  /// Vertrauensgrad der Entscheidung basierend auf Datenqualität.
  final NeedConfidence confidence;

  /// Vollständiger Rückwärts-Trace: Entscheidung -> Bedarf -> Evidenz -> Quelle.
  final Map<String, String> backwardTrace;

  /// Erzeugt die strukturierte, sportwissenschaftlich fundierte «Heute-Karte» auf Deutsch.
  String toHeuteCardText() {
    final buffer = StringBuffer();
    final dateStr =
        '${decisionDate.day.toString().padLeft(2, "0")}.${decisionDate.month.toString().padLeft(2, "0")}.${decisionDate.year}';

    buffer.writeln('=== GIULIA XC COACH – HEUTE-KARTE ($dateStr) ===');

    if (actionType == CoachingActionType.restDay) {
      buffer.writeln('STATUS: VOLLSTÄNDIGER RUHETAG');
      buffer.writeln('BEGRÜNDUNG: $coachingReason');
      if (safetyConstraintsApplied.isNotEmpty) {
        buffer.writeln('SICHERHEITSHINWEIS:');
        for (final sc in safetyConstraintsApplied) {
          buffer.writeln(' • ${sc.reason}');
        }
      }
    } else if (actionType == CoachingActionType.activeRecovery) {
      buffer.writeln('STATUS: AKTIVE REGENERATION');
      if (prescribedWorkout != null) {
        buffer.writeln('EINHEIT: ${prescribedWorkout!.title}');
        buffer.writeln(
          'DAUER: ${prescribedWorkout!.totalDurationMinutes} Minuten',
        );
        buffer.writeln('STRUKTUR: ${prescribedWorkout!.structureDescription}');
      }
      buffer.writeln('BEGRÜNDUNG: $coachingReason');
    } else {
      final w = prescribedWorkout!;
      buffer.writeln('EMPFOHLENE EINHEIT: ${w.title}');
      buffer.writeln('SPORTART: ${w.modality.label}');
      buffer.writeln(
        'DAUER: ${w.totalDurationMinutes} min (Warmup ${w.warmupMinutes}m · Belastung ${w.workMinutes}m · Cooldown ${w.cooldownMinutes}m)',
      );
      buffer.writeln('STRUKTUR: ${w.structureDescription}');
      buffer.writeln('INTENSITÄT: ${w.workIntensity.displayInstruction}');
      buffer.writeln('ERHOLUNGSBEDARF: ${w.recoveryCost.label}');
      buffer.writeln('');
      buffer.writeln('WARUM HEUTE:');
      buffer.writeln(' • $coachingReason');
      if (primaryNeed != null) {
        buffer.writeln(
          ' • Primärer Trainingsbedarf: ${primaryNeed!.type.label} (${primaryNeed!.priority.label})',
        );
      }
    }

    if (safetyConstraintsApplied.isNotEmpty &&
        actionType != CoachingActionType.restDay) {
      buffer.writeln('');
      buffer.writeln('AKTIVE SCHUTZLEITPLANKEN:');
      for (final sc in safetyConstraintsApplied) {
        buffer.writeln(' • ${sc.reason}');
      }
    }

    if (rejectedAlternatives.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('VERWORFENE ALTERNATIVEN:');
      for (final alt in rejectedAlternatives.take(3)) {
        buffer.writeln(
          ' • ${alt.workoutTitle}: ${alt.reason} [Stufe: ${alt.rejectionStage.label}]',
        );
      }
    }

    if (dataLimitations.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('DATENHINWEISE & TRANSPARENZ:');
      for (final lim in dataLimitations) {
        buffer.writeln(' • $lim');
      }
    }

    if (femaleContext != null && femaleContext!.isTrackingActive) {
      final sym = femaleContext!.todaysSymptoms;
      if (sym != null && sym.hasRelevantSymptoms) {
        buffer.writeln('');
        buffer.writeln('HEUTE BERÜCKSICHTIGT (ZYKLUSKONTEXT):');
        buffer.writeln(
          ' • Aktive Symptome gemeldet (${sym.describeActiveSymptoms().join(", ")}).',
        );
        if (femaleContext!.evidence.hasActionablePatterns) {
          buffer.writeln(
            ' • Wiederholtes persönliches Erholungs-Muster berücksichtigt.',
          );
        }
      }
    }

    return buffer.toString().trim();
  }

  Map<String, dynamic> toJson() => {
    'decisionDate': decisionDate.toIso8601String(),
    'athleteId': athleteId,
    'actionType': actionType.name,
    'prescribedWorkout': prescribedWorkout?.toJson(),
    'primaryNeed': primaryNeed?.toJson(),
    'secondaryNeeds': secondaryNeeds.map((n) => n.toJson()).toList(),
    'coachingReason': coachingReason,
    'safetyConstraintsApplied': safetyConstraintsApplied
        .map((s) => s.toJson())
        .toList(),
    'rejectedAlternatives': rejectedAlternatives
        .map((r) => r.toJson())
        .toList(),
    'dataLimitations': dataLimitations,
    'confidence': confidence.name,
    'backwardTrace': backwardTrace,
    if (femaleContext != null) 'femaleContext': femaleContext!.toJson(),
  };

  factory DailyCoachingDecision.fromJson(
    Map<String, dynamic> json,
  ) => DailyCoachingDecision(
    decisionDate: json['decisionDate'] != null
        ? DateTime.parse(json['decisionDate'].toString())
        : DateTime.now(),
    athleteId: json['athleteId']?.toString() ?? '',
    actionType: CoachingActionType.values.firstWhere(
      (a) => a.name == json['actionType'],
      orElse: () => CoachingActionType.restDay,
    ),
    prescribedWorkout: json['prescribedWorkout'] == null
        ? null
        : WorkoutPrescription.fromJson(
            json['prescribedWorkout'] as Map<String, dynamic>,
          ),
    primaryNeed: json['primaryNeed'] == null
        ? null
        : TrainingNeed.fromJson(json['primaryNeed'] as Map<String, dynamic>),
    secondaryNeeds: (json['secondaryNeeds'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TrainingNeed.fromJson)
        .toList(),
    safetyConstraintsApplied:
        (json['safetyConstraintsApplied'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(SafetyConstraint.fromJson)
            .toList(),
    rejectedAlternatives: (json['rejectedAlternatives'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(RejectedAlternative.fromJson)
        .toList(),
    coachingReason: json['coachingReason']?.toString() ?? '',
    dataLimitations:
        (json['dataLimitations'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
    confidence: NeedConfidence.values.firstWhere(
      (c) => c.name == json['confidence'],
      orElse: () => NeedConfidence.moderate,
    ),
    backwardTrace:
        (json['backwardTrace'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v.toString()),
        ) ??
        const {},
    femaleContext: json['femaleContext'] != null
        ? FemaleAthleteContext.fromJson(
            json['femaleContext'] as Map<String, dynamic>,
          )
        : null,
  );
}
