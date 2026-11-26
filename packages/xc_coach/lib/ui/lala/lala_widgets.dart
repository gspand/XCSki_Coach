/// Shared presentation widgets of the LaLa module.
///
/// One rule governs everything in this file: **draw only what was measured or
/// stored.** The lactate curve connects measured points with straight
/// segments, never with a smoothed spline — a spline would show a curve fit on
/// screen that the engine may never have performed, and a reader would take
/// the picture for the analysis.
library;

import 'package:flutter/material.dart';
import 'package:xc_coach/charts/lactate_curve_chart.dart';
import 'package:xc_coach/domain/diagnostics.dart';
import 'package:xc_coach/ui/load_language.dart';
import 'package:xc_coach/ui/orthography.dart';
import 'package:xc_coach/database/diagnostics_repository.dart';
import 'package:xc_coach/lala/application/lala_view_models.dart';
import 'package:xc_coach/ui/design_system.dart';

/// Small label describing where a shown method came from.
class LalaMethodChip extends StatelessWidget {
  const LalaMethodChip({super.key, required this.threshold});

  final LalaThresholdView threshold;

  @override
  Widget build(BuildContext context) {
    final (label, colour) = switch (threshold.origin) {
      LalaMethodOrigin.standard => ('STANDARDMETHODE', GiuliaTokens.success),
      LalaMethodOrigin.fallback => ('FALLBACK-METHODE', GiuliaTokens.warning),
      LalaMethodOrigin.expert => ('EXPERTENAUSWAHL', GiuliaTokens.accent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: colour.withValues(alpha: .45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          letterSpacing: .9,
          fontWeight: FontWeight.w600,
          color: colour,
        ),
      ),
    );
  }
}

/// The result a lactate test is read for, in one glance: LT2 as the large
/// number, its second reading, heart rate and lactate, and — quietly — the
/// method. LT1 stands beside it as the secondary threshold.
class LalaThresholdHero extends StatelessWidget {
  const LalaThresholdHero({
    super.key,
    required this.lt2,
    this.lt1,
    this.bodyMassKg,
  });

  final LalaThresholdView? lt2;
  final LalaThresholdView? lt1;
  final double? bodyMassKg;

  static (String, String?) _split(String formatted) {
    final space = formatted.lastIndexOf(' ');
    return space < 0
        ? (formatted, null)
        : (formatted.substring(0, space), formatted.substring(space + 1));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final value = lt2;
    final hasLoad = value?.loadValue != null;
    final (number, unit) = hasLoad
        ? _split(value!.loadLabel)
        : (giuliaMissing, null);
    final second = hasLoad
        ? secondaryLoad(
            value!.loadValue,
            value.loadUnit,
            bodyMassKg: bodyMassKg,
          )
        : null;
    final facts = <String>[
      if (value?.heartRateBpm case final bpm?) '$bpm bpm',
      if (value?.lactateMmolPerLitre case final mmol?)
        '${mmol.toStringAsFixed(2).replaceAll('.', ',')} mmol/l',
    ].join(' · ');
    final lt1Load = lt1?.loadValue == null ? null : _split(lt1!.loadLabel);

    final main = Column(
      key: const Key('lala-threshold-hero'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LT2',
          style: text.labelMedium?.copyWith(color: GiuliaTokens.warning),
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: GiuliaValue(
            value: number,
            unit: unit,
            fontSize: GiuliaTokens.metricHero * .8,
          ),
        ),
        if (second != null) ...[
          const SizedBox(height: GiuliaTokens.spacingXs),
          Text(
            second,
            style: text.headlineSmall?.copyWith(
              color: GiuliaTokens.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        if (facts.isNotEmpty) ...[
          const SizedBox(height: GiuliaTokens.spacingS),
          Text(facts, style: text.bodyLarge),
        ],
        const SizedBox(height: GiuliaTokens.spacingS),
        Text(
          hasLoad
              ? germanLabel(value!.methodLabel)
              : 'LaLa konnte für diesen Test keine Schwelle bestimmen.',
          style: text.bodySmall,
        ),
      ],
    );
    return GiuliaPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final secondary = lt1Load == null
              ? null
              : GiuliaMetric(
                  value: lt1Load.$1,
                  unit: lt1Load.$2,
                  label: 'LT1',
                  tone: GiuliaTokens.success,
                );
          if (secondary == null) return main;
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                main,
                const SizedBox(height: GiuliaTokens.spacingL),
                secondary,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: main),
              const SizedBox(width: GiuliaTokens.spacingL),
              secondary,
            ],
          );
        },
      ),
    );
  }
}

/// A single threshold as persisted, with its method and provenance.
class LalaThresholdCard extends StatelessWidget {
  const LalaThresholdCard({
    super.key,
    required this.threshold,
    this.deltaLabel,
    this.methodOptions = const <LalaThresholdView>[],
    this.onMethodSelected,
    this.bodyMassKg,
  });

  final LalaThresholdView? threshold;

  /// Enables the W/kg reading on a power test. See [secondaryLoad].
  final double? bodyMassKg;

  /// Change against the previous test, already formatted. Null hides the row.
  final String? deltaLabel;
  final List<LalaThresholdView> methodOptions;
  final ValueChanged<String>? onMethodSelected;

  @override
  Widget build(BuildContext context) {
    final value = threshold;
    if (value == null) {
      return const GiuliaPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('—', style: TextStyle(fontSize: GiuliaTokens.metricL)),
            SizedBox(height: 8),
            Text(
              'LaLa konnte für diesen Test keine Schwelle bestimmen.',
              style: TextStyle(color: GiuliaTokens.textSecondary),
            ),
          ],
        ),
      );
    }
    final text = Theme.of(context).textTheme;
    final fallbackNotice = value.origin == LalaMethodOrigin.fallback
        ? value.originNotice
        : null;
    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(value.typeLabel, style: text.labelMedium),
              const Spacer(),
              LalaMethodChip(threshold: value),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value.loadLabel,
            style: text.headlineLarge?.copyWith(fontSize: GiuliaTokens.metricM),
          ),
          if (secondaryLoad(
                value.loadValue,
                value.loadUnit,
                bodyMassKg: bodyMassKg,
              )
              case final spoken?) ...[
            const SizedBox(height: 2),
            Text(
              spoken,
              style: text.titleLarge?.copyWith(
                color: GiuliaTokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 6),
          if (onMethodSelected == null || methodOptions.length < 2)
            Text(germanLabel(value.methodLabel), style: text.titleMedium)
          else ...[
            const SizedBox(height: 2),
            DropdownButtonFormField<String>(
              key: Key('lala-method-${value.typeLabel}-dropdown'),
              initialValue: value.methodId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Auswertungsmethode',
                isDense: true,
              ),
              items: [
                for (final option in methodOptions)
                  DropdownMenuItem(
                    value: option.methodId,
                    child: Text(
                      germanLabel(option.methodLabel),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (methodId) {
                if (methodId != null && methodId != value.methodId) {
                  onMethodSelected!(methodId);
                }
              },
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              if (value.heartRateBpm != null)
                _MicroFact('HF', '${value.heartRateBpm} bpm'),
              if (value.lactateMmolPerLitre != null)
                _MicroFact(
                  'LAKTAT',
                  '${value.lactateMmolPerLitre!.toStringAsFixed(2).replaceAll('.', ',')} mmol/l',
                ),
              if (deltaLabel != null) _MicroFact('ggü. VORTEST', deltaLabel!),
            ],
          ),
          if (fallbackNotice != null) ...[
            const SizedBox(height: 14),
            _OriginNotice(notice: fallbackNotice, isFallback: true),
          ],
        ],
      ),
    );
  }
}

/// A compact, deliberately non-diagnostic reading guide for a stored result.
/// It only reports facts already persisted with the run and its measured
/// stages. It does not assign a medical or performance "grade".
class LalaResultQualityPanel extends StatelessWidget {
  const LalaResultQualityPanel({
    super.key,
    required this.run,
    required this.points,
  });

  final LalaRunView run;
  final List<LalaCurvePoint> points;

  @override
  Widget build(BuildContext context) {
    final excluded = points.where((point) => point.excluded).length;
    final zoneIssueCount = run.zoneSets.fold<int>(
      0,
      (count, set) => count + set.issues.length,
    );
    final provisional = run.zoneSets.any((set) => set.hasProvisionalBoundary);
    final rows = <_QualityFact>[
      _QualityFact(
        icon: Icons.scatter_plot_outlined,
        label: 'Messpunkte',
        value: '${points.length} von ${run.stageCount} Stufen mit Laktatprobe',
        colour: points.length == run.stageCount
            ? GiuliaTokens.success
            : GiuliaTokens.warning,
      ),
      _QualityFact(
        icon: Icons.rule_outlined,
        label: 'Einbezogene Stufen',
        value: excluded == 0
            ? 'Keine Stufe ausgeschlossen'
            : '$excluded Stufe${excluded == 1 ? '' : 'n'} ausgeschlossen',
        colour: excluded == 0 ? GiuliaTokens.success : GiuliaTokens.warning,
      ),
      _QualityFact(
        icon: Icons.functions_outlined,
        label: 'Schwellenmethoden',
        value: run.usedFallback
            ? 'Fallback dokumentiert – Methoden prüfen'
            : 'Standard- bzw. bewusst gewählte Methode',
        colour: run.usedFallback ? GiuliaTokens.warning : GiuliaTokens.success,
      ),
      _QualityFact(
        icon: Icons.tune_outlined,
        label: 'Trainingszonen',
        value: provisional || zoneIssueCount > 0
            ? '$zoneIssueCount Hinweis${zoneIssueCount == 1 ? '' : 'e'}${provisional ? ' · vorläufige Grenze' : ''}'
            : 'Keine gespeicherten Zonenhinweise',
        colour: provisional || zoneIssueCount > 0
            ? GiuliaTokens.warning
            : GiuliaTokens.success,
      ),
    ];
    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AUSWERTUNG EINORDNEN',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          for (final row in rows) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(row.icon, color: row.colour, size: GiuliaTokens.iconM),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodyMedium,
                      children: [
                        TextSpan(
                          text: '${row.label}: ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: row.value),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (row != rows.last) const SizedBox(height: 10),
          ],
          const SizedBox(height: GiuliaTokens.spacingS),
          Text(
            'Diese Übersicht beschreibt die gespeicherte Datengrundlage. Sie ersetzt keine sportwissenschaftliche Beurteilung des Testtags.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _QualityFact {
  const _QualityFact({
    required this.icon,
    required this.label,
    required this.value,
    required this.colour,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color colour;
}

class _MicroFact extends StatelessWidget {
  const _MicroFact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 2),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
    ],
  );
}

/// Explains a fallback or expert choice.
///
/// Styled as information, never as an error: a fallback is documented engine
/// behaviour. Colouring it red would train users to distrust correct results.
class _OriginNotice extends StatelessWidget {
  const _OriginNotice({required this.notice, required this.isFallback});
  final String notice;
  final bool isFallback;

  @override
  Widget build(BuildContext context) {
    final colour = isFallback ? GiuliaTokens.warning : GiuliaTokens.accent;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
        border: Border.all(color: colour.withValues(alpha: .3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: GiuliaTokens.iconS, color: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Text(notice, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Lactate over load, with the persisted thresholds marked.
class LalaLactateCurve extends StatelessWidget {
  const LalaLactateCurve({
    super.key,
    required this.points,
    required this.loadUnit,
    this.lt1Load,
    this.lt2Load,
    this.lt1Lactate,
    this.lt2Lactate,
    this.bodyMassKg,
    this.height = 300,
  });

  final List<LalaCurvePoint> points;
  final String loadUnit;
  final double? lt1Load;
  final double? lt2Load;

  /// The lactate the method settled on, when the run recorded one. Drawn as a
  /// marker on the curve; a threshold that only names a load leaves the reader
  /// guessing where on the curve it sits.
  final double? lt1Lactate;
  final double? lt2Lactate;

  /// Enables the W/kg row on the load axis of a power test.
  final double? bodyMassKg;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return GiuliaPanel(
        child: SizedBox(
          height: height - 48,
          child: const Center(
            child: Text(
              'Für eine Kurve werden mindestens zwei Messpunkte benötigt.',
              textAlign: TextAlign.center,
              style: TextStyle(color: GiuliaTokens.textSecondary),
            ),
          ),
        ),
      );
    }
    final excluded = points.where((point) => point.excluded).length;
    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'LAKTAT-LEISTUNGS-KURVE',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const _LegendDot(colour: GiuliaTokens.chartLine, label: 'LAKTAT'),
              const _LegendDot(colour: GiuliaTokens.error, label: 'HF'),
            ],
          ),
          const SizedBox(height: 10),
          LactateCurveChart.single(
            height: height,
            loadUnit: loadUnit,
            bodyMassKg: bodyMassKg,
            samples: <LactateSample>[
              for (final point in points)
                LactateSample(
                  load: point.load,
                  lactate: point.lactate,
                  heartRateBpm: point.heartRateBpm,
                  stageNumber: point.stageNumber,
                  excluded: point.excluded,
                ),
            ],
            thresholds: <LactateThreshold>[
              if (lt1Load case final load?)
                LactateThreshold(
                  label: 'LT1',
                  load: load,
                  colour: GiuliaTokens.success,
                  lactate: lt1Lactate,
                ),
              if (lt2Load case final load?)
                LactateThreshold(
                  label: 'LT2',
                  load: load,
                  colour: GiuliaTokens.warning,
                  lactate: lt2Lactate,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Messpunkte sind geradlinig verbunden; es wird bewusst keine '
            'geglättete Kurve gezeichnet.'
            '${excluded > 0 ? ' $excluded ausgeschlossene Stufe'
                      '${excluded == 1 ? '' : 'n'} bleiben hohl eingezeichnet.' : ''}'
            ' Tippen zeigt die Werte einer Stufe.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.colour, required this.label});
  final Color colour;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 14, height: 2, color: colour),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}

/// Two tests in **one** set of axes: both lactate curves and both heart-rate
/// curves, superimposed.
///
/// Stacking the two tests as separate charts is the more comfortable
/// implementation and the worse instrument. Two charts of their own are drawn
/// to their own scales, so a rightward shift of the lactate curve — the thing
/// the reader is looking for — is exactly what disappears. Superimposing them
/// on shared axes makes the shift visible as a distance on the screen.
///
/// The same reasoning forces one shared heart-rate scale for both tests. Two
/// heart-rate curves each fitted to their own range would sit on top of each
/// other whatever the athlete's heart did.
///
/// This widget must only be used for tests the comparison rules accepted; it
/// takes the load unit once, for both.
class LalaComparisonCurves extends StatelessWidget {
  const LalaComparisonCurves({
    super.key,
    required this.earlier,
    required this.later,
    required this.earlierLabel,
    required this.laterLabel,
    required this.loadUnit,
    this.earlierLt1Load,
    this.earlierLt2Load,
    this.laterLt1Load,
    this.laterLt2Load,
    this.height = 300,
  });

  final List<LalaCurvePoint> earlier;
  final List<LalaCurvePoint> later;
  final String earlierLabel;
  final String laterLabel;
  final String loadUnit;
  final double? earlierLt1Load;
  final double? earlierLt2Load;
  final double? laterLt1Load;
  final double? laterLt2Load;
  final double height;

  static List<LactateSample> _samples(List<LalaCurvePoint> points) =>
      <LactateSample>[
        for (final point in points)
          LactateSample(
            load: point.load,
            lactate: point.lactate,
            heartRateBpm: point.heartRateBpm,
            stageNumber: point.stageNumber,
            excluded: point.excluded,
          ),
      ];

  static List<LactateThreshold> _thresholds(
    double? lt1,
    double? lt2,
  ) => <LactateThreshold>[
    if (lt1 case final load?)
      LactateThreshold(label: 'LT1', load: load, colour: GiuliaTokens.success),
    if (lt2 case final load?)
      LactateThreshold(label: 'LT2', load: load, colour: GiuliaTokens.warning),
  ];

  @override
  Widget build(BuildContext context) {
    if (earlier.length < 2 || later.length < 2) {
      return GiuliaPanel(
        child: SizedBox(
          height: height - 48,
          child: const Center(
            child: Text(
              'Für eine überlagerte Darstellung werden in beiden Tests '
              'mindestens zwei Messpunkte benötigt.',
              textAlign: TextAlign.center,
              style: TextStyle(color: GiuliaTokens.textSecondary),
            ),
          ),
        ),
      );
    }
    final hasHeartRate =
        earlier.where((point) => point.heartRateBpm != null).length >= 2 &&
        later.where((point) => point.heartRateBpm != null).length >= 2;

    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LAKTAT UND HERZFREQUENZ ÜBERLAGERT',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _LegendDot(
                colour: GiuliaTokens.textMuted,
                label: 'LAKTAT $earlierLabel',
              ),
              _LegendDot(
                colour: GiuliaTokens.chartLine,
                label: 'LAKTAT $laterLabel',
              ),
              if (hasHeartRate) ...[
                _LegendDot(
                  colour: GiuliaTokens.error.withValues(alpha: .35),
                  label: 'HF $earlierLabel',
                ),
                _LegendDot(colour: GiuliaTokens.error, label: 'HF $laterLabel'),
              ],
            ],
          ),
          const SizedBox(height: 14),
          LactateCurveChart(
            key: const Key('lala-comparison-curves'),
            height: height,
            loadUnit: loadUnit,
            // Order matters: the later test is drawn last and is the one the
            // readout follows, because it is the test under discussion.
            series: <LactateSeries>[
              LactateSeries(
                label: earlierLabel,
                samples: _samples(earlier),
                colour: GiuliaTokens.textMuted,
                thresholds: _thresholds(earlierLt1Load, earlierLt2Load),
                emphasis: .45,
              ),
              LactateSeries(
                label: laterLabel,
                samples: _samples(later),
                thresholds: _thresholds(laterLt1Load, laterLt2Load),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Beide Tests stehen auf denselben Achsen. Die waagrechte '
            'Verschiebung der Kurve ist damit als Strecke ablesbar, nicht '
            'nur als Zahl.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class LalaZoneTable extends StatelessWidget {
  const LalaZoneTable({super.key, required this.zoneSet, this.bodyMassKg});

  final LalaZoneSetView zoneSet;

  /// The athlete's mass at the time of the test, when it was recorded. Needed
  /// for the W/kg reading and for nothing else; without it that column is
  /// omitted rather than computed against a guess.
  final double? bodyMassKg;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(zoneSet.modelName, style: text.titleMedium)),
              Text(
                'QUALITÄT: ${zoneSet.quality.toUpperCase()}',
                style: text.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final entry in zoneSet.zones.indexed) ...[
            _ZoneRow(
              zone: entry.$2,
              loadUnit: zoneSet.loadUnit,
              bodyMassKg: bodyMassKg,
              colour: giuliaZoneColour(entry.$1, zoneSet.zones.length),
              tint: giuliaZoneTint(entry.$1, zoneSet.zones.length),
            ),
            if (entry.$2 != zoneSet.zones.last) const SizedBox(height: 3),
          ],
          if (zoneSet.hasProvisionalBoundary) ...[
            const SizedBox(height: 12),
            Text(
              'Mit ° markierte Grenzen hat LaLa als vorläufig gekennzeichnet.',
              style: text.bodyMedium,
            ),
          ],
          for (final issue in zoneSet.issues) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: GiuliaTokens.iconS,
                  color: GiuliaTokens.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    germanSpelling(issue.message),
                    style: text.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({
    required this.zone,
    required this.loadUnit,
    required this.colour,
    required this.tint,
    this.bodyMassKg,
  });
  final PersistedTrainingZone zone;
  final String loadUnit;
  final Color colour;
  final Color tint;
  final double? bodyMassKg;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Ein getoentes Band ueber die volle Breite, links der gesaettigte
    // Balken. Die Intensitaet ist damit ablesbar, bevor eine Zahl gelesen
    // wurde -- und Bildschirm und Bericht benutzen dieselbe Skala.
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: const BorderRadius.horizontal(
          right: Radius.circular(GiuliaTokens.radiusS),
        ),
        border: Border(left: BorderSide(color: colour, width: 5)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The second reading of the same boundaries: pace for a running
          // test, W/kg for a power test. A running coach writes sessions in
          // min/km, so a zone table in km/h alone leaves a conversion to be
          // done by hand once per boundary.
          final spoken = secondaryLoadRange(
            zone.lowerLoadDisplay,
            zone.upperLoadDisplay,
            loadUnit,
            bodyMassKg: bodyMassKg,
          );
          final values = [
            _ZoneValue(
              LoadUnits.isPower(loadUnit) ? 'Leistung' : 'Geschwindigkeit',
              _range(zone.lowerLoadDisplay, zone.upperLoadDisplay, loadUnit),
            ),
            if (spoken != null)
              _ZoneValue(
                secondaryLoadCaption(loadUnit, bodyMassKg: bodyMassKg) ?? '',
                spoken,
              ),
            _ZoneValue(
              'Herzfrequenz',
              _rangeInt(
                zone.lowerHeartRateDisplay,
                zone.upperHeartRateDisplay,
                'bpm',
              ),
            ),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${zone.name}${zone.provisionalBoundary ? ' °' : ''}',
                style: text.titleMedium,
              ),
              if (zone.code != null) Text(zone.code!, style: text.labelMedium),
              const SizedBox(height: 4),
              Wrap(spacing: 20, runSpacing: 6, children: values),
            ],
          );
        },
      ),
    );
  }

  static String _range(double? from, double? to, String unit) {
    if (from == null && to == null) return '—';
    final start = from == null ? '' : formatLoad(from, unit).split(' ').first;
    final end = to == null ? '' : formatLoad(to, unit).split(' ').first;
    if (from == null) return 'bis $end $unit';
    if (to == null) return 'ab $start $unit';
    return '$start – $end $unit';
  }

  static String _rangeInt(int? from, int? to, String unit) {
    if (from == null && to == null) return '—';
    if (from == null) return 'bis $to $unit';
    if (to == null) return 'ab $from $unit';
    return '$from – $to $unit';
  }
}

class _ZoneValue extends StatelessWidget {
  const _ZoneValue(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
      Text(value, style: Theme.of(context).textTheme.bodyMedium),
    ],
  );
}

/// Engine provenance of one run: version, commit, fingerprints.
class LalaProvenancePanel extends StatelessWidget {
  const LalaProvenancePanel({super.key, required this.run});

  final LalaRunView run;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AUSWERTUNG UND HERKUNFT', style: text.labelMedium),
          const SizedBox(height: 14),
          GiuliaStatusLabel(
            label: 'CALCULATION RUN',
            value: '#${run.runIndex}',
          ),
          const SizedBox(height: 12),
          // The full identifier, not just the ordinal: a finding that is
          // quoted years later has to be findable in the archive by name.
          GiuliaStatusLabel(label: 'RUN-ID', value: run.id),
          const SizedBox(height: 12),
          GiuliaStatusLabel(label: 'LALA ENGINE', value: run.engineVersion),
          const SizedBox(height: 12),
          GiuliaStatusLabel(
            label: 'QUELL-COMMIT',
            value: _short(run.engineSourceCommit),
          ),
          const SizedBox(height: 12),
          GiuliaStatusLabel(
            label: 'EINGANGS-FINGERPRINT',
            value: _short(run.inputFingerprint),
          ),
          const SizedBox(height: 12),
          GiuliaStatusLabel(
            label: 'ERGEBNIS-FINGERPRINT',
            value: _short(run.outputFingerprint),
          ),
          const SizedBox(height: 12),
          GiuliaStatusLabel(
            label: 'AUSGEWERTETE STUFEN',
            value: '${run.stageCount}',
          ),
          const SizedBox(height: 14),
          Text(
            'Der Eingangs-Fingerprint identifiziert den Messdatenstand, der '
            'Ergebnis-Fingerprint die Schlussfolgerung. Bleibt der erste gleich '
            'und ändert sich der zweite, hat sich die Engine geändert.',
            style: text.bodyMedium,
          ),
        ],
      ),
    );
  }

  static String _short(String value) =>
      value.length <= 12 ? value : '${value.substring(0, 12)}…';
}

/// Formats a stored UTC microsecond timestamp as a date.
String formatTestDate(int utcMicroseconds) {
  final date = DateTime.fromMicrosecondsSinceEpoch(
    utcMicroseconds,
    isUtc: true,
  ).toLocal();
  return '${_two(date.day)}.${_two(date.month)}.${date.year}';
}

/// Formats a stored UTC microsecond timestamp as date and time.
String formatTestDateTime(int utcMicroseconds) {
  final date = DateTime.fromMicrosecondsSinceEpoch(
    utcMicroseconds,
    isUtc: true,
  ).toLocal();
  return '${formatTestDate(utcMicroseconds)}, '
      '${_two(date.hour)}:${_two(date.minute)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
