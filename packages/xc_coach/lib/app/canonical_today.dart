/// Die **eine** heutige Trainingsentscheidung.
///
/// ## Warum es diese Stelle gibt
///
/// Bis zum 05.10.2026 entstand die Antwort auf «was trainiere ich heute»
/// zweimal, in zwei getrennten Motoren:
///
/// * `planning/` — StimulusLedger → eigener Need → `WorkoutSelector` über den
///   Katalog → `TodayPlanning`. Sichtbar in HEUTE und in der Ercolina-Karte.
/// * `workout_selection/` — `XCAthleteState` → [TrainingNeedEngine] →
///   [DailyDecisionEngine] → [DailyCoachingDecision]. Sichtbar in PLAN.
///
/// Im Replay gegen den echten Datenstand sagte der erste «Rad drinnen
/// 180 min, lange Grundlage», der zweite am selben Tag für denselben
/// Athleten «Ercolina-Doppelstock 60 min, aerobe Basis». Zwei Oberflächen,
/// zwei Wahrheiten, kein Hinweis darauf, welche gilt.
///
/// Seitdem ist dieser Pfad kanonisch, und er ist der einzige:
///
///     NormalizedSession → XCAthleteState → TrainingNeedEngine
///                       → DailyDecisionEngine → DailyCoachingDecision
///
/// ## Was diese Klasse *nicht* ist
///
/// Kein dritter Planer. Sie entscheidet nichts: Sie sammelt die Eingaben,
/// ruft **einmal** [DailyDecisionEngine.decide] und gibt allen Oberflächen
/// dasselbe Ergebnis — dieselbe Instanz. Jede Zeile Auswahl- oder
/// Dosislogik gehört in die Engine, nicht hierher.
library;

import '../database/coach_storage_repository.dart';
import '../database/training_goal_repository.dart';
import '../database/training_plan_repository.dart';
import '../domain/training_plan.dart';
import '../domain/xc_modality.dart';
import '../intelligence/female_athlete/female_athlete_models.dart';
// Nur das Modalitaets-Enum des Plans, nicht dessen DayAvailability: Es gibt
// zwei Typen dieses Namens, und kanonisch ist der aus
// `workout_selection/availability_context.dart`.
import '../intelligence/planning/planning_models.dart' show TrainingModality;
import '../intelligence/training_need/training_need_engine.dart';
import '../intelligence/training_need/training_need_result.dart';
import '../intelligence/workout_selection/availability_context.dart';
import '../intelligence/workout_selection/daily_coaching_decision.dart';
import '../intelligence/workout_selection/daily_decision_engine.dart';
import '../intelligence/xc_athlete_state/xc_athlete_state.dart';
import 'athlete_state_service.dart';

/// Die heutige Entscheidung samt der Eingaben, aus denen sie entstand.
///
/// Die Eingaben gehören dazu, weil eine Entscheidung ohne sie nicht erklärbar
/// ist — und weil HEUTE sie braucht, um nach einer Änderung der Verfügbarkeit
/// mit **derselben** Engine neu zu rechnen.
class CanonicalToday {
  const CanonicalToday({
    required this.state,
    required this.needs,
    required this.availability,
    required this.decision,
    this.femaleContext,
    this.plannedWorkout,
  });

  final XCAthleteState state;
  final TrainingNeedResult needs;
  final DayAvailability availability;

  /// Die Absicht des Plans für heute. Sie geht als `plannedWorkout` in die
  /// Engine ein: Der Plan sagt, was vorgesehen war; die Engine entscheidet,
  /// was heute daraus wird.
  final PlannedWorkout? plannedWorkout;
  final FemaleAthleteContext? femaleContext;

  /// Die eine Entscheidung. Alle Oberflächen zeigen dieses Objekt.
  final DailyCoachingDecision decision;

  /// Ob die Entscheidung von der Planabsicht abweicht — der Fall, der
  /// erklärbar sein muss: «Plan wollte A, heute entscheidet GIULIA B.»
  /// Abweichung heisst **Modalitaet oder Dosis**. Nur die Sportart zu
  /// vergleichen uebersieht den haeufigsten Fall: Der Plan sah drei Stunden
  /// Laufen vor, die Engine verschreibt fuenfundvierzig Minuten Laufen —
  /// dieselbe Form, eine andere Dosis, und genau das ist die Entscheidung,
  /// die begruendet werden muss.
  String? get dayNote {
    final notes = [if (planDivergence case final v?) v, if (availability.assumption case final v?) v];
    return notes.isEmpty ? null : notes.join(' ');
  }

  bool get divergesFromPlan => planDivergence != null;

  /// Was genau abweicht, oder null bei Uebereinstimmung.
  String? get planDivergence {
    final planned = plannedWorkout;
    if (planned == null) return null;
    final prescribed = decision.prescribedWorkout;
    if (prescribed == null) {
      return 'Geplant war ${planned.goal}; heute steht Erholung an.';
    }
    final plannedMinutes = (planned.durationSeconds / 60).round();
    final sameModality = _sameModality(planned.sport, prescribed.modality);
    final sameDose = plannedMinutes == prescribed.totalDurationMinutes;
    if (sameModality && sameDose) return null;
    if (sameModality) {
      return 'Geplant waren $plannedMinutes min, verschrieben sind '
          '${prescribed.totalDurationMinutes} min.';
    }
    return 'Geplant war ${planned.sport}, verschrieben ist '
        '${prescribed.modality.label} '
        '(${prescribed.totalDurationMinutes} min).';
  }

  /// Ob die Planabsicht und die verschriebene Modalität dieselbe Trainingsform
  /// meinen.
  ///
  /// Der Plan speichert den Sportschlüssel von [TrainingModality]
  /// (`ercolina`, `langlauf`, `running`, `cycling`), die Entscheidung eine
  /// [XcModality] (`ercolina_double_poling`, `ski_skating`, …). Ein
  /// Zeichenvergleich meldete deshalb «geplant ercolina, verschrieben
  /// ercolinaDoublePoling» als Abweichung — dieselbe Einheit, zwei
  /// Schreibweisen. Eine Abweichung, die es nicht gibt, ist schlimmer als
  /// keine Erklärung.
  static bool _sameModality(String plannedSport, XcModality prescribed) =>
      switch (plannedSport.toLowerCase()) {
        'ercolina' => prescribed == XcModality.ercolinaDoublePoling,
        'running' => prescribed == XcModality.running,
        'cycling' => prescribed == XcModality.cycling,
        'langlauf' => prescribed.isSkiing && !prescribed.isErcolina,
        // Unbekannter Schlüssel: nicht behaupten, es passe.
        _ => plannedSport.toLowerCase() == prescribed.key,
      };
}

/// Rechnet die heutige Entscheidung genau einmal je Athlet, Tag und
/// Datenstand — und persistiert sie einmal.
class CanonicalTodayService {
  CanonicalTodayService({
    required this.stateService,
    required this.goalRepository,
    required this.planRepository,
    this.storage,
    this.persistDecisions = true,
    this.engine = const DailyDecisionEngine(),
    this.needEngine = const TrainingNeedEngine(),
  });

  final AthleteStateService stateService;
  final SqliteTrainingGoalRepository goalRepository;
  final SqliteTrainingPlanRepository planRepository;
  final SqliteCoachStorageRepository? storage;
  final bool persistDecisions;
  final DailyDecisionEngine engine;
  final TrainingNeedEngine needEngine;

  final Map<String, CanonicalToday> _memo = {};

  /// Die heutige Entscheidung für [athleteId].
  ///
  /// Mehrfache Aufrufe am selben Tag mit demselben Datenstand liefern
  /// dieselbe Instanz — darauf beruht, dass HEUTE und PLAN dasselbe zeigen.
  CanonicalToday of(String athleteId, {DateTime? now}) {
    final moment = now ?? DateTime.now();
    final day = CalendarDay.ofLocal(moment.toLocal());
    final key = '$athleteId|${day.key}';
    final cached = _memo[key];
    if (cached != null) return cached;
    final built = _build(athleteId, moment, day);
    _persist(athleteId, built, moment);
    _memo[key] = built;
    return built;
  }

  void invalidate(String athleteId) =>
      _memo.removeWhere((key, _) => key.startsWith('$athleteId|'));

  CanonicalToday _build(String athleteId, DateTime moment, CalendarDay day) {
    final nowUtc = moment.toUtc();
    final state = stateService.buildCurrentState(
      athleteId: athleteId,
      asOf: nowUtc,
    );
    final needs = needEngine.evaluate(state: state);
    final availability = _availabilityOf(athleteId, day, nowUtc);
    final planned = planRepository
        .planOf(athleteId, from: day, to: day)
        .workouts.where((w) => w.isOpen)
        .firstOrNull;
    final femaleContext = stateService.buildFemaleAthleteContext(
      athleteId: athleteId,
      asOf: nowUtc,
    );
    final decision = engine.decide(
      state: state,
      needResult: needs,
      availability: availability,
      userOverride: storage?.latestUserOverride(athleteId, onDay:moment),
      femaleContext: femaleContext,
      plannedWorkout: planned,
    );
    return CanonicalToday(
      state: state,
      needs: needs,
      availability: availability,
      plannedWorkout: planned,
      femaleContext: femaleContext,
      decision: decision,
    );
  }

  /// Verfügbarkeit heisst: wie viel Zeit **höchstens** da ist und welche
  /// Modalitäten praktisch in Frage kommen. Nicht: diese Zeit ausfüllen.
  DayAvailability _availabilityOf(
    String athleteId,
    CalendarDay day,
    DateTime nowUtc,
  ) {
    final weekly = goalRepository.availabilityOf(athleteId);
    final dayDef = weekly?.on(day);
    final allowed = <XcModality>{
      for (final tm in dayDef?.modalities ?? const <TrainingModality>{})
        ...switch (tm) {
          TrainingModality.skiSkating => {XcModality.skiSkating},
          TrainingModality.skiClassic => {XcModality.skiClassic},
          TrainingModality.ercolina => {XcModality.ercolinaDoublePoling},
          TrainingModality.running => {XcModality.running},
          TrainingModality.bikeIndoor ||
          TrainingModality.bikeOutdoor => {XcModality.cycling},
        },
    };
    if (allowed.isEmpty) {
      allowed.addAll(const {
        XcModality.skiSkating,
        XcModality.skiClassic,
      });
    }
    final hasSnow =
        allowed.contains(XcModality.skiSkating) ||
        allowed.contains(XcModality.skiClassic);
    final hasErcolina = allowed.contains(XcModality.ercolinaDoublePoling);
    return DayAvailability(
      date: nowUtc,
      availableMinutes: dayDef?.minutes ?? 60,
      assumption: dayDef == null
          ? 'Vorschlag für einen Tag mit Loipe und bis zu 60 Minuten Zeit. Deine Verfügbarkeit ist noch offen.'
          : null,
      allowedModalities: allowed,
      environment: hasSnow
          ? TrainingEnvironment.outdoorSnow
          : (hasErcolina
                ? TrainingEnvironment.indoorErcolina
                : TrainingEnvironment.outdoorTrailOrRoad),
      hasSnow: hasSnow,
      hasErcolina: hasErcolina,
    );
  }

  void _persist(String athleteId, CanonicalToday today, DateTime moment) {
    final store = storage;
    if (store == null || !persistDecisions) return;
    store.saveDailyDecision(
      athleteId: athleteId,
      decision: today.decision,
      decidedAtUtcUs: moment.toUtc().microsecondsSinceEpoch,
    );
  }
}
