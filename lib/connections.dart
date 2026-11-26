import 'package:flutter/material.dart';
import 'package:xc_coach/database/platform_repository.dart';
import 'package:xc_coach/products/garmin_fit_import.dart';
import 'coach_store.dart';
import 'garmin_connect_screen.dart';
import 'garmin_personal.dart';

class Connections extends StatefulWidget {
  const Connections({super.key, required this.store, required this.athlete});
  final CoachStore store;
  final AthleteSummary athlete;
  @override
  State<Connections> createState() => _ConnectionsState();
}

class _ConnectionsState extends State<Connections> {
  bool busy = false;
  String message = '';
  Future<void> run(Future<String> Function() operation) async {
    setState(() {
      busy = true;
      message = '';
    });
    try {
      final result = await operation();
      if (mounted) setState(() => message = result);
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      widget.store.today.invalidate(widget.athlete.id);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: Text('Daten für ${widget.athlete.name}')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.watch_outlined),
            title: const Text('Garmin Connect'),
            subtitle: const Text('Aktivitäten, Erholung und Frauengesundheit'),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GarminConnectScreen(
                        archive: GarminArchive(widget.store, widget.athlete.id),
                        name: widget.athlete.name,
                      ),
                    ),
                  ),
          ),
          const Divider(),
          Text('Garmin FIT', style: Theme.of(context).textTheme.titleLarge),
          ListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: const Text('Aktivitätsdatei importieren'),
            onTap: busy
                ? null
                : () => run(() async {
                    final fit = await garminFitImport(
                      context: context,
                      trainingActivity: true,
                    ).pick();
                    if (fit == null) return '';
                    widget.store.importFit(widget.athlete.id, fit);
                    return '${fit.fileName} ist im Trainingsbuch.';
                  }),
          ),
          if (busy) const LinearProgressIndicator(),
          if (message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(message),
            ),
        ],
      ),
    ),
  );
}
