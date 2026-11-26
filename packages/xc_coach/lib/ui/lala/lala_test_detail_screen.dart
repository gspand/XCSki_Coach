/// Detail of one lactate test: raw data, curve, thresholds, methods, zones and
/// the provenance of every number shown.
///
/// If a test carries several calculation runs, they stay distinguishable and
/// switchable. A later run never overwrites an earlier reading — it stands
/// beside it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xc_coach/lala/application/lala_controller.dart';
import 'package:xc_coach/lala/application/lala_view_models.dart';
import 'package:xc_coach/app/intelligence_factory.dart';
import 'package:xc_coach/ui/intelligence/giulia_coach.dart';
import 'package:xc_coach/export/diagnostic_report_sharing.dart';
import 'package:xc_coach/ui/design_system.dart';
import 'package:xc_coach/ui/orthography.dart';
import 'package:xc_coach/ui/vocabulary.dart';
import 'package:xc_coach/ui/lala/lala_comparison_screen.dart';
import 'package:xc_coach/ui/lala/lala_metabolic_technique_screen.dart';
import 'package:xc_coach/ui/lala/lala_widgets.dart';

class LalaTestDetailScreen extends StatefulWidget {
  const LalaTestDetailScreen({
    super.key,
    required this.controller,
    required this.testId,
  });

  final LalaController controller;
  final String testId;

  @override
  State<LalaTestDetailScreen> createState() => _LalaTestDetailScreenState();
}

class _LalaTestDetailScreenState extends State<LalaTestDetailScreen> {
  int? _runIndex;
  String? _zoneSetId;

  @override
  Widget build(BuildContext context) {
    final test = widget.controller.loadTest(widget.testId);
    final runs = test.runs;
    final selected = runs.isEmpty
        ? null
        : runs.firstWhere(
            (run) => run.runIndex == (_runIndex ?? runs.last.runIndex),
            orElse: () => runs.last,
          );

    return Scaffold(
      appBar: AppBar(
        title: Text('LaLa-Test ${formatTestDate(test.head.startedAtUtcUs)}'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _TestHeader(test: test),
          const SizedBox(height: GiuliaTokens.spacingM),
          if (runs.length > 1) ...[
            _RunSelector(
              runs: runs,
              selected: selected!,
              onSelect: (index) => setState(() => _runIndex = index),
            ),
            const SizedBox(height: GiuliaTokens.spacingM),
          ],
          if (selected != null) ...[
            LalaThresholdHero(
              lt2: selected.lt2,
              lt1: selected.lt1,
              bodyMassKg: test.data.bodyMassKg,
            ),
            const SizedBox(height: GiuliaTokens.spacingM),
            LalaLactateCurve(
              points: test.curve,
              loadUnit: test.head.loadUnit,
              lt1Load: selected.lt1?.loadValue,
              lt2Load: selected.lt2?.loadValue,
              lt1Lactate: selected.lt1?.lactateMmolPerLitre,
              lt2Lactate: selected.lt2?.lactateMmolPerLitre,
              bodyMassKg: test.data.bodyMassKg,
            ),
            const SizedBox(height: GiuliaTokens.spacingM),
            if (widget.controller.selectedAthleteId case final athleteId?) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('lala-detail-open-metabolic-profile'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LalaMetabolicTechniqueScreen(
                        controller: widget.controller,
                        athleteId: athleteId,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.monitor_heart_outlined),
                  label: const Text('Athleten-Vollauswertung öffnen'),
                ),
              ),
              const SizedBox(height: GiuliaTokens.spacingM),
            ],
          ],
          if (widget.controller.selectedAthleteId case final athleteId?) ...[
            GiuliaCoachCard(
              coach: giuliaCoachFor(
                database: widget.controller.diagnostics.database,
                platform: widget.controller.platform,
                organizationId: widget.controller.session.organizationId,
                userId: widget.controller.session.userId,
              ),
              athletes: widget.controller.athletes
                  .where((athlete) => athlete.id == athleteId)
                  .toList(growable: false),
              initialAthleteId: athleteId,
              prompt: 'Test mit GIULIA analysieren',
              questions: const [
                'Was fällt dir an meinem letzten Stufentest auf?',
                'Wie hat sich meine Schwelle verändert?',
                'Warum war mein Laktat bei gleicher Leistung höher?',
                'Warum empfiehlt GIULIA diese Trainingszone?',
              ],
            ),
            const SizedBox(height: GiuliaTokens.spacingM),
          ],

          if (selected == null)
            const GiuliaEmptyState(
              icon: Icons.calculate_outlined,
              title: 'Noch keine Auswertung',
              description:
                  'Für diesen Test wurde noch kein Calculation Run erzeugt.',
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final lt1 = LalaThresholdCard(
                  threshold: selected.lt1,
                  bodyMassKg: test.data.bodyMassKg,
                  methodOptions: _methodOptions(selected, 'lt1'),
                  onMethodSelected: (id) => _selectMethod(selected, lt1: id),
                );
                final lt2 = LalaThresholdCard(
                  threshold: selected.lt2,
                  bodyMassKg: test.data.bodyMassKg,
                  methodOptions: _methodOptions(selected, 'lt2'),
                  onMethodSelected: (id) => _selectMethod(selected, lt2: id),
                );
                if (constraints.maxWidth < 760) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      lt1,
                      const SizedBox(height: GiuliaTokens.spacingM),
                      lt2,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: lt1),
                    const SizedBox(width: GiuliaTokens.spacingM),
                    Expanded(child: lt2),
                  ],
                );
              },
            ),
            const SizedBox(height: GiuliaTokens.spacingM),
            LalaResultQualityPanel(run: selected, points: test.curve),
            const SizedBox(height: GiuliaTokens.spacingL),

            _ZoneModelSelector(
              zoneSets: selected.zoneSets,
              selectedId: _zoneSetId,
              bodyMassKg: test.data.bodyMassKg,
              onChanged: (id) => setState(() => _zoneSetId = id),
            ),

            const SizedBox(height: GiuliaTokens.spacingM),
            _RemarksCard(
              controller: widget.controller,
              testId: test.head.id,
              notes: test.head.notes,
            ),
            const SizedBox(height: GiuliaTokens.spacingM),
            _ShareReportButton(
              test: test,
              run: selected,
              zoneSet: _selectedZoneSet(selected),
              athleteName: widget.controller.overview?.athleteName ?? 'Athlet',
            ),
            const SizedBox(height: GiuliaTokens.spacingM),
            _CompareWithHistoryButton(
              controller: widget.controller,
              currentTest: test,
            ),
            const SizedBox(height: GiuliaTokens.spacingM),
            _RawDataTable(
              test: test,
              controller: widget.controller,
              onCorrected: () => setState(() => _runIndex = null),
            ),
            const SizedBox(height: GiuliaTokens.spacingM),
            _MethodTable(run: selected),
            const SizedBox(height: GiuliaTokens.spacingM),
            LalaProvenancePanel(run: selected),
          ],
        ],
      ),
    );
  }

  /// The zone model the coach is looking at, not simply the first one.
  ///
  /// The report must reproduce the screen. Printing `zoneSets.first` while the
  /// selector shows the fourth model would hand the athlete a table they never
  /// saw, and neither of them would have a way to notice.
  LalaZoneSetView? _selectedZoneSet(LalaRunView? run) {
    final sets = run?.zoneSets ?? const <LalaZoneSetView>[];
    if (sets.isEmpty) return null;
    return sets.firstWhere(
      (set) => set.id == _zoneSetId,
      orElse: () => sets.first,
    );
  }

  List<LalaThresholdView> _methodOptions(LalaRunView run, String type) => run
      .allThresholds
      .where((item) => item.type == type && item.loadValue != null)
      .toList(growable: false);

  void _selectMethod(LalaRunView run, {String? lt1, String? lt2}) {
    final runId = widget.controller.reevaluate(
      widget.testId,
      expertLt1MethodId: lt1 ?? run.lt1?.methodId,
      expertLt2MethodId: lt2 ?? run.lt2?.methodId,
    );
    if (runId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.failure?.message ?? 'Auswertung nicht erstellt.',
          ),
        ),
      );
      return;
    }
    setState(() => _runIndex = null);
  }
}

/// The diagnostician's assessment, written here and printed in the report.
///
/// This is the one place in GIULIA where a *judgement* is recorded, and it is
/// deliberately a human's: the engine says what it measured and which method
/// it used, and refuses to grade it. «Extensive aerobe Leistungsfähigkeit eher
/// schwach» is a sentence a coach who knows the athlete may write; it is not a
/// sentence software should generate from two numbers.
///
/// Saving does not re-evaluate — see [LalaController.saveNotes]. A reworded
/// sentence must not appear in the test's history as a new scientific result.
class _RemarksCard extends StatefulWidget {
  const _RemarksCard({
    required this.controller,
    required this.testId,
    this.notes,
  });

  final LalaController controller;
  final String testId;
  final String? notes;

  @override
  State<_RemarksCard> createState() => _RemarksCardState();
}

class _RemarksCardState extends State<_RemarksCard> {
  late final TextEditingController _text = TextEditingController(
    text: widget.notes ?? '',
  );
  late String _saved = widget.notes ?? '';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _changed => _text.text.trim() != _saved.trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('BEMERKUNGEN UND HINWEISE', style: theme.labelMedium),
          const SizedBox(height: 6),
          Text(
            'Die Beurteilung des Testtags. GIULIA schreibt sie nicht: Was die '
            'Zahlen für diese Athletin bedeuten, weiß die Trainerin, die sie '
            'kennt. Dieser Text steht im Bericht unter dieser Überschrift.',
            style: theme.bodyMedium,
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          TextField(
            key: const Key('lala-notes-field'),
            controller: _text,
            minLines: 3,
            maxLines: 10,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText:
                  'Ausbelastung, Tagesform, Trainingsrichtung für die '
                  'kommende Periode …',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('lala-notes-save'),
              onPressed: _changed ? _save : null,
              child: const Text('Bemerkung sichern'),
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    final value = _text.text.trim();
    final stored = widget.controller.saveNotes(
      testId: widget.testId,
      notes: value.isEmpty ? null : value,
    );
    if (!mounted) return;
    if (stored) setState(() => _saved = value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          stored
              ? 'Bemerkung gesichert. Sie steht im nächsten Bericht.'
              : widget.controller.failure?.message ??
                    'Die Bemerkung konnte nicht gesichert werden.',
        ),
      ),
    );
  }
}

/// Hands the evaluated test to the operating system's share sheet as PDF.
///
/// A separate widget because it owns a piece of state the screen around it
/// does not: the moment between tap and finished document. Rendering the curve
/// and laying out the pages takes long enough on a phone to need saying so,
/// and long enough that a second tap must not start a second render.
class _ShareReportButton extends StatefulWidget {
  const _ShareReportButton({
    required this.test,
    required this.run,
    required this.athleteName,
    this.zoneSet,
  });

  final LalaTestView test;
  final LalaRunView? run;
  final String athleteName;
  final LalaZoneSetView? zoneSet;

  @override
  State<_ShareReportButton> createState() => _ShareReportButtonState();
}

class _ShareReportButtonState extends State<_ShareReportButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      key: const Key('lala-share-report'),
      onPressed: widget.run == null || _busy ? null : _share,
      icon: _busy
          ? const SizedBox(
              width: GiuliaTokens.iconS,
              height: GiuliaTokens.iconS,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.description_outlined, size: GiuliaTokens.iconM),
      label: Text(_busy ? 'Bericht wird erstellt …' : 'Bericht weitergeben'),
    ),
  );

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final box = context.findRenderObject()! as RenderBox;
      final shared = await shareDiagnosticReport(
        origin: box.localToGlobal(Offset.zero) & box.size,
        athleteName: widget.athleteName,
        test: widget.test,
        run: widget.run,
        zoneSet: widget.zoneSet,
      );
      if (!shared && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Für diesen Test gibt es noch keine Auswertung, die ein '
              'Bericht wiedergeben könnte.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ZoneModelSelector extends StatelessWidget {
  const _ZoneModelSelector({
    required this.zoneSets,
    required this.selectedId,
    required this.onChanged,
    this.bodyMassKg,
  });

  final List<LalaZoneSetView> zoneSets;
  final String? selectedId;
  final ValueChanged<String> onChanged;
  final double? bodyMassKg;

  @override
  Widget build(BuildContext context) {
    if (zoneSets.isEmpty) return const SizedBox.shrink();
    final selected = zoneSets.firstWhere(
      (set) => set.id == selectedId,
      orElse: () => zoneSets.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TRAININGSZONEN', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: GiuliaTokens.spacingS),
        DropdownButtonFormField<String>(
          key: const Key('lala-zone-model-dropdown'),
          initialValue: selected.id,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Zonenmodell',
            isDense: true,
          ),
          items: [
            for (final zoneSet in zoneSets)
              DropdownMenuItem(
                value: zoneSet.id,
                child: Text(zoneSet.modelName, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) {
            if (id != null) onChanged(id);
          },
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        LalaZoneTable(zoneSet: selected, bodyMassKg: bodyMassKg),
      ],
    );
  }
}

class _TestHeader extends StatelessWidget {
  const _TestHeader({required this.test});
  final LalaTestView test;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GiuliaStatusLabel(
          label: 'ZEITPUNKT',
          value: formatTestDateTime(test.head.startedAtUtcUs),
        ),
        const SizedBox(height: 12),
        GiuliaStatusLabel(
          label: 'SPORTART',
          value: sportLabel(test.head.sport),
        ),
        const SizedBox(height: 12),
        GiuliaStatusLabel(
          label: 'PROTOKOLL',
          value: protocolLabel(test.head.protocol),
        ),
        const SizedBox(height: 12),
        GiuliaStatusLabel(
          label: 'MESSQUELLE',
          value: measurementSourceLabel(test.head.measurementSource),
        ),
        const SizedBox(height: 12),
        GiuliaStatusLabel(
          label: 'GERÄT',
          value: test.hasDevice ? test.head.deviceId! : 'ohne Gerät erfasst',
        ),
      ],
    ),
  );
}

class _RunSelector extends StatelessWidget {
  const _RunSelector({
    required this.runs,
    required this.selected,
    required this.onSelect,
  });

  final List<LalaRunView> runs;
  final LalaRunView selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${runs.length} AUSWERTUNGEN DIESES TESTS',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final run in runs)
              ChoiceChip(
                key: Key('lala-run-${run.runIndex}'),
                selected: run.runIndex == selected.runIndex,
                onSelected: (_) => onSelect(run.runIndex),
                label: Text(
                  '#${run.runIndex} · LaLa ${run.engineVersion} · '
                  '${formatTestDate(run.createdAtUtcUs)}',
                ),
              ),
          ],
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        Text(
          'Die Messung ist unveränderlich. Jede erneute Auswertung wird als '
          'zusätzlicher Lauf gespeichert; frühere Ergebnisse bleiben lesbar.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}

class _RawDataTable extends StatelessWidget {
  const _RawDataTable({
    required this.test,
    required this.controller,
    required this.onCorrected,
  });
  final LalaTestView test;
  final LalaController controller;
  final VoidCallback onCorrected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ROHDATEN', style: text.labelMedium),
          const SizedBox(height: GiuliaTokens.spacingS),
          Text(
            'Bei einem Eingabefehler kann eine Korrektur ergänzt werden. '
            'Der Originalwert und frühere Auswertungen bleiben nachvollziehbar.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          for (final point in test.curve) ...[
            _RawDataRow(
              point: point,
              loadUnit: test.head.loadUnit,
              onCorrect: () async {
                final changed = await showDialog<bool>(
                  context: context,
                  builder: (_) => _CorrectStageDialog(
                    controller: controller,
                    testId: test.head.id,
                    point: point,
                    loadUnit: test.head.loadUnit,
                  ),
                );
                if (changed == true) onCorrected();
              },
            ),
            if (point.excluded)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 2, bottom: 6),
                child: Text(
                  'Ausgeschlossen: ${point.exclusionReason ?? 'ohne Begründung'}',
                  style: text.bodyMedium?.copyWith(color: GiuliaTokens.warning),
                ),
              )
            else
              const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _RawDataRow extends StatelessWidget {
  const _RawDataRow({
    required this.point,
    required this.loadUnit,
    required this.onCorrect,
  });

  final LalaCurvePoint point;
  final String loadUnit;
  final VoidCallback onCorrect;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 430;
      final facts = <Widget>[
        _dataFact('Last', formatLoad(point.load, loadUnit)),
        _dataFact('HF', '${point.heartRateBpm ?? '—'} bpm'),
        _dataFact('RPE', '${point.rpe ?? '—'}'),
        _dataFact(
          'Laktat',
          '${point.lactate.toStringAsFixed(2).replaceAll('.', ',')} mmol/l',
        ),
      ];
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: compact
            ? Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: GiuliaTokens.surface2,
                  borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'STUFE ${point.stageNumber}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        IconButton(
                          key: Key('lala-correct-stage-${point.stageNumber}'),
                          tooltip: 'Eingabefehler korrigieren',
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: onCorrect,
                        ),
                      ],
                    ),
                    Wrap(spacing: 18, runSpacing: 8, children: facts),
                  ],
                ),
              )
            : Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Row(
                      children: [
                        Text('${point.stageNumber}'),
                        IconButton(
                          key: Key('lala-correct-stage-${point.stageNumber}'),
                          tooltip: 'Eingabefehler korrigieren',
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: onCorrect,
                        ),
                      ],
                    ),
                  ),
                  for (final fact in facts) Expanded(child: fact),
                ],
              ),
      );
    },
  );

  Widget _dataFact(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label.toUpperCase(),
        style: const TextStyle(fontSize: 10, color: GiuliaTokens.textMuted),
      ),
      Text(value, overflow: TextOverflow.ellipsis),
    ],
  );
}

class _CompareWithHistoryButton extends StatelessWidget {
  const _CompareWithHistoryButton({
    required this.controller,
    required this.currentTest,
  });

  final LalaController controller;
  final LalaTestView currentTest;

  @override
  Widget build(BuildContext context) {
    final earlier = controller
        .overviewFor(currentTest.head.athleteId)
        .history
        .where(
          (entry) =>
              entry.testId != currentTest.head.id &&
              entry.hasResult &&
              entry.sport == currentTest.head.sport &&
              entry.startedAtUtcUs < currentTest.head.startedAtUtcUs,
        )
        .toList(growable: false);
    if (earlier.isEmpty) return const SizedBox.shrink();
    return OutlinedButton.icon(
      key: const Key('lala-compare-history'),
      icon: const Icon(Icons.compare_arrows_outlined),
      label: const Text('Mit früherem Test vergleichen'),
      onPressed: () async {
        final selected = await showModalBottomSheet<LalaHistoryEntry>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Text(
                    'FRÜHEREN TEST AUSWÄHLEN',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                for (final test in earlier)
                  ListTile(
                    leading: const Icon(Icons.science_outlined),
                    title: Text(formatTestDate(test.startedAtUtcUs)),
                    subtitle: Text(
                      '${sportLabel(test.sport)} · LT1 ${formatLoad(test.lt1Load, test.loadUnit)} · LT2 ${formatLoad(test.lt2Load, test.loadUnit)}',
                    ),
                    onTap: () => Navigator.of(sheetContext).pop(test),
                  ),
              ],
            ),
          ),
        );
        if (selected == null || !context.mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LalaComparisonScreen(
              controller: controller,
              earlierTestId: selected.testId,
              laterTestId: currentTest.head.id,
            ),
          ),
        );
      },
    );
  }
}

class _CorrectStageDialog extends StatefulWidget {
  const _CorrectStageDialog({
    required this.controller,
    required this.testId,
    required this.point,
    required this.loadUnit,
  });
  final LalaController controller;
  final String testId;
  final LalaCurvePoint point;
  final String loadUnit;

  @override
  State<_CorrectStageDialog> createState() => _CorrectStageDialogState();
}

class _CorrectStageDialogState extends State<_CorrectStageDialog> {
  late final _load = TextEditingController(text: _number(widget.point.load));
  late final _heartRate = TextEditingController(
    text: widget.point.heartRateBpm?.toString() ?? '',
  );
  late final _rpe = TextEditingController(
    text: widget.point.rpe?.toString() ?? '',
  );
  late final _lactate = TextEditingController(
    text: _number(widget.point.lactate),
  );
  final _reason = TextEditingController();
  String? _error;

  static String _number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString().replaceAll('.', ',');

  @override
  void dispose() {
    _load.dispose();
    _heartRate.dispose();
    _rpe.dispose();
    _lactate.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Stufe ${widget.point.stageNumber} korrigieren'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Die Originalmessung wird nicht überschrieben. Giulia speichert '
            'Ihre Korrektur mit Begründung und erstellt eine neue Auswertung.',
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          Row(
            children: [
              Expanded(child: _field(_load, 'Last (${widget.loadUnit})')),
              const SizedBox(width: GiuliaTokens.spacingS),
              Expanded(child: _field(_heartRate, 'HF', decimals: false)),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          Row(
            children: [
              Expanded(child: _field(_rpe, 'RPE', decimals: false)),
              const SizedBox(width: GiuliaTokens.spacingS),
              Expanded(child: _field(_lactate, 'Laktat (mmol/l)')),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          TextField(
            key: const Key('lala-correction-reason'),
            controller: _reason,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Grund der Korrektur'),
          ),
          if (_error != null) ...[
            const SizedBox(height: GiuliaTokens.spacingS),
            Text(_error!, style: const TextStyle(color: GiuliaTokens.error)),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        key: const Key('lala-correction-save'),
        onPressed: _save,
        child: const Text('Korrektur speichern'),
      ),
    ],
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool decimals = true,
  }) => TextField(
    controller: controller,
    keyboardType: TextInputType.numberWithOptions(decimal: decimals),
    inputFormatters: [
      FilteringTextInputFormatter.allow(
        RegExp(decimals ? r'[0-9.,]' : r'[0-9]'),
      ),
    ],
    decoration: InputDecoration(labelText: label),
  );

  void _save() {
    double? number(TextEditingController field) =>
        double.tryParse(field.text.trim().replaceAll(',', '.'));
    final load = number(_load);
    final lactate = number(_lactate);
    final heartRate = int.tryParse(_heartRate.text.trim());
    final rpe = int.tryParse(_rpe.text.trim());
    if (load == null || load <= 0 || lactate == null || lactate < 0) {
      setState(() => _error = 'Last und Laktat müssen gültige Werte sein.');
      return;
    }
    final runId = widget.controller.correctStageAndEvaluate(
      testId: widget.testId,
      stageId: widget.point.stageId,
      reason: _reason.text,
      loadValue: load,
      lactateMmolPerLitre: lactate,
      heartRateBpm: heartRate,
      rpe: rpe,
    );
    if (runId == null) {
      setState(
        () => _error =
            widget.controller.failure?.message ??
            'Korrektur nicht gespeichert.',
      );
      return;
    }
    Navigator.of(context).pop(true);
  }
}

/// Every method the engine evaluated for this run.
///
/// Methods without a result are listed too. A method that could not be applied
/// is a finding about the protocol, and hiding it would make the analysis look
/// more complete than it was.
class _MethodTable extends StatelessWidget {
  const _MethodTable({required this.run});
  final LalaRunView run;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final withValue = run.allThresholds
        .where((threshold) => threshold.loadValue != null)
        .toList(growable: false);
    final without = run.methodsWithoutResult;

    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ALLE AUSGEWERTETEN METHODEN', style: text.labelMedium),
          const SizedBox(height: GiuliaTokens.spacingS),
          for (final threshold in withValue) ...[
            Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(threshold.typeLabel, style: text.titleMedium),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    germanLabel(threshold.methodLabel),
                    style: text.bodyMedium?.copyWith(
                      color: GiuliaTokens.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(threshold.loadLabel, textAlign: TextAlign.right),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (without.isNotEmpty) ...[
            const Divider(height: 20),
            Text('OHNE ERGEBNIS (${without.length})', style: text.labelMedium),
            const SizedBox(height: GiuliaTokens.spacingS),
            for (final threshold in without)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${threshold.typeLabel} · ${germanLabel(threshold.methodLabel)} — '
                  '${threshold.status}',
                  style: text.bodyMedium,
                ),
              ),
            Text(
              'Diese Verfahren wurden gerechnet, lieferten mit diesem '
              'Protokoll aber keinen verwertbaren Wert. Das ist ein Befund '
              'über den Test, kein Programmfehler.',
              style: text.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}
