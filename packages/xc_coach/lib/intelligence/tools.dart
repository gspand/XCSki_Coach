/// The tool/function boundary for GIULIA Intelligence.
///
/// DATA -> deterministic analysis -> structured context -> coach wording.
/// Every public method corresponds to a callable coach tool and records its
/// exact structured output. No tool asks a language model to calculate a
/// threshold, a load, a trend or readiness.
library;

import '../academy/academy_library.dart';
import '../academy/academy_search.dart';
import '../domain/diagnostic_catalogue.dart';
import '../domain/training_plan.dart';
import 'athlete_state_models.dart';
import 'coach_context.dart';
import 'deterministic_analysis.dart';
import 'models.dart';

typedef IntelligenceToolObserver = void Function(IntelligenceToolCall call);

class GiuliaIntelligenceTools {
  GiuliaIntelligenceTools({
    required this.data,
    this.observer,
    this.longitudinal = const LongitudinalIntelligence(),
    this.loadAnalyzer = const TrainingLoadAnalyzer(),
    this.readinessAnalyzer = const ReadinessAnalyzer(),
    this.ercolinaIntelligence = const ErcolinaIntelligence(),
    this.coachContext,
  });

  final IntelligenceDataSource data;
  final IntelligenceToolObserver? observer;
  final LongitudinalIntelligence longitudinal;
  final TrainingLoadAnalyzer loadAnalyzer;
  final ReadinessAnalyzer readinessAnalyzer;
  final ErcolinaIntelligence ercolinaIntelligence;

  /// Plan, history and per-sport physiology. Absent where no plan exists.
  final CoachContextBuilder? coachContext;
  final List<IntelligenceToolCall> _trace = [];
  final Map<String, AthleteState?> _athleteStateCache = {};

  List<IntelligenceToolCall> get trace => List.unmodifiable(_trace);
  void clearTrace() {
    _trace.clear();
    _athleteStateCache.clear();
  }

  IntelligenceAthlete? getAthleteProfile(String athleteId) {
    final value = data.getAthleteProfile(athleteId);
    _record(
      'getAthleteProfile',
      {'athleteId': athleteId},
      value?.toJson(),
      missing: value == null
          ? const ['Athletenprofil oder Freigabe']
          : const [],
    );
    return value;
  }

  AthleteState? getAthleteState(String athleteId, {required int nowUtcUs}) {
    final source = data;
    final value = source is AthleteStateDataSource
        ? (source as AthleteStateDataSource).getAthleteState(
            athleteId,
            nowUtcUs: nowUtcUs,
          )
        : null;
    _athleteStateCache[athleteId] = value;
    _record(
      'getAthleteState',
      {'athleteId': athleteId, 'nowUtcUs': nowUtcUs},
      value?.toJson(),
      missing: value == null
          ? const ['persistenter GIULIA Athlete State']
          : value.dataQuality.missing,
    );
    return value;
  }

  List<IntelligenceSession> getRecentTraining(
    String athleteId, {
    int? fromUtcUs,
    int limit = 40,
  }) {
    final value = data.getRecentTraining(
      athleteId,
      fromUtcUs: fromUtcUs,
      limit: limit,
    );
    _record(
      'getRecentTraining',
      {'athleteId': athleteId, 'fromUtcUs': ?fromUtcUs, 'limit': limit},
      [for (final session in value) session.toJson()],
      missing: value.isEmpty ? const ['aufgezeichnete Einheiten'] : const [],
    );
    return value;
  }

  TrainingLoadContext getTrainingLoad(
    String athleteId, {
    required int nowUtcUs,
  }) {
    final sessions = data.getRecentTraining(
      athleteId,
      fromUtcUs: nowUtcUs - 28 * Duration.microsecondsPerDay,
      limit: 200,
    );
    final tests = data.getTests(athleteId, limit: 10);
    final threshold = _latestThreshold(tests, 'lt2');
    final value = loadAnalyzer.analyze(
      sessions: sessions,
      nowUtcUs: nowUtcUs,
      lt2: threshold,
      lt2BySport: _lt2BySport(tests),
    );
    _record(
      'getTrainingLoad',
      {'athleteId': athleteId, 'nowUtcUs': nowUtcUs},
      value.toJson(),
      missing: value.missing,
    );
    return value;
  }

  IntelligenceTest? getLatestTest(String athleteId, {String? sport}) {
    final tests = data.getTests(athleteId, limit: 20);
    final value = tests
        .where(
          (test) =>
              sport == null ||
              test.sportKey == diagnosticComparisonSport(sport: sport),
        )
        .firstOrNull;
    _record(
      'getLatestTest',
      {'athleteId': athleteId, 'sport': ?sport},
      value?.toJson(),
      missing: value == null ? const ['ausgewerteter Stufentest'] : const [],
    );
    return value;
  }

  TestComparisonContext? compareTests(
    String athleteId, {
    String? earlierTestId,
    String? laterTestId,
  }) {
    final tests = data.getTests(athleteId, limit: 20);
    IntelligenceTest? earlier;
    IntelligenceTest? later;
    if (earlierTestId != null && laterTestId != null) {
      earlier = tests.where((test) => test.id == earlierTestId).firstOrNull;
      later = tests.where((test) => test.id == laterTestId).firstOrNull;
    } else if (tests.length >= 2) {
      // Prefer the same sport; otherwise the comparison states explicitly
      // why two sports are not compared.
      later = tests[0];
      earlier =
          tests
              .skip(1)
              .where((test) => test.sportKey == tests[0].sportKey)
              .firstOrNull ??
          tests[1];
    }
    final value = earlier == null || later == null
        ? null
        : longitudinal.compare(earlier, later);
    _record(
      'compareTests',
      {
        'athleteId': athleteId,
        'earlierTestId': ?earlierTestId,
        'laterTestId': ?laterTestId,
      },
      value?.toJson(),
      missing: value == null
          ? const ['mindestens zwei auswertbare Tests']
          : const [],
    );
    return value;
  }

  List<IntelligenceCurvePoint> getLactateCurve(
    String athleteId, {
    String? testId,
  }) {
    final tests = data.getTests(athleteId, limit: 20);
    final test = testId == null
        ? tests.firstOrNull
        : tests.where((item) => item.id == testId).firstOrNull;
    final value = test?.curve ?? const <IntelligenceCurvePoint>[];
    _record(
      'getLactateCurve',
      {'athleteId': athleteId, 'testId': ?testId},
      [for (final point in value) point.toJson()],
      missing: value.isEmpty ? const ['Laktatkurve'] : const [],
    );
    return value;
  }

  List<IntelligenceThreshold> getThresholds(
    String athleteId, {
    String? testId,
    bool selectedOnly = false,
  }) {
    final tests = data.getTests(athleteId, limit: 20);
    final test = testId == null
        ? tests.firstOrNull
        : tests.where((item) => item.id == testId).firstOrNull;
    final value = <IntelligenceThreshold>[
      for (final threshold in test?.thresholds ?? const [])
        if (!selectedOnly || threshold.selected) threshold,
    ];
    _record(
      'getThresholds',
      {'athleteId': athleteId, 'testId': ?testId, 'selectedOnly': selectedOnly},
      [for (final threshold in value) threshold.toJson()],
      missing: value.isEmpty ? const ['persistierte Schwellen'] : const [],
    );
    return value;
  }

  List<IntelligenceZone> getTrainingZones(String athleteId, {String? testId}) {
    final tests = data.getTests(athleteId, limit: 20);
    final test = testId == null
        ? tests.firstOrNull
        : tests.where((item) => item.id == testId).firstOrNull;
    final value = test?.zones ?? const <IntelligenceZone>[];
    _record(
      'getTrainingZones',
      {'athleteId': athleteId, 'testId': ?testId},
      [for (final zone in value) zone.toJson()],
      missing: value.isEmpty ? const ['berechnete Trainingszonen'] : const [],
    );
    return value;
  }

  IntelligenceSession? getSessionMetrics(
    String athleteId, {
    String? sessionId,
  }) {
    final sessions = data.getRecentTraining(athleteId, limit: 100);
    final value = sessionId == null
        ? sessions.firstOrNull
        : sessions.where((item) => item.id == sessionId).firstOrNull;
    _record(
      'getSessionMetrics',
      {'athleteId': athleteId, 'sessionId': ?sessionId},
      value?.toJson(),
      missing: value == null ? const ['Sitzungsmetriken'] : const [],
    );
    return value;
  }

  ErcolinaContext getErcolinaMetrics(String athleteId, {String? sessionId}) {
    final sessions = data.getRecentTraining(athleteId, limit: 100);
    final selected = sessionId == null
        ? sessions
        : sessions.where((item) => item.id == sessionId).toList();
    final value = ercolinaIntelligence.analyze(selected);
    _record(
      'getErcolinaMetrics',
      {'athleteId': athleteId, 'sessionId': ?sessionId},
      value.toJson(),
      missing: value.missing,
    );
    return value;
  }

  List<IntelligenceTrend> getTrends(String athleteId) {
    final value = longitudinal.trends(data.getTests(athleteId, limit: 20));
    _record(
      'getTrends',
      {'athleteId': athleteId},
      [for (final trend in value) trend.toJson()],
      missing: value.isEmpty
          ? const ['mindestens zwei vergleichbare Tests']
          : const [],
    );
    return value;
  }

  ReadinessContext getReadinessContext(
    String athleteId, {
    required int nowUtcUs,
  }) {
    final sessions = data.getRecentTraining(
      athleteId,
      fromUtcUs: nowUtcUs - 28 * Duration.microsecondsPerDay,
      limit: 200,
    );
    final tests = data.getTests(athleteId, limit: 20);
    final observations = data.getObservations(
      athleteId,
      fromUtcUs: nowUtcUs - 14 * Duration.microsecondsPerDay,
    );
    final lt2 = _latestThreshold(tests, 'lt2');
    final lt2BySport = _lt2BySport(tests);
    final load = loadAnalyzer.analyze(
      sessions: sessions,
      nowUtcUs: nowUtcUs,
      lt2: lt2,
      lt2BySport: lt2BySport,
    );
    final value = readinessAnalyzer.analyze(
      sessions: sessions,
      observations: observations,
      load: load,
      nowUtcUs: nowUtcUs,
      lt2: lt2,
      lt2BySport: lt2BySport,
      athleteState: _athleteStateCache[athleteId],
    );
    _record(
      'getReadinessContext',
      {'athleteId': athleteId, 'nowUtcUs': nowUtcUs},
      value.toJson(),
      missing: value.missing,
    );
    return value;
  }

  List<AcademyKnowledge> getRelevantAcademyKnowledge(
    String query, {
    int limit = 3,
  }) {
    final value = searchAcademy(query, library: academyLibrary)
        .take(limit)
        .map(
          (article) => AcademyKnowledge(
            articleId: article.id,
            title: article.title,
            summary: article.summary,
            evidenceLabel: article.evidence.label,
          ),
        )
        .toList(growable: false);
    _record(
      'getRelevantAcademyKnowledge',
      {'query': query, 'limit': limit},
      [for (final item in value) item.toJson()],
      missing: value.isEmpty ? const ['passender Academy-Inhalt'] : const [],
    );
    return value;
  }

  IntelligenceThreshold? _latestThreshold(
    List<IntelligenceTest> tests,
    String type,
  ) {
    for (final test in tests) {
      final value = test.threshold(type);
      if (value != null) return value;
    }
    return null;
  }

  /// Newest LT2 per sport; tests come newest first.
  Map<String, IntelligenceThreshold> _lt2BySport(List<IntelligenceTest> tests) {
    final result = <String, IntelligenceThreshold>{};
    for (final test in tests) {
      final value = test.threshold('lt2');
      if (value != null) result.putIfAbsent(test.sportKey, () => value);
    }
    return result;
  }

  /// The athlete's plan, week and per-sport physiology, or null without a
  /// plan source.
  CoachContext? getCoachContext(String athleteId, {required int nowUtcUs}) {
    final value = coachContext?.build(athleteId, nowUtcUs: nowUtcUs);
    _record(
      'getCoachContext',
      {'athleteId': athleteId, 'nowUtcUs': nowUtcUs},
      value == null
          ? null
          : {
              'athleteId': value.athleteId,
              'available': value.available,
              'today': [
                for (final item in value.plan?.todays ?? const <PlanActual>[])
                  item.planned.toJson(),
              ],
              'upcoming': [
                for (final item
                    in value.plan?.upcoming ?? const <PlannedWorkout>[])
                  item.toJson(),
              ],
              'sessionsThisWeek': [
                for (final item in value.sessionsThisWeek())
                  item.session.toJson(),
              ],
              'physiology': [
                for (final item in value.physiology)
                  {
                    'sport': item.sportKey,
                    'testId': item.testId,
                    'performedAtUtcUs': item.performedAtUtcUs,
                    'ltp1': item.powerOrSpeedAtLtp1,
                    'ltp2': item.powerOrSpeedAtLtp2,
                    'heartRateAtLtp1': item.heartRateAtLtp1,
                    'heartRateAtLtp2': item.heartRateAtLtp2,
                    'loadUnit': item.loadUnit,
                  },
              ],
            },
      missing: value == null ? const ['Trainingsplan'] : value.missing,
    );
    return value;
  }

  void _record(
    String name,
    Map<String, Object?> arguments,
    Object? output, {
    List<String> missing = const [],
  }) {
    final call = IntelligenceToolCall(
      name: name,
      arguments: arguments,
      output: output,
      missing: missing,
    );
    _trace.add(call);
    observer?.call(call);
  }
}

enum IntelligenceIntent {
  readiness,
  lactate,
  threshold,
  testComparison,
  zones,
  ercolina,
  plan,
  history,
  substitution,
  general,
}

class PreparedCoachContext {
  const PreparedCoachContext({
    required this.intent,
    required this.structured,
    this.athlete,
    this.athleteState,
    this.latestTest,
    this.comparison,
    this.trends = const [],
    this.readiness,
    this.zones = const [],
    this.ercolina,
    this.knowledge = const [],
    this.coach,
  });

  final IntelligenceIntent intent;
  final StructuredCoachContext structured;
  final IntelligenceAthlete? athlete;
  final AthleteState? athleteState;
  final IntelligenceTest? latestTest;
  final TestComparisonContext? comparison;
  final List<IntelligenceTrend> trends;
  final ReadinessContext? readiness;
  final List<IntelligenceZone> zones;
  final ErcolinaContext? ercolina;
  final List<AcademyKnowledge> knowledge;

  /// Plan, week and per-sport physiology of the asked-about athlete.
  final CoachContext? coach;
}

class GiuliaContextBuilder {
  GiuliaContextBuilder(this.tools);

  final GiuliaIntelligenceTools tools;

  PreparedCoachContext build({
    required String question,
    required String athleteId,
    required int nowUtcUs,
  }) {
    tools.clearTrace();
    final intent = classify(question);
    final athlete = tools.getAthleteProfile(athleteId);
    final athleteState = tools.getAthleteState(athleteId, nowUtcUs: nowUtcUs);
    IntelligenceTest? latest;
    TestComparisonContext? comparison;
    List<IntelligenceTrend> trends = const [];
    ReadinessContext? readiness;
    List<IntelligenceZone> zones = const [];
    ErcolinaContext? ercolina;
    CoachContext? coach;

    switch (intent) {
      case IntelligenceIntent.readiness:
        readiness = tools.getReadinessContext(athleteId, nowUtcUs: nowUtcUs);
        coach = tools.getCoachContext(athleteId, nowUtcUs: nowUtcUs);
        break;
      case IntelligenceIntent.plan ||
          IntelligenceIntent.history ||
          IntelligenceIntent.substitution:
        coach = tools.getCoachContext(athleteId, nowUtcUs: nowUtcUs);
        readiness = coach?.state?.readiness;
        break;
      case IntelligenceIntent.lactate:
        latest = tools.getLatestTest(athleteId);
        if (latest != null) {
          tools.getLactateCurve(athleteId, testId: latest.id);
        }
        comparison = tools.compareTests(athleteId);
        trends = tools.getTrends(athleteId);
        break;
      case IntelligenceIntent.threshold || IntelligenceIntent.testComparison:
        latest = tools.getLatestTest(athleteId);
        if (latest != null) {
          tools.getThresholds(athleteId, testId: latest.id);
        }
        comparison = tools.compareTests(athleteId);
        trends = tools.getTrends(athleteId);
        break;
      case IntelligenceIntent.zones:
        latest = tools.getLatestTest(athleteId);
        zones = tools.getTrainingZones(athleteId, testId: latest?.id);
        break;
      case IntelligenceIntent.ercolina:
        ercolina = tools.getErcolinaMetrics(athleteId);
        break;
      case IntelligenceIntent.general:
        latest = tools.getLatestTest(athleteId);
        readiness = tools.getReadinessContext(athleteId, nowUtcUs: nowUtcUs);
        trends = tools.getTrends(athleteId);
        break;
    }

    final knowledge = tools.getRelevantAcademyKnowledge(
      _academyQuery(intent, question),
    );
    return PreparedCoachContext(
      intent: intent,
      structured: StructuredCoachContext(
        question: question,
        athleteId: athleteId,
        calls: tools.trace,
      ),
      athlete: athlete,
      athleteState: athleteState,
      latestTest: latest,
      comparison: comparison,
      trends: trends,
      readiness: readiness,
      zones: zones,
      ercolina: ercolina,
      knowledge: knowledge,
      coach: coach,
    );
  }

  IntelligenceIntent classify(String question) {
    final value = question.trim().toLowerCase();
    if (value.contains(' statt ')) return IntelligenceIntent.substitution;
    if (_containsAny(value, [
          'steht heute an',
          'was steht',
          'geplant',
          'mein plan',
          'trainingsplan',
          'warum mache ich',
        ]) ||
        (value.contains('warum') &&
            value.contains('heute') &&
            _containsAny(value, ['soll ich', 'mache ich', 'einheit']))) {
      return IntelligenceIntent.plan;
    }
    if (_containsAny(value, [
      'was habe ich',
      'diese woche',
      'absolviert',
      'tatsächlich gemacht',
    ])) {
      return IntelligenceIntent.history;
    }
    if (_containsAny(value, [
      'heute train',
      'morgen interval',
      'soll ich',
      'bereit',
      'readiness',
      'erholt',
    ])) {
      return IntelligenceIntent.readiness;
    }
    if (_containsAny(value, ['laktat', 'lactate'])) {
      return IntelligenceIntent.lactate;
    }
    if (_containsAny(value, ['trainingszone', 'zone', 'bereich'])) {
      return IntelligenceIntent.zones;
    }
    if (_containsAny(value, [
      'ercolina',
      'technik',
      'symmetrie',
      'links',
      'rechts',
      'zug',
    ])) {
      return IntelligenceIntent.ercolina;
    }
    if (_containsAny(value, [
      'vergleich',
      'entwicklung',
      'entwickelt',
      'verbessert',
    ])) {
      return IntelligenceIntent.testComparison;
    }
    if (_containsAny(value, [
      'schwelle',
      'ltp1',
      'ltp2',
      'stufentest',
      'test',
    ])) {
      return IntelligenceIntent.threshold;
    }
    return IntelligenceIntent.general;
  }

  String _academyQuery(IntelligenceIntent intent, String question) =>
      switch (intent) {
        IntelligenceIntent.readiness => 'Erholung',
        IntelligenceIntent.lactate => 'Laktat',
        IntelligenceIntent.threshold => 'LTP2',
        IntelligenceIntent.testComparison => 'Fortschritt LTP1 LTP2',
        IntelligenceIntent.zones => 'Trainingszonen LT1 LT2',
        IntelligenceIntent.ercolina => 'Technik Symmetrie Ercolina',
        IntelligenceIntent.plan => 'Trainingsplanung',
        IntelligenceIntent.history => 'Trainingsumfang',
        IntelligenceIntent.substitution => 'Trainingszonen Sportart',
        IntelligenceIntent.general => question,
      };

  bool _containsAny(String value, List<String> needles) =>
      needles.any(value.contains);
}
