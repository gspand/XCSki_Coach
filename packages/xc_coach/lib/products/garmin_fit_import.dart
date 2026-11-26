/// Composition of Flutter's native file selector and the Garmin FIT adapter.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../external_data/normalization/external_data.dart';

import '../external_data/activity_import.dart';
import '../external_data/garmin_fit/garmin_fit_decoder.dart';

ActivityImportAccess garminFitImport({
  required BuildContext context,
  bool trainingActivity = false,
  GarminFitDecoder decoder = const GarminFitDecoder(),
}) => ActivityImportAccess(
  sourceLabel: 'Garmin FIT',
  pick: () async {
    const fitFiles = XTypeGroup(
      label: 'Garmin FIT-Aktivität',
      extensions: <String>['fit'],
      mimeTypes: <String>['application/octet-stream'],
      uniformTypeIdentifiers: <String>['public.data'],
    );
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[fitFiles],
    );
    if (file == null) return null;
    if (!context.mounted) return null;
    final origin = await showDialog<FitFileOrigin>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Woher stammt diese FIT-Datei?'),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              'Wähle die Quelle, von der du die Datei direkt erhalten hast. Strava-Exporte sind für den Coach gesperrt.',
            ),
          ),
          for (final option in const {
            FitFileOrigin.recordingDevice: 'Direkt vom Aufzeichnungsgerät',
            FitFileOrigin.garminConnect: 'Direkt aus Garmin Connect',
          }.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, option.key),
              child: Text(option.value),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Andere oder unbekannte Quelle · abbrechen'),
          ),
        ],
      ),
    );
    if (origin == null) return null;
    final size = await file.length();
    if (size > 64 * 1024 * 1024) {
      throw const GarminFitDecodeException(
        'Die FIT-Datei ist grösser als 64 MB und wird nicht geladen.',
      );
    }
    final bytes = await file.readAsBytes();
    return decoder.decode(
      bytes,
      fileName: file.name,
      fileOrigin: origin,
      trainingActivity: trainingActivity,
    );
  },
);
