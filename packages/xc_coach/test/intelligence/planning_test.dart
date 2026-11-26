import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/domain/coach_decision.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'package:xc_coach/intelligence/models.dart';
import 'package:xc_coach/intelligence/planning/daily_planner.dart';
import 'package:xc_coach/intelligence/planning/planning_models.dart';
import 'package:xc_coach/intelligence/planning/stimulus_ledger.dart';
import 'package:xc_coach/intelligence/planning/training_need.dart';
import 'package:xc_coach/intelligence/planning/workout_catalogue.dart';
import 'package:xc_coach/workout_engine/workout_library.dart';

const _hourUs = Duration.microsecondsPerHour;
final _now = DateTime.utc(2026, 10, 7, 12).microsecondsSinceEpoch;
const _today = CalendarDay(2026, 10, 7);
const _goal = TrainingGoal(
  name: '50 km Skating',
  day: CalendarDay(2027, 1, 31),
  modality: TrainingModality.skiSkating,
  distanceKm: 50,
  targetSeconds: 2 * 3600 + 15 * 60,
);

IntelligenceZone _zone(String code, double? lower, double? upper) =>
    IntelligenceZone(
      modelId: 'threshold-anchored-reg-sb',
      modelName: 'threshold-anchored-reg-sb',
      modelVersion: '2.0.1',
      engineVersion: '1',
      quality: 'ok',
      name: code,
      code: code,
      loadUnit: 'W',
      provisional: false,
      lowerLoad: lower,
      upperLoad: upper,
    );

IntelligenceTest _test({
  String id = 'test-ercolina',
  double lt1 = 150,
  double lt2 = 200,
  String sport = 'ercolina',
  int daysAgo = 20,
  bool zones = true,
}) => IntelligenceTest(
  id: id,
  startedAtUtcUs: _now - daysAgo * 24 * _hourUs,
  sport: sport,
  loadUnit: 'W',
  loadSemantics: 'load.protocol_target',
  protocol: 'step',
  status: 'completed',
  curve: const [],
  thresholds: [
    for (final (type, load) in [('lt1', lt1), ('lt2', lt2)])
      IntelligenceThreshold(
        type: type,
        methodId: 'm',
        methodVersion: '1',
        engineVersion: '1',
        status: 'success',
        loadUnit: 'W',
        selected: true,
        load: load,
      ),
  ],
  zones: zones
      ? [
          _zone('REG', null, lt1 * .70),
          _zone('GAL', lt1 * .70, lt1 * .825),
          _zone('GA1', lt1 * .825, lt1),
          _zone('GA2', lt1, lt2 * .92),
          _zone('EB', lt2 * .92, lt2),
          _zone('SB', lt2, null),
        ]
      : const [],
  structure: null,
  engineVersion: '1',
  qualityNotes: const [],
);

IntelligenceSession _session(
  String id, {
  required double hoursAgo,
  List<(int, double)> intervals = const [],
  int? durationSeconds,
  String sport = 'ercolina',
  double? power,
  int? heartRate,
  double? rpe,
}) => IntelligenceSession(
  id: id,
  startedAtUtcUs: _now - (hoursAgo * _hourUs).round(),
  durationSeconds:
      durationSeconds ?? intervals.fold(0, (sum, item) => sum + item.$1),
  sport: sport,
  completed: true,
  averagePowerWatt: power,
  averageHeartRateBpm: heartRate,
  rpe: rpe,
  intervals: [
    for (final (index, (seconds, watt)) in intervals.indexed)
      IntelligenceInterval(
        ordinal: index,
        durationSeconds: seconds,
        kind: 'work',
        averagePowerWatt: watt,
      ),
  ],
);

/// 4 × 6 min EB mit 10 min GA1 davor.
IntelligenceSession _threshold(String id, double hoursAgo) => _session(
  id,
  hoursAgo: hoursAgo,
  intervals: [
    (600, 130),
    for (var i = 0; i < 4; i++) ...[(360, 195), (180, 100)],
  ],
);

IntelligenceSession _base(String id, double hoursAgo, {int minutes = 60}) =>
    _session(id, hoursAgo: hoursAgo, intervals: [(minutes * 60, 135)]);

IntelligenceSession _vo2(String id, double hoursAgo) => _session(
  id,
  hoursAgo: hoursAgo,
  intervals: [
    (600, 130),
    for (var i = 0; i < 5; i++) ...[(180, 215), (180, 100)],
  ],
);

DayAvailability _day(
  int minutes, {
  CalendarDay day = _today,
  Set<TrainingModality> modalities = const {
    TrainingModality.ercolina,
    TrainingModality.bikeIndoor,
  },
}) => DayAvailability(day: day, minutes: minutes, modalities: modalities);

PlannedWorkout _planned(
  String id,
  CalendarDay day,
  String intensity, {
  int seconds = 3600,
  String? sessionId,
}) => PlannedWorkout(
  id: id,
  organizationId: 'org',
  athleteId: 'jan',
  day: day,
  sport: 'ercolina',
  goal: intensity == 'threshold' ? 'Schwellenintervalle' : 'Grundlage',
  durationSeconds: seconds,
  intensity: intensity,
  structure: [
    PlannedStep(kind: 'work', seconds: seconds, intensity: intensity),
  ],
  sessionId: sessionId,
  createdAtUtcUs: 0,
  updatedAtUtcUs: 0,
);

DailyRecommendation _recommend({
  required List<IntelligenceSession> sessions,
  List<IntelligenceTest>? tests,
  DayAvailability? today,
  List<DayAvailability> upcoming = const [],
  TrainingPlan? plan,
  TrainingGoal? goal = _goal,
  RecommendationChooser chooser = const HighestScoreChooser(),
  CalendarDay day = _today,
}) => const DailyPlanner().recommend(
  PlanningInput(
    athleteId: 'jan',
    nowUtcUs: _now,
    today: today ?? _day(60, day: day),
    upcoming: upcoming,
    goal: goal,
    sessions: sessions,
    tests: tests ?? [_test()],
    plan: plan,
  ),
  chooser: chooser,
);

void main() {
  group('StimulusLedger', () {
    test('ordnet Intervall für Intervall über das REG–SB-Modell ein', () {
      final ledger = StimulusLedger.build(
        sessions: [_threshold('eb', 30)],
        tests: [_test()],
        nowUtcUs: _now,
      );
      final dose = ledger.doses.single;
      expect(dose.source, DoseSource.zones);
      expect(dose.seconds[TrainingStimulus.aerobicBase], 600);
      expect(dose.seconds[TrainingStimulus.threshold], 1440);
      expect(dose.seconds[TrainingStimulus.regeneration], 720);
      expect(dose.hard, isTrue);
      expect(
        ledger.lastMeaningful(TrainingStimulus.threshold)?.sessionId,
        'eb',
      );
      expect(ledger.hoursSinceHard, closeTo(30, 1e-6));
    });

    test(
      'ohne Zonenmodell nur grob über LTP1/LTP2, Kurzes als Schnelligkeit',
      () {
        final ledger = StimulusLedger.build(
          sessions: [
            _session(
              'mix',
              hoursAgo: 5,
              intervals: [(300, 210), (15, 320), (1200, 140)],
            ),
          ],
          tests: [_test(zones: false)],
          nowUtcUs: _now,
        );
        final dose = ledger.doses.single;
        expect(dose.source, DoseSource.thresholds);
        expect(dose.seconds[TrainingStimulus.vo2max], 300);
        expect(dose.seconds[TrainingStimulus.speed], 15);
        expect(dose.seconds[TrainingStimulus.aerobicBase], 1200);
      },
    );

    test('Schwellen gelten nur für dieselbe Sportart', () {
      final ledger = StimulusLedger.build(
        sessions: [
          _session(
            'bike',
            hoursAgo: 5,
            sport: 'cycling',
            intervals: [(3600, 195)],
          ),
        ],
        tests: [_test()],
        nowUtcUs: _now,
      );
      final dose = ledger.doses.single;
      expect(dose.source, DoseSource.none);
      expect(dose.seconds, isEmpty);
      expect(dose.unclassifiedSeconds, 3600);
    });

    test('ohne Messung zählt der Reiz der erfüllten Plan-Einheit', () {
      final ledger = StimulusLedger.build(
        sessions: [
          _session(
            'ski',
            hoursAgo: 20,
            sport: 'langlauf',
            durationSeconds: 7200,
          ),
        ],
        tests: [_test()],
        nowUtcUs: _now,
        plannedStimulusBySession: {'ski': TrainingStimulus.aerobicBase},
      );
      final dose = ledger.doses.single;
      expect(dose.source, DoseSource.plan);
      expect(dose.long, isTrue);
      expect(
        ledger.lastMeaningful(TrainingStimulus.longEndurance)?.sessionId,
        'ski',
      );
    });
  });

  group('Saisonphase', () {
    test('folgt dem Abstand zum Ziel, nicht dem Kalender', () {
      SeasonPhase at(int month, int day) => SeasonPosition.of(
        _goal,
        CalendarDay(month >= 10 ? 2026 : 2027, month, day),
      ).phase;
      expect(at(10, 7), SeasonPhase.base);
      expect(at(11, 15), SeasonPhase.build);
      expect(at(1, 1), SeasonPhase.specific);
      expect(at(1, 25), SeasonPhase.taper);
      expect(at(1, 31), SeasonPhase.race);
      expect(SeasonPosition.of(null, _today).phase, SeasonPhase.open);
    });
  });

  group('IndividualProfile', () {
    test('schwache Basis (LTP1/LTP2 niedrig) gewichtet Grundlage höher', () {
      final profile = IndividualProfile.fromTests(
        tests: [_test(lt1: 140, lt2: 200)],
        nowUtcUs: _now,
      );
      expect(profile.baseRatio, closeTo(.70, 1e-9));
      expect(profile.weight(TrainingStimulus.aerobicBase), greaterThan(1));
      expect(profile.weight(TrainingStimulus.vo2max), lessThan(1));
      expect(profile.reasons.first.text, contains('70 %'));
      expect(profile.reasons.first.facts.single.id, 'test-ercolina');
    });

    test('gut entwickelte Basis gewichtet Schwelle und VO2max höher', () {
      final profile = IndividualProfile.fromTests(
        tests: [_test(lt1: 178, lt2: 200)],
        nowUtcUs: _now,
      );
      expect(profile.weight(TrainingStimulus.threshold), greaterThan(1));
      expect(profile.weight(TrainingStimulus.aerobicBase), lessThan(1));
    });

    test('Zielsportart ohne Diagnostik und alter Test werden benannt', () {
      final profile = IndividualProfile.fromTests(
        tests: [_test(daysAgo: 120)],
        nowUtcUs: _now,
        goal: _goal,
      );
      expect(profile.testDue, 'langlauf');
      expect(
        profile.reasons.map((item) => item.text).join(' '),
        allOf(contains('120 Tage'), contains('keine eigene Diagnostik')),
      );
    });
  });

  group('Vorlagen', () {
    test('skalieren nur innerhalb ihrer Grenzen', () {
      final eb = workoutCatalogue.firstWhere((item) => item.id == 'eb6');
      final full = eb.build(60, TrainingModality.ercolina)!;
      expect(full.name, '5 × 6 min EB');
      expect(full.duration.inMinutes, 60);
      expect(eb.build(35, TrainingModality.ercolina), isNull);
      expect(eb.build(200, TrainingModality.ercolina)!.workBlocks, eb.maxReps);
      final ga1 = workoutCatalogue.firstWhere((item) => item.id == 'ga1');
      expect(ga1.build(240, TrainingModality.ercolina)!.duration.inMinutes, 90);
      expect(ga1.build(25, TrainingModality.ercolina), isNull);
    });
  });

  group('DailyPlanner', () {
    test('fälliger Schwellenreiz nach 72 h Erholung: EB auf der Ercolina', () {
      final rec = _recommend(
        sessions: [
          _base('ga1-a', 26),
          _threshold('eb-old', 6 * 24 + 2),
          _vo2('vo2', 4 * 24),
          _base('ga1-b', 3 * 24),
          _base('ga1-c', 5 * 24),
        ],
        goal: const TrainingGoal(
          name: '50 km Skating',
          day: CalendarDay(2026, 12, 20),
          modality: TrainingModality.skiSkating,
        ),
        today: _day(60),
      );
      expect(rec.season.phase, SeasonPhase.build);
      expect(rec.readiness.level, ReadinessLevel.fresh);
      final chosen = rec.chosen!;
      expect(chosen.stimulus, TrainingStimulus.threshold);
      expect(chosen.modality, TrainingModality.ercolina);
      expect(chosen.minutes, lessThanOrEqualTo(60));
      expect(rec.explanation.join(' '), contains('Schwellenreiz'));
      expect(rec.planVerdict, PlanVerdict.none);
    });

    test('intensiver Reiz gestern: heute kein harter Reiz, mit Grund', () {
      final rec = _recommend(
        sessions: [_threshold('eb', 20), _base('ga1', 3 * 24)],
      );
      expect(rec.readiness.level, ReadinessLevel.limited);
      expect(rec.chosen!.stimulus.intensive, isFalse);
      final blocked = rec.blocked.where((item) => item.$1.stimulus.intensive);
      expect(blocked, isNotEmpty);
      expect(
        blocked.first.$2.violations.map((item) => item.text).join(),
        contains('20 h'),
      );
    });

    test('geplante Schwelle, aber Leistung bei gleicher Herzfrequenz '
        'gesunken: Reiz verschoben, Begründung mit Fakten', () {
      final sessions = [
        _session(
          'yesterday',
          hoursAgo: 22,
          intervals: [(3600, 150)],
          power: 150,
          heartRate: 145,
        ),
        for (var i = 1; i <= 4; i++)
          _session(
            'ref$i',
            hoursAgo: 24.0 * (3 + 4 * i),
            intervals: [(3600, 160)],
            power: 160,
            heartRate: 140,
          ),
        _threshold('eb-old', 7 * 24),
      ];
      final plan = TrainingPlan(
        athleteId: 'jan',
        workouts: [_planned('today-eb', _today, 'threshold')],
      );
      final rec = _recommend(sessions: sessions, plan: plan);
      expect(rec.readiness.level, ReadinessLevel.limited);
      expect(rec.planVerdict, PlanVerdict.changed);
      expect(rec.chosen!.stimulus.intensive, isFalse);
      final text = rec.explanation.join(' ');
      expect(
        text,
        contains('Eigentlich war heute Schwellenintervalle vorgesehen'),
      );
      expect(text, contains('vergleichbarer Herzfrequenz'));
      expect(text, contains('verschiebe ich den Schwellenreiz'));
      expect(rec.facts.any((fact) => fact.id == 'yesterday'), isTrue);

      final planned = rec.toPlannedWorkout(
        id: 'new',
        organizationId: 'org',
        athleteId: 'jan',
        nowUtcUs: _now,
      )!;
      expect(planned.day, _today);
      expect(
        planned.structure.every(
          (step) => Intensity.values.any((item) => item.name == step.intensity),
        ),
        isTrue,
      );
      final decision = rec.decision(
        id: 'd',
        organizationId: 'org',
        athleteId: 'jan',
        plannedWorkoutIds: ['today-eb', 'new'],
        nowUtcUs: _now,
      );
      expect(decision.type, CoachDecisionType.planned);
      expect(decision.change['replaces'], 'today-eb');
      expect(decision.author, CoachDecisionAuthor.giulia);
      expect(decision.facts, isNotEmpty);
    });

    test('geplante Einheit bleibt, wenn sie zulässig und sinnvoll ist', () {
      final plan = TrainingPlan(
        athleteId: 'jan',
        workouts: [_planned('today-eb', _today, 'threshold')],
      );
      final rec = _recommend(
        sessions: [_threshold('eb-old', 8 * 24), _base('ga1', 26)],
        plan: plan,
        goal: const TrainingGoal(
          name: 'Rennen',
          day: CalendarDay(2026, 12, 20),
          modality: TrainingModality.skiSkating,
        ),
      );
      expect(rec.planVerdict, PlanVerdict.kept);
      expect(rec.chosen!.stimulus, TrainingStimulus.threshold);
    });

    test(
      'verpasste Einheiten werden bewertet, nicht automatisch nachgeholt',
      () {
        final plan = TrainingPlan(
          athleteId: 'jan',
          workouts: [
            _planned('missed-eb', _today.addDays(-3), 'threshold'),
            _planned('missed-ga1', _today.addDays(-2), 'base'),
          ],
        );
        final rec = _recommend(
          sessions: [_base('ga1-done', 20), _threshold('eb-old', 12 * 24)],
          plan: plan,
          goal: const TrainingGoal(
            name: 'Rennen',
            day: CalendarDay(2026, 12, 20),
            modality: TrainingModality.skiSkating,
          ),
        );
        final eb = rec.missed.firstWhere(
          (item) => item.workout.id == 'missed-eb',
        );
        final ga1 = rec.missed.firstWhere(
          (item) => item.workout.id == 'missed-ga1',
        );
        expect(eb.stillDue, isTrue);
        expect(eb.reason, contains('nicht zwingend morgen'));
        expect(ga1.stillDue, isFalse);
        expect(ga1.reason, contains('inzwischen'));
      },
    );

    test('Belastungssprung: nur noch Regeneration zulässig', () {
      final rec = _recommend(
        sessions: [
          for (var i = 0; i < 6; i++)
            _base('heavy$i', 12.0 + 24 * i, minutes: 120),
          for (var i = 0; i < 6; i++) _base('ref$i', 24.0 * (9 + 3 * i)),
        ],
        today: _day(90),
      );
      expect(rec.readiness.level, ReadinessLevel.limited);
      expect(rec.chosen?.stimulus, TrainingStimulus.regeneration);
      expect(
        rec.blocked.first.$2.violations.map((item) => item.text).join(),
        contains('Fachen einer üblichen Woche'),
      );
    });

    test('wenig Zeit morgen macht heute zur Gelegenheit für Langes', () {
      final rec = _recommend(
        sessions: [_base('ga1', 26), _threshold('eb', 3 * 24)],
        today: _day(
          150,
          modalities: const {
            TrainingModality.bikeOutdoor,
            TrainingModality.ercolina,
          },
        ),
        upcoming: [
          _day(45, day: _today.addDays(1)),
          _day(30, day: _today.addDays(2)),
        ],
      );
      expect(rec.chosen!.stimulus, TrainingStimulus.longEndurance);
      expect(rec.explanation.join(' '), contains('zu wenig Zeit'));
    });

    test('ein Chooser kann nur zwischen zulässigen Einheiten wählen', () {
      final rec = _recommend(
        sessions: [_threshold('eb', 20)],
        chooser: _Rogue(),
      );
      expect(rec.chosen!.stimulus.intensive, isFalse);
      expect(rec.warnings.join(), contains('nicht zulässig'));
    });
  });
}

/// Wählt absichtlich eine blockierte Einheit, wie es ein Sprachmodell tun
/// könnte.
class _Rogue implements RecommendationChooser {
  @override
  WorkoutOption? choose(
    List<WorkoutOption> admissible,
    DailyPlanningContext context,
  ) {
    final need = context.needs.firstWhere(
      (item) => item.stimulus == TrainingStimulus.threshold,
    );
    final template = workoutCatalogue.firstWhere((item) => item.id == 'eb6');
    return WorkoutOption(
      template: template,
      modality: TrainingModality.ercolina,
      blueprint: template.build(60, TrainingModality.ercolina)!,
      need: need,
      score: 99,
      reasons: const [],
    );
  }
}
