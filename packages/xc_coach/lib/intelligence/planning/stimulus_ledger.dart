/// Welche Reize die absolvierten Einheiten tatsächlich gesetzt haben.
///
/// Eingeordnet wird mit dem, was LaLa für **dieselbe** Sportart gespeichert
/// hat, in dieser Reihenfolge:
///
/// 1. Zonenmodell REG–SB, Intervall für Intervall über Leistung bzw.
///    Geschwindigkeit,
/// 2. nur LTP1/LTP2: grob in drei Domänen (unter LTP1, dazwischen, darüber),
/// 3. Herzfrequenzgrenzen des Zonenmodells über den Mittelwert der Einheit,
/// 4. der Reiz der geplanten Einheit, die damit erfüllt wurde,
/// 5. sonst nicht eingeordnet – gezählt wird dann nur die Dauer.
///
/// Hier wird keine Schwelle und keine Zonengrenze berechnet.
library;

import '../../domain/diagnostic_catalogue.dart';
import '../models.dart';
import 'planning_models.dart';

enum DoseSource { zones, thresholds, heartRate, plan, none }

/// Die Reize einer absolvierten Einheit.
class SessionStimulusDose {
  const SessionStimulusDose({
    required this.sessionId,
    required this.startedAtUtcUs,
    required this.sportKey,
    required this.durationSeconds,
    required this.seconds,
    required this.unclassifiedSeconds,
    required this.source,
    required this.hard,
    required this.long,
    this.testId,
    this.rpe,
    this.peakLactate,
  });

  final String sessionId;
  final int startedAtUtcUs;
  final String sportKey;
  final int durationSeconds;
  final Map<TrainingStimulus, int> seconds;
  final int unclassifiedSeconds;
  final DoseSource source;

  /// Intensiver Reiz oder hohes Belastungsempfinden.
  final bool hard;

  /// Lange, überwiegend lockere Einheit.
  final bool long;
  final String? testId;
  final double? rpe;

  /// Höchster Laktatwert, der während der Einheit gemessen wurde.
  final double? peakLactate;

  int of(TrainingStimulus stimulus) =>
      stimulus == TrainingStimulus.longEndurance
      ? (long ? durationSeconds : 0)
      : seconds[stimulus] ?? 0;
}

class StimulusLedger {
  StimulusLedger._(this.doses, this.nowUtcUs, this.policy);

  /// [plannedStimulusBySession]: Reiz der geplanten Einheit, die eine Session
  /// erfüllt hat – nur genutzt, wenn die Messung selbst nichts einordnet.
  factory StimulusLedger.build({
    required List<IntelligenceSession> sessions,
    required List<IntelligenceTest> tests,
    required int nowUtcUs,
    PlanningPolicy policy = const PlanningPolicy(),
    Map<String, TrainingStimulus> plannedStimulusBySession = const {},
    List<IntelligenceObservation> observations = const [],
  }) {
    final lactate = <String, double>{};
    for (final item in observations) {
      final sessionId = item.sessionId;
      final value = item.value;
      if (!item.usable ||
          item.type != IntelligenceObservationType.lactate ||
          sessionId == null ||
          value == null) {
        continue;
      }
      if (value > (lactate[sessionId] ?? 0)) lactate[sessionId] = value;
    }
    final doses = [
      for (final session in sessions)
        if (session.completed &&
            session.startedAtUtcUs <= nowUtcUs &&
            session.durationSeconds >= policy.minSessionSeconds)
          _classify(
            session,
            _testFor(session, tests),
            plannedStimulusBySession[session.id],
            lactate[session.id],
            policy,
          ),
    ]..sort((a, b) => b.startedAtUtcUs.compareTo(a.startedAtUtcUs));
    return StimulusLedger._(List.unmodifiable(doses), nowUtcUs, policy);
  }

  /// Neueste zuerst.
  final List<SessionStimulusDose> doses;
  final int nowUtcUs;
  final PlanningPolicy policy;

  Iterable<SessionStimulusDose> within(int days) => doses.where(
    (dose) =>
        dose.startedAtUtcUs >= nowUtcUs - days * Duration.microsecondsPerDay,
  );

  int secondsIn(TrainingStimulus stimulus, int days) =>
      within(days).fold(0, (sum, dose) => sum + dose.of(stimulus));

  int durationSeconds(int days) =>
      within(days).fold(0, (sum, dose) => sum + dose.durationSeconds);

  /// Mittlere Woche der drei Wochen vor den letzten sieben Tagen.
  double get referenceWeekSeconds =>
      (durationSeconds(28) - durationSeconds(7)) / 3;

  /// Längste Einheit derselben Sportart; null ohne Verlauf.
  int? longestSeconds(String sportKey, int days) {
    int? longest;
    for (final dose in within(days)) {
      if (dose.sportKey != sportKey) continue;
      if (longest == null || dose.durationSeconds > longest) {
        longest = dose.durationSeconds;
      }
    }
    return longest;
  }

  /// Anteil der Trainingszeit, die sich keinem Reiz zuordnen liess.
  double unclassifiedShare(int days) {
    final total = durationSeconds(days);
    if (total == 0) return 0;
    return within(days)
            .where((dose) => dose.source == DoseSource.none)
            .fold(0, (sum, dose) => sum + dose.durationSeconds) /
        total;
  }

  /// Die letzte Einheit, die diesen Reiz wirksam gesetzt hat.
  SessionStimulusDose? lastMeaningful(TrainingStimulus stimulus) {
    final minimum = policy.meaningfulSeconds[stimulus] ?? 1;
    for (final dose in doses) {
      if (dose.of(stimulus) >= minimum) return dose;
    }
    return null;
  }

  double? daysSince(TrainingStimulus stimulus) {
    final last = lastMeaningful(stimulus);
    return last == null
        ? null
        : (nowUtcUs - last.startedAtUtcUs) / Duration.microsecondsPerDay;
  }

  SessionStimulusDose? get lastHard =>
      doses.where((dose) => dose.hard).firstOrNull;

  double? get hoursSinceHard {
    final last = lastHard;
    return last == null
        ? null
        : (nowUtcUs - last.startedAtUtcUs) / Duration.microsecondsPerHour;
  }

  static IntelligenceTest? _testFor(
    IntelligenceSession session,
    List<IntelligenceTest> tests,
  ) {
    final sport = sessionSportKey(session.sport);
    IntelligenceTest? before;
    IntelligenceTest? after;
    for (final test in tests) {
      if (test.sportKey != sport) continue;
      if (test.startedAtUtcUs <= session.startedAtUtcUs) {
        if (before == null || test.startedAtUtcUs > before.startedAtUtcUs) {
          before = test;
        }
      } else if (after == null || test.startedAtUtcUs < after.startedAtUtcUs) {
        after = test;
      }
    }
    return before ?? after;
  }

  static SessionStimulusDose _classify(
    IntelligenceSession session,
    IntelligenceTest? test,
    TrainingStimulus? planned,
    double? peakLactate,
    PlanningPolicy policy,
  ) {
    final seconds = <TrainingStimulus, int>{};
    void add(TrainingStimulus stimulus, int value) =>
        seconds.update(stimulus, (old) => old + value, ifAbsent: () => value);
    var source = DoseSource.none;
    final zones = test == null ? const <IntelligenceZone>[] : _zoneSet(test);
    final lt1 = test?.threshold('lt1');
    final lt2 = test?.threshold('lt2');

    for (final interval in session.intervals) {
      if (interval.durationSeconds <= 0) continue;
      if (zones.isNotEmpty) {
        final load = _load(interval, zones.first.loadUnit);
        final zone = load == null
            ? null
            : zones
                  .where(
                    (zone) =>
                        (zone.lowerLoad == null || load >= zone.lowerLoad!) &&
                        (zone.upperLoad == null || load < zone.upperLoad!),
                  )
                  .firstOrNull;
        if (zone != null) {
          add(
            _ofZone(zone.code, interval.durationSeconds, policy),
            interval.durationSeconds,
          );
          source = DoseSource.zones;
          continue;
        }
      }
      if (lt1?.load != null && lt2?.load != null) {
        final load = _load(interval, lt2!.loadUnit);
        if (load == null) continue;
        add(
          load < lt1!.load!
              ? TrainingStimulus.aerobicBase
              : load < lt2.load!
              ? TrainingStimulus.aerobicCapacity
              : interval.durationSeconds <= policy.speedMaxIntervalSeconds
              ? TrainingStimulus.speed
              : TrainingStimulus.vo2max,
          interval.durationSeconds,
        );
        if (source == DoseSource.none) source = DoseSource.thresholds;
      }
    }

    if (seconds.isEmpty && session.averageHeartRateBpm != null) {
      final heartRate = session.averageHeartRateBpm!;
      final zone = zones
          .where(
            (zone) =>
                (zone.lowerHeartRateBpm != null ||
                    zone.upperHeartRateBpm != null) &&
                (zone.lowerHeartRateBpm == null ||
                    heartRate >= zone.lowerHeartRateBpm!) &&
                (zone.upperHeartRateBpm == null ||
                    heartRate < zone.upperHeartRateBpm!),
          )
          .firstOrNull;
      if (zone != null) {
        add(
          _ofZone(zone.code, session.durationSeconds, policy),
          session.durationSeconds,
        );
        source = DoseSource.heartRate;
      }
    }

    if (seconds.isEmpty && planned != null) {
      add(
        planned == TrainingStimulus.longEndurance
            ? TrainingStimulus.aerobicBase
            : planned,
        session.durationSeconds,
      );
      source = DoseSource.plan;
    }

    final classified = seconds.values.fold(0, (sum, value) => sum + value);
    final unclassified = (session.durationSeconds - classified).clamp(
      0,
      session.durationSeconds,
    );
    final intensive = seconds.entries
        .where((entry) => entry.key.intensive)
        .fold(0, (sum, entry) => sum + entry.value);
    final easy =
        (seconds[TrainingStimulus.regeneration] ?? 0) +
        (seconds[TrainingStimulus.aerobicBase] ?? 0);
    final rpe = session.rpe;
    final long =
        session.durationSeconds >= policy.longSessionSeconds &&
        (classified > 0 ? easy >= 0.7 * classified : rpe == null || rpe <= 6);
    return SessionStimulusDose(
      sessionId: session.id,
      startedAtUtcUs: session.startedAtUtcUs,
      sportKey: sessionSportKey(session.sport),
      durationSeconds: session.durationSeconds,
      seconds: Map.unmodifiable(seconds),
      unclassifiedSeconds: unclassified,
      source: source,
      hard:
          intensive >= policy.hardMinSeconds ||
          (seconds[TrainingStimulus.speed] ?? 0) >=
              policy.meaningfulSeconds[TrainingStimulus.speed]! ||
          rpe != null && rpe >= policy.hardRpe ||
          peakLactate != null && peakLactate >= policy.hardLactateMmol,
      long: long,
      testId: test?.id,
      rpe: rpe,
      peakLactate: peakLactate,
    );
  }

  /// Das REG–SB-Modell des Tests, sonst nichts: Andere Modelle (drei, fünf
  /// oder sieben Zonen) lassen sich nicht eindeutig auf die Reize abbilden.
  static List<IntelligenceZone> _zoneSet(IntelligenceTest test) {
    const codes = {'REG', 'GAL', 'GA1', 'GA2', 'EB', 'SB'};
    final byModel = <String, List<IntelligenceZone>>{};
    for (final zone in test.zones) {
      if (!codes.contains(zone.code)) continue;
      byModel.putIfAbsent(zone.modelId, () => []).add(zone);
    }
    return byModel['threshold-anchored-reg-sb'] ??
        byModel.values.firstOrNull ??
        const [];
  }

  static TrainingStimulus _ofZone(
    String code,
    int durationSeconds,
    PlanningPolicy policy,
  ) => switch (code) {
    'REG' => TrainingStimulus.regeneration,
    'GAL' || 'GA1' => TrainingStimulus.aerobicBase,
    'GA2' => TrainingStimulus.aerobicCapacity,
    'EB' => TrainingStimulus.threshold,
    _ =>
      durationSeconds <= policy.speedMaxIntervalSeconds
          ? TrainingStimulus.speed
          : TrainingStimulus.vo2max,
  };

  static double? _load(IntelligenceInterval interval, String unit) =>
      switch (unit.trim().toLowerCase()) {
        'w' => interval.averagePowerWatt,
        'km/h' => interval.averageSpeedKmh,
        _ => null,
      };
}
