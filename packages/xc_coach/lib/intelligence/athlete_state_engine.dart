/// Deterministic feature engine for the persistent GIULIA Athlete State.
///
/// It aggregates measurements and applies already persisted LaLa thresholds.
/// It does not calculate a new physiological threshold and it does not turn
/// missing sleep, HRV or recovery data into a guessed fatigue score.
library;

import '../domain/source_authority.dart';
import 'athlete_state_models.dart';
import 'models.dart';

class AthleteStateEngine {
  const AthleteStateEngine({this.authority = const SourceAuthorityPolicy()});

  static const String version = 'giulia-athlete-state-v1';
  static const List<int> standardWindows = [7, 28, 90, 180, 365];

  final SourceAuthorityPolicy authority;

  AthleteState build({
    required String athleteId,
    required int asOfUtcUs,
    required String inputFingerprint,
    required List<IntelligenceSession> sessions,
    required List<IntelligenceTest> tests,
    required List<IntelligenceObservation> observations,
  }) {
    final eligibleSessions =
        sessions
            .where(
              (session) =>
                  session.completed && session.startedAtUtcUs <= asOfUtcUs,
            )
            .toList(growable: false)
          ..sort((a, b) => b.startedAtUtcUs.compareTo(a.startedAtUtcUs));
    final eligibleTests =
        tests
            .where((test) => test.startedAtUtcUs <= asOfUtcUs)
            .toList(growable: false)
          ..sort((a, b) => b.startedAtUtcUs.compareTo(a.startedAtUtcUs));
    final thresholds = _thresholdsBySport(eligibleTests);
    final windows = [
      for (final days in standardWindows)
        _window(
          days: days,
          asOfUtcUs: asOfUtcUs,
          sessions: eligibleSessions,
          thresholds: thresholds,
        ),
    ];
    final dataQuality = _quality(
      asOfUtcUs: asOfUtcUs,
      sessions: eligibleSessions,
      tests: eligibleTests,
    );
    final sports = _sports(
      asOfUtcUs: asOfUtcUs,
      sessions: eligibleSessions,
      tests: eligibleTests,
      windows: windows,
    );
    return AthleteState(
      athleteId: athleteId,
      asOfUtcUs: asOfUtcUs,
      featureEngineVersion: version,
      inputFingerprint: inputFingerprint,
      windows: windows,
      dimensions: _dimensions(
        windows: windows,
        sports: sports,
        observations: observations,
        dataQuality: dataQuality,
      ),
      sports: sports,
      dataQuality: dataQuality,
    );
  }

  Map<String, ({IntelligenceThreshold? lt1, IntelligenceThreshold? lt2})>
  _thresholdsBySport(List<IntelligenceTest> tests) {
    final result =
        <String, ({IntelligenceThreshold? lt1, IntelligenceThreshold? lt2})>{};
    for (final test in tests) {
      final sport = normalizeExternalSport(test.sport);
      if (result.containsKey(sport)) continue;
      final lt1 = test.threshold('lt1');
      final lt2 = test.threshold('lt2');
      if (lt1 != null || lt2 != null) result[sport] = (lt1: lt1, lt2: lt2);
    }
    return result;
  }

  AthleteTrainingWindow _window({
    required int days,
    required int asOfUtcUs,
    required List<IntelligenceSession> sessions,
    required Map<
      String,
      ({IntelligenceThreshold? lt1, IntelligenceThreshold? lt2})
    >
    thresholds,
  }) {
    final start = asOfUtcUs - days * Duration.microsecondsPerDay;
    final selected = sessions
        .where((session) => session.startedAtUtcUs >= start)
        .toList(growable: false);
    final sports = <String, int>{};
    var duration = 0;
    var distance = 0.0;
    var work = 0.0;
    var low = 0;
    var threshold = 0;
    var high = 0;
    final activeDays = <int>{};
    final activeWeeks = <int>{};
    for (final session in selected) {
      final sport = normalizeExternalSport(session.sport);
      duration += session.durationSeconds;
      distance += session.distanceMetres ?? 0;
      work += session.workJoule ?? 0;
      sports.update(
        sport,
        (value) => value + session.durationSeconds,
        ifAbsent: () => session.durationSeconds,
      );
      activeDays.add(session.startedAtUtcUs ~/ Duration.microsecondsPerDay);
      activeWeeks.add(
        (session.startedAtUtcUs - start) ~/ (7 * Duration.microsecondsPerDay),
      );
      final anchors = thresholds[sport];
      if (anchors?.lt1?.load == null || anchors?.lt2?.load == null) continue;
      for (final interval in session.intervals) {
        if (interval.kind != 'work' || interval.durationSeconds <= 0) continue;
        final load = _intervalLoad(interval, anchors!.lt2!.loadUnit);
        if (load == null) continue;
        if (load >= anchors.lt2!.load!) {
          high += interval.durationSeconds;
        } else if (load >= anchors.lt1!.load!) {
          threshold += interval.durationSeconds;
        } else {
          low += interval.durationSeconds;
        }
      }
    }
    return AthleteTrainingWindow(
      days: days,
      activityCount: selected.length,
      activeDays: activeDays.length,
      activeWeeks: activeWeeks.length,
      durationSeconds: duration,
      distanceMetres: distance,
      workJoule: work,
      longestGapDays: _longestGapDays(
        selected,
        startUtcUs: start,
        endUtcUs: asOfUtcUs,
      ),
      sportDurationSeconds: Map.unmodifiable(sports),
      lowIntensitySeconds: low,
      thresholdIntensitySeconds: threshold,
      highIntensitySeconds: high,
      classifiedIntensitySeconds: low + threshold + high,
    );
  }

  double? _intervalLoad(IntelligenceInterval interval, String unit) =>
      switch (unit.trim().toLowerCase()) {
        'w' => interval.averagePowerWatt,
        'km/h' => interval.averageSpeedKmh,
        _ => null,
      };

  double _longestGapDays(
    List<IntelligenceSession> sessions, {
    required int startUtcUs,
    required int endUtcUs,
  }) {
    if (sessions.isEmpty) {
      return (endUtcUs - startUtcUs) / Duration.microsecondsPerDay;
    }
    final points = sessions.map((item) => item.startedAtUtcUs).toList()..sort();
    var previous = startUtcUs;
    var longest = 0;
    for (final point in points) {
      final gap = point - previous;
      if (gap > longest) longest = gap;
      previous = point;
    }
    final tail = endUtcUs - previous;
    if (tail > longest) longest = tail;
    return longest / Duration.microsecondsPerDay;
  }

  List<SportAthleteState> _sports({
    required int asOfUtcUs,
    required List<IntelligenceSession> sessions,
    required List<IntelligenceTest> tests,
    required List<AthleteTrainingWindow> windows,
  }) {
    final window90 = windows.firstWhere((item) => item.days == 90);
    final window365 = windows.firstWhere((item) => item.days == 365);
    final names = <String>{
      ...window365.sportDurationSeconds.keys,
      for (final test in tests) normalizeExternalSport(test.sport),
    }.toList()..sort();
    return [
      for (final sport in names)
        _sportState(
          sport: sport,
          asOfUtcUs: asOfUtcUs,
          sessions: sessions,
          tests: tests,
          duration90: window90.sportDurationSeconds[sport] ?? 0,
          duration365: window365.sportDurationSeconds[sport] ?? 0,
        ),
    ];
  }

  SportAthleteState _sportState({
    required String sport,
    required int asOfUtcUs,
    required List<IntelligenceSession> sessions,
    required List<IntelligenceTest> tests,
    required int duration90,
    required int duration365,
  }) {
    final test = tests
        .where((item) => normalizeExternalSport(item.sport) == sport)
        .firstOrNull;
    final anchors = <AthleteStateEvidence>[
      if (test?.threshold('lt1') case final threshold?)
        _diagnosticEvidence(test!, threshold, 'lt1'),
      if (test?.threshold('lt2') case final threshold?)
        _diagnosticEvidence(test!, threshold, 'lt2'),
      if (test?.maximumLoad case final maximum?)
        AthleteStateEvidence(
          metric: 'maximum_test_load',
          value: maximum,
          unit: test!.loadUnit,
          providerId: 'giulia_diagnostic',
          authorityRank: authority.rank(
            'giulia_diagnostic',
            ExternalMetric.physiologicalThreshold,
          ),
          sourceId: test.id,
          observedAtUtcUs: test.startedAtUtcUs,
        ),
    ];
    final activityCount = sessions
        .where((session) => normalizeExternalSport(session.sport) == sport)
        .where(
          (session) =>
              session.startedAtUtcUs >=
              asOfUtcUs - 365 * Duration.microsecondsPerDay,
        )
        .length;
    final missing = <String>[
      if (test?.threshold('lt1') == null) 'keine gemessene LTP1',
      if (test?.threshold('lt2') == null) 'keine gemessene LTP2',
    ];
    return SportAthleteState(
      sport: sport,
      activityCount365Days: activityCount,
      durationSeconds90Days: duration90,
      durationSeconds365Days: duration365,
      confidence: anchors.length >= 2 && activityCount >= 10
          ? IntelligenceConfidence.high
          : anchors.isNotEmpty || activityCount >= 5
          ? IntelligenceConfidence.moderate
          : activityCount > 0
          ? IntelligenceConfidence.low
          : IntelligenceConfidence.insufficient,
      anchors: anchors,
      missing: missing,
    );
  }

  AthleteStateEvidence _diagnosticEvidence(
    IntelligenceTest test,
    IntelligenceThreshold threshold,
    String metric,
  ) => AthleteStateEvidence(
    metric: metric,
    value: threshold.load!,
    unit: threshold.loadUnit,
    providerId: 'giulia_diagnostic',
    authorityRank: authority.rank(
      'giulia_diagnostic',
      ExternalMetric.physiologicalThreshold,
    ),
    sourceId: test.id,
    observedAtUtcUs: test.startedAtUtcUs,
  );

  AthleteStateDataQuality _quality({
    required int asOfUtcUs,
    required List<IntelligenceSession> sessions,
    required List<IntelligenceTest> tests,
  }) {
    final providers = <String, int>{};
    for (final session in sessions) {
      final provider = session.providerId ?? 'giulia';
      providers.update(provider, (value) => value + 1, ifAbsent: () => 1);
    }
    final historyDays = sessions.isEmpty
        ? 0
        : ((asOfUtcUs - sessions.last.startedAtUtcUs) /
                      Duration.microsecondsPerDay)
                  .floor() +
              1;
    final withHeartRate = sessions
        .where((item) => item.averageHeartRateBpm != null)
        .length;
    final withLoad = sessions
        .where(
          (item) =>
              item.averagePowerWatt != null ||
              item.averageSpeedKmh != null ||
              item.distanceMetres != null,
        )
        .length;
    final missing = <String>[
      if (historyDays < 90) 'weniger als 90 Tage Trainingshistorie',
      if (withHeartRate < sessions.length / 2) 'geringe Herzfrequenzabdeckung',
      if (tests.isEmpty) 'keine Leistungsdiagnostik',
      'keine kontinuierliche HRV-/Schlaf-/Erholungszeitreihe',
    ];
    final confidence =
        historyDays >= 180 && sessions.length >= 40 && tests.isNotEmpty
        ? IntelligenceConfidence.high
        : historyDays >= 90 && sessions.length >= 20
        ? IntelligenceConfidence.moderate
        : sessions.isNotEmpty
        ? IntelligenceConfidence.low
        : IntelligenceConfidence.insufficient;
    return AthleteStateDataQuality(
      historyDays: historyDays,
      activityCount: sessions.length,
      activitiesWithHeartRate: withHeartRate,
      activitiesWithExternalLoad: withLoad,
      diagnosticTestCount: tests.length,
      providerActivityCounts: Map.unmodifiable(providers),
      missing: missing,
      confidence: confidence,
    );
  }

  List<AthleteStateDimension> _dimensions({
    required List<AthleteTrainingWindow> windows,
    required List<SportAthleteState> sports,
    required List<IntelligenceObservation> observations,
    required AthleteStateDataQuality dataQuality,
  }) {
    final w7 = windows.firstWhere((item) => item.days == 7);
    final w28 = windows.firstWhere((item) => item.days == 28);
    final w180 = windows.firstWhere((item) => item.days == 180);
    final w365 = windows.firstWhere((item) => item.days == 365);
    final previous21Seconds = w28.durationSeconds - w7.durationSeconds;
    final referenceWeek = previous21Seconds / 3;
    final loadChange = referenceWeek <= 0
        ? null
        : (w7.durationSeconds - referenceWeek) / referenceWeek * 100;
    final lt1 = [for (final sport in sports) ?sport.anchor('lt1')];
    final lt2 = [for (final sport in sports) ?sport.anchor('lt2')];
    final maxima = [
      for (final sport in sports) ?sport.anchor('maximum_test_load'),
    ];
    final reserveEvidence = <AthleteStateEvidence>[];
    final reserveValues = <String, num>{};
    for (final sport in sports) {
      final upper = sport.anchor('lt2');
      final maximum = sport.anchor('maximum_test_load');
      if (upper == null || maximum == null || upper.unit != maximum.unit) {
        continue;
      }
      final reserve = maximum.value - upper.value;
      reserveValues['${sport.sport}Reserve'] = reserve;
      reserveEvidence.add(
        AthleteStateEvidence(
          metric: '${sport.sport}_measured_reserve',
          value: reserve,
          unit: maximum.unit,
          providerId: 'giulia_feature_engine',
          authorityRank: 800,
          sourceId: maximum.sourceId,
          observedAtUtcUs: maximum.observedAtUtcUs,
        ),
      );
    }
    final latestRpe = observations
        .where(
          (item) =>
              item.usable &&
              item.type == IntelligenceObservationType.rpe &&
              item.value != null,
        )
        .lastOrNull;
    return [
      AthleteStateDimension(
        key: 'aerobic_base',
        label: 'Aerobe Basis',
        assessment: lt1.isNotEmpty
            ? 'durch aktuelle LTP1-Diagnostik kalibriert'
            : w90Assessment(windows),
        confidence: lt1.isNotEmpty
            ? IntelligenceConfidence.high
            : dataQuality.confidence,
        values: {
          'durationHours90Days': windows
              .firstWhere((item) => item.days == 90)
              .durationHours,
          'activeWeeks180Days': w180.activeWeeks,
        },
        evidence: lt1,
        missing: [if (lt1.isEmpty) 'sportartspezifische LTP1-Diagnostik'],
        caveat:
            'Trainingsumfang beschreibt Exposition; aerobe Leistungsfähigkeit '
            'wird ohne Diagnostik nicht als Stärkegrad behauptet.',
      ),
      AthleteStateDimension(
        key: 'threshold_performance',
        label: 'Schwellenleistung',
        assessment: lt2.isNotEmpty
            ? 'durch aktuelle LTP2-Diagnostik kalibriert'
            : 'noch nicht diagnostisch kalibriert',
        confidence: lt2.isNotEmpty
            ? IntelligenceConfidence.high
            : IntelligenceConfidence.insufficient,
        values: const {},
        evidence: lt2,
        missing: [if (lt2.isEmpty) 'sportartspezifische LTP2-Diagnostik'],
      ),
      AthleteStateDimension(
        key: 'high_intensity_capacity',
        label: 'Hochintensive Leistungsfähigkeit',
        assessment: reserveEvidence.isNotEmpty
            ? 'gemessene Reserve oberhalb LTP2 vorhanden'
            : maxima.isNotEmpty
            ? 'Maximalstufe vorhanden, aber keine kompatible LTP2-Reserve'
            : 'nicht belastbar quantifizierbar',
        confidence: reserveEvidence.isNotEmpty
            ? IntelligenceConfidence.moderate
            : IntelligenceConfidence.low,
        values: {
          ...reserveValues,
          'highIntensityHours28Days':
              w28.highIntensitySeconds / Duration.secondsPerHour,
        },
        evidence: reserveEvidence,
        missing: [
          if (reserveEvidence.isEmpty) 'kompatible LTP2 und Maximalstufe',
        ],
        caveat:
            'Die Stufentestreserve ist keine direkte Messung anaerober '
            'Kapazität.',
      ),
      AthleteStateDimension(
        key: 'training_tolerance',
        label: 'Trainingsverträglichkeit',
        assessment: loadChange == null
            ? 'noch keine 28-Tage-Referenz'
            : loadChange > 40
            ? 'kurzfristige Belastung deutlich erhöht'
            : loadChange < -40
            ? 'kurzfristige Belastung deutlich reduziert'
            : 'Trainingsumfang gegenüber den Vorwochen stabil',
        confidence: loadChange == null
            ? IntelligenceConfidence.insufficient
            : IntelligenceConfidence.moderate,
        values: {
          'durationHours7Days': w7.durationHours,
          'durationChangePercent': ?loadChange,
        },
        evidence: const [],
        missing: [if (loadChange == null) 'drei vollständige Referenzwochen'],
        caveat:
            'Belastungsverlauf ist beobachtbar; biologische Verträglichkeit '
            'braucht zusätzlich Erholung und subjektive Rückmeldung.',
      ),
      AthleteStateDimension(
        key: 'fatigue',
        label: 'Ermüdung',
        assessment: latestRpe == null
            ? 'ohne Erholungsdaten nicht zuverlässig ableitbar'
            : latestRpe.value! >= 8
            ? 'letztes subjektives Belastungsempfinden hoch'
            : 'keine hohe subjektive Belastung im letzten RPE belegt',
        confidence: latestRpe == null
            ? IntelligenceConfidence.insufficient
            : IntelligenceConfidence.low,
        values: {if (latestRpe?.value != null) 'latestRpe': latestRpe!.value!},
        evidence: const [],
        missing: const ['HRV', 'Schlaf', 'subjektive Erholung'],
        caveat: 'GIULIA leitet aus Trainingslast allein keine Ermüdung ab.',
      ),
      AthleteStateDimension(
        key: 'current_load',
        label: 'Aktuelle Belastung',
        assessment: w7.activityCount == 0
            ? 'keine Aktivität in den letzten sieben Tagen'
            : '${w7.activityCount} Aktivitäten in sieben Tagen',
        confidence: IntelligenceConfidence.high,
        values: {
          'activities7Days': w7.activityCount,
          'durationHours7Days': w7.durationHours,
          'workKiloJoule7Days': w7.workJoule / 1000,
        },
        evidence: const [],
      ),
      AthleteStateDimension(
        key: 'long_term_capacity',
        label: 'Langfristige Belastbarkeit',
        assessment: dataQuality.historyDays >= 180
            ? 'langfristiger Trainingsverlauf vorhanden'
            : 'Historie für Langzeitaussagen noch zu kurz',
        confidence: dataQuality.historyDays >= 180
            ? IntelligenceConfidence.moderate
            : IntelligenceConfidence.low,
        values: {
          'durationHours180Days': w180.durationHours,
          'durationHours365Days': w365.durationHours,
          'activeWeeks365Days': w365.activeWeeks,
          'longestGapDays365Days': w365.longestGapDays,
        },
        evidence: const [],
        missing: [
          if (dataQuality.historyDays < 180) 'mindestens 180 Tage Historie',
        ],
        caveat:
            'Historischer Umfang ist kein medizinischer Belastbarkeitstest.',
      ),
      AthleteStateDimension(
        key: 'data_quality',
        label: 'Datenqualität und Unsicherheit',
        assessment: switch (dataQuality.confidence) {
          IntelligenceConfidence.high => 'breite longitudinale Datengrundlage',
          IntelligenceConfidence.moderate =>
            'brauchbare, noch lückenhafte Grundlage',
          IntelligenceConfidence.low => 'begrenzte Datengrundlage',
          IntelligenceConfidence.insufficient => 'keine ausreichende Grundlage',
        },
        confidence: dataQuality.confidence,
        values: {
          'historyDays': dataQuality.historyDays,
          'activityCount': dataQuality.activityCount,
          'activitiesWithHeartRate': dataQuality.activitiesWithHeartRate,
          'diagnosticTestCount': dataQuality.diagnosticTestCount,
        },
        evidence: const [],
        missing: dataQuality.missing,
      ),
    ];
  }

  String w90Assessment(List<AthleteTrainingWindow> windows) {
    final window = windows.firstWhere((item) => item.days == 90);
    return window.activityCount == 0
        ? 'keine Trainingshistorie für eine Einordnung'
        : 'aus Trainingskontinuität beschrieben, nicht physiologisch gemessen';
  }
}
