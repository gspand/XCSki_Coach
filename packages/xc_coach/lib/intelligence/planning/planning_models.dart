/// Begriffe der Trainingsplanung: Reiz, Modalität, Ziel, Saisonphase und die
/// Planungspolitik.
///
/// Der Planer denkt in **Reizen** (REG bis SB, dazu Schnelligkeit und
/// Technik), nicht in Wochentagen. Welcher Reiz heute dran ist, entscheidet
/// der Zustand des Athleten; welche Einheit ihn setzt, die Bibliothek.
///
/// Die Zahlen in [PlanningPolicy] sind Ausgangswerte der Trainingslehre, keine
/// Naturgesetze. Sie gehören zum Athleten, und die Befunde (Diagnostik,
/// Verlauf, Erholung) verschieben sie – nie umgekehrt.
library;

import '../../domain/training_plan.dart';
import '../../workout_engine/workout_library.dart';

/// Ein Trainingsreiz, benannt nach dem Bereich des schwellenverankerten
/// LaLa-Zonenmodells (REG, GAL, GA1, GA2, EB, SB).
enum TrainingStimulus {
  regeneration('REG', 'Regeneration'),
  longEndurance('GAL', 'Lange Grundlage'),
  aerobicBase('GA1', 'Aerobe Basis'),
  aerobicCapacity('GA2', 'Aerobe Kapazität'),
  threshold('EB', 'Schwellenreiz', intensive: true),
  vo2max('SB', 'Aerobe Leistung (VO2max)', intensive: true),
  speed('SB', 'Schnelligkeit und Kraft', intensive: true),
  technique(null, 'Technik');

  const TrainingStimulus(this.zoneCode, this.label, {this.intensive = false});

  final String? zoneCode;
  final String label;

  /// Braucht Erholung davor und danach; zählt für den Abstand harter Reize.
  final bool intensive;

  /// Die relative Intensität der Bibliothek, mit der dieser Reiz arbeitet.
  Intensity get libraryIntensity => switch (this) {
    regeneration => Intensity.recovery,
    longEndurance || aerobicBase => Intensity.base,
    aerobicCapacity => Intensity.tempo,
    threshold => Intensity.threshold,
    vo2max => Intensity.vo2,
    speed => Intensity.maximal,
    technique => Intensity.technique,
  };

  /// Der Reiz einer geplanten Einheit: der intensive Anteil, wenn es einen
  /// gibt, sonst der längste.
  static TrainingStimulus? ofPlanned(PlannedWorkout workout) {
    final seconds = <TrainingStimulus, int>{};
    for (final step in workout.structure) {
      if (step.kind != 'work' && step.kind != 'technique') continue;
      final stimulus = _ofIntensityName(step.intensity);
      if (stimulus == null) continue;
      seconds.update(
        stimulus,
        (value) => value + step.seconds,
        ifAbsent: () => step.seconds,
      );
    }
    final intensive = seconds.keys.where((item) => item.intensive);
    final candidates = intensive.isNotEmpty ? intensive : seconds.keys;
    TrainingStimulus? best;
    for (final item in candidates) {
      if (best == null || seconds[item]! > seconds[best]!) best = item;
    }
    if (best == TrainingStimulus.aerobicBase &&
        workout.durationSeconds >= const PlanningPolicy().longSessionSeconds) {
      return TrainingStimulus.longEndurance;
    }
    return best ?? _ofIntensityName(workout.intensity);
  }

  static TrainingStimulus? _ofIntensityName(String? name) => switch (name) {
    'recovery' => regeneration,
    'base' => aerobicBase,
    'tempo' => aerobicCapacity,
    'threshold' => threshold,
    'vo2' => vo2max,
    'maximal' => speed,
    'technique' => technique,
    _ => null,
  };
}

/// Womit trainiert wird. Drinnen und draussen sind für die Planung
/// verschiedene Dinge (Zeit, Wetter, Dauer), für die Schwelle dieselbe
/// Sportart.
enum TrainingModality {
  ercolina('ercolina', 'Ercolina', maxMinutes: 120),
  bikeIndoor('cycling', 'Rad drinnen', maxMinutes: 180),
  bikeOutdoor('cycling', 'Rad draußen', maxMinutes: 360),
  skiSkating('langlauf', 'Langlauf Skating', maxMinutes: 300),
  skiClassic('langlauf', 'Langlauf klassisch', maxMinutes: 300),
  running('running', 'Laufen', maxMinutes: 90);

  const TrainingModality(this.sportKey, this.label, {required this.maxMinutes});

  /// Speicherschlüssel der Sportart, unter dem Schwellen gelten.
  final String sportKey;
  final String label;

  /// Die längste Einheit, die auf diesem Gerät sinnvoll ist.
  final int maxMinutes;
}

enum GoalKind {
  race('Wettkampf'),
  general('Allgemeines Ziel');

  const GoalKind(this.label);
  final String label;
}

/// A trägt die Saison, B und C ordnen sich unter.
enum GoalPriority { a, b, c }

/// Das Ziel, auf das die Saison zuläuft.
class TrainingGoal {
  const TrainingGoal({
    required this.name,
    required this.day,
    required this.modality,
    this.id,
    this.kind = GoalKind.race,
    this.priority = GoalPriority.a,
    this.distanceKm,
    this.targetSeconds,
  });

  final String? id;
  final String name;
  final GoalKind kind;
  final GoalPriority priority;

  /// Null bei einem allgemeinen Ziel ohne Termin.
  final CalendarDay? day;
  final TrainingModality modality;
  final double? distanceKm;
  final int? targetSeconds;

  /// Durchschnittsgeschwindigkeit der Zielzeit.
  double? get targetSpeedKmh => distanceKm == null || targetSeconds == null
      ? null
      : distanceKm! / (targetSeconds! / Duration.secondsPerHour);

  /// Das Ziel, nach dem sich die Planung richtet: das wichtigste, bei
  /// gleicher Priorität das nächste noch kommende.
  static TrainingGoal? primary(
    Iterable<TrainingGoal> goals,
    CalendarDay today,
  ) {
    TrainingGoal? best;
    for (final goal in goals) {
      final day = goal.day;
      if (day != null && day.isBefore(today.addDays(-14))) continue;
      if (best == null ||
          goal.priority.index < best.priority.index ||
          goal.priority == best.priority &&
              day != null &&
              (best.day == null || day.isBefore(best.day!))) {
        best = goal;
      }
    }
    return best;
  }
}

enum SeasonPhase {
  open('Ohne Wettkampfziel'),
  base('Grundlagenentwicklung'),
  build('Aufbau'),
  specific('Wettkampfspezifische Vorbereitung'),
  taper('Tapering'),
  race('Wettkampf'),
  afterRace('Nach dem Wettkampf');

  const SeasonPhase(this.label);
  final String label;
}

/// Wie oft ein Reiz in einer Phase gesetzt werden soll und wie wichtig er ist.
class StimulusRhythm {
  const StimulusRhythm(this.intervalDays, this.weight);

  /// Angestrebter Abstand zwischen zwei wirksamen Reizen.
  final double intervalDays;

  /// Bedeutung in dieser Phase, 0..1.
  final double weight;
}

/// Ausgangswerte der Planung. Alles hier ist überschreibbar und wird vom
/// Athletenprofil verschoben ([IndividualProfile]).
class PlanningPolicy {
  const PlanningPolicy({
    this.minHoursBetweenIntensive = 48,
    this.maxAcuteLoadRatio = 1.5,
    this.minReferenceWeekSeconds = 2 * 3600,
    this.efficiencyDropPercent = 5,
    this.efficiencyLookbackDays = 42,
    this.efficiencyMinReferences = 3,
    this.recoveryRpe = 9,
    this.hardRpe = 8,
    this.hardLactateMmol = 4.0,
    this.recoveryFatiguePercent = -15,
    this.weakBaseRatio = 0.75,
    this.strongBaseRatio = 0.85,
    this.testMaxAgeDays = 70,
    this.profileMaxAgeDays = 365,
    this.minSessionSeconds = 5 * 60,
    this.maxStepUpFactor = 1.5,
    this.minStepUpMinutes = 45,
    this.longSessionSeconds = 100 * 60,
    this.speedMaxIntervalSeconds = 30,
    this.hardMinSeconds = 6 * 60,
    this.taperDays = 10,
    this.specificDays = 35,
    this.buildDays = 49,
    this.taperMaxMinutes = 75,
    this.reinstateMinPriority = 0.45,
    this.meaningfulSeconds = const {
      TrainingStimulus.regeneration: 20 * 60,
      TrainingStimulus.longEndurance: 100 * 60,
      TrainingStimulus.aerobicBase: 30 * 60,
      TrainingStimulus.aerobicCapacity: 20 * 60,
      TrainingStimulus.threshold: 12 * 60,
      TrainingStimulus.vo2max: 6 * 60,
      TrainingStimulus.speed: 60,
      TrainingStimulus.technique: 10 * 60,
    },
    this.rhythms = defaultRhythms,
  });

  final double minHoursBetweenIntensive;

  /// Sieben Tage Trainingsdauer gegen die mittlere Woche der drei Vorwochen.
  /// Schützt vor Sprüngen, ist aber keine «10 % pro Woche»-Regel.
  final double maxAcuteLoadRatio;
  final int minReferenceWeekSeconds;

  /// Leistung je Herzschlag bei vergleichbaren Einheiten: so viel Abfall
  /// gilt als Hinweis auf unvollständige Erholung.
  final double efficiencyDropPercent;
  final int efficiencyLookbackDays;
  final int efficiencyMinReferences;
  final double recoveryRpe;
  final double hardRpe;

  /// Laktat während einer Einheit, ab dem sie als intensiv zählt.
  final double hardLactateMmol;
  final double recoveryFatiguePercent;

  /// LTP1/LTP2 derselben Sportart: darunter gilt die aerobe Basis als
  /// Engpass, darüber als gut entwickelt.
  final double weakBaseRatio;
  final double strongBaseRatio;
  final int testMaxAgeDays;

  /// Älter: die Diagnostik bestimmt den Engpass nicht mehr.
  final int profileMaxAgeDays;

  /// Kürzer ist kein Training (Sensortest, Fehlstart).
  final int minSessionSeconds;

  /// Eine Einheit darf die längste der letzten vier Wochen auf demselben
  /// Gerät höchstens um diesen Faktor übertreffen, mindestens aber
  /// [minStepUpMinutes] dauern.
  final double maxStepUpFactor;
  final int minStepUpMinutes;

  /// Obergrenze für [modality] aus der längsten Einheit derselben Sportart;
  /// null ohne Verlauf (dann ist nichts über die Belastbarkeit bekannt).
  int? stepUpMinutes(int? longestSeconds) => longestSeconds == null
      ? null
      : [
          minStepUpMinutes,
          (longestSeconds / 60 * maxStepUpFactor).round(),
        ].reduce((a, b) => a > b ? a : b);
  final int longSessionSeconds;
  final int speedMaxIntervalSeconds;
  final int hardMinSeconds;
  final int taperDays;
  final int specificDays;
  final int buildDays;
  final int taperMaxMinutes;

  /// Verpasste Reize kommen nur wieder, wenn ihr Bedarf mindestens so hoch ist.
  final double reinstateMinPriority;
  final Map<TrainingStimulus, int> meaningfulSeconds;
  final Map<SeasonPhase, Map<TrainingStimulus, StimulusRhythm>> rhythms;

  StimulusRhythm? rhythm(SeasonPhase phase, TrainingStimulus stimulus) =>
      rhythms[phase]?[stimulus];

  /// Wie sehr die Phase verlangt, in der Wettkampfsportart zu trainieren.
  double specificityPressure(SeasonPhase phase) => switch (phase) {
    SeasonPhase.open || SeasonPhase.afterRace => 0.2,
    SeasonPhase.base => 0.3,
    SeasonPhase.build => 0.6,
    SeasonPhase.specific || SeasonPhase.taper || SeasonPhase.race => 1.0,
  };

  /// Übertrag einer Modalität auf die Zielmodalität, 0..1.
  double transfer(TrainingModality goal, TrainingModality modality) {
    if (goal == modality) return 1.0;
    if (goal.sportKey == modality.sportKey) return 0.85;
    final skiGoal = goal.sportKey == 'langlauf';
    return switch (modality) {
      // Doppelstock ist im klassischen Rennen ein grösserer Teil als im
      // Skating, wo die Beine mehr Arbeit tragen.
      TrainingModality.ercolina =>
        goal == TrainingModality.skiClassic
            ? 0.8
            : skiGoal
            ? 0.7
            : 0.5,
      TrainingModality.skiSkating || TrainingModality.skiClassic => 0.7,
      TrainingModality.running => skiGoal ? 0.6 : 0.5,
      TrainingModality.bikeIndoor || TrainingModality.bikeOutdoor => 0.5,
    };
  }
}

/// Ausgangsrhythmus je Phase: Abstand in Tagen und Gewicht. Trainingslehre
/// als Startpunkt, verschoben durch [IndividualProfile] und den Verlauf.
const Map<SeasonPhase, Map<TrainingStimulus, StimulusRhythm>> defaultRhythms = {
  SeasonPhase.open: {
    TrainingStimulus.aerobicBase: StimulusRhythm(2, 1.0),
    TrainingStimulus.longEndurance: StimulusRhythm(7, 0.7),
    TrainingStimulus.aerobicCapacity: StimulusRhythm(7, 0.6),
    TrainingStimulus.threshold: StimulusRhythm(7, 0.7),
    TrainingStimulus.vo2max: StimulusRhythm(10, 0.5),
    TrainingStimulus.speed: StimulusRhythm(7, 0.4),
    TrainingStimulus.technique: StimulusRhythm(7, 0.5),
  },
  SeasonPhase.base: {
    TrainingStimulus.aerobicBase: StimulusRhythm(2, 1.0),
    TrainingStimulus.longEndurance: StimulusRhythm(7, 0.9),
    TrainingStimulus.aerobicCapacity: StimulusRhythm(7, 0.6),
    TrainingStimulus.threshold: StimulusRhythm(10, 0.5),
    TrainingStimulus.vo2max: StimulusRhythm(14, 0.3),
    TrainingStimulus.speed: StimulusRhythm(7, 0.4),
    TrainingStimulus.technique: StimulusRhythm(7, 0.6),
  },
  SeasonPhase.build: {
    TrainingStimulus.aerobicBase: StimulusRhythm(2, 0.9),
    TrainingStimulus.longEndurance: StimulusRhythm(7, 0.8),
    TrainingStimulus.aerobicCapacity: StimulusRhythm(7, 0.6),
    TrainingStimulus.threshold: StimulusRhythm(5, 0.9),
    TrainingStimulus.vo2max: StimulusRhythm(8, 0.7),
    TrainingStimulus.speed: StimulusRhythm(7, 0.4),
    TrainingStimulus.technique: StimulusRhythm(7, 0.5),
  },
  SeasonPhase.specific: {
    TrainingStimulus.aerobicBase: StimulusRhythm(2, 0.8),
    TrainingStimulus.longEndurance: StimulusRhythm(7, 0.8),
    TrainingStimulus.aerobicCapacity: StimulusRhythm(6, 0.7),
    TrainingStimulus.threshold: StimulusRhythm(5, 0.9),
    TrainingStimulus.vo2max: StimulusRhythm(7, 0.7),
    TrainingStimulus.speed: StimulusRhythm(7, 0.4),
    TrainingStimulus.technique: StimulusRhythm(5, 0.6),
  },
  SeasonPhase.taper: {
    TrainingStimulus.aerobicBase: StimulusRhythm(2, 0.8),
    TrainingStimulus.longEndurance: StimulusRhythm(14, 0.1),
    TrainingStimulus.aerobicCapacity: StimulusRhythm(7, 0.4),
    TrainingStimulus.threshold: StimulusRhythm(6, 0.6),
    TrainingStimulus.vo2max: StimulusRhythm(7, 0.5),
    TrainingStimulus.speed: StimulusRhythm(5, 0.5),
    TrainingStimulus.technique: StimulusRhythm(5, 0.5),
  },
  SeasonPhase.race: {
    TrainingStimulus.aerobicBase: StimulusRhythm(3, 0.5),
    TrainingStimulus.speed: StimulusRhythm(3, 0.3),
    TrainingStimulus.technique: StimulusRhythm(3, 0.3),
  },
  SeasonPhase.afterRace: {
    TrainingStimulus.aerobicBase: StimulusRhythm(3, 0.6),
    TrainingStimulus.technique: StimulusRhythm(7, 0.3),
  },
};

/// Die Saisonphase eines Tages relativ zum Ziel.
class SeasonPosition {
  const SeasonPosition({required this.phase, this.daysToGoal});

  final SeasonPhase phase;
  final int? daysToGoal;

  static SeasonPosition of(
    TrainingGoal? goal,
    CalendarDay day, {
    PlanningPolicy policy = const PlanningPolicy(),
  }) {
    final goalDay = goal?.day;
    if (goalDay == null) return const SeasonPosition(phase: SeasonPhase.open);
    final days = day.daysUntil(goalDay);
    final phase = days < 0
        ? (days >= -14 ? SeasonPhase.afterRace : SeasonPhase.open)
        : days == 0
        ? SeasonPhase.race
        : days <= policy.taperDays
        ? SeasonPhase.taper
        : days <= policy.taperDays + policy.specificDays
        ? SeasonPhase.specific
        : days <= policy.taperDays + policy.specificDays + policy.buildDays
        ? SeasonPhase.build
        : SeasonPhase.base;
    return SeasonPosition(phase: phase, daysToGoal: days);
  }
}

/// Wie viel Zeit an einem Tag zur Verfügung steht und womit. Eine Grenze,
/// keine Vorgabe: 60 min Ercolina möglich heisst nicht, Ercolina zu fahren.
class DayAvailability {
  const DayAvailability({
    required this.day,
    required this.minutes,
    required this.modalities,
    this.longDay = false,
  });

  final CalendarDay day;
  final int minutes;
  final Set<TrainingModality> modalities;

  /// Bevorzugter Tag für eine lange Einheit.
  final bool longDay;
}

/// Ein Wochentag der Verfügbarkeit, 1 = Montag bis 7 = Sonntag.
class WeekdayAvailability {
  const WeekdayAvailability({
    required this.weekday,
    required this.minutes,
    required this.modalities,
    this.restDay = false,
    this.longDay = false,
  });

  final int weekday;
  final int minutes;
  final Set<TrainingModality> modalities;

  /// Kein Training möglich.
  final bool restDay;
  final bool longDay;
}

class WeeklyAvailability {
  const WeeklyAvailability(this.days);

  /// Ohne Angaben: jeden Tag eine Stunde auf der Ercolina.
  static final WeeklyAvailability fallback = WeeklyAvailability([
    for (var weekday = 1; weekday <= 7; weekday++)
      WeekdayAvailability(
        weekday: weekday,
        minutes: 60,
        modalities: {TrainingModality.ercolina},
      ),
  ]);

  final List<WeekdayAvailability> days;

  WeekdayAvailability weekday(int weekday) =>
      days.where((item) => item.weekday == weekday).firstOrNull ??
      WeekdayAvailability(weekday: weekday, minutes: 0, modalities: const {});

  DayAvailability on(CalendarDay day) {
    final entry = weekday(DateTime.utc(day.year, day.month, day.day).weekday);
    return DayAvailability(
      day: day,
      minutes: entry.restDay ? 0 : entry.minutes,
      modalities: entry.restDay ? const {} : entry.modalities,
      longDay: entry.longDay,
    );
  }
}
