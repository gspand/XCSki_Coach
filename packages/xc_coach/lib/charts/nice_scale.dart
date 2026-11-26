/// Axes whose tick values a reader can say out loud.
///
/// A chart drawn straight from `min`/`max` of the data puts its gridlines at
/// 1.41, 4.63, 7.85 — numbers nobody reads off an axis. Worse, the top of the
/// plot lands on whatever the largest sample happened to be, so two tests of
/// the same athlete get two different scales and stop being comparable by eye.
///
/// [NiceScale] rounds the range outwards to values from the 1 / 2 / 2.5 / 5
/// family and reports the step it chose. Two tests whose data differ slightly
/// therefore usually land on the *same* axis, which is the property that makes
/// a visual comparison honest.
library;

import 'dart:math' as math;

class NiceScale {
  const NiceScale._({
    required this.min,
    required this.max,
    required this.step,
    required this.decimals,
  });

  /// Rounds [lowest] … [highest] outwards to a readable axis.
  ///
  /// [targetTicks] is a wish, not a promise: the rounding decides the actual
  /// count, which is the whole point — an axis with exactly five ugly ticks is
  /// worse than one with four readable ones.
  ///
  /// [includeZero] forces the baseline down to zero. Lactate is a
  /// concentration and belongs on a zero baseline: a lactate axis starting at
  /// 1.3 mmol/l exaggerates every rise. Heart rate is not, and clipping its
  /// axis to the measured band is what makes the curve legible at all.
  factory NiceScale.forRange(
    double lowest,
    double highest, {
    int targetTicks = 5,
    bool includeZero = false,
  }) {
    assert(targetTicks >= 2, 'An axis needs at least two ticks.');
    var low = includeZero ? math.min(0, lowest) : lowest;
    var high = math.max(highest, low);

    // A flat series has no range to round. Give it a nominal band so the line
    // sits in the middle of the plot instead of on its edge.
    if ((high - low).abs() < 1e-9) {
      final nominal = high.abs() < 1e-9 ? 1.0 : high.abs() * .1;
      low -= nominal;
      high += nominal;
      if (includeZero && low < 0) low = 0;
    }

    final step = _niceStep((high - low) / (targetTicks - 1));
    final min = (low / step).floorToDouble() * step;
    final max = (high / step).ceilToDouble() * step;
    return NiceScale._(
      min: min,
      max: max,
      step: step,
      decimals: _decimalsFor(step),
    );
  }

  /// An axis over [lowest] … [highest] with **exactly** [tickCount] ticks.
  ///
  /// Two axes on one chart — lactate on the left, heart rate on the right —
  /// must share their gridlines. If each rounds independently, the right-hand
  /// labels land between the lines they are supposed to name, and the reader
  /// has two grids to disentangle instead of one to read.
  ///
  /// The step is raised through the nice family until the data fits in
  /// [tickCount] intervals; the remaining slack is then spent upwards, so the
  /// baseline stays where the reader expects it.
  factory NiceScale.aligned(
    double lowest,
    double highest,
    int tickCount, {
    bool includeZero = false,
  }) {
    assert(tickCount >= 2, 'An axis needs at least two ticks.');
    var scale = NiceScale.forRange(
      lowest,
      highest,
      targetTicks: tickCount,
      includeZero: includeZero,
    );
    // Too many intervals: coarsen until the data fits into the wanted count.
    var guard = 0;
    while ((scale.span / scale.step).round() > tickCount - 1 && guard++ < 24) {
      final coarser = _niceStep(scale.step * 1.5);
      final min = (scale.min / coarser).floorToDouble() * coarser;
      final max = (scale.max / coarser).ceilToDouble() * coarser;
      scale = NiceScale._(
        min: min,
        max: max,
        step: coarser,
        decimals: _decimalsFor(coarser),
      );
    }
    // Too few: extend the top, which adds head-room rather than moving the
    // baseline out from under the data.
    final missing = (tickCount - 1) - (scale.span / scale.step).round();
    if (missing <= 0) return scale;
    return NiceScale._(
      min: scale.min,
      max: scale.max + scale.step * missing,
      step: scale.step,
      decimals: scale.decimals,
    );
  }

  /// The lower end of the drawn axis — at or below the smallest sample.
  final double min;

  /// The upper end of the drawn axis — at or above the largest sample.
  final double max;

  /// Distance between two gridlines, in data units.
  final double step;

  /// Decimal places that [format] uses, derived from [step]: a 0.5 step needs
  /// one place, a 20 step needs none, and printing "20.0" only adds noise.
  final int decimals;

  double get span => max - min;

  /// Every tick from [min] to [max] inclusive.
  List<double> get ticks {
    // Counted rather than accumulated: adding `step` repeatedly drifts, and
    // the drift is what makes a top gridline miss the frame by one pixel.
    final count = (span / step).round();
    return <double>[for (var i = 0; i <= count; i++) min + step * i];
  }

  /// Where [value] sits on the axis, 0 at [min] and 1 at [max].
  ///
  /// Values outside the axis map outside 0…1 rather than being clamped, so a
  /// caller can decide whether to clip or to let a marker sit in the margin.
  double normalize(double value) => span == 0 ? .5 : (value - min) / span;

  /// A tick as it is set on the axis, in German notation (comma).
  String format(double value) {
    final text = value.toStringAsFixed(decimals);
    return decimals == 0 ? text : text.replaceAll('.', ',');
  }

  static double _niceStep(double raw) {
    if (raw <= 0 || !raw.isFinite) return 1;
    final magnitude = math
        .pow(10, (math.log(raw) / math.ln10).floor())
        .toDouble();
    final residual = raw / magnitude;
    // The 2.5 rung exists for lactate: without it a range of ~9 mmol/l snaps
    // to a step of 5 and leaves an axis of three labels.
    final nice = switch (residual) {
      <= 1 => 1.0,
      <= 2 => 2.0,
      <= 2.5 => 2.5,
      <= 5 => 5.0,
      _ => 10.0,
    };
    return nice * magnitude;
  }

  /// Decimal places in which [step] is exact.
  ///
  /// Not «zero places for any step above one»: the nice family contains 2.5,
  /// and under that rule a lactate axis with gridlines at 2,5 and 7,5 was
  /// labelled «3» and «8». The line and its label then disagree, which is
  /// worse than an unlabelled axis — the reader has no way to notice.
  static int _decimalsFor(double step) {
    for (var places = 0; places <= 4; places++) {
      final scaled = step * math.pow(10, places);
      if ((scaled - scaled.roundToDouble()).abs() < 1e-9) return places;
    }
    return 4;
  }

  @override
  String toString() => 'NiceScale($min…$max, step $step)';
}
