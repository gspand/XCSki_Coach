/// Manual entry of a lactate step test.
///
/// Deliberately device-free: sport, protocol and every measured value are
/// typed in. Nothing here computes a threshold — pressing "Auswerten" writes
/// the test down and asks the engine once, through the repository.
library;

import '../../domain/diagnostic_catalogue.dart';
import '../../measurement/contracts/test_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xc_coach/lala/application/lala_controller.dart';
import 'package:xc_coach/lala/application/lala_test_draft.dart';
import 'package:xc_coach/ui/design_system.dart';
import 'package:xc_coach/ui/lala/measured_test.dart';
import 'package:xc_coach/ui/lala/lala_test_detail_screen.dart';

class LalaNewTestScreen extends StatefulWidget {
  const LalaNewTestScreen({
    super.key,
    required this.controller,
    required this.athleteId,
    this.measuredTest,
    this.athleteName,
    this.onOpenMeasuredResult,
    this.sport,
  });

  final LalaController controller;
  final String athleteId;

  /// Die in TEST gewählte Sportart. Gesetzt, bietet der Bildschirm nur deren
  /// Protokolle an; ohne sie alle.
  final DiagnosticSport? sport;

  /// Present when this installation can measure with a device. Absent means
  /// exactly one thing: the test is typed in. It never means the screen is
  /// incomplete.
  final MeasuredTestAccess? measuredTest;

  final String? athleteName;

  /// Öffnet nach einem geführten Gerätetest die vollständige Auswertung.
  /// Der Aufrufer besitzt den Kontext unterhalb des Testdialogs und kann den
  /// Vorgang deshalb sauber schließen, bevor er das Ergebnis öffnet.
  final ValueChanged<String>? onOpenMeasuredResult;

  @override
  State<LalaNewTestScreen> createState() => _LalaNewTestScreenState();
}

class _LalaNewTestScreenState extends State<LalaNewTestScreen> {
  late LalaTestDraft _draft;
  String? _error;

  @override
  void initState() {
    super.initState();
    final sport = widget.sport;
    _draft = LalaTestDraft(
      athleteId: widget.athleteId,
      preset: sport == null
          ? testProtocols.first
          : protocolsForSport(sport).first,
      startedAtUtcUs: widget.controller.clock(),
    );
  }

  List<TestProtocol> get _protocols {
    final sport = widget.sport;
    return sport == null ? testProtocols : protocolsForSport(sport);
  }

  /// Der Geräteweg passt nur zu einem Ercolina-Test. Ohne gewählte Sportart
  /// bleibt das bisherige Angebot unverändert.
  bool get _offersDevice =>
      (widget.measuredTest?.hasDevices ?? false) &&
      (widget.sport == null || widget.sport == DiagnosticSport.ercolina);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.sport == null
            ? 'Neuer LaLa-Test'
            : 'Neuer Test · ${widget.sport!.title}',
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        const GiuliaPanel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.edit_note_outlined,
                color: GiuliaTokens.textMuted,
                size: GiuliaTokens.iconM,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Alle Werte werden manuell erfasst. Ein Messgerät ist für '
                  'einen vollständigen Laktattest nicht erforderlich.',
                  style: TextStyle(color: GiuliaTokens.textSecondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: GiuliaTokens.spacingM),

        _ProtocolSelector(
          selected: _draft.preset,
          protocols: _protocols,
          title: widget.sport == null
              ? 'SPORTART UND PROTOKOLL'
              : 'PROTOKOLL · ${widget.sport!.label.toUpperCase()}',
          onSelect: (preset) =>
              setState(() => _draft = _draft.withPreset(preset)),
          onCustomize: _customizeProtocol,
        ),
        const SizedBox(height: GiuliaTokens.spacingM),

        if (_offersDevice) ...[
          _ErcolinaOffer(preset: _draft.preset, onOpen: _openErcolina),
          const SizedBox(height: GiuliaTokens.spacingM),
        ],

        Text('TESTSTUFEN', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: GiuliaTokens.spacingS),
        _StageTable(
          draft: _draft,
          onChanged: (number, stage) =>
              setState(() => _draft = _draft.withStage(number, stage)),
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        _ProtocolQualityHint(draft: _draft),
        const SizedBox(height: GiuliaTokens.spacingS),
        Row(
          children: [
            OutlinedButton.icon(
              key: const Key('lala-add-stage'),
              onPressed: () =>
                  setState(() => _draft = _draft.withAdditionalStage()),
              icon: const Icon(Icons.add),
              label: const Text('Stufe hinzufügen'),
            ),
            const SizedBox(width: GiuliaTokens.spacingS),
            OutlinedButton.icon(
              key: const Key('lala-remove-stage'),
              onPressed: () =>
                  setState(() => _draft = _draft.withoutLastStage()),
              icon: const Icon(Icons.remove),
              label: const Text('Letzte Stufe entfernen'),
            ),
          ],
        ),
        const SizedBox(height: GiuliaTokens.spacingL),

        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: GiuliaTokens.error.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
              border: Border.all(
                color: GiuliaTokens.error.withValues(alpha: .4),
              ),
            ),
            child: Text(_error!, key: const Key('lala-new-test-error')),
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
        ],

        FilledButton.icon(
          key: const Key('lala-save-and-evaluate'),
          onPressed: _draft.canSave ? _submit : null,
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('Test abschließen und mit LaLa auswerten'),
        ),
        if (!_draft.canSave)
          Padding(
            padding: const EdgeInsets.only(top: GiuliaTokens.spacingS),
            child: Text(
              _draft.blockingReason!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        const SizedBox(height: GiuliaTokens.spacingM),
        Text(
          'Welche Methode LaLa verwenden kann, entscheidet die Engine nach dem '
          'Speichern anhand des tatsächlichen Protokolls. Ein kurzes Protokoll '
          'ist kein Fehler — es führt gegebenenfalls zu einer dokumentierten '
          'Fallback-Methode.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );

  /// Opens the device-measured variant of exactly this protocol.
  ///
  /// The screen is replaced rather than stacked: it is the same test, recorded
  /// a different way, not a second test on top of the first.
  void _openErcolina() {
    final measured = widget.measuredTest;
    if (measured == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) {
          final request = MeasuredTestRequest(
            lala: widget.controller,
            athleteId: widget.athleteId,
            athleteName: widget.athleteName ?? 'Athlet',
            protocol: _draft.preset,
            onOpenResult: widget.onOpenMeasuredResult,
          );
          // Die Testzentrale stellt den vollständigen Vorgang bereit:
          // Vorbereitung, Sensorstatus, Messung und Ergebnis. Eingebettete
          // Athletenansichten ohne Ergebnis-Routing behalten den kompakten
          // Geräteablauf, der sein Ergebnis selbst öffnet.
          return widget.onOpenMeasuredResult == null
              ? measured.stepTest(request)
              : measured.session(request);
        },
      ),
    );
  }

  Future<void> _customizeProtocol() async {
    final custom = await showDialog<TestProtocol>(
      context: context,
      builder: (_) => _CustomProtocolDialog(
        initial: _draft.preset,
        fixedSport: widget.sport,
      ),
    );
    if (custom != null && mounted) {
      setState(() => _draft = _draft.withPreset(custom));
    }
  }

  void _submit() {
    final runId = widget.controller.saveAndEvaluate(_draft);
    if (runId == null) {
      setState(
        () => _error =
            widget.controller.failure?.message ??
            'Der Test konnte nicht gespeichert werden.',
      );
      return;
    }
    final testId = widget.controller.overview?.latestTest?.head.id;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LalaTestDetailScreen(
          controller: widget.controller,
          testId: testId ?? '',
        ),
      ),
    );
  }
}

/// The device as an offer, never as a requirement.
///
/// It appears only when the organization actually owns a device, it appears
/// after the protocol has been chosen, and declining it costs nothing: the
/// table below stays exactly where it was.
class _ErcolinaOffer extends StatelessWidget {
  const _ErcolinaOffer({required this.preset, required this.onOpen});

  final TestProtocol preset;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.speed_outlined,
              color: GiuliaTokens.accent,
              size: GiuliaTokens.iconM,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Mit Ercolina messen',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        Text(
          'Leistung, Zugfrequenz und Seitenverteilung werden je Stufe vom '
          'Gerät erfasst. Laktat und RPE gibst du weiterhin selbst ein. '
          'Ausgewertet wird derselbe Test von derselben LaLa-Auswertung.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: GiuliaTokens.spacingM),
        OutlinedButton.icon(
          key: const Key('lala-start-ercolina'),
          onPressed: onOpen,
          icon: const Icon(Icons.play_circle_outline),
          label: Text('${preset.name} am Gerät fahren'),
        ),
      ],
    ),
  );
}

class _ProtocolSelector extends StatelessWidget {
  const _ProtocolSelector({
    required this.selected,
    required this.protocols,
    required this.title,
    required this.onSelect,
    required this.onCustomize,
  });
  final TestProtocol selected;
  final List<TestProtocol> protocols;
  final String title;
  final ValueChanged<TestProtocol> onSelect;
  final VoidCallback onCustomize;

  List<TestProtocol> get _choices => [
    ...protocols,
    if (!protocols.any((preset) => preset.id == selected.id)) selected,
  ];

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: GiuliaTokens.spacingS),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const Key('lala-protocol-selector'),
            isExpanded: true,
            value: selected.id,
            items: [
              for (final preset in _choices)
                DropdownMenuItem(value: preset.id, child: Text(preset.name)),
            ],
            onChanged: (id) {
              if (id == null) return;
              onSelect(_choices.firstWhere((preset) => preset.id == id));
            },
          ),
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        Text(
          selected.description,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Belastungseinheit: ${selected.loadUnit}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: GiuliaTokens.spacingM),
        OutlinedButton.icon(
          key: const Key('lala-customize-protocol'),
          onPressed: onCustomize,
          icon: const Icon(Icons.tune),
          label: Text(
            selected.isCustom
                ? 'Eigenes Protokoll bearbeiten'
                : 'Eigenes Protokoll erstellen',
          ),
        ),
      ],
    ),
  );
}

/// A recommendation, never a gate. The measured historical protocol remains
/// primary evidence; LaLa's applicability evaluation decides what can be
/// calculated after the raw values have been stored.
class _ProtocolQualityHint extends StatelessWidget {
  const _ProtocolQualityHint({required this.draft});
  final LalaTestDraft draft;

  @override
  Widget build(BuildContext context) {
    final duration = draft.preset.stageDurationSeconds;
    final stageCount = draft.stages.length;
    final needsDuration = duration < 120;
    final needsStages = stageCount < 6;
    final recommended = !needsDuration && !needsStages;
    final color = recommended ? GiuliaTokens.success : GiuliaTokens.warning;
    final icon = recommended ? Icons.verified_outlined : Icons.info_outline;
    final detail = recommended
        ? 'Planung erfüllt die allgemeine Orientierung: mindestens 6 Stufen '
              'und 120 s je Stufe. Die konkrete Methodeneignung prüft LaLa '
              'erst anhand der eingegebenen Rohwerte.'
        : '${[if (needsStages) 'Mindestens 6 Stufen einplanen', if (needsDuration) 'Stufendauer von mindestens 120 s einplanen'].join(' · ')}. Der Test bleibt speicherbar; LaLa dokumentiert '
              'nachher, welche Methoden dafür anwendbar sind.';
    return Semantics(
      container: true,
      label: recommended
          ? 'Protokollplanung: Orientierung erfüllt'
          : 'Protokollplanung: eingeschränkt',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
          border: Border.all(color: color.withValues(alpha: .32)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: GiuliaTokens.iconM),
            const SizedBox(width: GiuliaTokens.spacingS),
            Expanded(
              child: Text(
                detail,
                key: const Key('lala-protocol-quality-hint'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomProtocolDialog extends StatefulWidget {
  const _CustomProtocolDialog({required this.initial, this.fixedSport});
  final TestProtocol initial;
  final DiagnosticSport? fixedSport;

  @override
  State<_CustomProtocolDialog> createState() => _CustomProtocolDialogState();
}

class _CustomProtocolDialogState extends State<_CustomProtocolDialog> {
  late DiagnosticSport _sport =
      widget.fixedSport ??
      widget.initial.diagnosticSport ??
      DiagnosticSport.cycling;
  late String _unit = _sport.loadUnits.contains(widget.initial.loadUnit)
      ? widget.initial.loadUnit
      : _sport.loadUnits.first;

  static String _sportLabel(DiagnosticSport sport) => switch (sport) {
    DiagnosticSport.cycling => 'Radergometrie',
    DiagnosticSport.running => 'Laufband',
    DiagnosticSport.xcSki => 'Skilanglauf',
    DiagnosticSport.ercolina => 'Ercolina',
  };
  late final _name = TextEditingController(
    text: widget.initial.isCustom
        ? widget.initial.name
        : 'Eigenes Stufenprotokoll',
  );
  late final _start = TextEditingController(
    text: _number(widget.initial.startLoad),
  );
  late final _increment = TextEditingController(
    text: _number(widget.initial.increment),
  );
  late final _duration = TextEditingController(
    text: widget.initial.stageDurationSeconds.toString(),
  );
  String? _error;

  static String _number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString().replaceAll('.', ',');

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
    title: const Text('Eigenes Stufenprotokoll'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('lala-custom-protocol-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name des Protokolls'),
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          DropdownButtonFormField<DiagnosticSport>(
            key: const Key('lala-custom-protocol-sport'),
            initialValue: _sport,
            decoration: const InputDecoration(labelText: 'Sportart'),
            items: [
              for (final sport in [
                if (widget.fixedSport case final fixed?)
                  fixed
                else
                  ...DiagnosticSport.values,
              ])
                DropdownMenuItem(value: sport, child: Text(_sportLabel(sport))),
            ],
            onChanged: (value) => setState(() {
              _sport = value!;
              if (!_sport.loadUnits.contains(_unit)) {
                _unit = _sport.loadUnits.first;
              }
            }),
          ),
          if (_sport.loadUnits.length > 1) ...[
            const SizedBox(height: GiuliaTokens.spacingS),
            DropdownButtonFormField<String>(
              key: ValueKey('lala-custom-protocol-unit-${_sport.name}'),
              initialValue: _unit,
              decoration: const InputDecoration(labelText: 'Belastungseinheit'),
              items: [
                for (final unit in _sport.loadUnits)
                  DropdownMenuItem(value: unit, child: Text(unit)),
              ],
              onChanged: (value) => setState(() => _unit = value!),
            ),
          ],
          const SizedBox(height: GiuliaTokens.spacingS),
          _ProtocolNumberField(
            fieldKey: const Key('lala-custom-start-load'),
            controller: _start,
            label: 'Startlast ($_unit)',
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          _ProtocolNumberField(
            fieldKey: const Key('lala-custom-increment'),
            controller: _increment,
            label: 'Steigerung je Stufe ($_unit)',
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          _ProtocolNumberField(
            fieldKey: const Key('lala-custom-duration'),
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
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        key: const Key('lala-custom-protocol-apply'),
        onPressed: _apply,
        child: const Text('Übernehmen'),
      ),
    ],
  );

  void _apply() {
    double? value(TextEditingController controller) =>
        double.tryParse(controller.text.trim().replaceAll(',', '.'));
    final start = value(_start);
    final increment = value(_increment);
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
        sport: _sport.storageKey,
        loadUnit: _unit,
        startLoad: start,
        increment: increment,
        stageDurationSeconds: duration,
      ),
    );
  }
}

class _ProtocolNumberField extends StatelessWidget {
  const _ProtocolNumberField({
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
    inputFormatters: [
      FilteringTextInputFormatter.allow(
        RegExp(decimals ? r'[0-9.,]' : r'[0-9]'),
      ),
    ],
    decoration: InputDecoration(labelText: label),
  );
}

class _StageTable extends StatelessWidget {
  const _StageTable({required this.draft, required this.onChanged});

  final LalaTestDraft draft;
  final void Function(int stageNumber, LalaStageDraft stage) onChanged;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    padding: const EdgeInsets.all(GiuliaTokens.spacingM),
    child: Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 34),
            _HeaderCell('LAST (${draft.loadUnit})'),
            const _HeaderCell('HF (bpm)'),
            const _HeaderCell('RPE'),
            const _HeaderCell('LAKTAT'),
          ],
        ),
        const Divider(height: 18),
        for (final stage in draft.stages) ...[
          _StageRow(
            stage: stage,
            onChanged: (updated) => onChanged(stage.stageNumber, updated),
          ),
          if (stage != draft.stages.last) const SizedBox(height: 10),
        ],
      ],
    ),
  );
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Text(label, style: Theme.of(context).textTheme.labelMedium),
  );
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.stage, required this.onChanged});

  final LalaStageDraft stage;
  final ValueChanged<LalaStageDraft> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 34,
        child: Text(
          '${stage.stageNumber}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      _NumberField(
        fieldKey: Key('lala-stage-${stage.stageNumber}-load'),
        initial: stage.load,
        onChanged: (value) =>
            onChanged(stage.copyWith(load: value, clearLoad: value == null)),
      ),
      _NumberField(
        fieldKey: Key('lala-stage-${stage.stageNumber}-hr'),
        initial: stage.heartRateBpm?.toDouble(),
        onChanged: (value) => onChanged(
          stage.copyWith(
            heartRateBpm: value?.round(),
            clearHeartRate: value == null,
          ),
        ),
      ),
      _NumberField(
        fieldKey: Key('lala-stage-${stage.stageNumber}-rpe'),
        initial: stage.rpe?.toDouble(),
        onChanged: (value) => onChanged(
          stage.copyWith(rpe: value?.round(), clearRpe: value == null),
        ),
      ),
      _NumberField(
        fieldKey: Key('lala-stage-${stage.stageNumber}-lactate'),
        initial: stage.lactateMmolPerLitre,
        onChanged: (value) => onChanged(
          stage.copyWith(
            lactateMmolPerLitre: value,
            clearLactate: value == null,
          ),
        ),
      ),
    ],
  );
}

class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.fieldKey,
    required this.initial,
    required this.onChanged,
  });

  final Key fieldKey;
  final double? initial;
  final ValueChanged<double?> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial == null ? '' : _format(widget.initial!),
  );

  static String _format(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString().replaceAll('.', ',');

  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial == widget.initial) return;
    _text.value = TextEditingValue(
      text: widget.initial == null ? '' : _format(widget.initial!),
      selection: TextSelection.collapsed(
        offset: widget.initial == null ? 0 : _format(widget.initial!).length,
      ),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextField(
        key: widget.fieldKey,
        controller: _text,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        onChanged: (raw) {
          final normalised = raw.trim().replaceAll(',', '.');
          widget.onChanged(
            normalised.isEmpty ? null : double.tryParse(normalised),
          );
        },
      ),
    ),
  );
}
