import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'garmin_personal.dart';
import 'giulia_garmin.dart';
import 'garmin_training_status.dart';

class GiuliaGarminPanel extends StatefulWidget {
  const GiuliaGarminPanel({
    super.key,
    required this.service,
    required this.name,
    required this.onBusy,
  });
  final GiuliaGarmin service;
  final String name;
  final ValueChanged<bool> onBusy;
  @override
  State<GiuliaGarminPanel> createState() => _GiuliaGarminPanelState();
}

class _GiuliaGarminPanelState extends State<GiuliaGarminPanel> {
  GarminJson? account;
  String message = '';
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      account = await widget.service.status();
    } catch (_) {
      message = 'Verbindungsstatus konnte nicht geladen werden.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> run(Future<void> Function() task) async {
    setState(() {
      busy = true;
      message = '';
    });
    widget.onBusy(true);
    try {
      await task();
    } on PlatformException catch (e) {
      message = e.code == 'CANCELED'
          ? 'Anmeldung abgebrochen.'
          : 'Anmeldung oder sicherer Gerätespeicher nicht verfügbar.';
    } on GarminFailure catch (e) {
      message = e.message;
    } on StateError catch (e) {
      message = e.message;
    } catch (_) {
      message = 'Verbindung unterbrochen. Bitte erneut versuchen.';
    } finally {
      if (mounted) {
        setState(() => busy = false);
        widget.onBusy(false);
      }
    }
  }

  Future<void> connect() async {
    account = await widget.service.connect(
      (url) async => Uri.parse(
        await FlutterWebAuth2.authenticate(
          url: url.toString(),
          callbackUrlScheme: 'xcski',
          options: const FlutterWebAuth2Options(
            httpsHost: 'garmin',
            httpsPath: '/callback',
            preferEphemeral: true,
          ),
        ),
      ),
    );
    await widget.service.synchronize();
    message = 'Verbunden. Neue Garmin-Daten werden automatisch übernommen.';
  }

  @override
  Widget build(BuildContext context) {
    final connected = account?['connected'] == true;
    final saved = widget.service.archive.setting('pushPermissions');
    final permissions =
        account?['permissions'] ?? (saved == null ? null : jsonDecode(saved));
    final name = account?['account']?['display_name'];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xffecf2f1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.watch_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Garmin Connect',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            connected
                ? 'Verbunden${name is String && name.isNotEmpty ? ' als $name' : ''} · Profil ${widget.name}'
                : 'Gib dein Garmin-Konto im Browser für das Trainingsprofil von ${widget.name} frei.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (!connected)
                FilledButton(
                  onPressed: busy ? null : () => run(connect),
                  child: const Text('Mit Garmin verbinden'),
                ),
              if (connected) ...[
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          final n = await widget.service.synchronize();
                          message = n == 0
                              ? 'Auf dem aktuellen Stand. Noch keine neue Lieferung von Garmin.'
                              : '$n Garmin-Datensätze übernommen.';
                        }),
                  child: const Text('Jetzt synchronisieren'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final yes = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Garmin-Verbindung trennen?'),
                              content: Text(
                                'Die Garmin-Freigabe für dieses Profil wird widerrufen. Garmin kann damit auch andere Verbindungen dieses Kontos zur selben Garmin-Anwendung trennen.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: const Text('Abbrechen'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text('Trennen'),
                                ),
                              ],
                            ),
                          );
                          if (yes == true && mounted)
                            await run(() async {
                              await widget.service.disconnect();
                              account = await widget.service.status();
                            });
                        },
                  child: const Text('Trennen'),
                ),
              ],
            ],
          ),
          if (connected) ...[
            const SizedBox(height: 10),
            Text(
              widget.service.archive.setting('lastPushReceived') == null
                  ? 'Wartet auf die erste Garmin-Lieferung. Synchronisiere deine Uhr mit Garmin Connect.'
                  : 'Letzter Datenempfang: ${_localTime(widget.service.archive.setting("lastPushReceived")!)}',
            ),
            Text(historyLabel(widget.service.archive)),
            if (permissions is List) ...[
              for (final entry in const {
                'ACTIVITY_EXPORT': 'Aktivitäten',
                'HEALTH_EXPORT': 'Gesundheit mit Schlaf und HRV',
                'MCT_EXPORT': 'Zyklusdaten',
              }.entries)
                if (!permissions.contains(entry.key) &&
                    (entry.key != 'MCT_EXPORT' ||
                        widget.service.archive.setting('pushCycleAllowed') ==
                            '1'))
                  Text('Bei Garmin fehlt die Freigabe für ${entry.value}.'),
            ],
            if ((widget.service.archive.setting('pushError') ?? '').isNotEmpty)
              Text(widget.service.archive.setting('pushError')!),
          ],
          if (busy) const LinearProgressIndicator(),
          if (message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Semantics(liveRegion: true, child: Text(message)),
            ),
        ],
      ),
    );
  }
}

String _localTime(String iso) {
  final date = DateTime.parse(iso).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year}, ${two(date.hour)}:${two(date.minute)}';
}
