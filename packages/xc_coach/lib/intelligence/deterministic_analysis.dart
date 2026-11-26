/// Deterministic longitudinal, load, readiness and Ercolina interpretation.
///
/// No threshold is determined here. Every threshold value enters as an
/// immutable, versioned result from LaLa. This layer only compares compatible
/// persisted facts and states when the data does not support an answer.
library;

import 'dart:math' as math;

import '../domain/diagnostic_catalogue.dart';
import '../domain/diagnostic_comparability.dart';
import 'athlete_state_models.dart';
import 'models.dart';

class LongitudinalIntelligence {
  const LongitudinalIntelligence();

  TestComparisonContext compare(
    IntelligenceTest earlier,
    IntelligenceTest later,
  ) {
    final blocked = diagnosticIncomparability(
      earlierSport: earlier.sportKey,
      laterSport: later.sportKey,
      earlierLoadUnit: earlier.loadUnit,
      laterLoadUnit: later.loadUnit,
      earlierStructure: earlier.structure,
      laterStructure: later.structure,
      earlierLoadSemantics: earlier.loadSemantics,
      laterLoadSemantics: later.loadSemantics,
    );
    if (blocked != null) {
      return TestComparisonContext(
        earlier: earlier,
        later: later,
        comparable: false,
        trends: const [],
        caveats: [blocked],
        confidence: IntelligenceConfidence.insufficient,
      );
    }

    final caveats = <String>[];
    if (earlier.engineVersion != later.engineVersion) {
      caveats.add(
        'Die Tests wurden mit unterschiedlichen LaLa-Engine-Versionen '
        'ausgewertet.',
      );
    }
    final trends = <IntelligenceTrend>[
      for (final type in const ['lt1', 'lt2'])
        ?_thresholdTrend(earlier, later, type, caveats),
      ?_maximumTrend(earlier, later),
      ?_reserveTrend(earlier, later),
      ?_comparableLactateTrend(earlier, later),
    ];

    final methodsChanged = <String>[];
    for (final type in const ['lt1', 'lt2']) {
      final a = earlier.threshold(type);
      final b = later.threshold(type);
      if (a != null && b != null && a.methodId != b.methodId) {
        methodsChanged.add(type.toUpperCase());
      }
    }
    if (methodsChanged.isNotEmpty) {
      caveats.add(
        '${methodsChanged.join(' und ')} wurden mit unterschiedlichen '
        'Methoden bestimmt. Die Differenz ist daher nur eingeschränkt '
        'physiologisch interpretierbar.',
      );
    }

    return TestComparisonContext(
      earlier: earlier,
      later: later,
      comparable: true,
      trends: trends,
      caveats: caveats,
      confidence: caveats.isEmpty
          ? IntelligenceConfidence.high
          : IntelligenceConfidence.moderate,
    );
  }

  List<IntelligenceTrend> trends(List<IntelligenceTest> newestFirst) {
    final evaluated = newestFirst
        .where(
          (test) =>
              test.threshold('lt1') != null || test.threshold('lt2') != null,
        )
        .toList(growable: false);
    if (evaluated.length < 2) return const [];

    final reference = evaluated.first;
    final compatible = <IntelligenceTest>[];
    for (final test in evaluated) {
      final blocked = diagnosticIncomparability(
        earlierSport: test.sport,
        laterSport: reference.sport,
        earlierLoadUnit: test.loadUnit,
        laterLoadUnit: reference.loadUnit,
        earlierStructure: test.structure,
        laterStructure: reference.structure,
        earlierLoadSemantics: test.loadSemantics,
        laterLoadSemantics: reference.loadSemantics,
      );
      if (blocked == null) compatible.add(test);
    }
    if (compatible.length < 2) return const [];
    compatible.sort((a, b) => a.startedAtUtcUs.compareTo(b.startedAtUtcUs));

    final out = <IntelligenceTrend>[];
    for (final type in const ['lt1', 'lt2']) {
      final values = <({IntelligenceTest test, IntelligenceThreshold value})>[
        for (final test in compatible)
          if (test.threshold(type) case final value?)
            (test: test, value: value),
      ];
      if (values.length < 2) continue;
      final first = values.first;
      final last = values.last;
      final delta = last.value.load! - first.value.load!;
      final percent = _percent(delta, first.value.load!);
      final methods = values.map((item) => item.value.methodId).toSet();
      final direction = _direction(percent, thresholdPercent: 1.5);
      final plateau =
          values.length >= 3 &&
          values.every(
            (item) =>
                ((item.value.load! - first.value.load!) /
                        first.value.load! *
                        100)
                    .abs() <
                1.5,
          );
      out.add(
        IntelligenceTrend(
          parameter: type,
          direction: plateau ? TrendDirection.stable : direction,
          summary: plateau
              ? '${type.toUpperCase()} ist über ${values.length} vergleichbare '
                    'Tests stabil; das ist ein Plateau, keine Verschlechterung.'
              : '${type.toUpperCase()} hat sich über ${values.length} '
                    'vergleichbare Tests ${_directionWords(direction)}.',
          confidence: methods.length == 1
              ? (values.length >= 3
                    ? IntelligenceConfidence.high
                    : IntelligenceConfidence.moderate)
              : IntelligenceConfidence.low,
          delta: delta,
          deltaPercent: percent,
          unit: last.value.loadUnit,
          evidence: [
            _thresholdEvidence(first.test, first.value),
            _thresholdEvidence(last.test, last.value),
          ],
          caveat: methods.length == 1
              ? null
              : 'Im Verlauf wurden unterschiedliche Methoden verwendet.',
        ),
      );
    }

    if (compatible.length >= 2) {
      final comparison = compare(
        compatible[compatible.length - 2],
        compatible.last,
      );
      final lactate = comparison.trends
          .where((trend) => trend.parameter == 'lactate_at_common_load')
          .firstOrNull;
      if (lactate != null) out.add(lactate);
    }
    return out;
  }

  IntelligenceTrend? _thresholdTrend(
    IntelligenceTest earlier,
    IntelligenceTest later,
    String type,
    List<String> caveats,
  ) {
    final a = earlier.threshold(type);
    final b = later.threshold(type);
    if (a?.load == null || b?.load == null) return null;
    final delta = b!.load! - a!.load!;
    final percent = _percent(delta, a.load!);
    final direction = _direction(percent, thresholdPercent: 1.0);
    return IntelligenceTrend(
      parameter: type,
      direction: direction,
      summary:
          '${type.toUpperCase()} ${_directionWords(direction)}: '
          '${_number(a.load!)} auf ${_number(b.load!)} ${b.loadUnit}.',
      confidence: a.methodId == b.methodId
          ? IntelligenceConfidence.high
          : IntelligenceConfidence.low,
      delta: delta,
      deltaPercent: percent,
      unit: b.loadUnit,
      evidence: [_thresholdEvidence(earlier, a), _thresholdEvidence(later, b)],
      caveat: a.methodId == b.methodId
          ? null
          : 'Methodenwechsel von ${a.methodId} zu ${b.methodId}.',
    );
  }

  IntelligenceTrend? _maximumTrend(
    IntelligenceTest earlier,
    IntelligenceTest later,
  ) {
    final a = earlier.maximumLoad;
    final b = later.maximumLoad;
    if (a == null || b == null) return null;
    final delta = b - a;
    final percent = _percent(delta, a);
    final direction = _direction(percent, thresholdPercent: 1.0);
    return IntelligenceTrend(
      parameter: 'maximum_load',
      direction: direction,
      summary:
          'Die höchste verwertbare Stufe hat sich '
          '${_directionWords(direction)}.',
      confidence: IntelligenceConfidence.high,
      delta: delta,
      deltaPercent: percent,
      unit: later.loadUnit,
      evidence: [
        IntelligenceEvidence(
          label: 'Maximum früher',
          value: a,
          unit: earlier.loadUnit,
          source: IntelligenceSource.measurement,
          sourceId: earlier.id,
          observedAtUtcUs: earlier.startedAtUtcUs,
        ),
        IntelligenceEvidence(
          label: 'Maximum aktuell',
          value: b,
          unit: later.loadUnit,
          source: IntelligenceSource.measurement,
          sourceId: later.id,
          observedAtUtcUs: later.startedAtUtcUs,
        ),
      ],
    );
  }

  IntelligenceTrend? _reserveTrend(
    IntelligenceTest earlier,
    IntelligenceTest later,
  ) {
    final maxA = earlier.maximumLoad;
    final maxB = later.maximumLoad;
    final lt2A = earlier.threshold('lt2')?.load;
    final lt2B = later.threshold('lt2')?.load;
    if (maxA == null || maxB == null || lt2A == null || lt2B == null) {
      return null;
    }
    final a = maxA - lt2A;
    final b = maxB - lt2B;
    final delta = b - a;
    return IntelligenceTrend(
      parameter: 'anaerobic_reserve',
      direction: _direction(_percent(delta, a), thresholdPercent: 2),
      summary:
          'Der Abstand zwischen LTP2 und höchster Stufe beträgt aktuell '
          '${_number(b)} ${later.loadUnit}.',
      confidence: IntelligenceConfidence.moderate,
      delta: delta,
      deltaPercent: _percent(delta, a),
      unit: later.loadUnit,
      evidence: [
        IntelligenceEvidence(
          label: 'Reserve früher',
          value: a,
          unit: earlier.loadUnit,
          source: IntelligenceSource.deterministicAnalysis,
          sourceId: earlier.id,
        ),
        IntelligenceEvidence(
          label: 'Reserve aktuell',
          value: b,
          unit: later.loadUnit,
          source: IntelligenceSource.deterministicAnalysis,
          sourceId: later.id,
        ),
      ],
      caveat:
          'Die Reserve beschreibt den gemessenen Abstand im Stufentest, nicht '
          'eine direkte Messung anaerober Kapazität.',
    );
  }

  IntelligenceTrend? _comparableLactateTrend(
    IntelligenceTest earlier,
    IntelligenceTest later,
  ) {
    final pairs = <({IntelligenceCurvePoint a, IntelligenceCurvePoint b})>[];
    for (final a in earlier.curve.where((point) => !point.excluded)) {
      for (final b in later.curve.where((point) => !point.excluded)) {
        if ((a.load - b.load).abs() <= 1e-6) pairs.add((a: a, b: b));
      }
    }
    if (pairs.isEmpty) return null;
    // Prefer the highest common sub-threshold load. It is usually the most
    // sensitive shared point while remaining a measured value, not an
    // interpolated invention.
    final upperA = earlier.threshold('lt2')?.load ?? double.infinity;
    final upperB = later.threshold('lt2')?.load ?? double.infinity;
    final eligible = pairs
        .where((pair) => pair.a.load <= math.min(upperA, upperB))
        .toList();
    final pool = eligible.isEmpty ? pairs : eligible;
    pool.sort((x, y) => y.a.load.compareTo(x.a.load));
    final pair = pool.first;
    final delta = pair.b.lactateMmolPerLitre - pair.a.lactateMmolPerLitre;
    final direction = delta < -0.2
        ? TrendDirection.improving
        : delta > 0.2
        ? TrendDirection.declining
        : TrendDirection.stable;
    return IntelligenceTrend(
      parameter: 'lactate_at_common_load',
      direction: direction,
      summary:
          'Bei derselben gemessenen Belastung von ${_number(pair.a.load)} '
          '${later.loadUnit} lag Laktat ${delta.abs() <= .2
              ? 'ähnlich'
              : delta < 0
              ? 'niedriger'
              : 'höher'}.',
      confidence: IntelligenceConfidence.moderate,
      delta: delta,
      unit: 'mmol/l',
      evidence: [
        IntelligenceEvidence(
          label: 'Laktat früher',
          value: pair.a.lactateMmolPerLitre,
          unit: 'mmol/l',
          source: IntelligenceSource.measurement,
          sourceId: earlier.id,
          observedAtUtcUs: earlier.startedAtUtcUs,
        ),
        IntelligenceEvidence(
          label: 'Laktat aktuell',
          value: pair.b.lactateMmolPerLitre,
          unit: 'mmol/l',
          source: IntelligenceSource.measurement,
          sourceId: later.id,
          observedAtUtcUs: later.startedAtUtcUs,
        ),
      ],
      caveat:
          'Ein Tagesunterschied kann auch durch Vorbelastung, Ernährung, '
          'Entnahmezeitpunkt, Temperatur oder Messstreuung entstehen.',
    );
  }

  IntelligenceEvidence _thresholdEvidence(
    IntelligenceTest test,
    IntelligenceThreshold threshold,
  ) => IntelligenceEvidence(
    label: threshold.type.toUpperCase(),
    value: threshold.load!,
    unit: threshold.loadUnit,
    source: IntelligenceSource.lalaEngine,
    sourceId: test.id,
    observedAtUtcUs: test.startedAtUtcUs,
    caveat: '${threshold.methodId} · ${threshold.engineVersion}',
  );
}

/// The LT2 that may classify [session]: with a per-sport map only the
/// session's own sport, never another one.
IntelligenceThreshold? lt2ForSession(
  IntelligenceSession session,
  IntelligenceThreshold? lt2,
  Map<String, IntelligenceThreshold>? lt2BySport,
) => lt2BySport == null ? lt2 : lt2BySport[sessionSportKey(session.sport)];

class TrainingLoadAnalyzer {
  const TrainingLoadAnalyzer();

  TrainingLoadContext analyze({
    required List<IntelligenceSession> sessions,
    required int nowUtcUs,
    IntelligenceThreshold? lt2,
    Map<String, IntelligenceThreshold>? lt2BySport,
  }) {
    const dayUs = Duration.microsecondsPerDay;
    final recentStart = nowUtcUs - 7 * dayUs;
    final referenceStart = nowUtcUs - 28 * dayUs;
    final recent = sessions
        .where((session) => session.startedAtUtcUs >= recentStart)
        .toList();
    final previous = sessions
        .where(
          (session) =>
              session.startedAtUtcUs >= referenceStart &&
              session.startedAtUtcUs < recentStart,
        )
        .toList();

    var classified = 0;
    var high = 0;
    for (final session in recent) {
      final threshold = lt2ForSession(session, lt2, lt2BySport);
      if (threshold?.load == null) continue;
      for (final interval in session.intervals) {
        final load = threshold!.loadUnit.toLowerCase() == 'w'
            ? interval.averagePowerWatt
            : threshold.loadUnit.toLowerCase() == 'km/h'
            ? interval.averageSpeedKmh
            : null;
        if (load == null || interval.kind != 'work') continue;
        classified += interval.durationSeconds;
        if (load >= threshold.load!) high += interval.durationSeconds;
      }
    }

    final missing = <String>[];
    if (sessions.isEmpty) missing.add('keine aufgezeichneten Einheiten');
    if (previous.isEmpty) {
      missing.add('keine dreiwöchige Referenz für die Belastungsentwicklung');
    }
    final hasThreshold = lt2BySport == null
        ? lt2?.load != null
        : lt2BySport.values.any((value) => value.load != null);
    if (!hasThreshold) {
      missing.add('keine aktuelle LTP2 für die Intensitätszuordnung');
    } else if (classified == 0) {
      missing.add('keine klassifizierbaren Workout-Intervalle');
    }

    return TrainingLoadContext(
      sessions7Days: recent.length,
      duration7Days: recent.fold(0, (sum, item) => sum + item.durationSeconds),
      work7DaysJoule: recent.fold(
        0.0,
        (sum, item) => sum + (item.workJoule ?? 0),
      ),
      sessionsPrevious21Days: previous.length,
      durationPrevious21Days: previous.fold(
        0,
        (sum, item) => sum + item.durationSeconds,
      ),
      highIntensitySeconds7Days: high,
      intensityClassifiedSeconds7Days: classified,
      missing: missing,
    );
  }
}

class ReadinessAnalyzer {
  const ReadinessAnalyzer();

  ReadinessContext analyze({
    required List<IntelligenceSession> sessions,
    required List<IntelligenceObservation> observations,
    required TrainingLoadContext load,
    required int nowUtcUs,
    IntelligenceThreshold? lt2,
    Map<String, IntelligenceThreshold>? lt2BySport,
    AthleteState? athleteState,
  }) {
    final evidence = <IntelligenceEvidence>[];
    final missing = <String>[...load.missing];
    final reasons = <String>[];
    final latest = sessions.firstOrNull;
    if (latest == null) {
      return ReadinessContext(
        recommendation: ReadinessRecommendation.insufficient,
        headline: 'Noch keine belastbare Trainingsempfehlung',
        reasons: const [
          'Ohne aufgezeichnete Einheit kennt GIULIA weder die jüngste '
              'Belastung noch die Erholung davon.',
        ],
        evidence: const [],
        missing: const [
          'Trainingshistorie',
          'subjektive Erholung',
          'aktuelles Belastungsempfinden',
        ],
        confidence: IntelligenceConfidence.insufficient,
      );
    }

    final hoursSince =
        (nowUtcUs - latest.startedAtUtcUs) / Duration.microsecondsPerHour;
    evidence.add(
      IntelligenceEvidence(
        label: 'Abstand zur letzten Einheit',
        value: hoursSince.clamp(0, double.infinity),
        unit: 'h',
        source: IntelligenceSource.measurement,
        sourceId: latest.id,
        observedAtUtcUs: latest.startedAtUtcUs,
      ),
    );
    if (athleteState?.window(7) case final stateWindow?) {
      evidence.add(
        IntelligenceEvidence(
          label: 'Aktivitäten im Athlete State (7 Tage)',
          value: stateWindow.activityCount,
          source: IntelligenceSource.deterministicAnalysis,
          sourceId: athleteState!.inputFingerprint,
          observedAtUtcUs: athleteState.asOfUtcUs,
          caveat: athleteState.featureEngineVersion,
        ),
      );
    }

    final recentRpe = observations
        .where(
          (item) =>
              item.usable &&
              item.type == IntelligenceObservationType.rpe &&
              item.value != null,
        )
        .lastOrNull;
    if (recentRpe != null) {
      evidence.add(
        IntelligenceEvidence(
          label: 'Letztes subjektives RPE',
          value: recentRpe.value!,
          source: IntelligenceSource.subjective,
          observedAtUtcUs: recentRpe.observedAtUtcUs,
        ),
      );
    } else {
      missing.add('aktuelles subjektives Belastungsempfinden');
    }
    missing.add('subjektive Erholung bzw. Schlaf');

    final latestLt2 = lt2ForSession(latest, lt2, lt2BySport);
    final latestHard = _isHard(latest, latestLt2);
    if (latestHard) {
      evidence.add(
        IntelligenceEvidence(
          label: 'Letzte Einheit als intensiv eingeordnet',
          value: 1,
          source: IntelligenceSource.deterministicAnalysis,
          sourceId: latest.id,
          caveat: _hardReason(latest, latestLt2),
        ),
      );
    }
    if (load.durationChangePercent case final change?) {
      evidence.add(
        IntelligenceEvidence(
          label: 'Trainingsdauer gegenüber Vorwochen',
          value: change,
          unit: '%',
          source: IntelligenceSource.deterministicAnalysis,
        ),
      );
    }

    if ((recentRpe?.value ?? 0) >= 9 ||
        latest.fatiguePercent != null && latest.fatiguePercent! <= -15) {
      reasons.add(
        (recentRpe?.value ?? 0) >= 9
            ? 'Das jüngste subjektive Belastungsempfinden war sehr hoch.'
            : 'Die Leistung fiel innerhalb der letzten Einheit deutlich ab.',
      );
      return _decision(
        ReadinessRecommendation.recovery,
        'Heute Erholung oder sehr locker',
        reasons,
        evidence,
        missing,
      );
    }

    if (latestHard && hoursSince < 36) {
      reasons.add(
        'Die letzte intensive Einheit liegt erst '
        '${hoursSince.round()} Stunden zurück.',
      );
      return _decision(
        ReadinessRecommendation.easy,
        'Heute locker, keine harten Intervalle',
        reasons,
        evidence,
        missing,
      );
    }

    if ((load.durationChangePercent ?? 0) > 40) {
      reasons.add(
        'Die aufgezeichnete Trainingsdauer der letzten sieben Tage liegt '
        'deutlich über dem Mittel der drei Vorwochen.',
      );
      return _decision(
        ReadinessRecommendation.easy,
        'Belastung heute begrenzen',
        reasons,
        evidence,
        missing,
      );
    }

    if (latest.symmetryPercent != null && latest.symmetryPercent! < 90) {
      reasons.add(
        'Die letzte Ercolina-Einheit zeigte eine ausgeprägte '
        'Links-rechts-Abweichung.',
      );
      return _decision(
        ReadinessRecommendation.technique,
        'Technik vor Intensität',
        reasons,
        evidence,
        missing,
      );
    }

    if (latestLt2?.load == null) {
      reasons.add(
        'Ohne aktuelle Schwelle kann GIULIA eine harte Einheit nicht '
        'individuell dosieren.',
      );
      return _decision(
        ReadinessRecommendation.technique,
        'Technik oder lockere Ausdauer',
        reasons,
        evidence,
        missing,
      );
    }

    if (hoursSince >= 48 && !latestHard && (recentRpe?.value ?? 0) <= 7) {
      reasons.add(
        'Seit mindestens 48 Stunden ist keine intensive Einheit belegt.',
      );
      return _decision(
        ReadinessRecommendation.quality,
        'Eine Qualitätseinheit ist vertretbar',
        reasons,
        evidence,
        missing,
      );
    }

    reasons.add(
      'Die vorhandenen Daten zeigen keinen klaren Grund für hohe Intensität '
      'und keinen klaren Warnhinweis.',
    );
    return _decision(
      ReadinessRecommendation.endurance,
      'Grundlagenausdauer ist die robuste Wahl',
      reasons,
      evidence,
      missing,
    );
  }

  ReadinessContext _decision(
    ReadinessRecommendation recommendation,
    String headline,
    List<String> reasons,
    List<IntelligenceEvidence> evidence,
    List<String> missing,
  ) => ReadinessContext(
    recommendation: recommendation,
    headline: headline,
    reasons: List.unmodifiable(reasons),
    evidence: List.unmodifiable(evidence),
    missing: List.unmodifiable(missing.toSet()),
    confidence: missing.length <= 1
        ? IntelligenceConfidence.high
        : missing.length <= 3
        ? IntelligenceConfidence.moderate
        : IntelligenceConfidence.low,
  );

  bool _isHard(IntelligenceSession session, IntelligenceThreshold? lt2) {
    if ((session.rpe ?? 0) >= 8) return true;
    if (lt2?.load != null &&
        (lt2!.loadUnit.toLowerCase() == 'w' ||
            lt2.loadUnit.toLowerCase() == 'km/h')) {
      return session.intervals.any((interval) {
        final load = lt2.loadUnit.toLowerCase() == 'w'
            ? interval.averagePowerWatt
            : interval.averageSpeedKmh;
        return interval.kind == 'work' && load != null && load >= lt2.load!;
      });
    }
    return false;
  }

  String _hardReason(IntelligenceSession session, IntelligenceThreshold? lt2) =>
      (session.rpe ?? 0) >= 8
      ? 'RPE ${session.rpe!.toStringAsFixed(0)}'
      : 'mindestens ein Intervall an oder über LTP2';
}

class ErcolinaIntelligence {
  const ErcolinaIntelligence();

  ErcolinaContext analyze(List<IntelligenceSession> newestFirst) {
    final session = newestFirst
        .where((item) => item.hasErcolinaMetrics)
        .firstOrNull;
    if (session == null) {
      return const ErcolinaContext(
        session: null,
        findings: [],
        missing: ['keine Sitzung mit Zugdaten'],
      );
    }

    final findings = <ErcolinaFinding>[];
    if (session.leftPowerWatt != null && session.rightPowerWatt != null) {
      final delta = session.leftPowerWatt! - session.rightPowerWatt!;
      final side = delta >= 0 ? 'links' : 'rechts';
      findings.add(
        ErcolinaFinding(
          parameter: 'symmetry',
          summary:
              delta.abs() <
                  .05 * (session.leftPowerWatt! + session.rightPowerWatt!)
              ? 'Die Leistung wurde annähernd symmetrisch erzeugt.'
              : 'Die $side Seite trug mehr Leistung bei; der Unterschied '
                    'sollte über weitere Einheiten beobachtet werden.',
          confidence: IntelligenceConfidence.high,
          evidence: [
            IntelligenceEvidence(
              label: 'Leistung links',
              value: session.leftPowerWatt!,
              unit: 'W',
              source: IntelligenceSource.deterministicAnalysis,
              sourceId: session.id,
            ),
            IntelligenceEvidence(
              label: 'Leistung rechts',
              value: session.rightPowerWatt!,
              unit: 'W',
              source: IntelligenceSource.deterministicAnalysis,
              sourceId: session.id,
            ),
          ],
        ),
      );
    }
    if (session.fatiguePercent != null) {
      findings.add(
        ErcolinaFinding(
          parameter: 'fatigue',
          summary: session.fatiguePercent! < -8
              ? 'Die Zugleistung fiel in der zweiten Hälfte sichtbar ab.'
              : 'Die Zugleistung blieb über die Einheit stabil.',
          confidence: IntelligenceConfidence.high,
          evidence: [
            IntelligenceEvidence(
              label: 'Leistungsänderung innerhalb der Einheit',
              value: session.fatiguePercent!,
              unit: '%',
              source: IntelligenceSource.deterministicAnalysis,
              sourceId: session.id,
            ),
          ],
        ),
      );
    }
    if (session.workPerStrokeJoule != null &&
        session.strokeRatePerMinute != null) {
      findings.add(
        ErcolinaFinding(
          parameter: 'power_production',
          summary:
              '${_number(session.averagePowerWatt!)} W entstanden aus '
              '${_number(session.workPerStrokeJoule!)} J je Zug bei '
              '${_number(session.strokeRatePerMinute!)} Zügen/min.',
          confidence: IntelligenceConfidence.high,
          evidence: [
            IntelligenceEvidence(
              label: 'Arbeit je Zug',
              value: session.workPerStrokeJoule!,
              unit: 'J',
              source: IntelligenceSource.deterministicAnalysis,
              sourceId: session.id,
            ),
            IntelligenceEvidence(
              label: 'Zugfrequenz',
              value: session.strokeRatePerMinute!,
              unit: '/min',
              source: IntelligenceSource.deterministicAnalysis,
              sourceId: session.id,
            ),
          ],
        ),
      );
    }

    final workIntervals = session.intervals
        .where((item) => item.kind == 'work' && item.averagePowerWatt != null)
        .toList();
    if (workIntervals.length >= 2) {
      final first = workIntervals.first;
      final last = workIntervals.last;
      final powerChange = last.averagePowerWatt! - first.averagePowerWatt!;
      final symmetryChange =
          first.symmetryPercent == null || last.symmetryPercent == null
          ? null
          : last.symmetryPercent! - first.symmetryPercent!;
      findings.add(
        ErcolinaFinding(
          parameter: 'interval_stability',
          summary: powerChange < -0.08 * first.averagePowerWatt!
              ? 'Die Belastungsintervalle verloren bis zum letzten Abschnitt '
                    'deutlich Leistung.'
              : symmetryChange != null && symmetryChange < -3
              ? 'Die Leistung blieb eher erhalten, die Symmetrie wurde aber '
                    'mit der Ermüdung instabiler.'
              : 'Leistung und Technik blieben über die Intervalle stabil.',
          confidence: IntelligenceConfidence.moderate,
          evidence: [
            IntelligenceEvidence(
              label: 'Leistungsänderung erstes bis letztes Intervall',
              value: powerChange,
              unit: 'W',
              source: IntelligenceSource.deterministicAnalysis,
              sourceId: session.id,
            ),
            if (symmetryChange != null)
              IntelligenceEvidence(
                label: 'Symmetrieänderung erstes bis letztes Intervall',
                value: symmetryChange,
                unit: 'Prozentpunkte',
                source: IntelligenceSource.deterministicAnalysis,
                sourceId: session.id,
              ),
          ],
        ),
      );
    }

    final missing = <String>[];
    if (session.intervals.isEmpty) {
      missing.add('keine Intervallgrenzen für eine Abschnittsanalyse');
    }
    missing.add('keine gespeicherte Zuglänge oder Zugzeit je Einzelzug');
    missing.add('keine normalisierte Force-/Power-Kurve im Sitzungsarchiv');
    return ErcolinaContext(
      session: session,
      findings: findings,
      missing: missing,
    );
  }
}

TrendDirection _direction(double? value, {required double thresholdPercent}) {
  if (value == null) return TrendDirection.unavailable;
  if (value > thresholdPercent) return TrendDirection.improving;
  if (value < -thresholdPercent) return TrendDirection.declining;
  return TrendDirection.stable;
}

String _directionWords(TrendDirection direction) => switch (direction) {
  TrendDirection.improving => 'verbessert',
  TrendDirection.declining => 'verschlechtert',
  TrendDirection.stable => 'kaum verändert',
  TrendDirection.mixed => 'uneinheitlich entwickelt',
  TrendDirection.unavailable => 'nicht zuverlässig bestimmen lassen',
};

double? _percent(double delta, double reference) =>
    reference == 0 ? null : delta / reference * 100;

String _number(double value) {
  final rounded = value.roundToDouble();
  return (value - rounded).abs() < .05
      ? rounded.toInt().toString()
      : value.toStringAsFixed(1).replaceAll('.', ',');
}
