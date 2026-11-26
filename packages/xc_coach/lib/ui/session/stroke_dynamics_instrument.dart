/// Zugdynamik als Instrument: Leistung, Verteilung, Zugphase, Profil und
/// Kennzahlen in einer zusammenhängenden Fläche.
///
/// Jede Grafik hier zeichnet gemessene Werte. Fehlt eine Seite oder eine
/// Kurve, bleibt ihr Instrument leer und zeigt einen Strich.
library;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import '../../app/mirco_preview.dart';

import '../../charts/nice_scale.dart';
import '../../core/stroke_metrics.dart';
import '../../metrics/stroke_curves.dart';
import '../design_system.dart';

/// Ab diesem Anteil der eigenen Spitze zählt Leistung als relevant.
const double strokePhaseRelevantShare = .2;

/// Ab diesem Anteil der eigenen Spitze beginnt der Bereich hoher Leistung.
const double strokePhaseHighShare = .7;

/// Wo innerhalb des Zuges (0..1) eine Seite ihre Leistung entfaltet.
@immutable
class StrokePhaseProfile {
  const StrokePhaseProfile({
    required this.start,
    required this.end,
    required this.highStart,
    required this.highEnd,
    required this.peak,
  });

  final double start;
  final double end;
  final double highStart;
  final double highEnd;
  final double peak;

  /// Aus einer gemessenen Leistungs-Phasen-Kurve; null ohne Leistung.
  static StrokePhaseProfile? fromCurve(List<CurvePoint> curve, {double? peak}) {
    if (curve.length < 2) return null;
    var top = 0.0;
    var topAt = curve.first.x;
    for (final point in curve) {
      if (point.y > top) {
        top = point.y;
        topAt = point.x;
      }
    }
    if (!(top > 0)) return null;
    double first(double level) =>
        curve.firstWhere((point) => point.y >= level).x;
    double last(double level) => curve.lastWhere((point) => point.y >= level).x;
    final relevant = top * strokePhaseRelevantShare;
    final high = top * strokePhaseHighShare;
    return StrokePhaseProfile(
      start: first(relevant),
      end: last(relevant),
      highStart: first(high),
      highEnd: last(high),
      peak: (peak ?? topAt).clamp(0.0, 1.0),
    );
  }

  static StrokePhaseProfile? lerp(
    StrokePhaseProfile? a,
    StrokePhaseProfile? b,
    double t,
  ) {
    if (a == null || b == null) return b;
    return StrokePhaseProfile(
      start: lerpDouble(a.start, b.start, t)!,
      end: lerpDouble(a.end, b.end, t)!,
      highStart: lerpDouble(a.highStart, b.highStart, t)!,
      highEnd: lerpDouble(a.highEnd, b.highEnd, t)!,
      peak: lerpDouble(a.peak, b.peak, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StrokePhaseProfile &&
      other.start == start &&
      other.end == end &&
      other.highStart == highStart &&
      other.highEnd == highEnd &&
      other.peak == peak;

  @override
  int get hashCode => Object.hash(start, end, highStart, highEnd, peak);
}

extension on StrokeSelection {
  String get shortLabel => switch (this) {
    StrokeSelection.last => previewText('Letzter', 'Last'),
    StrokeSelection.lastFive => 'Ø 5',
    StrokeSelection.lastTen => 'Ø 10',
    StrokeSelection.all => previewText('Alle', 'All'),
  };
}

const Duration _transition = Duration(milliseconds: 360);
const Curve _easing = Curves.easeOutCubic;

String _number(double? value, [int decimals = 0]) =>
    giuliaNumber(value, decimals: decimals);

String _percent(double? share) => share == null || !share.isFinite
    ? giuliaMissing
    : '${(share * 100).round()}';

/// Die ganze Zugdynamik-Seite.
class StrokeDynamicsInstrument extends StatefulWidget {
  const StrokeDynamicsInstrument({
    super.key,
    required this.sides,
    this.initialSelection = StrokeSelection.lastFive,
  });

  /// Beide Seiten je Zug, älteste zuerst.
  final List<StrokeSides> sides;
  final StrokeSelection initialSelection;

  @override
  State<StrokeDynamicsInstrument> createState() =>
      _StrokeDynamicsInstrumentState();
}

class _StrokeDynamicsInstrumentState extends State<StrokeDynamicsInstrument> {
  late StrokeSelection _selection;
  bool _forceOverDistance = ErcolinaMechanics.forceModelValidated;

  @override
  void initState() {
    super.initState();
    _selection = widget.initialSelection;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sides.isEmpty) {
      return GiuliaPanel(
        child: Center(
          child: Text(
            previewText(
              'Noch kein abgeschlossener Zug.',
              'No completed stroke yet.',
            ),
          ),
        ),
      );
    }
    final left = <StrokeMetrics>[for (final s in widget.sides) s.left];
    final right = <StrokeMetrics>[for (final s in widget.sides) s.right];
    double? mean(List<StrokeMetrics> side, double? Function(StrokeMetrics) f) =>
        averageOf(side, _selection, f);

    final leftPower = mean(left, (s) => s.averagePowerWatt);
    final rightPower = mean(right, (s) => s.averagePowerWatt);
    final total = leftPower != null && rightPower != null
        ? leftPower + rightPower
        : null;
    final leftPhaseCurve = averagePowerPhaseCurve(left, _selection);
    final rightPhaseCurve = averagePowerPhaseCurve(right, _selection);
    final leftPeak = mean(left, (s) => s.peakPowerPhase);
    final rightPeak = mean(right, (s) => s.peakPowerPhase);

    final metrics = <_SideMetric>[
      _SideMetric(
        previewText('Zugzeit', 'Stroke time'),
        _number(mean(left, (s) => s.durationSeconds), 2),
        _number(mean(right, (s) => s.durationSeconds), 2),
        's',
      ),
      _SideMetric('Peak', _percent(leftPeak), _percent(rightPeak), '%'),
      _SideMetric(
        previewText('Arbeit', 'Work'),
        _number(mean(left, (s) => s.workJoule)),
        _number(mean(right, (s) => s.workJoule)),
        'J',
      ),
      _SideMetric(
        'Max',
        _number(mean(left, (s) => s.peakPowerWatt)),
        _number(mean(right, (s) => s.peakPowerWatt)),
        'W',
      ),
      if (ErcolinaMechanics.forceModelValidated) ...[
        _SideMetric(
          previewText('Zuglänge', 'Stroke length'),
          _number(mean(left, (s) => s.strokeLengthMetres), 2),
          _number(mean(right, (s) => s.strokeLengthMetres), 2),
          'm',
        ),
        _SideMetric(
          'Peak Force',
          _number(mean(left, (s) => s.peakForceNewton)),
          _number(mean(right, (s) => s.peakForceNewton)),
          'N',
        ),
      ],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final height = constraints.maxHeight;
        final padding = wide ? GiuliaTokens.spacingL : GiuliaTokens.spacingM;
        // On narrow screens the arcs are width-limited; no empty band above.
        final arcWidth =
            (constraints.maxWidth - 2 * padding - GiuliaTokens.spacingM) / 2;
        final gaugeHeight = wide
            ? (height * .30).clamp(140.0, 220.0)
            : math.min((height * .2).clamp(104.0, 150.0), arcWidth / 2 + 28);
        final leftArc = _PhaseArc(
          key: const Key('dynamics-arc-left'),
          letter: 'L',
          colour: GiuliaTokens.sideLeft,
          power: leftPower,
          profile: StrokePhaseProfile.fromCurve(leftPhaseCurve, peak: leftPeak),
        );
        final rightArc = _PhaseArc(
          key: const Key('dynamics-arc-right'),
          letter: 'R',
          colour: GiuliaTokens.sideRight,
          power: rightPower,
          profile: StrokePhaseProfile.fromCurve(
            rightPhaseCurve,
            peak: rightPeak,
          ),
        );
        final totalAndBalance = _TotalAndBalance(
          total: total,
          leftShare: giuliaShare(leftPower, rightPower),
          large: wide,
        );
        final chart = _ProfileSection(
          left: left,
          right: right,
          selection: _selection,
          forceOverDistance: _forceOverDistance,
          onDiagram: ErcolinaMechanics.forceModelValidated
              ? (value) => setState(() => _forceOverDistance = value)
              : null,
        );
        final matrix = _MetricMatrix(metrics: metrics, large: wide);
        return GiuliaPanel(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                selection: _selection,
                onSelection: (value) => setState(() => _selection = value),
              ),
              SizedBox(
                height: wide ? GiuliaTokens.spacingM : GiuliaTokens.spacingS,
              ),
              if (!wide) ...[
                SizedBox(height: 92, child: totalAndBalance),
                const SizedBox(height: GiuliaTokens.spacingS),
              ],
              SizedBox(
                height: gaugeHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 4, child: leftArc),
                    SizedBox(
                      width: wide
                          ? GiuliaTokens.spacingL
                          : GiuliaTokens.spacingM,
                    ),
                    if (wide) ...[
                      Expanded(flex: 5, child: totalAndBalance),
                      const SizedBox(width: GiuliaTokens.spacingL),
                    ],
                    Expanded(flex: 4, child: rightArc),
                  ],
                ),
              ),
              SizedBox(
                height: wide ? GiuliaTokens.spacingL : GiuliaTokens.spacingM,
              ),
              Expanded(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: chart),
                          const SizedBox(width: GiuliaTokens.spacingXl),
                          SizedBox(
                            width: math.min(340, constraints.maxWidth * .3),
                            child: matrix,
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: chart),
                          const SizedBox(height: GiuliaTokens.spacingM),
                          matrix,
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.selection, required this.onSelection});

  final StrokeSelection selection;
  final ValueChanged<StrokeSelection> onSelection;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          switch (selection) {
            StrokeSelection.last => previewText('Letzter Zug', 'Last stroke'),
            StrokeSelection.all => previewText('Ø Einheit', 'Session average'),
            _ => previewText(
              'Ø ${selection.strokes} Züge',
              'Avg ${selection.strokes} strokes',
            ),
          },
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
      const SizedBox(width: GiuliaTokens.spacingS),
      Flexible(
        child: Align(
          alignment: Alignment.centerRight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: GiuliaSegmentedControl<StrokeSelection>(
              segments: [
                for (final option in StrokeSelection.values)
                  GiuliaSegment(
                    value: option,
                    label: option.shortLabel,
                    key: Key('dynamics-${option.name}'),
                  ),
              ],
              selected: selection,
              onChanged: onSelection,
            ),
          ),
        ),
      ),
    ],
  );
}

// ------------------------------------------------------------ total/balance

class _TotalAndBalance extends StatelessWidget {
  const _TotalAndBalance({
    required this.total,
    required this.leftShare,
    required this.large,
  });

  final double? total;
  final double? leftShare;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: GiuliaValue(
              key: const Key('dynamics-total'),
              value: _number(total),
              unit: 'W',
              fontSize: large ? 88 : 46,
            ),
          ),
        ),
        const SizedBox(height: GiuliaTokens.spacingXs),
        Text(
          previewText('LEISTUNG', 'POWER'),
          textAlign: TextAlign.center,
          style: text.labelSmall,
        ),
        SizedBox(height: large ? GiuliaTokens.spacingM : GiuliaTokens.spacingS),
        GiuliaBalanceGauge(
          key: const Key('dynamics-balance'),
          leftShare: leftShare,
          fontSize: large ? 22 : 15,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- phase arc

/// Der normierte Zug einer Seite als Halbkreis: links beginnt der Zug, rechts
/// endet er. Getönt ist, wo relevante Leistung fliesst, kräftig, wo sie hoch
/// ist; der Punkt ist die Spitze.
class _PhaseArc extends StatelessWidget {
  const _PhaseArc({
    super.key,
    required this.letter,
    required this.colour,
    required this.power,
    required this.profile,
  });

  final String letter;
  final Color colour;
  final double? power;
  final StrokePhaseProfile? profile;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const footer = 18.0;
        final arcHeight = constraints.maxHeight - footer;
        final radius = math.max(10.0, math.min(width / 2 - 4, arcHeight - 6));
        final stroke = (radius * .14).clamp(6.0, 16.0);
        Widget painted(StrokePhaseProfile? value, Widget? child) => CustomPaint(
          painter: _ArcPainter(
            profile: value,
            colour: colour,
            radius: radius,
            stroke: stroke,
          ),
          child: child,
        );
        final inside = Stack(
          children: [
            Positioned(
              left: math.max(0, width / 2 - radius - 2),
              top: math.max(0, arcHeight - 2 - radius - 4),
              child: Text(
                letter,
                style: text.titleMedium?.copyWith(color: colour),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 2,
              child: Center(
                child: SizedBox(
                  width: math.max(10, (radius - stroke) * 1.6),
                  height: math.max(10, (radius - stroke) * .78),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomCenter,
                    child: GiuliaValue(
                      value: _number(power),
                      unit: 'W',
                      fontSize: math.max(15, radius * .36),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
        final target = profile;
        return Column(
          children: [
            SizedBox(
              height: arcHeight,
              child: target == null
                  ? painted(null, inside)
                  : TweenAnimationBuilder<StrokePhaseProfile>(
                      tween: _ProfileTween(end: target),
                      duration: _transition,
                      curve: _easing,
                      builder: (context, value, child) => painted(value, child),
                      child: inside,
                    ),
            ),
            SizedBox(
              height: footer,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text.rich(
                  TextSpan(
                    text: 'PEAK ',
                    style: text.labelSmall,
                    children: [
                      TextSpan(
                        text: profile == null
                            ? giuliaMissing
                            : '${_percent(profile!.peak)} %',
                        style: text.labelLarge?.copyWith(
                          color: GiuliaTokens.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProfileTween extends Tween<StrokePhaseProfile> {
  _ProfileTween({super.end});

  @override
  StrokePhaseProfile lerp(double t) =>
      StrokePhaseProfile.lerp(begin, end, t) ?? end!;
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({
    required this.profile,
    required this.colour,
    required this.radius,
    required this.stroke,
  });

  final StrokePhaseProfile? profile;
  final Color colour;
  final double radius;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height - 2);
    final rect = Rect.fromCircle(center: centre, radius: radius - stroke / 2);
    double angle(double phase) => math.pi + phase.clamp(0.0, 1.0) * math.pi;
    Offset at(double phase, double r) => Offset(
      centre.dx + r * math.cos(angle(phase)),
      centre.dy + r * math.sin(angle(phase)),
    );
    Paint band(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      false,
      band(GiuliaTokens.sideNeutral),
    );
    // Quarter marks outside the ring give the arc its scale.
    final tick = Paint()
      ..color = GiuliaTokens.borderStrong
      ..strokeWidth = 1;
    for (final phase in const [0.0, .25, .5, .75, 1.0]) {
      canvas.drawLine(at(phase, radius + 2), at(phase, radius + 5), tick);
    }

    final p = profile;
    if (p == null) return;
    void sweep(double from, double to, Paint paint) {
      if (to <= from) return;
      canvas.drawArc(rect, angle(from), (to - from) * math.pi, false, paint);
    }

    sweep(p.start, p.end, band(colour.withValues(alpha: .28)));
    sweep(p.highStart, p.highEnd, band(colour));
    final edge = Paint()
      ..color = colour
      ..strokeWidth = 1.5;
    final inner = radius - stroke - 3;
    final outer = radius + 1;
    canvas.drawLine(at(p.start, inner), at(p.start, outer), edge);
    canvas.drawLine(at(p.end, inner), at(p.end, outer), edge);

    final dot = at(p.peak, radius - stroke / 2);
    canvas.drawCircle(
      dot,
      stroke * .62 + 2,
      Paint()..color = GiuliaTokens.surface1,
    );
    canvas.drawCircle(
      dot,
      stroke * .62,
      Paint()..color = GiuliaTokens.textPrimary,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.profile != profile ||
      old.colour != colour ||
      old.radius != radius ||
      old.stroke != stroke;
}

// ------------------------------------------------------------- profile chart

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.left,
    required this.right,
    required this.selection,
    required this.forceOverDistance,
    required this.onDiagram,
  });

  final List<StrokeMetrics> left;
  final List<StrokeMetrics> right;
  final StrokeSelection selection;
  final bool forceOverDistance;
  final ValueChanged<bool>? onDiagram;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final leftCurve = forceOverDistance
        ? averageForceDistanceCurve(left, selection)
        : averagePowerPhaseCurve(left, selection);
    final rightCurve = forceOverDistance
        ? averageForceDistanceCurve(right, selection)
        : averagePowerPhaseCurve(right, selection);
    final unit = forceOverDistance ? 'N' : 'W';
    final showMeasured =
        selection == StrokeSelection.last && !forceOverDistance;
    final leftMeasured = showMeasured && left.isNotEmpty
        ? measuredPhasePoints(left.last)
        : const <CurvePoint>[];
    final rightMeasured = showMeasured && right.isNotEmpty
        ? measuredPhasePoints(right.last)
        : const <CurvePoint>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              forceOverDistance
                  ? previewText('KRAFT ÜBER DEN WEG', 'FORCE OVER DISTANCE')
                  : previewText('ZUGPROFIL', 'STROKE PROFILE'),
              style: text.labelMedium,
            ),
            const Spacer(),
            if (onDiagram != null)
              GiuliaSegmentedControl<bool>(
                segments: [
                  GiuliaSegment(
                    value: true,
                    label: previewText('Kraft/Weg', 'Force/distance'),
                    key: Key('dynamics-force'),
                  ),
                  GiuliaSegment(
                    value: false,
                    label: previewText('Leistung/Zug', 'Power/stroke'),
                    key: Key('dynamics-power'),
                  ),
                ],
                selected: forceOverDistance,
                onChanged: onDiagram!,
              ),
          ],
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        Expanded(
          child: leftCurve.isEmpty && rightCurve.isEmpty
              ? Center(
                  child: Text(
                    forceOverDistance
                        ? ErcolinaMechanics.pendingValidation
                        : previewText(
                            'Die Kurve entsteht mit dem ersten vollständigen Zug.',
                            'The curve appears after the first complete stroke.',
                          ),
                    textAlign: TextAlign.center,
                    style: text.bodyMedium,
                  ),
                )
              : TweenAnimationBuilder<_Curves>(
                  tween: _CurvesTween(end: _Curves(leftCurve, rightCurve)),
                  duration: _transition,
                  curve: _easing,
                  builder: (context, curves, _) => CustomPaint(
                    key: const Key('dynamics-chart'),
                    painter: _ProfilePainter(
                      left: curves.left,
                      right: curves.right,
                      leftMeasured: leftMeasured,
                      rightMeasured: rightMeasured,
                      unit: unit,
                      metres: forceOverDistance,
                      labelStyle: text.labelSmall!.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      peakStyle: text.labelLarge!.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
        ),
      ],
    );
  }
}

@immutable
class _Curves {
  const _Curves(this.left, this.right);
  final List<CurvePoint> left;
  final List<CurvePoint> right;
}

class _CurvesTween extends Tween<_Curves> {
  _CurvesTween({super.end});

  static List<CurvePoint> _mix(
    List<CurvePoint> a,
    List<CurvePoint> b,
    double t,
  ) {
    if (a.length != b.length) return b;
    return <CurvePoint>[
      for (var i = 0; i < b.length; i++)
        CurvePoint(
          x: lerpDouble(a[i].x, b[i].x, t)!,
          y: lerpDouble(a[i].y, b[i].y, t)!,
        ),
    ];
  }

  @override
  _Curves lerp(double t) {
    final from = begin;
    final to = end!;
    if (from == null) return to;
    return _Curves(_mix(from.left, to.left, t), _mix(from.right, to.right, t));
  }
}

class _ProfilePainter extends CustomPainter {
  _ProfilePainter({
    required this.left,
    required this.right,
    required this.leftMeasured,
    required this.rightMeasured,
    required this.unit,
    required this.metres,
    required this.labelStyle,
    required this.peakStyle,
  });

  final List<CurvePoint> left;
  final List<CurvePoint> right;

  /// Messpunkte des letzten Zuges; leer bei gemittelten Kurven.
  final List<CurvePoint> leftMeasured;
  final List<CurvePoint> rightMeasured;
  final String unit;
  final bool metres;
  final TextStyle labelStyle;
  final TextStyle peakStyle;

  TextPainter _text(String value, TextStyle style) => TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final top = maxY(<List<CurvePoint>>[left, right]);
    if (!(top > 0)) return;
    final scale = NiceScale.forRange(0, top, targetTicks: 4, includeZero: true);
    final axisLabels = [for (final tick in scale.ticks) scale.format(tick)];
    final gutter =
        axisLabels.map((l) => _text(l, labelStyle).width).fold(0.0, math.max) +
        8;
    const bottom = 18.0;
    const headroom = 22.0;
    final plot = Rect.fromLTRB(
      gutter,
      headroom,
      size.width,
      math.max(headroom + 1, size.height - bottom),
    );
    final xEnd = math.max(
      left.isEmpty ? 0.0 : left.last.x,
      right.isEmpty ? 0.0 : right.last.x,
    );
    final xSpan = xEnd <= 0 ? 1.0 : xEnd;
    double y(double value) =>
        plot.bottom - (value / scale.max).clamp(0.0, 1.0) * plot.height;
    double x(double value) => plot.left + value / xSpan * plot.width;

    final grid = Paint()
      ..color = GiuliaTokens.chartGrid
      ..strokeWidth = 1;
    for (final (index, tick) in scale.ticks.indexed) {
      final dy = y(tick).roundToDouble() + .5;
      canvas.drawLine(Offset(plot.left, dy), Offset(plot.right, dy), grid);
      final label = _text(
        index == scale.ticks.length - 1
            ? '${axisLabels[index]} $unit'
            : axisLabels[index],
        labelStyle,
      );
      label.paint(canvas, Offset(0, dy - label.height / 2));
    }
    for (final share in const [0.0, .25, .5, .75, 1.0]) {
      final dx = (plot.left + share * plot.width).roundToDouble() + .5;
      if (share > 0 && share < 1) {
        canvas.drawLine(Offset(dx, plot.top), Offset(dx, plot.bottom), grid);
      }
      final value = metres
          ? '${(share * xSpan).toStringAsFixed(share == 1 ? 2 : 1)}${share == 1 ? ' m' : ''}'
          : '${(share * 100).round()}${share == 1 ? previewText(' % Zug', ' % stroke') : ''}';
      final label = _text(value, labelStyle);
      final lx = (dx - label.width * share).clamp(
        0.0,
        size.width - label.width,
      );
      label.paint(canvas, Offset(lx, plot.bottom + 4));
    }

    final peaks = <(Offset, String, Color)>[];
    void curve(List<CurvePoint> points, Color colour, String letter) {
      if (points.length < 2) return;
      final path = Path()..moveTo(x(points.first.x), y(points.first.y));
      var peak = points.first;
      for (final point in points.skip(1)) {
        path.lineTo(x(point.x), y(point.y));
        if (point.y > peak.y) peak = point;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      peaks.add((
        Offset(x(peak.x), y(peak.y)),
        '$letter ${peak.y.round()} $unit',
        colour,
      ));
    }

    curve(left, GiuliaTokens.sideLeft, 'L');
    curve(right, GiuliaTokens.sideRight, 'R');

    void measured(List<CurvePoint> points, Color colour) {
      final ring = Paint()..color = GiuliaTokens.surface1;
      final fill = Paint()..color = colour;
      for (final point in points) {
        final at = Offset(x(point.x), y(point.y));
        canvas.drawCircle(at, 3.5, ring);
        canvas.drawCircle(at, 2.2, fill);
      }
    }

    measured(leftMeasured, GiuliaTokens.sideLeft);
    measured(rightMeasured, GiuliaTokens.sideRight);

    Rect? placed;
    for (final (point, value, colour) in peaks) {
      canvas.drawCircle(point, 6, Paint()..color = GiuliaTokens.surface1);
      canvas.drawCircle(point, 4, Paint()..color = colour);
      final label = _text(value, peakStyle.copyWith(color: colour));
      var box = Rect.fromLTWH(
        (point.dx - label.width / 2).clamp(plot.left, size.width - label.width),
        point.dy - label.height - 8,
        label.width,
        label.height,
      );
      // Two peaks close together: stack the second label over the first.
      if (placed != null && box.inflate(3).overlaps(placed)) {
        box = box.translate(0, placed.top - 2 - box.bottom);
      }
      if (box.top < 0) box = box.translate(0, -box.top);
      label.paint(canvas, box.topLeft);
      placed = box;
    }
  }

  @override
  bool shouldRepaint(_ProfilePainter old) =>
      !identical(old.left, left) ||
      !identical(old.right, right) ||
      !identical(old.leftMeasured, leftMeasured) ||
      !identical(old.rightMeasured, rightMeasured) ||
      old.unit != unit ||
      old.metres != metres;
}

// ----------------------------------------------------------------- metrics

class _SideMetric {
  const _SideMetric(this.label, this.left, this.right, this.unit);
  final String label;
  final String left;
  final String right;
  final String unit;
}

/// Links · Kennzahl · Rechts, als drei ausgerichtete Spalten.
class _MetricMatrix extends StatelessWidget {
  const _MetricMatrix({required this.metrics, required this.large});

  final List<_SideMetric> metrics;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final valueSize = large ? 26.0 : 19.0;
    Widget value(String number, String unit, Color colour, bool left) =>
        Expanded(
          child: Align(
            alignment: left ? Alignment.centerLeft : Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: left ? Alignment.centerLeft : Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (left) _SideTick(colour: colour),
                  if (left) const SizedBox(width: 8),
                  GiuliaValue(value: number, unit: unit, fontSize: valueSize),
                  if (!left) const SizedBox(width: 8),
                  if (!left) _SideTick(colour: colour),
                ],
              ),
            ),
          ),
        );
    Widget row(_SideMetric metric) => Padding(
      padding: EdgeInsets.symmetric(vertical: large ? 6 : 3),
      child: Row(
        children: [
          value(metric.left, metric.unit, GiuliaTokens.sideLeft, true),
          SizedBox(
            width: large ? 96 : 84,
            child: Text(
              metric.label.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall,
            ),
          ),
          value(metric.right, metric.unit, GiuliaTokens.sideRight, false),
        ],
      ),
    );
    final header = Row(
      children: [
        Expanded(
          child: Text(
            previewText('LINKS', 'LEFT'),
            style: text.labelSmall?.copyWith(color: GiuliaTokens.sideLeft),
          ),
        ),
        Expanded(
          child: Text(
            previewText('RECHTS', 'RIGHT'),
            textAlign: TextAlign.right,
            style: text.labelSmall?.copyWith(color: GiuliaTokens.sideRight),
          ),
        ),
      ],
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Column(
        key: ValueKey(
          Object.hashAll([for (final m in metrics) m.left + m.right]),
        ),
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          SizedBox(
            height: large ? GiuliaTokens.spacingS : GiuliaTokens.spacingXs,
          ),
          for (final metric in metrics) row(metric),
        ],
      ),
    );
  }
}

class _SideTick extends StatelessWidget {
  const _SideTick({required this.colour});
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
    width: 3,
    height: 16,
    decoration: BoxDecoration(
      color: colour,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}
