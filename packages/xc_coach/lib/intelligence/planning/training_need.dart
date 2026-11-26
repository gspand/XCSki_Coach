/// Was der Athlet heute braucht – und was er heute verträgt.
///
/// Drei Schritte, jeder mit benannten Fakten:
///
/// 1. [IndividualProfile]: was die Diagnostik über den Engpass sagt
///    (LTP1/LTP2 derselben Sportart, Alter des Tests).
/// 2. [ReadinessGate]: ob heute ein intensiver Reiz vertretbar ist
///    (Abstand zum letzten harten Reiz, Belastungssprung, Leistung je
///    Herzschlag, Belastungsempfinden).
/// 3. [TrainingNeedEngine]: welcher Reiz fällig ist – aus Phase, Profil und
///    dem, was die letzten Wochen tatsächlich gesetzt haben.
library;

import 'dart:math' as math;

import '../../domain/coach_decision.dart';
import '../../domain/diagnostic_catalogue.dart';
import '../models.dart';
import 'planning_models.dart';
import 'stimulus_ledger.dart';

/// Ein Grund mit den Fakten, auf die er sich stützt.
class PlanningReason {
  const PlanningReason(this.text, [this.facts = const []]);

  final String text;
  final List<CoachFactRef> facts;
}

String _fmt(num value, [int digits = 0]) => value.toStringAsFixed(digits);

/// Was die Diagnostik über diesen Menschen sagt, soweit sie es sagt.
class IndividualProfile {
  const IndividualProfile({
    this.sportKey,
    this.testId,
    this.testAgeDays,
    this.baseRatio,
    this.weights = const {},
    this.reasons = const [],
    this.testDue,
  });

  /// Neuester Test der Zielsportart, sonst der neueste überhaupt.
  factory IndividualProfile.fromTests({
    required List<IntelligenceTest> tests,
    required int nowUtcUs,
    TrainingGoal? goal,
    PlanningPolicy policy = const PlanningPolicy(),
  }) {
    IntelligenceTest? newest(bool Function(IntelligenceTest) where) {
      IntelligenceTest? best;
      for (final test in tests) {
        if (test.startedAtUtcUs > nowUtcUs || !where(test)) continue;
        if (test.threshold('lt1') == null || test.threshold('lt2') == null) {
          continue;
        }
        if (best == null || test.startedAtUtcUs > best.startedAtUtcUs) {
          best = test;
        }
      }
      return best;
    }

    final goalSport = goal?.modality.sportKey;
    final test =
        (goalSport == null
            ? null
            : newest((test) => test.sportKey == goalSport)) ??
        newest((_) => true);
    final stale =
        test != null &&
        nowUtcUs - test.startedAtUtcUs >
            policy.profileMaxAgeDays * Duration.microsecondsPerDay;
    if (test == null || stale) {
      final when = test == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(test.startedAtUtcUs);
      final label = test == null
          ? null
          : DiagnosticSport.values
                    .where((item) => item.storageKey == test.sportKey)
                    .firstOrNull
                    ?.label ??
                test.sportKey;
      return IndividualProfile(
        reasons: [
          PlanningReason(
            when == null
                ? 'Keine Diagnostik mit LTP1 und LTP2: Die Reize werden nach '
                      'Phase und Verlauf gewichtet, nicht nach einem gemessenen '
                      'Engpass.'
                : 'Die letzte Diagnostik ($label, ${when.month}/${when.year}) '
                      'ist zu alt, um heute den Engpass zu bestimmen.',
            [
              if (test != null)
                CoachFactRef(kind: 'test', id: test.id, label: 'Diagnostik'),
            ],
          ),
        ],
        testDue: goalSport ?? test?.sportKey,
      );
    }
    final lt1 = test.threshold('lt1')!;
    final lt2 = test.threshold('lt2')!;
    final ratio = lt1.load! / lt2.load!;
    final age = (nowUtcUs - test.startedAtUtcUs) / Duration.microsecondsPerDay;
    final sport =
        DiagnosticSport.values
            .where((item) => item.storageKey == test.sportKey)
            .firstOrNull
            ?.label ??
        test.sportKey;
    final facts = [
      CoachFactRef(
        kind: 'test',
        id: test.id,
        label: 'LTP1/LTP2 $sport',
        value: double.parse(ratio.toStringAsFixed(3)),
      ),
    ];
    final weights = <TrainingStimulus, double>{};
    final reasons = <PlanningReason>[];
    final percent = _fmt(ratio * 100);
    if (ratio < policy.weakBaseRatio) {
      weights
        ..[TrainingStimulus.aerobicBase] = 1.25
        ..[TrainingStimulus.longEndurance] = 1.25
        ..[TrainingStimulus.vo2max] = 0.7;
      reasons.add(
        PlanningReason(
          'LTP1 liegt bei $percent % von LTP2 ($sport): Die aerobe Basis ist '
          'der Engpass, Grundlagenreize wiegen mehr.',
          facts,
        ),
      );
    } else if (ratio > policy.strongBaseRatio) {
      weights
        ..[TrainingStimulus.aerobicBase] = 0.9
        ..[TrainingStimulus.threshold] = 1.15
        ..[TrainingStimulus.vo2max] = 1.2;
      reasons.add(
        PlanningReason(
          'LTP1 liegt bei $percent % von LTP2 ($sport): Die Basis ist gut '
          'entwickelt, Schwellen- und VO2max-Reize wiegen mehr.',
          facts,
        ),
      );
    } else {
      reasons.add(
        PlanningReason(
          'LTP1 liegt bei $percent % von LTP2 ($sport): kein ausgeprägter '
          'Engpass zwischen Basis und Schwelle.',
          facts,
        ),
      );
    }
    final dated = age > policy.testMaxAgeDays;
    final wrongSport = goalSport != null && test.sportKey != goalSport;
    if (dated) {
      reasons.add(
        PlanningReason(
          'Die Diagnostik ist ${age.round()} Tage alt: Ein neuer Stufentest '
          'würde die Bereiche schärfen.',
          facts,
        ),
      );
    }
    if (wrongSport) {
      reasons.add(
        PlanningReason(
          'Für die Wettkampfsportart liegt keine eigene Diagnostik vor; das '
          'Profil stammt aus $sport.',
          facts,
        ),
      );
    }
    return IndividualProfile(
      sportKey: test.sportKey,
      testId: test.id,
      testAgeDays: age,
      baseRatio: ratio,
      weights: Map.unmodifiable(weights),
      reasons: List.unmodifiable(reasons),
      testDue: dated || wrongSport ? goalSport ?? test.sportKey : null,
    );
  }

  final String? sportKey;
  final String? testId;
  final double? testAgeDays;
  final double? baseRatio;
  final Map<TrainingStimulus, double> weights;
  final List<PlanningReason> reasons;

  /// Sportart, für die ein neuer Test sinnvoll wäre.
  final String? testDue;

  double weight(TrainingStimulus stimulus) => weights[stimulus] ?? 1.0;
}

enum ReadinessLevel {
  /// Lange kein harter Reiz, keine Warnzeichen.
  fresh,
  normal,

  /// Kein intensiver Reiz heute.
  limited,

  /// Nur Regeneration.
  recovery,
}

class ReadinessAssessment {
  const ReadinessAssessment({
    required this.level,
    required this.reasons,
    this.missing = const [],
  });

  final ReadinessLevel level;
  final List<PlanningReason> reasons;
  final List<String> missing;

  bool allows(TrainingStimulus stimulus) => switch (level) {
    ReadinessLevel.recovery => stimulus == TrainingStimulus.regeneration,
    ReadinessLevel.limited => !stimulus.intensive,
    _ => true,
  };
}

/// Ob heute ein intensiver Reiz vertretbar ist. Fehlt eine Grösse, wird sie
/// als fehlend benannt, nicht geraten.
class ReadinessGate {
  const ReadinessGate({this.policy = const PlanningPolicy()});

  final PlanningPolicy policy;

  ReadinessAssessment assess({
    required StimulusLedger ledger,
    required List<IntelligenceSession> sessions,
    required List<IntelligenceObservation> observations,
    required int nowUtcUs,
  }) {
    final recovery = <PlanningReason>[];
    final limited = <PlanningReason>[];
    final missing = <String>[];
    const hourUs = Duration.microsecondsPerHour;
    final recent =
        sessions
            .where(
              (session) =>
                  session.completed &&
                  session.startedAtUtcUs <= nowUtcUs &&
                  nowUtcUs - session.startedAtUtcUs <= 48 * hourUs,
            )
            .toList()
          ..sort((a, b) => b.startedAtUtcUs.compareTo(a.startedAtUtcUs));

    final rpeObservation = observations
        .where(
          (item) =>
              item.usable &&
              item.type == IntelligenceObservationType.rpe &&
              item.value != null &&
              item.observedAtUtcUs <= nowUtcUs &&
              nowUtcUs - item.observedAtUtcUs <= 48 * hourUs,
        )
        .fold<IntelligenceObservation?>(
          null,
          (best, item) =>
              best == null || item.observedAtUtcUs > best.observedAtUtcUs
              ? item
              : best,
        );
    final rpe =
        rpeObservation?.value ??
        recent.where((session) => session.rpe != null).firstOrNull?.rpe;
    if (rpe == null) missing.add('Belastungsempfinden der letzten 48 h');
    if (rpe != null && rpe >= policy.recoveryRpe) {
      recovery.add(
        PlanningReason(
          'Das Belastungsempfinden der letzten Einheit war sehr hoch '
          '(RPE ${_fmt(rpe)}).',
          [
            CoachFactRef(
              kind: 'observation',
              id: 'rpe',
              label: 'RPE',
              value: rpe,
            ),
          ],
        ),
      );
    }
    final fatigue = recent
        .where((session) => session.fatiguePercent != null)
        .firstOrNull;
    if (fatigue != null &&
        fatigue.fatiguePercent! <= policy.recoveryFatiguePercent) {
      recovery.add(
        PlanningReason(
          'Die Leistung fiel in der letzten Einheit um '
          '${_fmt(-fatigue.fatiguePercent!)} % ab.',
          [
            CoachFactRef(
              kind: 'session',
              id: fatigue.id,
              label: 'Leistungsabfall',
              value: fatigue.fatiguePercent,
              unit: '%',
            ),
          ],
        ),
      );
    }

    final sinceHard = ledger.hoursSinceHard;
    if (sinceHard != null && sinceHard < policy.minHoursBetweenIntensive) {
      limited.add(
        PlanningReason(
          'Die letzte intensive Einheit liegt erst ${sinceHard.round()} h '
          'zurück.',
          [
            CoachFactRef(
              kind: 'session',
              id: ledger.lastHard!.sessionId,
              label: 'Stunden seit intensivem Reiz',
              value: sinceHard.round(),
              unit: 'h',
            ),
          ],
        ),
      );
    } else {
      // Was sich nicht einordnen lässt, kann hart gewesen sein.
      final unclear = ledger
          .within(2)
          .where(
            (dose) =>
                dose.source == DoseSource.none &&
                dose.rpe == null &&
                dose.peakLactate == null &&
                dose.durationSeconds >= 30 * 60 &&
                nowUtcUs - dose.startedAtUtcUs <
                    policy.minHoursBetweenIntensive * hourUs,
          )
          .firstOrNull;
      if (unclear != null) {
        final hours = (nowUtcUs - unclear.startedAtUtcUs) / hourUs;
        limited.add(
          PlanningReason(
            'Die Einheit vor ${hours.round()} h lässt sich ohne Schwelle für '
            'diese Sportart und ohne Belastungsempfinden nicht einordnen. '
            'So kurz danach plant GIULIA deshalb keinen harten Reiz.',
            [
              CoachFactRef(
                kind: 'session',
                id: unclear.sessionId,
                label: 'Nicht eingeordnete Einheit',
                value: hours.round(),
                unit: 'h',
              ),
            ],
          ),
        );
      }
    }

    final reference = ledger.referenceWeekSeconds;
    if (reference >= policy.minReferenceWeekSeconds) {
      final ratio = ledger.durationSeconds(7) / reference;
      if (ratio > policy.maxAcuteLoadRatio) {
        limited.add(
          PlanningReason(
            'Die Belastung der letzten sieben Tage liegt beim '
            '${_fmt(ratio, 1)}-Fachen einer üblichen Woche.',
            [
              CoachFactRef(
                kind: 'load',
                id: 'acute_ratio',
                label: '7 Tage gegen Vorwochen',
                value: double.parse(ratio.toStringAsFixed(2)),
              ),
            ],
          ),
        );
      }
    } else {
      missing.add('drei Referenzwochen Trainingsdauer');
    }

    final efficiency = _efficiencyDrop(sessions, nowUtcUs);
    if (efficiency != null) limited.add(efficiency);

    if (recovery.isNotEmpty) {
      return ReadinessAssessment(
        level: ReadinessLevel.recovery,
        reasons: [...recovery, ...limited],
        missing: missing,
      );
    }
    if (limited.isNotEmpty) {
      return ReadinessAssessment(
        level: ReadinessLevel.limited,
        reasons: limited,
        missing: missing,
      );
    }
    final fresh = sinceHard == null || sinceHard >= 72;
    return ReadinessAssessment(
      level: fresh ? ReadinessLevel.fresh : ReadinessLevel.normal,
      reasons: [
        PlanningReason(
          sinceHard == null
              ? 'Kein intensiver Reiz in den aufgezeichneten Einheiten.'
              : 'Letzter intensiver Reiz vor ${sinceHard.round()} h, keine '
                    'Warnzeichen in Belastung und Leistung.',
          [
            if (ledger.lastHard case final hard?)
              CoachFactRef(
                kind: 'session',
                id: hard.sessionId,
                label: 'Stunden seit intensivem Reiz',
                value: sinceHard!.round(),
                unit: 'h',
              ),
          ],
        ),
      ],
      missing: missing,
    );
  }

  /// Leistung je Herzschlag der jüngsten Einheit gegen vergleichbare
  /// Einheiten derselben Sportart. Ein Abfall bei gleicher Herzfrequenz ist
  /// das, was Erholung von Ermüdung unterscheidet, ohne HRV oder Schlaf.
  PlanningReason? _efficiencyDrop(
    List<IntelligenceSession> sessions,
    int nowUtcUs,
  ) {
    double? factor(IntelligenceSession session) {
      final power = session.averagePowerWatt;
      final heartRate = session.averageHeartRateBpm;
      if (power == null || heartRate == null || heartRate <= 0) return null;
      if (session.durationSeconds < 20 * 60) return null;
      return power / heartRate;
    }

    const dayUs = Duration.microsecondsPerDay;
    final usable =
        sessions
            .where(
              (session) =>
                  session.completed &&
                  session.startedAtUtcUs <= nowUtcUs &&
                  nowUtcUs - session.startedAtUtcUs <=
                      policy.efficiencyLookbackDays * dayUs &&
                  factor(session) != null,
            )
            .toList()
          ..sort((a, b) => b.startedAtUtcUs.compareTo(a.startedAtUtcUs));
    final latest = usable.firstOrNull;
    if (latest == null || nowUtcUs - latest.startedAtUtcUs > 3 * dayUs) {
      return null;
    }
    final sport = sessionSportKey(latest.sport);
    final references = [
      for (final session in usable.skip(1))
        if (sessionSportKey(session.sport) == sport &&
            session.durationSeconds >= latest.durationSeconds ~/ 2 &&
            session.durationSeconds <= latest.durationSeconds * 2)
          factor(session)!,
    ]..sort();
    if (references.length < policy.efficiencyMinReferences) return null;
    final median = references[references.length ~/ 2];
    final drop = (1 - factor(latest)! / median) * 100;
    if (drop < policy.efficiencyDropPercent) return null;
    return PlanningReason(
      'In der letzten Einheit war die Leistung bei vergleichbarer '
      'Herzfrequenz um ${_fmt(drop)} % geringer als üblich.',
      [
        CoachFactRef(
          kind: 'session',
          id: latest.id,
          label: 'Leistung je Herzschlag gegen Median',
          value: double.parse((-drop).toStringAsFixed(1)),
          unit: '%',
        ),
      ],
    );
  }
}

/// Wie dringend ein Reiz heute ist.
class TrainingNeed {
  const TrainingNeed({
    required this.stimulus,
    required this.priority,
    required this.reasons,
    this.daysSince,
    this.intervalDays,
    this.blockedBy = const [],
  });

  final TrainingStimulus stimulus;

  /// 0 bis etwa 2.5; nur relativ zu den anderen Reizen desselben Tages
  /// bedeutsam.
  final double priority;
  final double? daysSince;
  final double? intervalDays;
  final List<PlanningReason> reasons;

  /// Warum der Reiz heute nicht gesetzt werden darf.
  final List<PlanningReason> blockedBy;

  bool get blocked => blockedBy.isNotEmpty;
}

class TrainingNeedEngine {
  const TrainingNeedEngine({this.policy = const PlanningPolicy()});

  final PlanningPolicy policy;

  /// Alle Reize, absteigend nach Dringlichkeit; blockierte stehen dabei.
  List<TrainingNeed> evaluate({
    required StimulusLedger ledger,
    required SeasonPosition season,
    required IndividualProfile profile,
    required ReadinessAssessment readiness,
  }) {
    final needs = <TrainingNeed>[];
    for (final stimulus in TrainingStimulus.values) {
      final blockedBy = readiness.allows(stimulus)
          ? const <PlanningReason>[]
          : readiness.reasons;
      if (stimulus == TrainingStimulus.regeneration) {
        needs.add(
          TrainingNeed(
            stimulus: stimulus,
            priority: readiness.level == ReadinessLevel.recovery ? 1.0 : 0.05,
            reasons: readiness.level == ReadinessLevel.recovery
                ? readiness.reasons
                : const [],
          ),
        );
        continue;
      }
      final rhythm = policy.rhythm(season.phase, stimulus);
      if (rhythm == null) continue;
      final days = ledger.daysSince(stimulus);
      // Nie gesetzt: fällig, aber nicht dringender als ein deutlich
      // überfälliger Reiz – die Historie kann schlicht fehlen.
      final dueness = days == null
          ? 1.5
          : math.min(days / rhythm.intervalDays, 2.5);
      final weight = rhythm.weight * profile.weight(stimulus);
      final reasons = <PlanningReason>[
        PlanningReason(
          days == null
              ? '${stimulus.label}: in den aufgezeichneten Einheiten nicht '
                    'wirksam gesetzt.'
              : '${stimulus.label}: zuletzt vor ${_fmt(days)} Tagen, '
                    'angestrebt etwa alle ${_fmt(rhythm.intervalDays)} Tage '
                    '(${season.phase.label}).',
          [
            if (ledger.lastMeaningful(stimulus) case final last?)
              CoachFactRef(
                kind: 'session',
                id: last.sessionId,
                label: 'Letzter ${stimulus.label}',
                value: double.parse(days!.toStringAsFixed(1)),
                unit: 'd',
              ),
          ],
        ),
        for (final reason in profile.reasons)
          if (profile.weight(stimulus) != 1.0) reason,
      ];
      needs.add(
        TrainingNeed(
          stimulus: stimulus,
          priority: weight * dueness,
          daysSince: days,
          intervalDays: rhythm.intervalDays,
          reasons: reasons,
          blockedBy: blockedBy,
        ),
      );
    }
    needs.sort((a, b) => b.priority.compareTo(a.priority));
    return List.unmodifiable(needs);
  }
}
