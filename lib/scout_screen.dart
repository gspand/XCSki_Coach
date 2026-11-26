import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:xc_coach/database/platform_repository.dart';
import 'coach_store.dart';
import 'scout_samples.dart';

class ScoutScreen extends StatefulWidget {
  const ScoutScreen({super.key, required this.store, required this.athlete});
  final CoachStore store;
  final AthleteSummary athlete;
  @override
  State<ScoutScreen> createState() => _ScoutScreenState();
}

class _ScoutScreenState extends State<ScoutScreen> {
  ScoutSamples get samples => ScoutSamples(widget.store, widget.athlete.id);
  Future<void> edit([Map<String, dynamic>? old]) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _Entry(samples: samples, name: widget.athlete.name, old: old),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> export() async {
    final data = jsonEncode({
      'format': 'xc-scout-1',
      'athlete': widget.athlete.name,
      'revisions': samples.history(),
    });
    final name = 'laktat-${widget.athlete.id}.json';
    final path = await getSaveLocation(suggestedName: name);
    if (path != null)
      await XFile.fromData(
        Uint8List.fromList(utf8.encode(data)),
        name: name,
        mimeType: 'application/json',
      ).saveTo(path.path);
  }

  @override
  Widget build(BuildContext context) {
    final all = samples.history();
    final latest = <String, Map<String, dynamic>>{};
    for (final r in all) {
      final id = r['sampleId'] as String;
      if (!latest.containsKey(id) ||
          (latest[id]!['revision'] as int) < (r['revision'] as int))
        latest[id] = r;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Laktat · ${widget.athlete.name}'),
        actions: [
          if (all.isNotEmpty &&
              {
                TargetPlatform.macOS,
                TargetPlatform.windows,
                TargetPlatform.linux,
              }.contains(Theme.of(context).platform))
            IconButton(
              onPressed: export,
              tooltip: 'Rohwerte mit Korrekturen exportieren',
              icon: const Icon(Icons.file_download_outlined),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: edit,
        icon: const Icon(Icons.add),
        label: const Text('Probe erfassen'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        children: [
          if (latest.isEmpty)
            const ListTile(
              title: Text('Noch keine Einzelprobe'),
              subtitle: Text(
                'Trage die Anzeige des Messgeräts zum Zeitpunkt der Blutprobe ein.',
              ),
            ),
          for (final r in latest.values)
            Card(
              child: ExpansionTile(
                title: Text(
                  '${r['raw']}${r['kind'] == 'missing' ? '' : ' mmol/L'}',
                ),
                subtitle: Text('${r['occasion']} · ${_stamp(r)}'),
                children: [
                  for (final v in all.where(
                    (v) => v['sampleId'] == r['sampleId'],
                  ))
                    ListTile(
                      title: Text("Fassung ${v['revision']} · ${v['raw']}"),
                      subtitle: Text(
                        [
                              _stamp(v),
                              v['stage'],
                              v['device'],
                              v['notes'],
                              v['correctionReason'],
                            ]
                            .whereType<String>()
                            .where((x) => x.isNotEmpty)
                            .join(' · '),
                      ),
                    ),
                  TextButton(
                    onPressed: () => edit(r),
                    child: const Text('Probe korrigieren'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _stamp(Map<String, dynamic> r) {
  if (r['sampledAtUs'] == null) return 'Probezeit unbekannt';
  final t = DateTime.fromMicrosecondsSinceEpoch(
    r['sampledAtUs'] as int,
    isUtc: true,
  ).add(Duration(minutes: r['timeOffsetMinutes'] as int));
  return "${r['timing'] == 'estimated' ? 'ca. ' : ''}${t.day}.${t.month}.${t.year} · ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
}

class _Entry extends StatefulWidget {
  const _Entry({required this.samples, required this.name, this.old});
  final ScoutSamples samples;
  final String name;
  final Map<String, dynamic>? old;
  @override
  State<_Entry> createState() => _EntryState();
}

class _EntryState extends State<_Entry> {
  late final old = widget.old ?? <String, dynamic>{};
  late final fields = {
    for (final k in [
      'raw',
      'stage',
      'device',
      'site',
      'notes',
      'secondsAfterLoad',
      'correctionReason',
    ])
      k: TextEditingController(
        text: k == 'correctionReason' ? '' : old[k]?.toString() ?? '',
      ),
  };
  late String timing = old['timing'] ?? 'known',
      occasion = old['occasion'] ?? 'Belastung';
  late DateTime sample = old['sampledAtUs'] == null
      ? DateTime.now()
      : DateTime.fromMicrosecondsSinceEpoch(old['sampledAtUs']);
  String? error;
  @override
  void dispose() {
    for (final f in fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  void save() {
    try {
      final seconds = fields['secondsAfterLoad']!.text.trim();
      widget.samples.save(
        raw: fields['raw']!.text,
        sampledAt: timing == 'unknown' ? null : sample,
        timing: timing,
        occasion: occasion,
        stage: fields['stage']!.text,
        device: fields['device']!.text,
        site: fields['site']!.text,
        notes: fields['notes']!.text,
        secondsAfterLoad: seconds.isEmpty ? null : int.parse(seconds),
        correctionOf: old['sampleId'],
        expectedRevision: old['revision'],
        correctionReason: fields['correctionReason']!.text,
      );
      Navigator.pop(context);
    } catch (e) {
      setState(() => error = e is FormatException ? e.message : e.toString());
    }
  }

  Widget field(String key, String label) => TextField(
    controller: fields[key],
    decoration: InputDecoration(labelText: label),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Blutprobe · ${widget.name}')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        field('raw', 'Geräteanzeige (mmol/L)'),
        const SizedBox(height: 12),
        DropdownButtonFormField(
          initialValue: occasion,
          decoration: const InputDecoration(labelText: 'Anlass'),
          items: [
            for (final s in ['Ruhe', 'Belastung', 'Nach Belastung', 'Erholung'])
              DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: (s) => setState(() => occasion = s!),
        ),
        DropdownButtonFormField(
          initialValue: timing,
          decoration: const InputDecoration(labelText: 'Probezeit'),
          items: [
            for (final e in {
              'known': 'Bekannt',
              'estimated': 'Geschätzt',
              'unknown': 'Unbekannt',
            }.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (s) => setState(() => timing = s!),
        ),
        if (timing != 'unknown')
          ListTile(
            leading: const Icon(Icons.schedule),
            title: Text(
              MaterialLocalizations.of(context).formatFullDate(sample),
            ),
            subtitle: Text(TimeOfDay.fromDateTime(sample).format(context)),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: sample,
                firstDate: DateTime(1970),
                lastDate: DateTime.now(),
              );
              if (d == null || !context.mounted) return;
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(sample),
              );
              if (t != null && mounted)
                setState(
                  () => sample = DateTime(
                    d.year,
                    d.month,
                    d.day,
                    t.hour,
                    t.minute,
                  ),
                );
            },
          ),
        ExpansionTile(
          title: const Text('Stufe, Messgerät und Bedingungen'),
          children: [
            field('stage', 'Test, Einheit oder Stufe (optional)'),
            field(
              'secondsAfterLoad',
              'Sekunden nach Belastungsende (optional)',
            ),
            field('device', 'Messgerät / Modell (optional)'),
            field('site', 'Entnahmestelle (optional)'),
            field('notes', 'Bedingungen und Bemerkungen (optional)'),
          ],
        ),
        if (old.isNotEmpty) field('correctionReason', 'Grund der Korrektur'),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: save,
          child: Text('Für ${widget.name} speichern'),
        ),
      ],
    ),
  );
}
