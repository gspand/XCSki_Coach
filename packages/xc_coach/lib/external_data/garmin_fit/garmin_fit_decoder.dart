/// Garmin FIT -> GIULIA's neutral external activity model.
///
/// FIT timestamps are UTC seconds since the FIT epoch. The SDK exposes them
/// as `DateTime`; only epoch microseconds leave this adapter so timezone rules
/// cannot leak into protocol matching.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fit_sdk/fit_sdk.dart';

import '../activity_import.dart';
import '../normalization/external_data.dart';

class GarminFitDecodeException implements Exception {
  const GarminFitDecodeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GarminFitDecoder {
  const GarminFitDecoder();

  ExternalActivityImport decode(Uint8List bytes, {required String fileName, bool trainingActivity = false, FitFileOrigin? fileOrigin}) {
    if (bytes.length < 14) {
      throw const GarminFitDecodeException('Die FIT-Datei ist zu kurz.');
    }

    FileIdMesg? fileId;
    final sessions = <SessionMesg>[];
    final records = <RecordMesg>[];
    try {
      final decoder = Decode()
        ..onMesg = (message) {
          switch (message.num) {
            case MesgNum.fileId:
              fileId ??= FileIdMesg.fromMesg(message);
            case MesgNum.session:
              sessions.add(SessionMesg.fromMesg(message));
            case MesgNum.record:
              records.add(RecordMesg.fromMesg(message));
          }
        };
      decoder.read(bytes);
    } on Object catch (failure) {
      throw GarminFitDecodeException(
        'FIT-Datei ungültig oder beschädigt: $failure',
      );
    }

    if (fileId?.getManufacturer() == Manufacturer.strava) {
      throw const GarminFitDecodeException('Die FIT-Datei nennt Strava als Ersteller. Diese Datenquelle ist gesperrt.');
    }
    if (records.isEmpty) {
      throw const GarminFitDecodeException(
        'Die FIT-Datei enthält keinen Aktivitätsverlauf.',
      );
    }

    records.sort((a, b) {
      final left = a.getTimestamp()?.microsecondsSinceEpoch ?? 0;
      final right = b.getTimestamp()?.microsecondsSinceEpoch ?? 0;
      return left.compareTo(right);
    });

    final session = _primarySession(sessions, records);
    final activityRecords = _recordsForSession(session, records);
    final isNordic = session?.getSport() == Sport.crossCountrySkiing;
    final sport = isNordic
        ? (session?.getSubSport() == SubSport.skateSkiing ? 'NordicSkiSkating' : 'NordicSki')
        : trainingActivity ? switch(session?.getSport()) {
          Sport.walking => 'walk', Sport.hiking => 'hike', Sport.cycling || Sport.eBiking => 'cycling',
          Sport.running || Sport.wheelchairPushRun => 'running', Sport.snowshoeing => 'snowshoe',
          _ => 'generic',
        } : _sportOf(session?.getSport(), activityRecords);
    final loadKind = isNordic
        ? (activityRecords.any((r) => r.getPower() != null) ? _LoadKind.power : _LoadKind.speed)
        : _loadKindFor(sport);
    final samples = <ExternalLoadSample>[];
    var timestampedRecords = 0;
    for (final record in activityRecords) {
      final timestamp = record.getTimestamp();
      if (timestamp == null) continue;
      timestampedRecords++;
      final load = switch (loadKind) {
        _LoadKind.power => record.getPower()?.toDouble(),
        _LoadKind.speed =>
          (record.getEnhancedSpeed() ?? record.getSpeed()) == null
              ? null
              : (record.getEnhancedSpeed() ?? record.getSpeed())! * 3.6,
      };
      // Zero denotes a pause or recovery, not a measured test stage. Keeping
      // it would let a post-exercise lactate sample become a fictitious 0-W
      // stage merely because the activity file still covers that timestamp.
      if (load == null || !load.isFinite || load <= 0) continue;
      samples.add(
        ExternalLoadSample(
          atUtcUs: timestamp.toUtc().microsecondsSinceEpoch,
          loadValue: load,
          loadUnit: loadKind == _LoadKind.power ? 'W' : 'km/h',
          heartRateBpm: _validHeartRate(record.getHeartRate()),
          cadencePerMinute: _validCadence(record.getCadence()),
        ),
      );
    }

    if (timestampedRecords == 0) {
      throw const GarminFitDecodeException(
        'Die FIT-Aktivität enthält keine Zeitstempel.',
      );
    }
    if (samples.isEmpty && !trainingActivity) {
      final missing = loadKind == _LoadKind.power ? 'Leistung' : 'Tempo';
      throw GarminFitDecodeException(
        'Die FIT-Aktivität enthält keine verwertbaren $missing-Daten.',
      );
    }

    final times = activityRecords.map((r) => r.getTimestamp()?.microsecondsSinceEpoch).nonNulls;
    final firstSample = times.first;
    final lastSample = times.last;
    final declaredStart = session
        ?.getStartTime()
        ?.toUtc()
        .microsecondsSinceEpoch;
    final declaredEnd = session?.getTimestamp()?.toUtc().microsecondsSinceEpoch;
    final start = declaredStart == null || declaredStart > firstSample
        ? firstSample
        : declaredStart;
    final end = declaredEnd == null || declaredEnd < lastSample
        ? lastSample
        : declaredEnd;
    final hash = sha256.convert(bytes).toString();
    final messageIndex = session?.getMessageIndex() ?? 0;
    final warnings = <String>[
      if (sessions.isEmpty)
        'Die Datei enthält keine Session-Zusammenfassung; Beginn und Ende '
            'wurden aus den Messpunkten bestimmt.',
      if (sessions.length > 1)
        'Die Datei enthält ${sessions.length} Sessions. Für den Stufentest '
            'wurde die Session mit den meisten passenden Messpunkten verwendet.',
      if (session?.getAvgHeartRate() == null && activityRecords.every((r) => _validHeartRate(r.getHeartRate()) == null))
        'In der Aktivität wurde keine Herzfrequenz gefunden.',
    ];

    return ExternalActivityImport(
      activity: ExternalActivity(
        provider: ExternalProvider.garmin,
        fitFileOrigin: fileOrigin,
        sourceId: 'fit:$hash:$messageIndex',
        sport: sport,
        startedAtUtcUs: start,
        endedAtUtcUs: end,
        samples: List<ExternalLoadSample>.unmodifiable(samples),
      ),
      fileName: fileName,
      recordCount: trainingActivity ? timestampedRecords : samples.length,
      summary: _summary(session, samples, activityRecords, loadKind, start, end),
      deviceName: _deviceName(fileId),
      warnings: List<String>.unmodifiable(warnings),
      rawFile: Uint8List.fromList(bytes),
      decoderVersion: trainingActivity ? 'xc-coach-fit-1' : 'garmin-fit.dart-v1/fit-profile-21.188',
    );
  }

  ExternalActivitySummary _summary(
    SessionMesg? session,
    List<ExternalLoadSample> samples,
    List<RecordMesg> records,
    _LoadKind loadKind,
    int startUtcUs,
    int endUtcUs,
  ) {
    final elapsed =
        session?.getTotalElapsedTime()?.round() ??
        ((endUtcUs - startUtcUs) / Duration.microsecondsPerSecond).round();
    final active = session?.getTotalTimerTime()?.round() ?? elapsed;
    final loads = [for (final sample in samples) sample.loadValue];
    final heartRates = records
        .map((r) => _validHeartRate(r.getHeartRate()))
        .nonNulls
        .toList();
    final cadences = samples
        .map((sample) => sample.cadencePerMinute)
        .nonNulls
        .toList();
    final sessionAverage = loadKind == _LoadKind.power
        ? session?.getAvgPower()?.toDouble()
        : (session?.getEnhancedAvgSpeed() ?? session?.getAvgSpeed()) == null
        ? null
        : (session?.getEnhancedAvgSpeed() ?? session?.getAvgSpeed())! * 3.6;
    final sessionPeak = loadKind == _LoadKind.power
        ? session?.getMaxPower()?.toDouble()
        : (session?.getEnhancedMaxSpeed() ?? session?.getMaxSpeed()) == null
        ? null
        : (session?.getEnhancedMaxSpeed() ?? session?.getMaxSpeed())! * 3.6;
    return ExternalActivitySummary(
      elapsedSeconds: elapsed < 0 ? 0 : elapsed,
      activeSeconds: active < 0 ? 0 : active,
      loadUnit: loadKind == _LoadKind.power ? 'W' : 'km/h',
      averageLoad: sessionAverage ?? _average(loads),
      peakLoad: sessionPeak ?? _maximum(loads),
      workJoule: loadKind == _LoadKind.power
          ? session?.getTotalWork()?.toDouble() ?? _work(samples)
          : null,
      distanceMetres: session?.getTotalDistance(),
      averageHeartRateBpm:
          _validHeartRate(session?.getAvgHeartRate()) ??
          _average(heartRates)?.round(),
      peakHeartRateBpm:
          _validHeartRate(session?.getMaxHeartRate()) ??
          _maximum(heartRates)?.round(),
      averageCadencePerMinute:
          session?.getAvgCadence()?.toDouble() ?? _average(cadences),
      peakCadencePerMinute:
          session?.getMaxCadence()?.toDouble() ?? _maximum(cadences),
    );
  }

  double? _average(List<num> values) => values.isEmpty
      ? null
      : values.fold<double>(0, (sum, value) => sum + value) / values.length;

  double? _maximum(List<num> values) => values.isEmpty
      ? null
      : values.fold<double>(
          -double.infinity,
          (maximum, value) => value > maximum ? value.toDouble() : maximum,
        );

  double _work(List<ExternalLoadSample> samples) {
    var joule = 0.0;
    for (var index = 1; index < samples.length; index++) {
      final seconds =
          (samples[index].atUtcUs - samples[index - 1].atUtcUs) /
          Duration.microsecondsPerSecond;
      // A large recording gap is not evidence that the preceding wattage was
      // sustained. Normal FIT record intervals are one second.
      if (seconds > 0 && seconds <= 10) {
        joule +=
            (samples[index - 1].loadValue + samples[index].loadValue) /
            2 *
            seconds;
      }
    }
    return joule;
  }

  SessionMesg? _primarySession(
    List<SessionMesg> sessions,
    List<RecordMesg> records,
  ) {
    if (sessions.isEmpty) return null;
    SessionMesg? best;
    var bestCount = -1;
    for (final session in sessions) {
      final start = session.getStartTime()?.microsecondsSinceEpoch;
      final end = session.getTimestamp()?.microsecondsSinceEpoch;
      final count = records.where((record) {
        final at = record.getTimestamp()?.microsecondsSinceEpoch;
        if (at == null) return false;
        return (start == null || at >= start) && (end == null || at <= end);
      }).length;
      if (count > bestCount) {
        best = session;
        bestCount = count;
      }
    }
    return best;
  }

  List<RecordMesg> _recordsForSession(
    SessionMesg? session,
    List<RecordMesg> records,
  ) {
    if (session == null) return records;
    final start = session.getStartTime()?.microsecondsSinceEpoch;
    final end = session.getTimestamp()?.microsecondsSinceEpoch;
    final inside = <RecordMesg>[
      for (final record in records)
        if (record.getTimestamp() case final timestamp?
            when (start == null || timestamp.microsecondsSinceEpoch >= start) &&
                (end == null || timestamp.microsecondsSinceEpoch <= end))
          record,
    ];
    return inside.isEmpty ? records : inside;
  }

  String _sportOf(int? fitSport, List<RecordMesg> records) =>
      switch (fitSport) {
        Sport.cycling || Sport.eBiking => 'cycling',
        Sport.running || Sport.walking || Sport.wheelchairPushRun => 'running',
        Sport.fitnessEquipment ||
        Sport.training ||
        Sport.rowing ||
        Sport.hiit => 'generic',
        _ =>
          records.any((record) => record.getPower() != null)
              ? 'generic'
              : 'running',
      };

  _LoadKind _loadKindFor(String sport) =>
      sport == 'running' ? _LoadKind.speed : _LoadKind.power;

  int? _validHeartRate(int? value) =>
      value != null && value >= 25 && value <= 250 ? value : null;

  int? _validCadence(int? value) =>
      value != null && value >= 0 && value <= 255 ? value : null;

  String? _deviceName(FileIdMesg? fileId) {
    final name = fileId?.getProductName()?.trim();
    if (name != null && name.isNotEmpty) return name;
    final product = fileId?.getProduct();
    return product == null ? null : 'Garmin FIT Produkt $product';
  }
}

enum _LoadKind { power, speed }
