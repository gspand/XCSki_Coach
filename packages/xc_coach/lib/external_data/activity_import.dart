/// A product-neutral way to obtain a measured activity from a file.
///
/// LaLa needs the load curve, not a Garmin decoder or a native file picker.
/// The application entry point composes those details and hands this small
/// capability into the diagnostic UI.
library;

import 'dart:typed_data';

import 'normalization/external_data.dart';

class ExternalActivityImport {
  const ExternalActivityImport({
    required this.activity,
    required this.fileName,
    required this.recordCount,
    required this.summary,
    this.deviceName,
    this.warnings = const <String>[],
    this.rawFile,
    this.decoderVersion = 'unknown',
  });

  final ExternalActivity activity;
  final String fileName;
  final int recordCount;
  final ExternalActivitySummary summary;
  final String? deviceName;
  final List<String> warnings;

  /// Exact source file where the adapter obtained one. It is persisted next
  /// to the normalized samples so a future decoder can reproduce the import.
  final Uint8List? rawFile;
  final String decoderVersion;
}

class ExternalActivitySummary {
  const ExternalActivitySummary({
    required this.elapsedSeconds,
    required this.activeSeconds,
    this.loadUnit,
    this.averageLoad,
    this.peakLoad,
    this.workJoule,
    this.distanceMetres,
    this.averageHeartRateBpm,
    this.peakHeartRateBpm,
    this.averageCadencePerMinute,
    this.peakCadencePerMinute,
  });

  final int elapsedSeconds;
  final int activeSeconds;
  final String? loadUnit;
  final double? averageLoad;
  final double? peakLoad;
  final double? workJoule;
  final double? distanceMetres;
  final int? averageHeartRateBpm;
  final int? peakHeartRateBpm;
  final double? averageCadencePerMinute;
  final double? peakCadencePerMinute;
}

class ActivityImportAccess {
  const ActivityImportAccess({required this.sourceLabel, required this.pick});

  final String sourceLabel;

  /// Opens the platform file selector and returns a decoded activity.
  ///
  /// `null` means that the human cancelled the selector. Invalid or
  /// unsupported files throw and are explained by the calling screen.
  final Future<ExternalActivityImport?> Function() pick;
}
