/// Der tägliche Regelkreis:
///
/// ```text
/// Plan → Training → Messdaten → Bewertung → Athletenzustand → nächster Plan
/// ```
///
/// [DailyPlanner] ordnet die absolvierten Einheiten in Reize ein, bewertet
/// Bereitschaft und Bedarf, bildet aus der Bibliothek die zulässigen
/// Möglichkeiten und lässt einen [RecommendationChooser] daraus wählen. Die
/// Wahl wird noch einmal geprüft: Auch ein Sprachmodell kann nur zwischen
/// zulässigen Einheiten entscheiden, nie eine eigene Belastung erfinden.
///
/// Ein verpasster Reiz wird nicht automatisch nachgeholt. Ob er noch fällig
/// ist, ergibt sich aus demselben Bedarf wie jeder andere Reiz.
library;

import '../../domain/coach_decision.dart';
import '../../domain/training_plan.dart';
import '../athlete_state_models.dart';
import '../models.dart';
import 'planning_models.dart';
import 'stimulus_ledger.dart';
import 'training_need.dart';
import 'workout_catalogue.dart';

class PlanningInput {
  const PlanningInput({
    required this.athleteId,
    required this.nowUtcUs,
    required this.today,
    required this.sessions,
    required this.tests,
    this.upcoming = const [],
    this.goal,
    this.observations = const [],
    this.plan,
    this.athleteState,
  });

  final String athleteId;
  final int nowUtcUs;
  final DayAvailability today;

  /// Verfügbarkeit der folgenden Tage, ab morgen.
  final List<DayAvailability> upcoming;
  final TrainingGoal? goal;
  final List<IntelligenceSession> sessions;
  final List<IntelligenceTest> tests;
  final List<IntelligenceObservation> observations;
  final TrainingPlan? plan;

  /// Der persistierte Athletenzustand, wenn er vorliegt: Seine Datenqualität
  /// geht als Hinweis in die Empfehlung ein.
  final AthleteState? athleteState;
}

enum PlanVerdict {
  /// Für heute war nichts geplant.
  none,

  /// Die geplante Einheit bleibt.
  kept,

  /// Die geplante Einheit wird ersetzt.
  changed,
}

/// Was aus einer verpassten Einheit wird.
class MissedWorkoutVerdict {
  const MissedWorkoutVerdict({
    required this.workout,
    required this.stimulus,
    required this.stillDue,
    required this.reason,
  });

  final PlannedWorkout workout;
  final TrainingStimulus? stimulus;

  /// Der Reiz ist weiterhin fällig und fliesst in die nächsten Tage ein –
  /// als Bedarf, nicht als Pflichttermin.
  final bool stillDue;
  final String reason;
}

class DailyPlanningContext {
  const DailyPlanningContext({
    required this.season,
    required this.readiness,
    required this.profile,
    required this.needs,
    this.plannedToday,
  });

  final SeasonPosition season;
  final ReadinessAssessment readiness;
  final IndividualProfile profile;
  final List<TrainingNeed> needs;
  final PlannedWorkout? plannedToday;
}

/// Wählt aus den zulässigen Möglichkeiten. Die deterministische Fassung
/// nimmt die höchstbewertete; ein Sprachmodell darf anders abwägen, aber nur
/// innerhalb von [admissible].
abstract interface class RecommendationChooser {
  WorkoutOption? choose(
    List<WorkoutOption> admissible,
    DailyPlanningContext context,
  );
}

class HighestScoreChooser implements RecommendationChooser {
  const HighestScoreChooser();

  @override
  WorkoutOption? choose(
    List<WorkoutOption> admissible,
    DailyPlanningContext context,
  ) => admissible.firstOrNull;
}

class DailyRecommendation {
  const DailyRecommendation({
    required this.day,
    required this.context,
    required this.ledger,
    required this.chosen,
    required this.alternatives,
    required this.blocked,
    required this.planVerdict,
    required this.missed,
    required this.explanation,
    required this.facts,
    required this.warnings,
    this.changeReasons = const [],
  });

  final CalendarDay day;
  final DailyPlanningContext context;
  final StimulusLedger ledger;

  /// Null: heute keine zulässige Einheit – Ruhetag.
  final WorkoutOption? chosen;

  /// Weitere zulässige Einheiten, nach Bewertung.
  final List<WorkoutOption> alternatives;

  /// Hoch bewertete, aber unzulässige Einheiten mit ihrem Grund.
  final List<(WorkoutOption, SafetyVerdict)> blocked;
  final PlanVerdict planVerdict;
  final List<MissedWorkoutVerdict> missed;

  /// Das Warum, Satz für Satz, für den Coach und die Oberfläche.
  final List<String> explanation;
  final List<CoachFactRef> facts;
  final List<String> warnings;

  /// Warum die geplante Einheit ersetzt wurde ([PlanVerdict.changed]).
  final List<PlanningReason> changeReasons;

  /// Alles, was der Athlet heute wählen darf: die Empfehlung zuerst.
  List<WorkoutOption> get admissible => [?chosen, ...alternatives];

  SeasonPosition get season => context.season;
  ReadinessAssessment get readiness => context.readiness;
  List<TrainingNeed> get needs => context.needs;

  /// Eine zulässige Einheit (ohne [option]: die gewählte) als Plan-Eintrag.
  /// Die Struktur trägt nur relative Intensitäten; Watt entstehen erst beim
  /// Start.
  PlannedWorkout? toPlannedWorkout({
    required String id,
    required String organizationId,
    required String athleteId,
    required int nowUtcUs,
    WorkoutOption? option,
    String? createdByUserId,
  }) {
    option ??= chosen;
    if (option == null) return null;
    final blueprint = option.blueprint;
    return PlannedWorkout(
      id: id,
      organizationId: organizationId,
      athleteId: athleteId,
      day: day,
      sport: option.modality.sportKey,
      goal: option.title,
      durationSeconds: blueprint.duration.inSeconds,
      intensity: option.stimulus.libraryIntensity.name,
      blueprintId: option.template.shape == TemplateShape.fixed
          ? blueprint.id
          : null,
      structure: [
        for (final step in blueprint.steps)
          PlannedStep(
            kind: step.kind.name,
            seconds: step.seconds,
            intensity: step.intensity.name,
          ),
      ],
      createdAtUtcUs: nowUtcUs,
      updatedAtUtcUs: nowUtcUs,
      createdByUserId: createdByUserId,
    );
  }

  /// Die nachvollziehbare Entscheidung zum neuen Plan-Eintrag.
  CoachDecision decision({
    required String id,
    required String organizationId,
    required String athleteId,
    required List<String> plannedWorkoutIds,
    required int nowUtcUs,
    WorkoutOption? option,
  }) {
    option ??= chosen;
    final alternative = option != null && !identical(option, chosen);
    return CoachDecision(
      id: id,
      organizationId: organizationId,
      athleteId: athleteId,
      decidedAtUtcUs: nowUtcUs,
      type: CoachDecisionType.planned,
      author: CoachDecisionAuthor.giulia,
      plannedWorkoutIds: plannedWorkoutIds,
      change: {
        'stimulus': option?.stimulus.name,
        'template': option?.template.id,
        'modality': option?.modality.name,
        'minutes': option?.minutes,
        'alternative': alternative,
        if (planVerdict == PlanVerdict.changed)
          'replaces': context.plannedToday?.id,
      },
      reason: [
        if (alternative)
          'Vom Athleten aus den zulässigen Alternativen gewählt.',
        ...explanation,
      ].join(' '),
      facts: facts,
    );
  }
}

class DailyPlanner {
  const DailyPlanner({
    this.policy = const PlanningPolicy(),
    this.catalogue = workoutCatalogue,
  });

  final PlanningPolicy policy;
  final List<WorkoutTemplate> catalogue;

  DailyRecommendation recommend(
    PlanningInput input, {
    RecommendationChooser chooser = const HighestScoreChooser(),
  }) {
    final plan = input.plan;
    final day = input.today.day;
    final ledger = StimulusLedger.build(
      sessions: input.sessions,
      tests: input.tests,
      nowUtcUs: input.nowUtcUs,
      policy: policy,
      plannedStimulusBySession: {
        for (final workout in plan?.workouts ?? const <PlannedWorkout>[])
          ?workout.sessionId: ?TrainingStimulus.ofPlanned(workout),
      },
      observations: input.observations,
    );
    final season = SeasonPosition.of(input.goal, day, policy: policy);
    final profile = IndividualProfile.fromTests(
      tests: input.tests,
      nowUtcUs: input.nowUtcUs,
      goal: input.goal,
      policy: policy,
    );
    final readiness = ReadinessGate(policy: policy).assess(
      ledger: ledger,
      sessions: input.sessions,
      observations: input.observations,
      nowUtcUs: input.nowUtcUs,
    );
    final needs = TrainingNeedEngine(policy: policy).evaluate(
      ledger: ledger,
      season: season,
      profile: profile,
      readiness: readiness,
    );
    final options = WorkoutSelector(catalogue: catalogue, policy: policy)
        .options(
          needs: needs,
          today: input.today,
          upcoming: input.upcoming,
          season: season,
          goal: input.goal,
          ledger: ledger,
        );
    final calibrated = {
      for (final test in input.tests)
        if (test.threshold('lt2') != null) test.sportKey,
    };
    final safety = PlanSafetyEngine(policy: policy);
    SafetyVerdict check(WorkoutOption option) => safety.check(
      option,
      readiness: readiness,
      ledger: ledger,
      today: input.today,
      season: season,
      calibratedSports: calibrated,
    );
    final admissible = <WorkoutOption>[];
    final blocked = <(WorkoutOption, SafetyVerdict)>[];
    final warnings = <String>{};
    for (final option in options) {
      final verdict = check(option);
      if (verdict.admissible) {
        admissible.add(option);
      } else {
        blocked.add((option, verdict));
      }
    }

    final plannedToday = plan?.workouts
        .where((workout) => workout.day == day && workout.isOpen)
        .firstOrNull;
    final context = DailyPlanningContext(
      season: season,
      readiness: readiness,
      profile: profile,
      needs: needs,
      plannedToday: plannedToday,
    );

    final explanation = <String>[];
    final facts = <CoachFactRef>[];
    void addFacts(Iterable<PlanningReason> reasons) {
      for (final reason in reasons) {
        for (final fact in reason.facts) {
          if (!facts.any(
            (item) =>
                item.kind == fact.kind &&
                item.id == fact.id &&
                item.label == fact.label,
          )) {
            facts.add(fact);
          }
        }
      }
    }

    explanation.add(_seasonLine(season, input.goal));

    WorkoutOption? chosen;
    var verdict = PlanVerdict.none;
    var changeReasons = const <PlanningReason>[];
    final plannedStimulus = plannedToday == null
        ? null
        : TrainingStimulus.ofPlanned(plannedToday);
    if (plannedToday != null) {
      final keep = admissible
          .where(
            (option) =>
                option.stimulus == plannedStimulus &&
                option.modality.sportKey == plannedToday.sport,
          )
          .firstOrNull;
      final top = admissible.firstOrNull;
      if (keep != null &&
          (top == null || keep.need.priority >= 0.5 * top.need.priority)) {
        chosen = keep;
        verdict = PlanVerdict.kept;
        explanation.add(
          'Geplant ist ${plannedToday.goal}; der Reiz ist weiterhin '
          'sinnvoll, der Plan bleibt.',
        );
        addFacts(keep.reasons);
      } else {
        verdict = PlanVerdict.changed;
        final reasons = _whyNot(plannedStimulus, blocked, needs, top);
        changeReasons = reasons;
        addFacts(reasons);
        explanation.add(
          'Eigentlich war heute ${plannedToday.goal} vorgesehen. '
          '${reasons.map((item) => item.text).join(' ')}',
        );
      }
    }

    if (chosen == null) {
      final picked = chooser.choose(List.unmodifiable(admissible), context);
      if (picked != null) {
        final recheck = check(picked);
        if (recheck.admissible) {
          chosen = picked;
        } else {
          warnings.add(
            'Die gewählte Einheit «${picked.title}» war nicht zulässig '
            '(${recheck.violations.map((item) => item.text).join(' ')}); '
            'GIULIA nimmt die bestbewertete zulässige.',
          );
          chosen = admissible.firstOrNull;
        }
      }
      if (chosen != null) {
        final lead = verdict == PlanVerdict.changed
            ? 'Deshalb ${plannedStimulus == chosen.stimulus ? 'passe ich die Einheit an' : 'verschiebe ich den ${plannedStimulus?.label ?? 'geplanten Reiz'}'} und plane heute'
            : 'Heute:';
        explanation.add(
          '$lead ${chosen.minutes} min ${chosen.title} '
          '(${chosen.stimulus.label}).',
        );
        if (chosen.need.reasons.firstOrNull case final reason?) {
          explanation.add(reason.text);
        } else if (blocked.firstOrNull case final other?) {
          explanation.add(
            'Mehr ist heute nicht zulässig: '
            '${other.$2.violations.first.text}',
          );
          addFacts(other.$2.violations);
        }
        for (final reason in chosen.reasons.skip(chosen.need.reasons.length)) {
          explanation.add(reason.text);
        }
        addFacts(chosen.reasons);
      } else {
        explanation.add('Heute passt keine Einheit in die Vorgaben: Ruhetag.');
        addFacts(blocked.expand((item) => item.$2.violations).take(3));
      }
    }

    if (readiness.level == ReadinessLevel.limited ||
        readiness.level == ReadinessLevel.recovery) {
      addFacts(readiness.reasons);
      if (verdict != PlanVerdict.changed) {
        explanation.add(readiness.reasons.map((item) => item.text).join(' '));
      }
    }
    for (final reason in profile.reasons) {
      if (chosen != null && profile.weight(chosen.stimulus) != 1.0) continue;
      explanation.add(reason.text);
    }
    addFacts(profile.reasons);
    if (chosen != null) warnings.addAll(check(chosen).warnings);
    if (facts.isEmpty) {
      facts.add(
        CoachFactRef(
          kind: 'season',
          id: season.phase.name,
          label: 'Saisonphase',
          value: season.daysToGoal,
          unit: season.daysToGoal == null ? null : 'd',
        ),
      );
    }
    if (ledger.durationSeconds(28) > 0 && ledger.unclassifiedShare(28) > 0.5) {
      warnings.add(
        'Deine letzten Einheiten kann GIULIA ohne passende Schwelle keinem '
        'Trainingsbereich zuordnen. Ein Stufentest oder Einheiten aus diesen '
        'Empfehlungen machen die Planung genauer.',
      );
    } else if (profile.testDue != null && profile.testId == null) {
      warnings.add(
        'Eine aktuelle Leistungsdiagnostik würde die Planung schärfen.',
      );
    }
    final quality = input.athleteState?.dataQuality;
    if (quality != null &&
        (quality.confidence == IntelligenceConfidence.low ||
            quality.confidence == IntelligenceConfidence.insufficient)) {
      warnings.add(
        'Die Datengrundlage ist noch dünn'
        '${quality.missing.isEmpty ? '' : ': es fehlen ${quality.missing.take(2).join(' und ')}'}.',
      );
    }

    return DailyRecommendation(
      day: day,
      context: context,
      ledger: ledger,
      chosen: chosen,
      alternatives: List.unmodifiable(
        admissible.where((option) => !identical(option, chosen)).take(3),
      ),
      blocked: List.unmodifiable(blocked.take(4)),
      planVerdict: verdict,
      missed: _missed(plan, day, ledger, needs),
      explanation: List.unmodifiable(explanation),
      facts: List.unmodifiable(facts),
      warnings: List.unmodifiable(warnings),
      changeReasons: List.unmodifiable(changeReasons),
    );
  }

  String _seasonLine(SeasonPosition season, TrainingGoal? goal) =>
      goal == null || season.daysToGoal == null
      ? 'Phase: ${season.phase.label}.'
      : season.daysToGoal! >= 0
      ? 'Phase: ${season.phase.label}, noch ${season.daysToGoal} Tage bis '
            '${goal.name}.'
      : 'Phase: ${season.phase.label}.';

  /// Warum der geplante Reiz heute nicht gesetzt wird.
  List<PlanningReason> _whyNot(
    TrainingStimulus? planned,
    List<(WorkoutOption, SafetyVerdict)> blocked,
    List<TrainingNeed> needs,
    WorkoutOption? top,
  ) {
    final rejected = blocked
        .where((item) => item.$1.stimulus == planned)
        .firstOrNull;
    if (rejected != null) return rejected.$2.violations;
    final need = needs.where((item) => item.stimulus == planned).firstOrNull;
    if (need != null && need.blocked) return need.blockedBy;
    if (planned == null) {
      return const [
        PlanningReason('Die geplante Einheit lässt sich keinem Reiz zuordnen.'),
      ];
    }
    if (top == null) {
      return [
        PlanningReason(
          'Für ${planned.label} passt heute keine Einheit in Zeit und Geräte.',
        ),
      ];
    }
    return [
      PlanningReason(
        '${top.stimulus.label} ist heute dringlicher als ${planned.label}.',
        top.need.reasons.expand((item) => item.facts).toList(),
      ),
    ];
  }

  List<MissedWorkoutVerdict> _missed(
    TrainingPlan? plan,
    CalendarDay today,
    StimulusLedger ledger,
    List<TrainingNeed> needs,
  ) {
    if (plan == null) return const [];
    final result = <MissedWorkoutVerdict>[];
    for (final workout in plan.workouts) {
      if (!workout.isOpen || workout.isStarted) continue;
      if (!workout.day.isBefore(today) || workout.day.daysUntil(today) > 14) {
        continue;
      }
      final stimulus = TrainingStimulus.ofPlanned(workout);
      if (stimulus == null) {
        result.add(
          MissedWorkoutVerdict(
            workout: workout,
            stimulus: null,
            stillDue: false,
            reason: 'Ohne erkennbaren Reiz: verfällt.',
          ),
        );
        continue;
      }
      final need = needs.where((item) => item.stimulus == stimulus).firstOrNull;
      final last = ledger.lastMeaningful(stimulus);
      final plannedDayUs = DateTime.utc(
        workout.day.year,
        workout.day.month,
        workout.day.day,
      ).microsecondsSinceEpoch;
      if (last != null && last.startedAtUtcUs >= plannedDayUs) {
        result.add(
          MissedWorkoutVerdict(
            workout: workout,
            stimulus: stimulus,
            stillDue: false,
            reason:
                '${stimulus.label} wurde inzwischen durch eine andere '
                'Einheit gesetzt: verfällt.',
          ),
        );
      } else if (need == null || need.priority < policy.reinstateMinPriority) {
        result.add(
          MissedWorkoutVerdict(
            workout: workout,
            stimulus: stimulus,
            stillDue: false,
            reason:
                '${stimulus.label} ist in dieser Phase nicht mehr dringlich: '
                'verfällt, statt nachgeholt zu werden.',
          ),
        );
      } else if (needs
              .where((item) => !item.blocked)
              .take(3)
              .every((item) => item.stimulus != stimulus) &&
          !need.blocked) {
        result.add(
          MissedWorkoutVerdict(
            workout: workout,
            stimulus: stimulus,
            stillDue: false,
            reason:
                '${stimulus.label} verfällt: Andere Reize sind gerade '
                'wichtiger.',
          ),
        );
      } else {
        result.add(
          MissedWorkoutVerdict(
            workout: workout,
            stimulus: stimulus,
            stillDue: true,
            reason:
                '${stimulus.label} bleibt fällig und wird eingeplant, sobald '
                'Erholung und Zeit es zulassen – nicht zwingend morgen.',
          ),
        );
      }
    }
    return List.unmodifiable(result);
  }
}
