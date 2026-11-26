/// Kurven eines Zuges — und die Mittelung über mehrere.
///
/// ## Warum gemittelt wird
///
/// Ein einzelner Zug ist zu unruhig, um ihn während des Trainings zu lesen:
/// das Diagramm spränge bei jedem Zug, und das Auge folgte der Bewegung statt
/// dem Befund. Gemittelt über fünf oder zehn Züge steht die Form still, und
/// genau die Form ist die Aussage. Der einzelne Zug bleibt wählbar, weil er
/// beim Techniküben die Frage ist.
///
/// ## Warum über die Phase gemittelt wird und nicht über die Zeit
///
/// Zwei Züge dauern nie gleich lang. Über der Zeit gemittelt verschmieren
/// Anfang und Ende zu einer Kurve, die kein Zug je hatte. Über der Phase — null
/// bis eins des Zuges — liegen Zugbeginn, Spitze und Zugende übereinander, und
/// der Mittelwert beschreibt eine Bewegung, die wirklich so gefahren wird.
library;

import 'dart:math' as math;

import '../core/stroke_metrics.dart';

/// Welcher Zug im Diagramm steht.
enum StrokeSelection {
  last('Letzter Zug', 1),
  lastFive('Ø 5 Züge', 5),
  lastTen('Ø 10 Züge', 10),
  all('Ganze Einheit', 0);

  const StrokeSelection(this.label, this.strokes);

  final String label;

  /// Über wie viele Züge gemittelt wird. 0 bedeutet alle Züge.
  final int strokes;
}

/// Ein Punkt einer gemittelten Kurve.
class CurvePoint {
  const CurvePoint({required this.x, required this.y});

  final double x;
  final double y;
}

/// Auflösung der dargestellten Kurve.
///
/// Intern liegen die Züge in voller Abtastrate; fürs Bild werden sie auf ein
/// festes Raster gelegt, fein genug, dass die Kurve auch auf dem Tablet ohne
/// Ecken läuft.
const int curveResolution = 96;

/// Legt eine Leistungs-Phasen-Kurve auf das feste Raster.
List<CurvePoint> resamplePhaseCurve(
  List<PowerPhaseSample> curve, {
  int points = curveResolution,
}) => _resample(
  xs: <double>[for (final sample in curve) sample.phase],
  ys: <double>[for (final sample in curve) sample.powerWatt],
  from: 0,
  to: 1,
  points: points,
);

/// Legt eine Kraft-Weg-Kurve auf das feste Raster, bezogen auf den Zugweg.
///
/// Das Raster läuft über den *anteiligen* Weg, damit Züge verschiedener Länge
/// überlagert werden können; die Achse trägt anschliessend die mittlere Länge.
List<CurvePoint> resampleForceCurve(
  List<ForceDistanceSample> curve, {
  int points = curveResolution,
}) {
  if (curve.isEmpty) return const <CurvePoint>[];
  final total = curve.last.distanceMetres;
  if (total <= 0) return const <CurvePoint>[];
  return _resample(
    xs: <double>[for (final s in curve) s.distanceMetres / total],
    ys: <double>[for (final s in curve) s.forceNewton],
    from: 0,
    to: 1,
    points: points,
  );
}

/// Mittelt die Leistungskurven mehrerer Züge einer Seite.
///
/// [strokes] ist die Zugfolge, älteste zuerst; genommen werden die letzten
/// [selection] Züge. Züge ohne Kurve werden übergangen, nicht mit null
/// aufgefüllt.
List<CurvePoint> averagePowerPhaseCurve(
  List<StrokeMetrics> strokes,
  StrokeSelection selection, {
  int points = curveResolution,
}) => _average(<List<CurvePoint>>[
  for (final stroke in _tail(strokes, selection))
    if (stroke.powerPhaseCurve.isNotEmpty)
      resamplePhaseCurve(stroke.powerPhaseCurve, points: points),
], points);

/// Mittelt die Kraft-Weg-Kurven mehrerer Züge einer Seite.
///
/// Die x-Achse ist der Weg in Metern: die anteilig gemittelte Kurve wird mit
/// der mittleren Zuglänge der beteiligten Züge gestreckt.
List<CurvePoint> averageForceDistanceCurve(
  List<StrokeMetrics> strokes,
  StrokeSelection selection, {
  int points = curveResolution,
}) {
  final tail = <StrokeMetrics>[
    for (final stroke in _tail(strokes, selection))
      if (stroke.forceDistanceCurve.isNotEmpty) stroke,
  ];
  if (tail.isEmpty) return const <CurvePoint>[];
  final shape = _average(<List<CurvePoint>>[
    for (final stroke in tail)
      resampleForceCurve(stroke.forceDistanceCurve, points: points),
  ], points);
  final length = averageStrokeLength(tail);
  if (length == null || length <= 0) return shape;
  return <CurvePoint>[
    for (final point in shape) CurvePoint(x: point.x * length, y: point.y),
  ];
}

/// Mittlere Zuglänge der gegebenen Züge, oder null ohne belegte Länge.
double? averageStrokeLength(List<StrokeMetrics> strokes) {
  var sum = 0.0;
  var count = 0;
  for (final stroke in strokes) {
    final length = stroke.strokeLengthMetres;
    if (length == null) continue;
    sum += length;
    count++;
  }
  return count == 0 ? null : sum / count;
}

/// Mittelwert einer Grösse über die gewählten Züge, oder null.
double? averageOf(
  List<StrokeMetrics> strokes,
  StrokeSelection selection,
  double? Function(StrokeMetrics stroke) value,
) {
  var sum = 0.0;
  var count = 0;
  for (final stroke in _tail(strokes, selection)) {
    final single = value(stroke);
    if (single == null) continue;
    sum += single;
    count++;
  }
  return count == 0 ? null : sum / count;
}

List<StrokeMetrics> _tail(List<StrokeMetrics> strokes, StrokeSelection s) =>
    s.strokes <= 0 || strokes.length <= s.strokes
        ? strokes
        : strokes.sublist(strokes.length - s.strokes);

/// Punktweises Mittel gleich gerasterter Kurven.
List<CurvePoint> _average(List<List<CurvePoint>> curves, int points) {
  final usable = <List<CurvePoint>>[
    for (final curve in curves)
      if (curve.length == points) curve,
  ];
  if (usable.isEmpty) return const <CurvePoint>[];
  return <CurvePoint>[
    for (var i = 0; i < points; i++)
      CurvePoint(
        x: usable.first[i].x,
        y:
            usable.fold<double>(0, (sum, curve) => sum + curve[i].y) /
            usable.length,
      ),
  ];
}

/// Die gemessenen Punkte eines Zuges innerhalb des Zuges (Phase 0 bis 1).
List<CurvePoint> measuredPhasePoints(StrokeMetrics stroke) => <CurvePoint>[
  for (final sample in stroke.powerPhaseCurve)
    if (sample.phase >= 0 && sample.phase <= 1)
      CurvePoint(x: sample.phase, y: sample.powerWatt),
];

/// Monotone kubische Interpolation (Fritsch–Butland) auf ein gleichmässiges
/// Raster.
///
/// Zwischen zwei Messpunkten bleibt die Kurve in deren Wertebereich: sie
/// schwingt nicht über, und die Spitze bleibt der höchste gemessene Wert.
List<CurvePoint> _resample({
  required List<double> xs,
  required List<double> ys,
  required double from,
  required double to,
  required int points,
}) {
  if (xs.length < 2 || xs.length != ys.length || points < 2) {
    return const <CurvePoint>[];
  }
  final px = <double>[];
  final py = <double>[];
  for (var i = 0; i < xs.length; i++) {
    if (px.isNotEmpty && xs[i] <= px.last) continue;
    px.add(xs[i]);
    py.add(ys[i]);
  }
  if (px.length < 2) return const <CurvePoint>[];
  final n = px.length;
  final h = <double>[for (var k = 0; k + 1 < n; k++) px[k + 1] - px[k]];
  final d = <double>[
    for (var k = 0; k + 1 < n; k++) (py[k + 1] - py[k]) / h[k],
  ];
  final m = List<double>.filled(n, 0);
  m[0] = d.first;
  m[n - 1] = d.last;
  for (var k = 1; k + 1 < n; k++) {
    if (d[k - 1] * d[k] <= 0) continue;
    m[k] =
        3 *
        (h[k - 1] + h[k]) /
        ((2 * h[k] + h[k - 1]) / d[k - 1] + (h[k] + 2 * h[k - 1]) / d[k]);
  }
  final result = <CurvePoint>[];
  var k = 0;
  for (var step = 0; step < points; step++) {
    final x = from + (to - from) * step / (points - 1);
    while (k + 2 < n && px[k + 1] < x) {
      k++;
    }
    final t = ((x - px[k]) / h[k]).clamp(0.0, 1.0);
    final t2 = t * t;
    final t3 = t2 * t;
    final y =
        (2 * t3 - 3 * t2 + 1) * py[k] +
        (t3 - 2 * t2 + t) * h[k] * m[k] +
        (-2 * t3 + 3 * t2) * py[k + 1] +
        (t3 - t2) * h[k] * m[k + 1];
    result.add(CurvePoint(x: x, y: y));
  }
  return List.unmodifiable(result);
}

/// Höchster y-Wert mehrerer Kurven, für eine gemeinsame Achse.
double maxY(Iterable<List<CurvePoint>> curves) {
  var top = 0.0;
  for (final curve in curves) {
    for (final point in curve) {
      top = math.max(top, point.y);
    }
  }
  return top;
}
