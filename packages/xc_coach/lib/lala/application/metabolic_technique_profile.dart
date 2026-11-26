/// Evidence-preserving athlete profile assembled from persisted LaLa tests.
///
/// This layer deliberately performs only transparent arithmetic on values
/// already stored by GIULIA. It does not estimate VO2max, VLamax, FatMax,
/// glycogen use or lactate production/clearance rates. Those require a
/// separately validated protocol and model.
library;

import 'package:xc_coach/domain/diagnostics.dart';
import 'package:xc_coach/lala/application/lala_view_models.dart';

enum ProfileEvidence { measured, calculated, notValidated }

class MetabolicTimelinePoint {
  const MetabolicTimelinePoint({
    required this.testId,
    required this.atUtc,
    required this.loadUnit,
    this.lt1Load,
    this.lt2Load,
    this.lt1HeartRate,
    this.lt2HeartRate,
    this.peakCompletedLoad,
  });

  final String testId;
  final DateTime atUtc;
  final String loadUnit;
  final double? lt1Load;
  final double? lt2Load;
  final int? lt1HeartRate;
  final int? lt2HeartRate;
  final double? peakCompletedLoad;
}

class RecoveryLactatePoint {
  const RecoveryLactatePoint({
    required this.minutesAfterEffort,
    required this.lactateMmolPerLitre,
    required this.context,
  });

  final double minutesAfterEffort;
  final double lactateMmolPerLitre;
  final LactateSampleContext context;
}

class TechniqueStagePoint {
  const TechniqueStagePoint({
    required this.stageNumber,
    required this.load,
    required this.excluded,
    required this.partial,
    this.meanPowerWatt,
    this.peakPowerWatt,
    this.steadyEndPowerWatt,
    this.strokeRatePerMinute,
    this.strokeCount,
    this.leftWorkShare,
    this.workJoule,
  });

  final int stageNumber;
  final double load;
  final bool excluded;
  final bool partial;
  final double? meanPowerWatt;
  final double? peakPowerWatt;
  final double? steadyEndPowerWatt;
  final double? strokeRatePerMinute;
  final int? strokeCount;
  final double? leftWorkShare;
  final double? workJoule;

  double? get endPowerRetention {
    final peak = peakPowerWatt;
    final end = steadyEndPowerWatt;
    if (peak == null || peak <= 0 || end == null) return null;
    return end / peak;
  }
}

class MetabolicTechniqueProfile {
  const MetabolicTechniqueProfile({
    required this.athleteName,
    required this.latestTest,
    required this.timeline,
    required this.recovery,
    required this.technique,
    required this.recoveryTimingAvailable,
  });

  factory MetabolicTechniqueProfile.fromOverview({
    required LalaAthleteOverview overview,
    required LalaTestView Function(String testId) loadTest,
  }) {
    final latest = overview.latestTest;
    if (latest == null) {
      return MetabolicTechniqueProfile(
        athleteName: overview.athleteName,
        latestTest: null,
        timeline: const [],
        recovery: const [],
        technique: const [],
        recoveryTimingAvailable: false,
      );
    }

    final comparableTests = <LalaTestView>[];
    for (final entry in overview.history.where((entry) => entry.hasResult)) {
      final test = loadTest(entry.testId);
      if (test.head.id == latest.head.id ||
          LalaComparison.between(earlier: test, later: latest).comparable) {
        comparableTests.add(test);
      }
    }
    comparableTests.sort(
      (a, b) => a.head.startedAtUtcUs.compareTo(b.head.startedAtUtcUs),
    );

    final timeline = <MetabolicTimelinePoint>[
      for (final test in comparableTests)
        MetabolicTimelinePoint(
          testId: test.head.id,
          atUtc: DateTime.fromMicrosecondsSinceEpoch(
            test.head.startedAtUtcUs,
            isUtc: true,
          ),
          loadUnit: test.head.loadUnit,
          lt1Load: test.latestRun?.lt1?.loadValue,
          lt2Load: test.latestRun?.lt2?.loadValue,
          lt1HeartRate: test.latestRun?.lt1?.heartRateBpm,
          lt2HeartRate: test.latestRun?.lt2?.heartRateBpm,
          peakCompletedLoad: test.data.peakLoad,
        ),
    ];

    final effortEndUtcUs = _effortEndUtcUs(latest);
    final recoverySamples =
        latest.data.samples
            .where(
              (sample) =>
                  sample.context == LactateSampleContext.postExercise ||
                  sample.context == LactateSampleContext.recovery,
            )
            .toList(growable: false)
          ..sort((a, b) => a.sampledAtUtcUs.compareTo(b.sampledAtUtcUs));
    final recovery = effortEndUtcUs == null
        ? const <RecoveryLactatePoint>[]
        : <RecoveryLactatePoint>[
            for (final sample in recoverySamples)
              if (sample.sampledAtUtcUs >= effortEndUtcUs)
                RecoveryLactatePoint(
                  minutesAfterEffort:
                      (sample.sampledAtUtcUs - effortEndUtcUs) / 60000000,
                  lactateMmolPerLitre: sample.lactateMmolPerLitre,
                  context: sample.context,
                ),
          ];

    final technique = <TechniqueStagePoint>[
      for (final stage in latest.data.stages)
        if (stage.meanPowerWatt != null ||
            stage.peakPowerWatt != null ||
            stage.steadyEndPowerWatt != null ||
            stage.strokeRatePerMinute != null ||
            stage.strokeCount != null ||
            stage.leftWorkShare != null ||
            stage.workJoule != null)
          TechniqueStagePoint(
            stageNumber: stage.stageIndex,
            load: stage.loadValue,
            excluded: stage.excluded,
            partial: stage.partial,
            meanPowerWatt: stage.meanPowerWatt,
            peakPowerWatt: stage.peakPowerWatt,
            steadyEndPowerWatt: stage.steadyEndPowerWatt,
            strokeRatePerMinute: stage.strokeRatePerMinute,
            strokeCount: stage.strokeCount,
            leftWorkShare: stage.leftWorkShare,
            workJoule: stage.workJoule,
          ),
    ];

    return MetabolicTechniqueProfile(
      athleteName: overview.athleteName,
      latestTest: latest,
      timeline: List.unmodifiable(timeline),
      recovery: List.unmodifiable(recovery),
      technique: List.unmodifiable(technique),
      recoveryTimingAvailable:
          recoverySamples.isEmpty || effortEndUtcUs != null,
    );
  }

  final String athleteName;
  final LalaTestView? latestTest;

  /// Every comparable test, oldest first. There is deliberately no 12-week
  /// cutoff: the complete documented history is the default contract.
  final List<MetabolicTimelinePoint> timeline;
  final List<RecoveryLactatePoint> recovery;
  final List<TechniqueStagePoint> technique;

  /// False means samples exist but the persisted final-effort timestamp does
  /// not; in that case GIULIA refuses to invent a recovery time axis.
  final bool recoveryTimingAvailable;

  LalaRunView? get latestRun => latestTest?.latestRun;
  double? get peakCompletedLoad => latestTest?.data.peakLoad;
  String? get loadUnit => latestTest?.head.loadUnit;
  double? get bodyMassKg => latestTest?.data.bodyMassKg;

  double? get lt1ToLt2Ratio {
    final lt1 = latestRun?.lt1?.loadValue;
    final lt2 = latestRun?.lt2?.loadValue;
    if (lt1 == null || lt2 == null || lt2 <= 0) return null;
    return lt1 / lt2;
  }

  double? get lt2ToPeakRatio {
    final lt2 = latestRun?.lt2?.loadValue;
    final peak = peakCompletedLoad;
    if (lt2 == null || peak == null || peak <= 0) return null;
    return lt2 / peak;
  }

  double? get peakPerKg {
    final peak = peakCompletedLoad;
    final mass = bodyMassKg;
    if (loadUnit != LoadUnits.watt ||
        peak == null ||
        mass == null ||
        mass <= 0) {
      return null;
    }
    return peak / mass;
  }

  static int? _effortEndUtcUs(LalaTestView test) {
    int? latest;
    for (final stage in test.data.stages) {
      if (stage.excluded) continue;
      final endedAt = stage.endedAtUtcUs;
      if (endedAt != null && (latest == null || endedAt > latest)) {
        latest = endedAt;
      }
    }
    return latest;
  }
}
