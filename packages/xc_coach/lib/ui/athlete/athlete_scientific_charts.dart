/// Scientifically labelled charts for the canonical XC athlete state.
///
/// Every chart uses one physical or count unit per axis. Values from different
/// units are never normalised into a synthetic score merely to fit a graphic.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/xc_modality.dart';
import '../../intelligence/load/stimulus_models.dart';
import '../../intelligence/xc_athlete_state/xc_athlete_state.dart';
import '../design_system.dart';

class AthleteModalityExposureChart extends StatelessWidget {
  const AthleteModalityExposureChart({super.key, required this.athleteState});

  final XCAthleteState athleteState;

  @override
  Widget build(BuildContext context) {
    final entries =
        athleteState.skiExposure.byModality.values
            .where((entry) => entry.durationSeconds28d > 0)
            .map(
              (entry) => _BarDatum(
                label: _shortModality(entry.modality),
                value: entry.durationHours28d,
                valueLabel: '${entry.durationHours28d.toStringAsFixed(1)} h',
                color: _modalityColor(entry.modality),
              ),
            )
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    return _ScientificBarCard(
      key: const Key('chart-modality-exposure'),
      title: 'UMFANG NACH MODALITÄT',
      subtitle: 'Tatsächlich erfasste Trainingszeit der letzten 28 Tage',
      emptyText: 'Noch keine Trainingszeit im 28-Tage-Fenster erfasst.',
      categoryAxisTitle: 'Modalität',
      valueAxisTitle: 'Trainingszeit [h in 28 d]',
      semanticsLabel:
          'Trainingsumfang nach Modalität. Horizontale Achse Trainingszeit '
          'in Stunden in 28 Tagen. Vertikale Achse Modalität.',
      data: entries,
    );
  }
}

class AthleteStimulusFrequencyChart extends StatelessWidget {
  const AthleteStimulusFrequencyChart({super.key, required this.athleteState});

  final XCAthleteState athleteState;

  @override
  Widget build(BuildContext context) {
    final entries = <_BarDatum>[
      for (final type in StimulusType.values)
        if (athleteState.stimulusHistory.entryFor(type).frequency28d > 0)
          _BarDatum(
            label: _shortStimulus(type),
            value: athleteState.stimulusHistory
                .entryFor(type)
                .frequency28d
                .toDouble(),
            valueLabel:
                '${athleteState.stimulusHistory.entryFor(type).frequency28d}×',
            color: _stimulusColor(type),
          ),
    ]..sort((a, b) => b.value.compareTo(a.value));

    return _ScientificBarCard(
      key: const Key('chart-stimulus-frequency'),
      title: 'BEOBACHTETE TRAININGSREIZE',
      subtitle:
          'Häufigkeit aus durchgeführten Einheiten; Planung allein zählt nicht',
      emptyText: 'Noch keine beobachteten Trainingsreize im 28-Tage-Fenster.',
      categoryAxisTitle: 'Reiztyp',
      valueAxisTitle: 'Beobachtete Reize [Anzahl in 28 d]',
      semanticsLabel:
          'Beobachtete Trainingsreize. Horizontale Achse Anzahl der Reize '
          'in 28 Tagen. Vertikale Achse Reiztyp.',
      data: entries,
      integerTicks: true,
    );
  }
}

class AthleteDataCoverageChart extends StatelessWidget {
  const AthleteDataCoverageChart({super.key, required this.athleteState});

  final XCAthleteState athleteState;

  @override
  Widget build(BuildContext context) {
    final coverage = athleteState.dataCoverage;
    final values = <(String, double)>[
      ('Externe Aktivitäten', coverage.externalActivityCoverage),
      ('Ercolina', coverage.ercolinaCoverage),
      ('Herzfrequenz', coverage.hrCoverage),
      ('Leistung', coverage.powerCoverage),
      ('Subjektiv', coverage.subjectiveCoverage),
      ('Diagnostik', coverage.diagnosticsCoverage),
    ];
    return _ScientificBarCard(
      key: const Key('chart-data-coverage'),
      title: 'DATENABDECKUNG',
      subtitle: 'Anteil vorhandener Daten je Kanal · keine Qualitätsnote',
      emptyText: 'Keine Angaben zur Datenabdeckung verfügbar.',
      categoryAxisTitle: 'Datenkanal',
      valueAxisTitle: 'Datenabdeckung [%]',
      semanticsLabel:
          'Datenabdeckung. Horizontale Achse Datenabdeckung in Prozent. '
          'Vertikale Achse Datenkanal.',
      fixedMaximum: 100,
      data: [
        for (final value in values)
          _BarDatum(
            label: value.$1,
            value: (value.$2 * 100).clamp(0, 100).toDouble(),
            valueLabel: '${(value.$2 * 100).clamp(0, 100).round()} %',
            color: _coverageColor(value.$2),
          ),
      ],
    );
  }
}

class _ScientificBarCard extends StatelessWidget {
  const _ScientificBarCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.emptyText,
    required this.categoryAxisTitle,
    required this.valueAxisTitle,
    required this.semanticsLabel,
    required this.data,
    this.fixedMaximum,
    this.integerTicks = false,
  });

  final String title;
  final String subtitle;
  final String emptyText;
  final String categoryAxisTitle;
  final String valueAxisTitle;
  final String semanticsLabel;
  final List<_BarDatum> data;
  final double? fixedMaximum;
  final bool integerTicks;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    tone: GiuliaTokens.surface1,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: GiuliaTokens.textPrimary,
            fontWeight: FontWeight.w800,
            letterSpacing: .4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: GiuliaTokens.textSecondary),
        ),
        const SizedBox(height: GiuliaTokens.spacingM),
        if (data.isEmpty)
          Text(
            emptyText,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: GiuliaTokens.textMuted),
          )
        else
          Semantics(
            label: semanticsLabel,
            image: true,
            child: SizedBox(
              height: 70 + data.length * 36,
              child: CustomPaint(
                painter: _HorizontalBarChartPainter(
                  data: data,
                  categoryAxisTitle: categoryAxisTitle,
                  valueAxisTitle: valueAxisTitle,
                  fixedMaximum: fixedMaximum,
                  integerTicks: integerTicks,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _BarDatum {
  const _BarDatum({
    required this.label,
    required this.value,
    required this.valueLabel,
    required this.color,
  });

  final String label;
  final double value;
  final String valueLabel;
  final Color color;
}

class _HorizontalBarChartPainter extends CustomPainter {
  const _HorizontalBarChartPainter({
    required this.data,
    required this.categoryAxisTitle,
    required this.valueAxisTitle,
    required this.fixedMaximum,
    required this.integerTicks,
  });

  final List<_BarDatum> data;
  final String categoryAxisTitle;
  final String valueAxisTitle;
  final double? fixedMaximum;
  final bool integerTicks;

  @override
  void paint(Canvas canvas, Size size) {
    final labelWidth = math.min(136.0, size.width * .38);
    final plot = Rect.fromLTRB(
      labelWidth,
      24,
      size.width - 8,
      size.height - 42,
    );
    final observedMax = data.fold<double>(
      0,
      (max, item) => math.max(max, item.value),
    );
    final axisMax = fixedMaximum ?? _niceAxisMaximum(observedMax);
    final ticks = integerTicks ? math.min(5, axisMax.round()).clamp(1, 5) : 4;

    _paintText(
      canvas,
      categoryAxisTitle,
      const Offset(0, 0),
      maxWidth: labelWidth - 8,
      color: GiuliaTokens.textMuted,
      fontSize: 10,
      fontWeight: FontWeight.w700,
    );

    for (var tick = 0; tick <= ticks; tick++) {
      final fraction = tick / ticks;
      final x = plot.left + plot.width * fraction;
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = GiuliaTokens.chartGrid
          ..strokeWidth = 1,
      );
      final raw = axisMax * fraction;
      final label = integerTicks
          ? raw.round().toString()
          : raw >= 10
          ? raw.toStringAsFixed(0)
          : raw.toStringAsFixed(1);
      _paintText(
        canvas,
        label,
        Offset(x - 18, plot.bottom + 5),
        maxWidth: 36,
        align: TextAlign.center,
        color: GiuliaTokens.textMuted,
        fontSize: 9,
      );
    }

    final rowHeight = plot.height / data.length;
    for (var index = 0; index < data.length; index++) {
      final item = data[index];
      final centerY = plot.top + rowHeight * (index + .5);
      _paintText(
        canvas,
        item.label,
        Offset(0, centerY - 8),
        maxWidth: labelWidth - 10,
        align: TextAlign.right,
        color: GiuliaTokens.textSecondary,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      );

      final barWidth = plot.width * (item.value / axisMax).clamp(0.0, 1.0);
      final bar = RRect.fromRectAndRadius(
        Rect.fromLTWH(plot.left, centerY - 7, barWidth, 14),
        const Radius.circular(4),
      );
      canvas.drawRRect(bar, Paint()..color = item.color);

      final valueInside = barWidth >= 54;
      final valueX = valueInside
          ? plot.left + barWidth - 45
          : math.min(plot.left + barWidth + 5, plot.right - 42);
      _paintText(
        canvas,
        item.valueLabel,
        Offset(valueX, centerY - 8),
        maxWidth: 44,
        align: valueInside ? TextAlign.right : TextAlign.left,
        color: valueInside ? Colors.white : GiuliaTokens.textPrimary,
        fontSize: 9,
        fontWeight: FontWeight.w700,
      );
    }

    _paintText(
      canvas,
      valueAxisTitle,
      Offset(plot.left, size.height - 14),
      maxWidth: plot.width,
      align: TextAlign.center,
      color: GiuliaTokens.textSecondary,
      fontSize: 10,
      fontWeight: FontWeight.w700,
    );
  }

  @override
  bool shouldRepaint(_HorizontalBarChartPainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.categoryAxisTitle != categoryAxisTitle ||
      oldDelegate.valueAxisTitle != valueAxisTitle ||
      oldDelegate.fixedMaximum != fixedMaximum ||
      oldDelegate.integerTicks != integerTicks;
}

double _niceAxisMaximum(double value) {
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

void _paintText(
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

String _shortModality(XcModality modality) => switch (modality) {
  XcModality.skiNordicUnknown => 'Langlauf unklar',
  XcModality.skiSkating => 'Schnee Skating',
  XcModality.skiClassic => 'Schnee Klassisch',
  XcModality.doublePoling => 'Schnee Doppelstock',
  XcModality.rollerSkiUnknown => 'Rollski unklar',
  XcModality.rollerSkiSkating => 'Rollski Skating',
  XcModality.rollerSkiClassic => 'Rollski Klassisch',
  XcModality.rollerSkiDoublePoling => 'Rollski Doppelstock',
  XcModality.ercolinaDoublePoling => 'Ercolina Doppelstock',
  XcModality.cycling => 'Radfahren',
  XcModality.running => 'Laufen',
  XcModality.strength => 'Krafttraining',
  XcModality.other => 'Sonstige',
  XcModality.unknown => 'Unbekannt',
};

Color _modalityColor(XcModality modality) {
  if (modality.isSnowSkiing) return const Color(0xFF2F6DB3);
  if (modality.isRollerSkiing) return const Color(0xFF8B5FBF);
  if (modality.isErcolina) return GiuliaTokens.accent;
  return switch (modality) {
    XcModality.running => const Color(0xFFD2762D),
    XcModality.cycling => const Color(0xFF3E8E5B),
    XcModality.strength => const Color(0xFFC34E5C),
    _ => GiuliaTokens.chartReference,
  };
}

String _shortStimulus(StimulusType type) => switch (type) {
  StimulusType.recovery => 'Regeneration',
  StimulusType.aerobicBase => 'Grundlage',
  StimulusType.longEndurance => 'Langer Umfang',
  StimulusType.threshold => 'Schwelle',
  StimulusType.vo2max => 'VO2max / HIT',
  StimulusType.speedNeuromuscular => 'Schnelligkeit',
  StimulusType.maxStrength => 'Maximalkraft',
  StimulusType.explosiveStrength => 'Schnellkraft',
  StimulusType.muscularEndurance => 'Kraftausdauer',
  StimulusType.doublePolingPower => 'DP Spitzenkraft',
  StimulusType.doublePolingEndurance => 'DP Ausdauer',
  StimulusType.technique => 'Technik',
  StimulusType.fatigueResistance => 'Durability',
  StimulusType.raceSpecific => 'Wettkampfspezifisch',
};

Color _stimulusColor(StimulusType type) => switch (type) {
  StimulusType.recovery => const Color(0xFF67A57A),
  StimulusType.aerobicBase ||
  StimulusType.longEndurance => const Color(0xFF2F6DB3),
  StimulusType.threshold => const Color(0xFFD08A24),
  StimulusType.vo2max || StimulusType.raceSpecific => const Color(0xFFC34E5C),
  StimulusType.speedNeuromuscular ||
  StimulusType.explosiveStrength => const Color(0xFF8B5FBF),
  StimulusType.maxStrength ||
  StimulusType.muscularEndurance => const Color(0xFF6C6570),
  StimulusType.doublePolingPower ||
  StimulusType.doublePolingEndurance => GiuliaTokens.accent,
  StimulusType.technique => const Color(0xFF3E8E8C),
  StimulusType.fatigueResistance => const Color(0xFF7A6EB0),
};

Color _coverageColor(double ratio) {
  if (ratio >= .9) return GiuliaTokens.success;
  if (ratio >= .75) return GiuliaTokens.accent;
  if (ratio >= .5) return GiuliaTokens.warning;
  return GiuliaTokens.error;
}
