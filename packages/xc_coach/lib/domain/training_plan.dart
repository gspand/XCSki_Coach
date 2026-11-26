/// Plan und Ist: was vorgesehen war und was gemacht wurde.
///
/// Eine geplante Einheit ist keine Session. Sie verweist höchstens auf die
/// Session, die sie erfüllt hat. TRAIN zeichnet auf, COACH plant; beides
/// bleibt getrennt gespeichert.
///
/// Reines Dart, ohne Datenbank und ohne Oberfläche.
library;

import 'diagnostic_catalogue.dart';
import 'coach_decision.dart';

/// Lesender Zugang zu Plan und Entscheidungen, unabhängig vom Speicher.
abstract interface class TrainingPlanReader {
  TrainingPlan planOf(String athleteId, {CalendarDay? from, CalendarDay? to});

  /// Neueste zuerst.
  List<CoachDecision> decisionsOf(String athleteId, {int limit = 20});
}

/// Ein Kalendertag in der Ortszeit des Athleten.
class CalendarDay implements Comparable<CalendarDay> {
  const CalendarDay(this.year, this.month, this.day);

  factory CalendarDay.ofLocal(DateTime value) =>
      CalendarDay(value.year, value.month, value.day);

  factory CalendarDay.ofUtcUs(int utcUs) => CalendarDay.ofLocal(
    DateTime.fromMicrosecondsSinceEpoch(utcUs, isUtc: true).toLocal(),
  );

  factory CalendarDay.parse(String key) {
    final parts = key.split('-').map(int.parse).toList(growable: false);
    return CalendarDay(parts[0], parts[1], parts[2]);
  }

  final int year;
  final int month;
  final int day;

  DateTime get _date => DateTime(year, month, day);

  String get key =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  CalendarDay addDays(int days) =>
      CalendarDay.ofLocal(DateTime(year, month, day + days));

  /// Montag der Woche, in der dieser Tag liegt.
  CalendarDay get weekStart => addDays(1 - _date.weekday);

  int daysUntil(CalendarDay other) => DateTime.utc(
    other.year,
    other.month,
    other.day,
  ).difference(DateTime.utc(year, month, day)).inDays;

  bool isBefore(CalendarDay other) => compareTo(other) < 0;

  @override
  int compareTo(CalendarDay other) => key.compareTo(other.key);

  @override
  bool operator ==(Object other) => other is CalendarDay && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => key;
}

enum PlannedWorkoutStatus { planned, completed, skipped, modified }

/// Ein Abschnitt der vorgesehenen Struktur.
class PlannedStep {
  const PlannedStep({
    required this.kind,
    required this.seconds,
    this.intensity,
  });

  factory PlannedStep.fromJson(Map<String, Object?> json) => PlannedStep(
    kind: json['kind'] as String,
    seconds: (json['seconds'] as num).toInt(),
    intensity: json['intensity'] as String?,
  );

  final String kind;
  final int seconds;

  /// Relative Intensität der Bibliothek (`base`, `threshold` …), nicht Watt.
  final String? intensity;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'seconds': seconds,
    'intensity': intensity,
  };
}

class PlannedWorkout {
  const PlannedWorkout({
    required this.id,
    required this.organizationId,
    required this.athleteId,
    required this.day,
    required this.sport,
    required this.goal,
    required this.durationSeconds,
    required this.createdAtUtcUs,
    required this.updatedAtUtcUs,
    this.intensity,
    this.blueprintId,
    this.structure = const [],
    this.status = PlannedWorkoutStatus.planned,
    this.sessionId,
    this.createdByUserId,
  });

  final String id;
  final String organizationId;
  final String athleteId;
  final CalendarDay day;

  /// Speicherschlüssel der Sportart (`ercolina`, `running`, …).
  final String sport;

  /// Wofür die Einheit da ist, in einem Satz.
  final String goal;
  final int durationSeconds;

  /// Die vorgesehene Hauptintensität, relativ (`base`, `threshold` …).
  final String? intensity;
  final String? blueprintId;
  final List<PlannedStep> structure;
  final PlannedWorkoutStatus status;

  /// Die Session, die diese Einheit erfüllt hat. Nie umgekehrt.
  final String? sessionId;
  final String? createdByUserId;
  final int createdAtUtcUs;
  final int updatedAtUtcUs;

  DiagnosticSport? get diagnosticSport =>
      DiagnosticSport.classify(sport: sport);

  bool get isOpen => status == PlannedWorkoutStatus.planned;

  /// Aus TRAIN gestartet, aber noch nicht abgeschlossen (läuft oder wurde
  /// unterbrochen). Weder ausgelassen noch absolviert.
  bool get isStarted => isOpen && sessionId != null;

  PlannedWorkout copyWith({
    PlannedWorkoutStatus? status,
    String? sessionId,
    CalendarDay? day,
    int? updatedAtUtcUs,
  }) => PlannedWorkout(
    id: id,
    organizationId: organizationId,
    athleteId: athleteId,
    day: day ?? this.day,
    sport: sport,
    goal: goal,
    durationSeconds: durationSeconds,
    intensity: intensity,
    blueprintId: blueprintId,
    structure: structure,
    status: status ?? this.status,
    sessionId: sessionId ?? this.sessionId,
    createdByUserId: createdByUserId,
    createdAtUtcUs: createdAtUtcUs,
    updatedAtUtcUs: updatedAtUtcUs ?? this.updatedAtUtcUs,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'athleteId': athleteId,
    'date': day.key,
    'sport': sport,
    'goal': goal,
    'durationSeconds': durationSeconds,
    'intensity': intensity,
    'blueprintId': blueprintId,
    'structure': [for (final step in structure) step.toJson()],
    'status': status.name,
    'sessionId': sessionId,
  };
}

/// Eine Kalenderwoche des Plans, Montag bis Sonntag.
class TrainingWeek {
  const TrainingWeek({required this.start, required this.workouts});

  final CalendarDay start;
  final List<PlannedWorkout> workouts;

  int get plannedSeconds =>
      workouts.fold(0, (sum, workout) => sum + workout.durationSeconds);

  int count(PlannedWorkoutStatus status) =>
      workouts.where((workout) => workout.status == status).length;
}

/// Die geplanten Einheiten eines Athleten, nach Tag geordnet.
class TrainingPlan {
  TrainingPlan({
    required this.athleteId,
    required List<PlannedWorkout> workouts,
  }) : workouts = List.unmodifiable(
         [...workouts]..sort((a, b) {
           final byDay = a.day.compareTo(b.day);
           return byDay != 0
               ? byDay
               : a.createdAtUtcUs.compareTo(b.createdAtUtcUs);
         }),
       ) {
    if (workouts.any((workout) => workout.athleteId != athleteId)) {
      throw ArgumentError('Ein Plan gehört genau einem Athleten.');
    }
  }

  final String athleteId;
  final List<PlannedWorkout> workouts;

  List<PlannedWorkout> on(CalendarDay day) => [
    for (final workout in workouts)
      if (workout.day == day) workout,
  ];

  /// Einheiten nach [day] bis einschließlich [day] + [days].
  List<PlannedWorkout> upcoming(CalendarDay day, {int days = 7}) {
    final end = day.addDays(days);
    return [
      for (final workout in workouts)
        if (day.isBefore(workout.day) && !end.isBefore(workout.day)) workout,
    ];
  }

  /// Vergangene Einheiten, die weder begonnen, erledigt noch ausgelassen
  /// wurden.
  List<PlannedWorkout> overdue(CalendarDay today) => [
    for (final workout in workouts)
      if (workout.day.isBefore(today) && workout.isOpen && !workout.isStarted)
        workout,
  ];

  TrainingWeek week(CalendarDay day) {
    final start = day.weekStart;
    final end = start.addDays(6);
    return TrainingWeek(
      start: start,
      workouts: [
        for (final workout in workouts)
          if (!workout.day.isBefore(start) && !end.isBefore(workout.day))
            workout,
      ],
    );
  }
}

/// Eine absolvierte Einheit, so viel davon, wie der Plan-Ist-Vergleich braucht.
class ActualSession {
  const ActualSession({
    required this.sessionId,
    required this.athleteId,
    required this.startedAtUtcUs,
    required this.durationSeconds,
    required this.sport,
    this.targetedIntervals = const [],
    this.intervalCount,
    this.finished = true,
  });

  final String sessionId;
  final String athleteId;
  final int startedAtUtcUs;
  final int durationSeconds;
  final String sport;

  /// Intervalle mit gemessener Leistung und dem Zielbereich, der während der
  /// Aufzeichnung galt.
  final List<TargetedInterval> targetedIntervals;

  /// Aufgezeichnete Abschnitte; null, wenn die Quelle keine kennt.
  final int? intervalCount;

  /// False für eine begonnene Session, die nie regulär beendet wurde.
  final bool finished;

  CalendarDay get day => CalendarDay.ofUtcUs(startedAtUtcUs);
}

class TargetedInterval {
  const TargetedInterval({
    required this.seconds,
    required this.averagePowerWatt,
    required this.targetMinWatt,
    required this.targetMaxWatt,
  });

  final int seconds;
  final double averagePowerWatt;
  final double targetMinWatt;
  final double targetMaxWatt;
}

/// Sekunden unter, im und über dem Zielbereich. Nur aus aufgezeichneten
/// Intervallen mit Zielbereich, sonst gibt es sie nicht.
class IntensityDeviation {
  const IntensityDeviation({
    required this.belowSeconds,
    required this.inTargetSeconds,
    required this.aboveSeconds,
  });

  final int belowSeconds;
  final int inTargetSeconds;
  final int aboveSeconds;

  int get totalSeconds => belowSeconds + inTargetSeconds + aboveSeconds;
}

/// Wann eine zugeordnete Session als «verändert» statt «absolviert» gilt.
///
/// Eine konfigurierbare Erfassungsheuristik, keine sportwissenschaftliche
/// Aussage über die Einheit. Sie entscheidet heute nur aus Sportart und Dauer;
/// Intensität und Struktur stellt [PlanActual] als Daten bereit, ohne sie zu
/// bewerten.
class PlanStatusRule {
  const PlanStatusRule({this.durationTolerance = 0.15});

  /// Relative Dauerabweichung, bis zu der eine Einheit als absolviert gilt.
  final double durationTolerance;
}

const PlanStatusRule planStatusRule = PlanStatusRule();

/// Was geplant war gegen das, was gemacht wurde.
class PlanActual {
  const PlanActual({
    required this.planned,
    this.actual,
    this.rule = planStatusRule,
  });

  final PlannedWorkout planned;
  final ActualSession? actual;
  final PlanStatusRule rule;

  bool get sportMatches {
    final session = actual;
    if (session == null) return false;
    return sameSport(planned.sport, session.sport);
  }

  /// Null ohne Session.
  bool? get sportChanged => actual == null ? null : !sportMatches;

  /// Null ohne Session.
  bool? get durationChanged {
    final delta = durationDeltaSeconds;
    if (delta == null) return null;
    final relative = planned.durationSeconds <= 0
        ? 0.0
        : delta.abs() / planned.durationSeconds;
    return relative > rule.durationTolerance;
  }

  /// Geplante und aufgezeichnete Abschnitte; null, wo nichts aufgezeichnet ist.
  int get plannedSteps => planned.structure.length;
  int? get recordedIntervals => actual?.intervalCount;

  /// Positiv: länger als geplant. Null ohne Session.
  int? get durationDeltaSeconds {
    final session = actual;
    return session == null
        ? null
        : session.durationSeconds - planned.durationSeconds;
  }

  IntensityDeviation? get intensityDeviation {
    final intervals = actual?.targetedIntervals ?? const <TargetedInterval>[];
    if (intervals.isEmpty) return null;
    var below = 0, inside = 0, above = 0;
    for (final interval in intervals) {
      if (interval.averagePowerWatt < interval.targetMinWatt) {
        below += interval.seconds;
      } else if (interval.averagePowerWatt > interval.targetMaxWatt) {
        above += interval.seconds;
      } else {
        inside += interval.seconds;
      }
    }
    return IntensityDeviation(
      belowSeconds: below,
      inTargetSeconds: inside,
      aboveSeconds: above,
    );
  }

  /// Der Status, den eine abgeschlossene, zugeordnete Session ergibt.
  PlannedWorkoutStatus get statusAfterLink {
    if (actual == null) return planned.status;
    return sportChanged! || durationChanged!
        ? PlannedWorkoutStatus.modified
        : PlannedWorkoutStatus.completed;
  }
}

/// Zwei Sportarten sind dieselbe, wenn TEST sie gleich einordnet.
bool sameSport(String a, String b) {
  final left = DiagnosticSport.classify(sport: a);
  final right = DiagnosticSport.classify(sport: b);
  if (left != null || right != null) return left == right;
  return a.trim().toLowerCase() == b.trim().toLowerCase();
}
