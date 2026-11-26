import 'dart:typed_data';

import 'package:fit_sdk/fit_sdk.dart';
import 'package:xc_coach/domain/normalized_session_adapters.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/external_data/garmin_fit/garmin_fit_decoder.dart';

const _fitEpochSeconds = 631065600;

void main() {
  const decoder = GarminFitDecoder();

  test('decodes cycling power, heart rate and cadence with CRC validation', () {
    final bytes = _activity(
      sport: Sport.cycling,
      records: const [
        _Record(second: 0, power: 180, heartRate: 142, cadence: 88),
        _Record(second: 1, power: 200, heartRate: 146, cadence: 90),
        _Record(second: 2, power: 0, heartRate: 148, cadence: 0),
      ],
    );

    final imported = decoder.decode(bytes, fileName: 'stufentest.fit');

    expect(imported.fileName, 'stufentest.fit');
    expect(imported.activity.sport, 'cycling');
    expect(imported.activity.sourceId, startsWith('fit:'));
    expect(imported.recordCount, 2);
    expect(imported.activity.samples.map((sample) => sample.loadValue), [
      180,
      200,
    ]);
    expect(imported.activity.samples.last.loadUnit, 'W');
    expect(imported.activity.samples.last.heartRateBpm, 146);
    expect(imported.activity.samples.last.cadencePerMinute, 90);
    expect(imported.activity.startedAtUtcUs, _unixSecond(0) * 1000000);
    expect(imported.activity.endedAtUtcUs, _unixSecond(2) * 1000000);
  });

  test('turns FIT running speed in m/s into protocol speed in km/h', () {
    final bytes = _activity(
      sport: Sport.running,
      records: const [
        _Record(second: 0, speed: 3),
        _Record(second: 1, speed: 3.5),
      ],
    );

    final imported = decoder.decode(bytes, fileName: 'laufband.fit');

    expect(imported.activity.sport, 'running');
    expect(imported.activity.samples.first.loadUnit, 'km/h');
    expect(imported.activity.samples.first.loadValue, closeTo(10.8, 0.001));
    expect(imported.activity.samples.last.loadValue, closeTo(12.6, 0.001));
  });

  test('XC ski speed stays speed and generic Nordic skiing remains unspecified', () {
    final bytes = _activity(sport: Sport.crossCountrySkiing, records: const [
      _Record(second: 0, speed: 3, heartRate: 142), _Record(second: 120, speed: 4, heartRate: 155),
    ]);
    final fit = decoder.decode(bytes, fileName: 'activity.fit');
    final session = ExternalActivityAdapter.toNormalized(fit, athleteId: 'a');
    expect(session.modality, XcModality.skiNordicUnknown);
    expect(session.externalMetrics.averagePowerWatt, isNull);
    expect(session.internalMetrics.averageHeartRateBpm, 149);
  });

  test('a Strava-produced FIT cannot be admitted under an independent origin', () {
    final bytes = _activity(sport: Sport.crossCountrySkiing, manufacturer: Manufacturer.strava,
        records: const [_Record(second: 0, speed: 3), _Record(second: 1, speed: 4)]);
    expect(() => decoder.decode(bytes, fileName: 'ski.fit'), throwsA(isA<GarminFitDecodeException>()
        .having((e) => e.message, 'message', contains('Strava'))));
  });

  test('rejects a damaged FIT checksum instead of importing partial data', () {
    final bytes = _activity(
      sport: Sport.cycling,
      records: const [_Record(second: 0, power: 180)],
    );
    bytes[bytes.length - 1] ^= 0xff;

    expect(
      () => decoder.decode(bytes, fileName: 'kaputt.fit'),
      throwsA(
        isA<GarminFitDecodeException>().having(
          (failure) => failure.message,
          'message',
          contains('beschädigt'),
        ),
      ),
    );
  });

  test('rejects activities without a load channel', () {
    final bytes = _activity(
      sport: Sport.cycling,
      records: const [_Record(second: 0, heartRate: 140)],
    );

    expect(
      () => decoder.decode(bytes, fileName: 'nur-puls.fit'),
      throwsA(
        isA<GarminFitDecodeException>().having(
          (failure) => failure.message,
          'message',
          contains('Leistung'),
        ),
      ),
    );
  });
}

Uint8List _activity({required int sport, int manufacturer = Manufacturer.garmin, required List<_Record> records}) {
  final encoder = Encode()..open();

  final file = FileIdMesg()
    ..setFieldValue(FileIdMesg.fieldType, 4)
    ..setFieldValue(FileIdMesg.fieldManufacturer, manufacturer)
    ..setFieldValue(FileIdMesg.fieldProduct, 123)
    ..setFieldValue(FileIdMesg.fieldTimeCreated, _fitSecond(0));
  _write(encoder, file);

  for (var index = 0; index < records.length; index++) {
    final value = records[index];
    final record = RecordMesg()
      ..setFieldValue(RecordMesg.fieldTimestamp, _fitSecond(value.second));
    if (value.power != null) {
      record.setFieldValue(RecordMesg.fieldPower, value.power);
    }
    if (value.speed != null) {
      record.setFieldValue(RecordMesg.fieldEnhancedSpeed, value.speed);
    }
    if (value.heartRate != null) {
      record.setFieldValue(RecordMesg.fieldHeartRate, value.heartRate);
    }
    if (value.cadence != null) {
      record.setFieldValue(RecordMesg.fieldCadence, value.cadence);
    }
    _write(encoder, record);
  }

  final session = SessionMesg()
    ..setFieldValue(SessionMesg.fieldMessageIndex, 7)
    ..setFieldValue(SessionMesg.fieldStartTime, _fitSecond(0))
    ..setFieldValue(SessionMesg.fieldTimestamp, _fitSecond(records.last.second))
    ..setFieldValue(SessionMesg.fieldSport, sport);
  _write(encoder, session);

  return encoder.close();
}

void _write(Encode encoder, Mesg message) {
  encoder.writeMesgDefinition(MesgDefinition.fromMesg(message));
  encoder.writeMesg(message);
}

int _unixSecond(int offset) =>
    DateTime.utc(2026, 1, 2, 10).millisecondsSinceEpoch ~/ 1000 + offset;

int _fitSecond(int offset) => _unixSecond(offset) - _fitEpochSeconds;

class _Record {
  const _Record({
    required this.second,
    this.power,
    this.speed,
    this.heartRate,
    this.cadence,
  });

  final int second;
  final int? power;
  final double? speed;
  final int? heartRate;
  final int? cadence;
}
