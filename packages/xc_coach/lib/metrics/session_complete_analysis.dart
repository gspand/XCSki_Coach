/// Vollstaendige, reproduzierbare Auswertung einer Ercolina-Einheit.
///
/// Die Auswertung arbeitet ausschliesslich auf archivierten Zuegen und der
/// lueckenbewussten HF-Auswertung. Sie erzeugt weder Kraft noch Weg und legt
/// keine Linie ueber Aufzeichnungsluecken. Zeitfensterleistung wird aus der
/// gespeicherten Arbeit der ueberlappenden Zuege rekonstruiert; zwischen den
/// Zuegen ist die mechanische Leistung null.
library;

import 'dart:math' as math;

import '../core/models.dart';
import '../core/stroke_metrics.dart';
import 'heart_rate_analytics.dart';
import 'stroke_curves.dart';

class StrokeClockAnchor {
  const StrokeClockAnchor({required this.monotonicUs, required this.utcUs});

  final int monotonicUs;
  final int utcUs;
}

class StrokeTimelinePoint {
  const StrokeTimelinePoint({
    required this.index,
    required this.elapsedSeconds,
    required this.activeSeconds,
    required this.recoverySeconds,
    required this.workJoule,
    required this.activePowerWatt,
    required this.peakPowerWatt,
    required this.leftShare,
    required this.quality,
    this.cadencePerMinute,
  });

  final int index;
  final double elapsedSeconds;
  final double activeSeconds;
  final double recoverySeconds;
  final double workJoule;
  final double activePowerWatt;
  final double peakPowerWatt;
  final double? cadencePerMinute;
  final double? leftShare;
  final SignalQuality quality;
}

class HeartRateWindow {
  const HeartRateWindow({
    required this.averageBpm,
    required this.coverage,
    required this.measuredDuration,
  });

  final double averageBpm;
  final double coverage;
  final Duration measuredDuration;
}

class StrokeWindowSummary {
  const StrokeWindowSummary({
    required this.strokeCount,
    required this.activePowerWatt,
    required this.medianStrokePowerWatt,
    required this.workPerStrokeJoule,
    required this.peakPowerWatt,
    this.cadencePerMinute,
    this.leftShare,
    this.leftPeakPhase,
    this.rightPeakPhase,
  });

  final int strokeCount;

  /// Arbeit geteilt durch die Summe der aktiven Zugzeiten.
  final double activePowerWatt;

  /// Median der einzeln gespeicherten mittleren Zugleistungen.
  final double medianStrokePowerWatt;
  final double workPerStrokeJoule;
  final double peakPowerWatt;
  final double? cadencePerMinute;
  final double? leftShare;
  final double? leftPeakPhase;
  final double? rightPeakPhase;
}

class SessionFatigueComparison {
  const SessionFatigueComparison({
    required this.windowStrokes,
    required this.first,
    required this.last,
    required this.powerDeltaPercent,
    required this.workDeltaPercent,
    required this.peakDeltaPercent,
    this.cadenceDeltaPercent,
    this.leftShareDeltaPercentagePoints,
    this.leftPeakPhaseDeltaPercentagePoints,
    this.rightPeakPhaseDeltaPercentagePoints,
    this.leftShapeDriftPercent,
    this.rightShapeDriftPercent,
    this.firstHeartRate,
    this.lastHeartRate,
  });

  final int windowStrokes;
  final StrokeWindowSummary first;
  final StrokeWindowSummary last;
  final double powerDeltaPercent;
  final double workDeltaPercent;
  final double peakDeltaPercent;
  final double? cadenceDeltaPercent;
  final double? leftShareDeltaPercentagePoints;
  final double? leftPeakPhaseDeltaPercentagePoints;
  final double? rightPeakPhaseDeltaPercentagePoints;
  final double? leftShapeDriftPercent;
  final double? rightShapeDriftPercent;
  final HeartRateWindow? firstHeartRate;
  final HeartRateWindow? lastHeartRate;

  double? get heartRateDeltaBpm =>
      firstHeartRate == null || lastHeartRate == null
      ? null
      : lastHeartRate!.averageBpm - firstHeartRate!.averageBpm;

  double? get firstPowerPerHeartRate => firstHeartRate == null
      ? null
      : first.activePowerWatt / firstHeartRate!.averageBpm;

  double? get lastPowerPerHeartRate => lastHeartRate == null
      ? null
      : last.activePowerWatt / lastHeartRate!.averageBpm;
}

class PowerDurationBest {
  const PowerDurationBest({
    required this.duration,
    required this.averagePowerWatt,
    required this.startedAtSeconds,
    required this.workJoule,
    required this.strokeCount,
    this.cadencePerMinute,
    this.workPerStrokeJoule,
    this.leftShare,
  });

  final Duration duration;
  final double averagePowerWatt;
  final double startedAtSeconds;
  final double workJoule;
  final int strokeCount;
  final double? cadencePerMinute;
  final double? workPerStrokeJoule;
  final double? leftShare;
}

class StrokeCountBest {
  const StrokeCountBest({
    required this.strokeCount,
    required this.firstStrokeIndex,
    required this.activePowerWatt,
    required this.workPerStrokeJoule,
    required this.peakPowerWatt,
    this.cadencePerMinute,
    this.leftShare,
    this.shapeVariationPercent,
  });

  final int strokeCount;
  final int firstStrokeIndex;
  final double activePowerWatt;
  final double workPerStrokeJoule;
  final double peakPowerWatt;
  final double? cadencePerMinute;
  final double? leftShare;

  /// Mittlere normierte Formabweichung vom Gruppenmittel. Niedriger ist
  /// konstanter; null bedeutet, dass keine gespeicherten Kurven vorliegen.
  final double? shapeVariationPercent;
}

class CompleteSessionAnalysis {
  const CompleteSessionAnalysis({
    required this.timeline,
    required this.powerDuration,
    required this.strokeCountBests,
    this.fatigue,
    this.shapeVariationPercent,
    this.leftRightShapeDifferencePercent,
    this.usesSessionClock = false,
  });

  final List<StrokeTimelinePoint> timeline;
  final SessionFatigueComparison? fatigue;
  final List<PowerDurationBest> powerDuration;
  final List<StrokeCountBest> strokeCountBests;
  final double? shapeVariationPercent;
  final double? leftRightShapeDifferencePercent;

  /// True, wenn die monotone Messuhr ueber einen bei der ersten Zugmeldung
  /// gespeicherten Anker auf die UTC-Sessionzeit gelegt werden konnte.
  final bool usesSessionClock;
}

const completePowerDurationWindows = <Duration>[
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 30),
  Duration(minutes: 1),
  Duration(minutes: 3),
  Duration(minutes: 5),
  Duration(minutes: 10),
  Duration(minutes: 20),
];

const completeStrokeCountWindows = <int>[1, 5, 10, 30, 100];

CompleteSessionAnalysis analyzeCompleteSession(
  List<Stroke> input, {
  HeartRateAnalysis? heartRate,
  StrokeClockAnchor? clockAnchor,
}) {
  final strokes = <Stroke>[
    for (final stroke in input)
      if (_validStroke(stroke)) stroke,
  ]..sort((a, b) => a.startUs.compareTo(b.startUs));
  if (strokes.isEmpty) {
    return const CompleteSessionAnalysis(
      timeline: <StrokeTimelinePoint>[],
      powerDuration: <PowerDurationBest>[],
      strokeCountBests: <StrokeCountBest>[],
    );
  }

  final startDiffs = <int>[
    for (var i = 1; i < strokes.length; i++)
      if (strokes[i].startUs > strokes[i - 1].startUs)
        strokes[i].startUs - strokes[i - 1].startUs,
  ]..sort();
  final typicalCycleUs = startDiffs.isEmpty
      ? 0
      : startDiffs[startDiffs.length ~/ 2];
  final maximumContinuousCycleUs = math.max(
    10 * Duration.microsecondsPerSecond,
    typicalCycleUs * 5,
  );
  final firstUs = strokes.first.startUs;
  final sessionClockOffsetUs = heartRate == null || clockAnchor == null
      ? null
      : clockAnchor.utcUs -
            clockAnchor.monotonicUs -
            heartRate.sessionStartUtcUs;
  final workIntegral = _StrokeWorkIntegral(strokes);
  final timeline = <StrokeTimelinePoint>[];
  for (final (index, stroke) in strokes.indexed) {
    double? cadence;
    if (index > 0) {
      final cycleUs = stroke.startUs - strokes[index - 1].startUs;
      if (cycleUs > 0 && cycleUs <= maximumContinuousCycleUs) {
        cadence = 60 * Duration.microsecondsPerSecond / cycleUs;
      }
    }
    final leftShare =
        stroke.workJoule > 0 &&
            stroke.leftWorkJoule >= 0 &&
            stroke.rightWorkJoule >= 0
        ? (stroke.leftWorkJoule / stroke.workJoule).clamp(0.0, 1.0)
        : null;
    timeline.add(
      StrokeTimelinePoint(
        index: index + 1,
        elapsedSeconds:
            (stroke.startUs + (sessionClockOffsetUs ?? -firstUs)) /
            Duration.microsecondsPerSecond,
        activeSeconds: stroke.durationSeconds,
        recoverySeconds: stroke.recoverySeconds,
        workJoule: stroke.workJoule,
        activePowerWatt: stroke.workJoule / stroke.durationSeconds,
        peakPowerWatt: stroke.peakPowerWatt,
        cadencePerMinute: cadence,
        leftShare: leftShare,
        quality: stroke.quality,
      ),
    );
  }

  return CompleteSessionAnalysis(
    timeline: List.unmodifiable(timeline),
    fatigue: _fatigue(
      strokes,
      timeline,
      sessionClockOffsetUs == null ? null : heartRate,
    ),
    powerDuration: List.unmodifiable(<PowerDurationBest>[
      for (final duration in completePowerDurationWindows)
        ?_bestPowerDuration(strokes, workIntegral, duration),
    ]),
    strokeCountBests: List.unmodifiable(<StrokeCountBest>[
      for (final count in completeStrokeCountWindows)
        ?_bestStrokeCount(strokes, timeline, count),
    ]),
    shapeVariationPercent: _shapeVariation(strokes),
    leftRightShapeDifferencePercent: _leftRightShapeDifference(strokes),
    usesSessionClock: sessionClockOffsetUs != null,
  );
}

SessionFatigueComparison? _fatigue(
  List<Stroke> strokes,
  List<StrokeTimelinePoint> timeline,
  HeartRateAnalysis? heartRate,
) {
  // Fuenf Zuege je Fenster sind die kleinste noch robuste Aussage.
  if (strokes.length < 25) return null;
  final count = math.max(5, (strokes.length * .2).floor());
  final firstStrokes = strokes.take(count).toList(growable: false);
  final lastStrokes = strokes
      .skip(strokes.length - count)
      .toList(growable: false);
  final firstTimeline = timeline.take(count).toList(growable: false);
  final lastTimeline = timeline
      .skip(timeline.length - count)
      .toList(growable: false);
  final first = _summary(firstStrokes, firstTimeline);
  final last = _summary(lastStrokes, lastTimeline);
  if (first == null || last == null) return null;

  HeartRateWindow? firstHr;
  HeartRateWindow? lastHr;
  if (heartRate != null) {
    final firstFrom = math.max(0, firstTimeline.first.elapsedSeconds);
    final firstTo = math.max(
      firstFrom,
      firstTimeline.last.elapsedSeconds + firstTimeline.last.activeSeconds,
    );
    final lastFrom = math.max(0, lastTimeline.first.elapsedSeconds);
    final lastTo = math.min(
      heartRate.wallDuration.inMicroseconds / Duration.microsecondsPerSecond,
      lastTimeline.last.elapsedSeconds + lastTimeline.last.activeSeconds,
    );
    firstHr = heartRateWindow(
      heartRate,
      from: Duration(microseconds: (firstFrom * 1000000).round()),
      to: Duration(microseconds: (firstTo * 1000000).round()),
    );
    lastHr = heartRateWindow(
      heartRate,
      from: Duration(microseconds: (lastFrom * 1000000).round()),
      to: Duration(microseconds: (lastTo * 1000000).round()),
    );
  }

  return SessionFatigueComparison(
    windowStrokes: count,
    first: first,
    last: last,
    powerDeltaPercent: _percentDelta(
      first.activePowerWatt,
      last.activePowerWatt,
    ),
    workDeltaPercent: _percentDelta(
      first.workPerStrokeJoule,
      last.workPerStrokeJoule,
    ),
    peakDeltaPercent: _percentDelta(first.peakPowerWatt, last.peakPowerWatt),
    cadenceDeltaPercent:
        first.cadencePerMinute == null || last.cadencePerMinute == null
        ? null
        : _percentDelta(first.cadencePerMinute!, last.cadencePerMinute!),
    leftShareDeltaPercentagePoints:
        first.leftShare == null || last.leftShare == null
        ? null
        : (last.leftShare! - first.leftShare!) * 100,
    leftPeakPhaseDeltaPercentagePoints:
        first.leftPeakPhase == null || last.leftPeakPhase == null
        ? null
        : (last.leftPeakPhase! - first.leftPeakPhase!) * 100,
    rightPeakPhaseDeltaPercentagePoints:
        first.rightPeakPhase == null || last.rightPeakPhase == null
        ? null
        : (last.rightPeakPhase! - first.rightPeakPhase!) * 100,
    leftShapeDriftPercent: _shapeDrift(
      firstStrokes,
      lastStrokes,
      StrokeSide.left,
    ),
    rightShapeDriftPercent: _shapeDrift(
      firstStrokes,
      lastStrokes,
      StrokeSide.right,
    ),
    firstHeartRate: firstHr,
    lastHeartRate: lastHr,
  );
}

StrokeWindowSummary? _summary(
  List<Stroke> strokes,
  List<StrokeTimelinePoint> timeline,
) {
  if (strokes.isEmpty) return null;
  final activeSeconds = strokes.fold<double>(
    0,
    (sum, stroke) => sum + stroke.durationSeconds,
  );
  final work = strokes.fold<double>(0, (sum, stroke) => sum + stroke.workJoule);
  if (activeSeconds <= 0 || work <= 0) return null;
  final powers = <double>[for (final stroke in strokes) stroke.meanPowerWatt]
    ..sort();
  final cadences = <double>[
    for (final point in timeline) ?point.cadencePerMinute,
  ];
  final left = strokes.fold<double>(
    0,
    (sum, stroke) => sum + stroke.leftWorkJoule,
  );
  final sideWorkValid = strokes.every(
    (stroke) => stroke.leftWorkJoule >= 0 && stroke.rightWorkJoule >= 0,
  );
  return StrokeWindowSummary(
    strokeCount: strokes.length,
    activePowerWatt: work / activeSeconds,
    medianStrokePowerWatt: _median(powers),
    workPerStrokeJoule: work / strokes.length,
    peakPowerWatt:
        strokes.fold<double>(0, (sum, stroke) => sum + stroke.peakPowerWatt) /
        strokes.length,
    cadencePerMinute: cadences.isEmpty
        ? null
        : cadences.reduce((a, b) => a + b) / cadences.length,
    leftShare: sideWorkValid ? (left / work).clamp(0.0, 1.0) : null,
    leftPeakPhase: _meanNullable(<double?>[
      for (final stroke in strokes)
        stroke.sides?.left.peakPowerPhase ?? stroke.leftPeakPosition,
    ]),
    rightPeakPhase: _meanNullable(<double?>[
      for (final stroke in strokes)
        stroke.sides?.right.peakPowerPhase ?? stroke.rightPeakPosition,
    ]),
  );
}

PowerDurationBest? _bestPowerDuration(
  List<Stroke> strokes,
  _StrokeWorkIntegral workIntegral,
  Duration duration,
) {
  final windowUs = duration.inMicroseconds;
  final firstUs = strokes.first.startUs;
  final lastUs = strokes.last.endUs;
  if (windowUs <= 0 || lastUs - firstUs < windowUs) return null;

  final candidates = <int>{firstUs, lastUs - windowUs};
  for (final stroke in strokes) {
    if (stroke.startUs >= firstUs && stroke.startUs + windowUs <= lastUs) {
      candidates.add(stroke.startUs);
    }
    final fromEnd = stroke.endUs - windowUs;
    if (fromEnd >= firstUs && fromEnd + windowUs <= lastUs) {
      candidates.add(fromEnd);
    }
  }

  double bestWork = -1;
  int bestStart = firstUs;
  for (final start in candidates) {
    final end = start + windowUs;
    final work = workIntegral.at(end) - workIntegral.at(start);
    if (work > bestWork) {
      bestWork = work;
      bestStart = start;
    }
  }
  if (bestWork < 0) return null;
  final fullInside = <Stroke>[
    for (final stroke in strokes)
      if (stroke.startUs >= bestStart && stroke.endUs <= bestStart + windowUs)
        stroke,
  ];
  final count = fullInside.length;
  final left = fullInside.fold<double>(
    0,
    (sum, stroke) => sum + stroke.leftWorkJoule,
  );
  final total = fullInside.fold<double>(
    0,
    (sum, stroke) => sum + stroke.workJoule,
  );
  final sidesValid = fullInside.every(
    (stroke) => stroke.leftWorkJoule >= 0 && stroke.rightWorkJoule >= 0,
  );
  return PowerDurationBest(
    duration: duration,
    averagePowerWatt:
        bestWork / duration.inMicroseconds * Duration.microsecondsPerSecond,
    startedAtSeconds: (bestStart - firstUs) / Duration.microsecondsPerSecond,
    workJoule: bestWork,
    strokeCount: count,
    cadencePerMinute: count == 0
        ? null
        : count / duration.inMicroseconds * Duration.microsecondsPerSecond * 60,
    workPerStrokeJoule: count == 0 ? null : total / count,
    leftShare: !sidesValid || total <= 0 ? null : left / total,
  );
}

/// Integral der gespeicherten mechanischen Arbeit. Zwischen zwei Zuegen ist
/// es konstant; innerhalb eines Zuges wird die Zugenergie linear ueber dessen
/// aktive Dauer verteilt. Ein festes Zeitfenster kostet damit O(log n), nicht
/// einen erneuten Durchlauf ueber alle Zuege.
class _StrokeWorkIntegral {
  _StrokeWorkIntegral(this.strokes)
    : prefixWork = List<double>.filled(strokes.length + 1, 0) {
    for (var index = 0; index < strokes.length; index++) {
      prefixWork[index + 1] = prefixWork[index] + strokes[index].workJoule;
    }
  }

  final List<Stroke> strokes;
  final List<double> prefixWork;

  double at(int timeUs) {
    var low = 0;
    var high = strokes.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (strokes[middle].startUs < timeUs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == 0) return 0;
    final index = low - 1;
    final stroke = strokes[index];
    if (timeUs >= stroke.endUs) return prefixWork[index + 1];
    final durationUs = stroke.endUs - stroke.startUs;
    if (durationUs <= 0) return prefixWork[index];
    final share = ((timeUs - stroke.startUs) / durationUs).clamp(0.0, 1.0);
    return prefixWork[index] + stroke.workJoule * share;
  }
}

StrokeCountBest? _bestStrokeCount(
  List<Stroke> strokes,
  List<StrokeTimelinePoint> timeline,
  int count,
) {
  if (count <= 0 || strokes.length < count) return null;
  StrokeWindowSummary? bestSummary;
  var bestStart = 0;
  for (var start = 0; start + count <= strokes.length; start++) {
    final group = strokes.sublist(start, start + count);
    final points = timeline.sublist(start, start + count);
    final summary = _summary(group, points);
    if (summary == null) continue;
    if (bestSummary == null ||
        summary.activePowerWatt > bestSummary.activePowerWatt) {
      bestSummary = summary;
      bestStart = start;
    }
  }
  final summary = bestSummary;
  if (summary == null) return null;
  final bestGroup = strokes.sublist(bestStart, bestStart + count);
  return StrokeCountBest(
    strokeCount: count,
    firstStrokeIndex: bestStart + 1,
    activePowerWatt: summary.activePowerWatt,
    workPerStrokeJoule: summary.workPerStrokeJoule,
    peakPowerWatt: bestGroup.fold<double>(
      0,
      (peak, stroke) => math.max(peak, stroke.peakPowerWatt),
    ),
    cadencePerMinute: summary.cadencePerMinute,
    leftShare: summary.leftShare,
    shapeVariationPercent: _shapeVariation(bestGroup),
  );
}

/// Zeitgewichteter HF-Mittelwert eines Teilfensters. Ein Funkloch bleibt ein
/// Loch; es wird weder der letzte Wert gehalten noch linear interpoliert.
HeartRateWindow? heartRateWindow(
  HeartRateAnalysis analysis, {
  required Duration from,
  required Duration to,
  double minimumCoverage = .5,
}) {
  final fromUs = analysis.sessionStartUtcUs + from.inMicroseconds;
  final toUs = analysis.sessionStartUtcUs + to.inMicroseconds;
  if (toUs <= fromUs) return null;
  var measuredUs = 0;
  var weighted = 0.0;
  for (var i = 0; i + 1 < analysis.samples.length; i++) {
    final current = analysis.samples[i];
    final next = analysis.samples[i + 1];
    if (!analysis.isContinuous(current, next)) continue;
    final start = math.max(fromUs, current.recordedAtUs);
    final end = math.min(toUs, next.recordedAtUs);
    final covered = end - start;
    if (covered <= 0) continue;
    measuredUs += covered;
    weighted += current.bpm * covered;
  }
  if (measuredUs <= 0) return null;
  final coverage = measuredUs / (toUs - fromUs);
  if (coverage < minimumCoverage) return null;
  return HeartRateWindow(
    averageBpm: weighted / measuredUs,
    coverage: coverage.clamp(0.0, 1.0),
    measuredDuration: Duration(microseconds: measuredUs),
  );
}

bool _validStroke(Stroke stroke) =>
    stroke.endUs > stroke.startUs &&
    stroke.workJoule.isFinite &&
    stroke.workJoule >= 0 &&
    stroke.meanPowerWatt.isFinite &&
    stroke.peakPowerWatt.isFinite &&
    stroke.quality != SignalQuality.invalid;

double _percentDelta(double first, double last) =>
    first <= 0 ? 0 : (last - first) / first * 100;

double _median(List<double> values) {
  final middle = values.length ~/ 2;
  return values.length.isOdd
      ? values[middle]
      : (values[middle - 1] + values[middle]) / 2;
}

double? _meanNullable(Iterable<double?> values) {
  var sum = 0.0;
  var count = 0;
  for (final value in values) {
    if (value == null || !value.isFinite) continue;
    sum += value;
    count++;
  }
  return count == 0 ? null : sum / count;
}

double? _shapeDrift(List<Stroke> first, List<Stroke> last, StrokeSide side) {
  final a = _meanNormalisedShape(first, side);
  final b = _meanNormalisedShape(last, side);
  if (a == null || b == null) return null;
  return _relativeRmsDifference(a, b);
}

double? _shapeVariation(List<Stroke> strokes) {
  final values = <double>[];
  for (final side in StrokeSide.values) {
    final curves = _normalisedShapes(strokes, side);
    if (curves.length < 2) continue;
    final mean = _meanCurve(curves);
    for (final curve in curves) {
      values.add(_relativeRmsDifference(mean, curve));
    }
  }
  return values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
}

double? _leftRightShapeDifference(List<Stroke> strokes) {
  final left = _meanNormalisedShape(strokes, StrokeSide.left);
  final right = _meanNormalisedShape(strokes, StrokeSide.right);
  if (left == null || right == null) return null;
  return _relativeRmsDifference(left, right);
}

List<double>? _meanNormalisedShape(List<Stroke> strokes, StrokeSide side) {
  final curves = _normalisedShapes(strokes, side);
  return curves.isEmpty ? null : _meanCurve(curves);
}

List<List<double>> _normalisedShapes(List<Stroke> strokes, StrokeSide side) =>
    <List<double>>[
      for (final stroke in strokes) ?_normalisedShape(stroke.sides?[side]),
    ];

List<double>? _normalisedShape(StrokeMetrics? metrics) {
  if (metrics == null || metrics.powerPhaseCurve.length < 2) return null;
  final curve = resamplePhaseCurve(metrics.powerPhaseCurve, points: 48);
  if (curve.length != 48) return null;
  final rms = math.sqrt(
    curve.fold<double>(0, (sum, point) => sum + point.y * point.y) /
        curve.length,
  );
  if (rms <= 0 || !rms.isFinite) return null;
  return <double>[for (final point in curve) point.y / rms];
}

List<double> _meanCurve(List<List<double>> curves) => <double>[
  for (var i = 0; i < curves.first.length; i++)
    curves.fold<double>(0, (sum, curve) => sum + curve[i]) / curves.length,
];

double _relativeRmsDifference(List<double> reference, List<double> other) {
  var squaredDifference = 0.0;
  var squaredReference = 0.0;
  for (var i = 0; i < reference.length; i++) {
    final delta = other[i] - reference[i];
    squaredDifference += delta * delta;
    squaredReference += reference[i] * reference[i];
  }
  if (squaredReference <= 0) return 0;
  return math.sqrt(squaredDifference / squaredReference) * 100;
}
