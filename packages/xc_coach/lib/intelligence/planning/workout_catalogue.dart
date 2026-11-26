/// Geprüfte Einheiten, aus denen der Planer wählt – er erfindet keine.
///
/// Jede Vorlage setzt genau einen Reiz und darf nur innerhalb ihrer Grenzen
/// skaliert werden: Wiederholungen bei Intervallen, Dauer bei Dauereinheiten.
/// Die Intensitäten sind die relativen Bereiche der Bibliothek; Watt entstehen
/// erst beim Start aus dem Zonenmodell bzw. der Schwelle des Athleten.
library;

import '../../workout_engine/workout_engine.dart';
import '../../workout_engine/workout_library.dart';
import 'planning_models.dart';
import 'stimulus_ledger.dart';
import 'training_need.dart';

enum TemplateShape { continuous, intervals, fixed }

class WorkoutTemplate {
  const WorkoutTemplate({
    required this.id,
    required this.name,
    required this.stimulus,
    required this.purpose,
    required this.modalities,
    required this.shape,
    this.minMinutes = 20,
    this.maxMinutes = 120,
    this.preferredMinutes,
    this.workSeconds = 0,
    this.restSeconds = 0,
    this.minReps = 1,
    this.maxReps = 1,
    this.blueprintId,
    this.workLabel,
  });

  final String id;
  final String name;

  /// Kurzname des Arbeitsteils in der Struktur, z. B. «5 × 6 min EB».
  final String? workLabel;
  final TrainingStimulus stimulus;
  final String purpose;
  final Set<TrainingModality> modalities;
  final TemplateShape shape;
  final int minMinutes;
  final int maxMinutes;

  /// Dauer, die ohne Not nicht überschritten wird, auch wenn mehr Zeit da ist.
  final int? preferredMinutes;
  final int workSeconds;
  final int restSeconds;
  final int minReps;
  final int maxReps;

  /// [TemplateShape.fixed]: der unveränderte Bibliotheksbaustein.
  final String? blueprintId;

  static const _warmupSeconds = 600;
  static const _cooldownSeconds = 480;

  /// Die Einheit für höchstens [minutes] Minuten, oder null, wenn sie darin
  /// nicht sinnvoll Platz hat.
  WorkoutBlueprint? build(int minutes, TrainingModality modality) {
    final limit = [
      minutes,
      maxMinutes,
      modality.maxMinutes,
    ].reduce((a, b) => a < b ? a : b);
    switch (shape) {
      case TemplateShape.fixed:
        final blueprint = workoutLibrary
            .where((item) => item.id == blueprintId)
            .firstOrNull;
        if (blueprint == null || blueprint.duration.inMinutes > limit) {
          return null;
        }
        return blueprint;
      case TemplateShape.continuous:
        final chosen = preferredMinutes == null
            ? limit
            : (limit < preferredMinutes! ? limit : preferredMinutes!);
        if (chosen < minMinutes) return null;
        return WorkoutBlueprint(
          id: '$id-${chosen}m',
          name: name,
          category: _category,
          purpose: purpose,
          steps: [
            BlueprintStep(
              kind: stimulus == TrainingStimulus.technique
                  ? WorkoutStepKind.technique
                  : WorkoutStepKind.work,
              intensity: stimulus.libraryIntensity,
              seconds: chosen * 60,
            ),
          ],
        );
      case TemplateShape.intervals:
        final available =
            limit * 60 - _warmupSeconds - _cooldownSeconds + restSeconds;
        var reps = available ~/ (workSeconds + restSeconds);
        if (reps < minReps) return null;
        if (reps > maxReps) reps = maxReps;
        final work = BlueprintStep(
          kind: WorkoutStepKind.work,
          intensity: stimulus.libraryIntensity,
          seconds: workSeconds,
        );
        final rest = BlueprintStep(
          kind: WorkoutStepKind.recovery,
          intensity: Intensity.recovery,
          seconds: restSeconds,
        );
        final blueprint = WorkoutBlueprint(
          id: '$id-x$reps',
          name: '$reps × ${_duration(workSeconds)} ${workLabel ?? name}',
          category: _category,
          purpose: purpose,
          steps: [
            const BlueprintStep(
              kind: WorkoutStepKind.warmup,
              intensity: Intensity.base,
              seconds: _warmupSeconds,
            ),
            for (var index = 0; index < reps; index++) ...[
              work,
              if (index < reps - 1) rest,
            ],
            const BlueprintStep(
              kind: WorkoutStepKind.cooldown,
              intensity: Intensity.recovery,
              seconds: _cooldownSeconds,
            ),
          ],
        );
        return blueprint.duration.inMinutes < minMinutes ? null : blueprint;
    }
  }

  WorkoutCategory get _category => switch (stimulus) {
    TrainingStimulus.technique => WorkoutCategory.technique,
    TrainingStimulus.speed => WorkoutCategory.power,
    TrainingStimulus.threshold ||
    TrainingStimulus.vo2max ||
    TrainingStimulus.aerobicCapacity => WorkoutCategory.intervals,
    _ => WorkoutCategory.endurance,
  };

  static String _duration(int seconds) =>
      seconds % 60 == 0 ? '${seconds ~/ 60} min' : '$seconds s';
}

const _all = {...TrainingModality.values};
const _allWithoutRunning = {
  TrainingModality.ercolina,
  TrainingModality.bikeIndoor,
  TrainingModality.bikeOutdoor,
  TrainingModality.skiSkating,
  TrainingModality.skiClassic,
};

/// Die Vorlagen. Neue kommen hierher, geprüft – nicht in den Planer.
const List<WorkoutTemplate> workoutCatalogue = [
  WorkoutTemplate(
    id: 'reg',
    name: 'Regeneration',
    stimulus: TrainingStimulus.regeneration,
    purpose: 'Durchbluten und erholen, ohne neuen Reiz.',
    modalities: _all,
    shape: TemplateShape.continuous,
    minMinutes: 20,
    maxMinutes: 60,
    preferredMinutes: 40,
  ),
  WorkoutTemplate(
    id: 'ga1',
    name: 'Grundlage',
    stimulus: TrainingStimulus.aerobicBase,
    purpose: 'Aerobe Basis: lange ruhig unter LTP1.',
    modalities: _all,
    shape: TemplateShape.continuous,
    minMinutes: 30,
    maxMinutes: 150,
    preferredMinutes: 90,
  ),
  WorkoutTemplate(
    id: 'gal',
    name: 'Lange Grundlage',
    stimulus: TrainingStimulus.longEndurance,
    purpose:
        'Ermüdungsarm lange unterwegs: Fettstoffwechsel und Ausdauer '
        'für die Renndauer.',
    modalities: _allWithoutRunning,
    shape: TemplateShape.continuous,
    minMinutes: 100,
    maxMinutes: 300,
  ),
  WorkoutTemplate(
    id: 'ga2',
    name: 'GA2-Blöcke',
    workLabel: 'GA2',
    stimulus: TrainingStimulus.aerobicCapacity,
    purpose: 'Aerobe Kapazität knapp unter der Schwelle.',
    modalities: _all,
    shape: TemplateShape.intervals,
    workSeconds: 15 * 60,
    restSeconds: 3 * 60,
    minReps: 2,
    maxReps: 4,
    minMinutes: 45,
    maxMinutes: 100,
  ),
  WorkoutTemplate(
    id: 'eb6',
    name: 'Schwellenintervalle',
    workLabel: 'EB',
    stimulus: TrainingStimulus.threshold,
    purpose: 'Hebt die Leistung, die du über eine Stunde halten kannst.',
    modalities: _all,
    shape: TemplateShape.intervals,
    workSeconds: 6 * 60,
    restSeconds: 3 * 60,
    minReps: 3,
    maxReps: 6,
    minMinutes: 40,
    maxMinutes: 75,
  ),
  WorkoutTemplate(
    id: 'eb10',
    name: 'Lange Schwellenintervalle',
    workLabel: 'EB',
    stimulus: TrainingStimulus.threshold,
    purpose: 'Längere Zeit an der Schwelle: Tempohärte für lange Rennen.',
    modalities: _all,
    shape: TemplateShape.intervals,
    workSeconds: 10 * 60,
    restSeconds: 3 * 60,
    minReps: 3,
    maxReps: 6,
    minMinutes: 55,
    maxMinutes: 100,
  ),
  WorkoutTemplate(
    id: 'vo2-3',
    name: 'VO2max-Intervalle',
    workLabel: 'VO2max',
    stimulus: TrainingStimulus.vo2max,
    purpose:
        'Aerobe Leistung: lange genug oberhalb der Schwelle, um die '
        'maximale Sauerstoffaufnahme zu fordern.',
    modalities: _all,
    shape: TemplateShape.intervals,
    workSeconds: 3 * 60,
    restSeconds: 3 * 60,
    minReps: 4,
    maxReps: 6,
    minMinutes: 40,
    maxMinutes: 60,
  ),
  WorkoutTemplate(
    id: 'vo2-30-30',
    name: 'VO2max 30/30',
    stimulus: TrainingStimulus.vo2max,
    purpose:
        'Oft an die maximale Sauerstoffaufnahme, ohne dass die Technik '
        'zerfällt.',
    modalities: {
      TrainingModality.ercolina,
      TrainingModality.bikeIndoor,
      TrainingModality.bikeOutdoor,
    },
    shape: TemplateShape.fixed,
    blueprintId: 'vo2-30-30',
  ),
  WorkoutTemplate(
    id: 'speed',
    name: 'Sprints',
    workLabel: 'maximal',
    stimulus: TrainingStimulus.speed,
    purpose: 'Spitzenleistung und Zugkraft, mit vollständiger Erholung.',
    modalities: _all,
    shape: TemplateShape.intervals,
    workSeconds: 15,
    restSeconds: 165,
    minReps: 6,
    maxReps: 10,
    minMinutes: 30,
    maxMinutes: 50,
  ),
  WorkoutTemplate(
    id: 'tech-doublepole',
    name: 'Doppelstock Technik',
    stimulus: TrainingStimulus.technique,
    purpose: 'Gleiche Arbeit bei niedrigerer Frequenz.',
    modalities: {TrainingModality.ercolina},
    shape: TemplateShape.fixed,
    blueprintId: 'technique-doublepoling',
  ),
  WorkoutTemplate(
    id: 'tech-ski',
    name: 'Technik Langlauf',
    stimulus: TrainingStimulus.technique,
    purpose: 'Locker, mit Aufmerksamkeit auf Gleitphase und Rhythmuswechsel.',
    modalities: {TrainingModality.skiSkating, TrainingModality.skiClassic},
    shape: TemplateShape.continuous,
    minMinutes: 30,
    maxMinutes: 75,
    preferredMinutes: 60,
  ),
];

/// Eine zulässige Möglichkeit für heute: Vorlage, Gerät, Dauer, Reiz.
class WorkoutOption {
  const WorkoutOption({
    required this.template,
    required this.modality,
    required this.blueprint,
    required this.need,
    required this.score,
    required this.reasons,
  });

  final WorkoutTemplate template;
  final TrainingModality modality;
  final WorkoutBlueprint blueprint;
  final TrainingNeed need;
  final double score;
  final List<PlanningReason> reasons;

  TrainingStimulus get stimulus => template.stimulus;
  int get minutes => blueprint.duration.inMinutes;

  String get title => '${blueprint.name} · ${modality.label}';
}

class WorkoutSelector {
  const WorkoutSelector({
    this.catalogue = workoutCatalogue,
    this.policy = const PlanningPolicy(),
  });

  final List<WorkoutTemplate> catalogue;
  final PlanningPolicy policy;

  /// Jede Vorlage auf jedem verfügbaren Gerät, bewertet nach Bedarf,
  /// Übertrag auf das Ziel und der Gelegenheit, die der heutige Tag bietet.
  List<WorkoutOption> options({
    required List<TrainingNeed> needs,
    required DayAvailability today,
    List<DayAvailability> upcoming = const [],
    required SeasonPosition season,
    TrainingGoal? goal,
    StimulusLedger? ledger,
  }) {
    final options = <WorkoutOption>[];
    final nextMinutes = upcoming
        .take(2)
        .fold<int?>(
          null,
          (best, day) =>
              best == null || day.minutes > best ? day.minutes : best,
        );
    var limit = today.minutes;
    if (season.phase == SeasonPhase.taper && limit > policy.taperMaxMinutes) {
      limit = policy.taperMaxMinutes;
    }
    for (final need in needs) {
      for (final template in catalogue) {
        if (template.stimulus != need.stimulus) continue;
        for (final modality in today.modalities) {
          if (!template.modalities.contains(modality)) continue;
          final longest = ledger?.longestSeconds(modality.sportKey, 28);
          final cap = policy.stepUpMinutes(longest);
          final capped = cap != null && cap < limit;
          final blueprint = template.build(capped ? cap : limit, modality);
          if (blueprint == null) continue;
          final reasons = <PlanningReason>[...need.reasons];
          if (capped && blueprint.duration.inMinutes >= cap - 5) {
            reasons.add(
              PlanningReason(
                'Deine längste Einheit dieser Art in den letzten vier Wochen '
                'dauerte ${(longest! / 60).round()} min: GIULIA steigert '
                'schrittweise.',
              ),
            );
          }
          var transfer = 1.0;
          if (goal != null) {
            final pressure = policy.specificityPressure(season.phase);
            transfer =
                1 - pressure * (1 - policy.transfer(goal.modality, modality));
          }
          var opportunity = 1.0;
          if (today.longDay &&
              need.stimulus == TrainingStimulus.longEndurance) {
            // Ein vom Athleten benannter langer Tag wiegt mehr als ein
            // zufällig freier.
            opportunity = 1.3;
            reasons.add(
              const PlanningReason(
                'Heute ist dein Tag für eine lange Einheit.',
              ),
            );
          } else if (nextMinutes != null && template.minMinutes > nextMinutes) {
            opportunity = 1.15;
            reasons.add(
              PlanningReason(
                'In den nächsten Tagen bleibt für ${template.name} zu wenig '
                'Zeit (höchstens $nextMinutes min).',
              ),
            );
          }
          // Eine lange Einheit wirkt erst, wenn sie an die Renndauer reicht.
          var fit = 1.0;
          if (need.stimulus == TrainingStimulus.longEndurance) {
            final target = (goal?.targetSeconds ?? 150 * 60) / 60;
            fit = blueprint.duration.inMinutes / target;
            if (fit > 1) fit = 1;
          }
          options.add(
            WorkoutOption(
              template: template,
              modality: modality,
              blueprint: blueprint,
              need: need,
              score: need.priority * transfer * opportunity * fit,
              reasons: reasons,
            ),
          );
        }
      }
    }
    options.sort((a, b) => b.score.compareTo(a.score));
    return options;
  }
}

class SafetyVerdict {
  const SafetyVerdict({required this.violations, this.warnings = const []});

  final List<PlanningReason> violations;
  final List<String> warnings;

  bool get admissible => violations.isEmpty;
}

/// Prüft jede Möglichkeit, auch die, die ein Sprachmodell gewählt hat.
class PlanSafetyEngine {
  const PlanSafetyEngine({this.policy = const PlanningPolicy()});

  final PlanningPolicy policy;

  SafetyVerdict check(
    WorkoutOption option, {
    required ReadinessAssessment readiness,
    required StimulusLedger ledger,
    required DayAvailability today,
    required SeasonPosition season,
    Set<String> calibratedSports = const {},
  }) {
    final violations = <PlanningReason>[];
    final warnings = <String>[];
    if (option.minutes > today.minutes) {
      violations.add(
        PlanningReason(
          '${option.minutes} min passen nicht in die verfügbaren '
          '${today.minutes} min.',
        ),
      );
    }
    if (!today.modalities.contains(option.modality)) {
      violations.add(
        PlanningReason('${option.modality.label} ist heute nicht verfügbar.'),
      );
    }
    final cap = policy.stepUpMinutes(
      ledger.longestSeconds(option.modality.sportKey, 28),
    );
    if (cap != null && option.minutes > cap) {
      violations.add(
        PlanningReason(
          '${option.minutes} min wären ein zu grosser Sprung gegenüber deinen '
          'bisherigen Einheiten dieser Art (höchstens $cap min).',
        ),
      );
    }
    if (!readiness.allows(option.stimulus)) {
      violations.addAll(readiness.reasons);
    }
    final sinceHard = ledger.hoursSinceHard;
    if (option.stimulus.intensive &&
        sinceHard != null &&
        sinceHard < policy.minHoursBetweenIntensive &&
        readiness.allows(option.stimulus)) {
      violations.add(
        PlanningReason(
          'Zwischen zwei intensiven Reizen liegen weniger als '
          '${policy.minHoursBetweenIntensive.round()} h.',
        ),
      );
    }
    final reference = ledger.referenceWeekSeconds;
    if (option.stimulus != TrainingStimulus.regeneration &&
        reference >= policy.minReferenceWeekSeconds) {
      final ratio =
          (ledger.durationSeconds(7) + option.minutes * 60) / reference;
      if (ratio > policy.maxAcuteLoadRatio) {
        violations.add(
          PlanningReason(
            'Mit dieser Einheit läge die Woche beim '
            '${ratio.toStringAsFixed(1)}-Fachen einer üblichen Woche.',
          ),
        );
      }
    }
    if (season.phase == SeasonPhase.taper &&
        option.minutes > policy.taperMaxMinutes) {
      violations.add(
        PlanningReason(
          'Im Tapering bleibt keine Einheit über ${policy.taperMaxMinutes} min.',
        ),
      );
    }
    if (option.stimulus.intensive &&
        !calibratedSports.contains(option.modality.sportKey)) {
      warnings.add(
        'Für ${option.modality.label} liegt keine Schwelle vor: Die '
        'Intensität wird nach Gefühl (RPE) gesteuert, nicht nach Watt.',
      );
    }
    return SafetyVerdict(violations: violations, warnings: warnings);
  }
}
