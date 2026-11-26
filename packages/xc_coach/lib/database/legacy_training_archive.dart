import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

/// Copies only athlete-owned GIULIA values with a verified meaning. They
/// remain archival records until their XC counterparts explicitly adopt them.
void copyLegacyTrainingSettings(Database target, Set<String> athletes) {
  Row? read(String key) => target.select(
    'SELECT key,value,updated_at_utc_us FROM original.app_state WHERE key=?',
    [key],
  ).firstOrNull;
  void store(Row row, String owner, String kind, Object data) {
    target.execute('INSERT INTO main.app_state VALUES (?,?,?)', [
      'xc.legacy.giulia.$owner.$kind',
      jsonEncode(data),
      row['updated_at_utc_us'],
    ]);
  }

  Object? decode(Row row) {
    try {
      return jsonDecode(row['value'] as String);
    } on FormatException {
      return null;
    }
  }

  bool numeric(Object? value) => value is num && value.isFinite;
  bool points(Object? value) =>
      value is List &&
      value.every(
        (p) =>
            p is List &&
            p.length == 4 &&
            p.every((n) => n == null || numeric(n)),
      );
  final assignedRides = <String, String>{};
  final duplicates = <String>{};
  for (final owner in athletes) {
    final row =
        read('indoor_rides.$owner') ??
        read('xc.legacy.giulia.$owner.indoor_rides');
    if (row == null) continue;
    final rides = decode(row);
    if (rides is! List) continue;
    for (final ride in rides.whereType<Map>()) {
      final id = ride['id'];
      if (id is! String || !RegExp(r'^ride-\d{10,20}$').hasMatch(id)) continue;
      if (assignedRides.containsKey(id)) duplicates.add(id);
      assignedRides[id] = owner;
    }
  }
  for (final owner in athletes) {
    final goalRow =
        read('weekly_goal.$owner') ??
        read('xc.legacy.giulia.$owner.weekly_goal');
    if (goalRow != null) {
      final value = decode(goalRow);
      if (value is Map &&
          const {'sessions', 'minutes', 'kilometres'}.contains(value['type']) &&
          numeric(value['target']) &&
          (value['target'] as num) > 0) {
        store(goalRow, owner, 'weekly_goal', {
          'type': value['type'],
          'target': value['target'],
        });
      }
    }
    final estimateRow =
        read('profile.$owner.estimate') ??
        read('xc.legacy.giulia.$owner.estimate');
    if (estimateRow != null) {
      final value = decode(estimateRow);
      if (value is Map &&
          value['session'] is String &&
          [
            'watt',
            'best_w',
            'window_s',
            'started_us',
          ].every((k) => numeric(value[k])) &&
          target
              .select(
                '''SELECT 1 FROM original.session s JOIN original.normalized_session_record n
            ON n.athlete_id=s.athlete_id AND n.source_id=s.id AND n.source='ercolina'
            WHERE s.athlete_id=? AND s.id=? LIMIT 1''',
                [owner, value['session']],
              )
              .isNotEmpty) {
        store(estimateRow, owner, 'estimate', {
          for (final k in [
            'watt',
            'best_w',
            'window_s',
            'started_us',
            'session',
          ])
            k: value[k],
        });
      }
    }
    final row =
        read('indoor_rides.$owner') ??
        read('xc.legacy.giulia.$owner.indoor_rides');
    if (row == null) continue;
    final rides = decode(row);
    if (rides is! List) continue;
    final retained = <Map<String, dynamic>>[];
    for (final ride in rides.whereType<Map>()) {
      final id = ride['id'];
      if (id is! String ||
          assignedRides[id] != owner ||
          duplicates.contains(id)) {
        continue;
      }
      final start = ride['s'];
      if (start is! String ||
          !start.endsWith('Z') ||
          DateTime.tryParse(start)?.isUtc != true ||
          !['d', 'm', 'kj'].every((k) => numeric(ride[k])) ||
          !points(ride['p']) ||
          ride['l'] is! List ||
          !(ride['l'] as List).every((n) => n is int)) {
        continue;
      }
      // Omits the free-form paired-device name and unknown fields.
      retained.add({
        'id': id,
        's': start,
        for (final k in [
          'd',
          'e',
          'kj',
          'm',
          'aw',
          'mw',
          'ac',
          'ah',
          'mh',
          'np',
        ])
          if (numeric(ride[k])) k: ride[k],
        'l': ride['l'],
        'p': ride['p'],
      });
      final samples =
          read('indoor_ride.samples.$id') ??
          read('xc.legacy.giulia.$owner.indoor_samples.$id');
      if (samples != null) {
        final value = decode(samples);
        if (points(value)) store(samples, owner, 'indoor_samples.$id', value!);
      }
    }
    if (retained.isNotEmpty) store(row, owner, 'indoor_rides', retained);
  }
}
