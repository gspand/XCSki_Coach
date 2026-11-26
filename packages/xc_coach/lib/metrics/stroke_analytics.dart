/// Was sich aus einer Folge von Zügen sagen lässt.
///
/// ## Warum das hier steht und nicht im Bildschirm
///
/// Weil es Aussagen über Messwerte sind und keine Darstellung. Ein Mittelwert,
/// der in einem Widget entsteht, lässt sich nicht prüfen, nicht wiederverwenden
/// und nicht nachrechnen — und genau das sind die drei Dinge, die eine
/// Trainingsaussage braucht.
///
/// ## Die Regel, der alles hier folgt
///
/// **Nichts wird geschätzt.** Jede Funktion gibt null zurück, wo die Daten die
/// Aussage nicht tragen: zu wenige Züge, keine Arbeit, keine Zeit. Ein
/// Ermüdungswert aus drei Zügen wäre eine Zahl ohne Inhalt, und ein
/// Variationskoeffizient über zwei Werte ist Arithmetik, keine Aussage.
///
/// ## Warum Joule je Zug
///
/// Zwei Athleten mit derselben mittleren Leistung sind nicht dieselben
/// Athleten: 250 W aus 40 kräftigen Zügen je Minute ist eine andere Bewegung
/// als 250 W aus 60 schwächeren. Watt allein verbirgt diesen Unterschied, die
/// Arbeit je Zug zeigt ihn.
library;

import 'dart:math' as math;

import '../core/models.dart';

/// Mittlere Leistung je Seite über eine Folge von Zügen.
///
/// Gerechnet als Arbeit durch Zeit, nicht als Mittel der Zugmittelwerte: ein
/// kurzer und ein langer Zug tragen sonst gleich viel bei, obwohl der eine
/// doppelt so lange gearbeitet hat.
({double left, double right})? sidePower(List<Stroke> strokes) {
  var left = 0.0;
  var right = 0.0;
  var seconds = 0.0;
  for (final stroke in strokes) {
    left += stroke.leftWorkJoule;
    right += stroke.rightWorkJoule;
    seconds += stroke.durationSeconds;
  }
  if (seconds <= 0) return null;
  return (left: left / seconds, right: right / seconds);
}

/// Mittlere Leistung je Zug über alle abgeschlossenen Züge.
///
/// Berechnet als Mittelwert der Zugmittelwerte ([Stroke.meanPowerWatt]).
/// Das ist die sportlich relevante Zugleistung während der aktiven Züge,
/// im Gegensatz zur Gesamtleistung über die ganze Einheit inklusive Pausen.
double? averageStrokePower(List<Stroke> strokes) => _meanPower(strokes);

/// Mittlere Gesamtleistung über die [count] jüngsten abgeschlossenen Züge.
///
/// Arbeit und Dauer werden zuerst zusammengeführt, damit ein kurzer Zug nicht
/// dasselbe Gewicht wie ein langer Zug erhält.
double? recentStrokePower(List<Stroke> strokes, int count) {
  if (count <= 0 || strokes.length < count) return null;
  final recent = strokes.skip(strokes.length - count);
  var work = 0.0;
  var seconds = 0.0;
  for (final stroke in recent) {
    work += stroke.workJoule;
    seconds += stroke.durationSeconds;
  }
  return seconds <= 0 ? null : work / seconds;
}

/// Mittlere Arbeit je Zug, gesamt und je Seite.
({double total, double left, double right})? workPerStroke(
  List<Stroke> strokes,
) {
  if (strokes.isEmpty) return null;
  var total = 0.0;
  var left = 0.0;
  var right = 0.0;
  for (final stroke in strokes) {
    total += stroke.workJoule;
    left += stroke.leftWorkJoule;
    right += stroke.rightWorkJoule;
  }
  final count = strokes.length;
  return (total: total / count, left: left / count, right: right / count);
}

/// Die höchste Spitzenleistung der Folge.
double? peakPower(List<Stroke> strokes) {
  if (strokes.isEmpty) return null;
  return strokes.fold<double>(
    0,
    (top, stroke) => math.max(top, stroke.peakPowerWatt),
  );
}

/// Veränderung der mittleren Zugleistung über die Folge, in Prozent.
///
/// Verglichen wird die zweite Hälfte mit der ersten. Negative Werte bedeuten
/// Abfall — das ist die Ermüdung, nach der jemand sucht. Unter [minimumStrokes]
/// Zügen gibt es keine Aussage: eine Prozentzahl aus vier Zügen beschreibt
/// Zufall, nicht Ermüdung.
double? fatiguePercent(List<Stroke> strokes, {int minimumStrokes = 8}) {
  if (strokes.length < minimumStrokes) return null;
  final half = strokes.length ~/ 2;
  final first = _meanPower(strokes.take(half));
  final second = _meanPower(strokes.skip(strokes.length - half));
  if (first == null || second == null || first <= 0) return null;
  return (second - first) / first * 100;
}

/// Variationskoeffizient der Zugleistung in Prozent — die technische Konstanz.
///
/// Ein niedriger Wert heisst: jeder Zug gleicht dem anderen. Er sagt nichts
/// darüber, ob die Züge gut sind.
double? powerVariationPercent(List<Stroke> strokes, {int minimumStrokes = 5}) {
  if (strokes.length < minimumStrokes) return null;
  final mean = _meanPower(strokes);
  if (mean == null || mean <= 0) return null;
  var sum = 0.0;
  for (final stroke in strokes) {
    final delta = stroke.meanPowerWatt - mean;
    sum += delta * delta;
  }
  final deviation = math.sqrt(sum / strokes.length);
  return deviation / mean * 100;
}

/// Ein Frequenzband und was in ihm geleistet wurde.
class PowerRateBin {
  const PowerRateBin({
    required this.rateFrom,
    required this.rateTo,
    required this.meanPowerWatt,
    required this.meanWorkPerStrokeJoule,
    required this.strokes,
  });

  final double rateFrom;
  final double rateTo;
  final double meanPowerWatt;
  final double meanWorkPerStrokeJoule;
  final int strokes;

  double get rateCentre => (rateFrom + rateTo) / 2;
}

/// Wie dieser Mensch Leistung erzeugt: über die Frequenz oder über den Zug.
///
/// Die Züge werden nach Zugfrequenz in Bänder von [binWidth] Zügen je Minute
/// sortiert; je Band steht die mittlere Leistung und die mittlere Arbeit je
/// Zug. Erst beides zusammen beantwortet die Frage — steigende Leistung bei
/// gleicher Arbeit je Zug kommt aus der Frequenz, steigende Arbeit je Zug aus
/// dem Zug selbst.
///
/// Bänder mit weniger als [minimumPerBin] Zügen fallen weg: ein einzelner Zug
/// ist ein Ausrutscher, kein Arbeitspunkt.
List<PowerRateBin> powerRateMatrix(
  List<Stroke> strokes, {
  double binWidth = 6,
  int minimumPerBin = 3,
}) {
  final buckets = <int, List<Stroke>>{};
  for (final stroke in strokes) {
    final rate = stroke.frequencyPerMinute;
    if (rate <= 0) continue;
    buckets
        .putIfAbsent((rate / binWidth).floor(), () => <Stroke>[])
        .add(stroke);
  }
  final bins = <PowerRateBin>[];
  for (final entry in buckets.entries) {
    if (entry.value.length < minimumPerBin) continue;
    final mean = _meanPower(entry.value)!;
    var work = 0.0;
    for (final stroke in entry.value) {
      work += stroke.workJoule;
    }
    bins.add(
      PowerRateBin(
        rateFrom: entry.key * binWidth,
        rateTo: (entry.key + 1) * binWidth,
        meanPowerWatt: mean,
        meanWorkPerStrokeJoule: work / entry.value.length,
        strokes: entry.value.length,
      ),
    );
  }
  bins.sort((a, b) => a.rateFrom.compareTo(b.rateFrom));
  return List.unmodifiable(bins);
}

/// Welche Seite nichts liefert — oder null, wenn beide senden.
///
/// ## Warum das eine Messaussage ist und keine Anzeigeentscheidung
///
/// Fällt ein Sensor aus, kommen weiter Züge an: Die Paarung hält die letzte
/// bekannte Seite, und die Zugerkennung findet weiterhin Züge. Die
/// Seitenverteilung zeigt dann 100 zu 0 — und eine Oberfläche, die das nicht
/// benennt, zeigt einen Athleten, der perfekt einseitig zieht.
///
/// Geprüft wird über mehrere Züge, nicht über einen: Ein einzelner Zug ohne
/// Arbeit auf einer Seite kommt vor, wenn jemand die Hand nachfasst.
SensorSide? silentSide(List<Stroke> strokes, {int minimumStrokes = 3}) {
  if (strokes.length < minimumStrokes) return null;
  final recent = strokes.length <= 8
      ? strokes
      : strokes.sublist(strokes.length - 8);

  var left = 0.0;
  var right = 0.0;
  for (final stroke in recent) {
    left += stroke.leftWorkJoule;
    right += stroke.rightWorkJoule;
  }
  final total = left + right;
  if (total <= 0) return null;

  // Ein Prozent der Gesamtarbeit: unterhalb davon liefert die Seite nichts,
  // was eine Aussage trüge.
  if (right / total < .01) return SensorSide.right;
  if (left / total < .01) return SensorSide.left;
  return null;
}

double? _meanPower(Iterable<Stroke> strokes) {
  var sum = 0.0;
  var count = 0;
  for (final stroke in strokes) {
    sum += stroke.meanPowerWatt;
    count++;
  }
  return count == 0 ? null : sum / count;
}
