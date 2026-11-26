/// Eine gefahrene Einheit.
///
/// Steht unter `ui/session` und nicht unter `ui/ercolina`: Der Bildschirm liest
/// einen [SessionReport](../../app/session_report.dart) und weiss nichts von
/// einem Gerät. Eine Trainerin sieht dieselbe Einheit wie der Athlet — läge er
/// beim Gerät, zöge GIULIA Coach den Ercolina-Treiber mit, nur um eine
/// gefahrene Einheit zu zeigen.
///
/// Derselbe Bildschirm zweimal: direkt nach dem Stop und Wochen später aus dem
/// Verlauf. Nicht zwei ähnliche — **einer**. Beide lesen dieselbe Auswertung
/// aus dem Archiv ([SessionReport](../../app/session_report.dart)), und der
/// einzige Unterschied ist die Überschrift und der Knopf unten.
///
/// Wäre es zweimal gebaut, würden die Zahlen irgendwann auseinanderlaufen, und
/// zwar an der Stelle, an der es am meisten schadet: Ein Athlet sieht nach dem
/// Training 184 W und im Verlauf 179 W und glaubt danach keiner von beiden.
///
/// ## Hierarchie
///
/// Was man in einer Sekunde sehen soll: wie lange, wie viele Züge, welche
/// mittlere Leistung. Danach Balance, Verlauf, Zuganalyse und GIULIAs Lesart.
/// Auf dem iPad stehen Kennzahlen und Diagramme in zwei Spalten.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../database/session_repository.dart';

import '../../app/session_report.dart';
import '../../app/mirco_preview.dart';
import '../../charts/nice_scale.dart';
import '../../core/models.dart';
import '../../core/stroke_metrics.dart';
import '../../domain/training_plan.dart';
import '../../metrics/heart_rate_analytics.dart';
import '../../metrics/session_complete_analysis.dart';
import '../../metrics/stroke_curves.dart';
import '../../training/workout_recorder.dart';
import '../design_system.dart';
import '../../workout_engine/workout_labels.dart';
import 'stroke_dynamics_instrument.dart';

class SessionReportScreen extends StatelessWidget {
  const SessionReportScreen({
    super.key,
    required this.report,
    this.isSummary = false,
    this.onDone,
    this.plan,
  });

  final SessionReport report;

  /// Ob der Bildschirm direkt nach dem Training erscheint.
  final bool isSummary;

  final VoidCallback? onDone;

  /// Plan und Ist, wenn die Session aus einer geplanten Einheit stammt.
  final PlanActual? plan;

  static const double _twoColumnWidth = 900;

  @override
  Widget build(BuildContext context) {
    final density = GiuliaDensity.of(context);

    return Scaffold(
      backgroundColor: GiuliaTokens.surface0,
      appBar: AppBar(
        title: Text(
          report.session.recordingState == SessionRecordingState.interrupted
              ? previewText(
                  'Aufzeichnung unvollständig',
                  'Recording incomplete',
                )
              : isSummary
              ? previewText('Training beendet', 'Training complete')
              : previewText('Einheit', 'Session'),
        ),
        automaticallyImplyLeading: !isSummary,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= _twoColumnWidth;
            final gap = density.sectionGap;
            final complete = report.completeAnalysis;
            final header = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (report.session.recordingState ==
                    SessionRecordingState.interrupted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      previewText(
                        'Diese Aufzeichnung wurde unterbrochen oder enthält Speicherfehler. Ergebnisse können unvollständig sein.',
                        'This recording was interrupted or had storage errors. Results may be incomplete.',
                      ),
                      key: const Key('incomplete-recording-notice'),
                      style: TextStyle(color: GiuliaTokens.error),
                    ),
                  ),
                _Header(report: report, isSummary: isSummary),
                if (report.hasStrokes)
                  Text(
                    previewText(
                      ErcolinaMechanics.prototypeNotice,
                      ErcolinaMechanics.prototypeNoticeEnglish,
                    ),
                    key: const Key('prototype-model-notice'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (plan case final plan?) ...[
                  SizedBox(height: gap),
                  _PlanActualPanel(plan: plan),
                ],
              ],
            );
            final summary = <Widget>[
              _PowerSummary(report: report),
              SizedBox(height: gap),
              GiuliaSection(
                title: 'Balance',
                child: _Balance(report: report),
              ),
              if (report.hasIntervals) ...[
                SizedBox(height: gap),
                GiuliaSection(
                  title: previewText('Die Abschnitte', 'Workout intervals'),
                  subtitle: _hitLine(report),
                  child: GiuliaPanel(
                    key: const Key('session-intervals'),
                    child: Column(
                      children: [
                        for (final (index, interval)
                            in report.intervals.indexed) ...[
                          if (index > 0) const Divider(height: 1),
                          _IntervalRow(interval: interval),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ];
            final analysis = <Widget>[
              _CompleteTimelineSection(
                analysis: complete,
                heartRate: report.heartRate,
              ),
              SizedBox(height: gap),
              _HeartRateSection(analysis: report.heartRate),
              SizedBox(height: gap),
              _FatigueSection(analysis: complete),
              SizedBox(height: gap),
              _PerformanceProfiles(analysis: complete),
              SizedBox(height: gap),
              GiuliaSection(
                title: previewText('Zuganalyse', 'Stroke analysis'),
                child: _StrokeAnalysis(report: report),
              ),
              if (_insight(report) case final insight?) ...[
                SizedBox(height: gap),
                insight,
              ],
            ];
            final dynamics = GiuliaSection(
              key: const Key('session-stroke-dynamics'),
              title: previewText(
                'Zugdynamik links / rechts',
                'Stroke dynamics: left / right',
              ),
              subtitle: report.strokeSides.isEmpty
                  ? previewText(
                      'Für diese Einheit wurden keine beidseitigen Zugkurven gespeichert.',
                      'No left/right stroke curves were saved for this session.',
                    )
                  : previewText(
                      'Ø ganze Einheit · umschaltbar bis zum Einzelzug · '
                          'x: Zugphase 0–100 % · y: Leistung (W)',
                      'Session average · select individual strokes · '
                          'x: stroke phase 0–100% · y: power (W)',
                    ),
              child: report.strokeSides.isEmpty
                  ? GiuliaEmptyState(
                      icon: Icons.show_chart,
                      title: previewText(
                        'Keine Zugkurven in dieser Einheit',
                        'No stroke curves in this session',
                      ),
                      description: previewText(
                        'Leistung, Arbeit und Balance bleiben auswertbar. '
                            'Das detaillierte Links-rechts-Profil ist nur für '
                            'Einheiten verfügbar, die beidseitige Kurven '
                            'gespeichert haben.',
                        'Power, work and balance are still available. Detailed '
                            'left/right profiles require saved curves from both sensors.',
                      ),
                    )
                  : SizedBox(
                      height: wide ? 620 : 760,
                      child: StrokeDynamicsInstrument(
                        sides: report.strokeSides,
                        initialSelection: StrokeSelection.all,
                      ),
                    ),
            );

            final body = !report.hasStrokes
                ? <Widget>[
                    header,
                    SizedBox(height: gap),
                    GiuliaEmptyState(
                      icon: Icons.timer_outlined,
                      title: previewText(
                        'Keine Züge aufgezeichnet',
                        'No strokes recorded',
                      ),
                      description: previewText(
                        'Die Einheit ist gespeichert, aber es kam kein Zug '
                            'an. Ohne Züge gibt es nichts auszuwerten.',
                        'The session was saved, but no strokes arrived. There are no stroke metrics to analyze.',
                      ),
                    ),
                    SizedBox(height: gap),
                    _HeartRateSection(analysis: report.heartRate),
                  ]
                : wide
                ? <Widget>[
                    header,
                    SizedBox(height: gap),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: summary,
                          ),
                        ),
                        SizedBox(width: GiuliaTokens.spacingXl),
                        Expanded(
                          flex: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: analysis,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: gap),
                    dynamics,
                  ]
                : <Widget>[
                    header,
                    SizedBox(height: gap),
                    ...summary,
                    SizedBox(height: gap),
                    ...analysis,
                    SizedBox(height: gap),
                    dynamics,
                  ];

            return ListView(
              padding: density.pageInsets,
              children: [
                GiuliaContentWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...body,
                      if (isSummary) ...[
                        SizedBox(height: gap),
                        Align(
                          alignment: Alignment.center,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 420,
                              minWidth: 240,
                            ),
                            child: FilledButton(
                              key: const Key('session-summary-done'),
                              onPressed: onDone,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: GiuliaTokens.spacingM,
                                ),
                              ),
                              child: Text(previewText('Fertig', 'Done')),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// «3 von 4 Intervallen im Zielbereich» — oder nichts, wenn es keine
  /// Vorgaben gab. Eine Quote ohne Ziel wäre eine erfundene Note.
  static String? _hitLine(SessionReport report) {
    final hits = report.targetHits;
    // Die Zahl rechts in jeder Zeile ist die Zugleistung — dieselbe Groesse
    // wie oben und auf der Startseite. Sie gehoert benannt: eine Wattzahl
    // ohne Bezugsgroesse kann zweierlei bedeuten.
    final quantity = previewText(
      'Ø Zugleistung je Abschnitt',
      'Avg stroke power per interval',
    );
    if (hits == null) return quantity;
    return previewText(
      '${hits.hit} von ${hits.total} Belastungen im Zielbereich · $quantity',
      '${hits.hit} of ${hits.total} work intervals on target · $quantity',
    );
  }

  /// GIULIAs Lesart — nur aus Werten, die oben schon stehen, und nur wenn
  /// sie eine Aussage tragen. Keine Note, keine erfundene Empfehlung.
  static Widget? _insight(SessionReport report) {
    final fatigue = report.fatiguePercent;
    final variation = report.powerVariationPercent;
    if (!giuliaIsValid(fatigue) && !giuliaIsValid(variation)) return null;
    final evidence =
        '${report.strokeCount} Züge · Streuung '
        '${giuliaNumber(variation, decimals: 1)} % · Ermüdung '
        '${giuliaNumber(fatigue, decimals: 1)} %';
    if (giuliaIsValid(fatigue) && fatigue! <= -5) {
      return GiuliaInsight(
        title: 'Leistung nachgelassen',
        message:
            'Gegen Ende lag die Leistung je Zug '
            '${giuliaNumber(-fatigue, decimals: 1)} % unter dem Anfang.',
        evidence: evidence,
        tone: GiuliaTokens.warning,
      );
    }
    if (giuliaIsValid(variation) && variation! < 8) {
      return GiuliaInsight(
        title: 'Stabile Leistung',
        message:
            'Die Leistung je Zug schwankte nur um '
            '${giuliaNumber(variation, decimals: 1)} %.',
        evidence: evidence,
      );
    }
    if (giuliaIsValid(variation) && variation! >= 15) {
      return GiuliaInsight(
        title: 'Ungleichmässige Züge',
        message:
            'Die Leistung je Zug schwankte um '
            '${giuliaNumber(variation, decimals: 1)} %. Ein gleichmässigerer '
            'Rhythmus macht die Einheit vergleichbarer.',
        evidence: evidence,
        tone: GiuliaTokens.warning,
      );
    }
    return null;
  }
}

/// Oben: wann, wie lange, wie viele Züge.
/// Geplant gegen absolviert – nur aus gespeicherten Werten.
class _PlanActualPanel extends StatelessWidget {
  const _PlanActualPanel({required this.plan});

  final PlanActual plan;

  static String _minutes(int seconds) => '${(seconds / 60).round()} min';

  // Labels of `Intensity`; the library itself would pull `coaching` into
  // every product that shows a session.
  static const _intensityLabels = {
    'recovery': 'Regeneration',
    'base': 'Grundlage',
    'tempo': 'Tempo',
    'threshold': 'Schwelle',
    'vo2': 'VO2max',
    'maximal': 'Maximal',
    'technique': 'Technik',
  };

  static String _intensity(String? name) =>
      _intensityLabels[name] ?? name ?? 'ohne Vorgabe';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final planned = plan.planned;
    final actual = plan.actual;
    final deviation = plan.intensityDeviation;
    final delta = plan.durationDeltaSeconds;
    Widget block(String title, List<String> lines) => Padding(
      padding: const EdgeInsets.only(bottom: GiuliaTokens.spacingS),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.labelMedium),
          for (final line in lines) Text(line),
        ],
      ),
    );
    return GiuliaPanel(
      key: const Key('session-plan-actual'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          block('GEPLANT', [
            planned.goal,
            '${_minutes(planned.durationSeconds)} · '
                '${_intensity(planned.intensity)}',
            if (planned.structure.isNotEmpty)
              [
                for (final step in planned.structure)
                  '${_minutes(step.seconds)} ${_intensity(step.intensity)}',
              ].join(' · '),
          ]),
          block('ABSOLVIERT', [
            if (actual == null)
              'Keine auswertbaren Daten gespeichert.'
            else ...[
              _minutes(actual.durationSeconds),
              if (actual.intervalCount case final count?)
                '$count aufgezeichnete Abschnitte',
              if (deviation != null)
                '${_minutes(deviation.inTargetSeconds)} im Zielbereich, '
                    '${_minutes(deviation.belowSeconds)} darunter, '
                    '${_minutes(deviation.aboveSeconds)} darüber'
              else
                'Keine Zielbereiche aufgezeichnet.',
            ],
          ]),
          block('ABWEICHUNG', [
            if (delta != null)
              delta == 0
                  ? 'Dauer wie geplant'
                  : 'Dauer ${delta > 0 ? '+' : '−'}${_minutes(delta.abs())}',
            if (plan.sportChanged == true) 'Andere Sportart als geplant',
            'Status: ${switch (planned.status) {
              PlannedWorkoutStatus.planned => 'offen',
              PlannedWorkoutStatus.completed => 'absolviert',
              PlannedWorkoutStatus.skipped => 'ausgelassen',
              PlannedWorkoutStatus.modified => 'verändert absolviert',
            }}',
          ]),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.report, required this.isSummary});

  final SessionReport report;
  final bool isSummary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final paused = report.pausedTime;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          report.session.recordingState == SessionRecordingState.interrupted
              ? previewText(
                  'Aufzeichnung unvollständig',
                  'Recording incomplete',
                )
              : isSummary
              ? previewText('Training abgeschlossen', 'Training complete')
              : 'SESSION',
          style: isSummary ? text.headlineMedium : text.labelMedium,
        ),
        const SizedBox(height: GiuliaTokens.spacingXs),
        Text(_dateLine(report.session.startedAtUtcUs), style: text.bodyMedium),
        const SizedBox(height: GiuliaTokens.spacingL),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: GiuliaMetricRow(
            children: [
              GiuliaMetric(
                key: const Key('session-active-time'),
                value: _clock(report.activeTime),
                unit: 'min',
                label: previewText('Aktiv', 'Active'),
                size: GiuliaMetricSize.primary,
              ),
              GiuliaMetric(
                value: '${report.strokeCount}',
                label: previewText('Züge', 'Strokes'),
                size: GiuliaMetricSize.primary,
              ),
              if (report.trackDistanceMetres case final metres?)
                GiuliaMetric(
                  key: const Key('session-track-distance'),
                  value: mircoPreview
                      ? (metres / 1000).toStringAsFixed(2)
                      : (metres / 1000).toStringAsFixed(2).replaceAll('.', ','),
                  unit: 'km',
                  label: previewText('Distanz', 'Distance'),
                  size: GiuliaMetricSize.primary,
                ),
              GiuliaMetric(
                key: const Key('session-wall-time'),
                value: _clock(report.wallTime),
                unit: 'min',
                label: previewText('Gesamt', 'Total'),
              ),
              if (paused > Duration.zero)
                GiuliaMetric(
                  value: _clock(paused),
                  unit: 'min',
                  label: previewText('Pause', 'Paused'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _clock(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static String _dateLine(int utcUs) {
    final local = DateTime.fromMicrosecondsSinceEpoch(
      utcUs,
      isUtc: true,
    ).toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} · '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// Die mittlere Leistung als Hauptzahl, darunter Peak, Frequenz, Arbeit.
class _PowerSummary extends StatelessWidget {
  const _PowerSummary({required this.report});
  final SessionReport report;

  @override
  Widget build(BuildContext context) {
    final recap = report.recap;
    final strokePower = report.averageStrokePowerWatt;
    final sessionPower = recap?.shownPowerWatt;

    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: GiuliaHeroMetric(
                  value: giuliaNumber(strokePower ?? sessionPower),
                  unit: 'W',
                  label: strokePower != null
                      ? previewText('Ø Zugleistung', 'Avg stroke power')
                      : previewText('Ø Leistung', 'Avg power'),
                  fontSize: GiuliaTokens.metricHero * .8,
                ),
              ),
              // Hier stand «Ø Gesamt» daneben — die Leistung ueber die
              // Gesamtzeit. Zwei Wattzahlen nebeneinander, beide «Ø», die
              // eine deutlich kleiner: Genau die Verwechslung, die die
              // Startseite schon hatte. Es gilt eine Groesse, und das ist die
              // Zugleistung.
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingL),
          const Divider(height: 1),
          const SizedBox(height: GiuliaTokens.spacingM),
          GiuliaMetricRow(
            minItemWidth: 110,
            children: [
              GiuliaMetric(
                value: giuliaNumber(report.peakPowerWatt),
                unit: 'W',
                label: 'Peak',
              ),
              GiuliaMetric(
                value: giuliaNumber(recap?.strokeRatePerMinute),
                unit: '/min',
                label: previewText(
                  (mircoPreview ? 'Stroke rate' : 'Zugfrequenz'),
                  'Stroke rate',
                ),
              ),
              GiuliaMetric(
                value: giuliaNumber(report.workJoule / 1000, decimals: 1),
                unit: 'kJ',
                label: previewText('Arbeit', 'Work'),
              ),
              if (report.trackSpeedMetresPerSecond case final speed?)
                GiuliaMetric(
                  value: giuliaNumber(speed * 3.6, decimals: 1),
                  unit: 'km/h',
                  label: previewText('Ø Geschwindigkeit', 'Avg speed'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Links gegen rechts: die Verteilung, die Symmetrie, die Leistung je Seite.
class _Balance extends StatelessWidget {
  const _Balance({required this.report});
  final SessionReport report;

  @override
  Widget build(BuildContext context) {
    final recap = report.recap;
    final power = report.sidePower;
    final symmetry = giuliaValidPercent(recap?.symmetryPercent);
    final classic = recap?.hasClassicStrokes ?? false;
    final caption = symmetry != null
        ? previewText(
            '${symmetry.round()} % Symmetrie',
            '${symmetry.round()}% symmetry',
          )
        : classic
        ? previewText(
            'Klassikzüge L / R: ${recap!.classicLeftStrokeCount} / '
                '${recap.classicRightStrokeCount}',
            'Classic strokes L / R: ${recap.classicLeftStrokeCount} / '
                '${recap.classicRightStrokeCount}',
          )
        : null;
    final share = report.leftShare;
    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GiuliaBalance(
            leftShare: share,
            caption: caption,
            unavailableReason: classic && caption != null
                ? caption
                : previewText(
                    'Zu wenige gültige Züge',
                    'Too few valid strokes',
                  ),
            fontSize: GiuliaTokens.metricPrimary * .8,
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          Row(
            children: [
              Expanded(
                child: GiuliaMetric(
                  value: share == null
                      ? giuliaMissing
                      : giuliaNumber(power?.left),
                  unit: 'W',
                  label: previewText('Leistung links', 'Power left'),
                  tone: GiuliaTokens.sideLeft,
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: GiuliaMetric(
                    value: share == null
                        ? giuliaMissing
                        : giuliaNumber(power?.right),
                    unit: 'W',
                    label: previewText('Leistung rechts', 'Power right'),
                    tone: GiuliaTokens.sideRight,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Die komplette Einheit als synchronisierte Zugfolge. Alle Teilspuren nutzen
/// dieselbe Zeitachse; Aufzeichnungsluecken werden nicht ueberzeichnet.
class _CompleteTimelineSection extends StatelessWidget {
  const _CompleteTimelineSection({required this.analysis, this.heartRate});

  final CompleteSessionAnalysis analysis;
  final HeartRateAnalysis? heartRate;

  @override
  Widget build(BuildContext context) {
    final timeline = analysis.timeline;
    final strokeEnd = timeline.isEmpty ? 0.0 : timeline.last.elapsedSeconds;
    final hrEnd =
        !analysis.usesSessionClock ||
            heartRate?.wallDuration.inMicroseconds == null
        ? 0.0
        : heartRate!.wallDuration.inMicroseconds /
              Duration.microsecondsPerSecond;
    final xMaximum = math.max(strokeEnd, hrEnd).clamp(1.0, double.infinity);
    List<_TimelinePoint> strokePoints(
      double? Function(StrokeTimelinePoint point) value,
    ) {
      final result = <_TimelinePoint>[];
      for (final (index, point) in timeline.indexed) {
        final y = value(point);
        if (y == null) continue;
        result.add(
          _TimelinePoint(
            x: point.elapsedSeconds,
            y: y,
            continuous:
                index > 0 &&
                point.cadencePerMinute != null &&
                timeline[index - 1].cadencePerMinute != null,
          ),
        );
      }
      return result;
    }

    final hr = analysis.usesSessionClock ? heartRate : null;
    final heartRatePoints = hr == null
        ? const <_TimelinePoint>[]
        : <_TimelinePoint>[
            for (final (index, sample) in hr.samples.indexed)
              _TimelinePoint(
                x:
                    (sample.recordedAtUs - hr.sessionStartUtcUs) /
                    Duration.microsecondsPerSecond,
                y: sample.bpm.toDouble(),
                continuous:
                    index > 0 && hr.isContinuous(hr.samples[index - 1], sample),
              ),
          ];

    return GiuliaSection(
      key: const Key('session-complete-timeline'),
      title: (mircoPreview ? 'Complete timeline' : 'Kompletter Verlauf'),
      subtitle: analysis.usesSessionClock
          ? (mircoPreview
                ? '${timeline.length} valid strokes · shared heart rate timeline · gaps are not smoothed'
                : '${timeline.length} gültige Züge · gemeinsame Zeitachse mit HF · '
                      'keine Glättung über Messlücken')
          : (mircoPreview
                ? '${timeline.length} valid strokes · time from first valid stroke · heart rate shown separately because this older session has no clock anchor'
                : '${timeline.length} gültige Züge · Zeit ab erstem gültigen Zug · '
                      'HF separat, weil diese alte Einheit keinen Uhrenanker enthält'),
      child: GiuliaPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TimelineMetricChart(
              label: (mircoPreview
                  ? 'ACTIVE STROKE POWER'
                  : 'AKTIVE ZUGLEISTUNG'),
              unit: 'W',
              colour: GiuliaTokens.chartLine,
              points: strokePoints((point) => point.activePowerWatt),
              xMaximum: xMaximum,
              includeZero: true,
            ),
            const Divider(height: GiuliaTokens.spacingL),
            _TimelineMetricChart(
              label: (mircoPreview ? 'STROKE RATE' : 'ZUGFREQUENZ'),
              unit: (mircoPreview ? 'strokes/min' : 'Züge/min'),
              colour: GiuliaTokens.sideRight,
              points: strokePoints((point) => point.cadencePerMinute),
              xMaximum: xMaximum,
            ),
            const Divider(height: GiuliaTokens.spacingL),
            _TimelineMetricChart(
              label: (mircoPreview ? 'WORK PER STROKE' : 'ARBEIT JE ZUG'),
              unit: 'J',
              colour: GiuliaTokens.warning,
              points: strokePoints((point) => point.workJoule),
              xMaximum: xMaximum,
              includeZero: true,
            ),
            const Divider(height: GiuliaTokens.spacingL),
            _TimelineMetricChart(
              label: (mircoPreview ? 'LEFT SHARE' : 'ANTEIL LINKS'),
              unit: '%',
              colour: GiuliaTokens.sideLeft,
              points: strokePoints(
                (point) =>
                    point.leftShare == null ? null : point.leftShare! * 100,
              ),
              xMaximum: xMaximum,
              reference: 50,
            ),
            if (heartRatePoints.isNotEmpty) ...[
              const Divider(height: GiuliaTokens.spacingL),
              _TimelineMetricChart(
                label: (mircoPreview ? 'HEART RATE' : 'HERZFREQUENZ'),
                unit: 'bpm',
                colour: GiuliaTokens.heartRate,
                points: heartRatePoints,
                xMaximum: xMaximum,
              ),
            ],
            const SizedBox(height: GiuliaTokens.spacingS),
            Text(
              (mircoPreview
                  ? 'x: time from start (min:s). Stroke rate uses the interval between consecutive stroke starts; longer pauses remain gaps.'
                  : 'x: Zeit seit Beginn (min:s). Zugfrequenz wird aus dem Abstand '
                        'aufeinanderfolgender Zugstarts berechnet; längere Pausen '
                        'bleiben Lücken.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelinePoint {
  const _TimelinePoint({
    required this.x,
    required this.y,
    required this.continuous,
  });

  final double x;
  final double y;
  final bool continuous;
}

class _TimelineMetricChart extends StatelessWidget {
  const _TimelineMetricChart({
    required this.label,
    required this.unit,
    required this.colour,
    required this.points,
    required this.xMaximum,
    this.includeZero = false,
    this.reference,
  });

  final String label;
  final String unit;
  final Color colour;
  final List<_TimelinePoint> points;
  final double xMaximum;
  final bool includeZero;
  final double? reference;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Text('$label · keine belastbaren Werte');
    }
    final minimum = points.fold<double>(
      points.first.y,
      (value, point) => math.min(value, point.y),
    );
    final maximum = points.fold<double>(
      points.first.y,
      (value, point) => math.max(value, point.y),
    );
    final scale = NiceScale.forRange(
      reference == null ? minimum : math.min(minimum, reference!),
      reference == null ? maximum : math.max(maximum, reference!),
      includeZero: includeZero,
      targetTicks: 4,
    );
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: '$label über die Trainingszeit in $unit',
      child: SizedBox(
        height: 132,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(width: 10, height: 3, color: colour),
                const SizedBox(width: GiuliaTokens.spacingS),
                Text(label, style: text.labelSmall),
                const Spacer(),
                Text('y: $unit', style: text.labelSmall),
              ],
            ),
            const SizedBox(height: GiuliaTokens.spacingXs),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 42,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          scale.format(scale.ticks.last),
                          style: text.labelSmall,
                        ),
                        Text(
                          scale.format(scale.ticks.first),
                          style: text.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: GiuliaTokens.spacingS),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: CustomPaint(
                            painter: _TimelinePainter(
                              points: points,
                              scale: scale,
                              xMaximum: xMaximum,
                              colour: colour,
                              reference: reference,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const _CompactTime(seconds: 0),
                            _CompactTime(seconds: xMaximum / 2),
                            _CompactTime(seconds: xMaximum),
                          ],
                        ),
                      ],
                    ),
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

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.points,
    required this.scale,
    required this.xMaximum,
    required this.colour,
    this.reference,
  });

  final List<_TimelinePoint> points;
  final NiceScale scale;
  final double xMaximum;
  final Color colour;
  final double? reference;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = GiuliaTokens.chartGrid
      ..strokeWidth = 1;
    for (var index = 0; index < scale.ticks.length; index++) {
      final y = size.height * index / (scale.ticks.length - 1);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    double x(double value) => value / xMaximum * size.width;
    double y(double value) =>
        size.height * (1 - scale.normalize(value).clamp(0.0, 1.0));
    if (reference case final value?) {
      canvas.drawLine(
        Offset(0, y(value)),
        Offset(size.width, y(value)),
        Paint()
          ..color = GiuliaTokens.chartReference
          ..strokeWidth = 1,
      );
    }
    final path = Path();
    var hasStarted = false;
    for (final point in points) {
      final offset = Offset(x(point.x), y(point.y));
      if (point.continuous && hasStarted) {
        path.lineTo(offset.dx, offset.dy);
      } else {
        path.moveTo(offset.dx, offset.dy);
      }
      hasStarted = true;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = colour.withValues(alpha: .78)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );
    final dot = Paint()..color = colour;
    for (final point in points) {
      canvas.drawCircle(Offset(x(point.x), y(point.y)), 1.7, dot);
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.scale != scale ||
      oldDelegate.xMaximum != xMaximum ||
      oldDelegate.colour != colour ||
      oldDelegate.reference != reference;
}

class _CompactTime extends StatelessWidget {
  const _CompactTime({required this.seconds});
  final double seconds;

  @override
  Widget build(BuildContext context) {
    final whole = seconds.round();
    return Text(
      '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}',
      style: Theme.of(context).textTheme.labelSmall,
    );
  }
}

class _FatigueSection extends StatelessWidget {
  const _FatigueSection({required this.analysis});

  final CompleteSessionAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final fatigue = analysis.fatigue;
    if (fatigue == null) {
      return const GiuliaSection(
        key: Key('session-fatigue-analysis'),
        title: (mircoPreview ? 'Fatigue over time' : 'Ermüdungsverlauf'),
        child: GiuliaEmptyState(
          icon: Icons.compare_arrows,
          title: (mircoPreview
              ? 'Not enough data for fatigue analysis'
              : 'Noch keine belastbare Ermüdungsanalyse'),
          description: (mircoPreview
              ? 'GIULIA needs at least 25 valid strokes so the first and last fifth each contain enough data.'
              : 'Dafür braucht GIULIA mindestens 25 gültige Züge, damit '
                    'erstes und letztes Fünftel jeweils ausreichend groß sind.'),
        ),
      );
    }
    final observations = _fatigueObservations(fatigue);
    return GiuliaSection(
      key: const Key('session-fatigue-analysis'),
      title: (mircoPreview ? 'Fatigue over time' : 'Ermüdungsverlauf'),
      subtitle: (mircoPreview
          ? 'First ${fatigue.windowStrokes} vs last ${fatigue.windowStrokes} strokes · measured changes, no score'
          : 'Erste ${fatigue.windowStrokes} gegen letzte '
                '${fatigue.windowStrokes} Züge · Rohveränderungen, kein Score'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GiuliaPanel(
            child: Column(
              children: [
                const _ComparisonHeader(),
                _ComparisonRow(
                  label: (mircoPreview
                      ? 'Active stroke power'
                      : 'Aktive Zugleistung'),
                  first: fatigue.first.activePowerWatt,
                  last: fatigue.last.activePowerWatt,
                  delta: fatigue.powerDeltaPercent,
                  unit: 'W',
                ),
                _ComparisonRow(
                  label: (mircoPreview ? 'Work per stroke' : 'Arbeit je Zug'),
                  first: fatigue.first.workPerStrokeJoule,
                  last: fatigue.last.workPerStrokeJoule,
                  delta: fatigue.workDeltaPercent,
                  unit: 'J',
                ),
                _ComparisonRow(
                  label: (mircoPreview ? 'Stroke rate' : 'Zugfrequenz'),
                  first: fatigue.first.cadencePerMinute,
                  last: fatigue.last.cadencePerMinute,
                  delta: fatigue.cadenceDeltaPercent,
                  unit: '/min',
                ),
                _ComparisonRow(
                  label: (mircoPreview ? 'Average peak' : 'Mittlerer Peak'),
                  first: fatigue.first.peakPowerWatt,
                  last: fatigue.last.peakPowerWatt,
                  delta: fatigue.peakDeltaPercent,
                  unit: 'W',
                ),
                _ComparisonRow(
                  label: (mircoPreview ? 'Left share' : 'Anteil links'),
                  first: fatigue.first.leftShare == null
                      ? null
                      : fatigue.first.leftShare! * 100,
                  last: fatigue.last.leftShare == null
                      ? null
                      : fatigue.last.leftShare! * 100,
                  delta: fatigue.leftShareDeltaPercentagePoints,
                  unit: '%',
                  deltaUnit: 'pp',
                ),
                if (fatigue.firstHeartRate != null &&
                    fatigue.lastHeartRate != null)
                  _ComparisonRow(
                    label: (mircoPreview
                        ? 'Heart rate in window'
                        : 'HF im Zeitfenster'),
                    first: fatigue.firstHeartRate!.averageBpm,
                    last: fatigue.lastHeartRate!.averageBpm,
                    delta: fatigue.heartRateDeltaBpm,
                    unit: 'bpm',
                    deltaUnit: 'bpm',
                  ),
              ],
            ),
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          GiuliaPanel(
            tone: GiuliaTokens.surface2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (mircoPreview
                      ? 'STROKE SHAPE UNDER LOAD'
                      : 'ZUGFORM UNTER BELASTUNG'),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: GiuliaTokens.spacingS),
                Wrap(
                  spacing: GiuliaTokens.spacingL,
                  runSpacing: GiuliaTokens.spacingS,
                  children: [
                    _InlineFact(
                      label: (mircoPreview
                          ? 'Left shape drift'
                          : 'Formdrift links'),
                      value: _percentOrMissing(fatigue.leftShapeDriftPercent),
                    ),
                    _InlineFact(
                      label: (mircoPreview
                          ? 'Right shape drift'
                          : 'Formdrift rechts'),
                      value: _percentOrMissing(fatigue.rightShapeDriftPercent),
                    ),
                    _InlineFact(
                      label: (mircoPreview
                          ? 'Left peak position'
                          : 'Peaklage links'),
                      value: _pointsOrMissing(
                        fatigue.leftPeakPhaseDeltaPercentagePoints,
                      ),
                    ),
                    _InlineFact(
                      label: (mircoPreview
                          ? 'Right peak position'
                          : 'Peaklage rechts'),
                      value: _pointsOrMissing(
                        fatigue.rightPeakPhaseDeltaPercentagePoints,
                      ),
                    ),
                  ],
                ),
                if (observations.isNotEmpty) ...[
                  const SizedBox(height: GiuliaTokens.spacingM),
                  for (final observation in observations)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: GiuliaTokens.spacingXs,
                      ),
                      child: Text('• $observation'),
                    ),
                ],
                if (fatigue.firstPowerPerHeartRate != null &&
                    fatigue.lastPowerPerHeartRate != null) ...[
                  const SizedBox(height: GiuliaTokens.spacingM),
                  Text(
                    'P/HF deskriptiv: '
                    'von ${fatigue.firstPowerPerHeartRate!.toStringAsFixed(2)} auf '
                    '${fatigue.lastPowerPerHeartRate!.toStringAsFixed(2)} '
                    'W/bpm. Das ist keine physiologische Effizienzdiagnose.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<String> _fatigueObservations(SessionFatigueComparison value) {
    final findings = <String>[];
    final cadence = value.cadenceDeltaPercent;
    if (value.powerDeltaPercent < -3 &&
        cadence != null &&
        cadence.abs() < 3 &&
        value.workDeltaPercent < -3) {
      findings.add(
        (mircoPreview
            ? 'Active power falls at a similar stroke rate while work per stroke also decreases.'
            : 'Die aktive Leistung fällt bei ähnlicher Frequenz; die Arbeit je Zug '
                  'nimmt gleichzeitig ab.'),
      );
    }
    if (value.powerDeltaPercent.abs() < 3 &&
        cadence != null &&
        cadence > 3 &&
        value.workDeltaPercent < -3) {
      findings.add(
        (mircoPreview
            ? 'Similar power is maintained with a higher stroke rate and less work per stroke.'
            : 'Ähnliche Leistung wird mit höherer Frequenz und weniger Arbeit je '
                  'Zug aufrechterhalten.'),
      );
    }
    if ((value.leftShareDeltaPercentagePoints?.abs() ?? 0) >= 2) {
      findings.add(
        (mircoPreview
            ? 'The left/right distribution changes measurably.'
            : 'Die Links-rechts-Verteilung verschiebt sich messbar.'),
      );
    }
    final hr = value.heartRateDeltaBpm;
    if (value.powerDeltaPercent.abs() < 3 && hr != null && hr >= 5) {
      findings.add(
        (mircoPreview
            ? 'Heart rate rises at similar mechanical power. Increasing internal load is a possible explanation, not a diagnosis.'
            : 'Bei ähnlicher mechanischer Leistung steigt die HF. Steigende interne '
                  'Belastung ist eine mögliche Erklärung, keine Diagnose.'),
      );
    }
    return findings;
  }
}

class _ComparisonHeader extends StatelessWidget {
  const _ComparisonHeader();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(flex: 3, child: SizedBox()),
      for (final label in const [
        (mircoPreview ? 'FIRST 20 %' : 'ERSTE 20 %'),
        (mircoPreview ? 'LAST 20 %' : 'LETZTE 20 %'),
        'Δ',
      ])
        Expanded(
          flex: 2,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
    ],
  );
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
    required this.label,
    required this.first,
    required this.last,
    required this.delta,
    required this.unit,
    this.deltaUnit = '%',
  });

  final String label;
  final double? first;
  final double? last;
  final double? delta;
  final String unit;
  final String deltaUnit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: GiuliaTokens.spacingS),
    child: Row(
      children: [
        Expanded(flex: 3, child: Text(label)),
        Expanded(
          flex: 2,
          child: Text(
            first == null ? giuliaMissing : '${giuliaNumber(first)} $unit',
            textAlign: TextAlign.right,
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            last == null ? giuliaMissing : '${giuliaNumber(last)} $unit',
            textAlign: TextAlign.right,
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            delta == null
                ? giuliaMissing
                : '${delta! >= 0 ? '+' : ''}${giuliaNumber(delta, decimals: 1)} $deltaUnit',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: delta == null
                  ? GiuliaTokens.textMuted
                  : delta!.abs() < .05
                  ? GiuliaTokens.textSecondary
                  : delta! < 0
                  ? GiuliaTokens.warning
                  : GiuliaTokens.accent,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PerformanceProfiles extends StatelessWidget {
  const _PerformanceProfiles({required this.analysis});

  final CompleteSessionAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    return GiuliaSection(
      key: const Key('session-performance-profiles'),
      title: (mircoPreview
          ? 'Session performance profiles'
          : 'Leistungsprofile dieser Einheit'),
      subtitle: (mircoPreview
          ? 'Time windows: work / total window duration · stroke windows: active power of consecutive strokes'
          : 'Zeitfenster: Arbeit / gesamte Fensterdauer · Zugfenster: aktive '
                'Leistung der zusammenhängenden Züge'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GiuliaPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ERCOLINA POWER-DURATION',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: GiuliaTokens.spacingS),
                if (analysis.powerDuration.isEmpty)
                  const Text(
                    (mircoPreview
                        ? 'The session is too short for a complete time window.'
                        : 'Einheit zu kurz für ein vollständiges Zeitfenster.'),
                  )
                else
                  for (final best in analysis.powerDuration)
                    _PowerDurationRow(best: best),
              ],
            ),
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          GiuliaPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'STROKE-DURATION',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: GiuliaTokens.spacingS),
                if (analysis.strokeCountBests.isEmpty)
                  const Text(
                    (mircoPreview
                        ? 'No valid sequence of strokes available.'
                        : 'Keine gültige Zugfolge vorhanden.'),
                  )
                else
                  for (final best in analysis.strokeCountBests)
                    _StrokeCountRow(best: best),
              ],
            ),
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          GiuliaPanel(
            tone: GiuliaTokens.surface2,
            child: Wrap(
              spacing: GiuliaTokens.spacingXl,
              runSpacing: GiuliaTokens.spacingS,
              children: [
                _InlineFact(
                  label: (mircoPreview
                      ? 'Stroke shape consistency'
                      : 'Zugform-Konstanz'),
                  value: _percentOrMissing(analysis.shapeVariationPercent),
                ),
                _InlineFact(
                  label: (mircoPreview
                      ? 'L/R shape difference'
                      : 'L/R-Formunterschied'),
                  value: _percentOrMissing(
                    analysis.leftRightShapeDifferencePercent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PowerDurationRow extends StatelessWidget {
  const _PowerDurationRow({required this.best});
  final PowerDurationBest best;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: GiuliaTokens.spacingS),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(width: 54, child: Text(_windowLabel(best.duration))),
            Text(
              '${giuliaNumber(best.averagePowerWatt)} W',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            Text(
              'ab ${_windowLabel(Duration(seconds: best.startedAtSeconds.round()))}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: GiuliaTokens.spacingXs),
        Text(
          '${best.strokeCount} Züge · '
          '${giuliaNumber(best.cadencePerMinute, decimals: 1)} /min · '
          '${giuliaNumber(best.workPerStrokeJoule)} J/Zug · '
          '${best.leftShare == null ? giuliaMissing : giuliaNumber(best.leftShare! * 100, decimals: 1)} % L',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _StrokeCountRow extends StatelessWidget {
  const _StrokeCountRow({required this.best});
  final StrokeCountBest best;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: GiuliaTokens.spacingS),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(
                '${best.strokeCount} Zug${best.strokeCount == 1 ? '' : 'e'}',
              ),
            ),
            Text(
              '${giuliaNumber(best.activePowerWatt)} W',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            Text(
              'ab Zug ${best.firstStrokeIndex}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: GiuliaTokens.spacingXs),
        Text(
          '${giuliaNumber(best.workPerStrokeJoule)} J/Zug · '
          'Peak ${giuliaNumber(best.peakPowerWatt)} W · '
          '${giuliaNumber(best.cadencePerMinute, decimals: 1)} /min · '
          '${best.leftShare == null ? giuliaMissing : giuliaNumber(best.leftShare! * 100, decimals: 1)} % L · '
          'Form ${_percentOrMissing(best.shapeVariationPercent)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _InlineFact extends StatelessWidget {
  const _InlineFact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      Text(value, style: Theme.of(context).textTheme.titleSmall),
    ],
  );
}

String _windowLabel(Duration duration) {
  final seconds = duration.inSeconds;
  return seconds < 60 ? '$seconds s' : '${seconds ~/ 60} min';
}

String _percentOrMissing(double? value) =>
    value == null ? giuliaMissing : '${giuliaNumber(value, decimals: 1)} % RMS';

String _pointsOrMissing(double? value) => value == null
    ? giuliaMissing
    : '${value >= 0 ? '+' : ''}${giuliaNumber(value, decimals: 1)} pp';

/// Vollständige HF der Einheit: Kennzahlen, unverfälschter Zeitverlauf und –
/// nur mit individueller HFmax – zeitgewichtete Zonen.
class _HeartRateSection extends StatelessWidget {
  const _HeartRateSection({required this.analysis});

  final HeartRateAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    final value = analysis;
    if (value == null) {
      return const GiuliaSection(
        key: Key('session-heart-rate'),
        title: (mircoPreview ? 'Heart rate' : 'Herzfrequenz'),
        child: GiuliaEmptyState(
          icon: Icons.monitor_heart_outlined,
          title: (mircoPreview
              ? 'No valid heart rate recorded'
              : 'Keine gültige HF aufgezeichnet'),
          description: (mircoPreview
              ? 'No reliable strap readings are available for this session. GIULIA does not estimate missing heart rate.'
              : 'Für diese Einheit liegen keine belastbaren Gurtwerte vor. '
                    'GIULIA ergänzt keine Herzfrequenz aus Schätzungen.'),
        ),
      );
    }

    final coverage = value.coverage;
    final quality = <String>[
      (mircoPreview
          ? '${value.samples.length} valid readings'
          : '${value.samples.length} gültige Messpunkte'),
      (mircoPreview
          ? '${_duration(value.measuredDuration)} continuously measured'
          : '${_duration(value.measuredDuration)} kontinuierlich gemessen'),
      if (coverage != null)
        (mircoPreview
            ? '${(coverage * 100).round()} % time coverage'
            : '${(coverage * 100).round()} % Zeitabdeckung'),
      if (value.rrIntervalCount > 0)
        (mircoPreview
            ? '${value.rrIntervalCount} recorded RR intervals'
            : '${value.rrIntervalCount} gespeicherte RR-Intervalle'),
      if (value.rejectedContactSamples > 0)
        (mircoPreview
            ? '${value.rejectedContactSamples} readings without strap contact rejected'
            : '${value.rejectedContactSamples} Werte ohne Gurtkontakt verworfen'),
    ].join(' · ');

    return GiuliaSection(
      key: const Key('session-heart-rate'),
      title: (mircoPreview ? 'Heart rate' : 'Herzfrequenz'),
      subtitle: (mircoPreview
          ? 'Measured strap data · radio gaps are not interpolated'
          : 'Gemessener Gurtverlauf – keine interpolierten Funklücken'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GiuliaPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GiuliaMetricRow(
                  minItemWidth: 105,
                  children: [
                    GiuliaMetric(
                      key: const Key('session-heart-rate-average'),
                      value: giuliaNumber(value.averageBpm),
                      unit: 'bpm',
                      label: (mircoPreview
                          ? 'Average heart rate'
                          : 'Ø Herzfrequenz'),
                      tone: GiuliaTokens.heartRate,
                      size: GiuliaMetricSize.primary,
                    ),
                    GiuliaMetric(
                      key: const Key('session-heart-rate-maximum'),
                      value: '${value.maximumBpm}',
                      unit: 'bpm',
                      label: 'Maximum',
                    ),
                    GiuliaMetric(
                      value: '${value.minimumBpm}',
                      unit: 'bpm',
                      label: 'Minimum',
                    ),
                    if (coverage != null)
                      GiuliaMetric(
                        value: '${(coverage * 100).round()}',
                        unit: '%',
                        label: (mircoPreview ? 'Coverage' : 'Abdeckung'),
                      ),
                  ],
                ),
                const SizedBox(height: GiuliaTokens.spacingM),
                Text(quality, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          GiuliaChartCard(
            key: const Key('session-heart-rate-chart'),
            title: (mircoPreview ? 'Heart rate timeline' : 'HF-Verlauf'),
            legend: const [
              GiuliaLegendItem(
                label: (mircoPreview ? 'HEART RATE' : 'HERZFREQUENZ'),
                colour: GiuliaTokens.heartRate,
              ),
              GiuliaLegendItem(
                label: (mircoPreview
                    ? 'TIME-WEIGHTED MEAN'
                    : 'ZEITGEWICHTETES MITTEL'),
                colour: GiuliaTokens.chartReference,
              ),
            ],
            range: _duration(value.wallDuration),
            interpretation: (mircoPreview
                ? 'x: time from training start (min:s) · y: heart rate (bpm) · line gaps indicate missing readings'
                : 'x: Zeit seit Trainingsstart (min:s) · y: Herzfrequenz '
                      '(bpm) · Linienlücken markieren fehlende Messwerte'),
            child: _HeartRateChart(analysis: value),
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          if (value.hasZones)
            _HeartRateZones(analysis: value)
          else
            const GiuliaPanel(
              child: Text(
                (mircoPreview
                    ? 'Heart rate zones unavailable: maximum heart rate is missing from the athlete profile. GIULIA does not substitute an age-based estimate.'
                    : 'Keine HF-Zonen berechnet: Im Athletenprofil fehlt eine '
                          'individuelle maximale Herzfrequenz. GIULIA verwendet keine '
                          'altersbasierte Schätzung als Ersatz.'),
              ),
            ),
        ],
      ),
    );
  }

  static String _duration(Duration duration) {
    final seconds = duration.inSeconds;
    final minutes = seconds ~/ 60;
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')} min';
  }
}

class _HeartRateZones extends StatelessWidget {
  const _HeartRateZones({required this.analysis});

  final HeartRateAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final totalUs = analysis.classifiedDuration.inMicroseconds;
    String range(HeartRateZoneDuration zone) => switch (zone) {
      HeartRateZoneDuration(ordinal: 0, :final upperBpm) =>
        '< ${(upperBpm ?? 0) + 1} bpm',
      HeartRateZoneDuration(:final lowerBpm, upperBpm: null) =>
        '≥ $lowerBpm bpm',
      HeartRateZoneDuration(:final lowerBpm, :final upperBpm) =>
        '$lowerBpm–$upperBpm bpm',
    };
    String clock(Duration duration) {
      final seconds = duration.inSeconds;
      return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    }

    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                (mircoPreview
                    ? 'TIME IN HEART RATE ZONES'
                    : 'ZEIT IN HF-ZONEN'),
                style: text.labelMedium,
              ),
              const Spacer(),
              Text(
                'HFmax ${analysis.profileMaximumBpm} bpm',
                style: text.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          Text(
            (mircoPreview
                ? '5 zones based on % HRmax · continuously measured time only'
                : '5-Zonen-Modell nach % HFmax · nur kontinuierlich gemessene Zeit'),
            style: text.bodySmall,
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          for (final zone in analysis.zones) ...[
            Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(zone.label, style: text.labelMedium),
                ),
                SizedBox(
                  width: 94,
                  child: Text(range(zone), style: text.bodySmall),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 10,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final share = totalUs <= 0
                              ? 0.0
                              : zone.duration.inMicroseconds / totalUs;
                          return Stack(
                            children: [
                              ColoredBox(
                                color: GiuliaTokens.surface3,
                                child: SizedBox.expand(),
                              ),
                              SizedBox(
                                width: constraints.maxWidth * share,
                                child: ColoredBox(
                                  color: giuliaZoneColour(
                                    zone.ordinal,
                                    analysis.zones.length,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: GiuliaTokens.spacingS),
                SizedBox(
                  width: 44,
                  child: Text(
                    clock(zone.duration),
                    textAlign: TextAlign.right,
                    style: text.labelSmall,
                  ),
                ),
              ],
            ),
            if (zone != analysis.zones.last)
              const SizedBox(height: GiuliaTokens.spacingS),
          ],
        ],
      ),
    );
  }
}

class _HeartRateChart extends StatelessWidget {
  const _HeartRateChart({required this.analysis});

  final HeartRateAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final scale = NiceScale.forRange(
      analysis.minimumBpm.toDouble(),
      analysis.maximumBpm.toDouble(),
      targetTicks: 5,
    );
    final elapsedUs = analysis.wallDuration.inMicroseconds.clamp(1, 1 << 62);
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: 'Herzfrequenz über die Trainingszeit in Schlägen pro Minute',
      child: SizedBox(
        height: 220,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 42,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final tick in scale.ticks.reversed)
                      Text(
                        tick == scale.ticks.last
                            ? '${scale.format(tick)} bpm'
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
                      painter: _HeartRatePainter(
                        analysis: analysis,
                        scale: scale,
                        elapsedUs: elapsedUs,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  const SizedBox(height: GiuliaTokens.spacingXs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const _AxisTime(value: 0),
                      _AxisTime(value: elapsedUs ~/ 2),
                      _AxisTime(value: elapsedUs),
                    ],
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

class _HeartRatePainter extends CustomPainter {
  const _HeartRatePainter({
    required this.analysis,
    required this.scale,
    required this.elapsedUs,
  });

  final HeartRateAnalysis analysis;
  final NiceScale scale;
  final int elapsedUs;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = GiuliaTokens.chartGrid
      ..strokeWidth = 1;
    for (var index = 0; index < scale.ticks.length; index++) {
      final y = size.height * index / (scale.ticks.length - 1);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    double x(HeartRateSample sample) =>
        ((sample.recordedAtUs - analysis.sessionStartUtcUs) / elapsedUs).clamp(
          0.0,
          1.0,
        ) *
        size.width;
    double y(double bpm) =>
        size.height * (1 - scale.normalize(bpm).clamp(0.0, 1.0));

    final averageY = y(analysis.averageBpm);
    canvas.drawLine(
      Offset(0, averageY),
      Offset(size.width, averageY),
      Paint()
        ..color = GiuliaTokens.chartReference.withValues(alpha: .75)
        ..strokeWidth = 1.2,
    );

    final path = Path();
    var hasLine = false;
    HeartRateSample? previous;
    for (final sample in analysis.samples) {
      final point = Offset(x(sample), y(sample.bpm.toDouble()));
      final continuous =
          previous != null && analysis.isContinuous(previous, sample);
      if (!continuous) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
        hasLine = true;
      }
      previous = sample;
    }
    if (hasLine) {
      canvas.drawPath(
        path,
        Paint()
          ..color = GiuliaTokens.heartRate
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    final points = Paint()..color = GiuliaTokens.heartRate;
    if (analysis.samples.length == 1) {
      final sample = analysis.samples.single;
      canvas.drawCircle(Offset(x(sample), y(sample.bpm.toDouble())), 3, points);
    }
  }

  @override
  bool shouldRepaint(_HeartRatePainter oldDelegate) =>
      oldDelegate.analysis != analysis || oldDelegate.scale != scale;
}

class _StrokeAnalysis extends StatelessWidget {
  const _StrokeAnalysis({required this.report});
  final SessionReport report;

  @override
  Widget build(BuildContext context) {
    final work = report.workPerStroke;
    // Kein Wert bei zu wenigen Zügen: Aus fünf Zügen einen Abfall zu lesen
    // wäre Kaffeesatz.
    final tooFew = report.fatiguePercent == null
        ? previewText('Zu wenige gültige Züge', 'Too few valid strokes')
        : null;
    return GiuliaMetricRow(
      minItemWidth: 110,
      children: [
        GiuliaMetric(
          value: giuliaNumber(work?.total),
          unit: 'J',
          label: previewText(
            (mircoPreview ? 'Work per stroke' : 'Arbeit je Zug'),
            'Work per stroke',
          ),
        ),
        GiuliaMetric(
          value: giuliaNumber(report.powerVariationPercent, decimals: 1),
          unit: '%',
          label: previewText('Streuung', 'Variation'),
        ),
        GiuliaMetric(
          value: giuliaNumber(report.fatiguePercent, decimals: 1),
          unit: '%',
          label: previewText(
            (mircoPreview ? 'Fatigue' : 'Ermüdung'),
            'Fatigue',
          ),
          caption: tooFew,
        ),
      ],
    );
  }
}

/// Ein Abschnitt: was vorgegeben war, was daraus wurde.
class _IntervalRow extends StatelessWidget {
  const _IntervalRow({required this.interval});
  final RecordedInterval interval;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final within = interval.withinTarget;
    final minutes = interval.duration.inMinutes;
    final seconds = interval.duration.inSeconds % 60;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GiuliaTokens.spacingS),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  previewWorkoutStepKind(interval.kind),
                  style: text.bodyMedium,
                ),
                Text(
                  '$minutes:${seconds.toString().padLeft(2, '0')}',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                GiuliaValue(
                  value: giuliaNumber(interval.shownPowerWatt),
                  unit: 'W',
                  fontSize: 18,
                ),
                Text(
                  previewText('aktive Zugleistung', 'active stroke power'),
                  style: text.bodySmall,
                ),
                if (interval.averagePowerWatt case final sectionPower?)
                  Text(
                    previewText(
                      '${giuliaNumber(sectionPower)} W Abschnitt inkl. Pausen',
                      '${giuliaNumber(sectionPower)} W interval incl. pauses',
                    ),
                    style: text.bodySmall,
                  ),
                if (interval.medianStrokePowerWatt case final median?)
                  Text(
                    'Median ${giuliaNumber(median)} W · '
                    '${interval.strokeCount} ${previewText('Züge', 'strokes')}',
                    style: text.bodySmall,
                  )
                else if (interval.strokeCount > 0)
                  Text(
                    '${interval.strokeCount} ${previewText('Züge', 'strokes')}',
                    style: text.bodySmall,
                  ),
                if (interval.fatigueDeltaPercent case final fatigue?)
                  Text(
                    previewText(
                      'Erstes auf letztes Fünftel '
                          '${fatigue >= 0 ? '+' : ''}'
                          '${giuliaNumber(fatigue, decimals: 1)} %',
                      'First to last fifth '
                          '${fatigue >= 0 ? '+' : ''}'
                          '${giuliaNumber(fatigue, decimals: 1)}%',
                    ),
                    style: text.bodySmall?.copyWith(
                      color: fatigue < -3
                          ? GiuliaTokens.warning
                          : GiuliaTokens.textSecondary,
                    ),
                  ),
                if (interval.hasTarget)
                  Text(
                    '${previewText('Ziel', 'Target')} '
                    '${interval.targetMinWatt!.round()}–'
                    '${interval.targetMaxWatt!.round()} W',
                    style: text.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(width: GiuliaTokens.spacingS),
          SizedBox(
            width: GiuliaTokens.iconM,
            child: within == null
                ? null
                : Icon(
                    within ? Icons.check_circle : Icons.remove_circle_outline,
                    size: GiuliaTokens.iconS,
                    color: within ? GiuliaTokens.success : GiuliaTokens.warning,
                  ),
          ),
        ],
      ),
    );
  }
}

class _AxisTime extends StatelessWidget {
  const _AxisTime({required this.value});
  final int value;

  @override
  Widget build(BuildContext context) {
    final seconds = value ~/ Duration.microsecondsPerSecond;
    final minutes = seconds ~/ 60;
    return Text(
      '$minutes:${(seconds % 60).toString().padLeft(2, '0')}',
      style: Theme.of(context).textTheme.labelSmall,
    );
  }
}
