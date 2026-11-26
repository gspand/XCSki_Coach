/// Langzeitprofil aus den vollstaendig gespeicherten Ercolina-Zuegen.
///
/// Zeitfenster werden nur mit demselben Zeitfenster verglichen und
/// Zugfenster nur mit derselben Zugzahl. Damit wird keine lockere Stunde
/// gegen einen Fuenf-Minuten-All-out-Test als pauschaler Sessionmittelwert
/// ausgespielt.
library;

import '../database/session_repository.dart';
import '../metrics/session_complete_analysis.dart';
import 'training_profiles.dart' show comparablePowerSinceUtcUs;

class HistoricalPowerDurationBest {
  const HistoricalPowerDurationBest({
    required this.sessionId,
    required this.achievedAt,
    required this.best,
    this.fatigueDeltaPercent,
  });

  final String sessionId;
  final DateTime achievedAt;
  final PowerDurationBest best;
  final double? fatigueDeltaPercent;
}

class HistoricalStrokeCountBest {
  const HistoricalStrokeCountBest({
    required this.sessionId,
    required this.achievedAt,
    required this.best,
  });

  final String sessionId;
  final DateTime achievedAt;
  final StrokeCountBest best;
}

class AthleteErcolinaProfile {
  const AthleteErcolinaProfile({
    required this.sessionCount,
    required this.powerBests,
    required this.strokeBests,
    required this.powerHistory,
    this.firstSessionAt,
    this.lastSessionAt,
  });

  final int sessionCount;
  final DateTime? firstSessionAt;
  final DateTime? lastSessionAt;
  final List<HistoricalPowerDurationBest> powerBests;
  final List<HistoricalStrokeCountBest> strokeBests;

  /// Alle belegten Session-Bestwerte je Dauer, chronologisch. Damit bleibt
  /// eine Entwicklung ueber Monate sichtbar, nicht nur der Rekord.
  final Map<Duration, List<HistoricalPowerDurationBest>> powerHistory;

  bool get isEmpty => sessionCount == 0;
}

class AthleteErcolinaProfileReader {
  const AthleteErcolinaProfileReader(this.sessions);

  final SessionRepository sessions;

  AthleteErcolinaProfile of(String athleteId) {
    final summaries = sessions.sessionsOfAthlete(athleteId);
    final powerHistory = <Duration, List<HistoricalPowerDurationBest>>{};
    final strokeBests = <int, HistoricalStrokeCountBest>{};
    var evaluated = 0;
    DateTime? first;
    DateTime? last;

    for (final session in summaries) {
      if (session.recordingState != SessionRecordingState.completed ||
          session.startedAtUtcUs < comparablePowerSinceUtcUs) {
        continue;
      }
      final strokes = sessions.loadStrokes(session.id);
      if (strokes.isEmpty) continue;
      final analysis = analyzeCompleteSession(strokes);
      if (analysis.timeline.isEmpty) continue;
      evaluated++;
      final achievedAt = DateTime.fromMicrosecondsSinceEpoch(
        session.startedAtUtcUs,
        isUtc: true,
      );
      if (first == null || achievedAt.isBefore(first)) first = achievedAt;
      if (last == null || achievedAt.isAfter(last)) last = achievedAt;

      for (final best in analysis.powerDuration) {
        powerHistory
            .putIfAbsent(best.duration, () => <HistoricalPowerDurationBest>[])
            .add(
              HistoricalPowerDurationBest(
                sessionId: session.id,
                achievedAt: achievedAt,
                best: best,
                fatigueDeltaPercent: analysis.fatigue?.powerDeltaPercent,
              ),
            );
      }
      for (final best in analysis.strokeCountBests) {
        final candidate = HistoricalStrokeCountBest(
          sessionId: session.id,
          achievedAt: achievedAt,
          best: best,
        );
        final current = strokeBests[best.strokeCount];
        if (current == null ||
            best.activePowerWatt > current.best.activePowerWatt) {
          strokeBests[best.strokeCount] = candidate;
        }
      }
    }

    for (final values in powerHistory.values) {
      values.sort((a, b) => a.achievedAt.compareTo(b.achievedAt));
    }
    final powerBests = <HistoricalPowerDurationBest>[
      for (final duration in completePowerDurationWindows)
        if (powerHistory[duration] case final values?)
          values.reduce(
            (a, b) =>
                a.best.averagePowerWatt >= b.best.averagePowerWatt ? a : b,
          ),
    ];
    final orderedStrokeBests = <HistoricalStrokeCountBest>[
      for (final count in completeStrokeCountWindows) ?strokeBests[count],
    ];
    return AthleteErcolinaProfile(
      sessionCount: evaluated,
      firstSessionAt: first,
      lastSessionAt: last,
      powerBests: List.unmodifiable(powerBests),
      strokeBests: List.unmodifiable(orderedStrokeBests),
      powerHistory:
          Map.unmodifiable(<Duration, List<HistoricalPowerDurationBest>>{
            for (final entry in powerHistory.entries)
              entry.key: List.unmodifiable(entry.value),
          }),
    );
  }
}
