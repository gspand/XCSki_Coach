import 'dart:convert';
import 'dart:typed_data';

import '../core/models.dart';
import '../core/stroke_metrics.dart';
import '../domain/platform.dart';
import '../core/raw_device_frame.dart';
import 'giulia_database.dart';
import 'platform_repository.dart';

/// Everything a recording must declare before the first sample is stored.
///
/// The athlete is chosen per session, not per app installation, so one shared
/// device can be used by an entire training group in sequence.
class SessionStart {
  const SessionStart({
    required this.id,
    required this.organizationId,
    required this.athleteId,
    required this.startedAtUtcUs,
    required this.algorithmVersion,
    required this.processingConfigJson,
    this.dataFormatVersion = 'giulia.session.v1',
    this.appVersion,
    this.sensorSnapshotJson,
    this.calibrationSnapshotJson,
    this.batteryStartJson,
    this.deviceId,
    this.teamId,
    this.workoutId,
    this.recordedByUserId,
    this.movementType,
    this.resistanceSetting,
  });

  final String id;
  final String organizationId;
  final String athleteId;
  final String? deviceId;
  final String? teamId;
  final String? workoutId;
  final String? recordedByUserId;
  final int startedAtUtcUs;
  final String algorithmVersion;
  final String processingConfigJson;
  final String dataFormatVersion;
  final String? appVersion;
  final String? sensorSnapshotJson;
  final String? calibrationSnapshotJson;
  final String? batteryStartJson;
  final String? movementType;
  final String? resistanceSetting;
}

/// Append-only recorder for measured data.
///
/// Raw samples are written in bounded transactions and never updated. Sessions
/// are attributed to an organization and an athlete; the device is referenced
/// as equipment provenance only.
class SessionRepository {
  SessionRepository(this.database, {PlatformRepository? platform})
    : platform = platform ?? PlatformRepository(database);

  final GiuliaDatabase database;
  final PlatformRepository platform;
  final List<RawSensorSample> _pendingRaw = [];
  final List<DerivedSample> _pendingDerived = [];
  final List<({int ordinal, RawSensorFrame frame})> _pendingFrames = [];
  String? _activeSessionId;
  String? _activeDeviceId;
  Set<String> _activeSensorIds = const <String>{};
  int _nextFrameOrdinal = 0;
  int _nextDeviceFrameOrdinal = 0;
  String? _activeAlgorithmVersionValue;
  final Map<String, Object?> _initialBatteries = {};

  /// Keeps write amplification bounded while limiting the uncheckpointed
  /// window at a 100 Hz dual-sensor stream to well below one second.
  static const int rawBatchSize = 64;

  String? get activeSessionId => _activeSessionId;

  /// Starts a recording after verifying tenancy and, when a user is acting,
  /// the permission to record for that athlete.
  void startSession(SessionStart session) {
    if (_activeSessionId != null) {
      throw StateError('A session is already being recorded.');
    }
    final athleteOrganization = platform.organizationOfAthlete(
      session.athleteId,
    );
    if (athleteOrganization != session.organizationId) {
      throw const PlatformAccessException(
        'The athlete does not belong to the recording organization.',
      );
    }
    if (session.deviceId != null &&
        _deviceOrganization(session.deviceId!) != session.organizationId) {
      throw const PlatformAccessException(
        'The device belongs to a different organization.',
      );
    }
    final actor = session.recordedByUserId;
    if (actor != null) {
      platform.assertCanRecordFor(userId: actor, athleteId: session.athleteId);
    }

    database.transaction(() {
      final snapshots = _sessionSnapshots(session);
      database.raw.execute(
        '''INSERT INTO session(
           id, organization_id, athlete_id, device_id, team_id, workout_id,
           recorded_by_user_id, started_at_utc_us, movement_type,
           resistance_setting, algorithm_version, processing_config_json,
           updated_at_utc_us, recording_state, last_checkpoint_utc_us,
           data_format_version, app_version, sensor_snapshot_json,
           calibration_snapshot_json, battery_start_json)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'recording', ?,
                 ?, ?, ?, ?, ?)''',
        [
          session.id,
          session.organizationId,
          session.athleteId,
          session.deviceId,
          session.teamId,
          session.workoutId,
          session.recordedByUserId,
          session.startedAtUtcUs,
          session.movementType,
          session.resistanceSetting,
          session.algorithmVersion,
          session.processingConfigJson,
          session.startedAtUtcUs,
          session.startedAtUtcUs,
          session.dataFormatVersion,
          session.appVersion,
          snapshots.sensorJson,
          snapshots.calibrationJson,
          snapshots.batteryJson,
        ],
      );
      platform.enqueueSync(
        organizationId: session.organizationId,
        entity: 'session',
        entityId: session.id,
        operation: 'insert',
        nowUtcUs: session.startedAtUtcUs,
      );
      platform.writeAudit(
        organizationId: session.organizationId,
        actorUserId: session.recordedByUserId,
        action: 'session_started',
        entity: 'session',
        entityId: session.id,
        nowUtcUs: session.startedAtUtcUs,
      );
    });
    _activeSessionId = session.id;
    _bindDevice(session.deviceId);
    _nextFrameOrdinal = 0;
    _nextDeviceFrameOrdinal = 0;
    _activeAlgorithmVersionValue = session.algorithmVersion;
    _initialBatteries
      ..clear()
      ..addAll(_jsonObject(session.batteryStartJson ?? '{}'));
  }

  /// Writes a session that is already over.
  ///
  /// [startSession] is the live path and deliberately allows only one active
  /// recording. A session that happened in the past — imported from another
  /// system, for instance — has no live phase to manage, so it is written in
  /// one step.
  ///
  /// It runs through exactly the same tenancy and permission checks. A
  /// historical session is not a privileged back door.
  void recordCompletedSession({
    required SessionStart session,
    required int endedAtUtcUs,
    String? notes,
  }) {
    if (endedAtUtcUs < session.startedAtUtcUs) {
      throw const PlatformAccessException(
        'A session cannot end before it started.',
      );
    }
    final previous = _activeSessionId;
    final previousDevice = _activeDeviceId;
    final previousSensors = _activeSensorIds;
    final previousFrameOrdinal = _nextFrameOrdinal;
    final previousDeviceFrameOrdinal = _nextDeviceFrameOrdinal;
    final previousAlgorithm = _activeAlgorithmVersionValue;
    _activeSessionId = null;
    try {
      startSession(session);
      database.transaction(() {
        database.raw.execute(
          '''UPDATE session
              SET ended_at_utc_us = ?, notes = ?, updated_at_utc_us = ?,
                  recording_state = 'completed', last_checkpoint_utc_us = ?
            WHERE id = ?''',
          [endedAtUtcUs, notes, endedAtUtcUs, endedAtUtcUs, session.id],
        );
        platform.enqueueSync(
          organizationId: session.organizationId,
          entity: 'session',
          entityId: session.id,
          operation: 'update',
          nowUtcUs: endedAtUtcUs,
        );
        platform.writeAudit(
          organizationId: session.organizationId,
          actorUserId: session.recordedByUserId,
          action: 'session_imported',
          entity: 'session',
          entityId: session.id,
          nowUtcUs: endedAtUtcUs,
        );
      });
    } finally {
      _activeSessionId = previous;
      _activeDeviceId = previousDevice;
      _activeSensorIds = previousSensors;
      _nextFrameOrdinal = previousFrameOrdinal;
      _nextDeviceFrameOrdinal = previousDeviceFrameOrdinal;
      _activeAlgorithmVersionValue = previousAlgorithm;
    }
  }

  /// Queues one immutable observation for the active session.
  void appendRaw(RawSensorSample sample) {
    _assertRecording();
    _assertActiveSensor(sample.sensorId);
    _validateRaw(sample);
    _captureInitialBattery(sample);
    _pendingRaw.add(sample);
    if (_pendingCount >= rawBatchSize) flush();
  }

  /// Queues the exact BLE frame whether decoding succeeded or not.
  void appendRawFrame(RawSensorFrame frame) {
    final sessionId = _assertRecording();
    _assertActiveSensor(frame.sensorId);
    if (frame.receivedAtUs < 0 || frame.bytes.isEmpty) {
      throw ArgumentError('A raw sensor frame needs bytes and a valid clock.');
    }
    // The transport frame is the irreplaceable truth. Commit it before
    // returning to the BLE callback; normalized/derived rows may be batched
    // because they can be rebuilt from this payload.
    database.raw.execute(
      '''INSERT INTO raw_sensor_frame(
           session_id, ordinal, sensor_id, side, received_at_monotonic_us,
           payload, decoder_version, decode_valid, failure_code,
           decoded_device_time_us, decoded_sequence)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        sessionId,
        _nextFrameOrdinal,
        frame.sensorId,
        frame.side.name,
        frame.receivedAtUs,
        frame.bytes,
        frame.decoderVersion,
        frame.valid ? 1 : 0,
        frame.failureCode,
        frame.deviceTimeUs,
        frame.sequence,
      ],
    );
    _nextFrameOrdinal++;
  }

  /// Commits one complete logical-device notification before returning.
  void appendRawDeviceFrame(RawDeviceFrame frame) {
    _assertRecording();
    if (frame.deviceId != _activeDeviceId ||
        frame.receivedAtUs < 0 ||
        frame.bytes.isEmpty) {
      throw ArgumentError(
        'A raw device frame needs the active device and bytes.',
      );
    }
    database.raw.execute(
      '''INSERT INTO raw_device_frame(
           session_id, ordinal, device_id, received_at_monotonic_us,
           payload, decoder_version, source_channel, decode_valid, failure_code,
           decoded_device_time_us, decoded_sequence, stream_epoch,
           schema_id, envelope_flags)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        _activeSessionId!,
        _nextDeviceFrameOrdinal,
        frame.deviceId,
        frame.receivedAtUs,
        frame.bytes,
        frame.decoderVersion,
        frame.channel,
        frame.valid ? 1 : 0,
        frame.failureCode,
        frame.deviceTimeUs,
        frame.sequence,
        frame.streamEpoch,
        frame.schemaId,
        frame.flags,
      ],
    );
    _nextDeviceFrameOrdinal++;
  }

  /// Queues the reproducible output of the versioned processing pipeline.
  /// It never replaces the raw sample or frame it came from.
  void appendDerived(DerivedSample sample) {
    _assertRecording();
    _assertActiveSensor(sample.raw.sensorId);
    if (sample.alignedTimeUs < 0 ||
        !sample.calibratedForceNewton.isFinite ||
        !sample.calibratedVelocityMetresPerSecond.isFinite ||
        !sample.calibratedPowerWatt.isFinite ||
        !sample.filteredForceNewton.isFinite ||
        !sample.filteredPowerWatt.isFinite) {
      throw ArgumentError('A derived sample contains invalid numeric data.');
    }
    _pendingDerived.add(sample);
    if (_pendingCount >= rawBatchSize) flush();
  }

  /// Commits queued raw data atomically. Duplicate packets keep the first
  /// observed record because the primary key denotes one device observation.
  void flush() {
    final sessionId = _activeSessionId;
    if (sessionId == null || _pendingCount == 0) return;
    database.transaction(() {
      final rawStatement = database.raw.prepare(
        '''INSERT OR IGNORE INTO raw_sensor_sample(
             session_id, sensor_id, device_time_us, received_at_monotonic_us,
             sequence, payload, force_n, velocity_m_s, power_w,
             battery_percent, parser_valid, pulling, source_epoch,
             mapped_time_us, status_flags, position_m, optical_raw,
             optical_min, optical_max, hall_passes, flywheel_revolutions,
                 stroke_counter, battery_mv, missed_samples, adc_errors,
                     angular_velocity_rad_s, stroke_event_time_us, stroke_source,
                     stroke_events_supported
           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                       ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      );
      try {
        for (final sample in _pendingRaw) {
          rawStatement.execute([
            sessionId,
            sample.sensorId,
            sample.deviceTimeUs,
            sample.receivedAtUs,
            sample.sequence,
            sample.payload,
            sample.forceNewton,
            sample.velocityMetresPerSecond,
            sample.powerWatt,
            sample.batteryPercent,
            sample.packetValid ? 1 : 0,
            switch (sample.pulling) {
              true => 1,
              false => 0,
              null => null,
            },
            sample.sourceEpoch,
            sample.mappedTimeUs,
            sample.statusFlags,
            sample.positionMetres,
            sample.opticalRaw,
            sample.opticalMinimum,
            sample.opticalMaximum,
            sample.hallPasses,
            sample.flywheelRevolutions,
            sample.strokeCounter,
            sample.batteryMillivolts,
            sample.missedSamples,
            sample.adcErrors,
            sample.angularVelocityRadPerSecond,
            sample.strokeEventTimeUs,
            sample.strokeSource,
            sample.firmwareStrokeEventsAvailable ? 1 : 0,
          ]);
        }
      } finally {
        rawStatement.dispose();
      }

      final frameStatement = database.raw.prepare(
        '''INSERT INTO raw_sensor_frame(
             session_id, ordinal, sensor_id, side,
             received_at_monotonic_us, payload, decoder_version,
             decode_valid, failure_code, decoded_device_time_us,
             decoded_sequence)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      );
      try {
        for (final pending in _pendingFrames) {
          final frame = pending.frame;
          frameStatement.execute([
            sessionId,
            pending.ordinal,
            frame.sensorId,
            frame.side.name,
            frame.receivedAtUs,
            frame.bytes,
            frame.decoderVersion,
            frame.valid ? 1 : 0,
            frame.failureCode,
            frame.deviceTimeUs,
            frame.sequence,
          ]);
        }
      } finally {
        frameStatement.dispose();
      }

      final derivedStatement = database.raw.prepare(
        '''INSERT OR IGNORE INTO derived_sample(
             session_id, sensor_id, aligned_time_us, calibrated_force_n,
             calibrated_velocity_m_s, calibrated_power_w, filtered_force_n,
             filtered_power_w, quality, algorithm_version, source_epoch)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      );
      try {
        for (final sample in _pendingDerived) {
          derivedStatement.execute([
            sessionId,
            sample.raw.sensorId,
            sample.alignedTimeUs,
            sample.calibratedForceNewton,
            sample.calibratedVelocityMetresPerSecond,
            sample.calibratedPowerWatt,
            sample.filteredForceNewton,
            sample.filteredPowerWatt,
            sample.quality.name,
            _activeAlgorithmVersionValue!,
            sample.raw.sourceEpoch,
          ]);
        }
      } finally {
        derivedStatement.dispose();
      }
    });
    _pendingRaw.clear();
    _pendingFrames.clear();
    _pendingDerived.clear();
  }

  int get _pendingCount =>
      _pendingRaw.length + _pendingFrames.length + _pendingDerived.length;

  /// Speichert einen abgeschlossenen Zug der laufenden Aufzeichnung.
  ///
  /// Die Tabelle gab es seit v1 und niemand schrieb hinein: gemessen wurde
  /// bisher nur im Stufentest, und der speichert Stufen. Ein freies Training
  /// besteht aber aus Zügen, und ein Zug ist die Einheit, in der dieses Gerät
  /// Leistung überhaupt kennt.
  ///
  /// Anders als ein Rohwert hängt ein Zug an keinem registrierten Sensor. Er
  /// ist deshalb das, was eine Aufzeichnung ohne angelegtes Gerät festhalten
  /// kann — und das ist der Normalfall, solange die Anwendung keinen
  /// Bildschirm hat, der ein Gerät anlegt.
  void appendStroke(
    Stroke stroke, {
    required int ordinal,
    required String algorithmVersion,
  }) {
    final sessionId = _assertRecording();
    database.raw.execute(
      '''INSERT OR IGNORE INTO stroke(
           id, session_id, ordinal, start_us, end_us, recovery_us, work_j,
           impulse_ns, mean_power_w, peak_power_w, peak_force_n, left_work_j,
           right_work_j, quality, algorithm_version, sides_json,
           firmware_events_json, technique
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        '$sessionId-stroke-$ordinal',
        sessionId,
        ordinal,
        stroke.startUs,
        stroke.endUs,
        stroke.recoveryUs,
        stroke.workJoule,
        stroke.impulseNewtonSecond,
        stroke.meanPowerWatt,
        stroke.peakPowerWatt,
        stroke.peakForceNewton,
        stroke.leftWorkJoule,
        stroke.rightWorkJoule,
        stroke.quality.name,
        algorithmVersion,
        _encodeStrokeSides(stroke.sides),
        _encodeFirmwareEvents(stroke.firmwareEvents),
        stroke.technique.name,
      ],
    );
  }

  /// Die Züge einer Sitzung, in der Reihenfolge, in der sie gefahren wurden.
  List<Stroke> loadStrokes(String sessionId) => database.raw
      .select(
        '''SELECT start_us, end_us, recovery_us, work_j, impulse_ns,
                  mean_power_w, peak_power_w, peak_force_n, left_work_j,
                  right_work_j, quality, sides_json, firmware_events_json,
                  technique
             FROM stroke WHERE session_id = ? ORDER BY ordinal''',
        [sessionId],
      )
      .map((row) {
        final sides = _decodeStrokeSides(row['sides_json'] as String?);
        int? peakAt(StrokeMetrics? side) => side == null
            ? null
            : side.startUs +
                  ((side.endUs - side.startUs) * side.peakPowerPhase).round();
        return Stroke(
          startUs: row['start_us'] as int,
          endUs: row['end_us'] as int,
          recoveryUs: row['recovery_us'] as int,
          workJoule: row['work_j'] as double,
          impulseNewtonSecond: row['impulse_ns'] as double,
          meanPowerWatt: row['mean_power_w'] as double,
          peakPowerWatt: row['peak_power_w'] as double,
          peakForceNewton: row['peak_force_n'] as double,
          leftWorkJoule: row['left_work_j'] as double,
          rightWorkJoule: row['right_work_j'] as double,
          quality: SignalQuality.values.byName(row['quality'] as String),
          peakLeftPowerWatt: sides?.left.peakPowerWatt,
          peakRightPowerWatt: sides?.right.peakPowerWatt,
          leftPeakAtUs: peakAt(sides?.left),
          rightPeakAtUs: peakAt(sides?.right),
          sides: sides,
          firmwareEvents: _decodeFirmwareEvents(
            row['firmware_events_json'] as String?,
          ),
          technique: StrokeTechnique.values.byName(row['technique'] as String),
        );
      })
      .toList(growable: false);

  /// Records one heart rate reading of the active session.
  ///
  /// Written immediately rather than batched: heart rate arrives about once a
  /// second, so batching would buy nothing and would risk losing the last
  /// readings of a step when a test is stopped abruptly.
  void appendHeartRate(HeartRateSample sample) {
    final sessionId = _assertRecording();
    if (sample.recordedAtUs < 0 ||
        sample.bpm < 20 ||
        sample.bpm > 250 ||
        sample.rrIntervalsMs.any((value) => !value.isFinite || value <= 0)) {
      throw ArgumentError('Invalid heart-rate observation.');
    }
    final rr = sample.rrIntervalsMs.isEmpty
        ? null
        : Uint8List.fromList(utf8.encode(jsonEncode(sample.rrIntervalsMs)));
    database.raw.execute(
      '''INSERT OR IGNORE INTO heart_rate_sample(
           session_id, recorded_at_us, bpm, rr_intervals_ms,
           contact_detected)
         VALUES (?, ?, ?, ?, ?)''',
      [
        sessionId,
        sample.recordedAtUs,
        sample.bpm,
        rr,
        switch (sample.contactDetected) {
          true => 1,
          false => 0,
          null => null,
        },
      ],
    );
  }

  /// Heart rate readings of a session, oldest first.
  List<HeartRateSample> loadHeartRates(String sessionId) => database.raw
      .select(
        '''SELECT recorded_at_us, bpm, rr_intervals_ms, contact_detected
             FROM heart_rate_sample
            WHERE session_id = ? ORDER BY recorded_at_us''',
        [sessionId],
      )
      .map(
        (row) => HeartRateSample(
          recordedAtUs: row['recorded_at_us'] as int,
          bpm: row['bpm'] as int,
          rrIntervalsMs: _decodeRrIntervals(row['rr_intervals_ms']),
          contactDetected: switch (row['contact_detected'] as int?) {
            1 => true,
            0 => false,
            _ => null,
          },
        ),
      )
      .toList(growable: false);

  /// Loads original samples in recorded arrival order for replay. Nothing is
  /// recalibrated, filtered or synthesized in this operation.
  List<RawSensorSample> loadRawSamples(String sessionId) =>
      iterateRawSamples(sessionId).toList(growable: false);

  Iterable<RawSensorSample> iterateRawSamples(String sessionId) => database
      .readPages(
        '''SELECT raw.sensor_id, sensor.side, raw.device_time_us,
                  raw.received_at_monotonic_us, raw.sequence, raw.payload,
                  raw.force_n, raw.velocity_m_s, raw.power_w,
                  raw.battery_percent, raw.parser_valid, raw.pulling,
                  raw.source_epoch, raw.mapped_time_us, raw.status_flags,
                  raw.position_m, raw.optical_raw, raw.optical_min,
                  raw.optical_max, raw.hall_passes, raw.flywheel_revolutions,
                  raw.stroke_counter, raw.battery_mv, raw.missed_samples,
                  raw.adc_errors, raw.angular_velocity_rad_s,
                  raw.stroke_event_time_us, raw.stroke_source,
                  raw.stroke_events_supported
             FROM raw_sensor_sample raw
             JOIN sensor ON sensor.id = raw.sensor_id
            WHERE raw.session_id = ?
            ORDER BY raw.received_at_monotonic_us, raw.rowid''',
        [sessionId],
      )
      .map((row) {
        final payload = row['payload'];
        return RawSensorSample(
          sensorId: row['sensor_id'] as String,
          side: SensorSide.values.byName(row['side'] as String),
          deviceTimeUs: row['device_time_us'] as int,
          receivedAtUs: row['received_at_monotonic_us'] as int,
          sequence: row['sequence'] as int,
          forceNewton: row['force_n'] as double,
          velocityMetresPerSecond: row['velocity_m_s'] as double,
          powerWatt: row['power_w'] as double,
          batteryPercent: row['battery_percent'] as int?,
          packetValid: (row['parser_valid'] as int) == 1,
          pulling: switch (row['pulling'] as int?) {
            1 => true,
            0 => false,
            _ => null,
          },
          sourceEpoch: row['source_epoch'] as int?,
          mappedTimeUs: row['mapped_time_us'] as int?,
          statusFlags: row['status_flags'] as int?,
          positionMetres: row['position_m'] as double?,
          opticalRaw: row['optical_raw'] as int?,
          opticalMinimum: row['optical_min'] as int?,
          opticalMaximum: row['optical_max'] as int?,
          hallPasses: row['hall_passes'] as int?,
          flywheelRevolutions: row['flywheel_revolutions'] as int?,
          strokeCounter: row['stroke_counter'] as int?,
          batteryMillivolts: row['battery_mv'] as int?,
          missedSamples: row['missed_samples'] as int?,
          adcErrors: row['adc_errors'] as int?,
          angularVelocityRadPerSecond: row['angular_velocity_rad_s'] as double?,
          strokeEventTimeUs: row['stroke_event_time_us'] as int?,
          strokeSource: row['stroke_source'] as String?,
          firmwareStrokeEventsAvailable:
              (row['stroke_events_supported'] as int) == 1,
          payload: payload == null
              ? null
              : Uint8List.fromList(payload as List<int>),
        );
      });

  /// Every original BLE notification, including notifications that could not
  /// be decoded into [RawSensorSample].
  List<RawSensorFrame> loadRawFrames(String sessionId) =>
      iterateRawFrames(sessionId).toList(growable: false);

  Iterable<RawSensorFrame> iterateRawFrames(String sessionId) => database
      .readPages(
        '''SELECT sensor_id, side, received_at_monotonic_us, payload,
                  decoder_version, decode_valid, failure_code,
                  decoded_device_time_us, decoded_sequence
             FROM raw_sensor_frame
            WHERE session_id = ? ORDER BY ordinal''',
        [sessionId],
      )
      .map(
        (row) => RawSensorFrame(
          sensorId: row['sensor_id'] as String,
          side: SensorSide.values.byName(row['side'] as String),
          receivedAtUs: row['received_at_monotonic_us'] as int,
          bytes: row['payload'] as List<int>,
          decoderVersion: row['decoder_version'] as String,
          valid: (row['decode_valid'] as int) == 1,
          failureCode: row['failure_code'] as String?,
          deviceTimeUs: row['decoded_device_time_us'] as int?,
          sequence: row['decoded_sequence'] as int?,
        ),
      );

  /// The machine power model V1 strokes (schema 0x1205) of a session, with the
  /// pipeline status frames (0x1302) that name each sensor's last stroke.
  List<RawDeviceFrame> loadMachineStrokeFrames(String sessionId) => database.raw
      .select(
        '''SELECT device_id, received_at_monotonic_us, payload,
                  decoder_version, source_channel, decode_valid, failure_code,
                  decoded_device_time_us, decoded_sequence, stream_epoch,
                  schema_id, envelope_flags
             FROM raw_device_frame
            WHERE session_id = ? AND schema_id IN (4613, 4866)
            ORDER BY ordinal''',
        [sessionId],
      )
      .map(
        (row) => RawDeviceFrame(
          deviceId: row['device_id'] as String,
          receivedAtUs: row['received_at_monotonic_us'] as int,
          bytes: row['payload'] as List<int>,
          decoderVersion: row['decoder_version'] as String,
          channel: row['source_channel'] as String,
          valid: (row['decode_valid'] as int) == 1,
          failureCode: row['failure_code'] as String?,
          deviceTimeUs: row['decoded_device_time_us'] as int?,
          sequence: row['decoded_sequence'] as int?,
          streamEpoch: row['stream_epoch'] as int?,
          schemaId: row['schema_id'] as int?,
          flags: row['envelope_flags'] as int?,
        ),
      )
      .toList(growable: false);

  /// Complete PRIMARY notifications in original arrival order.
  List<RawDeviceFrame> loadRawDeviceFrames(String sessionId) =>
      iterateRawDeviceFrames(sessionId).toList(growable: false);

  Iterable<RawDeviceFrame> iterateRawDeviceFrames(
    String sessionId, {
    bool measurementMetadataOnly = false,
  }) => database
      .readPages(
        '''SELECT device_id, received_at_monotonic_us, ${measurementMetadataOnly ? "X''" : 'payload'} AS payload,
                  decoder_version, source_channel, decode_valid, failure_code,
                  decoded_device_time_us, decoded_sequence, stream_epoch,
                  schema_id, envelope_flags
             FROM raw_device_frame
            WHERE session_id = ? ${measurementMetadataOnly ? "AND source_channel = 'measurement'" : ''} ORDER BY ordinal''',
        [sessionId],
      )
      .map(
        (row) => RawDeviceFrame(
          deviceId: row['device_id'] as String,
          receivedAtUs: row['received_at_monotonic_us'] as int,
          bytes: row['payload'] as List<int>,
          decoderVersion: row['decoder_version'] as String,
          channel: row['source_channel'] as String,
          valid: (row['decode_valid'] as int) == 1,
          failureCode: row['failure_code'] as String?,
          deviceTimeUs: row['decoded_device_time_us'] as int?,
          sequence: row['decoded_sequence'] as int?,
          streamEpoch: row['stream_epoch'] as int?,
          schemaId: row['schema_id'] as int?,
          flags: row['envelope_flags'] as int?,
        ),
      );

  SessionIntegritySummary integrityOf(String sessionId) {
    final deviceFrames = iterateRawDeviceFrames(
      sessionId,
      measurementMetadataOnly: true,
    ).toList(growable: false);
    if (deviceFrames.isNotEmpty) {
      return _integrityOfDeviceFrames(sessionId, deviceFrames);
    }
    final frames = loadRawFrames(sessionId);
    final counters = <String, _SequenceIntegrity>{};
    for (final frame in frames) {
      if (!frame.valid || frame.sequence == null) continue;
      counters
          .putIfAbsent(frame.sensorId, _SequenceIntegrity.new)
          .add(frame.sequence!);
    }
    final spanUs = frames.length < 2
        ? 0
        : frames.last.receivedAtUs - frames.first.receivedAtUs;
    return SessionIntegritySummary(
      frameCount: frames.length,
      decodedSampleCount:
          database.raw.select(
                'SELECT COUNT(*) AS n FROM raw_sensor_sample WHERE session_id = ?',
                [sessionId],
              ).single['n']
              as int,
      invalidFrameCount: frames.where((frame) => !frame.valid).length,
      duplicateFrameCount: counters.values.fold(
        0,
        (sum, c) => sum + c.duplicates,
      ),
      missingSequenceCount: counters.values.fold(
        0,
        (sum, c) => sum + c.missing,
      ),
      outOfOrderFrameCount: counters.values.fold(
        0,
        (sum, c) => sum + c.outOfOrder,
      ),
      observedSampleRateHz: spanUs <= 0
          ? null
          : (frames.length - 1) * Duration.microsecondsPerSecond / spanUs,
      lastFrameAtMonotonicUs: frames.isEmpty ? null : frames.last.receivedAtUs,
    );
  }

  /// Quality facts used by the inspector and persisted when a session closes.
  SessionDataQuality dataQualityOf(String sessionId) {
    final hasDeviceFrames = database.raw.select(
      'SELECT 1 FROM raw_device_frame WHERE session_id = ? LIMIT 1',
      [sessionId],
    ).isNotEmpty;
    final table = hasDeviceFrames ? 'raw_device_frame' : 'raw_sensor_frame';
    var longestGapUs = 0;
    int? previousArrival;
    for (final row in database.readPages(
      'SELECT received_at_monotonic_us FROM $table WHERE session_id = ? ORDER BY ordinal',
      [sessionId],
    )) {
      final arrival = row['received_at_monotonic_us'] as int;
      final gap = previousArrival == null ? 0 : arrival - previousArrival;
      if (gap > longestGapUs) longestGapUs = gap;
      previousArrival = arrival;
    }
    final integrity = integrityOf(sessionId);
    final received = integrity.frameCount - integrity.invalidFrameCount;
    final expected = received + integrity.missingSequenceCount;
    final byteRow = database.raw.select(
      hasDeviceFrames
          ? '''SELECT COALESCE(SUM(length(payload)), 0) AS bytes
                 FROM raw_device_frame WHERE session_id = ?'''
          : '''SELECT COALESCE(SUM(length(payload)), 0) AS bytes
                 FROM raw_sensor_frame WHERE session_id = ?''',
      [sessionId],
    ).single;
    final interruptions =
        database.raw
                .select(
                  '''SELECT COUNT(*) AS n FROM session_event
          WHERE session_id = ? AND kind IN
            ('device_temporarilyDisconnected', 'device_disconnected')''',
                  [sessionId],
                )
                .single['n']
            as int;
    final failures = database.raw
        .select(
          """SELECT COALESCE(MAX(CASE WHEN json_valid(detail)
           THEN json_extract(detail, '\$.failed_write_count') ELSE 0 END), 0) AS n
         FROM session_event WHERE session_id = ? AND kind = 'recording_failed'""",
          [sessionId],
        )
        .single['n'];
    return SessionDataQuality(
      recordingFailureCount: failures is int ? failures : 0,
      receivedPackets: received,
      expectedPackets: expected,
      lostPackets: integrity.missingSequenceCount,
      invalidPackets: integrity.invalidFrameCount,
      duplicatePackets: integrity.duplicateFrameCount,
      outOfOrderPackets: integrity.outOfOrderFrameCount,
      bleInterruptions: interruptions,
      longestGapUs: longestGapUs,
      byteCount: byteRow['bytes'] as int,
      observedRateHz: integrity.observedSampleRateHz,
    );
  }

  SessionInspection inspectSession(String sessionId) {
    final rows = database.raw.select(
      '''SELECT id, athlete_id, device_id, started_at_utc_us, ended_at_utc_us,
                recording_state, algorithm_version, processing_config_json,
                data_format_version, app_version, sensor_snapshot_json,
                calibration_snapshot_json, battery_start_json,
                battery_end_json
           FROM xc_session WHERE id = ?''',
      [sessionId],
    );
    if (rows.isEmpty) throw StateError('Unknown session $sessionId');
    final row = rows.single;
    final samples = loadRawSamples(sessionId);
    final bySide = <SensorSide, List<RawSensorSample>>{
      for (final side in SensorSide.values)
        side: [
          for (final sample in samples)
            if (sample.side == side) sample,
        ],
    };
    final strokeCount =
        database.raw.select(
              'SELECT COUNT(*) AS n FROM stroke WHERE session_id = ?',
              [sessionId],
            ).single['n']
            as int;
    return SessionInspection(
      sessionId: sessionId,
      athleteId: row['athlete_id'] as String,
      deviceId: row['device_id'] as String?,
      startedAtUtcUs: row['started_at_utc_us'] as int,
      endedAtUtcUs: row['ended_at_utc_us'] as int?,
      recordingState: _recordingState(row['recording_state'] as String?),
      algorithmVersion: row['algorithm_version'] as String,
      dataFormatVersion: row['data_format_version'] as String,
      appVersion: row['app_version'] as String?,
      processingConfig: _jsonObject(row['processing_config_json'] as String),
      sensorSnapshot: _jsonObject(row['sensor_snapshot_json'] as String),
      calibrationSnapshot: _jsonObject(
        row['calibration_snapshot_json'] as String,
      ),
      batteryStart: _jsonObject(row['battery_start_json'] as String),
      batteryEnd: _jsonObject(row['battery_end_json'] as String),
      rawDeviceFrameCount:
          database.raw.select(
                'SELECT COUNT(*) n FROM raw_device_frame WHERE session_id = ?',
                [sessionId],
              ).single['n']
              as int,
      rawSampleCount: samples.length,
      strokeCount: strokeCount,
      sideStatistics: {
        for (final entry in bySide.entries)
          entry.key: SessionSideStatistics.fromSamples(entry.value),
      },
      quality: dataQualityOf(sessionId),
    );
  }

  static Map<String, Object?> _jsonObject(String stored) =>
      Map<String, Object?>.unmodifiable(
        (jsonDecode(stored) as Map<String, dynamic>).cast<String, Object?>(),
      );

  SessionIntegritySummary _integrityOfDeviceFrames(
    String sessionId,
    List<RawDeviceFrame> frames,
  ) {
    final counters = <int, _SequenceIntegrity>{};
    for (final frame in frames) {
      if (!frame.valid || frame.sequence == null) continue;
      counters
          .putIfAbsent(frame.streamEpoch ?? 0, _SequenceIntegrity.new)
          .add(frame.sequence!);
    }
    final spanUs = frames.length < 2
        ? 0
        : frames.last.receivedAtUs - frames.first.receivedAtUs;
    return SessionIntegritySummary(
      frameCount: frames.length,
      decodedSampleCount:
          database.raw.select(
                'SELECT COUNT(*) AS n FROM raw_sensor_sample WHERE session_id = ?',
                [sessionId],
              ).single['n']
              as int,
      invalidFrameCount: frames.where((frame) => !frame.valid).length,
      duplicateFrameCount: counters.values.fold(
        0,
        (sum, c) => sum + c.duplicates,
      ),
      missingSequenceCount: counters.values.fold(
        0,
        (sum, c) => sum + c.missing,
      ),
      outOfOrderFrameCount: counters.values.fold(
        0,
        (sum, c) => sum + c.outOfOrder,
      ),
      observedSampleRateHz: spanUs <= 0
          ? null
          : (frames.length - 1) * Duration.microsecondsPerSecond / spanUs,
      lastFrameAtMonotonicUs: frames.isEmpty ? null : frames.last.receivedAtUs,
    );
  }

  /// Sessions of one athlete, newest first. This is the entry point for the
  /// athlete record and for long-term development analysis.
  /// Schreibt das Ergebnis eines Workoutabschnitts.
  ///
  /// [stepId] bleibt null, solange die Einheit aus der Bibliothek stammt und
  /// nicht als eigene gespeichert ist — die Spalte verweist auf
  /// `workout_step`, und ein Verweis auf eine Zeile, die es nicht gibt, wäre
  /// eine Lüge mit Fremdschlüssel. Was die Auswertung braucht, steht ohnehin
  /// in [metricsJson]: Vorgabe, Ergebnis, Zugzahl.
  void appendIntervalRecord({
    required String id,
    required int ordinal,
    required int startedAtUs,
    required int endedAtUs,
    required String metricsJson,
    String? stepId,
  }) {
    final sessionId = _assertRecording();
    database.raw.execute(
      '''INSERT OR IGNORE INTO interval_record(
           id, session_id, step_id, ordinal, started_at_us, ended_at_us,
           metrics_json)
         VALUES (?, ?, ?, ?, ?, ?, ?)''',
      [id, sessionId, stepId, ordinal, startedAtUs, endedAtUs, metricsJson],
    );
  }

  /// Die Abschnitte einer Einheit, in der Reihenfolge, in der sie gefahren
  /// wurden.
  List<PersistedInterval> loadIntervals(String sessionId) => database.raw
      .select(
        '''SELECT id, ordinal, started_at_us, ended_at_us, metrics_json
             FROM interval_record
            WHERE session_id = ?
            ORDER BY ordinal''',
        [sessionId],
      )
      .map(
        (row) => PersistedInterval(
          id: row['id'] as String,
          ordinal: row['ordinal'] as int,
          startedAtUs: row['started_at_us'] as int,
          endedAtUs: row['ended_at_us'] as int?,
          metricsJson: row['metrics_json'] as String,
        ),
      )
      .toList(growable: false);

  /// Eine einzelne Sitzung, oder null.
  ///
  /// Gebraucht, sobald eine Einheit aus dem Archiv geöffnet wird: Die
  /// Zusammenfassung entsteht dann aus dieser Zeile und ihren Zügen, nicht aus
  /// dem, was der Bildschirm noch im Speicher hat.
  SessionSummary? sessionById(String sessionId) {
    final rows = database.raw.select(
      '''SELECT id, athlete_id, device_id, started_at_utc_us, ended_at_utc_us,
                algorithm_version, paused_us, recording_state,
                last_checkpoint_utc_us
           FROM xc_session WHERE id = ?''',
      [sessionId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return SessionSummary(
      id: row['id'] as String,
      athleteId: row['athlete_id'] as String,
      deviceId: row['device_id'] as String?,
      startedAtUtcUs: row['started_at_utc_us'] as int,
      endedAtUtcUs: row['ended_at_utc_us'] as int?,
      algorithmVersion: row['algorithm_version'] as String,
      pausedUs: row['paused_us'] as int? ?? 0,
      recordingState: _recordingState(row['recording_state'] as String?),
      lastCheckpointUtcUs: row['last_checkpoint_utc_us'] as int?,
    );
  }

  List<SessionSummary> sessionsOfAthlete(String athleteId) => database.raw
      .select(
        '''SELECT id, athlete_id, device_id, started_at_utc_us, ended_at_utc_us,
                  algorithm_version, paused_us, recording_state,
                  last_checkpoint_utc_us
             FROM xc_session WHERE athlete_id = ?
            ORDER BY started_at_utc_us DESC''',
        [athleteId],
      )
      .map(
        (row) => SessionSummary(
          id: row['id'] as String,
          athleteId: row['athlete_id'] as String,
          deviceId: row['device_id'] as String?,
          startedAtUtcUs: row['started_at_utc_us'] as int,
          endedAtUtcUs: row['ended_at_utc_us'] as int?,
          algorithmVersion: row['algorithm_version'] as String,
          pausedUs: row['paused_us'] as int? ?? 0,
          recordingState: _recordingState(row['recording_state'] as String?),
          lastCheckpointUtcUs: row['last_checkpoint_utc_us'] as int?,
        ),
      )
      .toList(growable: false);

  /// The newest completed/evaluable sessions that actually contain strokes.
  ///
  /// Home cards only need a handful of recaps. Filtering and limiting in SQL
  /// prevents them from loading the strokes of every historical session just
  /// to discard all but the first few afterwards.
  List<SessionSummary> recentStrokeSessionsOfAthlete(
    String athleteId, {
    required int limit,
  }) {
    if (limit <= 0) return const [];
    return database.raw
        .select(
          '''SELECT session.id, session.athlete_id, session.device_id,
                    session.started_at_utc_us, session.ended_at_utc_us,
                    session.algorithm_version, session.paused_us,
                    session.recording_state, session.last_checkpoint_utc_us
               FROM xc_session AS session
              WHERE session.athlete_id = ?
                AND EXISTS (
                  SELECT 1 FROM stroke WHERE stroke.session_id = session.id
                )
              ORDER BY session.started_at_utc_us DESC
              LIMIT ?''',
          [athleteId, limit],
        )
        .map(
          (row) => SessionSummary(
            id: row['id'] as String,
            athleteId: row['athlete_id'] as String,
            deviceId: row['device_id'] as String?,
            startedAtUtcUs: row['started_at_utc_us'] as int,
            endedAtUtcUs: row['ended_at_utc_us'] as int?,
            algorithmVersion: row['algorithm_version'] as String,
            pausedUs: row['paused_us'] as int? ?? 0,
            recordingState: _recordingState(row['recording_state'] as String?),
            lastCheckpointUtcUs: row['last_checkpoint_utc_us'] as int?,
          ),
        )
        .toList(growable: false);
  }

  List<SessionSummary> interruptedSessionsOfAthlete(String athleteId) =>
      sessionsOfAthlete(athleteId)
          .where(
            (session) =>
                session.recordingState == SessionRecordingState.interrupted,
          )
          .toList(growable: false);

  /// Marks recordings left open by an earlier process as interrupted.
  /// Nothing is ended or deleted: a later recovery can attach to the same row.
  int markOpenSessionsInterrupted({required int nowUtcUs}) {
    final rows = database.raw.select(
      '''SELECT id, organization_id, recorded_by_user_id FROM xc_session
          WHERE ended_at_utc_us IS NULL AND recording_state = 'recording' ''',
    );
    database.transaction(() {
      database.raw.execute(
        '''UPDATE session
            SET recording_state = 'interrupted', updated_at_utc_us = ?
          WHERE ended_at_utc_us IS NULL AND recording_state = 'recording' ''',
        [nowUtcUs],
      );
      for (final row in rows) {
        final organizationId = row['organization_id'] as String;
        final sessionId = row['id'] as String;
        platform.enqueueSync(
          organizationId: organizationId,
          entity: 'session',
          entityId: sessionId,
          operation: 'update',
          nowUtcUs: nowUtcUs,
        );
        platform.writeAudit(
          organizationId: organizationId,
          actorUserId: row['recorded_by_user_id'] as String?,
          action: 'session_interrupted_after_restart',
          entity: 'session',
          entityId: sessionId,
          nowUtcUs: nowUtcUs,
        );
      }
    });
    return rows.length;
  }

  /// What a recovered recording continues from: owner, start and the number
  /// of rows already stored, so continued ids never collide.
  RecoverableSession? recoverable(String sessionId) {
    final rows = database.raw.select(
      '''SELECT athlete_id, device_id, started_at_utc_us, ended_at_utc_us,
                recording_state, last_checkpoint_utc_us, movement_type,
                (SELECT COUNT(*) FROM session_event WHERE session_id = s.id)
                  AS events,
                (SELECT COUNT(*) FROM stroke WHERE session_id = s.id)
                  AS strokes,
                (SELECT COALESCE(MAX(ordinal) + 1, 0) FROM interval_record
                  WHERE session_id = s.id) AS intervals
           FROM xc_session s WHERE id = ?''',
      [sessionId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return RecoverableSession(
      sessionId: sessionId,
      athleteId: row['athlete_id'] as String,
      deviceId: row['device_id'] as String?,
      startedAtUtcUs: row['started_at_utc_us'] as int,
      endedAtUtcUs: row['ended_at_utc_us'] as int?,
      interrupted: row['recording_state'] == 'interrupted',
      lastCheckpointUtcUs: row['last_checkpoint_utc_us'] as int?,
      movementType: row['movement_type'] as String?,
      storedEvents: row['events'] as int,
      storedStrokes: row['strokes'] as int,
      nextIntervalOrdinal: row['intervals'] as int,
    );
  }

  /// Re-attaches this repository to an interrupted recording.
  ///
  /// The original athlete and device are read from the row and never replaced
  /// by the currently selected UI athlete.
  void recoverSession({
    required String sessionId,
    required int nowUtcUs,
    String? actorUserId,
  }) {
    if (_activeSessionId != null) {
      throw StateError('A session is already being recorded.');
    }
    final rows = database.raw.select(
      '''SELECT athlete_id, device_id, algorithm_version, recording_state,
                ended_at_utc_us, organization_id, recorded_by_user_id,
                battery_start_json
           FROM xc_session WHERE id = ?''',
      [sessionId],
    );
    if (rows.isEmpty) throw StateError('Unknown session $sessionId');
    final row = rows.first;
    if (row['ended_at_utc_us'] != null ||
        row['recording_state'] != 'interrupted') {
      throw StateError('Only an interrupted open session can be recovered.');
    }
    final athleteId = row['athlete_id'] as String;
    if (actorUserId != null) {
      platform.assertCanRecordFor(userId: actorUserId, athleteId: athleteId);
    }
    _activeSessionId = sessionId;
    _bindDevice(row['device_id'] as String?);
    _activeAlgorithmVersionValue = row['algorithm_version'] as String;
    _initialBatteries
      ..clear()
      ..addAll(_jsonObject(row['battery_start_json'] as String));
    final lastOrdinal =
        database.raw
                .select(
                  '''SELECT COALESCE(MAX(ordinal), -1) AS ordinal
           FROM raw_sensor_frame WHERE session_id = ?''',
                  [sessionId],
                )
                .first['ordinal']
            as int;
    _nextFrameOrdinal = lastOrdinal + 1;
    final lastDeviceOrdinal =
        database.raw
                .select(
                  '''SELECT COALESCE(MAX(ordinal), -1) AS ordinal
           FROM raw_device_frame WHERE session_id = ?''',
                  [sessionId],
                )
                .first['ordinal']
            as int;
    _nextDeviceFrameOrdinal = lastDeviceOrdinal + 1;
    database.transaction(() {
      database.raw.execute(
        '''UPDATE session SET recording_state = 'recording',
                  updated_at_utc_us = ? WHERE id = ?''',
        [nowUtcUs, sessionId],
      );
      platform.enqueueSync(
        organizationId: row['organization_id'] as String,
        entity: 'session',
        entityId: sessionId,
        operation: 'update',
        nowUtcUs: nowUtcUs,
      );
      platform.writeAudit(
        organizationId: row['organization_id'] as String,
        actorUserId: actorUserId ?? row['recorded_by_user_id'] as String?,
        action: 'session_recovered',
        entity: 'session',
        entityId: sessionId,
        nowUtcUs: nowUtcUs,
      );
    });
  }

  /// Durable boundary used by periodic and app-lifecycle checkpoints.
  void checkpoint({required int atUtcUs}) {
    final sessionId = _assertRecording();
    flush();
    database.raw.execute(
      '''UPDATE session
            SET last_checkpoint_utc_us = ?, updated_at_utc_us = ?
          WHERE id = ?''',
      [atUtcUs, atUtcUs, sessionId],
    );
  }

  /// Releases an open recorder without pretending the session completed.
  void interruptActiveSession({required int atUtcUs}) {
    final sessionId = _assertRecording();
    checkpoint(atUtcUs: atUtcUs);
    final row = database.raw.select(
      'SELECT organization_id, recorded_by_user_id FROM xc_session WHERE id = ?',
      [sessionId],
    ).single;
    database.transaction(() {
      database.raw.execute(
        "UPDATE session SET recording_state = 'interrupted' WHERE id = ?",
        [sessionId],
      );
      platform.enqueueSync(
        organizationId: row['organization_id'] as String,
        entity: 'session',
        entityId: sessionId,
        operation: 'update',
        nowUtcUs: atUtcUs,
      );
      platform.writeAudit(
        organizationId: row['organization_id'] as String,
        actorUserId: row['recorded_by_user_id'] as String?,
        action: 'session_interrupted',
        entity: 'session',
        entityId: sessionId,
        nowUtcUs: atUtcUs,
      );
    });
    _clearActiveBinding();
  }

  /// Append-only operational provenance. [detail] must describe the device or
  /// lifecycle state and must not contain athlete names or other PII.
  void recordEvent({
    required String id,
    required String kind,
    required int occurredAtUtcUs,
    int? occurredAtMonotonicUs,
    String? detail,
  }) {
    final sessionId = _assertRecording();
    database.raw.execute(
      '''INSERT INTO session_event(
           id, session_id, kind, occurred_at_utc_us,
           occurred_at_monotonic_us, detail)
         VALUES (?, ?, ?, ?, ?, ?)''',
      [id, sessionId, kind, occurredAtUtcUs, occurredAtMonotonicUs, detail],
    );
  }

  List<SessionEvent> loadEvents(String sessionId) => database.raw
      .select(
        '''SELECT id, kind, occurred_at_utc_us, occurred_at_monotonic_us,
                  detail
             FROM session_event WHERE session_id = ?
            ORDER BY occurred_at_utc_us, id''',
        [sessionId],
      )
      .map(
        (row) => SessionEvent(
          id: row['id'] as String,
          kind: row['kind'] as String,
          occurredAtUtcUs: row['occurred_at_utc_us'] as int,
          occurredAtMonotonicUs: row['occurred_at_monotonic_us'] as int?,
          detail: row['detail'] as String?,
        ),
      )
      .toList(growable: false);

  /// Schliesst die laufende Aufzeichnung ab.
  ///
  /// [pausedUs] ist die Zeit, die zwischendurch pausiert wurde. Sie gehört an
  /// die Zeile und nicht in den Arbeitsspeicher: Nur so kann die
  /// Zusammenfassung später aus dem Archiv entstehen und nicht aus dem, was
  /// gerade noch offen ist.
  void finishSession({
    required int endedAtUtcUs,
    String? notes,
    int pausedUs = 0,
    PersistedInterval? finalInterval,
    String? recordingFailure,
  }) {
    final sessionId = _assertRecording();
    final startedAtUtcUs =
        database.raw.select(
              'SELECT started_at_utc_us FROM xc_session WHERE id = ?',
              [sessionId],
            ).first['started_at_utc_us']
            as int;
    if (endedAtUtcUs < startedAtUtcUs) {
      throw ArgumentError('A session cannot end before it started.');
    }
    final durationUs = endedAtUtcUs - startedAtUtcUs;
    if (pausedUs < 0 || pausedUs > durationUs) {
      throw ArgumentError('Paused time must fit inside the session.');
    }
    flush();
    final batteryEndJson = jsonEncode(_lastBatteries(sessionId));
    database.transaction(() {
      if (recordingFailure != null) {
        recordEvent(
          id: '$sessionId-recording-failure',
          kind: 'recording_failed',
          occurredAtUtcUs: endedAtUtcUs,
          detail: recordingFailure,
        );
      }
      final qualityJson = jsonEncode(dataQualityOf(sessionId).toJson());
      // The last interval and the completed flag commit together. On failure
      // the caller can keep collecting and retry with a fresh snapshot.
      if (finalInterval != null) {
        final intervalEnd = finalInterval.endedAtUs;
        if (intervalEnd == null) {
          throw ArgumentError('The final interval needs an end time.');
        }
        appendIntervalRecord(
          id: finalInterval.id,
          ordinal: finalInterval.ordinal,
          startedAtUs: finalInterval.startedAtUs,
          endedAtUs: intervalEnd,
          metricsJson: finalInterval.metricsJson,
        );
      }
      database.raw.execute(
        '''UPDATE session
              SET ended_at_utc_us = ?, notes = ?, paused_us = ?,
                  updated_at_utc_us = ?, recording_state = ?,
                  last_checkpoint_utc_us = ?, data_quality_json = ?,
                  battery_end_json = ?
            WHERE id = ?''',
        [
          endedAtUtcUs,
          notes,
          pausedUs,
          endedAtUtcUs,
          recordingFailure == null ? 'completed' : 'interrupted',
          endedAtUtcUs,
          qualityJson,
          batteryEndJson,
          sessionId,
        ],
      );
      final row = database.raw.select(
        'SELECT organization_id, recorded_by_user_id FROM xc_session WHERE id = ?',
        [sessionId],
      ).single;
      platform.enqueueSync(
        organizationId: row['organization_id'] as String,
        entity: 'session',
        entityId: sessionId,
        operation: 'update',
        nowUtcUs: endedAtUtcUs,
      );
      platform.writeAudit(
        organizationId: row['organization_id'] as String,
        actorUserId: row['recorded_by_user_id'] as String?,
        action: 'session_finalized',
        entity: 'session',
        entityId: sessionId,
        nowUtcUs: endedAtUtcUs,
      );
    });
    _clearActiveBinding();
  }

  static List<double> _decodeRrIntervals(Object? stored) {
    if (stored == null) return const <double>[];
    try {
      final bytes = stored as List<int>;
      final decoded = jsonDecode(utf8.decode(bytes)) as List<dynamic>;
      return List<double>.unmodifiable(
        decoded.map((value) => (value as num).toDouble()),
      );
    } on Object {
      // Legacy rows stored NULL. A non-null unreadable payload is corruption,
      // not an empty RR list that callers could mistake for a real absence.
      throw const FormatException('Corrupt RR interval payload.');
    }
  }

  Map<String, Object?> _lastBatteries(String sessionId) {
    final result = <String, Object?>{};
    for (final row in database.raw.select(
      '''SELECT sensor_id, battery_percent
           FROM raw_sensor_sample
          WHERE session_id = ? AND battery_percent IS NOT NULL
          ORDER BY received_at_monotonic_us DESC''',
      [sessionId],
    )) {
      final sensorId = row['sensor_id'] as String;
      result.putIfAbsent(
        sensorId,
        () => {'percent': row['battery_percent'] as int},
      );
    }
    for (final row in database.raw.select(
      '''SELECT sensor_id, battery_mv
           FROM raw_sensor_sample
          WHERE session_id = ? AND battery_mv IS NOT NULL
          ORDER BY received_at_monotonic_us DESC''',
      [sessionId],
    )) {
      final sensorId = row['sensor_id'] as String;
      final prior = result[sensorId];
      // Rows are newest first. Voltage and percentage can arrive separately;
      // retain the first non-null value of each without replacing the other.
      if (prior is Map<String, Object?> && prior.containsKey('millivolts')) {
        continue;
      }
      result[sensorId] = {
        if (prior is Map<String, Object?>) ...prior,
        'millivolts': row['battery_mv'] as int,
      };
    }
    return result;
  }

  void _captureInitialBattery(RawSensorSample sample) {
    if (_initialBatteries.containsKey(sample.sensorId) ||
        (sample.batteryPercent == null && sample.batteryMillivolts == null)) {
      return;
    }
    _initialBatteries[sample.sensorId] = {
      if (sample.batteryPercent != null) 'percent': sample.batteryPercent,
      if (sample.batteryMillivolts != null)
        'millivolts': sample.batteryMillivolts,
    };
    database.raw.execute(
      'UPDATE session SET battery_start_json = ? WHERE id = ?',
      [jsonEncode(_initialBatteries), _activeSessionId],
    );
  }

  static String? _encodeStrokeSides(StrokeSides? sides) {
    if (sides == null) return null;
    Map<String, Object?> side(StrokeMetrics value) => {
      'side': value.side.name,
      'start_us': value.startUs,
      'end_us': value.endUs,
      'work_j': value.workJoule,
      'average_power_w': value.averagePowerWatt,
      'peak_power_w': value.peakPowerWatt,
      'peak_power_phase': value.peakPowerPhase,
      'peak_speed_m_s': value.peakSpeedMetresPerSecond,
      'peak_speed_phase': value.peakSpeedPhase,
      'stroke_length_m': value.strokeLengthMetres,
      'average_force_n': value.averageForceNewton,
      'peak_force_n': value.peakForceNewton,
      'peak_force_position': value.peakForcePosition,
      'power_phase_curve': [
        for (final point in value.powerPhaseCurve)
          {'phase': point.phase, 'power_w': point.powerWatt},
      ],
      'speed_phase_curve': [
        for (final point in value.speedPhaseCurve)
          {'phase': point.phase, 'speed_m_s': point.metresPerSecond},
      ],
      'force_distance_curve': [
        for (final point in value.forceDistanceCurve)
          {'distance_m': point.distanceMetres, 'force_n': point.forceNewton},
      ],
    };
    return jsonEncode({'left': side(sides.left), 'right': side(sides.right)});
  }

  static String? _encodeFirmwareEvents(List<FirmwareStrokeEvent> events) {
    if (events.isEmpty) return null;
    return jsonEncode([
      for (final event in events)
        {
          'side': event.side.name,
          'counter': event.counter,
          'event_time_us': event.eventTimeUs,
          'source': event.source,
          'missed_before': event.missedBefore,
        },
    ]);
  }

  static List<FirmwareStrokeEvent> _decodeFirmwareEvents(String? stored) {
    if (stored == null) return const [];
    return [
      for (final value in jsonDecode(stored) as List<dynamic>)
        FirmwareStrokeEvent(
          side: SensorSide.values.byName(
            (value as Map<String, dynamic>)['side'] as String,
          ),
          counter: value['counter'] as int,
          eventTimeUs: value['event_time_us'] as int,
          source: value['source'] as String,
          missedBefore: value['missed_before'] as int? ?? 0,
        ),
    ];
  }

  static StrokeSides? _decodeStrokeSides(String? stored) {
    if (stored == null) return null;
    final root = jsonDecode(stored) as Map<String, dynamic>;
    StrokeMetrics side(String name) {
      final value = root[name] as Map<String, dynamic>;
      return StrokeMetrics(
        side: StrokeSide.values.byName(value['side'] as String),
        startUs: value['start_us'] as int,
        endUs: value['end_us'] as int,
        workJoule: (value['work_j'] as num).toDouble(),
        averagePowerWatt: (value['average_power_w'] as num).toDouble(),
        peakPowerWatt: (value['peak_power_w'] as num).toDouble(),
        peakPowerPhase: (value['peak_power_phase'] as num).toDouble(),
        peakSpeedMetresPerSecond: (value['peak_speed_m_s'] as num?)?.toDouble(),
        peakSpeedPhase: (value['peak_speed_phase'] as num?)?.toDouble(),
        strokeLengthMetres: (value['stroke_length_m'] as num?)?.toDouble(),
        averageForceNewton: (value['average_force_n'] as num?)?.toDouble(),
        peakForceNewton: (value['peak_force_n'] as num?)?.toDouble(),
        peakForcePosition: (value['peak_force_position'] as num?)?.toDouble(),
        powerPhaseCurve: [
          for (final point
              in value['power_phase_curve'] as List<dynamic>? ?? const [])
            PowerPhaseSample(
              phase: ((point as Map<String, dynamic>)['phase'] as num)
                  .toDouble(),
              powerWatt: (point['power_w'] as num).toDouble(),
            ),
        ],
        speedPhaseCurve: [
          for (final point
              in value['speed_phase_curve'] as List<dynamic>? ?? const [])
            SpeedPhaseSample(
              phase: ((point as Map<String, dynamic>)['phase'] as num)
                  .toDouble(),
              metresPerSecond: (point['speed_m_s'] as num).toDouble(),
            ),
        ],
        forceDistanceCurve: [
          for (final point
              in value['force_distance_curve'] as List<dynamic>? ?? const [])
            ForceDistanceSample(
              distanceMetres:
                  ((point as Map<String, dynamic>)['distance_m'] as num)
                      .toDouble(),
              forceNewton: (point['force_n'] as num).toDouble(),
            ),
        ],
      );
    }

    return StrokeSides(left: side('left'), right: side('right'));
  }

  void _bindDevice(String? deviceId) {
    _activeDeviceId = deviceId;
    if (deviceId == null) {
      _activeSensorIds = const <String>{};
      return;
    }
    _activeSensorIds = database.raw
        .select('SELECT id FROM sensor WHERE device_id = ?', [deviceId])
        .map((row) => row['id'] as String)
        .toSet();
  }

  ({String sensorJson, String calibrationJson, String batteryJson})
  _sessionSnapshots(SessionStart session) {
    if (session.deviceId == null) {
      return (
        sensorJson: session.sensorSnapshotJson ?? '{}',
        calibrationJson: session.calibrationSnapshotJson ?? '{}',
        batteryJson: session.batteryStartJson ?? '{}',
      );
    }
    final device = database.raw
        .select(
          '''SELECT id, model, hardware_version, firmware_version, serial_number
           FROM device WHERE id = ?''',
          [session.deviceId],
        )
        .single;
    final sensors = database.raw.select(
      '''SELECT id, side, service_uuid, measurement_uuid
           FROM sensor WHERE device_id = ? ORDER BY side, id''',
      [session.deviceId],
    );
    final sensorSnapshot = <String, Object?>{
      'device_id': device['id'],
      'model': device['model'],
      'hardware_version': device['hardware_version'],
      'firmware_version': device['firmware_version'],
      'serial_number': device['serial_number'],
      'sensors': [
        for (final sensor in sensors)
          {
            'sensor_id': sensor['id'],
            'side': sensor['side'],
            'service_uuid': sensor['service_uuid'],
            'measurement_uuid': sensor['measurement_uuid'],
          },
      ],
    };
    final calibrations = <String, Object?>{};
    for (final sensor in sensors) {
      final rows = database.raw.select(
        '''SELECT id, calibration_type, parameters_json, protocol_version,
                  effective_from_utc_us, valid_until_utc_us
             FROM calibration
            WHERE sensor_id = ? AND effective_from_utc_us <= ?
              AND (valid_until_utc_us IS NULL OR valid_until_utc_us > ?)
              AND valid = 1
            ORDER BY effective_from_utc_us DESC, created_at_utc_us DESC''',
        [sensor['id'], session.startedAtUtcUs, session.startedAtUtcUs],
      );
      calibrations[sensor['id'] as String] = [
        for (final row in rows)
          {
            'calibration_id': row['id'],
            'type': row['calibration_type'],
            'parameters': jsonDecode(row['parameters_json'] as String),
            'protocol_version': row['protocol_version'],
            'effective_from_utc_us': row['effective_from_utc_us'],
            'valid_until_utc_us': row['valid_until_utc_us'],
          },
      ];
    }
    return (
      sensorJson: session.sensorSnapshotJson ?? jsonEncode(sensorSnapshot),
      calibrationJson:
          session.calibrationSnapshotJson ?? jsonEncode(calibrations),
      batteryJson: session.batteryStartJson ?? '{}',
    );
  }

  void _assertActiveSensor(String sensorId) {
    if (_activeDeviceId == null || !_activeSensorIds.contains(sensorId)) {
      throw PlatformAccessException(
        'Sensor $sensorId does not belong to the active session device.',
      );
    }
  }

  static void _validateRaw(RawSensorSample sample) {
    if (sample.deviceTimeUs < 0 ||
        sample.receivedAtUs < 0 ||
        sample.sequence < 0 ||
        !sample.forceNewton.isFinite ||
        !sample.velocityMetresPerSecond.isFinite ||
        !sample.powerWatt.isFinite ||
        (sample.batteryPercent != null &&
            (sample.batteryPercent! < 0 || sample.batteryPercent! > 100))) {
      throw ArgumentError('A raw sensor sample contains invalid data.');
    }
  }

  static SessionRecordingState _recordingState(String? stored) =>
      switch (stored) {
        'recording' => SessionRecordingState.recording,
        'completed' => SessionRecordingState.completed,
        _ => SessionRecordingState.interrupted,
      };

  void _clearActiveBinding() {
    _activeSessionId = null;
    _activeDeviceId = null;
    _activeSensorIds = const <String>{};
    _activeAlgorithmVersionValue = null;
    _nextFrameOrdinal = 0;
    _nextDeviceFrameOrdinal = 0;
    _initialBatteries.clear();
  }

  String _deviceOrganization(String deviceId) {
    final rows = database.raw.select(
      'SELECT organization_id FROM device WHERE id = ?',
      [deviceId],
    );
    if (rows.isEmpty) throw StateError('Unknown device $deviceId');
    return rows.first['organization_id'] as String;
  }

  String _assertRecording() {
    final sessionId = _activeSessionId;
    if (sessionId == null) {
      throw StateError('Raw samples require an active session.');
    }
    return sessionId;
  }
}

class SessionEvent {
  const SessionEvent({
    required this.id,
    required this.kind,
    required this.occurredAtUtcUs,
    this.occurredAtMonotonicUs,
    this.detail,
  });

  final String id;
  final String kind;
  final int occurredAtUtcUs;
  final int? occurredAtMonotonicUs;
  final String? detail;
}

class SessionIntegritySummary {
  const SessionIntegritySummary({
    required this.frameCount,
    required this.decodedSampleCount,
    required this.invalidFrameCount,
    required this.duplicateFrameCount,
    required this.missingSequenceCount,
    required this.outOfOrderFrameCount,
    required this.observedSampleRateHz,
    required this.lastFrameAtMonotonicUs,
  });

  final int frameCount;
  final int decodedSampleCount;
  final int invalidFrameCount;
  final int duplicateFrameCount;
  final int missingSequenceCount;
  final int outOfOrderFrameCount;
  final double? observedSampleRateHz;
  final int? lastFrameAtMonotonicUs;

  bool get hasIntegrityWarnings =>
      invalidFrameCount != 0 ||
      duplicateFrameCount != 0 ||
      missingSequenceCount != 0 ||
      outOfOrderFrameCount != 0;
}

class SessionDataQuality {
  const SessionDataQuality({
    required this.receivedPackets,
    required this.expectedPackets,
    required this.lostPackets,
    required this.invalidPackets,
    required this.duplicatePackets,
    required this.outOfOrderPackets,
    required this.bleInterruptions,
    required this.longestGapUs,
    required this.byteCount,
    required this.observedRateHz,
    this.recordingFailureCount = 0,
  });

  final int recordingFailureCount;
  final int receivedPackets;
  final int expectedPackets;
  final int lostPackets;
  final int invalidPackets;
  final int duplicatePackets;
  final int outOfOrderPackets;
  final int bleInterruptions;
  final int longestGapUs;
  final int byteCount;
  final double? observedRateHz;

  double get packetLossPercent =>
      expectedPackets == 0 ? 0 : 100 * lostPackets / expectedPackets;

  Map<String, Object?> toJson() => {
    'recording_failure_count': recordingFailureCount,
    'received_packets': receivedPackets,
    'expected_packets': expectedPackets,
    'lost_packets': lostPackets,
    'packet_loss_percent': packetLossPercent,
    'invalid_packets': invalidPackets,
    'duplicate_packets': duplicatePackets,
    'out_of_order_packets': outOfOrderPackets,
    'ble_interruptions': bleInterruptions,
    'longest_gap_us': longestGapUs,
    'byte_count': byteCount,
    'observed_rate_hz': observedRateHz,
  };
}

class SessionSideStatistics {
  const SessionSideStatistics({
    required this.sampleCount,
    this.minForceNewton,
    this.maxForceNewton,
    this.minVelocityMetresPerSecond,
    this.maxVelocityMetresPerSecond,
    this.minPowerWatt,
    this.maxPowerWatt,
    this.minOpticalRaw,
    this.maxOpticalRaw,
    this.hallEventCount,
    this.batteryMillivolts,
    this.missedSamples,
    this.adcErrors,
  });

  factory SessionSideStatistics.fromSamples(List<RawSensorSample> samples) {
    if (samples.isEmpty) return const SessionSideStatistics(sampleCount: 0);
    double minimum(double Function(RawSensorSample value) pick) =>
        samples.map(pick).reduce((a, b) => a < b ? a : b);
    double maximum(double Function(RawSensorSample value) pick) =>
        samples.map(pick).reduce((a, b) => a > b ? a : b);
    return SessionSideStatistics(
      sampleCount: samples.length,
      minForceNewton: minimum((value) => value.forceNewton),
      maxForceNewton: maximum((value) => value.forceNewton),
      minVelocityMetresPerSecond: minimum(
        (value) => value.velocityMetresPerSecond,
      ),
      maxVelocityMetresPerSecond: maximum(
        (value) => value.velocityMetresPerSecond,
      ),
      minPowerWatt: minimum((value) => value.powerWatt),
      maxPowerWatt: maximum((value) => value.powerWatt),
      minOpticalRaw: _minimumInt(samples.map((value) => value.opticalRaw)),
      maxOpticalRaw: _maximumInt(samples.map((value) => value.opticalRaw)),
      hallEventCount: _counterDelta(samples.map((value) => value.hallPasses)),
      batteryMillivolts: samples
          .map((value) => value.batteryMillivolts)
          .whereType<int>()
          .lastOrNull,
      missedSamples: samples
          .map((value) => value.missedSamples)
          .whereType<int>()
          .lastOrNull,
      adcErrors: samples
          .map((value) => value.adcErrors)
          .whereType<int>()
          .lastOrNull,
    );
  }

  static int? _minimumInt(Iterable<int?> values) {
    final present = values.whereType<int>();
    return present.isEmpty ? null : present.reduce((a, b) => a < b ? a : b);
  }

  static int? _maximumInt(Iterable<int?> values) {
    final present = values.whereType<int>();
    return present.isEmpty ? null : present.reduce((a, b) => a > b ? a : b);
  }

  static int? _counterDelta(Iterable<int?> values) {
    final present = values.whereType<int>().toList();
    if (present.isEmpty) return null;
    return (present.last - present.first) & 0xffffffff;
  }

  final int sampleCount;
  final double? minForceNewton;
  final double? maxForceNewton;
  final double? minVelocityMetresPerSecond;
  final double? maxVelocityMetresPerSecond;
  final double? minPowerWatt;
  final double? maxPowerWatt;
  final int? minOpticalRaw;
  final int? maxOpticalRaw;
  final int? hallEventCount;
  final int? batteryMillivolts;
  final int? missedSamples;
  final int? adcErrors;
}

class SessionInspection {
  const SessionInspection({
    required this.sessionId,
    required this.athleteId,
    required this.deviceId,
    required this.startedAtUtcUs,
    required this.endedAtUtcUs,
    required this.recordingState,
    required this.algorithmVersion,
    required this.dataFormatVersion,
    required this.appVersion,
    required this.processingConfig,
    required this.sensorSnapshot,
    required this.calibrationSnapshot,
    required this.batteryStart,
    required this.batteryEnd,
    required this.rawDeviceFrameCount,
    required this.rawSampleCount,
    required this.strokeCount,
    required this.sideStatistics,
    required this.quality,
  });

  final String sessionId;
  final String athleteId;
  final String? deviceId;
  final int startedAtUtcUs;
  final int? endedAtUtcUs;
  final SessionRecordingState recordingState;
  final String algorithmVersion;
  final String dataFormatVersion;
  final String? appVersion;
  final Map<String, Object?> processingConfig;
  final Map<String, Object?> sensorSnapshot;
  final Map<String, Object?> calibrationSnapshot;
  final Map<String, Object?> batteryStart;
  final Map<String, Object?> batteryEnd;
  final int rawDeviceFrameCount;
  final int rawSampleCount;
  final int strokeCount;
  final Map<SensorSide, SessionSideStatistics> sideStatistics;
  final SessionDataQuality quality;

  Duration get duration => Duration(
    microseconds:
        (endedAtUtcUs ?? startedAtUtcUs).clamp(startedAtUtcUs, 1 << 62) -
        startedAtUtcUs,
  );
}

/// Ein gespeicherter Abschnitt, so wie er in der Datenbank steht.
class PersistedInterval {
  const PersistedInterval({
    required this.id,
    required this.ordinal,
    required this.startedAtUs,
    required this.metricsJson,
    this.endedAtUs,
  });

  final String id;
  final int ordinal;
  final int startedAtUs;
  final int? endedAtUs;

  /// Vorgabe und Ergebnis dieses Abschnitts.
  final String metricsJson;
}

class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.startedAtUtcUs,
    required this.algorithmVersion,
    this.athleteId,
    this.deviceId,
    this.endedAtUtcUs,
    this.pausedUs = 0,
    this.recordingState = SessionRecordingState.completed,
    this.lastCheckpointUtcUs,
  });

  final String id;
  final String? athleteId;
  final String? deviceId;
  final int startedAtUtcUs;
  final int? endedAtUtcUs;
  final String algorithmVersion;
  final SessionRecordingState recordingState;
  final int? lastCheckpointUtcUs;

  /// Wie viel der Gesamtzeit Pause war.
  final int pausedUs;

  /// Gesamtdauer von Beginn bis Ende.
  Duration get wallTime => endedAtUtcUs == null
      ? Duration.zero
      : Duration(microseconds: endedAtUtcUs! - startedAtUtcUs);

  /// Die Zeit, in der wirklich trainiert wurde.
  Duration get activeTime => wallTime - Duration(microseconds: pausedUs);
}

enum SessionRecordingState { recording, interrupted, completed }

class RecoverableSession {
  const RecoverableSession({
    required this.sessionId,
    required this.athleteId,
    required this.startedAtUtcUs,
    required this.interrupted,
    required this.storedEvents,
    required this.storedStrokes,
    required this.nextIntervalOrdinal,
    this.deviceId,
    this.endedAtUtcUs,
    this.lastCheckpointUtcUs,
    this.movementType,
  });

  final String sessionId;
  final String athleteId;
  final String? deviceId;
  final int startedAtUtcUs;
  final int? endedAtUtcUs;

  /// Open, but no longer attached to a recorder.
  final bool interrupted;
  final int? lastCheckpointUtcUs;
  final String? movementType;
  final int storedEvents;
  final int storedStrokes;
  final int nextIntervalOrdinal;

  bool get canResume => endedAtUtcUs == null && interrupted;
}

// Sequence numbers are modulo 2^32. Keep a high-water mark so a late or
// duplicate packet cannot create another gap. Missing counts are the holes
// still unfilled at inspection time, not the sum of transient arrival gaps.
// As with the wire protocol, jumps of >= 2^31 are treated as backwards.
class _SequenceIntegrity {
  final Set<int> _seen = {};
  int? _minimum;
  int? _maximum;
  int duplicates = 0;
  int outOfOrder = 0;
  void add(int sequence) {
    final maximum = _maximum;
    final delta = maximum == null ? 0 : (sequence - maximum) & 0xffffffff;
    final unwrapped = maximum == null
        ? sequence
        : maximum + (delta >= 0x80000000 ? delta - 0x100000000 : delta);
    if (!_seen.add(unwrapped)) {
      duplicates++;
      return;
    }
    if (maximum != null && unwrapped < maximum) outOfOrder++;
    if (_minimum == null || unwrapped < _minimum!) _minimum = unwrapped;
    if (maximum == null || unwrapped > maximum) _maximum = unwrapped;
  }

  int get missing =>
      _maximum == null ? 0 : _maximum! - _minimum! + 1 - _seen.length;
}
