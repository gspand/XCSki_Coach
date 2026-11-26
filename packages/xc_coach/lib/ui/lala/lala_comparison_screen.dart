/// Comparison of two lactate tests of the same athlete.
///
/// This screen subtracts stored numbers and names methodological caveats. It
/// deliberately draws **no conclusion**: it does not say "improved", does not
/// suggest a cause and does not judge training. LaLa never said any of that,
/// and a comparison view is the easiest place to accidentally invent a claim.
library;

import 'package:flutter/material.dart';
import 'package:xc_coach/lala/application/lala_controller.dart';
import 'package:xc_coach/lala/application/lala_view_models.dart';
import 'package:xc_coach/ui/design_system.dart';
import 'package:xc_coach/ui/orthography.dart';
import 'package:xc_coach/ui/vocabulary.dart';
import 'package:xc_coach/ui/lala/lala_widgets.dart';

class LalaComparisonScreen extends StatelessWidget {
  const LalaComparisonScreen({
    super.key,
    required this.controller,
    required this.earlierTestId,
    required this.laterTestId,
  });

  final LalaController controller;
  final String earlierTestId;
  final String laterTestId;

  @override
  Widget build(BuildContext context) {
    final comparison = controller.compare(
      earlierTestId: earlierTestId,
      laterTestId: laterTestId,
    );
    final earlier = comparison.earlier;
    final later = comparison.later;

    return Scaffold(
      appBar: AppBar(title: const Text('LaLa-Testvergleich')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          GiuliaPanel(
            child: Row(
              children: [
                Expanded(
                  child: _TestStamp(label: 'VORHER', test: earlier),
                ),
                const Icon(Icons.arrow_forward, color: GiuliaTokens.textMuted),
                Expanded(
                  child: _TestStamp(label: 'NACHHER', test: later),
                ),
              ],
            ),
          ),
          const SizedBox(height: GiuliaTokens.spacingM),

          if (!comparison.comparable)
            GiuliaEmptyState(
              icon: Icons.compare_arrows_outlined,
              title: 'Nicht vergleichbar',
              description: comparison.incomparableReason!,
            )
          else ...[
            _DeltaPanel(comparison: comparison),
            const SizedBox(height: GiuliaTokens.spacingM),

            if (comparison.mixedMethods || comparison.mixedEngineVersions)
              _CaveatPanel(comparison: comparison),
            if (comparison.mixedMethods || comparison.mixedEngineVersions)
              const SizedBox(height: GiuliaTokens.spacingM),

            Text(
              'LAKTATKURVEN',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: GiuliaTokens.spacingS),
            LalaComparisonCurves(
              earlier: earlier.curve,
              later: later.curve,
              earlierLabel: formatTestDate(earlier.head.startedAtUtcUs),
              laterLabel: formatTestDate(later.head.startedAtUtcUs),
              loadUnit: comparison.loadUnit,
              earlierLt1Load: earlier.latestRun?.lt1?.loadValue,
              earlierLt2Load: earlier.latestRun?.lt2?.loadValue,
              laterLt1Load: later.latestRun?.lt1?.loadValue,
              laterLt2Load: later.latestRun?.lt2?.loadValue,
            ),
            const SizedBox(height: GiuliaTokens.spacingM),
            _ZoneShiftPanel(comparison: comparison),
          ],
        ],
      ),
    );
  }
}

class _TestStamp extends StatelessWidget {
  const _TestStamp({required this.label, required this.test});
  final String label;
  final LalaTestView test;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 6),
      Text(
        formatTestDate(test.head.startedAtUtcUs),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      Text(
        sportLabel(test.head.sport),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ],
  );
}

class _DeltaPanel extends StatelessWidget {
  const _DeltaPanel({required this.comparison});
  final LalaComparison comparison;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('VERÄNDERUNG', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: GiuliaTokens.spacingM),
        _DeltaRow(
          key: const Key('lala-delta-lt1'),
          label: 'LTP1',
          before: comparison.earlier.latestRun?.lt1?.loadValue,
          after: comparison.later.latestRun?.lt1?.loadValue,
          unit: comparison.loadUnit,
          delta: comparison.lt1LoadDelta,
          secondary: _hr(comparison.lt1HeartRateDelta),
        ),
        const Divider(height: 20),
        _DeltaRow(
          key: const Key('lala-delta-lt2'),
          label: 'LTP2',
          before: comparison.earlier.latestRun?.lt2?.loadValue,
          after: comparison.later.latestRun?.lt2?.loadValue,
          unit: comparison.loadUnit,
          delta: comparison.lt2LoadDelta,
          secondary: _hr(comparison.lt2HeartRateDelta),
        ),
        const SizedBox(height: GiuliaTokens.spacingM),
        Text(
          'Angegeben sind ausschließlich Differenzen der gespeicherten Werte. '
          'Eine Bewertung nimmt LaLa nicht vor und diese Ansicht daher '
          'ebenfalls nicht.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );

  static String _hr(int? delta) {
    if (delta == null) return 'HF —';
    final sign = delta > 0
        ? '+'
        : delta < 0
        ? '−'
        : '±';
    return 'HF $sign${delta.abs()} bpm';
  }
}

class _DeltaRow extends StatelessWidget {
  const _DeltaRow({
    super.key,
    required this.label,
    required this.before,
    required this.after,
    required this.unit,
    required this.delta,
    required this.secondary,
  });

  final String label;
  final double? before;
  final double? after;
  final String unit;
  final double? delta;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final percent = before == null || after == null || before == 0
        ? null
        : (after! - before!) / before! * 100;
    final tone = delta == null || delta == 0
        ? GiuliaTokens.textMuted
        : delta! > 0
        ? GiuliaTokens.success
        : GiuliaTokens.warning;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 64, child: Text(label, style: text.titleMedium)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'von ${formatLoad(before, unit)} auf ${formatLoad(after, unit)}',
                style: text.headlineMedium?.copyWith(
                  fontSize: GiuliaTokens.metricM,
                ),
              ),
              const SizedBox(height: GiuliaTokens.spacingXs),
              Wrap(
                spacing: GiuliaTokens.spacingS,
                runSpacing: GiuliaTokens.spacingXs,
                children: [
                  GiuliaChip(
                    formatLoadDelta(delta, unit),
                    tone: delta == null ? null : tone,
                  ),
                  if (percent != null)
                    GiuliaChip(
                      '${percent >= 0 ? '+' : '−'}${percent.abs().toStringAsFixed(1).replaceAll('.', ',')} %',
                      tone: tone,
                    ),
                  GiuliaChip(secondary),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Names the reasons a numeric difference may not mean what it looks like.
class _CaveatPanel extends StatelessWidget {
  const _CaveatPanel({required this.comparison});
  final LalaComparison comparison;

  @override
  Widget build(BuildContext context) {
    final earlier = comparison.earlier.latestRun;
    final later = comparison.later.latestRun;
    return Container(
      key: const Key('lala-comparison-caveat'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GiuliaTokens.warning.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
        border: Border.all(color: GiuliaTokens.warning.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'METHODISCHER HINWEIS',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          if (comparison.mixedMethods)
            Text(
              'Die beiden Auswertungen verwendeten nicht dieselben Methoden '
              '(vorher LT1 ${germanLabel(earlier?.lt1?.methodLabel ?? '—')} / LT2 '
              '${germanLabel(earlier?.lt2?.methodLabel ?? '—')}, nachher LT1 '
              '${germanLabel(later?.lt1?.methodLabel ?? '—')} / LT2 '
              '${germanLabel(later?.lt2?.methodLabel ?? '—')}). Ein Teil der Differenz kann '
              'daher methodisch bedingt sein.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          if (comparison.mixedMethods && comparison.mixedEngineVersions)
            const SizedBox(height: 8),
          if (comparison.mixedEngineVersions)
            Text(
              'Die Auswertungen stammen aus unterschiedlichen '
              'LaLa-Versionen (${earlier?.engineVersion} und '
              '${later?.engineVersion}).',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }
}

class _ZoneShiftPanel extends StatelessWidget {
  const _ZoneShiftPanel({required this.comparison});
  final LalaComparison comparison;

  @override
  Widget build(BuildContext context) {
    final before = comparison.earlier.latestRun?.zoneSets;
    final after = comparison.later.latestRun?.zoneSets;
    if (before == null || after == null || before.isEmpty || after.isEmpty) {
      return const SizedBox.shrink();
    }
    final beforeSet = before.first;
    final afterSet = after.firstWhere(
      (set) => set.modelId == beforeSet.modelId,
      orElse: () => after.first,
    );
    final text = Theme.of(context).textTheme;

    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TRAININGSZONEN', style: text.labelMedium),
          const SizedBox(height: 4),
          Text(afterSet.modelName, style: text.titleMedium),
          const SizedBox(height: GiuliaTokens.spacingM),
          for (var index = 0; index < afterSet.zones.length; index++) ...[
            Builder(
              builder: (context) {
                final zone = afterSet.zones[index];
                final previous = index < beforeSet.zones.length
                    ? beforeSet.zones[index]
                    : null;
                final delta =
                    (zone.lowerLoadExact != null &&
                        previous?.lowerLoadExact != null)
                    ? zone.lowerLoadExact! - previous!.lowerLoadExact!
                    : null;
                return Row(
                  children: [
                    Expanded(flex: 4, child: Text(zone.name)),
                    Expanded(
                      flex: 3,
                      child: Text(
                        formatLoad(zone.lowerLoadDisplay, zone.loadUnit),
                        style: text.bodyMedium,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        formatLoadDelta(delta, zone.loadUnit),
                        textAlign: TextAlign.right,
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
                );
              },
            ),
            if (index < afterSet.zones.length - 1) const Divider(height: 14),
          ],
          const SizedBox(height: GiuliaTokens.spacingS),
          Text(
            'Verschiebung der unteren Zonengrenze gegenüber dem Vortest.',
            style: text.bodyMedium,
          ),
        ],
      ),
    );
  }
}
