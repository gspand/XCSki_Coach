/// Eine gefahrene Einheit, aus ihren Zügen gerechnet.
///
/// Steht hier und nicht bei einem der Produkte, weil beide dieselbe Zahl
/// meinen müssen: Was der Athlet auf seiner Startseite als «192 W Ø» liest,
/// muss bei seiner Trainerin dieselbe Einheit mit derselben Zahl sein. Zwei
/// Rechenwege für denselben Wert sind ein Streit, der irgendwann in einem
/// Gespräch zwischen zwei Menschen landet.
library;

import '../core/models.dart';
import '../database/session_repository.dart';

/// Die vier Zahlen, die man nach einer Einheit ansieht.
class SessionRecap {
  const SessionRecap({
    required this.sessionId,
    required this.startedAtUtcUs,
    required this.duration,
    required this.averagePowerWatt,
    this.averageStrokePowerWatt,
    required this.strokeRatePerMinute,
    required this.symmetryPercent,
    this.classicLeftWorkPercent,
    this.classicLeftStrokeCount = 0,
    this.classicRightStrokeCount = 0,
    this.powerDeltaWatt,
    this.incomplete = false,
  });

  final String sessionId;
  final bool incomplete;
  final int startedAtUtcUs;
  final Duration duration;
  final double averagePowerWatt;

  /// Mittlere Leistung je Zug (während der aktiven Zugphasen).
  final double? averageStrokePowerWatt;

  /// Die Leistung, die eine Einheit beschreibt — **die im Zug**.
  ///
  /// [averagePowerWatt] teilt die Arbeit durch die ganze Einheit,
  /// Rückholphasen eingeschlossen: Wer dieselben Züge ruhiger wiederholt, hat
  /// nicht schwächer gezogen, aber diese Zahl faellt trotzdem. Sie taugt zur
  /// Beschreibung der Dichte einer Einheit und nicht zur Beschreibung einer
  /// Leistung. Darum liest jede Anzeige diesen Wert, und nur ersatzweise —
  /// wenn keine Züge gespeichert sind — die Leistung über die Gesamtzeit.
  double get shownPowerWatt => averageStrokePowerWatt ?? averagePowerWatt;
  final double strokeRatePerMinute;
  final double? symmetryPercent;
  final double? classicLeftWorkPercent;
  final int classicLeftStrokeCount;
  final int classicRightStrokeCount;

  bool get hasClassicStrokes =>
      classicLeftStrokeCount + classicRightStrokeCount > 0;

  /// Unterschied zur letzten **vergleichbaren** Einheit. Null, wenn es keine
  /// gibt; dann steht auch nichts da.
  final double? powerDeltaWatt;

  SessionRecap withDelta(double? delta) => SessionRecap(
    sessionId: sessionId,
    incomplete: incomplete,
    startedAtUtcUs: startedAtUtcUs,
    duration: duration,
    averagePowerWatt: averagePowerWatt,
    averageStrokePowerWatt: averageStrokePowerWatt,
    strokeRatePerMinute: strokeRatePerMinute,
    symmetryPercent: symmetryPercent,
    classicLeftWorkPercent: classicLeftWorkPercent,
    classicLeftStrokeCount: classicLeftStrokeCount,
    classicRightStrokeCount: classicRightStrokeCount,
    powerDeltaWatt: delta,
  );
}

/// Ob zwei Einheiten überhaupt nebeneinander gehören.
///
/// «Vergleichbar» heisst: höchstens ein Viertel kürzer oder länger. Ein Sprint
/// und eine Grundlageneinheit sagen nebeneinander nichts — und ein Vergleich,
/// der nichts sagt, sagt trotzdem etwas aus, wenn er auf dem Bildschirm steht.
bool comparable(SessionRecap a, SessionRecap b) {
  final longer = a.duration.inSeconds.clamp(1, 1 << 30);
  final ratio = b.duration.inSeconds / longer;
  return ratio >= 0.75 && ratio <= 1.33;
}

/// Liest Einheiten aus den gespeicherten Zügen.
class SessionRecapReader {
  const SessionRecapReader(this.sessions);
  final SessionRepository sessions;

  /// Die jüngsten [limit] Einheiten dieses Athleten, neueste zuerst.
  ///
  /// Begrenzt, weil die Züge jeder Einheit einzeln gelesen werden. Für eine
  /// Startseite reichen die letzten paar; wer die ganze Historie braucht,
  /// fragt danach.
  List<SessionRecap> recentOf(String athleteId, {int limit = 8}) {
    if (limit <= 0) return const [];
    final recaps = <SessionRecap>[];
    for (final summary in sessions.recentStrokeSessionsOfAthlete(
      athleteId,
      limit: limit,
    )) {
      final recap = of(summary);
      if (recap != null) recaps.add(recap);
    }
    return recaps;
  }

  /// Alle auswertbaren Einheiten dieses Athleten, neueste zuerst.
  List<SessionRecap> allOf(String athleteId) {
    final summaries = sessions.sessionsOfAthlete(athleteId).toList()
      ..sort((a, b) => b.startedAtUtcUs.compareTo(a.startedAtUtcUs));
    final recaps = <SessionRecap>[];
    for (final summary in summaries) {
      final recap = of(summary);
      if (recap != null) recaps.add(recap);
    }
    return recaps;
  }

  /// Eine Einheit. Null, wenn sie keine Züge hat — dann war sie keine.
  SessionRecap? of(SessionSummary summary) {
    final strokes = sessions.loadStrokes(summary.id);
    if (strokes.isEmpty) return null;

    final spanUs = strokes.last.endUs - strokes.first.startUs;
    if (spanUs <= 0) return null;
    final seconds = spanUs / Duration.microsecondsPerSecond;

    var work = 0.0;
    var left = 0.0;
    var right = 0.0;
    var classicLeftWork = 0.0;
    var classicRightWork = 0.0;
    var classicLeftStrokes = 0;
    var classicRightStrokes = 0;
    var activeStrokeSeconds = 0.0;
    for (final stroke in strokes) {
      work += stroke.workJoule;
      activeStrokeSeconds += stroke.durationSeconds;
      if (stroke.supportsSymmetry) {
        left += stroke.leftWorkJoule;
        right += stroke.rightWorkJoule;
      } else if (stroke.technique == StrokeTechnique.leftArm) {
        classicLeftWork += stroke.workJoule;
        classicLeftStrokes++;
      } else if (stroke.technique == StrokeTechnique.rightArm) {
        classicRightWork += stroke.workJoule;
        classicRightStrokes++;
      }
    }
    final total = left + right;
    final classicTotal = classicLeftWork + classicRightWork;

    return SessionRecap(
      sessionId: summary.id,
      incomplete: summary.recordingState != SessionRecordingState.completed,
      startedAtUtcUs: summary.startedAtUtcUs,
      duration: Duration(seconds: seconds.round()),
      // Mittlere Leistung über die ganze Einheit, Rückholphasen eingeschlossen
      // — das ist die Zahl, die eine Einheit beschreibt, nicht der Mittelwert
      // der Züge.
      averagePowerWatt: work / seconds,
      averageStrokePowerWatt: activeStrokeSeconds <= 0
          ? null
          : work / activeStrokeSeconds,
      strokeRatePerMinute: strokes.length / (seconds / 60),
      // Eine Seite mit negativer Arbeit ist ein Messfehler, keine Symmetrie.
      symmetryPercent: total <= 0 || left < 0 || right < 0
          ? null
          : 100 * (1 - (left - right).abs() / total),
      classicLeftWorkPercent: classicTotal <= 0
          ? null
          : 100 * classicLeftWork / classicTotal,
      classicLeftStrokeCount: classicLeftStrokes,
      classicRightStrokeCount: classicRightStrokes,
    );
  }
}

/// Setzt in die neueste Einheit den Unterschied zur letzten vergleichbaren.
List<SessionRecap> withComparison(List<SessionRecap> recaps) {
  return withComparablePredecessors(recaps);
}

/// Vergleicht jede Einheit mit der nächstälteren vergleichbaren Einheit.
///
/// Die Reihenfolge bleibt neueste zuerst. Ohne passenden Vorgänger bleibt der
/// Delta-Wert null, statt einen sportlich unbrauchbaren Vergleich zu erfinden.
List<SessionRecap> withComparablePredecessors(List<SessionRecap> recaps) {
  if (recaps.length < 2) return recaps;
  return [
    for (var index = 0; index < recaps.length; index++)
      _withComparablePredecessor(recaps, index),
  ];
}

SessionRecap _withComparablePredecessor(List<SessionRecap> recaps, int index) {
  final current = recaps[index];
  for (final earlier in recaps.skip(index + 1)) {
    if (comparable(current, earlier)) {
      // Dieselbe Groesse wie die angezeigte Zahl: ein Delta, das etwas
      // anderes vergleicht als das, was darueber steht, ist eine Falle.
      return current.withDelta(current.shownPowerWatt - earlier.shownPowerWatt);
    }
  }
  return current;
}
