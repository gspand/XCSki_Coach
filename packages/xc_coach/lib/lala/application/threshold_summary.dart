/// «Schwellen und Maximalwerte»: the ladder a diagnostician reads first.
///
/// A test produces more than two thresholds. Beside LT1 and LT2 the engine
/// also determines the loads at fixed lactate concentrations — 2,0 / 2,5 /
/// 3,0 / 4,0 mmol/l — and the test itself has a maximum. Read together, and
/// each as a percentage of that maximum, they describe the *shape* of the
/// athlete: where the curve leaves its baseline, how much room lies between
/// the upper threshold and exhaustion, how the heart rate is distributed
/// across that range.
///
/// A single pair of numbers cannot say that. Two athletes with the same LT2
/// and different maxima need different training, and the ladder is where that
/// becomes visible.
///
/// ## This module derives, it does not decide
///
/// Every value here is either read from the stored calculation run or is
/// arithmetic over it — a percentage, a difference, a division by body mass.
/// No threshold is recomputed, no method is re-run, and nothing is judged.
/// The scientific core stays the only place where a threshold is determined;
/// see docs/LALA_SCIENTIFIC_GUARDRAILS.md.
library;

import 'dart:math' as math;

import 'package:xc_coach/lala/application/lala_view_models.dart';

/// What a row of the ladder is, so a reader can weigh it.
enum ThresholdSummaryKind {
  /// The highest stage the athlete completed. Measured, not determined.
  maximum,

  /// The load at a fixed lactate concentration — a convention, not a
  /// threshold: it says «this athlete reached 4 mmol/l here», nothing more.
  fixedLactate,

  /// LT1 or LT2 as the selected method determined them.
  threshold,
}

/// One rung of the ladder.
class ThresholdSummaryRow {
  const ThresholdSummaryRow({
    required this.label,
    required this.kind,
    required this.load,
    this.methodLabel,
    this.heartRateBpm,
    this.lactate,
    this.loadPercentOfMaximum,
    this.heartRatePercentOfMaximum,
    this.relativeLoad,
  });

  final String label;
  final ThresholdSummaryKind kind;
  final double load;

  /// Named only for [ThresholdSummaryKind.threshold]: a fixed lactate value
  /// and the maximum are not the product of a method choice.
  final String? methodLabel;

  final int? heartRateBpm;
  final double? lactate;

  /// Share of the highest completed load, 0…1.
  final double? loadPercentOfMaximum;

  /// Share of the highest measured heart rate, 0…1.
  final double? heartRatePercentOfMaximum;

  /// Load per kilogram of body mass; null when no mass was recorded.
  final double? relativeLoad;
}

/// The whole ladder, plus the two figures read underneath it.
class ThresholdSummary {
  const ThresholdSummary({
    required this.rows,
    required this.maximumLoad,
    this.maximumHeartRateBpm,
    this.maximumLactate,
    this.anaerobicReserve,
    this.anaerobicReservePercent,
    this.anaerobicReserveRelative,
  });

  /// Highest load first, so the ladder is read downwards from exhaustion.
  final List<ThresholdSummaryRow> rows;

  final double maximumLoad;
  final int? maximumHeartRateBpm;
  final double? maximumLactate;

  /// Distance between the upper threshold and the maximum, in load units.
  ///
  /// The room an athlete has above the threshold. A large reserve and a low
  /// threshold describe a different athlete than a small reserve and a high
  /// one — and the same training plan would be wrong for one of them.
  final double? anaerobicReserve;

  /// The same distance as a share of the maximum, 0…1.
  final double? anaerobicReservePercent;

  /// The same distance per kilogram of body mass.
  final double? anaerobicReserveRelative;

  bool get isEmpty => rows.isEmpty;
}

/// Builds the ladder for one stored calculation run.
///
/// Returns an empty summary when the test has no usable stage — a ladder
/// whose maximum is unknown has no rung to hang the percentages on.
ThresholdSummary buildThresholdSummary({
  required LalaTestView test,
  required LalaRunView run,
  double? bodyMassKg,
}) {
  // The maximum comes from the *measured* stages, and excluded ones do not
  // count: a stage dropped from the evaluation cannot define the maximum the
  // rest is measured against.
  final stages = test.curve.where((point) => !point.excluded).toList();
  if (stages.isEmpty) {
    return const ThresholdSummary(
      rows: <ThresholdSummaryRow>[],
      maximumLoad: 0,
    );
  }
  final maximumLoad = stages.map((s) => s.load).reduce(math.max);
  final peak = stages.firstWhere((s) => s.load == maximumLoad);
  final maximumHeartRate = stages
      .map((s) => s.heartRateBpm)
      .whereType<int>()
      .fold<int?>(null, (best, hr) => best == null ? hr : math.max(best, hr));

  double? share(double? value, double? reference) =>
      value == null || reference == null || reference <= 0
      ? null
      : value / reference;

  ThresholdSummaryRow row({
    required String label,
    required ThresholdSummaryKind kind,
    required double load,
    String? methodLabel,
    int? heartRateBpm,
    double? lactate,
  }) => ThresholdSummaryRow(
    label: label,
    kind: kind,
    load: load,
    methodLabel: methodLabel,
    heartRateBpm: heartRateBpm,
    lactate: lactate,
    loadPercentOfMaximum: share(load, maximumLoad),
    heartRatePercentOfMaximum: share(
      heartRateBpm?.toDouble(),
      maximumHeartRate?.toDouble(),
    ),
    relativeLoad: bodyMassKg == null || bodyMassKg <= 0
        ? null
        : load / bodyMassKg,
  );

  final rows = <ThresholdSummaryRow>[
    row(
      label: 'Maximum',
      kind: ThresholdSummaryKind.maximum,
      load: maximumLoad,
      heartRateBpm: maximumHeartRate,
      lactate: stages.map((s) => s.lactate).reduce(math.max),
    ),
    // Fixed concentrations, as the engine determined them for this test.
    for (final threshold in run.allThresholds)
      if (isFixedLactateMethod(threshold.methodId) &&
          threshold.loadValue != null)
        row(
          label: fixedLactateLabel(threshold),
          kind: ThresholdSummaryKind.fixedLactate,
          load: threshold.loadValue!,
          heartRateBpm: threshold.heartRateBpm,
          lactate: threshold.lactateMmolPerLitre,
        ),
    // The two selected thresholds last in the list, sorted into place below.
    for (final threshold in <LalaThresholdView?>[run.lt1, run.lt2])
      if (threshold?.loadValue case final load?)
        row(
          label: threshold!.typeLabel,
          kind: ThresholdSummaryKind.threshold,
          load: load,
          methodLabel: threshold.methodLabel,
          heartRateBpm: threshold.heartRateBpm,
          lactate: threshold.lactateMmolPerLitre,
        ),
  ]..sort((a, b) => b.load.compareTo(a.load));

  final upper = run.lt2?.loadValue;
  final reserve = upper == null ? null : maximumLoad - upper;
  return ThresholdSummary(
    rows: rows,
    maximumLoad: maximumLoad,
    maximumHeartRateBpm: maximumHeartRate,
    maximumLactate: peak.lactate,
    anaerobicReserve: reserve,
    anaerobicReservePercent: share(reserve, maximumLoad),
    anaerobicReserveRelative:
        reserve == null || bodyMassKg == null || bodyMassKg <= 0
        ? null
        : reserve / bodyMassKg,
  );
}

/// True for the engine's fixed-concentration methods.
///
/// Matched on the stored method id rather than on the label, because the label
/// is language and the id is the contract.
bool isFixedLactateMethod(String methodId) =>
    methodId.startsWith('fixed_blood_lactate.');

/// «4,0 mmol/l» — the concentration the method targets.
///
/// Taken from the determined lactate value when there is one; the method id
/// carries it too (`…v1.4_0mmol`), but reading the value keeps the label and
/// the row's own lactate column from ever disagreeing.
String fixedLactateLabel(LalaThresholdView threshold) {
  final value = threshold.lactateMmolPerLitre;
  if (value == null) return threshold.methodLabel;
  return '${value.toStringAsFixed(1).replaceAll('.', ',')} mmol/l';
}
