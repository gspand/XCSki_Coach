import 'dart:math' as math;

import '../core/models.dart';

/// What the live screen is allowed to show.
///
/// Every field here is either measured or integrated from measurements. There
/// is no estimate in this class and no field that exists only because a screen
/// wanted one — the live screen shows what the sensors produced, or it shows
/// nothing.
///
/// ## Why the per-stroke values matter more than the instantaneous ones
///
/// On this machine a stroke is the natural unit. The manufacturer's own
/// computer states force and power as *averages per push* and can only state
/// them when the flywheel keeps turning after the push, because that free
/// run-down is what reveals the brake. An instantaneous number is useful as
/// motion on the screen; the per-stroke number is the one a coach can compare.
/// The live screen leads with the latter for exactly that reason.
/// Die beste mittlere Leistung über feste Zeitfenster.
///
/// Nicht die beste *Zug*-Leistung: gesucht ist, was jemand über fünf Sekunden,
/// über eine halbe Minute, über eine Minute durchgehalten hat. Genau das macht
/// zwei Einheiten und zwei Athleten vergleichbar, während ein einzelner
/// Spitzenzug vor allem Glück beschreibt.
///
/// Ein Fenster, für das die Einheit noch nicht lang genug ist, bleibt null —
/// eine «beste Minute» nach vierzig Sekunden gäbe es nicht.
class BestPowers {
  const BestPowers({
    this.fiveSeconds,
    this.tenSeconds,
    this.thirtySeconds,
    this.oneMinute,
  });

  final double? fiveSeconds;
  final double? tenSeconds;
  final double? thirtySeconds;
  final double? oneMinute;

  /// Die Fenster in der Reihenfolge, in der sie gezeigt werden.
  static const List<Duration> windows = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 1),
  ];

  double? forWindow(Duration window) => switch (window.inSeconds) {
    5 => fiveSeconds,
    10 => tenSeconds,
    30 => thirtySeconds,
    60 => oneMinute,
    _ => null,
  };
}

class LiveMetrics {
  const LiveMetrics({
    required this.powerWatt,
    required this.leftPowerWatt,
    required this.rightPowerWatt,
    required this.averagePowerWatt,
    required this.totalWorkJoule,
    required this.elapsedSeconds,
    required this.strokeCount,
    required this.lastStroke,
    required this.recentStrokes,
    required this.symmetryIndex,
    this.best = const BestPowers(),
    this.liveLeftPowerWatt,
    this.liveRightPowerWatt,
    this.awaitingPair = false,
  });

  /// Filtered power of the newest paired sample, both sides together.
  final double powerWatt;

  /// The same instant, per side. Kept apart because left and right are the
  /// question this machine is bought to answer.
  final double leftPowerWatt;
  final double rightPowerWatt;

  /// Integrated work divided by elapsed time — not a mean of samples.
  final double averagePowerWatt;

  final double totalWorkJoule;

  /// Seconds between the first and the newest sample of this session.
  final double elapsedSeconds;

  final int strokeCount;

  /// The newest completed stroke, or null before the first one is finished.
  final Stroke? lastStroke;

  /// The completed strokes still worth drawing, oldest first. Bounded by
  /// [MetricsEngine.strokeHistoryLength]; the same instance is handed out
  /// again until a stroke completes, so a screen may compare by identity.
  final List<Stroke> recentStrokes;

  final double symmetryIndex;

  /// Die besten Zeitfenster dieser Einheit.
  final BestPowers best;

  /// Die zuletzt gemessene Leistung je Seite, unabhängig von der Paarung.
  ///
  /// ## Warum es diese beiden Felder gibt
  ///
  /// Weil die ganze Live-Anzeige bisher an einer **gepaarten** Messung hing:
  /// [MetricsEngine.add] wird nur aufgerufen, wenn links und rechts sich zu
  /// einem Sample zusammenfügen lassen. Fällt ein Sensor aus, entsteht kein
  /// Paar — und damit blieb der Bildschirm **vollständig leer**, obwohl die
  /// andere Seite einwandfrei weitermass. Genau das ist passiert: In einer
  /// Einheit lieferte links 1 182 Proben und rechts keine einzige, und zu
  /// sehen war nichts.
  ///
  /// Arbeit, Züge und Symmetrie brauchen weiterhin ein echtes Paar — sie
  /// stehen hier nicht drin. Was hier steht, ist das, was **eine** Seite
  /// alleine weiss. Null heisst: diese Seite meldet sich gerade nicht.
  final double? liveLeftPowerWatt;
  final double? liveRightPowerWatt;

  /// Messwerte kommen an, aber das Gerät meldet links und rechts seit
  /// Sekunden als nicht zusammengehörig (Uhrenabgleich der Sensoren). Dann
  /// entstehen weder Leistung noch Züge.
  final bool awaitingPair;

  /// Der Stand vor der ersten gepaarten Messung.
  ///
  /// Er existiert, damit der Live-Bildschirm seine Seiten zeigen kann, bevor
  /// eine Messung durch ist. Vorher blieb dort eine Wartekarte stehen, und
  /// wenn die Paarung von links und rechts nicht zustande kam, blieb sie für
  /// immer stehen — man sah nicht einmal, welche Kacheln es überhaupt gibt.
  static const LiveMetrics idle = LiveMetrics(
    powerWatt: 0,
    leftPowerWatt: 0,
    rightPowerWatt: 0,
    averagePowerWatt: 0,
    totalWorkJoule: 0,
    elapsedSeconds: 0,
    strokeCount: 0,
    lastStroke: null,
    recentStrokes: <Stroke>[],
    symmetryIndex: 0,
  );

  /// Share of the left side in recent bilateral strokes, or null while no
  /// bilateral stroke has been completed.
  ///
  /// Deliberately built from *work*, not from a mean of shares: a soft stroke
  /// would otherwise weigh as much as a hard one and the number would drift
  /// with technique rather than with the imbalance it claims to describe.
  double? get recentLeftWorkShare {
    var left = 0.0;
    var total = 0.0;
    for (final stroke in recentStrokes) {
      if (!stroke.supportsSymmetry) continue;
      left += stroke.leftWorkJoule;
      total += stroke.workJoule;
    }
    if (total <= 0) return null;
    return left / total;
  }
}

/// Integrates power in the physical unit $J = W·s$. No packet-count estimates.
class MetricsEngine {
  /// How many completed strokes stay available for the live screen.
  ///
  /// Forty is a wide screen full of bars at a legible width. The bound is here
  /// rather than in the widget because a growing list in a stream that ticks at
  /// sample rate is a leak, not a layout decision.
  static const int strokeHistoryLength = 40;

  PairedSample? _previous;
  double _totalWorkJoule = 0;
  int _firstUs = 0;
  int _lastUs = 0;
  int _strokeCount = 0;
  Stroke? _lastStroke;
  final List<Stroke> _history = <Stroke>[];
  List<Stroke> _historyView = const <Stroke>[];

  /// Die Spur der aufsummierten Arbeit, aus der die Bestfenster kommen.
  ///
  /// Nur so lang wie das längste Fenster: was älter ist als eine Minute, kann
  /// zu keinem Fenster mehr beitragen, und ein Puffer, der eine Stunde lang
  /// mitwächst, ist ein Leck mit guten Absichten.
  final List<int> _trailTimeUs = <int>[];
  final List<double> _trailWorkJoule = <double>[];
  double? _best5;
  double? _best10;
  double? _best30;
  double? _best60;
  int _lastTrailUs = 0;

  /// Schreibt die Spur fort und prüft jedes Fenster gegen seinen Bestwert.
  ///
  /// Der Wert am Fensteranfang wird zwischen zwei Stützstellen interpoliert:
  /// sonst hinge die «beste Minute» davon ab, wo zufällig ein Abtastpunkt lag,
  /// und zwei Läufe derselben Einheit ergäben verschiedene Bestwerte.
  void _updateBestWindows(int nowUs) {
    const resolutionUs = 100000; // zehn Stützstellen je Sekunde
    if (_trailTimeUs.isEmpty || nowUs - _lastTrailUs >= resolutionUs) {
      _trailTimeUs.add(nowUs);
      _trailWorkJoule.add(_totalWorkJoule);
      _lastTrailUs = nowUs;
    } else {
      // Innerhalb derselben Stützstelle bleibt der jüngste Stand massgeblich.
      _trailTimeUs[_trailTimeUs.length - 1] = nowUs;
      _trailWorkJoule[_trailWorkJoule.length - 1] = _totalWorkJoule;
    }

    _best5 = _bestOver(const Duration(seconds: 5), _best5);
    _best10 = _bestOver(const Duration(seconds: 10), _best10);
    _best30 = _bestOver(const Duration(seconds: 30), _best30);
    _best60 = _bestOver(const Duration(minutes: 1), _best60);

    // Alles, was älter ist als das längste Fenster, wird nicht mehr gebraucht.
    final horizon = nowUs - const Duration(seconds: 70).inMicroseconds;
    if (_trailTimeUs.length > 64 && _trailTimeUs.first < horizon) {
      var drop = 0;
      while (drop < _trailTimeUs.length - 1 &&
          _trailTimeUs[drop + 1] < horizon) {
        drop++;
      }
      if (drop > 0) {
        _trailTimeUs.removeRange(0, drop);
        _trailWorkJoule.removeRange(0, drop);
      }
    }
  }

  double? _bestOver(Duration window, double? current) {
    final nowUs = _trailTimeUs.last;
    final targetUs = nowUs - window.inMicroseconds;
    if (_trailTimeUs.first > targetUs) return current; // noch zu kurz
    var index = 0;
    while (index + 1 < _trailTimeUs.length &&
        _trailTimeUs[index + 1] <= targetUs) {
      index++;
    }
    final startUs = _trailTimeUs[index];
    final startWork = _trailWorkJoule[index];
    double workAtTarget;
    if (index + 1 < _trailTimeUs.length && _trailTimeUs[index + 1] > startUs) {
      final span = _trailTimeUs[index + 1] - startUs;
      final share = (targetUs - startUs) / span;
      workAtTarget =
          startWork + (_trailWorkJoule[index + 1] - startWork) * share;
    } else {
      workAtTarget = startWork;
    }
    final seconds = window.inMicroseconds / Duration.microsecondsPerSecond;
    final power = (_trailWorkJoule.last - workAtTarget) / seconds;
    if (!power.isFinite || power < 0) return current;
    return current == null ? power : math.max(current, power);
  }

  /// Keep measured totals and completed strokes, but never integrate or
  /// interpolate a rolling best across a disconnected/restarted time segment.
  void breakContinuity() {
    _previous = null;
    _trailTimeUs.clear();
    _trailWorkJoule.clear();
    _lastTrailUs = 0;
  }

  LiveMetrics add(PairedSample sample, {Stroke? completedStroke}) {
    final previous = _previous;
    if (_firstUs == 0) _firstUs = sample.timeUs;
    if (previous != null) {
      final seconds =
          (sample.timeUs - previous.timeUs) / Duration.microsecondsPerSecond;
      if (seconds > 0 && seconds <= .25) {
        _totalWorkJoule +=
            (previous.powerWatt + sample.powerWatt) * seconds / 2;
      }
    }
    _previous = sample;
    _lastUs = sample.timeUs;
    if (completedStroke != null) {
      _strokeCount++;
      _lastStroke = completedStroke;
      _history.add(completedStroke);
      if (_history.length > strokeHistoryLength) _history.removeAt(0);
      // Rebuilt only here: between two strokes the screen receives the same
      // list instance a few hundred times.
      _historyView = List.unmodifiable(_history);
    }
    _updateBestWindows(sample.timeUs);
    final durationSeconds =
        (_lastUs - _firstUs) / Duration.microsecondsPerSecond;
    return LiveMetrics(
      powerWatt: sample.displayPowerWatt,
      leftPowerWatt: sample.left.displayPowerWatt,
      rightPowerWatt: sample.right.displayPowerWatt,
      averagePowerWatt: durationSeconds <= 0
          ? 0
          : _totalWorkJoule / durationSeconds,
      totalWorkJoule: _totalWorkJoule,
      elapsedSeconds: durationSeconds <= 0 ? 0 : durationSeconds,
      strokeCount: _strokeCount,
      lastStroke: _lastStroke,
      recentStrokes: _historyView,
      symmetryIndex: sample.symmetryIndex,
      best: BestPowers(
        fiveSeconds: _best5,
        tenSeconds: _best10,
        thirtySeconds: _best30,
        oneMinute: _best60,
      ),
    );
  }
}
