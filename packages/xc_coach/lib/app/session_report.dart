/// Was über eine gefahrene Einheit gesagt werden kann — aus dem Archiv.
///
/// ## Warum das aus der Datenbank kommt und nicht aus dem Speicher
///
/// Weil die Zusammenfassung direkt nach dem Training und dieselbe Einheit drei
/// Wochen später im Verlauf **dieselben Zahlen** zeigen müssen. Entstünde die
/// eine aus dem, was der Bildschirm noch weiss, und die andere aus
/// gespeicherten Zügen, gäbe es zwei Rechenwege für eine Aussage — und der
/// Unterschied fiele erst auf, wenn ihn jemand bemerkt.
///
/// Deshalb gibt es hier genau einen Weg: Sitzungszeile plus gespeicherte Züge.
/// Der Bildschirm nach dem Stop liest ihn wie jeder andere.
///
/// ## Ein Rechenweg je Kennzahl
///
/// Züge kommen aus [SessionRecap] und
/// [stroke_analytics.dart](../metrics/stroke_analytics.dart), Herzfrequenz aus
/// [heart_rate_analytics.dart](../metrics/heart_rate_analytics.dart). Der
/// Bildschirm berechnet keine eigene Variante: direkt nach dem Stop und beim
/// späteren Öffnen im Archiv gilt derselbe geprüfte Weg.
library;

import '../core/models.dart';
import '../core/raw_device_frame.dart';
import '../core/stroke_metrics.dart';
import '../database/session_repository.dart';
import '../domain/platform.dart';
import '../metrics/heart_rate_analytics.dart';
import '../metrics/machine_work.dart';
import '../metrics/session_complete_analysis.dart';
import '../metrics/stroke_analytics.dart';
import '../metrics/virtual_ski_track.dart';
import '../training/workout_recorder.dart';
import '../workout_engine/workout_engine.dart';
import 'session_recap.dart';

/// Eine Einheit, wie sie im Archiv steht.
class SessionReport {
  const SessionReport({
    required this.session,
    required this.strokes,
    required this.recap,
    required this.workJoule,
    this.peakPowerWatt,
    this.sidePower,
    this.workPerStroke,
    this.fatiguePercent,
    this.powerVariationPercent,
    this.heartRate,
    this.intervals = const [],
    this.trackDistanceMetres,
    this.machineWork,
    this.precomputedAnalysis,
  });

  final SessionSummary session;

  /// Die gespeicherten Züge. Der Bildschirm zeichnet daraus seine Verläufe;
  /// nichts davon wird zusätzlich abgelegt.
  final List<Stroke> strokes;

  /// Die geteilte Auswertung — dieselbe, die Startseite und Trainerliste
  /// benutzen.
  final SessionRecap? recap;

  /// Mittlere Zugleistung (während der aktiven Züge).
  double? get averageStrokePowerWatt {
    final fromRecap = recap?.averageStrokePowerWatt;
    if (fromRecap != null) return fromRecap;
    final seconds = strokes.fold<double>(
      0,
      (sum, stroke) => sum + stroke.durationSeconds,
    );
    if (seconds <= 0) return null;
    return strokes.fold<double>(0, (sum, stroke) => sum + stroke.workJoule) /
        seconds;
  }

  final double workJoule;
  final double? peakPowerWatt;

  /// Mittlere Leistung je Seite.
  final ({double left, double right})? sidePower;

  /// Arbeit je Zug, gesamt und je Seite.
  final ({double total, double left, double right})? workPerStroke;

  /// Leistungsabfall zwischen erstem und letztem Fünftel.
  final double? fatiguePercent;

  /// Streuung der Zugleistung.
  final double? powerVariationPercent;

  /// Herzfrequenz aus den archivierten Gurtwerten. Null bedeutet: keine
  /// belastbare HF aufgezeichnet, nicht null bpm.
  final HeartRateAnalysis? heartRate;

  /// Beidseitige, gespeicherte Zugkurven. Alte Einheiten können Züge ohne diese
  /// Detaildaten enthalten; sie werden nicht durch eine Modellkurve ersetzt.
  List<StrokeSides> get strokeSides => <StrokeSides>[
    for (final stroke in strokes) ?stroke.sides,
  ];

  /// Die Abschnitte, falls eine strukturierte Einheit gefahren wurde.
  ///
  /// Leer bei freiem Training — und das ist kein Mangel, sondern die richtige
  /// Aussage: Wer ohne Vorgabe fährt, hat keine Abschnitte.
  final List<RecordedInterval> intervals;

  bool get hasIntervals => intervals.isNotEmpty;

  /// Distanz auf der virtuellen Loipe, null bei Einheiten ohne Loipe.
  final double? trackDistanceMetres;

  /// Maschinenleistungsmodell V1 der Sensoren, null ohne dessen Datensätze
  /// (Firmware vor 0.22.30).
  final MachineWorkLedger? machineWork;

  final CompleteSessionAnalysis? precomputedAnalysis;

  /// Zug-fuer-Zug-Verlauf, Ermuedungsfenster und Leistungsprofile. Ein aus
  /// dem Archiv gelesener Bericht berechnet sie genau einmal. Direkt gebaute
  /// Berichte (beispielsweise Widget-Tests) nutzen denselben Rechenweg bei
  /// Bedarf.
  CompleteSessionAnalysis get completeAnalysis =>
      precomputedAnalysis ??
      analyzeCompleteSession(strokes, heartRate: heartRate);

  /// Mittleres Tempo auf der Loipe über die aktive Zeit.
  double? get trackSpeedMetresPerSecond {
    final distance = trackDistanceMetres;
    final seconds = activeTime.inMicroseconds / Duration.microsecondsPerSecond;
    if (distance == null || seconds <= 0) return null;
    return distance / seconds;
  }

  /// Wie viele Belastungsabschnitte im Zielbereich lagen — null, wenn es
  /// keine Vorgaben gab.
  ({int hit, int total})? get targetHits {
    final rated = [
      for (final interval in intervals)
        if (interval.kind == WorkoutStepKind.work &&
            interval.withinTarget != null)
          interval,
    ];
    if (rated.isEmpty) return null;
    return (
      hit: rated.where((interval) => interval.withinTarget!).length,
      total: rated.length,
    );
  }

  Duration get wallTime => session.wallTime;
  Duration get activeTime => session.activeTime;
  Duration get pausedTime => Duration(microseconds: session.pausedUs);

  int get strokeCount => strokes.length;

  /// Ob überhaupt etwas gemessen wurde. Eine Einheit ohne Züge ist eine
  /// Zeitangabe, keine Trainingsaussage.
  bool get hasStrokes => strokes.isNotEmpty;

  /// Der Anteil der linken Seite an der Arbeit, 0 bis 1.
  ///
  /// Null, wenn eine Seite negative Arbeit meldet: Das ist ein Messfehler
  /// (Seite nicht erfasst, Energiebilanz ohne Antrieb), kein Anteil — sonst
  /// entstünden 107 % links und −7 % rechts.
  double? get leftShare {
    final work = workPerStroke;
    if (work == null || work.total <= 0) return null;
    if (work.left < 0 || work.right < 0) return null;
    final share = work.left / work.total;
    return share.isFinite && share >= 0 && share <= 1 ? share : null;
  }
}

/// Liest eine Einheit aus dem Archiv.
class SessionReportReader {
  const SessionReportReader(this.sessions, {this.machineWork});

  final SessionRepository sessions;

  /// Liest die Maschinenarbeit (0x1205) aus den gespeicherten Rohframes. Nur
  /// ein Produkt mit Geräteprotokoll hat sie; ohne bleibt der Abschnitt leer.
  final MachineWorkLedger Function(Iterable<RawDeviceFrame> frames)?
  machineWork;

  /// Derselbe Leser, der die Maschinenarbeit mitliest.
  SessionReportReader withMachineWork(
    MachineWorkLedger Function(Iterable<RawDeviceFrame> frames) decode,
  ) => SessionReportReader(sessions, machineWork: decode);

  /// Die Einheit, oder null, wenn es sie nicht gibt.
  SessionReport? of(String sessionId) {
    final session = sessions.sessionById(sessionId);
    if (session == null) return null;

    final strokes = sessions.loadStrokes(sessionId);
    final heartRates = sessions.loadHeartRates(sessionId);
    final events = sessions.loadEvents(sessionId);
    final work = strokes.isEmpty
        ? 0.0
        : strokes.map((s) => s.workJoule).reduce((a, b) => a + b);
    final trackSetup = VirtualTrackSetup.decode(
      events
          .where((event) => event.kind == virtualTrackEventKind)
          .firstOrNull
          ?.detail,
    );

    final machine = machineWork?.call(
      sessions.loadMachineStrokeFrames(sessionId),
    );
    final athleteId = session.athleteId;
    final maximumHeartRate = athleteId == null
        ? null
        : sessions.platform
              .attributeAt(
                athleteId: athleteId,
                attribute: AthleteAttribute.maxHeartRateBpm,
                asOfUtcUs: session.endedAtUtcUs ?? session.startedAtUtcUs,
              )
              ?.round();
    final heartRate = analyzeHeartRate(
      heartRates,
      sessionStartUtcUs: session.startedAtUtcUs,
      sessionEndUtcUs: session.endedAtUtcUs ?? session.startedAtUtcUs,
      profileMaximumBpm: maximumHeartRate,
    );
    final clockEvent = events
        .where(
          (event) =>
              event.kind == 'stroke_clock_anchor' &&
              event.occurredAtMonotonicUs != null,
        )
        .firstOrNull;
    final clockAnchor = clockEvent == null
        ? null
        : StrokeClockAnchor(
            monotonicUs: clockEvent.occurredAtMonotonicUs!,
            utcUs: clockEvent.occurredAtUtcUs,
          );
    final completeAnalysis = analyzeCompleteSession(
      strokes,
      heartRate: heartRate,
      clockAnchor: clockAnchor,
    );
    final intervals = <RecordedInterval>[];
    for (final stored in sessions.loadIntervals(sessionId)) {
      var interval = RecordedInterval.fromJson(
        ordinal: stored.ordinal,
        startedAtUs: stored.startedAtUs,
        endedAtUs: stored.endedAtUs,
        duration: Duration(
          microseconds:
              (stored.endedAtUs ?? stored.startedAtUs) - stored.startedAtUs,
        ),
        json: stored.metricsJson,
      );
      final first = interval.firstStrokeOrdinal;
      final last = interval.lastStrokeOrdinal;
      if (first != null &&
          last != null &&
          first >= 0 &&
          last < strokes.length) {
        interval = interval.withExactStrokes(strokes.sublist(first, last + 1));
      }
      intervals.add(interval);
    }

    return SessionReport(
      session: session,
      strokes: strokes,
      machineWork: machine == null || machine.isEmpty ? null : machine,
      recap: SessionRecapReader(sessions).of(session),
      workJoule: work,
      peakPowerWatt: peakPower(strokes),
      sidePower: sidePower(strokes),
      workPerStroke: workPerStroke(strokes),
      fatiguePercent:
          completeAnalysis.fatigue?.powerDeltaPercent ??
          fatiguePercent(strokes),
      powerVariationPercent: powerVariationPercent(strokes),
      heartRate: heartRate,
      trackDistanceMetres: trackSetup == null
          ? null
          : VirtualSkiTrack.replay(trackSetup, strokes).distanceMetres,
      intervals: List<RecordedInterval>.unmodifiable(intervals),
      precomputedAnalysis: completeAnalysis,
    );
  }
}
