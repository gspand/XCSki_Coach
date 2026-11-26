/// The lactate–performance curve: the one picture this product is judged by.
///
/// ## What this chart has to do that a line graph does not
///
/// A coach reads three things off it, and the drawing has to support all
/// three at once:
///
/// 1. **Values.** What lactate, at what load, at what heart rate. That needs
///    two labelled value axes, not one — a heart-rate line fitted to an
///    invisible scale is decoration, because no number can be read off it.
/// 2. **Shape.** Where the curve leaves its baseline and where it turns up.
///    That needs a zero-based lactate axis: a baseline at 1.3 mmol/l
///    exaggerates the first rise into a threshold that is not there.
/// 3. **Position.** Where LT1 and LT2 fall relative to that shape. They are
///    drawn as named markers with their values, not as bare lines, so the
///    picture stays readable away from the cards that state them.
///
/// ## Deliberate restraint
///
/// The measured points are joined by straight segments. A spline through
/// eight lactate samples invents a curvature that the measurement does not
/// contain — and it invents it exactly in the region where the thresholds are
/// read. An excluded stage is drawn hollow rather than dropped, so the
/// decision to exclude it stays visible to whoever reads the test later.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:xc_coach/charts/nice_scale.dart';
import 'package:xc_coach/ui/design_system.dart';
import 'package:xc_coach/ui/load_language.dart';

/// One measured stage, in the terms the chart needs.
///
/// Deliberately not the view model of the LaLa module: the chart is a drawing
/// instrument, and tying it to one screen's model is what stops the next
/// screen from using it.
class LactateSample {
  const LactateSample({
    required this.load,
    required this.lactate,
    this.heartRateBpm,
    this.stageNumber,
    this.excluded = false,
  });

  final double load;
  final double lactate;
  final int? heartRateBpm;
  final int? stageNumber;
  final bool excluded;
}

/// A named vertical marker — a threshold, drawn where it was determined.
class LactateThreshold {
  const LactateThreshold({
    required this.label,
    required this.load,
    required this.colour,
    this.lactate,
    this.heartRateBpm,
  });

  final String label;
  final double load;
  final Color colour;
  final double? lactate;
  final int? heartRateBpm;
}

/// One test on the chart: its stages, its thresholds and how loudly it speaks.
///
/// A comparison of two tests is the reason this exists. Stacking the two as
/// separate charts is the easier implementation and the worse instrument:
/// each would be drawn to its own scale, so a rightward shift of the curve —
/// the thing the reader is looking for — is exactly what disappears. On shared
/// axes the shift is a distance on the screen.
class LactateSeries {
  const LactateSeries({
    required this.samples,
    this.label,
    this.colour = GiuliaTokens.chartLine,
    this.thresholds = const <LactateThreshold>[],
    this.emphasis = 1,
  });

  final List<LactateSample> samples;
  final String? label;
  final Color colour;
  final List<LactateThreshold> thresholds;

  /// 1 for the test under discussion, less for the one it is measured against.
  /// The older test stays fully visible — it is the reference, not clutter —
  /// but it must not compete with the newer one for attention.
  final double emphasis;
}

/// Renders the chart to a PNG, without ever putting it on screen.
///
/// The report must show the *same* curve the coach discussed on the screen —
/// not a second drawing that looks similar. Reusing the painter is what
/// guarantees that: there is one set of rules for where a point goes, and a
/// change to it moves the screen and the report together or neither.
///
/// [pixelRatio] is the print resolution. Three is roughly 220 dpi at the size
/// the report places the image at, which is the point where the axis labels
/// stop looking like screen pixels on paper.
Future<Uint8List> renderLactateCurvePng({
  required List<LactateSeries> series,
  required String loadUnit,
  required Size size,
  double? bodyMassKg,
  double pixelRatio = 3,
  Color background = GiuliaTokens.surface1,
}) async {
  final drawable = series.where((entry) => entry.samples.length >= 2).toList();
  if (drawable.isEmpty) {
    throw ArgumentError('Eine Kurve braucht mindestens zwei Messpunkte.');
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(pixelRatio);
  canvas.drawRect(Offset.zero & size, Paint()..color = background);

  _LactateCurvePainter(
    geometry: _CurveGeometry(
      series: drawable,
      size: size,
      hasSecondLoadAxis:
          secondaryLoadUnit(loadUnit, bodyMassKg: bodyMassKg) != null,
    ),
    loadUnit: loadUnit,
    bodyMassKg: bodyMassKg,
    textDirection: TextDirection.ltr,
  ).paint(canvas, size);

  final image = await recorder.endRecording().toImage(
    (size.width * pixelRatio).round(),
    (size.height * pixelRatio).round(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

class LactateCurveChart extends StatefulWidget {
  const LactateCurveChart({
    super.key,
    required this.series,
    required this.loadUnit,
    this.height = 300,
    this.bodyMassKg,
  });

  /// One test, drawn on its own.
  LactateCurveChart.single({
    Key? key,
    required List<LactateSample> samples,
    required String loadUnit,
    List<LactateThreshold> thresholds = const <LactateThreshold>[],
    double height = 300,
    double? bodyMassKg,
  }) : this(
         key: key,
         loadUnit: loadUnit,
         height: height,
         bodyMassKg: bodyMassKg,
         series: <LactateSeries>[
           LactateSeries(samples: samples, thresholds: thresholds),
         ],
       );

  /// Drawn in order; the last series is the one the readout follows.
  final List<LactateSeries> series;
  final String loadUnit;
  final double height;

  /// Enables the second load axis: pace under a speed axis, W/kg under a
  /// power axis. Null on a power test simply omits it.
  final double? bodyMassKg;

  @override
  State<LactateCurveChart> createState() => _LactateCurveChartState();
}

class _LactateCurveChartState extends State<LactateCurveChart> {
  /// Index of the stage the finger is nearest, or null when nobody touches.
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final drawable = widget.series
        .where((series) => series.samples.length >= 2)
        .toList();
    if (drawable.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text(
            'Für eine Kurve werden mindestens zwei Messpunkte benötigt.',
            textAlign: TextAlign.center,
            style: TextStyle(color: GiuliaTokens.textSecondary),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = _CurveGeometry(
          series: drawable,
          size: Size(constraints.maxWidth, widget.height),
          hasSecondLoadAxis:
              secondaryLoadUnit(
                widget.loadUnit,
                bodyMassKg: widget.bodyMassKg,
              ) !=
              null,
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _touch(geometry, details.localPosition),
          onHorizontalDragStart: (d) => _touch(geometry, d.localPosition),
          onHorizontalDragUpdate: (d) => _touch(geometry, d.localPosition),
          onHorizontalDragEnd: (_) => setState(() => _touched = null),
          onTapUp: (_) => setState(() => _touched = null),
          onTapCancel: () => setState(() => _touched = null),
          child: SizedBox(
            height: widget.height,
            child: CustomPaint(
              size: Size.infinite,
              painter: _LactateCurvePainter(
                geometry: geometry,
                loadUnit: widget.loadUnit,
                bodyMassKg: widget.bodyMassKg,
                touched: _touched,
                textDirection: Directionality.of(context),
              ),
            ),
          ),
        );
      },
    );
  }

  void _touch(_CurveGeometry geometry, Offset position) {
    final index = geometry.nearestSample(position.dx);
    if (index != _touched) setState(() => _touched = index);
  }
}

/// Everything positional, computed once and shared by painter and hit test.
///
/// The hit test has to agree with the drawing to the pixel; deriving both from
/// one object is what guarantees it, rather than two copies of the same
/// arithmetic drifting apart.
class _CurveGeometry {
  factory _CurveGeometry({
    required List<LactateSeries> series,
    required Size size,
    bool hasSecondLoadAxis = false,
  }) {
    // Every scale spans **all** series. This is the property that makes a
    // comparison mean anything: two tests fitted to their own axes look alike
    // however far apart their numbers are.
    final all = series.expand((s) => s.samples).toList();
    final lactate = NiceScale.forRange(
      0,
      all.map((s) => s.lactate).reduce(math.max),
      includeZero: true,
    );
    final load = NiceScale.forRange(
      all.map((s) => s.load).reduce(math.min),
      all.map((s) => s.load).reduce(math.max),
      targetTicks: 6,
    );
    // A heart-rate axis is drawn only when *every* series can carry one.
    // Drawing it for some and not others would put two different meanings on
    // one right-hand scale.
    final rates = all
        .where((s) => s.heartRateBpm != null)
        .map((s) => s.heartRateBpm!.toDouble())
        .toList();
    final complete = series.every(
      (s) => s.samples.where((p) => p.heartRateBpm != null).length >= 2,
    );
    return _CurveGeometry._(
      series: series,
      size: size,
      hasSecondLoadAxis: hasSecondLoadAxis,
      lactate: lactate,
      load: load,
      heartRate: complete && rates.length >= 2
          ? NiceScale.aligned(
              rates.reduce(math.min),
              rates.reduce(math.max),
              lactate.ticks.length,
            )
          : null,
    );
  }

  const _CurveGeometry._({
    required this.series,
    required this.size,
    required this.hasSecondLoadAxis,
    required this.lactate,
    required this.load,
    required this.heartRate,
  });

  /// True when the load axis carries a second row of labels — pace or W/kg.
  final bool hasSecondLoadAxis;

  final List<LactateSeries> series;

  /// The series the touch readout follows: the last one drawn, which is the
  /// test under discussion rather than the one it is compared against.
  List<LactateSample> get samples => series.last.samples;

  final Size size;
  final NiceScale lactate;
  final NiceScale load;

  /// Null when fewer than two stages carry a heart rate: a single point is not
  /// a curve, and an axis drawn for it would claim a precision it has not got.
  final NiceScale? heartRate;

  /// Room for the axis furniture. The right gutter collapses when there is no
  /// heart-rate axis, so a lactate-only test uses the full width.
  static const double _gutterLeft = 52;
  static const double _gutterTop = 30;
  double get _gutterBottom => hasSecondLoadAxis ? 62 : 46;
  double get _gutterRight => heartRate == null ? 16 : 52;

  Rect get plot => Rect.fromLTRB(
    _gutterLeft,
    _gutterTop,
    size.width - _gutterRight,
    size.height - _gutterBottom,
  );

  double x(double value) => plot.left + load.normalize(value) * plot.width;
  double yLactate(double value) =>
      plot.bottom - lactate.normalize(value) * plot.height;
  double? yHeartRate(num? value) {
    final scale = heartRate;
    if (scale == null || value == null) return null;
    return plot.bottom - scale.normalize(value.toDouble()) * plot.height;
  }

  Offset pointOf(LactateSample sample) =>
      Offset(x(sample.load), yLactate(sample.lactate));

  /// The stage nearest to a horizontal position, for the touch readout.
  int nearestSample(double dx) {
    var best = 0;
    var distance = double.infinity;
    for (var index = 0; index < samples.length; index++) {
      final candidate = (x(samples[index].load) - dx).abs();
      if (candidate < distance) {
        distance = candidate;
        best = index;
      }
    }
    return best;
  }
}

class _LactateCurvePainter extends CustomPainter {
  const _LactateCurvePainter({
    required this.geometry,
    required this.loadUnit,
    required this.textDirection,
    this.bodyMassKg,
    this.touched,
  });

  final _CurveGeometry geometry;
  final String loadUnit;
  final double? bodyMassKg;
  final TextDirection textDirection;
  final int? touched;

  static const _axisStyle = TextStyle(
    color: GiuliaTokens.textMuted,
    fontSize: 11,
    fontFamily: GiuliaTokens.fontFamily,
    height: 1,
  );

  /// Lighter than the primary row: it is a second reading of the same tick,
  /// not a second axis with its own scale.
  static const _secondAxisStyle = TextStyle(
    color: GiuliaTokens.textMuted,
    fontSize: 10,
    fontFamily: GiuliaTokens.fontFamily,
    height: 1,
  );
  static const _titleStyle = TextStyle(
    color: GiuliaTokens.textSecondary,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    fontFamily: GiuliaTokens.fontFamily,
    letterSpacing: .3,
    height: 1,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final plot = geometry.plot;
    if (plot.width <= 0 || plot.height <= 0) return;

    _paintTransitionBand(canvas, plot);
    _paintGrid(canvas, plot);
    for (final series in geometry.series) {
      _paintThresholds(canvas, plot, series);
    }
    for (final series in geometry.series) {
      _paintHeartRate(canvas, plot, series);
    }
    for (final series in geometry.series) {
      _paintLactate(canvas, plot, series);
    }
    _paintAxes(canvas, plot);
    _paintReadout(canvas, plot);
  }

  /// The aerobic–anaerobic transition as a tinted band.
  ///
  /// The region between LT1 and LT2 is the one a training plan is built on;
  /// showing it as an area rather than as two unrelated lines is what makes
  /// its *width* — the athlete's transition range — visible at a glance.
  void _paintTransitionBand(Canvas canvas, Rect plot) {
    // Only for the series under discussion. Two tinted bands overlapping
    // would read as a third region that nothing measured.
    final thresholds = geometry.series.last.thresholds;
    if (thresholds.length < 2) return;
    final loads = thresholds.map((t) => t.load).toList()..sort();
    final left = geometry.x(loads.first);
    final right = geometry.x(loads.last);
    if (!left.isFinite || !right.isFinite || right <= left) return;
    canvas.drawRect(
      Rect.fromLTRB(
        left.clamp(plot.left, plot.right),
        plot.top,
        right.clamp(plot.left, plot.right),
        plot.bottom,
      ),
      Paint()..color = GiuliaTokens.accent.withValues(alpha: .045),
    );
  }

  void _paintGrid(Canvas canvas, Rect plot) {
    final grid = Paint()
      ..color = GiuliaTokens.chartGrid
      ..strokeWidth = 1;
    for (final tick in geometry.lactate.ticks) {
      final y = geometry.yLactate(tick);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }
    // The load axis gets ticks on the baseline only. Full vertical gridlines
    // would compete with the threshold markers, which are the vertical lines
    // that carry meaning here.
    for (final tick in geometry.load.ticks) {
      final x = geometry.x(tick);
      if (x < plot.left - .5 || x > plot.right + .5) continue;
      canvas.drawLine(Offset(x, plot.bottom), Offset(x, plot.bottom + 4), grid);
    }
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      Paint()
        ..color = GiuliaTokens.chartReference.withValues(alpha: .45)
        ..strokeWidth = 1,
    );
  }

  void _paintThresholds(Canvas canvas, Rect plot, LactateSeries series) {
    for (final threshold in series.thresholds) {
      final x = geometry.x(threshold.load);
      if (x < plot.left || x > plot.right) continue;

      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = threshold.colour.withValues(alpha: .85 * series.emphasis)
          ..strokeWidth = 1.5,
      );

      // A pill above the plot: the label sits clear of the data instead of on
      // top of it, and still points at its own line.
      // Where the threshold meets the curve: a diamond on the lactate line.
      // Without it the vertical marker states a load but never says which
      // lactate value the method actually settled on.
      if (threshold.lactate case final lactate? when series.emphasis == 1) {
        final centre = Offset(x, geometry.yLactate(lactate));
        final diamond = Path()
          ..moveTo(centre.dx, centre.dy - 6)
          ..lineTo(centre.dx + 6, centre.dy)
          ..lineTo(centre.dx, centre.dy + 6)
          ..lineTo(centre.dx - 6, centre.dy)
          ..close();
        canvas
          ..drawPath(diamond, Paint()..color = GiuliaTokens.surface1)
          ..drawPath(
            diamond,
            Paint()
              ..color = threshold.colour
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
      }

      // Only the leading series labels its markers. In a comparison the
      // earlier test's pills would double the furniture above the plot to say
      // what the legend already says.
      if (series.emphasis < 1) continue;
      final text = _layout(
        '${threshold.label}  ${_number(threshold.load)} $loadUnit',
        TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          fontFamily: GiuliaTokens.fontFamily,
          height: 1,
        ),
      );
      final pill = Rect.fromLTWH(
        (x - text.width / 2 - 7).clamp(plot.left, plot.right - text.width - 14),
        plot.top - 22,
        text.width + 14,
        18,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(pill, const Radius.circular(9)),
        Paint()..color = threshold.colour,
      );
      text.paint(canvas, Offset(pill.left + 7, pill.top + 4));
    }
  }

  void _paintHeartRate(Canvas canvas, Rect plot, LactateSeries series) {
    if (geometry.heartRate == null) return;
    final path = Path();
    final marks = <Offset>[];
    var started = false;
    for (final sample in series.samples) {
      final y = geometry.yHeartRate(sample.heartRateBpm);
      if (y == null) continue;
      final point = Offset(geometry.x(sample.load), y);
      marks.add(point);
      started
          ? path.lineTo(point.dx, point.dy)
          : path.moveTo(point.dx, point.dy);
      started = true;
    }
    final alpha = .75 * series.emphasis;
    canvas.drawPath(
      path,
      Paint()
        ..color = GiuliaTokens.error.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
    for (final mark in marks) {
      canvas.drawCircle(
        mark,
        2.6,
        Paint()..color = GiuliaTokens.error.withValues(alpha: alpha),
      );
    }
  }

  void _paintLactate(Canvas canvas, Rect plot, LactateSeries series) {
    final points = series.samples.map(geometry.pointOf).toList();

    // Area under the curve: it separates the lactate line from the heart-rate
    // line at a glance, without a legend lookup. Only under the leading
    // series — two stacked fills would read as a third quantity.
    if (series.emphasis == 1) {
      _paintArea(canvas, plot, points, series.colour);
    }

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = series.colour.withValues(alpha: series.emphasis)
        ..style = PaintingStyle.stroke
        ..strokeWidth = series.emphasis == 1 ? 2.4 : 2
        ..strokeJoin = StrokeJoin.round,
    );

    for (var index = 0; index < points.length; index++) {
      final sample = series.samples[index];
      final point = points[index];
      // A white halo keeps a point readable where the curve steepens and the
      // markers start to overlap the line.
      canvas.drawCircle(point, 5.6, Paint()..color = GiuliaTokens.surface1);
      canvas.drawCircle(
        point,
        4,
        Paint()
          ..color = sample.excluded
              ? GiuliaTokens.surface1
              : series.colour.withValues(alpha: series.emphasis),
      );
      canvas.drawCircle(
        point,
        4,
        Paint()
          ..color = sample.excluded
              ? GiuliaTokens.textMuted
              : series.colour.withValues(alpha: series.emphasis)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  void _paintArea(Canvas canvas, Rect plot, List<Offset> points, Color colour) {
    final area = Path()..moveTo(points.first.dx, plot.bottom);
    for (final point in points) {
      area.lineTo(point.dx, point.dy);
    }
    area
      ..lineTo(points.last.dx, plot.bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(plot.left, plot.top),
          Offset(plot.left, plot.bottom),
          <Color>[colour.withValues(alpha: .22), colour.withValues(alpha: .02)],
        ),
    );
  }

  void _paintAxes(Canvas canvas, Rect plot) {
    for (final tick in geometry.lactate.ticks) {
      final label = _layout(geometry.lactate.format(tick), _axisStyle);
      label.paint(
        canvas,
        Offset(plot.left - 8 - label.width, geometry.yLactate(tick) - 5),
      );
    }

    final heartRate = geometry.heartRate;
    if (heartRate != null) {
      // Both axes carry the same number of ticks (see [NiceScale.aligned]), so
      // the n-th heart-rate label belongs on the n-th lactate gridline. Walked
      // by index rather than looked up by value: two equal heart rates would
      // make a search by value return the same line twice.
      final ticks = heartRate.ticks;
      for (var index = 0; index < ticks.length; index++) {
        final label = _layout(heartRate.format(ticks[index]), _axisStyle);
        final y = geometry.yLactate(
          geometry.lactate.min + geometry.lactate.step * index,
        );
        label.paint(canvas, Offset(plot.right + 8, y - 5));
      }
    }

    // The second reading of the load axis: pace under a speed axis, W/kg under
    // a power axis. Same ticks, same positions — a running coach reads the
    // session off the row they think in without converting anything.
    final secondUnit = secondaryLoadUnit(loadUnit, bodyMassKg: bodyMassKg);
    for (final tick in geometry.load.ticks) {
      final x = geometry.x(tick);
      if (x < plot.left - .5 || x > plot.right + .5) continue;
      final label = _layout(geometry.load.format(tick), _axisStyle);
      label.paint(canvas, Offset(x - label.width / 2, plot.bottom + 9));

      if (secondUnit == null) continue;
      final spoken = secondaryLoad(tick, loadUnit, bodyMassKg: bodyMassKg);
      if (spoken == null) continue;
      final second = _layout(
        spoken.replaceAll(' $secondUnit', ''),
        _secondAxisStyle,
      );
      second.paint(canvas, Offset(x - second.width / 2, plot.bottom + 25));
    }

    _paintRotatedTitle(
      canvas,
      'LAKTAT (mmol/l)',
      Offset(14, plot.center.dy),
      quarterTurns: -1,
    );
    if (heartRate != null) {
      _paintRotatedTitle(
        canvas,
        'HERZFREQUENZ (bpm)',
        Offset(geometry.size.width - 12, plot.center.dy),
        quarterTurns: 1,
      );
    }
    final loadTitle = _layout(
      secondUnit == null
          ? 'BELASTUNG ($loadUnit)'
          : 'BELASTUNG ($loadUnit)  ·  ${secondaryLoadCaption(loadUnit, bodyMassKg: bodyMassKg)} ($secondUnit)',
      _titleStyle,
    );
    loadTitle.paint(
      canvas,
      Offset(
        (plot.center.dx - loadTitle.width / 2).clamp(
          0,
          math.max(0, geometry.size.width - loadTitle.width),
        ),
        plot.bottom + (secondUnit == null ? 28 : 44),
      ),
    );
  }

  void _paintRotatedTitle(
    Canvas canvas,
    String text,
    Offset anchor, {
    required int quarterTurns,
  }) {
    final label = _layout(text, _titleStyle);
    canvas
      ..save()
      ..translate(anchor.dx, anchor.dy)
      ..rotate(quarterTurns * math.pi / 2);
    label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
    canvas.restore();
  }

  /// The touch readout: one stage, named, with every value it carries.
  void _paintReadout(Canvas canvas, Rect plot) {
    final index = touched;
    if (index == null || index >= geometry.samples.length) return;
    final sample = geometry.samples[index];
    final point = geometry.pointOf(sample);

    canvas.drawLine(
      Offset(point.dx, plot.top),
      Offset(point.dx, plot.bottom),
      Paint()
        ..color = GiuliaTokens.textPrimary.withValues(alpha: .35)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      point,
      7,
      Paint()
        ..color = GiuliaTokens.chartLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final lines = <String>[
      if (sample.stageNumber != null)
        'Stufe ${sample.stageNumber}'
      else
        'Messpunkt',
      '${_number(sample.load)} $loadUnit',
      '${_decimal(sample.lactate)} mmol/l',
      if (sample.heartRateBpm != null) '${sample.heartRateBpm} bpm',
      if (sample.excluded) 'ausgeschlossen',
    ];
    final painters = <TextPainter>[
      _layout(
        lines.first,
        const TextStyle(
          color: GiuliaTokens.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          fontFamily: GiuliaTokens.fontFamily,
          letterSpacing: .6,
          height: 1.35,
        ),
      ),
      for (final line in lines.skip(1))
        _layout(
          line,
          const TextStyle(
            color: GiuliaTokens.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: GiuliaTokens.fontFamily,
            height: 1.35,
          ),
        ),
    ];

    final width = painters.map((p) => p.width).reduce(math.max) + 20;
    final height = painters.fold<double>(0, (sum, p) => sum + p.height) + 16;
    // Flip to the other side of the guide line when the card would leave the
    // plot — the readout must never cover the point it describes.
    final left = point.dx + 14 + width <= plot.right
        ? point.dx + 14
        : point.dx - 14 - width;
    final card = Rect.fromLTWH(
      left.clamp(plot.left, math.max(plot.left, plot.right - width)),
      plot.top + 6,
      width,
      height,
    );
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(card, const Radius.circular(10)),
        Paint()..color = GiuliaTokens.surface1,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(card, const Radius.circular(10)),
        Paint()
          ..color = GiuliaTokens.chartGrid
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    var y = card.top + 8;
    for (final painter in painters) {
      painter.paint(canvas, Offset(card.left + 10, y));
      y += painter.height;
    }
  }

  TextPainter _layout(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
  )..layout();

  static String _number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : _decimal(value);

  static String _decimal(double value) =>
      value.toStringAsFixed(value.abs() >= 10 ? 1 : 2).replaceAll('.', ',');

  @override
  bool shouldRepaint(covariant _LactateCurvePainter old) =>
      old.touched != touched ||
      old.geometry.series != geometry.series ||
      old.geometry.size != geometry.size ||
      old.bodyMassKg != bodyMassKg ||
      old.loadUnit != loadUnit;
}
