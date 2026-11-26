/// Was aus jedem Schritt einer Einheit wirklich geworden ist.
///
/// ## Warum das gebraucht wird
///
/// Die Führung im Cockpit sagt, was zu tun ist. Danach war es weg: Eine
/// gefahrene Einheit hinterliess ihre Züge, aber niemand wusste mehr, welcher
/// Zug zu welchem Intervall gehörte. Die Frage «wie war das dritte, verglichen
/// mit dem ersten» — die Frage, wegen der man Intervalle fährt — war nicht
/// beantwortbar.
///
/// ## Wie er arbeitet
///
/// Er sammelt Züge, solange ein Schritt läuft, und schliesst ihn ab, sobald
/// die Führung zum nächsten weitergeht. Gerechnet wird nichts Neues: Was
/// herauskommt, sind dieselben Zugauswertungen wie überall
/// ([stroke_analytics.dart](../metrics/stroke_analytics.dart)), nur auf einen
/// Abschnitt begrenzt.
///
/// Die Vorgabe wird mitgeschrieben. Ohne sie liesse sich später nicht sagen,
/// ob 241 W gut waren — und die Vorgabe stammt aus der Diagnostik des Tages,
/// die sich bis zur nächsten Ansicht geändert haben kann.
library;

import 'dart:convert';

import '../core/models.dart';
import '../metrics/stroke_analytics.dart';
import '../workout_engine/workout_engine.dart';

/// Ein abgeschlossener Abschnitt einer Einheit.
class IntervalResult {
  const IntervalResult({
    required this.ordinal,
    required this.kind,
    required this.startedAtUs,
    required this.endedAtUs,
    required this.strokes,
    this.firstStrokeOrdinal,
    this.lastStrokeOrdinal,
    this.targetMinWatt,
    this.targetMaxWatt,
  });

  /// Der wievielte Schritt der Einheit.
  final int ordinal;
  final WorkoutStepKind kind;

  final int startedAtUs;
  final int endedAtUs;

  /// Die Züge dieses Abschnitts.
  final List<Stroke> strokes;

  /// Inklusive Spanne der persistenten Session-Zugzeilen dieses Abschnitts.
  /// Null, wenn ein Aufrufer nur im Speicher aggregiert hat. Eine exakte
  /// Abschnitt-zu-Zug-Beziehung darf nur mit beiden Grenzen behauptet werden.
  final int? firstStrokeOrdinal;
  final int? lastStrokeOrdinal;

  /// Was vorgegeben war — null, wenn die Diagnostik keine Zahl hergab.
  final double? targetMinWatt;
  final double? targetMaxWatt;

  Duration get duration =>
      Duration(microseconds: (endedAtUs - startedAtUs).clamp(0, 1 << 62));

  double get workJoule => strokes.isEmpty
      ? 0
      : strokes.map((stroke) => stroke.workJoule).reduce((a, b) => a + b);

  /// Mittlere Leistung über den Abschnitt, Rückholphasen eingeschlossen.
  ///
  /// Beschreibt, wie dicht der Abschnitt war — nicht, wie stark gezogen
  /// wurde. Bleibt erhalten, weil sie gespeichert ist und etwas anderes sagt;
  /// angezeigt und bewertet wird [averageStrokePowerWatt].
  double? get averagePowerWatt {
    final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds <= 0 || strokes.isEmpty) return null;
    return workJoule / seconds;
  }

  /// Mittlere Leistung **im Zug**.
  ///
  /// Das ist die Zahl, die eine Leistung beschreibt: Wer dieselben Züge
  /// langsamer wiederholt, hat nicht schwächer gezogen — die Leistung über
  /// die Gesamtzeit faellt trotzdem. Deshalb steht sie in der Auswertung und
  /// entscheidet über [withinTarget]; eine Wattvorgabe meint den Zug.
  double? get averageStrokePowerWatt {
    if (strokes.isEmpty) return null;
    final activeSeconds = strokes.fold<double>(
      0,
      (sum, stroke) => sum + stroke.durationSeconds,
    );
    return activeSeconds <= 0 ? null : workJoule / activeSeconds;
  }

  /// Median der einzeln gespeicherten Zugleistungen. Der Median bleibt neben
  /// dem aktiven Mittel erhalten, weil ein einzelner Maximalzug den Mittelwert
  /// verschieben kann.
  double? get medianStrokePowerWatt {
    if (strokes.isEmpty) return null;
    final values = <double>[for (final stroke in strokes) stroke.meanPowerWatt]
      ..sort();
    final middle = values.length ~/ 2;
    return values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2;
  }

  /// Veraenderung der Zugleistung zwischen erstem und letztem Fuenftel.
  double? get fatigueDeltaPercent {
    if (strokes.length < 10) return null;
    final count = (strokes.length * .2)
        .floor()
        .clamp(2, strokes.length ~/ 2)
        .toInt();
    double mean(Iterable<Stroke> values) =>
        values.fold<double>(0, (sum, stroke) => sum + stroke.meanPowerWatt) /
        values.length;
    final first = mean(strokes.take(count));
    final last = mean(strokes.skip(strokes.length - count));
    return first <= 0 ? null : (last - first) / first * 100;
  }

  double? get peakPowerWatt => peakPower(strokes);

  ({double left, double right})? get sides => sidePower(strokes);

  int get strokeCount => strokes.length;

  /// Ob die Zugleistung im vorgegebenen Bereich lag.
  ///
  /// Null, wenn es keine Vorgabe gab — und dann steht auf dem Bildschirm auch
  /// keine Bewertung. Eine Zielerfüllung ohne Ziel wäre eine erfundene Note.
  bool? get withinTarget {
    final min = targetMinWatt;
    final max = targetMaxWatt;
    final actual = averageStrokePowerWatt;
    if (min == null || max == null || actual == null) return null;
    return actual >= min && actual <= max;
  }
}

/// Das Ergebnis eines Abschnitts als Zeichenkette.
///
/// Lesbar und benannt: Wer in zwei Jahren in die Datenbank sieht, soll
/// erkennen, was vorgegeben war und was daraus wurde.
String encodeInterval(IntervalResult result) {
  final sides = result.sides;
  return jsonEncode(<String, Object?>{
    'kind': result.kind.name,
    'strokes': result.strokeCount,
    if (result.firstStrokeOrdinal != null && result.lastStrokeOrdinal != null)
      'firstStrokeOrdinal': result.firstStrokeOrdinal,
    if (result.firstStrokeOrdinal != null && result.lastStrokeOrdinal != null)
      'lastStrokeOrdinal': result.lastStrokeOrdinal,
    'workJoule': result.workJoule,
    if (result.averagePowerWatt != null)
      'averagePowerWatt': result.averagePowerWatt,
    if (result.averageStrokePowerWatt != null)
      'averageStrokePowerWatt': result.averageStrokePowerWatt,
    if (result.medianStrokePowerWatt != null)
      'medianStrokePowerWatt': result.medianStrokePowerWatt,
    if (result.fatigueDeltaPercent != null)
      'fatigueDeltaPercent': result.fatigueDeltaPercent,
    if (result.peakPowerWatt != null) 'peakPowerWatt': result.peakPowerWatt,
    if (sides != null) 'leftWatt': sides.left,
    if (sides != null) 'rightWatt': sides.right,
    if (result.targetMinWatt != null) 'targetMinWatt': result.targetMinWatt,
    if (result.targetMaxWatt != null) 'targetMaxWatt': result.targetMaxWatt,
  });
}

/// Ein Abschnitt, aus dem Archiv gelesen.
class RecordedInterval {
  const RecordedInterval({
    required this.ordinal,
    required this.kind,
    required this.duration,
    this.startedAtUs,
    this.endedAtUs,
    required this.strokeCount,
    required this.workJoule,
    this.firstStrokeOrdinal,
    this.lastStrokeOrdinal,
    this.strokes = const <Stroke>[],
    this.averagePowerWatt,
    this.averageStrokePowerWatt,
    this.medianStrokePowerWatt,
    this.fatigueDeltaPercent,
    this.peakPowerWatt,
    this.leftWatt,
    this.rightWatt,
    this.targetMinWatt,
    this.targetMaxWatt,
  });

  factory RecordedInterval.fromJson({
    required int ordinal,
    required Duration duration,
    required String json,
    int? startedAtUs,
    int? endedAtUs,
  }) {
    final data = jsonDecode(json) as Map<String, Object?>;
    double? number(String key) => (data[key] as num?)?.toDouble();
    final strokeCount = (data['strokes'] as num?)?.toInt() ?? 0;
    final storedFirst = (data['firstStrokeOrdinal'] as num?)?.toInt();
    final storedLast = (data['lastStrokeOrdinal'] as num?)?.toInt();
    final exactRange =
        storedFirst != null &&
        storedLast != null &&
        storedFirst >= 0 &&
        storedLast >= storedFirst &&
        storedLast - storedFirst + 1 == strokeCount;
    return RecordedInterval(
      ordinal: ordinal,
      kind: _kindFrom(data['kind'] as String?),
      duration: duration,
      startedAtUs: startedAtUs,
      endedAtUs: endedAtUs,
      strokeCount: strokeCount,
      workJoule: number('workJoule') ?? 0,
      firstStrokeOrdinal: exactRange ? storedFirst : null,
      lastStrokeOrdinal: exactRange ? storedLast : null,
      averagePowerWatt: number('averagePowerWatt'),
      averageStrokePowerWatt: number('averageStrokePowerWatt'),
      medianStrokePowerWatt: number('medianStrokePowerWatt'),
      fatigueDeltaPercent: number('fatigueDeltaPercent'),
      peakPowerWatt: number('peakPowerWatt'),
      leftWatt: number('leftWatt'),
      rightWatt: number('rightWatt'),
      targetMinWatt: number('targetMinWatt'),
      targetMaxWatt: number('targetMaxWatt'),
    );
  }

  final int ordinal;
  final WorkoutStepKind kind;
  final Duration duration;
  final int? startedAtUs;
  final int? endedAtUs;
  final int strokeCount;
  final double workJoule;
  final int? firstStrokeOrdinal;
  final int? lastStrokeOrdinal;

  /// Exakte archivierte Züge dieses Abschnitts. Bei alten Intervallzeilen
  /// bleiben die Aggregate erhalten, die Mitgliedschaft bleibt aber offen.
  final List<Stroke> strokes;

  bool get hasExactStrokeMembership =>
      firstStrokeOrdinal != null &&
      lastStrokeOrdinal != null &&
      strokes.length == strokeCount;

  RecordedInterval withExactStrokes(List<Stroke> value) {
    if (firstStrokeOrdinal == null ||
        lastStrokeOrdinal == null ||
        value.length != strokeCount) {
      return this;
    }
    return RecordedInterval(
      ordinal: ordinal,
      kind: kind,
      duration: duration,
      startedAtUs: startedAtUs,
      endedAtUs: endedAtUs,
      strokeCount: strokeCount,
      workJoule: workJoule,
      firstStrokeOrdinal: firstStrokeOrdinal,
      lastStrokeOrdinal: lastStrokeOrdinal,
      strokes: List<Stroke>.unmodifiable(value),
      averagePowerWatt: averagePowerWatt,
      averageStrokePowerWatt: averageStrokePowerWatt,
      medianStrokePowerWatt: medianStrokePowerWatt,
      fatigueDeltaPercent: fatigueDeltaPercent,
      peakPowerWatt: peakPowerWatt,
      leftWatt: leftWatt,
      rightWatt: rightWatt,
      targetMinWatt: targetMinWatt,
      targetMaxWatt: targetMaxWatt,
    );
  }

  final double? averagePowerWatt;

  /// Mittlere Leistung im Zug. Null bei Abschnitten, die vor dieser
  /// Unterscheidung gespeichert wurden — dort bleibt nur die Gesamtleistung.
  final double? averageStrokePowerWatt;
  final double? medianStrokePowerWatt;
  final double? fatigueDeltaPercent;
  final double? peakPowerWatt;

  /// Die Zahl, die angezeigt und bewertet wird: die Zugleistung, und nur
  /// ersatzweise die alte Gesamtleistung.
  double? get shownPowerWatt => averageStrokePowerWatt ?? averagePowerWatt;
  final double? leftWatt;
  final double? rightWatt;
  final double? targetMinWatt;
  final double? targetMaxWatt;

  bool get hasTarget => targetMinWatt != null && targetMaxWatt != null;

  /// Ob die Leistung im Zielbereich lag. Null ohne Vorgabe.
  bool? get withinTarget {
    final actual = shownPowerWatt;
    if (!hasTarget || actual == null) return null;
    return actual >= targetMinWatt! && actual <= targetMaxWatt!;
  }
}

WorkoutStepKind _kindFrom(String? stored) {
  for (final kind in WorkoutStepKind.values) {
    if (kind.name == stored) return kind;
  }
  return WorkoutStepKind.work;
}

/// Sammelt Abschnitte, während eine Einheit läuft.
class WorkoutRecorder {
  WorkoutRecorder({Map<int, ({double min, double max})> targets = const {}})
    : _targets = Map.of(targets);

  /// Die aufgelösten Vorgaben je Schrittnummer. Leer heisst: keine Zahlen —
  /// die Einheit läuft trotzdem.
  final Map<int, ({double min, double max})> _targets;

  Map<int, ({double min, double max})> get targets => _targets;

  void updateTargets(Map<int, ({double min, double max})> newTargets) {
    _targets
      ..clear()
      ..addAll(newTargets);
  }

  final List<IntervalResult> _closed = [];
  final List<Stroke> _current = [];
  final List<int> _currentStrokeOrdinals = [];
  bool _currentStrokeOrdinalsComplete = true;
  int? _openOrdinal;
  int _openStartedAtUs = 0;
  WorkoutStepKind _openKind = WorkoutStepKind.work;

  /// Die bisher abgeschlossenen Abschnitte.
  List<IntervalResult> get results => List.unmodifiable(_closed);

  /// Ein Zug gehört zum gerade laufenden Abschnitt.
  void onStroke(Stroke stroke, {int? ordinal}) {
    if (_openOrdinal == null) return;
    _current.add(stroke);
    if (ordinal == null ||
        ordinal < 0 ||
        (_currentStrokeOrdinals.isNotEmpty &&
            ordinal != _currentStrokeOrdinals.last + 1)) {
      _currentStrokeOrdinalsComplete = false;
    } else {
      _currentStrokeOrdinals.add(ordinal);
    }
  }

  /// Meldet den Stand der Führung. Gibt den abgeschlossenen Abschnitt zurück,
  /// wenn gerade einer zu Ende ging.
  IntervalResult? onProgress(WorkoutProgress progress, int nowUs) {
    final ordinal = progress.completed ? null : progress.stepIndex;
    if (ordinal == _openOrdinal) return null;

    final closed = _close(nowUs);
    if (ordinal != null) {
      _openOrdinal = ordinal;
      _openStartedAtUs = nowUs;
      _openKind = progress.step?.kind ?? WorkoutStepKind.work;
    }
    return closed;
  }

  /// Schliesst den offenen Abschnitt — beim Beenden der Einheit.
  IntervalResult? finish(int nowUs) => _close(nowUs);

  /// Snapshot for a database transaction. Keep collecting if the commit fails.
  IntervalResult? snapshotOpenInterval(int nowUs) {
    final ordinal = _openOrdinal;
    if (ordinal == null) return null;

    final target = targets[ordinal];
    final exactOrdinals =
        _currentStrokeOrdinalsComplete &&
        _currentStrokeOrdinals.length == _current.length &&
        _currentStrokeOrdinals.isNotEmpty;
    return IntervalResult(
      ordinal: ordinal,
      kind: _openKind,
      startedAtUs: _openStartedAtUs,
      endedAtUs: nowUs,
      strokes: List.unmodifiable(_current),
      firstStrokeOrdinal: exactOrdinals ? _currentStrokeOrdinals.first : null,
      lastStrokeOrdinal: exactOrdinals ? _currentStrokeOrdinals.last : null,
      targetMinWatt: target?.min,
      targetMaxWatt: target?.max,
    );
  }

  IntervalResult? _close(int nowUs) {
    final result = snapshotOpenInterval(nowUs);
    if (result == null) return null;
    _closed.add(result);
    _current.clear();
    _currentStrokeOrdinals.clear();
    _currentStrokeOrdinalsComplete = true;
    _openOrdinal = null;
    return result;
  }
}
