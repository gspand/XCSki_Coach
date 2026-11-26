/// Complete, evidence-labelled metabolic and Ercolina technique profile.
///
/// The screen is intentionally conservative: it visualises measured values
/// and transparent ratios over the athlete's complete comparable history.
/// Unsupported physiological models remain visible as unavailable instead of
/// being replaced by plausible-looking estimates.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:xc_coach/lala/application/lala_controller.dart';
import 'package:xc_coach/lala/application/lala_view_models.dart';
import 'package:xc_coach/lala/application/metabolic_technique_profile.dart';
import 'package:xc_coach/ui/design_system.dart';
import 'package:xc_coach/ui/lala/lala_widgets.dart';

class LalaMetabolicTechniqueScreen extends StatelessWidget {
  const LalaMetabolicTechniqueScreen({
    super.key,
    required this.controller,
    required this.athleteId,
  });

  final LalaController controller;
  final String athleteId;

  @override
  Widget build(BuildContext context) {
    final overview = controller.overviewFor(athleteId);
    final profile = MetabolicTechniqueProfile.fromOverview(
      overview: overview,
      loadTest: controller.loadTest,
    );
    final latest = profile.latestTest;
    if (latest == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Metabolik & Technik')),
        body: const Padding(
          padding: EdgeInsets.all(GiuliaTokens.spacingL),
          child: GiuliaEmptyState(
            icon: Icons.science_outlined,
            title: 'Noch keine vollständige Auswertung',
            description:
                'Für das Athletenprofil wird mindestens ein ausgewerteter '
                'Stufentest benötigt.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Metabolik & Technik')),
      body: ListView(
        key: const Key('metabolic-technique-profile'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
        children: [
          _ProfileHeader(profile: profile),
          const SizedBox(height: GiuliaTokens.spacingM),
          const _EvidenceLegend(),
          const SizedBox(height: GiuliaTokens.spacingL),
          _SectionTitle(
            title: 'Aktuelles physiologisches Profil',
            detail: 'Test vom ${formatTestDate(latest.head.startedAtUtcUs)}',
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          _MetricGrid(profile: profile),
          const SizedBox(height: GiuliaTokens.spacingL),
          _MethodAndQualitySection(profile: profile),
          const SizedBox(height: GiuliaTokens.spacingL),
          _LatestCurves(profile: profile),
          const SizedBox(height: GiuliaTokens.spacingL),
          _LongitudinalSection(profile: profile),
          const SizedBox(height: GiuliaTokens.spacingL),
          _RecoverySection(profile: profile),
          const SizedBox(height: GiuliaTokens.spacingL),
          _TechniqueSection(profile: profile),
          const SizedBox(height: GiuliaTokens.spacingL),
          const _UnavailableModels(),
          const SizedBox(height: GiuliaTokens.spacingL),
          const _InterpretationBoundary(),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});
  final MetabolicTechniqueProfile profile;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    tone: GiuliaTokens.textPrimary,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          profile.athleteName,
          style: Theme.of(
            context,
          ).textTheme.headlineLarge?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        Text(
          'Vollständige dokumentierte Zeit · '
          '${profile.timeline.length} vergleichbare '
          '${profile.timeline.length == 1 ? 'Messung' : 'Messungen'}',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: GiuliaTokens.spacingM),
        Text(
          'Schwellen, Herzfrequenz, Laktat, Erholung und '
          'Ercolina-Zugdynamik in einem Profil.',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: Colors.white),
        ),
      ],
    ),
  );
}

class _EvidenceLegend extends StatelessWidget {
  const _EvidenceLegend();

  @override
  Widget build(BuildContext context) => const GiuliaPanel(
    padding: EdgeInsets.all(GiuliaTokens.spacingM),
    child: Wrap(
      spacing: GiuliaTokens.spacingM,
      runSpacing: GiuliaTokens.spacingS,
      children: [
        _EvidenceChip(ProfileEvidence.measured),
        _EvidenceChip(ProfileEvidence.calculated),
        _EvidenceChip(ProfileEvidence.notValidated),
      ],
    ),
  );
}

class _EvidenceChip extends StatelessWidget {
  const _EvidenceChip(this.evidence);
  final ProfileEvidence evidence;

  @override
  Widget build(BuildContext context) {
    final (label, colour, icon) = switch (evidence) {
      ProfileEvidence.measured => (
        'GEMESSEN',
        GiuliaTokens.success,
        Icons.sensors_outlined,
      ),
      ProfileEvidence.calculated => (
        'BERECHNET',
        GiuliaTokens.accent,
        Icons.functions,
      ),
      ProfileEvidence.notValidated => (
        'NICHT VALIDIERT',
        GiuliaTokens.textMuted,
        Icons.lock_outline,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colour.withValues(alpha: .45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colour),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colour,
              fontWeight: FontWeight.w700,
              letterSpacing: .5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.detail});
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      const SizedBox(width: GiuliaTokens.spacingM),
      Text(
        detail,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
      ),
    ],
  );
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.profile});
  final MetabolicTechniqueProfile profile;

  @override
  Widget build(BuildContext context) {
    final run = profile.latestRun;
    final unit = profile.loadUnit ?? '';
    final metrics = <Widget>[
      _MetricCard(
        label: 'LT1',
        value: formatLoad(run?.lt1?.loadValue, unit),
        detail: _heartRate(run?.lt1?.heartRateBpm),
        evidence: ProfileEvidence.calculated,
        colour: GiuliaTokens.success,
      ),
      _MetricCard(
        label: 'LT2',
        value: formatLoad(run?.lt2?.loadValue, unit),
        detail: _heartRate(run?.lt2?.heartRateBpm),
        evidence: ProfileEvidence.calculated,
        colour: GiuliaTokens.warning,
      ),
      _MetricCard(
        label: 'Höchste abgeschlossene Stufe',
        value: formatLoad(profile.peakCompletedLoad, unit),
        detail: profile.peakPerKg == null
            ? 'Testleistung, kein VO2max-Wert'
            : '${_number(profile.peakPerKg!, 2)} W/kg · Testleistung',
        evidence: ProfileEvidence.measured,
        colour: GiuliaTokens.accent,
      ),
      _MetricCard(
        label: 'LT1 / LT2',
        value: _percent(profile.lt1ToLt2Ratio),
        detail: 'transparentes Leistungsverhältnis',
        evidence: ProfileEvidence.calculated,
        colour: GiuliaTokens.sideRight,
      ),
      _MetricCard(
        label: 'LT2 / Spitzenstufe',
        value: _percent(profile.lt2ToPeakRatio),
        detail: 'beobachtete Hochintensitätsreserve',
        evidence: ProfileEvidence.calculated,
        colour: GiuliaTokens.sideLeft,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - (columns - 1) * GiuliaTokens.spacingM) /
            columns;
        return Wrap(
          spacing: GiuliaTokens.spacingM,
          runSpacing: GiuliaTokens.spacingM,
          children: [
            for (final metric in metrics) SizedBox(width: width, child: metric),
          ],
        );
      },
    );
  }

  static String _heartRate(int? value) =>
      value == null ? 'HF nicht dokumentiert' : '$value bpm';
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.evidence,
    required this.colour,
  });

  final String label;
  final String value;
  final String detail;
  final ProfileEvidence evidence;
  final Color colour;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            _EvidenceChip(evidence),
          ],
        ),
        const SizedBox(height: GiuliaTokens.spacingM),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: colour,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: GiuliaTokens.spacingXs),
        Text(detail, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _MethodAndQualitySection extends StatelessWidget {
  const _MethodAndQualitySection({required this.profile});
  final MetabolicTechniqueProfile profile;

  @override
  Widget build(BuildContext context) {
    final test = profile.latestTest!;
    final run = profile.latestRun;
    if (run == null) {
      return const _HonestEmpty(
        text:
            'Für diesen Test ist noch kein reproduzierbarer Auswertungslauf '
            'gespeichert.',
      );
    }
    final excluded = test.data.stages.where((stage) => stage.excluded).length;
    final partial = test.data.stages.where((stage) => stage.partial).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: 'Methoden & Datenbasis',
          detail: 'Engine ${run.engineVersion} · Auswertung ${run.runIndex}',
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        GiuliaPanel(
          key: const Key('metabolic-method-provenance'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: GiuliaTokens.spacingL,
                runSpacing: GiuliaTokens.spacingM,
                children: [
                  if (run.lt1 case final threshold?)
                    _ThresholdMethodSummary(threshold: threshold),
                  if (run.lt2 case final threshold?)
                    _ThresholdMethodSummary(threshold: threshold),
                ],
              ),
              const SizedBox(height: GiuliaTokens.spacingM),
              const Divider(),
              const SizedBox(height: GiuliaTokens.spacingS),
              Wrap(
                spacing: GiuliaTokens.spacingL,
                runSpacing: GiuliaTokens.spacingS,
                children: [
                  _DataFact(label: 'analysierte Stufen', value: run.stageCount),
                  _DataFact(label: 'ausgeschlossen', value: excluded),
                  _DataFact(label: 'teilweise', value: partial),
                  _DataFact(
                    label: 'Methoden ohne Ergebnis',
                    value: run.methodsWithoutResult.length,
                  ),
                ],
              ),
              const SizedBox(height: GiuliaTokens.spacingM),
              Text(
                'Input-Fingerprint: ${run.inputFingerprint}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: GiuliaTokens.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: GiuliaTokens.spacingXs),
              Text(
                'Output-Fingerprint: ${run.outputFingerprint}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: GiuliaTokens.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThresholdMethodSummary extends StatelessWidget {
  const _ThresholdMethodSummary({required this.threshold});
  final LalaThresholdView threshold;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 310),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              threshold.typeLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(width: GiuliaTokens.spacingS),
            LalaMethodChip(threshold: threshold),
          ],
        ),
        const SizedBox(height: GiuliaTokens.spacingXs),
        Text(threshold.methodLabel),
        Text(
          'Methode ${threshold.methodVersion} · ${threshold.status}',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
        ),
      ],
    ),
  );
}

class _DataFact extends StatelessWidget {
  const _DataFact({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '$value ',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        TextSpan(text: label),
      ],
    ),
    style: Theme.of(context).textTheme.bodyMedium,
  );
}

class _LatestCurves extends StatelessWidget {
  const _LatestCurves({required this.profile});
  final MetabolicTechniqueProfile profile;

  @override
  Widget build(BuildContext context) {
    final test = profile.latestTest!;
    final excluded = test.curve.where((point) => point.excluded).toList();
    final loadUnit = test.head.loadUnit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          title: 'Aktueller Stufentest',
          detail: 'Messpunkte werden linear verbunden',
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        _ResponsiveCharts(
          children: [
            ScientificChart(
              key: const Key('metabolic-lactate-chart'),
              title: 'Laktatprofil',
              subtitle:
                  'Keine Glättung · ausgeschlossene Punkte bleiben sichtbar',
              xAxisLabel: 'Belastung [$loadUnit]',
              yAxisLabel: 'Laktat [mmol/l]',
              series: [
                ChartSeries(
                  label: 'verwendet',
                  colour: GiuliaTokens.accent,
                  points: _chartPointsWithGaps(
                    test.curve,
                    x: (point) => point.load,
                    y: (point) => point.excluded ? null : point.lactate,
                  ),
                ),
                ChartSeries(
                  label: 'ausgeschlossen',
                  colour: GiuliaTokens.error,
                  connect: false,
                  points: [
                    for (final point in excluded)
                      ChartPoint(point.load, point.lactate),
                  ],
                ),
              ],
              verticalReferences: [
                if (profile.latestRun?.lt1?.loadValue case final value?)
                  ChartReference(value, 'LT1', GiuliaTokens.success),
                if (profile.latestRun?.lt2?.loadValue case final value?)
                  ChartReference(value, 'LT2', GiuliaTokens.warning),
              ],
            ),
            ScientificChart(
              key: const Key('metabolic-heart-rate-chart'),
              title: 'Herzfrequenzprofil',
              subtitle: 'Nur pro Stufe gespeicherte HF-Werte',
              xAxisLabel: 'Belastung [$loadUnit]',
              yAxisLabel: 'Herzfrequenz [bpm]',
              series: [
                ChartSeries(
                  label: 'HF',
                  colour: GiuliaTokens.heartRate,
                  points: _chartPointsWithGaps(
                    test.curve,
                    x: (point) => point.load,
                    y: (point) =>
                        point.excluded ? null : point.heartRateBpm?.toDouble(),
                  ),
                ),
                ChartSeries(
                  label: 'ausgeschlossen',
                  colour: GiuliaTokens.error,
                  connect: false,
                  points: [
                    for (final point in excluded)
                      if (point.heartRateBpm case final heartRate?)
                        ChartPoint(point.load, heartRate.toDouble()),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _LongitudinalSection extends StatelessWidget {
  const _LongitudinalSection({required this.profile});
  final MetabolicTechniqueProfile profile;

  @override
  Widget build(BuildContext context) {
    final timeline = profile.timeline;
    final unit = profile.loadUnit ?? '';
    double x(DateTime date) =>
        date.millisecondsSinceEpoch / Duration.millisecondsPerDay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: 'Entwicklung über die gesamte Zeit',
          detail:
              '${timeline.length} vergleichbare Tests · kein 12-Wochen-Limit',
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        _ResponsiveCharts(
          children: [
            ScientificChart(
              key: const Key('metabolic-all-time-thresholds'),
              title: 'Schwellenleistung',
              subtitle: 'Nur protokollgleiche, numerisch vergleichbare Tests',
              xAxisLabel: 'Testdatum',
              yAxisLabel: 'Belastung [$unit]',
              xFormatter: _dateFromDay,
              series: [
                ChartSeries(
                  label: 'LT1',
                  colour: GiuliaTokens.success,
                  points: _chartPointsWithGaps(
                    timeline,
                    x: (point) => x(point.atUtc),
                    y: (point) => point.lt1Load,
                  ),
                ),
                ChartSeries(
                  label: 'LT2',
                  colour: GiuliaTokens.warning,
                  points: _chartPointsWithGaps(
                    timeline,
                    x: (point) => x(point.atUtc),
                    y: (point) => point.lt2Load,
                  ),
                ),
                ChartSeries(
                  label: 'höchste Stufe',
                  colour: GiuliaTokens.accent,
                  points: _chartPointsWithGaps(
                    timeline,
                    x: (point) => x(point.atUtc),
                    y: (point) => point.peakCompletedLoad,
                  ),
                ),
              ],
            ),
            ScientificChart(
              key: const Key('metabolic-all-time-heart-rate'),
              title: 'Herzfrequenz an den Schwellen',
              subtitle: 'Fehlende HF bleibt eine Lücke',
              xAxisLabel: 'Testdatum',
              yAxisLabel: 'Herzfrequenz [bpm]',
              xFormatter: _dateFromDay,
              series: [
                ChartSeries(
                  label: 'HF an LT1',
                  colour: GiuliaTokens.sideRight,
                  points: _chartPointsWithGaps(
                    timeline,
                    x: (point) => x(point.atUtc),
                    y: (point) => point.lt1HeartRate?.toDouble(),
                  ),
                ),
                ChartSeries(
                  label: 'HF an LT2',
                  colour: GiuliaTokens.heartRate,
                  points: _chartPointsWithGaps(
                    timeline,
                    x: (point) => x(point.atUtc),
                    y: (point) => point.lt2HeartRate?.toDouble(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _RecoverySection extends StatelessWidget {
  const _RecoverySection({required this.profile});
  final MetabolicTechniqueProfile profile;

  @override
  Widget build(BuildContext context) {
    final points = profile.recovery;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          title: 'Erholungslaktat',
          detail: 'beobachteter Verlauf, keine Clearance-Modellierung',
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        if (!profile.recoveryTimingAvailable)
          const _HonestEmpty(
            text:
                'Erholungsproben sind gespeichert, aber das Ende der letzten '
                'Belastungsstufe hat keinen Zeitstempel. GIULIA erzeugt '
                'deshalb keine erfundene Minutenachse.',
          )
        else if (points.isEmpty)
          const _HonestEmpty(
            text:
                'Für den letzten Test sind keine zeitlich zuordenbaren '
                'Erholungsproben gespeichert.',
          )
        else
          ScientificChart(
            key: const Key('metabolic-recovery-chart'),
            title: 'Laktat nach Belastungsende',
            subtitle: '${points.length} gespeicherte Proben',
            xAxisLabel: 'Zeit nach Belastungsende [min]',
            yAxisLabel: 'Laktat [mmol/l]',
            series: [
              ChartSeries(
                label: 'Erholungslaktat',
                colour: GiuliaTokens.warning,
                points: [
                  for (final point in points)
                    ChartPoint(
                      point.minutesAfterEffort,
                      point.lactateMmolPerLitre,
                    ),
                ],
              ),
            ],
          ),
      ],
    );
  }
}

class _TechniqueSection extends StatelessWidget {
  const _TechniqueSection({required this.profile});
  final MetabolicTechniqueProfile profile;

  @override
  Widget build(BuildContext context) {
    final stages = profile.technique;
    final partial = stages
        .where((stage) => !stage.excluded && stage.partial)
        .toList();
    final excluded = stages.where((stage) => stage.excluded).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          title: 'Ercolina-Zugdynamik',
          detail: 'pro Stufe · ausgeschlossene Stufen nicht verbunden',
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        if (stages.isEmpty)
          const _HonestEmpty(
            text:
                'Dieser Test enthält keine gespeicherten Ercolina-'
                'Zugdynamikwerte.',
          )
        else
          _ResponsiveCharts(
            children: [
              ScientificChart(
                key: const Key('technique-power-dynamics-chart'),
                title: 'Leistungsdynamik je Stufe',
                subtitle: 'Mittelwert, Spitze und stabile Endphase',
                xAxisLabel: 'Stufe [Nr.]',
                yAxisLabel: 'Leistung [W]',
                series: [
                  ChartSeries(
                    label: 'Mittel',
                    colour: GiuliaTokens.accent,
                    points: _chartPointsWithGaps(
                      stages,
                      x: (stage) => stage.stageNumber.toDouble(),
                      y: (stage) => stage.excluded || stage.partial
                          ? null
                          : stage.meanPowerWatt,
                    ),
                  ),
                  ChartSeries(
                    label: 'Spitze',
                    colour: GiuliaTokens.warning,
                    points: _chartPointsWithGaps(
                      stages,
                      x: (stage) => stage.stageNumber.toDouble(),
                      y: (stage) => stage.excluded || stage.partial
                          ? null
                          : stage.peakPowerWatt,
                    ),
                  ),
                  ChartSeries(
                    label: 'Endphase',
                    colour: GiuliaTokens.success,
                    points: _chartPointsWithGaps(
                      stages,
                      x: (stage) => stage.stageNumber.toDouble(),
                      y: (stage) => stage.excluded || stage.partial
                          ? null
                          : stage.steadyEndPowerWatt,
                    ),
                  ),
                  ChartSeries(
                    label: 'teilweise · Mittel',
                    colour: GiuliaTokens.warning,
                    connect: false,
                    points: [
                      for (final stage in partial)
                        if (stage.meanPowerWatt case final value?)
                          ChartPoint(stage.stageNumber.toDouble(), value),
                    ],
                  ),
                  ChartSeries(
                    label: 'ausgeschlossen · Mittel',
                    colour: GiuliaTokens.error,
                    connect: false,
                    points: [
                      for (final stage in excluded)
                        if (stage.meanPowerWatt case final value?)
                          ChartPoint(stage.stageNumber.toDouble(), value),
                    ],
                  ),
                ],
              ),
              ScientificChart(
                key: const Key('technique-stroke-rate-chart'),
                title: 'Zugfrequenz',
                subtitle: 'Gespeicherter Stufenmittelwert',
                xAxisLabel: 'Stufe [Nr.]',
                yAxisLabel: 'Züge [1/min]',
                series: [
                  ChartSeries(
                    label: 'Zugfrequenz',
                    colour: GiuliaTokens.sideRight,
                    points: _chartPointsWithGaps(
                      stages,
                      x: (stage) => stage.stageNumber.toDouble(),
                      y: (stage) => stage.excluded || stage.partial
                          ? null
                          : stage.strokeRatePerMinute,
                    ),
                  ),
                  ChartSeries(
                    label: 'teilweise',
                    colour: GiuliaTokens.warning,
                    connect: false,
                    points: [
                      for (final stage in partial)
                        if (stage.strokeRatePerMinute case final value?)
                          ChartPoint(stage.stageNumber.toDouble(), value),
                    ],
                  ),
                  ChartSeries(
                    label: 'ausgeschlossen',
                    colour: GiuliaTokens.error,
                    connect: false,
                    points: [
                      for (final stage in excluded)
                        if (stage.strokeRatePerMinute case final value?)
                          ChartPoint(stage.stageNumber.toDouble(), value),
                    ],
                  ),
                ],
              ),
              ScientificChart(
                key: const Key('technique-symmetry-chart'),
                title: 'Links-/Rechts-Arbeitsanteil',
                subtitle: '50 % entspricht gleicher Arbeit beider Seiten',
                xAxisLabel: 'Stufe [Nr.]',
                yAxisLabel: 'Linksanteil [%]',
                yFormatter: (value) => _number(value, 0),
                series: [
                  ChartSeries(
                    label: 'Links',
                    colour: GiuliaTokens.sideLeft,
                    points: _chartPointsWithGaps(
                      stages,
                      x: (stage) => stage.stageNumber.toDouble(),
                      y: (stage) => stage.excluded || stage.partial
                          ? null
                          : stage.leftWorkShare == null
                          ? null
                          : stage.leftWorkShare! * 100,
                    ),
                  ),
                  ChartSeries(
                    label: 'teilweise',
                    colour: GiuliaTokens.warning,
                    connect: false,
                    points: [
                      for (final stage in partial)
                        if (stage.leftWorkShare case final value?)
                          ChartPoint(stage.stageNumber.toDouble(), value * 100),
                    ],
                  ),
                  ChartSeries(
                    label: 'ausgeschlossen',
                    colour: GiuliaTokens.error,
                    connect: false,
                    points: [
                      for (final stage in excluded)
                        if (stage.leftWorkShare case final value?)
                          ChartPoint(stage.stageNumber.toDouble(), value * 100),
                    ],
                  ),
                ],
                horizontalReferences: const [
                  ChartReference(50, '50 %', GiuliaTokens.chartReference),
                ],
              ),
              ScientificChart(
                key: const Key('technique-retention-chart'),
                title: 'Endphasen-Retention',
                subtitle: 'Endphasenleistung / Spitzenleistung je Stufe',
                xAxisLabel: 'Stufe [Nr.]',
                yAxisLabel: 'Retention [%]',
                yFormatter: (value) => _number(value, 0),
                series: [
                  ChartSeries(
                    label: 'Retention',
                    colour: GiuliaTokens.accent,
                    points: _chartPointsWithGaps(
                      stages,
                      x: (stage) => stage.stageNumber.toDouble(),
                      y: (stage) => stage.excluded || stage.partial
                          ? null
                          : stage.endPowerRetention == null
                          ? null
                          : stage.endPowerRetention! * 100,
                    ),
                  ),
                  ChartSeries(
                    label: 'teilweise',
                    colour: GiuliaTokens.warning,
                    connect: false,
                    points: [
                      for (final stage in partial)
                        if (stage.endPowerRetention case final value?)
                          ChartPoint(stage.stageNumber.toDouble(), value * 100),
                    ],
                  ),
                  ChartSeries(
                    label: 'ausgeschlossen',
                    colour: GiuliaTokens.error,
                    connect: false,
                    points: [
                      for (final stage in excluded)
                        if (stage.endPowerRetention case final value?)
                          ChartPoint(stage.stageNumber.toDouble(), value * 100),
                    ],
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }
}

class _UnavailableModels extends StatelessWidget {
  const _UnavailableModels();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _SectionTitle(
        title: 'Noch nicht als Messwert verfügbar',
        detail: 'sichtbar gesperrt statt geschätzt',
      ),
      const SizedBox(height: GiuliaTokens.spacingS),
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth >= 760
              ? (constraints.maxWidth - GiuliaTokens.spacingM) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: GiuliaTokens.spacingM,
            runSpacing: GiuliaTokens.spacingM,
            children: [
              for (final item in const [
                (
                  'VO2max',
                  'Keine validierte direkte oder indirekte GIULIA-Methode.',
                ),
                (
                  'VLamax',
                  'Aus dem aktuellen Stufentest nicht valide ableitbar.',
                ),
                (
                  'FatMax',
                  'Erfordert ein validiertes Stoffwechselmodell bzw. Gasaustausch.',
                ),
                (
                  'Glykogenverbrauch',
                  'Ohne validiertes Substratmodell keine seriöse Zahl.',
                ),
              ])
                SizedBox(
                  width: width,
                  child: _UnavailableCard(title: item.$1, reason: item.$2),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({required this.title, required this.reason});
  final String title;
  final String reason;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    tone: GiuliaTokens.surface3,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_outline, color: GiuliaTokens.textMuted),
        const SizedBox(width: GiuliaTokens.spacingM),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: GiuliaTokens.spacingXs),
              Text(reason, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: GiuliaTokens.spacingS),
              const _EvidenceChip(ProfileEvidence.notValidated),
            ],
          ),
        ),
      ],
    ),
  );
}

class _InterpretationBoundary extends StatelessWidget {
  const _InterpretationBoundary();

  @override
  Widget build(BuildContext context) => const GiuliaPanel(
    tone: GiuliaTokens.accentSoft,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.fact_check_outlined, color: GiuliaTokens.accent),
        SizedBox(width: GiuliaTokens.spacingM),
        Expanded(
          child: Text(
            'Diese Ansicht trennt Rohmessung und Berechnung. Sie zeigt keine '
            'medizinische Diagnose und ersetzt keine sportärztliche '
            'Leistungsdiagnostik. Fehlende Werte bleiben fehlend.',
          ),
        ),
      ],
    ),
  );
}

class _HonestEmpty extends StatelessWidget {
  const _HonestEmpty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    tone: GiuliaTokens.surface2,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, color: GiuliaTokens.textMuted),
        const SizedBox(width: GiuliaTokens.spacingM),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _ResponsiveCharts extends StatelessWidget {
  const _ResponsiveCharts({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900 ? 2 : 1;
      final width =
          (constraints.maxWidth - (columns - 1) * GiuliaTokens.spacingM) /
          columns;
      return Wrap(
        spacing: GiuliaTokens.spacingM,
        runSpacing: GiuliaTokens.spacingM,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class ChartPoint {
  const ChartPoint(this.x, this.y, {this.connectFromPrevious = true});
  final double x;
  final double y;

  /// False after a missing, partial or excluded observation. This prevents
  /// the chart from visually bridging a gap that exists in the record.
  final bool connectFromPrevious;
}

class ChartSeries {
  const ChartSeries({
    required this.label,
    required this.colour,
    required this.points,
    this.connect = true,
  });

  final String label;
  final Color colour;
  final List<ChartPoint> points;
  final bool connect;
}

class ChartReference {
  const ChartReference(this.value, this.label, this.colour);
  final double value;
  final String label;
  final Color colour;
}

class ScientificChart extends StatelessWidget {
  const ScientificChart({
    super.key,
    required this.title,
    required this.subtitle,
    required this.xAxisLabel,
    required this.yAxisLabel,
    required this.series,
    this.xFormatter = _defaultTick,
    this.yFormatter = _defaultTick,
    this.verticalReferences = const [],
    this.horizontalReferences = const [],
  });

  final String title;
  final String subtitle;
  final String xAxisLabel;
  final String yAxisLabel;
  final List<ChartSeries> series;
  final String Function(double) xFormatter;
  final String Function(double) yFormatter;
  final List<ChartReference> verticalReferences;
  final List<ChartReference> horizontalReferences;

  @override
  Widget build(BuildContext context) {
    final visible = series.where((entry) => entry.points.isNotEmpty).toList();
    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: GiuliaTokens.spacingXs),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: GiuliaTokens.spacingM),
          if (visible.isEmpty)
            const SizedBox(
              height: 220,
              child: Center(child: Text('Keine dokumentierten Messpunkte')),
            )
          else
            SizedBox(
              height: 280,
              child: CustomPaint(
                painter: _ScientificChartPainter(
                  series: visible,
                  xAxisLabel: xAxisLabel,
                  yAxisLabel: yAxisLabel,
                  xFormatter: xFormatter,
                  yFormatter: yFormatter,
                  verticalReferences: verticalReferences,
                  horizontalReferences: horizontalReferences,
                ),
              ),
            ),
          if (visible.isNotEmpty) ...[
            const SizedBox(height: GiuliaTokens.spacingS),
            Wrap(
              spacing: GiuliaTokens.spacingM,
              runSpacing: GiuliaTokens.spacingXs,
              children: [
                for (final entry in visible)
                  _ChartLegend(colour: entry.colour, label: entry.label),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.colour, required this.label});
  final Color colour;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 18,
        height: 3,
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _ScientificChartPainter extends CustomPainter {
  const _ScientificChartPainter({
    required this.series,
    required this.xAxisLabel,
    required this.yAxisLabel,
    required this.xFormatter,
    required this.yFormatter,
    required this.verticalReferences,
    required this.horizontalReferences,
  });

  final List<ChartSeries> series;
  final String xAxisLabel;
  final String yAxisLabel;
  final String Function(double) xFormatter;
  final String Function(double) yFormatter;
  final List<ChartReference> verticalReferences;
  final List<ChartReference> horizontalReferences;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 60.0;
    const top = 14.0;
    const right = 14.0;
    const bottom = 50.0;
    final plot = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final points = [for (final entry in series) ...entry.points];
    var minX = points.map((point) => point.x).reduce(math.min);
    var maxX = points.map((point) => point.x).reduce(math.max);
    var minY = points.map((point) => point.y).reduce(math.min);
    var maxY = points.map((point) => point.y).reduce(math.max);
    for (final reference in verticalReferences) {
      minX = math.min(minX, reference.value);
      maxX = math.max(maxX, reference.value);
    }
    for (final reference in horizontalReferences) {
      minY = math.min(minY, reference.value);
      maxY = math.max(maxY, reference.value);
    }
    final xPadding = maxX == minX ? 1.0 : (maxX - minX) * .04;
    final yPadding = maxY == minY ? 1.0 : (maxY - minY) * .08;
    minX -= xPadding;
    maxX += xPadding;
    minY = math.max(0, minY - yPadding);
    maxY += yPadding;

    double px(double x) => plot.left + (x - minX) / (maxX - minX) * plot.width;
    double py(double y) =>
        plot.bottom - (y - minY) / (maxY - minY) * plot.height;

    final grid = Paint()
      ..color = GiuliaTokens.chartGrid
      ..strokeWidth = 1;
    final axis = Paint()
      ..color = GiuliaTokens.borderStrong
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final fraction = index / 4;
      final x = plot.left + plot.width * fraction;
      final y = plot.bottom - plot.height * fraction;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _paintText(
        canvas,
        xFormatter(minX + (maxX - minX) * fraction),
        Offset(x, plot.bottom + 7),
        align: TextAlign.center,
        width: 72,
      );
      _paintText(
        canvas,
        yFormatter(minY + (maxY - minY) * fraction),
        Offset(0, y - 7),
        align: TextAlign.right,
        width: left - 8,
      );
    }
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axis);
    canvas.drawLine(plot.bottomLeft, plot.topLeft, axis);

    for (final reference in verticalReferences) {
      final paint = Paint()
        ..color = reference.colour.withValues(alpha: .65)
        ..strokeWidth = 1;
      final x = px(reference.value);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), paint);
      _paintText(
        canvas,
        reference.label,
        Offset(x + 3, plot.top + 2),
        colour: reference.colour,
        width: 42,
      );
    }
    for (final reference in horizontalReferences) {
      final paint = Paint()
        ..color = reference.colour.withValues(alpha: .65)
        ..strokeWidth = 1;
      final y = py(reference.value);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), paint);
      _paintText(
        canvas,
        reference.label,
        Offset(plot.right - 44, y - 15),
        colour: reference.colour,
        width: 44,
        align: TextAlign.right,
      );
    }

    canvas.save();
    canvas.clipRect(plot.inflate(4));
    for (final entry in series) {
      final sorted = [...entry.points]..sort((a, b) => a.x.compareTo(b.x));
      final paint = Paint()
        ..color = entry.colour
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (entry.connect && sorted.length > 1) {
        final path = Path()..moveTo(px(sorted.first.x), py(sorted.first.y));
        for (final point in sorted.skip(1)) {
          if (point.connectFromPrevious) {
            path.lineTo(px(point.x), py(point.y));
          } else {
            path.moveTo(px(point.x), py(point.y));
          }
        }
        canvas.drawPath(path, paint);
      }
      final dot = Paint()..color = entry.colour;
      for (final point in sorted) {
        canvas.drawCircle(Offset(px(point.x), py(point.y)), 3.7, dot);
        canvas.drawCircle(
          Offset(px(point.x), py(point.y)),
          3.7,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
    canvas.restore();

    _paintText(
      canvas,
      xAxisLabel,
      Offset(plot.left, size.height - 17),
      align: TextAlign.center,
      width: plot.width,
      colour: GiuliaTokens.textSecondary,
    );
    canvas.save();
    canvas.translate(14, plot.bottom);
    canvas.rotate(-math.pi / 2);
    _paintText(
      canvas,
      yAxisLabel,
      Offset(0, 0),
      align: TextAlign.center,
      width: plot.height,
      colour: GiuliaTokens.textSecondary,
    );
    canvas.restore();
  }

  void _paintText(
    Canvas canvas,
    String value,
    Offset offset, {
    double width = 60,
    TextAlign align = TextAlign.left,
    Color colour = GiuliaTokens.textMuted,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(fontSize: 10, color: colour),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
    )..layout(maxWidth: width);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_ScientificChartPainter oldDelegate) =>
      oldDelegate.series != series ||
      oldDelegate.xAxisLabel != xAxisLabel ||
      oldDelegate.yAxisLabel != yAxisLabel;
}

String _percent(double? value) =>
    value == null ? '—' : '${_number(value * 100, 1)} %';

List<ChartPoint> _chartPointsWithGaps<T>(
  Iterable<T> source, {
  required double Function(T value) x,
  required double? Function(T value) y,
}) {
  final ordered = source.toList()..sort((a, b) => x(a).compareTo(x(b)));
  final result = <ChartPoint>[];
  var previousWasPresent = false;
  for (final value in ordered) {
    final measured = y(value);
    if (measured == null) {
      previousWasPresent = false;
      continue;
    }
    result.add(
      ChartPoint(x(value), measured, connectFromPrevious: previousWasPresent),
    );
    previousWasPresent = true;
  }
  return result;
}

String _number(double value, int digits) =>
    value.toStringAsFixed(digits).replaceAll('.', ',');

String _defaultTick(double value) {
  final absolute = value.abs();
  final digits = absolute >= 100
      ? 0
      : absolute >= 10
      ? 1
      : 2;
  return _number(value, digits);
}

String _dateFromDay(double value) {
  final date = DateTime.fromMillisecondsSinceEpoch(
    (value * Duration.millisecondsPerDay).round(),
    isUtc: true,
  );
  return '${date.day.toString().padLeft(2, '0')}.'
      '${date.month.toString().padLeft(2, '0')}.'
      '${date.year.toString().substring(2)}';
}
