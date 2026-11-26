/// Compact and detailed views of the canonical training-load time series.
///
/// These widgets only present the Banister TRIMP EWMA already contained in
/// [XCAthleteState]. They do not turn load balance into a readiness or injury
/// prediction.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../intelligence/load/ewma_load_tracker.dart';
import '../../intelligence/xc_athlete_state/xc_athlete_state.dart';
import '../design_system.dart';

class AthleteLoadSnapshot extends StatelessWidget {
  const AthleteLoadSnapshot({
    super.key,
    required this.athleteState,
    this.onOpenFullEvaluation,
  });

  final XCAthleteState athleteState;
  final VoidCallback? onOpenFullEvaluation;

  @override
  Widget build(BuildContext context) {
    final load = athleteState.trainingLoad.latestBanisterState;
    return GiuliaPanel(
      key: const Key('coach-today-load-snapshot'),
      tone: GiuliaTokens.surface2,
      onTap: onOpenFullEvaluation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'BELASTUNG & FORM',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: GiuliaTokens.accent,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .7,
                  ),
                ),
              ),
              if (onOpenFullEvaluation != null)
                TextButton(
                  key: const Key('open-full-athlete-evaluation'),
                  onPressed: onOpenFullEvaluation,
                  child: const Text('Vollauswertung'),
                ),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SnapshotMetric(
                  label: 'ERMÜDUNG',
                  value: _loadValue(load?.acuteLoad),
                  detail: 'akut · 7 Tage',
                ),
              ),
              const _MetricDivider(),
              Expanded(
                child: _SnapshotMetric(
                  label: 'BELASTUNG',
                  value: _loadValue(load?.chronicLoad),
                  detail: 'Fitness · 42 Tage',
                ),
              ),
              const _MetricDivider(),
              Expanded(
                child: _SnapshotMetric(
                  label: 'FORM*',
                  value: load == null ? '—' : _signed(load.loadBalance),
                  detail: 'Balance',
                  valueColor: load != null && load.loadBalance < 0
                      ? GiuliaTokens.warning
                      : GiuliaTokens.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          Text(
            load == null
                ? 'Noch keine belastbare TRIMP-Zeitreihe. Fehlende Daten '
                      'werden nicht als Erholung gewertet.'
                : '* Form = chronische minus akute Last. Deskriptiver '
                      'Trainingswert, keine medizinische Freigabe.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
          ),
        ],
      ),
    );
  }
}

class AthleteLoadTrendCard extends StatelessWidget {
  const AthleteLoadTrendCard({super.key, required this.athleteState});

  final XCAthleteState athleteState;

  @override
  Widget build(BuildContext context) {
    final allStates = athleteState.trainingLoad.banisterTrimpSeries?.states;
    if (allStates == null || allStates.length < 2) {
      return const GiuliaPanel(
        key: Key('athlete-load-trend-empty'),
        child: Text(
          'Für den Belastungsverlauf sind mindestens zwei beobachtete '
          'Tageszustände erforderlich.',
        ),
      );
    }
    final states = allStates;

    return GiuliaPanel(
      key: const Key('athlete-load-trend'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'BELASTUNGSVERLAUF · GESAMTE HISTORIE',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          Semantics(
            label:
                'Verlauf aus akuter und chronischer Banister-TRIMP-Last '
                'über ${states.length} Tage. Vertikale Achse Banister TRIMP '
                'in Punkten. Horizontale Achse Datum.',
            image: true,
            child: SizedBox(
              height: 220,
              child: CustomPaint(
                painter: _LoadTrendPainter(
                  states: states,
                  gridColor: GiuliaTokens.border,
                  acuteColor: GiuliaTokens.warning,
                  chronicColor: GiuliaTokens.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          const Wrap(
            spacing: GiuliaTokens.spacingL,
            runSpacing: GiuliaTokens.spacingXs,
            children: [
              _Legend(color: GiuliaTokens.warning, label: 'Akut · 7 Tage'),
              _Legend(color: GiuliaTokens.accent, label: 'Chronisch · 42 Tage'),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingXs),
          Text(
            '${_longDate(states.first.date)} bis ${_longDate(states.last.date)} · '
            'EWMA nach Banister · unbekannte Tage halten den letzten Stand '
            'und senken die Konfidenz.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SnapshotMetric extends StatelessWidget {
  const _SnapshotMetric({
    required this.label,
    required this.value,
    required this.detail,
    this.valueColor,
  });

  final String label;
  final String value;
  final String detail;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: GiuliaTokens.textMuted),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: valueColor ?? GiuliaTokens.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
      Text(
        detail,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: GiuliaTokens.textSecondary),
      ),
    ],
  );
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: GiuliaTokens.spacingS),
    child: SizedBox(height: 54, child: VerticalDivider(width: 1)),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 16,
        height: 3,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: GiuliaTokens.spacingXs),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _LoadTrendPainter extends CustomPainter {
  const _LoadTrendPainter({
    required this.states,
    required this.gridColor,
    required this.acuteColor,
    required this.chronicColor,
  });

  final List<EwmaDailyState> states;
  final Color gridColor;
  final Color acuteColor;
  final Color chronicColor;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(62, 12, size.width - 10, size.height - 42);
    final observedMax = states.fold<double>(
      1,
      (value, state) =>
          math.max(value, math.max(state.acuteLoad, state.chronicLoad)),
    );
    final maxValue = _niceLoadAxisMaximum(observedMax);
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    const tickCount = 4;
    for (var i = 0; i <= tickCount; i++) {
      final fraction = i / tickCount;
      final y = plot.bottom - plot.height * fraction;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final value = maxValue * fraction;
      _paintChartText(
        canvas,
        value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1),
        Offset(22, y - 7),
        maxWidth: 34,
        align: TextAlign.right,
        color: GiuliaTokens.textMuted,
        fontSize: 9,
      );
    }

    for (final index in <int>{0, states.length ~/ 2, states.length - 1}) {
      final x = plot.left + plot.width * index / (states.length - 1);
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = gridColor.withValues(alpha: .55)
          ..strokeWidth = 1,
      );
      _paintChartText(
        canvas,
        _shortDate(states[index].date),
        Offset(x - 24, plot.bottom + 6),
        maxWidth: 48,
        align: TextAlign.center,
        color: GiuliaTokens.textMuted,
        fontSize: 9,
      );
    }

    _paintChartText(
      canvas,
      'Datum [TT.MM.]',
      Offset(plot.left, size.height - 14),
      maxWidth: plot.width,
      align: TextAlign.center,
      color: GiuliaTokens.textSecondary,
      fontSize: 10,
      fontWeight: FontWeight.w700,
    );
    canvas.save();
    canvas.translate(9, plot.center.dy);
    canvas.rotate(-math.pi / 2);
    _paintChartText(
      canvas,
      'Banister TRIMP [Punkte]',
      Offset(-plot.height / 2, -6),
      maxWidth: plot.height,
      align: TextAlign.center,
      color: GiuliaTokens.textSecondary,
      fontSize: 10,
      fontWeight: FontWeight.w700,
    );
    canvas.restore();

    Path pathFor(double Function(EwmaDailyState state) valueOf) {
      final path = Path();
      for (var i = 0; i < states.length; i++) {
        final x = states.length == 1
            ? plot.left
            : plot.left + plot.width * i / (states.length - 1);
        final value = valueOf(states[i]).clamp(0.0, maxValue).toDouble();
        final y = plot.bottom - plot.height * value / maxValue;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      return path;
    }

    void drawArea(double Function(EwmaDailyState state) valueOf, Color color) {
      final area = pathFor(valueOf)
        ..lineTo(plot.right, plot.bottom)
        ..lineTo(plot.left, plot.bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..color = color.withValues(alpha: .08)
          ..style = PaintingStyle.fill,
      );
    }

    drawArea((state) => state.chronicLoad, chronicColor);
    drawArea((state) => state.acuteLoad, acuteColor);

    canvas.drawPath(
      pathFor((state) => state.chronicLoad),
      Paint()
        ..color = chronicColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      pathFor((state) => state.acuteLoad),
      Paint()
        ..color = acuteColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final lastX = plot.right;
    for (final (value, color) in [
      (states.last.chronicLoad, chronicColor),
      (states.last.acuteLoad, acuteColor),
    ]) {
      final y =
          plot.bottom -
          plot.height * value.clamp(0.0, maxValue).toDouble() / maxValue;
      canvas.drawCircle(
        Offset(lastX, y),
        4,
        Paint()
          ..color = GiuliaTokens.surface1
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(lastX, y),
        3,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_LoadTrendPainter oldDelegate) =>
      oldDelegate.states != states ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.acuteColor != acuteColor ||
      oldDelegate.chronicColor != chronicColor;
}

String _loadValue(double? value) => value?.toStringAsFixed(1) ?? '—';

String _signed(double value) =>
    '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}';

double _niceLoadAxisMaximum(double value) {
  if (value <= 0) return 1;
  final exponent = math
      .pow(10, (math.log(value) / math.ln10).floor())
      .toDouble();
  final normalised = value / exponent;
  final ceiling = normalised <= 1
      ? 1.0
      : normalised <= 2
      ? 2.0
      : normalised <= 5
      ? 5.0
      : 10.0;
  return ceiling * exponent;
}

String _shortDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.'
    '${value.month.toString().padLeft(2, '0')}.';

String _longDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.'
    '${value.month.toString().padLeft(2, '0')}.${value.year}';

void _paintChartText(
  Canvas canvas,
  String text,
  Offset offset, {
  required double maxWidth,
  TextAlign align = TextAlign.left,
  Color color = GiuliaTokens.textPrimary,
  double fontSize = 10,
  FontWeight fontWeight = FontWeight.w400,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontFamily: GiuliaTokens.fontFamily,
      ),
    ),
    textAlign: align,
    maxLines: 1,
    ellipsis: '…',
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);
  painter.paint(canvas, offset);
}
