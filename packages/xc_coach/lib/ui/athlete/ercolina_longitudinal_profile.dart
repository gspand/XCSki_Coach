/// Ercolina power history drawn only from archived Ercolina strokes.
/// Shared by the device app and the full athlete app; no imported activities.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/athlete_ercolina_profile.dart';
import '../../app/mirco_preview.dart';
import '../../charts/nice_scale.dart';
import '../design_system.dart';

class ErcolinaLongitudinalProfile extends StatelessWidget {
  const ErcolinaLongitudinalProfile({super.key, required this.profile});

  final AthleteErcolinaProfile profile;

  @override
  Widget build(BuildContext context) {
    if (profile.isEmpty) {
      return GiuliaPanel(
        key: const Key('ercolina-longitudinal-empty'),
        child: Text(
          previewText(
            'Noch keine vergleichbare Ercolina-Einheit mit gespeicherten Zügen. '
                'Die Historie bleibt unter Einheiten erreichbar.',
            'No comparable Ercolina session with recorded strokes yet. '
                'Your complete training history is available under Sessions.',
          ),
        ),
      );
    }
    return GiuliaPanel(
      key: const Key('ercolina-longitudinal-profile'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            previewText(
              'ERCOLINA POWER CURVE · GESAMTE HISTORIE',
              'ERCOLINA POWER CURVE · ALL TIME',
            ),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: GiuliaTokens.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: GiuliaTokens.spacingXs),
          Text(
            '${profile.sessionCount} ${previewText('Einheiten', 'sessions')} · '
            '${_date(profile.firstSessionAt)} – '
            '${_date(profile.lastSessionAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          _ErcolinaPowerCurveChart(bests: profile.powerBests),
          _ErcolinaPowerTrendChart(history: profile.powerHistory),
          const SizedBox(height: GiuliaTokens.spacingM),
          Text(
            previewText('POWER-DURATION BESTWERTE', 'POWER-DURATION BESTS'),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          for (final best in profile.powerBests)
            _HistoricalPowerBestRow(value: best),
          const SizedBox(height: GiuliaTokens.spacingL),
          Text(
            previewText('STROKE-DURATION BESTWERTE', 'STROKE-COUNT BESTS'),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          for (final best in profile.strokeBests)
            _HistoricalStrokeBestRow(value: best),
          const SizedBox(height: GiuliaTokens.spacingM),
          Text(
            previewText(
              'Verglichen werden ausschließlich gleiche Zeitfenster '
                  '(z. B. 5 min mit 5 min) und gleiche Zugzahlen. Die '
                  'Zeitfensterleistung enthält Pausen als null mechanische '
                  'Leistung. Kraft und Weg fehlen, solange das mechanische Modell '
                  'nicht referenzvalidiert ist.',
              'Only equal durations and equal stroke counts are compared. '
                  'Power over a time window includes pauses as zero mechanical work. '
                  'Force and travel remain unavailable until the mechanical model is validated.',
            ),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
          ),
        ],
      ),
    );
  }
}

class _HistoricalPowerBestRow extends StatelessWidget {
  const _HistoricalPowerBestRow({required this.value});
  final HistoricalPowerDurationBest value;

  @override
  Widget build(BuildContext context) {
    final best = value.best;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GiuliaTokens.spacingS),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(width: 62, child: Text(_duration(best.duration))),
              Text(
                '${best.averagePowerWatt.toStringAsFixed(0)} W',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: GiuliaTokens.accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(_date(value.achievedAt)),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingXs),
          Text(
            '${best.strokeCount} ${previewText('Züge', 'strokes')} · '
            '${best.cadencePerMinute?.toStringAsFixed(1) ?? '—'} /min · '
            '${best.workPerStrokeJoule?.toStringAsFixed(0) ?? '—'} J/${previewText('Zug', 'stroke')} · '
            '${best.leftShare == null ? '—' : (best.leftShare! * 100).toStringAsFixed(1)} % L · '
            '${previewText('Erstes/letztes Fünftel', 'First/last 20%')} '
            '${value.fatigueDeltaPercent == null ? '—' : '${value.fatigueDeltaPercent! >= 0 ? '+' : ''}${value.fatigueDeltaPercent!.toStringAsFixed(1)} %'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _HistoricalStrokeBestRow extends StatelessWidget {
  const _HistoricalStrokeBestRow({required this.value});
  final HistoricalStrokeCountBest value;

  @override
  Widget build(BuildContext context) {
    final best = value.best;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GiuliaTokens.spacingS),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 82,
                child: Text(
                  '${best.strokeCount} ${previewText(best.strokeCount == 1 ? 'Zug' : 'Züge', best.strokeCount == 1 ? 'stroke' : 'strokes')}',
                ),
              ),
              Text(
                '${best.activePowerWatt.toStringAsFixed(0)} W',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: GiuliaTokens.accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(_date(value.achievedAt)),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingXs),
          Text(
            '${best.workPerStrokeJoule.toStringAsFixed(0)} J/${previewText('Zug', 'stroke')} · '
            'Peak ${best.peakPowerWatt.toStringAsFixed(0)} W · '
            '${best.cadencePerMinute?.toStringAsFixed(1) ?? '—'} /min · '
            '${best.leftShare == null ? '—' : (best.leftShare! * 100).toStringAsFixed(1)} % L · '
            '${previewText('Formstreuung', 'Shape variation')} '
            '${best.shapeVariationPercent?.toStringAsFixed(1) ?? '—'} % RMS',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ErcolinaPowerCurveChart extends StatelessWidget {
  const _ErcolinaPowerCurveChart({required this.bests});
  final List<HistoricalPowerDurationBest> bests;

  @override
  Widget build(BuildContext context) {
    if (bests.length < 2) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: Text(
            (mircoPreview
                ? 'Not enough recorded durations for a curve yet.'
                : 'Noch zu wenige Zeitfenster für eine Kurve.'),
          ),
        ),
      );
    }
    final minimum = bests
        .map((value) => value.best.averagePowerWatt)
        .reduce(math.min);
    final maximum = bests
        .map((value) => value.best.averagePowerWatt)
        .reduce(math.max);
    final scale = NiceScale.forRange(minimum, maximum, targetTicks: 5);
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: previewText(
        'Persönliche Ercolina Bestleistung nach Zeitfenster in Watt, logarithmische Zeitachse',
        'Personal Ercolina power bests by duration in watts, logarithmic time axis',
      ),
      child: SizedBox(
        height: 250,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 48,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final tick in scale.ticks.reversed)
                      Text(
                        tick == scale.ticks.last
                            ? '${scale.format(tick)} W'
                            : scale.format(tick),
                        style: text.labelSmall,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: GiuliaTokens.spacingS),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: CustomPaint(
                      painter: _ErcolinaPowerCurvePainter(
                        bests: bests,
                        scale: scale,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  const SizedBox(height: GiuliaTokens.spacingXs),
                  const SizedBox(
                    height: 16,
                    child: CustomPaint(painter: _ErcolinaLogAxisPainter()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErcolinaLogAxisPainter extends CustomPainter {
  const _ErcolinaLogAxisPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const points = <(double, String)>[
      (5, '5 s'),
      (30, '30 s'),
      (60, '1 min'),
      (300, '5 min'),
      (1200, '20 min'),
    ];
    final denominator = math.log(1200 / 5);
    for (final (index, point) in points.indexed) {
      final fraction = math.log(point.$1 / 5) / denominator;
      _paintText(
        canvas,
        point.$2,
        Offset(size.width * fraction, 0),
        GiuliaTokens.textMuted,
        anchor: index == 0
            ? 0
            : index == points.length - 1
            ? 1
            : .5,
      );
    }
  }

  @override
  bool shouldRepaint(_ErcolinaLogAxisPainter oldDelegate) => false;
}

class _ErcolinaPowerCurvePainter extends CustomPainter {
  const _ErcolinaPowerCurvePainter({required this.bests, required this.scale});
  final List<HistoricalPowerDurationBest> bests;
  final NiceScale scale;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = GiuliaTokens.chartGrid
      ..strokeWidth = 1;
    for (var index = 0; index < scale.ticks.length; index++) {
      final y = size.height * index / (scale.ticks.length - 1);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final minimumSeconds = 5.0;
    final maximumSeconds = 20 * 60.0;
    double x(Duration duration) =>
        (math.log(duration.inSeconds / minimumSeconds) /
            math.log(maximumSeconds / minimumSeconds)) *
        size.width;
    double y(double watt) =>
        size.height * (1 - scale.normalize(watt).clamp(0.0, 1.0));
    final ordered = [...bests]
      ..sort((a, b) => a.best.duration.compareTo(b.best.duration));
    final path = Path();
    for (final (index, value) in ordered.indexed) {
      final point = Offset(
        x(value.best.duration),
        y(value.best.averagePowerWatt),
      );
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = GiuliaTokens.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );
    final pointPaint = Paint()..color = GiuliaTokens.accent;
    for (final value in ordered) {
      canvas.drawCircle(
        Offset(x(value.best.duration), y(value.best.averagePowerWatt)),
        4,
        pointPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ErcolinaPowerCurvePainter oldDelegate) =>
      oldDelegate.bests != bests || oldDelegate.scale != scale;
}

class _ErcolinaPowerTrendChart extends StatelessWidget {
  const _ErcolinaPowerTrendChart({required this.history});
  final Map<Duration, List<HistoricalPowerDurationBest>> history;

  static const _wanted = <Duration>[
    Duration(seconds: 5),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 20),
  ];
  static const _colours = <Color>[
    GiuliaTokens.sideLeft,
    GiuliaTokens.warning,
    GiuliaTokens.accent,
    GiuliaTokens.sideRight,
  ];

  @override
  Widget build(BuildContext context) {
    final series = <Duration, List<HistoricalPowerDurationBest>>{
      for (final duration in _wanted)
        if ((history[duration]?.length ?? 0) >= 2) duration: history[duration]!,
    };
    if (series.isEmpty) return const SizedBox.shrink();
    final all = series.values.expand((values) => values).toList();
    final first = all
        .map((value) => value.achievedAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final last = all
        .map((value) => value.achievedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final minimum = all
        .map((value) => value.best.averagePowerWatt)
        .reduce(math.min);
    final maximum = all
        .map((value) => value.best.averagePowerWatt)
        .reduce(math.max);
    final scale = NiceScale.forRange(minimum, maximum, targetTicks: 5);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: GiuliaTokens.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            previewText('ENTWICKLUNG ÜBER DIE ZEIT', 'POWER OVER TIME'),
            style: text.labelMedium,
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          Wrap(
            spacing: GiuliaTokens.spacingM,
            runSpacing: GiuliaTokens.spacingXs,
            children: [
              for (final (index, duration) in series.keys.indexed)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 12, height: 3, color: _colours[index]),
                    const SizedBox(width: GiuliaTokens.spacingXs),
                    Text(_duration(duration), style: text.labelSmall),
                  ],
                ),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          Semantics(
            label: previewText(
              'Beste mittlere Ercolina Leistung gleicher Zeitfenster über das Datum in Watt',
              'Best average Ercolina power for equal durations over time, in watts',
            ),
            child: SizedBox(
              height: 230,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 48,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final tick in scale.ticks.reversed)
                            Text(
                              tick == scale.ticks.last
                                  ? '${scale.format(tick)} W'
                                  : scale.format(tick),
                              style: text.labelSmall,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: GiuliaTokens.spacingS),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: CustomPaint(
                            painter: _ErcolinaPowerTrendPainter(
                              series: series,
                              first: first,
                              last: last,
                              scale: scale,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                        const SizedBox(height: GiuliaTokens.spacingXs),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_shortDate(first), style: text.labelSmall),
                            Text(_shortDate(last), style: text.labelSmall),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Text(
            previewText(
              'x: Datum · y: beste mittlere mechanische Leistung (W) im jeweils gleichen Zeitfenster',
              'x: date · y: best average mechanical power (W), compared over equal durations',
            ),
            style: text.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ErcolinaPowerTrendPainter extends CustomPainter {
  const _ErcolinaPowerTrendPainter({
    required this.series,
    required this.first,
    required this.last,
    required this.scale,
  });

  final Map<Duration, List<HistoricalPowerDurationBest>> series;
  final DateTime first;
  final DateTime last;
  final NiceScale scale;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = GiuliaTokens.chartGrid
      ..strokeWidth = 1;
    for (var index = 0; index < scale.ticks.length; index++) {
      final y = size.height * index / (scale.ticks.length - 1);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final span = last.difference(first).inMicroseconds.clamp(1, 1 << 62);
    double x(DateTime date) =>
        date.difference(first).inMicroseconds / span * size.width;
    double y(double watt) =>
        size.height * (1 - scale.normalize(watt).clamp(0.0, 1.0));
    for (final (seriesIndex, values) in series.values.indexed) {
      final ordered = [...values]
        ..sort((a, b) => a.achievedAt.compareTo(b.achievedAt));
      final colour = _ErcolinaPowerTrendChart._colours[seriesIndex];
      final path = Path();
      for (final (index, value) in ordered.indexed) {
        final point = Offset(
          x(value.achievedAt),
          y(value.best.averagePowerWatt),
        );
        if (index == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final dots = Paint()..color = colour;
      for (final value in ordered) {
        canvas.drawCircle(
          Offset(x(value.achievedAt), y(value.best.averagePowerWatt)),
          3,
          dots,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ErcolinaPowerTrendPainter oldDelegate) =>
      oldDelegate.series != series ||
      oldDelegate.first != first ||
      oldDelegate.last != last ||
      oldDelegate.scale != scale;
}

String _shortDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.'
    '${value.month.toString().padLeft(2, '0')}.${value.year}';

String _duration(Duration value) =>
    value.inSeconds < 60 ? '${value.inSeconds} s' : '${value.inMinutes} min';

String _date(DateTime? date) => date == null
    ? 'Nicht erfasst'
    : '${date.day.toString().padLeft(2, '0')}.'
          '${date.month.toString().padLeft(2, '0')}.${date.year}';

void _paintText(
  Canvas canvas,
  String text,
  Offset offset,
  Color color, {
  double maxWidth = double.infinity,
  TextAlign align = TextAlign.left,
  double anchor = 0,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      // In Widget-Tests ist die Standardschrift Ahem. Explizit dieselbe
      // Schrift wie im Produkt setzen, damit Achsen und Einheiten auch im
      // visuellen Regressionstest wirklich lesbar sind.
      style: TextStyle(
        color: color,
        fontSize: 10,
        height: 1.2,
        fontFamily: GiuliaTokens.fontFamily,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: align,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  painter.paint(canvas, Offset(offset.dx - painter.width * anchor, offset.dy));
}
