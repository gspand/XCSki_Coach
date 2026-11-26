import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'garmin_personal.dart';

/// Keep each summary, including intraday series. The dashboard projection uses
/// separate keys so a push never replaces an existing personal archive.
void storeGarminPush(GarminArchive archive, GarminJson event) {
  final data = event['data'] as GarminJson;
  final type = event['type'] as String;
  final cycle = event['kind'] == 'cycle';
  if (cycle && !archive.cycleEnabled) return;
  final id =
      data['summaryId'] ??
      data['activityId'] ??
      sha256.convert(utf8.encode(jsonEncode(data))).toString();
  final key = '${cycle ? "cyclePush" : "connectPush"}.$type.$id';
  String? day;
  for (final field in [
    'calendarDate',
    'date',
    'startDate',
    'cycleStartDate',
    'periodStartDate',
    'menstrualCycleStartDate',
  ]) {
    final value = data[field];
    if (value is String &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
        DateTime.tryParse(value)?.toIso8601String().startsWith(value) == true) {
      day = value;
      break;
    }
  }
  final start = data['startTimeInSeconds'];
  final offset = data['startTimeOffsetInSeconds'];
  if (day == null && start is int && offset is int) {
    day = DateTime.fromMillisecondsSinceEpoch(
      (start + offset) * 1000,
      isUtc: true,
    ).toIso8601String().substring(0, 10);
  }
  if (day == null) {
    archive.set('undated.$key', jsonEncode(data));
    return;
  }
  archive.save(day, key, data);
  final metrics = <String, dynamic>{};
  void metric(String name, dynamic value) {
    if (value is num && value.isFinite && value >= 0) metrics[name] = value;
  }

  if (type == 'sleeps') metric('sleep', data['durationInSeconds']);
  if (type == 'hrv') metric('hrv', data['lastNightAvg']);
  if (type == 'dailies') {
    metric('pulse', data['restingHeartRateInBeatsPerMinute']);
    metric('stress', data['averageStressLevel']);
    metric('battery', data['bodyBatteryMostRecentValue']);
  }
  if (type == 'stressDetails') {
    final values = data['timeOffsetBodyBatteryValues'];
    if (values is Map) {
      final offsets =
          values.keys.map((v) => int.tryParse(v.toString())).nonNulls.toList()
            ..sort();
      if (offsets.isNotEmpty)
        metric('battery', values[offsets.last.toString()]);
    }
  }
  if (type == 'pulseox') metric('oxygen', data['averageSpO2']);
  if (cycle) metric('cycle', data['dayInCycle'] ?? data['cycleDay']);
  if (metrics.isNotEmpty) {
    final series = cycle ? 'cycleConnectMetrics' : 'connectMetrics';
    archive.save(day, series, {
      ...?archive.read(day, series) as GarminJson?,
      ...metrics,
    });
  }
}
