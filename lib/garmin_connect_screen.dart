import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'garmin_personal.dart';
import 'giulia_garmin.dart';
import 'giulia_garmin_panel.dart';

class GarminConnectScreen extends StatefulWidget {
  const GarminConnectScreen({
    super.key,
    required this.archive,
    required this.name,
  });
  final GarminArchive archive;
  final String name;
  @override
  State<GarminConnectScreen> createState() => _GarminConnectScreenState();
}

class _GarminConnectScreenState extends State<GarminConnectScreen> {
  static const vault = GiuliaGarmin.deviceVault;
  final keyField = TextEditingController();
  final client = http.Client();
  late final personal = GarminPersonal(widget.archive, client);
  DateTime end = DateUtils.dateOnly(DateTime.now());
  bool businessBusy = false;
  late final business = GiuliaGarmin(
    widget.archive.store,
    widget.archive.athlete,
    client,
    vault,
  );
  bool stop = false;
  int days = 1;
  bool fullHistory = true;
  bool extended = true,
      busy = false,
      remember = true,
      saved = false,
      checking = true;
  String status = '';
  String get vaultKey => 'xc.personal.garmin.${widget.archive.athlete}';
  @override
  void initState() {
    super.initState();
    checkKey();
  }

  Future<void> checkKey() async {
    try {
      saved = await vault.containsKey(key: vaultKey);
    } catch (_) {
      remember = false;
    }
    if (mounted) setState(() => checking = false);
  }

  @override
  void dispose() {
    keyField.dispose();
    client.close();
    super.dispose();
  }

  Future<void> synchronize() async {
    setState(() {
      busy = true;
      stop = false;
      status = 'Garmin-Konto wird geprüft …';
    });
    try {
      final input = keyField.text.trim();
      final key = input.isEmpty && saved
          ? await vault.read(key: vaultKey)
          : input;
      if (key == null || key.isEmpty) {
        throw const GarminFailure(
          'Bitte den eigenen Garmin-Schlüssel eingeben.',
        );
      }
      final endDay = CalendarDay.ofLocal(end);
      final today = CalendarDay.ofLocal(DateTime.now());
      final identity = await personal.identify(key, today);
      if (!mounted) return;
      if (stop) throw const GarminFailure('Abruf beendet.');
      final a = widget.archive;
      final previous = a.store.platform.appState(
        'xc.account.garminPersonal.${a.athlete}',
      );
      if (previous == null) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Garmin-Konto zuordnen'),
            content: Text(
              'Die Daten von „${identity.name}“ werden im Trainingsprofil von ${widget.name} gespeichert. Gehört dieses Konto zu diesem Profil?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Konto zuordnen'),
              ),
            ],
          ),
        );
        if (confirmed != true) {
          if (mounted) setState(() => status = 'Verbindung abgebrochen.');
          return;
        }
      }
      personal.bind();
      var storedKey = saved;
      String keyNote = '';
      if (input.isNotEmpty && remember) {
        try {
          await vault.write(key: vaultKey, value: key);
          if (await vault.read(key: vaultKey) != key)
            throw StateError('Schlüssel wurde nicht gespeichert.');
          storedKey = true;
        } catch (_) {
          keyNote = ' Der Gerätespeicher konnte den Schlüssel nicht sichern.';
        }
      }
      if (mounted) {
        setState(() {
          saved = storedKey;
          if (storedKey || !remember) keyField.clear();
        });
      }
      final result = await personal.sync(
        start: endDay.addDays(1 - days),
        end: endDay,
        extended: extended,
        fullActivityHistory: fullHistory,
        checkpointActivities: fullHistory && endDay == today,
        cancelled: () => stop,
        progress: (message) {
          if (mounted) setState(() => status = message);
        },
      );
      if (fullHistory) a.set('activityHistory', '1');
      final unavailable = result.unavailable
          .map((s) => garminSeries[s])
          .join(', ');
      if (mounted) {
        setState(
          () => status =
              '${result.activities} Aktivitäten und ${result.records} Gesundheitsdatensätze abgerufen.'
              '${unavailable.isEmpty ? '' : ' Ohne Freigabe: $unavailable.'}$keyNote',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => status =
              e is GarminFailure || e is StateError || e is FormatException
              ? e.toString()
              : 'Synchronisierung unterbrochen. Bereits gespeicherte Daten bleiben verfügbar. Bitte erneut versuchen.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> changeCycle(bool value) async {
    if (!value) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Garmin-Zyklusdaten entfernen?'),
          content: Text(
            'Die bisher von Garmin importierten Zyklusdaten für ${widget.name} werden von diesem Gerät entfernt. Ausstehende Zyklusdaten werden auf dem Server gelöscht.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Entfernen'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => businessBusy = true);
    try {
      await business.configureCycle(value);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Zyklusfreigabe konnte nicht geändert werden: $error',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => businessBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && !businessBusy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Garmin Connect')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Garmin für ${widget.name}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              IgnorePointer(
                ignoring: busy || businessBusy,
                child: GiuliaGarminPanel(
                  service: business,
                  name: widget.name,
                  onBusy: (v) => setState(() => businessBusy = v),
                ),
              ),
              SwitchListTile(
                title: const Text('Zyklusdaten von Garmin'),
                subtitle: Text(
                  'Mit deiner Zustimmung im Profil von ${widget.name} automatisch empfangen und anzeigen.',
                ),
                value: widget.archive.setting('pushCycleAllowed') == '1',
                onChanged: busy || businessBusy ? null : changeCycle,
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                initiallyExpanded: saved,
                title: const Text('Optionaler Direktabruf'),
                subtitle: const Text(
                  'Zusätzlicher Zugang für einen selbst gewählten Zeitraum',
                ),
                children: [
                  IgnorePointer(
                    ignoring: businessBusy,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Erstelle in deinem Garmin-Konto einen persönlichen API-Schlüssel und gib ihn hier ein. Die App ruft deine Daten direkt bei Garmin ab.',
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Icons.open_in_new, size: 17),
                            label: const Text('Schlüssel bei Garmin erstellen'),
                            onPressed: busy
                                ? null
                                : () async {
                                    if (!await launchUrl(
                                          Uri.parse(garminKeyPage),
                                          mode: LaunchMode.externalApplication,
                                        ) &&
                                        mounted) {
                                      setState(
                                        () => status =
                                            'Garmin Connect konnte nicht geöffnet werden.',
                                      );
                                    }
                                  },
                          ),
                        ),
                        TextField(
                          controller: keyField,
                          enabled: !busy && !checking,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: saved
                                ? 'Gespeicherter Schlüssel · zum Ersetzen eingeben'
                                : 'Persönlicher Garmin-Schlüssel',
                          ),
                        ),
                        if (saved)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      try {
                                        await vault.delete(key: vaultKey);
                                        if (mounted) {
                                          setState(() {
                                            saved = false;
                                            keyField.clear();
                                            status =
                                                'Schlüssel von diesem Gerät entfernt.';
                                          });
                                        }
                                      } catch (_) {
                                        if (mounted) {
                                          setState(
                                            () => status =
                                                'Der Schlüssel konnte nicht entfernt werden.',
                                          );
                                        }
                                      }
                                    },
                              child: const Text(
                                'Gespeicherten Schlüssel entfernen',
                              ),
                            ),
                          )
                        else
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Schlüssel auf diesem Gerät sicher speichern',
                            ),
                            value: remember,
                            onChanged: busy
                                ? null
                                : (v) => setState(() => remember = v == true),
                          ),
                        const Divider(height: 30),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.event_outlined),
                          title: const Text('Letzter Tag des Abrufs'),
                          subtitle: Text(CalendarDay.ofLocal(end).key),
                          onTap: busy
                              ? null
                              : () async {
                                  final day = await showDatePicker(
                                    context: context,
                                    initialDate: end,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime.now(),
                                  );
                                  if (day != null && mounted)
                                    setState(() => end = day);
                                },
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final count in [1, 7, 30])
                              ChoiceChip(
                                label: Text(
                                  count == 1 ? 'Ein Tag' : '$count Tage',
                                ),
                                selected: days == count,
                                onSelected: busy
                                    ? null
                                    : (_) => setState(() => days = count),
                              ),
                          ],
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Gesamte Aktivitätshistorie'),
                          subtitle: const Text(
                            'Auch Aktivitäten vor dem gewählten Zeitraum importieren.',
                          ),
                          value: fullHistory,
                          onChanged: busy
                              ? null
                              : (v) => setState(() => fullHistory = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Erweiterte Gesundheitsdaten'),
                          subtitle: const Text(
                            'Unter anderem Herzfrequenzverlauf, Sauerstoffsättigung, Gewicht, Ernährung und VO₂max.',
                          ),
                          value: extended,
                          onChanged: busy
                              ? null
                              : (v) => setState(() => extended = v),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: busy || checking ? null : synchronize,
                          icon: const Icon(Icons.sync),
                          label: const Text('Mit Garmin synchronisieren'),
                        ),
                        if (busy) ...[
                          const LinearProgressIndicator(),
                          TextButton(
                            onPressed: stop
                                ? null
                                : () => setState(() => stop = true),
                            child: Text(
                              stop ? 'Wird beendet …' : 'Abruf beenden',
                            ),
                          ),
                        ],
                        if (status.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(status),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
