/// COACH's structured view of one athlete.
///
/// A read model only: it copies nothing into new tables and computes no
/// physiology. Every value comes from the existing sources (athlete profile,
/// sessions, LaLa results, the training plan). What is not stored stays
/// `null` or is listed under [CoachContext.missing].
library;

import '../domain/coach_decision.dart';
import '../domain/diagnostic_catalogue.dart';
import '../domain/training_plan.dart';
import 'athlete_state_models.dart';
import 'deterministic_analysis.dart';
import 'models.dart';

class CoachAthlete {
  const CoachAthlete({
    required this.id,
    required this.name,
    required this.sports,
    this.birthYear,
    this.sex,
    this.bodyMassKg,
    this.maxHeartRateBpm,
    this.restingHeartRateBpm,
  });

  final String id;
  final String name;
  final int? birthYear;
  final String? sex;
  final double? bodyMassKg;
  final int? maxHeartRateBpm;
  final int? restingHeartRateBpm;

  /// Sport keys that occur in this athlete's sessions or tests.
  final List<String> sports;

  /// Goals and available training time are not stored anywhere yet.
  List<String>? get goals => null;
  int? get availableMinutesPerWeek => null;
}

/// The newest evaluated test of one sport.
class SportPhysiology {
  const SportPhysiology({
    required this.sportKey,
    required this.test,
    this.previousTest,
  });

  final String sportKey;
  final IntelligenceTest test;

  /// The evaluated test of the same sport before [test], if any.
  final IntelligenceTest? previousTest;

  DiagnosticSport? get sport => DiagnosticSport.classify(sport: sportKey);
  String get testId => test.id;
  int get performedAtUtcUs => test.startedAtUtcUs;
  String get loadUnit => test.loadUnit;
  String get protocol => test.protocol;
  IntelligenceThreshold? get ltp1 => test.threshold('lt1');
  IntelligenceThreshold? get ltp2 => test.threshold('lt2');
  double? get powerOrSpeedAtLtp1 => ltp1?.load;
  double? get powerOrSpeedAtLtp2 => ltp2?.load;
  int? get heartRateAtLtp1 => ltp1?.heartRateBpm;
  int? get heartRateAtLtp2 => ltp2?.heartRateBpm;
  List<IntelligenceZone> get zones => test.zones;
}

class CoachSession {
  const CoachSession({required this.session, this.plannedWorkoutId});

  final IntelligenceSession session;

  /// The planned workout this session fulfilled, if it was assigned.
  final String? plannedWorkoutId;

  String get sportKey => sessionSportKey(session.sport);
}

class CoachPlanView {
  const CoachPlanView({
    required this.today,
    required this.plan,
    required this.todays,
    required this.upcoming,
    required this.week,
    required this.overdue,
    required this.suggestions,
  });

  final CalendarDay today;
  final TrainingPlan plan;

  /// Today's planned workouts with their actual session, if assigned.
  final List<PlanActual> todays;
  final List<PlannedWorkout> upcoming;
  final TrainingWeek week;

  /// Past workouts still open: neither done nor skipped.
  final List<PlannedWorkout> overdue;

  /// Unassigned sessions that fall on the day and sport of an open workout.
  /// Only a suggestion; assigning is an explicit action.
  final List<PlanActual> suggestions;
}

class CoachCurrentState {
  const CoachCurrentState({
    required this.sessions7Days,
    required this.durationSeconds7Days,
    required this.durationBySport7Days,
    this.lastSession,
    this.highIntensitySeconds7Days,
    this.intensityClassifiedSeconds7Days = 0,
    this.readiness,
    this.athleteState,
  });

  final int sessions7Days;
  final int durationSeconds7Days;
  final Map<String, int> durationBySport7Days;
  final IntelligenceSession? lastSession;

  /// Seconds at or above the LT2 of the session's own sport. Null when no
  /// interval could be classified.
  final int? highIntensitySeconds7Days;
  final int intensityClassifiedSeconds7Days;
  final ReadinessContext? readiness;
  final AthleteState? athleteState;
}

enum CoachInsightLevel { info, notice, concern }

class CoachInsight {
  const CoachInsight({
    required this.kind,
    required this.level,
    required this.title,
    required this.detail,
  });

  /// `zonesUpdated`, `plannedMissed`, `sessionToAssign`, or an attention rule.
  final String kind;
  final CoachInsightLevel level;
  final String title;
  final String detail;
}

class CoachContext {
  const CoachContext({
    required this.athleteId,
    required this.asOfUtcUs,
    required this.athlete,
    required this.physiology,
    required this.sessions,
    required this.plan,
    required this.state,
    required this.insights,
    required this.decisions,
    required this.missing,
  });

  /// No visible athlete: nothing is read, not even the plan.
  const CoachContext.unavailable(this.athleteId, this.asOfUtcUs)
    : athlete = null,
      physiology = const [],
      sessions = const [],
      plan = null,
      state = null,
      insights = const [],
      decisions = const [],
      missing = const ['Athletenprofil oder Freigabe'];

  final String athleteId;
  final int asOfUtcUs;
  final CoachAthlete? athlete;

  /// One entry per sport, newest valid test each.
  final List<SportPhysiology> physiology;

  /// Sessions of the last 28 days, newest first.
  final List<CoachSession> sessions;
  final CoachPlanView? plan;
  final CoachCurrentState? state;
  final List<CoachInsight> insights;
  final List<CoachDecision> decisions;
  final List<String> missing;

  bool get available => athlete != null;

  /// Thresholds of exactly this sport, or null. Never another sport's values.
  SportPhysiology? physiologyFor(String sport) {
    final key = sessionSportKey(sport);
    for (final entry in physiology) {
      if (entry.sportKey == key) return entry;
    }
    return null;
  }

  /// Sessions of the current calendar week (Monday to today).
  List<CoachSession> sessionsThisWeek() {
    final start = CalendarDay.ofUtcUs(asOfUtcUs).weekStart;
    return [
      for (final entry in sessions)
        if (!CalendarDay.ofUtcUs(entry.session.startedAtUtcUs).isBefore(start))
          entry,
    ];
  }

  /// Why [workout] is planned, from stored facts only. Each sentence has a
  /// source; a statement without data is left out.
  List<String> reasonsFor(PlannedWorkout workout) {
    final reasons = <String>[
      if (workout.goal.trim().isNotEmpty) 'Ziel der Einheit: ${workout.goal}',
    ];
    final physiology = physiologyFor(workout.sport);
    if (physiology == null) {
      reasons.add(
        'Für diese Sportart liegt kein ausgewerteter Test vor; die Intensität '
        'bleibt relativ und wird nicht in Watt oder Tempo übersetzt.',
      );
    } else {
      final ltp1 = physiology.ltp1?.load;
      final ltp2 = physiology.ltp2?.load;
      reasons.add(
        'Bezug sind deine Schwellen vom '
        '${_date(physiology.performedAtUtcUs)}: '
        'LTP1 ${_load(ltp1, physiology.loadUnit)}, '
        'LTP2 ${_load(ltp2, physiology.loadUnit)}.',
      );
    }
    final state = this.state;
    final easy = const {'recovery', 'base'}.contains(workout.intensity);
    final hard = const {
      'threshold',
      'vo2',
      'maximal',
    }.contains(workout.intensity);
    final high = state?.highIntensitySeconds7Days;
    if (easy && high != null && high > 0) {
      reasons.add(
        'In den letzten sieben Tagen sind bereits '
        '${(high / 60).round()} min an oder über LTP2 belegt.',
      );
    }
    final readiness = state?.readiness;
    if (hard &&
        readiness != null &&
        const {
          ReadinessRecommendation.recovery,
          ReadinessRecommendation.easy,
        }.contains(readiness.recommendation)) {
      reasons.add(
        'Hinweis: Die Auswertung der letzten Einheiten rät heute zu '
        '„${readiness.headline}“.',
      );
    }
    final last = state?.lastSession;
    if (last != null) {
      final hours =
          (asOfUtcUs - last.startedAtUtcUs) / Duration.microsecondsPerHour;
      reasons.add(
        'Letzte Einheit vor ${hours.round()} h '
        '(${(last.durationSeconds / 60).round()} min).',
      );
    }
    return reasons;
  }
}

/// Builds a [CoachContext] from the existing sources.
class CoachContextBuilder {
  const CoachContextBuilder({
    required this.data,
    this.plan,
    this.attention,
    this.loadAnalyzer = const TrainingLoadAnalyzer(),
    this.readinessAnalyzer = const ReadinessAnalyzer(),
  });

  final IntelligenceDataSource data;
  final TrainingPlanReader? plan;

  /// Further insights from the product, e.g. the coach attention rules.
  final List<CoachInsight> Function(CoachContext context)? attention;
  final TrainingLoadAnalyzer loadAnalyzer;
  final ReadinessAnalyzer readinessAnalyzer;

  CoachContext build(String athleteId, {required int nowUtcUs}) {
    final profile = data.getAthleteProfile(athleteId);
    if (profile == null || profile.id != athleteId) {
      return CoachContext.unavailable(athleteId, nowUtcUs);
    }
    const dayUs = Duration.microsecondsPerDay;
    final sessions = data
        .getRecentTraining(
          athleteId,
          fromUtcUs: nowUtcUs - 28 * dayUs,
          limit: 200,
        )
        .where((session) => session.startedAtUtcUs <= nowUtcUs)
        .toList(growable: false);
    final tests = data.getTests(athleteId, limit: 30);
    final physiology = _physiology(tests);
    final lt2BySport = {
      for (final entry in physiology)
        if (entry.ltp2 != null) entry.sportKey: entry.ltp2!,
    };

    final today = CalendarDay.ofUtcUs(nowUtcUs);
    final trainingPlan = plan?.planOf(
      athleteId,
      from: today.addDays(-28),
      to: today.addDays(28),
    );
    final linked = <String, String>{
      for (final workout in trainingPlan?.workouts ?? const <PlannedWorkout>[])
        if (workout.sessionId != null) workout.sessionId!: workout.id,
    };
    final coachSessions = [
      for (final session in sessions)
        CoachSession(session: session, plannedWorkoutId: linked[session.id]),
    ];

    final load = loadAnalyzer.analyze(
      sessions: sessions,
      nowUtcUs: nowUtcUs,
      lt2BySport: lt2BySport,
    );
    final athleteState = data is AthleteStateDataSource
        ? (data as AthleteStateDataSource).getAthleteState(
            athleteId,
            nowUtcUs: nowUtcUs,
          )
        : null;
    final readiness = readinessAnalyzer.analyze(
      sessions: sessions,
      observations: data.getObservations(
        athleteId,
        fromUtcUs: nowUtcUs - 14 * dayUs,
      ),
      load: load,
      nowUtcUs: nowUtcUs,
      lt2BySport: lt2BySport,
      athleteState: athleteState,
    );
    final recent = sessions
        .where((session) => session.startedAtUtcUs >= nowUtcUs - 7 * dayUs)
        .toList(growable: false);
    final bySport = <String, int>{};
    for (final session in recent) {
      final key = sessionSportKey(session.sport);
      bySport[key] = (bySport[key] ?? 0) + session.durationSeconds;
    }
    final state = CoachCurrentState(
      sessions7Days: recent.length,
      durationSeconds7Days: recent.fold(
        0,
        (sum, session) => sum + session.durationSeconds,
      ),
      durationBySport7Days: bySport,
      lastSession: sessions.firstOrNull,
      highIntensitySeconds7Days: load.intensityClassifiedSeconds7Days > 0
          ? load.highIntensitySeconds7Days
          : null,
      intensityClassifiedSeconds7Days: load.intensityClassifiedSeconds7Days,
      readiness: readiness,
      athleteState: athleteState,
    );

    final planView = trainingPlan == null
        ? null
        : _planView(trainingPlan, today, sessions, linked);
    final sports = <String>{
      for (final session in sessions) sessionSportKey(session.sport),
      for (final test in tests) test.sportKey,
    }.toList()..sort();

    final missing = <String>[
      'Trainingsziele',
      'verfügbare Trainingszeit',
      if (sessions.isEmpty) 'Einheiten der letzten 28 Tage',
      if (physiology.isEmpty) 'ausgewerteter Stufentest',
      if (plan == null) 'Trainingsplan',
      for (final workout in planView?.todays ?? const <PlanActual>[])
        if (physiology.every(
          (entry) => entry.sportKey != sessionSportKey(workout.planned.sport),
        ))
          'Schwellen für ${workout.planned.sport}',
    ];

    final base = CoachContext(
      athleteId: athleteId,
      asOfUtcUs: nowUtcUs,
      athlete: CoachAthlete(
        id: profile.id,
        name: profile.name,
        birthYear: profile.birthYear,
        sex: profile.sex,
        bodyMassKg: profile.bodyMassKg,
        maxHeartRateBpm: profile.maxHeartRateBpm,
        restingHeartRateBpm: profile.restingHeartRateBpm,
        sports: sports,
      ),
      physiology: physiology,
      sessions: coachSessions,
      plan: planView,
      state: state,
      insights: const [],
      decisions: plan?.decisionsOf(athleteId) ?? const [],
      missing: missing,
    );
    final insights = <CoachInsight>[
      ..._insights(base, nowUtcUs),
      ...?attention?.call(base),
    ];
    return CoachContext(
      athleteId: base.athleteId,
      asOfUtcUs: base.asOfUtcUs,
      athlete: base.athlete,
      physiology: base.physiology,
      sessions: base.sessions,
      plan: base.plan,
      state: base.state,
      insights: insights,
      decisions: base.decisions,
      missing: base.missing,
    );
  }

  /// Newest valid test per sport. Valid means: a selected LTP1 or LTP2.
  List<SportPhysiology> _physiology(List<IntelligenceTest> newestFirst) {
    final evaluated = [
      for (final test in newestFirst)
        if (test.threshold('lt1') != null || test.threshold('lt2') != null)
          test,
    ];
    final result = <SportPhysiology>[];
    final seen = <String>{};
    for (final test in evaluated) {
      if (!seen.add(test.sportKey)) continue;
      final previous = evaluated
          .where(
            (other) =>
                other.sportKey == test.sportKey &&
                other.startedAtUtcUs < test.startedAtUtcUs,
          )
          .firstOrNull;
      result.add(
        SportPhysiology(
          sportKey: test.sportKey,
          test: test,
          previousTest: previous,
        ),
      );
    }
    return result;
  }

  CoachPlanView _planView(
    TrainingPlan plan,
    CalendarDay today,
    List<IntelligenceSession> sessions,
    Map<String, String> linked,
  ) {
    ActualSession? actual(String? sessionId) {
      if (sessionId == null) return null;
      final session = sessions
          .where((item) => item.id == sessionId)
          .firstOrNull;
      return session == null ? null : actualOf(plan.athleteId, session);
    }

    final suggestions = <PlanActual>[];
    final claimed = <String>{...linked.keys};
    for (final workout in plan.workouts) {
      if (!workout.isOpen || workout.isStarted || today.isBefore(workout.day)) {
        continue;
      }
      final match = sessions
          .where(
            (session) =>
                !claimed.contains(session.id) &&
                CalendarDay.ofUtcUs(session.startedAtUtcUs) == workout.day &&
                sameSport(workout.sport, session.sport),
          )
          .firstOrNull;
      if (match == null) continue;
      claimed.add(match.id);
      suggestions.add(
        PlanActual(planned: workout, actual: actualOf(plan.athleteId, match)),
      );
    }
    return CoachPlanView(
      today: today,
      plan: plan,
      todays: [
        for (final workout in plan.on(today))
          PlanActual(planned: workout, actual: actual(workout.sessionId)),
      ],
      upcoming: plan.upcoming(today),
      week: plan.week(today),
      overdue: plan.overdue(today),
      suggestions: suggestions,
    );
  }

  List<CoachInsight> _insights(CoachContext context, int nowUtcUs) {
    const dayUs = Duration.microsecondsPerDay;
    final insights = <CoachInsight>[];
    for (final entry in context.physiology) {
      final previous = entry.previousTest;
      if (previous == null || entry.zones.isEmpty) continue;
      if (nowUtcUs - entry.performedAtUtcUs > 14 * dayUs) continue;
      insights.add(
        CoachInsight(
          kind: 'zonesUpdated',
          level: CoachInsightLevel.notice,
          title: 'Neue Trainingszonen (${_sportName(entry.sportKey)})',
          detail:
              'Der Test vom ${_date(entry.performedAtUtcUs)} ersetzt den vom '
              '${_date(previous.startedAtUtcUs)} als Bezug.',
        ),
      );
    }
    for (final workout in context.plan?.overdue ?? const <PlannedWorkout>[]) {
      final suggested = context.plan!.suggestions.any(
        (item) => item.planned.id == workout.id,
      );
      if (suggested) continue;
      insights.add(
        CoachInsight(
          kind: 'plannedMissed',
          level: CoachInsightLevel.notice,
          title: 'Geplante Einheit nicht absolviert',
          detail:
              '${_day(workout.day)}: ${workout.goal} '
              '(${(workout.durationSeconds / 60).round()} min). '
              'Keine Session ist dieser Einheit zugeordnet.',
        ),
      );
    }
    for (final suggestion
        in context.plan?.suggestions ?? const <PlanActual>[]) {
      insights.add(
        CoachInsight(
          kind: 'sessionToAssign',
          level: CoachInsightLevel.info,
          title: 'Einheit zuordnen?',
          detail:
              'Am ${_day(suggestion.planned.day)} passt eine Einheit '
              '(${(suggestion.actual!.durationSeconds / 60).round()} min) '
              'zur geplanten „${suggestion.planned.goal}“.',
        ),
      );
    }
    return insights;
  }
}

/// The plan-relevant part of a recorded session.
ActualSession actualOf(String athleteId, IntelligenceSession session) =>
    ActualSession(
      sessionId: session.id,
      athleteId: athleteId,
      startedAtUtcUs: session.startedAtUtcUs,
      durationSeconds: session.durationSeconds,
      sport: session.sport,
      finished: session.completed,
      // Imported activities carry a single synthetic interval, not a structure.
      intervalCount: session.providerId == null
          ? session.intervals.length
          : null,
      targetedIntervals: [
        for (final interval in session.intervals)
          if (interval.averagePowerWatt != null &&
              interval.targetMinWatt != null &&
              interval.targetMaxWatt != null)
            TargetedInterval(
              seconds: interval.durationSeconds,
              averagePowerWatt: interval.averagePowerWatt!,
              targetMinWatt: interval.targetMinWatt!,
              targetMaxWatt: interval.targetMaxWatt!,
            ),
      ],
    );

String _sportName(String key) =>
    DiagnosticSport.classify(sport: key)?.label ?? key;

String _load(double? value, String unit) {
  if (value == null) return 'unbekannt';
  final digits = unit.toLowerCase() == 'w' ? 0 : 1;
  return '${value.toStringAsFixed(digits).replaceAll('.', ',')} $unit';
}

String _date(int utcUs) {
  final day = CalendarDay.ofUtcUs(utcUs);
  return _day(day);
}

String _day(CalendarDay day) =>
    '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}';
