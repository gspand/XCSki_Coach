/// Was ein Mensch sieht, bevor aus einer Übertragung ein Test wird.
///
/// ## Warum dieser Bildschirm der wichtigste des Imports ist
///
/// Weil hier die einzige Stelle liegt, an der ein Vorschlag zu einer Tatsache
/// wird. Alles davor ist Rechnen; alles danach steht im Bestand und wird
/// ausgewertet. Deshalb zeigt dieser Bildschirm zu **jedem** Wert:
///
/// * was das Gerät geliefert hat,
/// * woher er kommt,
/// * welcher Stufe GIULIA ihn zugeordnet hat und ob gemessen oder nominell,
/// * ob jemand ihn korrigiert oder ausgeschlossen hat, und warum.
///
/// Nichts davon ist verborgen hinter einem Aufklapper. Ein Diagnostiker, der
/// erst tippen muss, um zu sehen, dass Stufe 6 korrigiert wurde, sieht es
/// nicht.
///
/// ## Der Fall, der diesen Bildschirm nötig macht
///
/// Ohne gemessene Aktivität hat GIULIA nichts, woran es einen Ruhewert von
/// einem Stufenwert unterscheiden könnte — der Scout liefert Uhrzeit und
/// Laktat, sonst nichts. Es zeigt deshalb **alle** Werte als Stufen und lässt
/// herausnehmen, was keine ist. Die übrigen rücken nach, und die nominellen
/// Belastungen folgen der neuen Nummer: Bliebe der Ruhewert Stufe 1, stünde
/// der ganze Test um eine Stufe verschoben da.
library;

import 'package:flutter/material.dart';

import '../../domain/diagnostics.dart';
import '../../external_data/normalization/external_data.dart';
import '../../external_data/normalization/import_review.dart';
import '../../external_data/normalization/measurement_grouping.dart';
import '../../external_data/normalization/protocol_matching.dart';
import '../../measurement/contracts/test_protocol.dart';
import '../design_system.dart';

/// Prüft eine übertragene Messreihe und legt daraus einen Test an.
class ImportReviewScreen extends StatefulWidget {
  const ImportReviewScreen({
    super.key,
    required this.group,
    required this.onCreate,
    this.activity,
    this.protocols = testProtocols,
    this.matching = const ProtocolMatching(),
    this.sourceLabel = 'Lactate Scout',
  });

  /// Die gefundene Reihe.
  final MeasurementGroup group;

  /// Der Belastungsverlauf, wo einer vorliegt.
  final ExternalActivity? activity;

  /// Die Protokolle, gegen die abgeglichen wird. Die vorhandenen von LaLa —
  /// dieser Bildschirm erfindet keines.
  final List<TestProtocol> protocols;

  final ProtocolMatching matching;

  /// Woher die Werte kamen, für die Überschrift.
  final String sourceLabel;

  /// Legt den Test an. Gibt zurück, wohin es danach geht.
  final Future<void> Function(ImportReview review) onCreate;

  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

class _ImportReviewScreenState extends State<ImportReviewScreen> {
  /// Jeder Griff legt den vorherigen Zustand ab. [ImportReview] ist
  /// unveränderlich — damit ist Zurücknehmen kein Rückrechnen, sondern ein
  /// Griff in den Stapel.
  final List<ImportReview> _history = [];

  ImportReview? _review;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    final candidates = widget.matching.candidatesFor(
      widget.group,
      protocols: widget.protocols,
      activity: widget.activity,
    );
    if (candidates.isNotEmpty) _review = ImportReview.of(candidates.first);
  }

  void _apply(ImportReview next) {
    final current = _review;
    setState(() {
      if (current != null) _history.add(current);
      _review = next;
    });
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() => _review = _history.removeLast());
  }

  void _choose(TestProtocol protocol) => _apply(
    ImportReview.of(
      widget.matching.matchFor(
        widget.group,
        protocol,
        activity: widget.activity,
      ),
      sampleSite: _review?.sampleSite ?? LactateSampleSite.unknown,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final review = _review;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.sourceLabel}: Import'),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              key: const Key('import-undo'),
              onPressed: _undo,
              icon: const Icon(Icons.undo),
              tooltip: 'Letzte Änderung zurücknehmen',
            ),
        ],
      ),
      body: ListView(
        padding: GiuliaDensity.of(context).pageInsets,
        children: [
          _FoundSeries(group: widget.group, activity: widget.activity),
          const SizedBox(height: GiuliaTokens.spacingM),
          _ProtocolBlock(
            protocols: widget.protocols,
            selected: review?.protocol,
            onChoose: _choose,
          ),
          if (review != null) ...[
            const SizedBox(height: GiuliaTokens.spacingM),
            _SampleSettings(
              site: review.sampleSite,
              onChanged: (site) => _apply(review.withSampleSite(site)),
            ),
            const SizedBox(height: GiuliaTokens.spacingM),
            _QualityBlock(review: review, source: widget.sourceLabel),
            const SizedBox(height: GiuliaTokens.spacingL),
            const GiuliaSectionHeader(
              title: 'Zuordnung prüfen',
              subtitle:
                  'Jeder Wert steht so da, wie das Gerät ihn geliefert '
                  'hat. Was hier geändert wird, tritt neben ihn.',
            ),
            const SizedBox(height: GiuliaTokens.spacingS),
            ..._rows(review),
            const SizedBox(height: GiuliaTokens.spacingL),
            _CreateButton(review: review, working: _working, onCreate: _create),
          ],
        ],
      ),
    );
  }

  List<Widget> _rows(ImportReview review) {
    final rows = <Widget>[];
    for (final stage in review.stages) {
      rows
        ..add(
          _StageRow(
            stage: stage,
            source: widget.sourceLabel,
            onCorrect: () => _correct(review, stage),
            onEditFacts: () => _editFacts(review, stage),
            onExclude: () => _exclude(review, stage),
            onNotPartOfTest: stage.measurement == null
                ? null
                : () => _apply(review.notPartOfTest(stage.stageNumber)),
            onRestore: stage.decision == ReviewDecision.accept
                ? null
                : () => _apply(review.accept(stage.stageNumber)),
          ),
        )
        ..add(const SizedBox(height: GiuliaTokens.spacingS));
    }
    for (final measurement in review.separate) {
      rows
        ..add(
          _SeparateRow(
            measurement: measurement,
            label: _occasionOf(measurement, review),
            source: widget.sourceLabel,
          ),
        )
        ..add(const SizedBox(height: GiuliaTokens.spacingS));
    }
    return rows;
  }

  /// Wo ein Wert lag, wo keine Stufe war. Dieselbe Regel wie beim Schreiben.
  String _occasionOf(ExternalMeasurement measurement, ImportReview review) {
    if (review.stages.isEmpty) return 'Probe';
    final first = review.stages.first.measurement?.measuredAtUtcUs;
    final last = review.stages.last.measurement?.measuredAtUtcUs;
    if (first == null || last == null) return 'Probe';
    if (measurement.measuredAtUtcUs < first) return 'Ruhe';
    if (measurement.measuredAtUtcUs > last) return 'Erholung';
    return 'Probe';
  }

  Future<void> _correct(ImportReview review, ReviewedStage stage) async {
    final outcome = await showDialog<_Decision>(
      context: context,
      builder: (_) => _DecisionDialog(stage: stage, correcting: true),
    );
    if (outcome == null || !mounted) return;
    _apply(
      review.correct(
        stage.stageNumber,
        value: outcome.value!,
        reason: outcome.reason,
        note: outcome.note,
      ),
    );
  }

  Future<void> _exclude(ImportReview review, ReviewedStage stage) async {
    final outcome = await showDialog<_Decision>(
      context: context,
      builder: (_) => _DecisionDialog(stage: stage, correcting: false),
    );
    if (outcome == null || !mounted) return;
    _apply(
      review.exclude(
        stage.stageNumber,
        reason: outcome.reason,
        note: outcome.note,
      ),
    );
  }

  Future<void> _editFacts(ImportReview review, ReviewedStage stage) async {
    final facts = await showDialog<_StageFacts>(
      context: context,
      builder: (_) => _StageFactsDialog(stage: stage),
    );
    if (facts == null || !mounted) return;
    _apply(
      review.updateStageFacts(
        stage.stageNumber,
        loadValue: facts.loadValue,
        heartRateBpm: facts.heartRateBpm,
        rpe: facts.rpe,
      ),
    );
  }

  Future<void> _create() async {
    final review = _review;
    if (review == null || _working) return;
    setState(() => _working = true);
    try {
      await widget.onCreate(review);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

/// Was gefunden wurde, bevor irgendetwas gedeutet ist.
class _FoundSeries extends StatelessWidget {
  const _FoundSeries({required this.group, this.activity});

  final MeasurementGroup group;
  final ExternalActivity? activity;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GEFUNDENE MESSREIHE', style: text.labelMedium),
          const SizedBox(height: GiuliaTokens.spacingS),
          Text(
            '${formatDate(group.startedAtUtcUs)} · '
            '${formatTime(group.startedAtUtcUs)}$enDash'
            '${formatTime(group.endedAtUtcUs)}',
            style: text.titleMedium,
          ),
          const SizedBox(height: GiuliaTokens.spacingXs),
          Text(
            '${group.count} Messungen',
            style: text.bodyMedium?.copyWith(color: GiuliaTokens.textSecondary),
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          Wrap(
            spacing: GiuliaTokens.spacingS,
            runSpacing: GiuliaTokens.spacingXs,
            children: [
              GiuliaChip(
                group.origin == GroupOrigin.deviceMarking
                    ? 'Vom Gerät zusammen abgelegt'
                    : 'Aus den Zeitabständen geschlossen',
                tone: group.origin == GroupOrigin.deviceMarking
                    ? GiuliaTokens.accent
                    : null,
              ),
              if (group.medianInterval != null)
                GiuliaChip('Ø ${_minutes(group.medianInterval!)} min Abstand'),
            ],
          ),
        ],
      ),
    );
  }

  static String _minutes(Duration gap) =>
      (gap.inSeconds / 60).toStringAsFixed(1).replaceAll('.', ',');
}

/// Welches Protokoll gefahren wurde.
class _ProtocolBlock extends StatelessWidget {
  const _ProtocolBlock({
    required this.protocols,
    required this.selected,
    required this.onChoose,
  });

  final List<TestProtocol> protocols;
  final TestProtocol? selected;
  final ValueChanged<TestProtocol> onChoose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PROTOKOLL', style: text.labelMedium),
          const SizedBox(height: GiuliaTokens.spacingS),
          if (selected == null) ...[
            Row(
              children: [
                const Icon(
                  Icons.help_outline,
                  size: GiuliaTokens.iconM,
                  color: GiuliaTokens.warning,
                ),
                const SizedBox(width: GiuliaTokens.spacingS),
                Expanded(
                  child: Text(
                    'Kein eindeutiger Treffer',
                    style: text.titleSmall?.copyWith(
                      color: GiuliaTokens.warning,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: GiuliaTokens.spacingXs),
            Text(
              'Die Abstände der Messungen passen zu keinem hinterlegten '
              'Protokoll. Welches gefahren wurde, weisst du — GIULIA rät es '
              'nicht.',
              style: text.bodySmall?.copyWith(
                color: GiuliaTokens.textSecondary,
              ),
            ),
          ] else ...[
            Text(selected!.name, style: text.titleSmall),
            const SizedBox(height: GiuliaTokens.spacingXs),
            Text(
              selected!.description,
              style: text.bodySmall?.copyWith(
                color: GiuliaTokens.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: GiuliaTokens.spacingS),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const Key('import-choose-protocol'),
              onPressed: () => _pick(context),
              child: Text(
                selected == null ? 'Protokoll auswählen' : 'Anderes Protokoll',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final chosen = await showModalBottomSheet<TestProtocol>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => ListView(
        shrinkWrap: true,
        children: [
          for (final protocol in protocols)
            ListTile(
              key: Key('import-protocol-${protocol.id}'),
              title: Text(protocol.name),
              subtitle: Text(protocol.description),
              onTap: () => Navigator.of(sheet).pop(protocol),
            ),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;
    if (!chosen.isCustom) {
      onChoose(chosen);
      return;
    }
    final custom = await showDialog<TestProtocol>(
      context: context,
      builder: (_) => _ImportProtocolDialog(initial: selected ?? chosen),
    );
    if (custom != null) onChoose(custom);
  }
}

class _SampleSettings extends StatelessWidget {
  const _SampleSettings({required this.site, required this.onChanged});

  final LactateSampleSite site;
  final ValueChanged<LactateSampleSite> onChanged;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    child: Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PROBENAHME'),
              SizedBox(height: GiuliaTokens.spacingXs),
              Text(
                'Entnahmestelle gilt für alle ausgewählten Proben.',
                style: TextStyle(color: GiuliaTokens.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: GiuliaTokens.spacingM),
        DropdownButton<LactateSampleSite>(
          key: const Key('import-sample-site'),
          value: site,
          items: const [
            DropdownMenuItem(
              value: LactateSampleSite.ear,
              child: Text('Ohrläppchen'),
            ),
            DropdownMenuItem(
              value: LactateSampleSite.finger,
              child: Text('Finger'),
            ),
            DropdownMenuItem(
              value: LactateSampleSite.unknown,
              child: Text('Nicht angegeben'),
            ),
          ],
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ],
    ),
  );
}

/// Was der Import mit der Reihe gemacht hat — in vier Zeilen.
class _QualityBlock extends StatelessWidget {
  const _QualityBlock({required this.review, required this.source});

  final ImportReview review;
  final String source;

  @override
  Widget build(BuildContext context) {
    // «Zugeordnet» heisst: Die Stufe hat einen Wert. Ob er ausgewertet wird,
    // steht eine Zeile tiefer — das sind zwei Aussagen und nicht eine.
    final assigned = review.stages
        .where((stage) => stage.measurement != null)
        .length;
    final excluded = review.stages
        .where((stage) => stage.decision == ReviewDecision.exclude)
        .length;
    final corrected = review.stages.where((stage) => stage.isCorrected).length;
    final activity = review.activity;

    return GiuliaPanel(
      tone: GiuliaTokens.surface2,
      child: Column(
        children: [
          GiuliaStatusLabel(
            label: 'Stufen zugeordnet',
            value: '$assigned / ${review.stages.length}',
            status: assigned == review.stages.length
                ? GiuliaTokens.success
                : GiuliaTokens.warning,
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          GiuliaStatusLabel(
            label: 'Ausserhalb des Tests',
            value: '${review.separate.length}',
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          GiuliaStatusLabel(
            label: 'Ausgeschlossen',
            value: '$excluded',
            status: excluded == 0
                ? GiuliaTokens.textMuted
                : GiuliaTokens.warning,
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          GiuliaStatusLabel(
            label: 'Korrigiert',
            value: '$corrected',
            status: corrected == 0
                ? GiuliaTokens.textMuted
                : GiuliaTokens.warning,
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          GiuliaStatusLabel(
            label: 'Belastungsdaten',
            value: activity == null
                ? 'keine · nominell aus dem Protokoll'
                : activity.provider.id,
            status: activity == null
                ? GiuliaTokens.textMuted
                : GiuliaTokens.accent,
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          GiuliaStatusLabel(label: 'Laktat', value: source),
        ],
      ),
    );
  }
}

/// Eine Stufe mit allem, was über sie bekannt ist.
class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.stage,
    required this.source,
    required this.onCorrect,
    required this.onEditFacts,
    required this.onExclude,
    required this.onNotPartOfTest,
    required this.onRestore,
  });

  final ReviewedStage stage;
  final String source;
  final VoidCallback onCorrect;
  final VoidCallback onEditFacts;
  final VoidCallback onExclude;
  final VoidCallback? onNotPartOfTest;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final measurement = stage.measurement;
    final excluded = stage.decision == ReviewDecision.exclude;

    return GiuliaPanel(
      key: Key('import-stage-${stage.stageNumber}'),
      tone: excluded ? GiuliaTokens.surface2 : GiuliaTokens.surface1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 76,
                child: Text(
                  'Stufe ${stage.stageNumber}',
                  style: text.labelLarge,
                ),
              ),
              Expanded(
                child: Text(
                  measurement == null
                      ? placeholder
                      : formatTime(measurement.measuredAtUtcUs),
                  style: text.bodyMedium,
                ),
              ),
              Expanded(
                child: Text(
                  stage.loadValue == null
                      ? placeholder
                      : '${_number(stage.loadValue!)} ${stage.loadUnit ?? ''}',
                  textAlign: TextAlign.end,
                  style: text.bodyMedium,
                ),
              ),
              Expanded(
                child: Text(
                  stage.heartRateBpm == null
                      ? placeholder
                      : '${stage.heartRateBpm}',
                  textAlign: TextAlign.end,
                  style: text.bodyMedium,
                ),
              ),
              SizedBox(width: 86, child: _LactateCell(stage: stage)),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          Wrap(
            spacing: GiuliaTokens.spacingS,
            runSpacing: GiuliaTokens.spacingXs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GiuliaChip(source),
              GiuliaChip(
                switch (stage.loadOrigin) {
                  StageLoadOrigin.measured => 'Belastung gemessen',
                  StageLoadOrigin.manual => 'Belastung eingetragen',
                  StageLoadOrigin.nominal => 'Belastung nominell',
                  StageLoadOrigin.unknown => 'Belastung unbekannt',
                },
                tone: stage.loadOrigin == StageLoadOrigin.measured
                    ? GiuliaTokens.accent
                    : null,
              ),
              if (stage.rpe != null) GiuliaChip('RPE ${stage.rpe}'),
              if (measurement?.temperatureCelsius case final temperature?)
                GiuliaChip('${_number(temperature)} °C Probe'),
              if (measurement?.sequenceNumber case final memoryId?)
                GiuliaChip('Speicher $memoryId'),
              if (stage.reason != null)
                GiuliaChip(stage.reason!.label, tone: GiuliaTokens.warning),
            ],
          ),
          if (stage.note != null) ...[
            const SizedBox(height: GiuliaTokens.spacingXs),
            Text(
              stage.note!,
              style: text.bodySmall?.copyWith(
                color: GiuliaTokens.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: GiuliaTokens.spacingXs),
          Wrap(
            spacing: GiuliaTokens.spacingS,
            children: [
              TextButton(
                key: Key('import-edit-facts-${stage.stageNumber}'),
                onPressed: onEditFacts,
                child: const Text('Last · Puls · RPE'),
              ),
              if (onRestore != null)
                TextButton(
                  key: Key('import-restore-${stage.stageNumber}'),
                  onPressed: onRestore,
                  child: const Text('Zurücknehmen'),
                )
              else ...[
                if (measurement != null)
                  TextButton(
                    key: Key('import-correct-${stage.stageNumber}'),
                    onPressed: onCorrect,
                    child: const Text('Korrigieren'),
                  ),
                if (measurement != null)
                  TextButton(
                    key: Key('import-exclude-${stage.stageNumber}'),
                    onPressed: onExclude,
                    child: const Text('Ausschliessen'),
                  ),
                if (onNotPartOfTest != null)
                  TextButton(
                    key: Key('import-not-part-${stage.stageNumber}'),
                    onPressed: onNotPartOfTest,
                    child: const Text('Nicht Teil des Tests'),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1).replaceAll('.', ',');
}

/// Der Laktatwert — und, wo korrigiert wurde, beide.
class _LactateCell extends StatelessWidget {
  const _LactateCell({required this.stage});

  final ReviewedStage stage;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final original = stage.originalValue;
    final accepted = stage.acceptedValue;

    if (original == null) {
      return Text(
        placeholder,
        textAlign: TextAlign.end,
        style: text.bodyMedium,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          accepted == null ? placeholder : formatLactate(accepted),
          style: text.titleSmall?.copyWith(
            color: accepted == null
                ? GiuliaTokens.textMuted
                : GiuliaTokens.textPrimary,
          ),
        ),
        // Der gelieferte Wert bleibt sichtbar. Eine Korrektur, die den
        // Originalwert verschwinden lässt, ist nicht mehr von einer Messung zu
        // unterscheiden.
        if (accepted != original)
          Text(
            'statt ${formatLactate(original)}',
            style: text.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
          ),
      ],
    );
  }
}

/// Ein Wert, der zu keiner Stufe gehört.
class _SeparateRow extends StatelessWidget {
  const _SeparateRow({
    required this.measurement,
    required this.label,
    required this.source,
  });

  final ExternalMeasurement measurement;
  final String label;
  final String source;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GiuliaPanel(
      key: Key('import-separate-${measurement.sourceId}'),
      tone: GiuliaTokens.surface2,
      child: Row(
        children: [
          SizedBox(width: 76, child: Text(label, style: text.labelLarge)),
          Expanded(
            child: Text(
              formatTime(measurement.measuredAtUtcUs),
              style: text.bodyMedium,
            ),
          ),
          Expanded(child: Text(placeholder, textAlign: TextAlign.end)),
          Expanded(
            child: Text(
              measurement.heartRateBpm == null
                  ? placeholder
                  : '${measurement.heartRateBpm}',
              textAlign: TextAlign.end,
              style: text.bodyMedium,
            ),
          ),
          SizedBox(
            width: 86,
            child: Text(
              formatLactate(measurement.value),
              textAlign: TextAlign.end,
              style: text.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Der Knopf, hinter dem der Bestand wächst.
class _CreateButton extends StatelessWidget {
  const _CreateButton({
    required this.review,
    required this.working,
    required this.onCreate,
  });

  final ImportReview review;
  final bool working;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!review.mayBeEvaluated)
        Padding(
          padding: const EdgeInsets.only(bottom: GiuliaTokens.spacingS),
          child: Text(
            'Unter drei auswertbaren Stufen entsteht kein Test. Eine Schwelle '
            'aus zwei Punkten ist eine Linie, keine Aussage.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: GiuliaTokens.warning),
          ),
        ),
      FilledButton(
        key: const Key('import-create-test'),
        onPressed: review.mayBeEvaluated && !working ? onCreate : null,
        child: Text(working ? 'Wird angelegt …' : 'Test erstellen'),
      ),
    ],
  );
}

class _StageFacts {
  const _StageFacts({
    required this.loadValue,
    required this.heartRateBpm,
    required this.rpe,
  });

  final double loadValue;
  final int? heartRateBpm;
  final int? rpe;
}

class _StageFactsDialog extends StatefulWidget {
  const _StageFactsDialog({required this.stage});
  final ReviewedStage stage;

  @override
  State<_StageFactsDialog> createState() => _StageFactsDialogState();
}

class _StageFactsDialogState extends State<_StageFactsDialog> {
  late final _load = TextEditingController(
    text: widget.stage.loadValue == null
        ? ''
        : _plainNumber(widget.stage.loadValue!),
  );
  late final _heartRate = TextEditingController(
    text: widget.stage.heartRateBpm?.toString() ?? '',
  );
  late final _rpe = TextEditingController(
    text: widget.stage.rpe?.toString() ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _load.dispose();
    _heartRate.dispose();
    _rpe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Stufe ${widget.stage.stageNumber} ergänzen'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ImportNumberField(
          fieldKey: const Key('import-stage-load'),
          controller: _load,
          label: 'Tatsächliche Belastung (${widget.stage.loadUnit ?? ''})',
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        _ImportNumberField(
          fieldKey: const Key('import-stage-heart-rate'),
          controller: _heartRate,
          label: 'Herzfrequenz (/min)',
          decimals: false,
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        _ImportNumberField(
          fieldKey: const Key('import-stage-rpe'),
          controller: _rpe,
          label: 'RPE (0–10)',
          decimals: false,
        ),
        if (_error != null) ...[
          const SizedBox(height: GiuliaTokens.spacingS),
          Text(_error!, style: const TextStyle(color: GiuliaTokens.error)),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        key: const Key('import-stage-facts-apply'),
        onPressed: _apply,
        child: const Text('Übernehmen'),
      ),
    ],
  );

  void _apply() {
    final load = double.tryParse(_load.text.trim().replaceAll(',', '.'));
    final heartRate = _optionalInt(_heartRate.text);
    final rpe = _optionalInt(_rpe.text);
    if (load == null || load <= 0) {
      setState(() => _error = 'Die Belastung muss größer als null sein.');
      return;
    }
    if (heartRate != null && (heartRate < 25 || heartRate > 250)) {
      setState(() => _error = 'Herzfrequenz muss zwischen 25 und 250 liegen.');
      return;
    }
    if (rpe != null && (rpe < 0 || rpe > 10)) {
      setState(() => _error = 'RPE muss zwischen 0 und 10 liegen.');
      return;
    }
    Navigator.of(
      context,
    ).pop(_StageFacts(loadValue: load, heartRateBpm: heartRate, rpe: rpe));
  }
}

class _ImportProtocolDialog extends StatefulWidget {
  const _ImportProtocolDialog({required this.initial});
  final TestProtocol initial;

  @override
  State<_ImportProtocolDialog> createState() => _ImportProtocolDialogState();
}

class _ImportProtocolDialogState extends State<_ImportProtocolDialog> {
  late String _sport = widget.initial.sport;
  late final _name = TextEditingController(
    text: widget.initial.isCustom
        ? widget.initial.name
        : 'Eigenes Stufenprotokoll',
  );
  late final _start = TextEditingController(
    text: _plainNumber(widget.initial.startLoad),
  );
  late final _increment = TextEditingController(
    text: _plainNumber(widget.initial.increment),
  );
  late final _duration = TextEditingController(
    text: widget.initial.stageDurationSeconds.toString(),
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _start.dispose();
    _increment.dispose();
    _duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Testprotokoll festlegen'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('import-protocol-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: GiuliaTokens.spacingS),
            DropdownButtonFormField<String>(
              key: const Key('import-protocol-sport'),
              initialValue: _sport,
              decoration: const InputDecoration(labelText: 'Sportart'),
              items: const [
                DropdownMenuItem(
                  value: 'cycling',
                  child: Text('Radergometrie'),
                ),
                DropdownMenuItem(value: 'running', child: Text('Laufband')),
                DropdownMenuItem(value: 'generic', child: Text('Ercolina')),
              ],
              onChanged: (value) => setState(() => _sport = value!),
            ),
            const SizedBox(height: GiuliaTokens.spacingS),
            _ImportNumberField(
              fieldKey: const Key('import-protocol-start'),
              controller: _start,
              label: _sport == 'running'
                  ? 'Startgeschwindigkeit (km/h)'
                  : 'Startlast (W)',
            ),
            const SizedBox(height: GiuliaTokens.spacingS),
            _ImportNumberField(
              fieldKey: const Key('import-protocol-increment'),
              controller: _increment,
              label: _sport == 'running'
                  ? 'Steigerung je Stufe (km/h)'
                  : 'Steigerung je Stufe (W)',
            ),
            const SizedBox(height: GiuliaTokens.spacingS),
            _ImportNumberField(
              fieldKey: const Key('import-protocol-duration'),
              controller: _duration,
              label: 'Stufendauer (Sekunden)',
              decimals: false,
            ),
            if (_error != null) ...[
              const SizedBox(height: GiuliaTokens.spacingS),
              Text(_error!, style: const TextStyle(color: GiuliaTokens.error)),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        key: const Key('import-protocol-apply'),
        onPressed: _apply,
        child: const Text('Übernehmen'),
      ),
    ],
  );

  void _apply() {
    final start = double.tryParse(_start.text.trim().replaceAll(',', '.'));
    final increment = double.tryParse(
      _increment.text.trim().replaceAll(',', '.'),
    );
    final duration = int.tryParse(_duration.text.trim());
    if (start == null ||
        start <= 0 ||
        increment == null ||
        increment <= 0 ||
        duration == null ||
        duration <= 0) {
      setState(
        () => _error =
            'Startlast, Steigerung und Stufendauer müssen größer als null sein.',
      );
      return;
    }
    Navigator.of(context).pop(
      TestProtocol.custom(
        name: _name.text,
        sport: _sport,
        loadUnit: _sport == 'running' ? 'km/h' : 'W',
        startLoad: start,
        increment: increment,
        stageDurationSeconds: duration,
      ),
    );
  }
}

class _ImportNumberField extends StatelessWidget {
  const _ImportNumberField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    this.decimals = true,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final bool decimals;

  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    keyboardType: TextInputType.numberWithOptions(decimal: decimals),
    decoration: InputDecoration(labelText: label),
  );
}

int? _optionalInt(String source) {
  final value = source.trim();
  return value.isEmpty ? null : int.tryParse(value);
}

String _plainNumber(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1).replaceAll('.', ',');

/// Was eine Korrektur oder ein Ausschluss braucht.
class _Decision {
  const _Decision({required this.reason, this.value, this.note});

  final double? value;
  final ReviewReason reason;
  final String? note;
}

class _DecisionDialog extends StatefulWidget {
  const _DecisionDialog({required this.stage, required this.correcting});

  final ReviewedStage stage;

  /// Korrigieren braucht einen Wert, Ausschliessen nicht.
  final bool correcting;

  @override
  State<_DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends State<_DecisionDialog> {
  late final TextEditingController _value = TextEditingController(
    text: widget.stage.originalValue == null
        ? ''
        : formatLactate(widget.stage.originalValue!),
  );
  final TextEditingController _note = TextEditingController();
  ReviewReason _reason = ReviewReason.measurementError;

  @override
  void dispose() {
    _value.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _parsed =>
      double.tryParse(_value.text.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.correcting
          ? 'Stufe ${widget.stage.stageNumber} korrigieren'
          : 'Stufe ${widget.stage.stageNumber} ausschliessen',
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.stage.originalValue != null)
          Text(
            'Geliefert: ${formatLactate(widget.stage.originalValue!)} mmol/l. '
            'Dieser Wert bleibt erhalten.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (widget.correcting) ...[
          const SizedBox(height: GiuliaTokens.spacingM),
          TextField(
            key: const Key('import-correction-value'),
            controller: _value,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Stattdessen gültig',
              suffixText: 'mmol/l',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: GiuliaTokens.spacingM),
        DropdownButtonFormField<ReviewReason>(
          key: const Key('import-decision-reason'),
          initialValue: _reason,
          decoration: const InputDecoration(labelText: 'Grund'),
          items: [
            for (final reason in ReviewReason.values)
              DropdownMenuItem(value: reason, child: Text(reason.label)),
          ],
          onChanged: (reason) => setState(() => _reason = reason ?? _reason),
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        TextField(
          key: const Key('import-decision-note'),
          controller: _note,
          decoration: const InputDecoration(
            labelText: 'Bemerkung',
            hintText: 'Was sonst noch zu sagen war',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        key: const Key('import-decision-confirm'),
        onPressed: widget.correcting && _parsed == null
            ? null
            : () => Navigator.of(context).pop(
                _Decision(
                  reason: _reason,
                  value: _parsed,
                  note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                ),
              ),
        child: Text(widget.correcting ? 'Korrigieren' : 'Ausschliessen'),
      ),
    ],
  );
}

/// Wo keine Zahl steht, steht dieses Zeichen — und keine Null.
const String placeholder = '–';

/// Der Gedankenstrich zwischen zwei Uhrzeiten.
const String enDash = '–';

String formatLactate(double value) =>
    value.toStringAsFixed(1).replaceAll('.', ',');

String formatTime(int utcUs) {
  final stamp = DateTime.fromMicrosecondsSinceEpoch(
    utcUs,
    isUtc: true,
  ).toLocal();
  return '${stamp.hour.toString().padLeft(2, '0')}:'
      '${stamp.minute.toString().padLeft(2, '0')}';
}

String formatDate(int utcUs) {
  final stamp = DateTime.fromMicrosecondsSinceEpoch(
    utcUs,
    isUtc: true,
  ).toLocal();
  return '${stamp.day.toString().padLeft(2, '0')}.'
      '${stamp.month.toString().padLeft(2, '0')}.${stamp.year}';
}
