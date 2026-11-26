import 'dart:convert';

import '../core/models.dart';
import '../core/stroke_metrics.dart';
import '../database/session_repository.dart';
import '../core/raw_device_frame.dart';

class SessionExport {
  /// Lossless, versioned interchange representation for development sessions.
  /// Payloads are hexadecimal so the JSON stays portable without changing a
  /// single byte of the BLE notification.
  static String completeSessionJson({
    required SessionInspection inspection,
    required Iterable<RawDeviceFrame> deviceFrames,
    required Iterable<RawSensorFrame> sensorFrames,
    required Iterable<RawSensorSample> samples,
    required Iterable<Stroke> strokes,
    required Iterable<SessionEvent> events,
    Iterable<HeartRateSample> heartRates = const [],
    Iterable<PersistedInterval> intervals = const [],
    Iterable<Map<String, Object?>> derivedSamples = const [],
    Map<String, Object?> storedSession = const {},
  }) => completeSessionChunks(
    inspection: inspection,
    deviceFrames: deviceFrames,
    sensorFrames: sensorFrames,
    samples: samples,
    strokes: strokes,
    events: events,
    heartRates: heartRates,
    intervals: intervals,
    derivedSamples: derivedSamples,
    storedSession: storedSession,
  ).join();

  static Iterable<String> completeSessionChunks({
    required SessionInspection inspection,
    required Iterable<RawDeviceFrame> deviceFrames,
    required Iterable<RawSensorFrame> sensorFrames,
    required Iterable<RawSensorSample> samples,
    required Iterable<Stroke> strokes,
    required Iterable<SessionEvent> events,
    Iterable<HeartRateSample> heartRates = const [],
    Iterable<PersistedInterval> intervals = const [],
    Iterable<Map<String, Object?>> derivedSamples = const [],
    Map<String, Object?> storedSession = const {},
  }) sync* {
    final sections = <String, Object?>{
      'export_format': 'giulia.raw-session.v2',
      'session': {
        'session_id': inspection.sessionId,
        'athlete_id': inspection.athleteId,
        'device_id': inspection.deviceId,
        'started_at_utc_us': inspection.startedAtUtcUs,
        'ended_at_utc_us': inspection.endedAtUtcUs,
        'recording_state': inspection.recordingState.name,
        'algorithm_version': inspection.algorithmVersion,
        'data_format_version': inspection.dataFormatVersion,
        'app_version': inspection.appVersion,
        'processing_config': inspection.processingConfig,
        'sensor_snapshot': inspection.sensorSnapshot,
        'calibration_snapshot': inspection.calibrationSnapshot,
        'battery_start': inspection.batteryStart,
        'battery_end': inspection.batteryEnd,
        'data_quality': inspection.quality.toJson(),
      },
      'stored_session': storedSession,
      'heart_rate_samples': heartRates.map(
        (sample) => {
          'recorded_at_utc_us': sample.recordedAtUs,
          'bpm': sample.bpm,
          'rr_intervals_ms': sample.rrIntervalsMs,
          'contact_detected': sample.contactDetected,
        },
      ),
      'intervals': intervals.map(
        (interval) => {
          'id': interval.id,
          'ordinal': interval.ordinal,
          'started_at_us': interval.startedAtUs,
          'ended_at_us': interval.endedAtUs,
          'metrics_json': interval.metricsJson,
        },
      ),
      'derived_samples': derivedSamples,
      'raw_device_frames': deviceFrames.map(_deviceFrameJson),
      'raw_sensor_frames': sensorFrames.map(_sensorFrameJson),
      'raw_samples': samples.map(_rawSampleJson),
      'strokes': strokes.map(_strokeJson),
      'events': events.map(
        (event) => {
          'id': event.id,
          'kind': event.kind,
          'occurred_at_utc_us': event.occurredAtUtcUs,
          'occurred_at_monotonic_us': event.occurredAtMonotonicUs,
          'detail': event.detail,
        },
      ),
    };
    yield '{';
    var firstSection = true;
    for (final entry in sections.entries) {
      if (!firstSection) yield ',';
      firstSection = false;
      yield '${jsonEncode(entry.key)}:';
      final value = entry.value;
      if (value is Iterable) {
        yield '[';
        var first = true;
        for (final row in value) {
          if (!first) yield ',';
          first = false;
          yield jsonEncode(row);
        }
        yield ']';
      } else {
        yield jsonEncode(value);
      }
    }
    yield '}';
  }

  static String strokesCsv(Iterable<Stroke> strokes) {
    final buffer = StringBuffer(
      'start_us,end_us,recovery_us,work_j,impulse_ns,mean_power_w,peak_power_w,peak_force_n,left_work_j,right_work_j,quality,technique\n',
    );
    for (final stroke in strokes) {
      buffer.writeln(
        [
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
          stroke.technique.name,
        ].join(','),
      );
    }
    return buffer.toString();
  }

  static String rawSamplesJson(Iterable<RawSensorSample> samples) =>
      const JsonEncoder.withIndent(
        '  ',
      ).convert(samples.map(_rawSampleJson).toList());

  static String rawSamplesCsv(Iterable<RawSensorSample> samples) {
    final buffer = StringBuffer(
      'sensor_id,side,device_time_us,received_at_monotonic_us,sequence,'
      'force_n,velocity_m_s,power_w,battery_percent,packet_valid,pulling,'
      'source_epoch,mapped_time_us,status_flags,position_m,optical_raw,'
      'optical_min,optical_max,hall_passes,flywheel_revolutions,'
      'stroke_counter,battery_mv,missed_samples,adc_errors,'
      'angular_velocity_rad_s,stroke_event_time_us,stroke_source,'
      'stroke_events_supported,raw_payload_hex\n',
    );
    for (final sample in samples) {
      buffer.writeln(
        [
          sample.sensorId,
          sample.side.name,
          sample.deviceTimeUs,
          sample.receivedAtUs,
          sample.sequence,
          sample.forceNewton,
          sample.velocityMetresPerSecond,
          sample.powerWatt,
          sample.batteryPercent ?? '',
          sample.packetValid ? 1 : 0,
          sample.pulling == null ? '' : (sample.pulling! ? 1 : 0),
          sample.sourceEpoch ?? '',
          sample.mappedTimeUs ?? '',
          sample.statusFlags ?? '',
          sample.positionMetres ?? '',
          sample.opticalRaw ?? '',
          sample.opticalMinimum ?? '',
          sample.opticalMaximum ?? '',
          sample.hallPasses ?? '',
          sample.flywheelRevolutions ?? '',
          sample.strokeCounter ?? '',
          sample.batteryMillivolts ?? '',
          sample.missedSamples ?? '',
          sample.adcErrors ?? '',
          sample.angularVelocityRadPerSecond ?? '',
          sample.strokeEventTimeUs ?? '',
          sample.strokeSource ?? '',
          sample.firmwareStrokeEventsAvailable ? 1 : 0,
          sample.payload == null ? '' : _hex(sample.payload!),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  static String rawFramesJson(Iterable<RawSensorFrame> frames) =>
      const JsonEncoder.withIndent(
        '  ',
      ).convert(frames.map(_sensorFrameJson).toList());

  static Map<String, Object?> _rawSampleJson(RawSensorSample sample) => {
    'sensor_id': sample.sensorId,
    'side': sample.side.name,
    'device_time_us': sample.deviceTimeUs,
    'received_at_monotonic_us': sample.receivedAtUs,
    'sequence': sample.sequence,
    'force_n': sample.forceNewton,
    'velocity_m_s': sample.velocityMetresPerSecond,
    'power_w': sample.powerWatt,
    'battery_percent': sample.batteryPercent,
    'packet_valid': sample.packetValid,
    'pulling': sample.pulling,
    'source_epoch': sample.sourceEpoch,
    'mapped_time_us': sample.mappedTimeUs,
    'status_flags': sample.statusFlags,
    'position_m': sample.positionMetres,
    'optical_raw': sample.opticalRaw,
    'optical_min': sample.opticalMinimum,
    'optical_max': sample.opticalMaximum,
    'hall_passes': sample.hallPasses,
    'flywheel_revolutions': sample.flywheelRevolutions,
    'stroke_counter': sample.strokeCounter,
    'battery_mv': sample.batteryMillivolts,
    'missed_samples': sample.missedSamples,
    'adc_errors': sample.adcErrors,
    'angular_velocity_rad_s': sample.angularVelocityRadPerSecond,
    'stroke_event_time_us': sample.strokeEventTimeUs,
    'stroke_source': sample.strokeSource,
    'stroke_events_supported': sample.firmwareStrokeEventsAvailable,
    'raw_payload_hex': sample.payload == null ? null : _hex(sample.payload!),
  };

  static Map<String, Object?> _sensorFrameJson(RawSensorFrame frame) => {
    'sensor_id': frame.sensorId,
    'side': frame.side.name,
    'received_at_monotonic_us': frame.receivedAtUs,
    'decoder_version': frame.decoderVersion,
    'decode_valid': frame.valid,
    'failure_code': frame.failureCode,
    'decoded_device_time_us': frame.deviceTimeUs,
    'decoded_sequence': frame.sequence,
    'raw_payload_hex': _hex(frame.bytes),
  };

  static Map<String, Object?> _deviceFrameJson(RawDeviceFrame frame) => {
    'device_id': frame.deviceId,
    'received_at_monotonic_us': frame.receivedAtUs,
    'decoder_version': frame.decoderVersion,
    'source_channel': frame.channel,
    'decode_valid': frame.valid,
    'failure_code': frame.failureCode,
    'decoded_device_time_us': frame.deviceTimeUs,
    'decoded_sequence': frame.sequence,
    'stream_epoch': frame.streamEpoch,
    'schema_id': frame.schemaId,
    'envelope_flags': frame.flags,
    'raw_payload_hex': _hex(frame.bytes),
  };

  static Map<String, Object?> _strokeJson(Stroke stroke) => {
    'start_us': stroke.startUs,
    'end_us': stroke.endUs,
    'recovery_us': stroke.recoveryUs,
    'work_j': stroke.workJoule,
    'impulse_ns': stroke.impulseNewtonSecond,
    'mean_power_w': stroke.meanPowerWatt,
    'peak_power_w': stroke.peakPowerWatt,
    'peak_force_n': stroke.peakForceNewton,
    'left_work_j': stroke.leftWorkJoule,
    'right_work_j': stroke.rightWorkJoule,
    'quality': stroke.quality.name,
    'technique': stroke.technique.name,
    'firmware_events': [
      for (final event in stroke.firmwareEvents)
        {
          'side': event.side.name,
          'counter': event.counter,
          'event_time_us': event.eventTimeUs,
          'source': event.source,
          'missed_before': event.missedBefore,
        },
    ],
    'left': stroke.sides == null ? null : _strokeSideJson(stroke.sides!.left),
    'right': stroke.sides == null ? null : _strokeSideJson(stroke.sides!.right),
  };

  static Map<String, Object?> _strokeSideJson(StrokeMetrics side) => {
    'start_us': side.startUs,
    'end_us': side.endUs,
    'work_j': side.workJoule,
    'average_power_w': side.averagePowerWatt,
    'peak_power_w': side.peakPowerWatt,
    'peak_power_phase': side.peakPowerPhase,
    'peak_speed_m_s': side.peakSpeedMetresPerSecond,
    'peak_speed_phase': side.peakSpeedPhase,
    'stroke_length_m': side.strokeLengthMetres,
    'average_force_n': side.averageForceNewton,
    'peak_force_n': side.peakForceNewton,
    'power_phase_curve': [
      for (final point in side.powerPhaseCurve)
        {'phase': point.phase, 'power_w': point.powerWatt},
    ],
    'speed_phase_curve': [
      for (final point in side.speedPhaseCurve)
        {'phase': point.phase, 'speed_m_s': point.metresPerSecond},
    ],
    'force_distance_curve': [
      for (final point in side.forceDistanceCurve)
        {'distance_m': point.distanceMetres, 'force_n': point.forceNewton},
    ],
  };

  static String _hex(Iterable<int> bytes) => bytes
      .map((byte) => (byte & 0xff).toRadixString(16).padLeft(2, '0'))
      .join();
}
