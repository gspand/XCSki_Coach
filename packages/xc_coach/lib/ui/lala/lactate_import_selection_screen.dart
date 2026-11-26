/// Der Scout-Speicher als Trainer-Inbox.
///
/// Automatische Gruppierung ist hier nur eine Arbeitshilfe. Jeder gelesene
/// Wert bleibt sichtbar und kann einzeln in die zu prüfende Reihe aufgenommen
/// werden. So kann eine ungewöhnlich lange Pause keinen Messpunkt verstecken.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../external_data/normalization/external_data.dart';
import '../../external_data/normalization/measurement_grouping.dart';
import '../design_system.dart';
import 'lactate_import.dart';

class LactateImportSelectionScreen extends StatefulWidget {
  const LactateImportSelectionScreen({
    super.key,
    required this.batch,
    required this.unimported,
  });

  final LactateImportBatch batch;
  final List<ExternalMeasurement> unimported;

  @override
  State<LactateImportSelectionScreen> createState() =>
      _LactateImportSelectionScreenState();
}

class _LactateImportSelectionScreenState
    extends State<LactateImportSelectionScreen> {
  late final Set<String> _newKeys = {
    for (final measurement in widget.unimported) _key(measurement),
  };
  late final List<MeasurementGroup> _groups = const MeasurementGrouping()
      .groupsOf(widget.batch.measurements)
      .reversed
      .toList(growable: false);
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    final candidates = [
      ..._groups.where((group) => group.measurements.where(_isNew).length >= 3),
      ..._groups.where((group) => group.measurements.any(_isNew)),
    ];
    if (candidates.isNotEmpty) {
      _selected.addAll(candidates.first.measurements.where(_isNew).map(_key));
    }
  }

  bool _isNew(ExternalMeasurement measurement) =>
      _newKeys.contains(_key(measurement));

  List<ExternalMeasurement> get _selection {
    final values = [
      for (final measurement in widget.batch.measurements)
        if (_selected.contains(_key(measurement))) measurement,
    ]..sort((a, b) => a.measuredAtUtcUs.compareTo(b.measuredAtUtcUs));
    return values;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scout-Speicher prüfen')),
    body: Column(
      children: [
        Expanded(
          child: ListView(
            padding: GiuliaDensity.of(context).pageInsets,
            children: [
              _summary(context),
              const SizedBox(height: GiuliaTokens.spacingM),
              const GiuliaSectionHeader(
                title: 'Messwerte auswählen',
                subtitle:
                    'Alle gelesenen Werte stehen hier. Wähle Ruhe-, Stufen- '
                    'und Erholungswerte, die zu diesem Test gehören.',
              ),
              const SizedBox(height: GiuliaTokens.spacingS),
              if (_groups.isEmpty)
                const GiuliaEmptyState(
                  icon: Icons.science_outlined,
                  title: 'Keine Messwerte im Speicher',
                  description:
                      'Der Scout hat keine lesbaren Laktatwerte geliefert.',
                )
              else
                for (final group in _groups) ...[
                  _group(context, group),
                  const SizedBox(height: GiuliaTokens.spacingS),
                ],
            ],
          ),
        ),
        _action(context),
      ],
    ),
  );

  Widget _summary(BuildContext context) {
    final total = widget.batch.measurements.length;
    final imported = total - widget.unimported.length;
    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.batch.deviceName?.isNotEmpty == true
                ? widget.batch.deviceName!
                : 'Lactate Scout',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          Wrap(
            spacing: GiuliaTokens.spacingS,
            runSpacing: GiuliaTokens.spacingXs,
            children: [
              GiuliaChip('$total gelesen', tone: GiuliaTokens.accent),
              GiuliaChip('${widget.unimported.length} neu'),
              if (imported != 0) GiuliaChip('$imported bereits importiert'),
              if (widget.batch.rejectedMeasurements != 0)
                GiuliaChip(
                  '${widget.batch.rejectedMeasurements} unlesbar',
                  tone: GiuliaTokens.warning,
                ),
              GiuliaChip(
                widget.batch.transferComplete
                    ? 'Speicher vollständig'
                    : 'Vollständigkeit prüfen',
                tone: widget.batch.transferComplete
                    ? GiuliaTokens.success
                    : GiuliaTokens.warning,
              ),
            ],
          ),
          if (widget.batch.warnings.isNotEmpty) ...[
            const SizedBox(height: GiuliaTokens.spacingS),
            for (final warning in widget.batch.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: GiuliaTokens.spacingXs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_outlined,
                      color: GiuliaTokens.warning,
                      size: GiuliaTokens.iconS,
                    ),
                    const SizedBox(width: GiuliaTokens.spacingS),
                    Expanded(child: Text(warning)),
                  ],
                ),
              ),
          ],
          if (widget.batch.rawExport != null) ...[
            const SizedBox(height: GiuliaTokens.spacingS),
            TextButton.icon(
              key: const Key('import-copy-raw-data'),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: widget.batch.rawExport!),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Scout-Diagnose wurde kopiert.'),
                  ),
                );
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Übertragungsdiagnose kopieren'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _group(BuildContext context, MeasurementGroup group) {
    final available = group.measurements.where(_isNew).toList();
    final selected = available.where(
      (value) => _selected.contains(_key(value)),
    );
    final allSelected =
        available.isNotEmpty && selected.length == available.length;
    final range = _range(group.measurements);
    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_date(group.startedAtUtcUs)} · '
                      '${_time(group.startedAtUtcUs)}–${_time(group.endedAtUtcUs)}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: GiuliaTokens.spacingXs),
                    Text(
                      '${group.count} Werte · $range mmol/l',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: GiuliaTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (available.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    if (allSelected) {
                      _selected.removeAll(available.map(_key));
                    } else {
                      _selected.addAll(available.map(_key));
                    }
                  }),
                  child: Text(allSelected ? 'Abwählen' : 'Reihe wählen'),
                ),
            ],
          ),
          const Divider(),
          for (final measurement in group.measurements)
            _measurement(context, measurement),
        ],
      ),
    );
  }

  Widget _measurement(BuildContext context, ExternalMeasurement measurement) {
    final isNew = _isNew(measurement);
    final selected = _selected.contains(_key(measurement));
    final details = <String>[
      if (measurement.sequenceNumber != null)
        'Speicher ${measurement.sequenceNumber}',
      measurement.heartRateBpm == null
          ? 'Puls –'
          : 'Puls ${measurement.heartRateBpm}',
      if (measurement.temperatureCelsius != null)
        '${_number(measurement.temperatureCelsius!)} °C',
      if (!isNew) 'bereits importiert',
    ];
    return Material(
      color: Colors.transparent,
      child: CheckboxListTile(
        key: Key('import-measurement-${measurement.sourceId}'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: isNew && selected,
        onChanged: isNew
            ? (checked) => setState(() {
                if (checked == true) {
                  _selected.add(_key(measurement));
                } else {
                  _selected.remove(_key(measurement));
                }
              })
            : null,
        title: Row(
          children: [
            Expanded(child: Text(_time(measurement.measuredAtUtcUs))),
            Text(
              '${_number(measurement.value)} mmol/l',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
        subtitle: Text(details.join(' · ')),
      ),
    );
  }

  Widget _action(BuildContext context) {
    final count = _selected.length;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(GiuliaTokens.spacingM),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('import-review-selected'),
            onPressed: count == 0
                ? null
                : () => Navigator.of(context).pop(
                    MeasurementGroup(
                      origin: GroupOrigin.timing,
                      measurements: _selection,
                    ),
                  ),
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(
              count == 0 ? 'Messwerte auswählen' : '$count Werte prüfen',
            ),
          ),
        ),
      ),
    );
  }
}

String _key(ExternalMeasurement measurement) =>
    '${measurement.provider.id}\u0000${measurement.sourceId}';

String _number(double value) => value.toStringAsFixed(1).replaceAll('.', ',');

String _range(List<ExternalMeasurement> values) {
  final sorted = values.map((value) => value.value).toList()..sort();
  return '${_number(sorted.first)}–${_number(sorted.last)}';
}

DateTime _local(int utcUs) =>
    DateTime.fromMicrosecondsSinceEpoch(utcUs, isUtc: true).toLocal();

String _time(int utcUs) {
  final stamp = _local(utcUs);
  return '${stamp.hour.toString().padLeft(2, '0')}:'
      '${stamp.minute.toString().padLeft(2, '0')}';
}

String _date(int utcUs) {
  final stamp = _local(utcUs);
  return '${stamp.day.toString().padLeft(2, '0')}.'
      '${stamp.month.toString().padLeft(2, '0')}.${stamp.year}';
}
