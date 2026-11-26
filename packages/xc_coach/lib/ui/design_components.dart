/// The reusable GIULIA building blocks: metrics, balance, chart containers,
/// interpretation and sections.
///
/// Every screen composes these instead of setting its own sizes and colours.
/// Numbers dominate, units and labels step back, and a value that cannot be
/// computed is shown as a dash — never as NaN, a negative share or 107 %.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../branding.dart';
import 'design_system.dart';

// ------------------------------------------------------------------ values

const String giuliaMissing = '—';

bool giuliaIsValid(num? value) => value != null && value.isFinite;

/// A number for display, or a dash when there is none to show.
String giuliaNumber(num? value, {int decimals = 0, bool comma = false}) {
  if (!giuliaIsValid(value)) return giuliaMissing;
  final text = decimals == 0
      ? value!.round().toString()
      : value!.toStringAsFixed(decimals);
  return comma ? text.replaceAll('.', ',') : text;
}

/// The left part of a two-sided quantity, 0..1 — only when both sides were
/// measured and neither is negative. Anything else is a data-quality problem,
/// not a share.
double? giuliaShare(num? part, num? other) {
  if (!giuliaIsValid(part) || !giuliaIsValid(other)) return null;
  if (part! < 0 || other! < 0) return null;
  final total = part + other;
  if (total <= 0) return null;
  return part / total;
}

/// A share that is already 0..1, or null if it is not a possible share.
double? giuliaValidShare(num? share) =>
    giuliaIsValid(share) && share! >= 0 && share <= 1 ? share.toDouble() : null;

/// A percentage that must lie within 0..100 (symmetry, distribution).
double? giuliaValidPercent(num? percent) =>
    giuliaIsValid(percent) && percent! >= 0 && percent <= 100
    ? percent.toDouble()
    : null;

// ---------------------------------------------------------------- metrics

enum GiuliaMetricSize {
  hero(GiuliaTokens.metricHero),
  primary(GiuliaTokens.metricPrimary),
  secondary(GiuliaTokens.metricSecondary);

  const GiuliaMetricSize(this.fontSize);
  final double fontSize;
}

/// A number with its unit on one baseline; the unit clearly smaller.
class GiuliaValue extends StatelessWidget {
  const GiuliaValue({
    super.key,
    required this.value,
    this.unit,
    this.fontSize = GiuliaTokens.metricSecondary,
    this.colour,
    this.textAlign,
  });

  final String value;
  final String? unit;
  final double fontSize;
  final Color? colour;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final missing = value == giuliaMissing;
    return Text.rich(
      TextSpan(
        text: value,
        style: text.displayLarge?.copyWith(
          fontSize: fontSize,
          height: 1,
          letterSpacing: fontSize >= 40 ? -1.2 : -.3,
          color: missing
              ? GiuliaTokens.textMuted
              : colour ?? GiuliaTokens.textPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        children: <InlineSpan>[
          if (unit != null && unit!.isNotEmpty && !missing)
            TextSpan(
              text: ' $unit',
              style: text.titleMedium?.copyWith(
                fontSize: math.max(11, fontSize * GiuliaTokens.unitRatio),
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
                color: GiuliaTokens.textSecondary,
              ),
            ),
        ],
      ),
      maxLines: 1,
      textAlign: textAlign,
    );
  }
}

/// The one number a screen is about.
class GiuliaHeroMetric extends StatelessWidget {
  const GiuliaHeroMetric({
    super.key,
    required this.value,
    required this.label,
    this.unit,
    this.trend,
    this.trendTone,
    this.status,
    this.statusTone,
    this.fontSize = GiuliaTokens.metricHero,
    this.colour,
    this.alignment = CrossAxisAlignment.start,
  });

  final String value;
  final String? unit;
  final String label;

  /// Change against a reference, already formatted ("+12 W").
  final String? trend;
  final Color? trendTone;

  /// A short qualifier under the label ("Zu wenige gültige Züge").
  final String? status;
  final Color? statusTone;
  final double fontSize;
  final Color? colour;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final center = alignment == CrossAxisAlignment.center;
    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: center ? Alignment.center : Alignment.centerLeft,
          child: GiuliaValue(
            value: value,
            unit: unit,
            fontSize: fontSize,
            colour: colour,
          ),
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(), style: text.labelMedium),
            if (trend != null) ...[
              const SizedBox(width: GiuliaTokens.spacingS),
              Text(
                trend!,
                style: text.labelMedium?.copyWith(
                  color: trendTone ?? GiuliaTokens.textSecondary,
                ),
              ),
            ],
          ],
        ),
        if (status != null) ...[
          const SizedBox(height: GiuliaTokens.spacingXs),
          Text(
            status!,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: text.bodySmall?.copyWith(
              color: statusTone ?? GiuliaTokens.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

/// One number with its unit and, underneath, what it is.
class GiuliaMetric extends StatelessWidget {
  const GiuliaMetric({
    super.key,
    required this.value,
    required this.label,
    this.unit,
    this.tone,
    this.size = GiuliaMetricSize.secondary,
    this.caption,
  });

  final String value;
  final String label;
  final String? unit;
  final Color? tone;
  final GiuliaMetricSize size;

  /// Small line under the label, e.g. why a value is missing.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: GiuliaValue(
            value: value,
            unit: unit,
            fontSize: size.fontSize,
            colour: tone,
          ),
        ),
        const SizedBox(height: GiuliaTokens.spacingXs + 2),
        Text(
          label.toUpperCase(),
          style: text.labelMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (caption != null) ...[
          const SizedBox(height: 2),
          Text(caption!, style: text.bodySmall),
        ],
      ],
    );
  }
}

/// Two to four metrics side by side; two per row when the space is narrow.
class GiuliaMetricRow extends StatelessWidget {
  const GiuliaMetricRow({
    super.key,
    required this.children,
    this.minItemWidth = 132,
    this.spacing = GiuliaTokens.spacingL,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final perRow = math.max(
        1,
        math.min(
          children.length,
          ((constraints.maxWidth + spacing) / (minItemWidth + spacing)).floor(),
        ),
      );
      if (perRow >= children.length) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, child) in children.indexed) ...[
              if (index > 0) SizedBox(width: spacing),
              Expanded(child: child),
            ],
          ],
        );
      }
      final width = (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
      return Wrap(
        spacing: spacing,
        runSpacing: GiuliaTokens.spacingM,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

// ---------------------------------------------------------------- balance

/// Left against right: two percentages and one thin bar.
///
/// An impossible share (missing side, negative work, NaN) is drawn as an
/// empty bar with dashes and the reason, never as a number.
class GiuliaBalance extends StatelessWidget {
  const GiuliaBalance({
    super.key,
    required this.leftShare,
    this.leftLabel = 'LINKS',
    this.rightLabel = 'RECHTS',
    this.caption,
    this.unavailableReason = 'Zu wenige gültige Züge',
    this.fontSize = GiuliaTokens.metricSecondary,
  });

  /// Left share of the whole, 0..1.
  final double? leftShare;
  final String leftLabel;
  final String rightLabel;

  /// Centered line under the bar, e.g. "91 % Symmetrie".
  final String? caption;
  final String unavailableReason;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final share = giuliaValidShare(leftShare);
    String percent(double? value) =>
        value == null ? giuliaMissing : '${(value * 100).round()}';
    Widget side(String label, Color colour, String value, bool left) => Column(
      crossAxisAlignment: left
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (left) _Dot(colour: colour),
            if (left) const SizedBox(width: 6),
            Text(label, style: text.labelMedium),
            if (!left) const SizedBox(width: 6),
            if (!left) _Dot(colour: colour),
          ],
        ),
        const SizedBox(height: GiuliaTokens.spacingXs),
        GiuliaValue(value: value, unit: '%', fontSize: fontSize),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            side(leftLabel, GiuliaTokens.sideLeft, percent(share), true),
            const Spacer(),
            side(
              rightLabel,
              GiuliaTokens.sideRight,
              percent(share == null ? null : 1 - share),
              false,
            ),
          ],
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        GiuliaBalanceBar(leftShare: share),
        if (share == null || caption != null) ...[
          const SizedBox(height: GiuliaTokens.spacingS),
          Text(
            share == null ? unavailableReason : caption!,
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// The bar alone: a neutral track split where the work was split, with a
/// fine mark at the middle.
class GiuliaBalanceBar extends StatelessWidget {
  const GiuliaBalanceBar({super.key, required this.leftShare, this.height = 6});

  final double? leftShare;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: CustomPaint(
      painter: _BalanceBarPainter(giuliaValidShare(leftShare)),
      child: const SizedBox.expand(),
    ),
  );
}

/// Balance in one line: `52 ━━━━│━━━ 48`, left percent in the left colour.
class GiuliaBalanceGauge extends StatelessWidget {
  const GiuliaBalanceGauge({
    super.key,
    required this.leftShare,
    this.fontSize = 15,
    this.barHeight = 8,
  });

  final double? leftShare;
  final double fontSize;
  final double barHeight;

  @override
  Widget build(BuildContext context) {
    final share = giuliaValidShare(leftShare);
    Widget percent(double? value, Color colour) => SizedBox(
      width: fontSize * 1.9,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: GiuliaValue(
          value: value == null ? giuliaMissing : '${(value * 100).round()}',
          fontSize: fontSize,
          colour: colour,
        ),
      ),
    );
    return Row(
      children: [
        percent(share, GiuliaTokens.sideLeft),
        const SizedBox(width: GiuliaTokens.spacingS),
        Expanded(
          child: share == null
              ? GiuliaBalanceBar(leftShare: null, height: barHeight)
              : TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: share),
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) =>
                      GiuliaBalanceBar(leftShare: value, height: barHeight),
                ),
        ),
        const SizedBox(width: GiuliaTokens.spacingS),
        percent(share == null ? null : 1 - share, GiuliaTokens.sideRight),
      ],
    );
  }
}

class _BalanceBarPainter extends CustomPainter {
  const _BalanceBarPainter(this.leftShare);

  final double? leftShare;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final track = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas.drawRRect(track, Paint()..color = GiuliaTokens.sideNeutral);
    final share = leftShare;
    if (share != null) {
      const gap = 2.0;
      final split = size.width * share;
      canvas.save();
      canvas.clipRRect(track);
      canvas.drawRect(
        Rect.fromLTRB(0, 0, math.max(0, split - gap / 2), size.height),
        Paint()..color = GiuliaTokens.sideLeft,
      );
      canvas.drawRect(
        Rect.fromLTRB(
          math.min(size.width, split + gap / 2),
          0,
          size.width,
          size.height,
        ),
        Paint()..color = GiuliaTokens.sideRight,
      );
      canvas.restore();
    }
    final middle = size.width / 2;
    canvas.drawLine(
      Offset(middle, -2),
      Offset(middle, size.height + 2),
      Paint()
        ..color = GiuliaTokens.surface1
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_BalanceBarPainter old) => old.leftShare != leftShare;
}

class _Dot extends StatelessWidget {
  const _Dot({required this.colour});
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
  );
}

// ----------------------------------------------------------------- charts

/// A series swatch for chart legends.
class GiuliaLegendItem extends StatelessWidget {
  const GiuliaLegendItem({
    super.key,
    required this.label,
    required this.colour,
  });

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 2,
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}

/// One frame for every chart: title, legend, range, chart, interpretation.
class GiuliaChartCard extends StatelessWidget {
  const GiuliaChartCard({
    super.key,
    required this.title,
    required this.child,
    this.legend = const <Widget>[],
    this.range,
    this.interpretation,
    this.framed = true,
  });

  final String title;
  final Widget child;
  final List<Widget> legend;

  /// Time span or value range, right-aligned next to the title.
  final String? range;
  final String? interpretation;

  /// False draws the chart on the page ground, without a card.
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(title.toUpperCase(), style: text.labelMedium),
            const Spacer(),
            if (range != null) Text(range!, style: text.bodySmall),
          ],
        ),
        if (legend.isNotEmpty) ...[
          const SizedBox(height: GiuliaTokens.spacingS),
          Wrap(spacing: GiuliaTokens.spacingM, runSpacing: 6, children: legend),
        ],
        const SizedBox(height: GiuliaTokens.spacingM),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
          builder: (context, opacity, child) =>
              Opacity(opacity: opacity, child: child),
          child: child,
        ),
        if (interpretation != null) ...[
          const SizedBox(height: GiuliaTokens.spacingM),
          Text(interpretation!, style: text.bodySmall),
        ],
      ],
    );
    if (!framed) return content;
    return GiuliaPanel(child: content);
  }
}

// ---------------------------------------------------------- interpretation

/// GIULIA's own reading of the numbers: a statement, a sentence, evidence.
class GiuliaInsight extends StatelessWidget {
  const GiuliaInsight({
    super.key,
    required this.title,
    required this.message,
    this.evidence,
    this.tone = GiuliaTokens.accent,
  });

  final String title;
  final String message;
  final String? evidence;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: GiuliaTokens.surface1,
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusCard),
        border: Border.all(color: GiuliaTokens.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              margin: const EdgeInsets.symmetric(
                vertical: GiuliaTokens.spacingM,
              ),
              decoration: BoxDecoration(
                color: tone,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  GiuliaTokens.spacingM,
                  GiuliaTokens.spacingM,
                  GiuliaTokens.spacingL,
                  GiuliaTokens.spacingM,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      giuliaWordmark,
                      style: text.labelSmall?.copyWith(color: tone),
                    ),
                    const SizedBox(height: GiuliaTokens.spacingXs),
                    Text(title, style: text.titleMedium),
                    const SizedBox(height: GiuliaTokens.spacingXs),
                    Text(message, style: text.bodyMedium),
                    if (evidence != null) ...[
                      const SizedBox(height: GiuliaTokens.spacingS),
                      Text(evidence!, style: text.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- layout

/// A titled section. Separation by space and heading — not by another card.
class GiuliaSection extends StatelessWidget {
  const GiuliaSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      GiuliaSectionHeader(title: title, subtitle: subtitle, action: action),
      const SizedBox(height: GiuliaTokens.spacingM),
      child,
    ],
  );
}

/// A quiet segmented control; the selection slides softly.
class GiuliaSegmentedControl<T> extends StatelessWidget {
  const GiuliaSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<GiuliaSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Narrow screens shrink the control instead of breaking the row.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: GiuliaTokens.surface3,
          borderRadius: BorderRadius.circular(GiuliaTokens.radiusButton),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final segment in segments)
              GestureDetector(
                key: segment.key,
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(segment.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: segment.value == selected
                        ? GiuliaTokens.surface1
                        : GiuliaTokens.surface1.withValues(alpha: 0),
                    borderRadius: BorderRadius.circular(
                      GiuliaTokens.radiusButton - 3,
                    ),
                  ),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: text.labelLarge!.copyWith(
                      color: segment.value == selected
                          ? GiuliaTokens.accent
                          : GiuliaTokens.textSecondary,
                    ),
                    child: Text(segment.label),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class GiuliaSegment<T> {
  const GiuliaSegment({required this.value, required this.label, this.key});

  final T value;
  final String label;
  final Key? key;
}

/// Centers content at a readable width on large displays.
class GiuliaContentWidth extends StatelessWidget {
  const GiuliaContentWidth({
    super.key,
    required this.child,
    this.maxWidth = GiuliaTokens.maxContentWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
