import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/athlete_ercolina_profile.dart';
import '../../domain/xc_modality.dart';
import '../../intelligence/xc_athlete_state/elite_analysis_state.dart';
import '../../intelligence/xc_athlete_state/xc_athlete_state.dart';
import '../design_system.dart';
import 'ercolina_longitudinal_profile.dart';
export 'ercolina_longitudinal_profile.dart';

class AthleteEliteLongitudinalSection extends StatelessWidget {
  const AthleteEliteLongitudinalSection({
    super.key,
    required this.athleteState,
    this.onEditPhysiology,
    this.ercolinaProfile,
  });

  final XCAthleteState athleteState;
  final VoidCallback? onEditPhysiology;
  final AthleteErcolinaProfile? ercolinaProfile;

  @override
  Widget build(BuildContext context) {
    final analysis = athleteState.eliteAnalysis;
    if (!analysis.hasHistory) {
      return const GiuliaPanel(
        key: Key('elite-analysis-empty'),
        child: Text(
          'Noch keine auswertbare Trainingshistorie. Fehlende Daten werden '
          'nicht durch Vergleichswerte oder Schätzungen ersetzt.',
        ),
      );
    }
    final all = analysis.allTime!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GiuliaPanel(
          key: const Key('elite-analysis-overview'),
          tone: GiuliaTokens.surface2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GESAMTE DATENHISTORIE',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: GiuliaTokens.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: GiuliaTokens.spacingS),
              Text(
                '${_date(analysis.historyStart)} bis ${_date(analysis.historyEnd)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: GiuliaTokens.spacingM),
              _MetricWrap(
                metrics: [
                  ('Einheiten', '${all.sessionCount}'),
                  (
                    'Trainingszeit',
                    '${all.durationHours.toStringAsFixed(1)} h',
                  ),
                  ('Distanz', '${all.distanceKm.toStringAsFixed(0)} km'),
                  (
                    'Höhenmeter',
                    '${all.elevationGainMetres.toStringAsFixed(0)} m',
                  ),
                  ('Aktive Tage', '${all.activeDays}'),
                  ('Aktive Wochen', '${all.activeWeeks}'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: GiuliaTokens.spacingM),
        _PhysiologyPanel(
          analysis: analysis,
          onEditPhysiology: onEditPhysiology,
        ),
        const SizedBox(height: GiuliaTokens.spacingM),
        _WindowComparison(analysis: analysis),
        const SizedBox(height: GiuliaTokens.spacingM),
        if (ercolinaProfile case final profile?) ...[
          ErcolinaLongitudinalProfile(profile: profile),
          const SizedBox(height: GiuliaTokens.spacingM),
        ],
        AthleteMonthlyVolumeChart(analysis: analysis),
        const SizedBox(height: GiuliaTokens.spacingM),
        AthleteIntensityDistributionChart(analysis: analysis),
        const SizedBox(height: GiuliaTokens.spacingM),
        AthleteAllTimeModalityChart(analysis: analysis),
      ],
    );
  }
}

class AthleteEliteEvidenceSection extends StatelessWidget {
  const AthleteEliteEvidenceSection({super.key, required this.athleteState});

  final XCAthleteState athleteState;

  @override
  Widget build(BuildContext context) {
    final analysis = athleteState.eliteAnalysis;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (analysis.personalBests.isEmpty)
          const GiuliaPanel(
            child: Text('Noch keine belegten Bestwerte in den Messdaten.'),
          )
        else
          for (final best in analysis.personalBests) ...[
            GiuliaPanel(
              key: ValueKey('elite-best-${best.key}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          best.label,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        '${_bestValue(best.value, best.unit)} ${best.unit}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: GiuliaTokens.accent,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GiuliaTokens.spacingXs),
                  Text(
                    '${best.modality.label} · ${_date(best.achievedAt)} · ${best.source}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: GiuliaTokens.textSecondary,
                    ),
                  ),
                  if (best.caveat != null) ...[
                    const SizedBox(height: GiuliaTokens.spacingS),
                    Text(
                      best.caveat!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: GiuliaTokens.warning,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: GiuliaTokens.spacingS),
          ],
        const SizedBox(height: GiuliaTokens.spacingM),
        GiuliaPanel(
          key: const Key('elite-evidence-gaps'),
          tone: GiuliaTokens.surface2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NOCH FEHLENDE ELITE-EVIDENZ',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: GiuliaTokens.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: GiuliaTokens.spacingS),
              if (analysis.missingEvidence.isEmpty)
                const Text('Keine bekannte Evidenzlücke im aktuellen Modell.')
              else
                for (final gap in analysis.missingEvidence)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: GiuliaTokens.spacingXs,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.remove_circle_outline,
                          size: 17,
                          color: GiuliaTokens.warning,
                        ),
                        const SizedBox(width: GiuliaTokens.spacingS),
                        Expanded(child: Text(gap)),
                      ],
                    ),
                  ),
              const SizedBox(height: GiuliaTokens.spacingS),
              Text(
                'Diese Punkte werden nicht geschätzt. Sie werden erst nach '
                'einer passenden Messung Teil der Auswertung.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PhysiologyPanel extends StatelessWidget {
  const _PhysiologyPanel({required this.analysis, this.onEditPhysiology});

  final EliteAnalysisState analysis;
  final VoidCallback? onEditPhysiology;

  @override
  Widget build(BuildContext context) {
    final physiology = analysis.physiology;
    final reserve = physiology.hasHeartRateReserve
        ? physiology.maxHeartRateBpm! - physiology.restingHeartRateBpm!
        : null;
    return GiuliaPanel(
      key: const Key('elite-physiology-profile'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'INDIVIDUELLE PHYSIOLOGISCHE ANKER',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          _MetricWrap(
            metrics: [
              (
                'Körpermasse',
                physiology.bodyMassKg == null
                    ? 'Nicht erfasst'
                    : '${physiology.bodyMassKg!.toStringAsFixed(1)} kg',
              ),
              (
                'HFmax',
                physiology.maxHeartRateBpm == null
                    ? 'Nicht erfasst'
                    : '${physiology.maxHeartRateBpm} bpm',
              ),
              (
                'Ruhe-HF',
                physiology.restingHeartRateBpm == null
                    ? 'Nicht erfasst'
                    : '${physiology.restingHeartRateBpm} bpm',
              ),
              (
                'HF-Reserve',
                reserve == null ? 'Nicht berechenbar' : '$reserve bpm',
              ),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          Text(
            physiology.hasHeartRateReserve
                ? 'TRIMP verwendet die individuell gespeicherte HFmax und Ruhe-HF.'
                : 'Ohne individuelle HFmax und Ruhe-HF berechnet GIULIA keinen Banister-TRIMP aus Bevölkerungswerten.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: physiology.hasHeartRateReserve
                  ? GiuliaTokens.textMuted
                  : GiuliaTokens.warning,
            ),
          ),
          if (onEditPhysiology != null) ...[
            const SizedBox(height: GiuliaTokens.spacingM),
            OutlinedButton.icon(
              key: const Key('edit-athlete-physiology'),
              onPressed: onEditPhysiology,
              icon: const Icon(Icons.monitor_heart_outlined),
              label: const Text('Profilwerte bearbeiten'),
            ),
          ],
        ],
      ),
    );
  }
}

class _WindowComparison extends StatelessWidget {
  const _WindowComparison({required this.analysis});

  final EliteAnalysisState analysis;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    key: const Key('elite-window-comparison'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ZEITFENSTER & PERIODISIERUNG',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: GiuliaTokens.spacingM),
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                columnSpacing: 22,
                columns: const [
                  DataColumn(label: Text('Zeitraum')),
                  DataColumn(label: Text('Zeit [h]'), numeric: true),
                  DataColumn(label: Text('Einheiten [n]'), numeric: true),
                  DataColumn(label: Text('Distanz [km]'), numeric: true),
                  DataColumn(label: Text('Höhe [m]'), numeric: true),
                  DataColumn(label: Text('Aktive Wochen [n]'), numeric: true),
                ],
                rows: [
                  for (final window in analysis.windows)
                    DataRow(
                      cells: [
                        DataCell(Text(window.label)),
                        DataCell(Text(window.durationHours.toStringAsFixed(1))),
                        DataCell(Text('${window.sessionCount}')),
                        DataCell(Text(window.distanceKm.toStringAsFixed(0))),
                        DataCell(
                          Text(window.elevationGainMetres.toStringAsFixed(0)),
                        ),
                        DataCell(Text('${window.activeWeeks}')),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        Text(
          'Umfang Δ 28 Tage: ${_delta(analysis.volumeChange28dPercent)} · '
          'Umfang Δ 90 Tage: ${_delta(analysis.volumeChange90dPercent)}',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: GiuliaTokens.textSecondary),
        ),
        const SizedBox(height: GiuliaTokens.spacingXs),
        Text(
          'Δ vergleicht das aktuelle Fenster mit dem unmittelbar vorherigen '
          'gleich langen Fenster. Es ist keine Belastbarkeits- oder Verletzungsprognose.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
        ),
      ],
    ),
  );
}

class AthleteMonthlyVolumeChart extends StatelessWidget {
  const AthleteMonthlyVolumeChart({super.key, required this.analysis});

  final EliteAnalysisState analysis;

  @override
  Widget build(BuildContext context) {
    final months = analysis.months;
    return GiuliaPanel(
      key: const Key('elite-monthly-volume-chart'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'MONATLICHER TRAININGSUMFANG · GESAMTE ZEIT',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          Text(
            'Vertikale Achse: Trainingszeit [h/Monat] · Horizontale Achse: Kalendermonat',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: GiuliaTokens.textSecondary),
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = math.max(
                constraints.maxWidth,
                math.max(1, months.length) * 34.0 + 64,
              );
              return Semantics(
                image: true,
                label:
                    'Monatlicher Trainingsumfang über die gesamte aufgezeichnete Historie. '
                    'Vertikale Achse Stunden pro Monat, horizontale Achse Kalendermonat.',
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    height: 240,
                    child: CustomPaint(
                      painter: _MonthlyVolumePainter(
                        months: months,
                        gridColor: GiuliaTokens.border,
                        totalColor: const Color(0xFF5C6BC0),
                        skiColor: GiuliaTokens.accent,
                        textColor: GiuliaTokens.textMuted,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          const Wrap(
            spacing: GiuliaTokens.spacingL,
            children: [
              _Legend(color: Color(0xFF5C6BC0), label: 'Gesamt'),
              _Legend(color: GiuliaTokens.accent, label: 'Skispezifisch'),
            ],
          ),
        ],
      ),
    );
  }
}

class AthleteIntensityDistributionChart extends StatelessWidget {
  const AthleteIntensityDistributionChart({super.key, required this.analysis});

  final EliteAnalysisState analysis;

  @override
  Widget build(BuildContext context) {
    final all = analysis.allTime;
    final bars = [
      for (var zone = 1; zone <= 5; zone++)
        _BarDatum(
          label: 'Z$zone',
          value: (all?.hrZoneSeconds['z$zone'] ?? 0) / 3600.0,
          formatted:
              '${((all?.hrZoneSeconds['z$zone'] ?? 0) / 3600.0).toStringAsFixed(1)} h',
          color: _zoneColor(zone),
        ),
    ];
    return _HorizontalChartPanel(
      panelKey: const Key('elite-intensity-chart'),
      title: 'HF-ZONENVERTEILUNG · GESAMTE ZEIT',
      subtitle:
          'Horizontale Achse: aufgezeichnete Zeit [h] · Vertikale Achse: Quell-Zone',
      bars: bars,
      axisLabel: 'Aufgezeichnete Zeit [h]',
      footer:
          'Zonenabdeckung ${(100 * (all?.hrZoneCoverage ?? 0)).toStringAsFixed(0)} % der aufgezeichneten Trainingszeit. '
          '${all?.sessionsWithHeartRateZones ?? 0} Einheiten mit Zeitverteilung, davon '
          '${all?.sessionsWithDerivedHeartRateZones ?? 0} aus zeitaufgelöstem HF-Stream '
          'und individueller HFmax (Z1 <60, Z2 60–69, Z3 70–79, Z4 80–89, Z5 ≥90 % HFmax). '
          'Quell-Zonen werden bevorzugt; fehlende Minuten werden nicht ergänzt.',
    );
  }
}

class AthleteAllTimeModalityChart extends StatelessWidget {
  const AthleteAllTimeModalityChart({super.key, required this.analysis});

  final EliteAnalysisState analysis;

  @override
  Widget build(BuildContext context) {
    final entries =
        analysis.allTime?.modalityDurationSeconds.entries.toList(
          growable: true,
        ) ??
        <MapEntry<XcModality, int>>[];
    entries.sort((a, b) => b.value.compareTo(a.value));
    final bars = [
      for (var index = 0; index < entries.length; index++)
        _BarDatum(
          label: entries[index].key.label,
          value: entries[index].value / 3600.0,
          formatted: '${(entries[index].value / 3600.0).toStringAsFixed(1)} h',
          color: _modalityColor(entries[index].key, index),
        ),
    ];
    return _HorizontalChartPanel(
      panelKey: const Key('elite-modality-chart'),
      title: 'MODALITÄTEN · GESAMTE ZEIT',
      subtitle:
          'Horizontale Achse: Trainingszeit [h] · Vertikale Achse: Modalität',
      bars: bars,
      axisLabel: 'Trainingszeit [h]',
      footer:
          'Nur tatsächlich klassifizierte und gespeicherte Einheiten; keine Hochrechnung.',
    );
  }
}

class _HorizontalChartPanel extends StatelessWidget {
  const _HorizontalChartPanel({
    required this.panelKey,
    required this.title,
    required this.subtitle,
    required this.bars,
    required this.axisLabel,
    required this.footer,
  });

  final Key panelKey;
  final String title;
  final String subtitle;
  final List<_BarDatum> bars;
  final String axisLabel;
  final String footer;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    key: panelKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: GiuliaTokens.spacingXs),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: GiuliaTokens.textSecondary),
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        if (bars.isEmpty || bars.every((bar) => bar.value <= 0))
          const Padding(
            padding: EdgeInsets.symmetric(vertical: GiuliaTokens.spacingL),
            child: Text('Keine auswertbaren Werte aufgezeichnet.'),
          )
        else
          Semantics(
            image: true,
            label: '$title. Horizontale Achse $axisLabel.',
            child: SizedBox(
              height: math.max(190, bars.length * 38 + 70),
              child: CustomPaint(
                painter: _HorizontalBarsPainter(
                  bars: bars.where((bar) => bar.value > 0).toList(),
                  gridColor: GiuliaTokens.border,
                  textColor: GiuliaTokens.textMuted,
                  axisLabel: axisLabel,
                ),
              ),
            ),
          ),
        const SizedBox(height: GiuliaTokens.spacingS),
        Text(
          footer,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
        ),
      ],
    ),
  );
}

class _MetricWrap extends StatelessWidget {
  const _MetricWrap({required this.metrics});
  final List<(String, String)> metrics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 700 ? 4 : 2;
      final width =
          (constraints.maxWidth - (columns - 1) * GiuliaTokens.spacingM) /
          columns;
      return Wrap(
        spacing: GiuliaTokens.spacingM,
        runSpacing: GiuliaTokens.spacingM,
        children: [
          for (final metric in metrics)
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metric.$1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: GiuliaTokens.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    metric.$2,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
        ],
      );
    },
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
      Container(width: 14, height: 4, color: color),
      const SizedBox(width: GiuliaTokens.spacingXs),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _BarDatum {
  const _BarDatum({
    required this.label,
    required this.value,
    required this.formatted,
    required this.color,
  });
  final String label;
  final double value;
  final String formatted;
  final Color color;
}

class _HorizontalBarsPainter extends CustomPainter {
  const _HorizontalBarsPainter({
    required this.bars,
    required this.gridColor,
    required this.textColor,
    required this.axisLabel,
  });

  final List<_BarDatum> bars;
  final Color gridColor;
  final Color textColor;
  final String axisLabel;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    const left = 116.0;
    const right = 48.0;
    const top = 12.0;
    const bottom = 48.0;
    final plot = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final maximum = _niceMaximum(bars.map((bar) => bar.value).reduce(math.max));
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var tick = 0; tick <= 4; tick++) {
      final x = plot.left + plot.width * tick / 4;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      _paintText(
        canvas,
        (maximum * tick / 4).toStringAsFixed(maximum < 10 ? 1 : 0),
        Offset(x, plot.bottom + 5),
        textColor,
        align: TextAlign.center,
        anchor: .5,
      );
    }
    final rowHeight = plot.height / bars.length;
    for (var index = 0; index < bars.length; index++) {
      final bar = bars[index];
      final centerY = plot.top + rowHeight * (index + .5);
      final barHeight = math.min(22.0, rowHeight * .58);
      final width = plot.width * bar.value / maximum;
      _paintText(
        canvas,
        bar.label,
        Offset(0, centerY - 8),
        textColor,
        maxWidth: left - 8,
        align: TextAlign.right,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(plot.left, centerY - barHeight / 2, width, barHeight),
          const Radius.circular(5),
        ),
        Paint()..color = bar.color,
      );
      _paintText(
        canvas,
        bar.formatted,
        Offset(
          math.min(plot.left + width + 6, size.width - right + 4),
          centerY - 8,
        ),
        textColor,
        maxWidth: right - 4,
      );
    }
    _paintText(
      canvas,
      axisLabel,
      Offset(plot.center.dx, size.height - 17),
      textColor,
      align: TextAlign.center,
      anchor: .5,
    );
  }

  @override
  bool shouldRepaint(covariant _HorizontalBarsPainter oldDelegate) =>
      oldDelegate.bars != bars || oldDelegate.axisLabel != axisLabel;
}

class _MonthlyVolumePainter extends CustomPainter {
  const _MonthlyVolumePainter({
    required this.months,
    required this.gridColor,
    required this.totalColor,
    required this.skiColor,
    required this.textColor,
  });

  final List<MonthlyTrainingSummary> months;
  final Color gridColor;
  final Color totalColor;
  final Color skiColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty) return;
    const left = 46.0;
    const right = 14.0;
    const top = 10.0;
    const bottom = 48.0;
    final plot = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final maximum = _niceMaximum(
      months.map((month) => month.durationHours).fold<double>(0, math.max),
    );
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var tick = 0; tick <= 4; tick++) {
      final value = maximum * tick / 4;
      final y = plot.bottom - plot.height * tick / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _paintText(
        canvas,
        value.toStringAsFixed(maximum < 10 ? 1 : 0),
        Offset(0, y - 7),
        textColor,
        maxWidth: left - 7,
        align: TextAlign.right,
      );
    }
    final slot = plot.width / months.length;
    final barWidth = math.min(22.0, slot * .68);
    final labelStride = math.max(1, (months.length / 8).ceil());
    for (var index = 0; index < months.length; index++) {
      final month = months[index];
      final x = plot.left + slot * (index + .5);
      final totalHeight = plot.height * month.durationHours / maximum;
      final skiHeight = plot.height * month.skiSpecificHours / maximum;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x - barWidth / 2,
            plot.bottom - totalHeight,
            barWidth,
            totalHeight,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = totalColor,
      );
      if (skiHeight > 0) {
        final skiBarWidth = barWidth * .55;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              x - skiBarWidth / 2,
              plot.bottom - skiHeight,
              skiBarWidth,
              skiHeight,
            ),
            const Radius.circular(3),
          ),
          Paint()..color = skiColor,
        );
      }
      if (index % labelStride == 0 || index == months.length - 1) {
        _paintText(
          canvas,
          '${month.month.toString().padLeft(2, '0')}.${month.year.toString().substring(2)}',
          Offset(x, plot.bottom + 7),
          textColor,
          align: TextAlign.center,
          anchor: .5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MonthlyVolumePainter oldDelegate) =>
      oldDelegate.months != months;
}

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

double _niceMaximum(double value) {
  if (!value.isFinite || value <= 0) return 1;
  final exponent = math
      .pow(10, (math.log(value) / math.ln10).floor())
      .toDouble();
  final normalized = value / exponent;
  final nice = normalized <= 1
      ? 1.0
      : normalized <= 2
      ? 2.0
      : normalized <= 5
      ? 5.0
      : 10.0;
  return nice * exponent;
}

Color _zoneColor(int zone) => switch (zone) {
  1 => const Color(0xFF42A5F5),
  2 => const Color(0xFF26A69A),
  3 => const Color(0xFFFBC02D),
  4 => const Color(0xFFFB8C00),
  _ => const Color(0xFFE53935),
};

Color _modalityColor(XcModality modality, int index) {
  if (modality.isSnowSkiing) return const Color(0xFF42A5F5);
  if (modality == XcModality.ercolinaDoublePoling) {
    return const Color(0xFF26A69A);
  }
  if (modality == XcModality.rollerSkiSkating ||
      modality == XcModality.rollerSkiClassic ||
      modality == XcModality.rollerSkiDoublePoling) {
    return const Color(0xFF7E57C2);
  }
  const palette = [
    Color(0xFF5C6BC0),
    Color(0xFF8D6E63),
    Color(0xFF78909C),
    Color(0xFFEC407A),
  ];
  return palette[index % palette.length];
}

String _date(DateTime? date) => date == null
    ? 'Nicht erfasst'
    : '${date.day.toString().padLeft(2, '0')}.'
          '${date.month.toString().padLeft(2, '0')}.${date.year}';

String _delta(double? value) => value == null
    ? 'nicht berechenbar'
    : '${value >= 0 ? '+' : ''}${value.toStringAsFixed(0)} %';

String _bestValue(double value, String unit) => unit == 'km' || unit == 'kJ'
    ? value.toStringAsFixed(1)
    : value.toStringAsFixed(0);
