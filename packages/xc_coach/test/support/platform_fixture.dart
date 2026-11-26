import 'dart:typed_data';

import 'package:xc_coach/core/models.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_coach/database/platform_repository.dart';
import 'package:xc_coach/domain/platform.dart';

/// Builds a realistic multi-tenant environment in memory so tests exercise the
/// same relations the production database uses.
class PlatformFixture {
  PlatformFixture() : database = GiuliaDatabase.inMemory(), _now = 1000 {
    platform = PlatformRepository(database);
  }

  final GiuliaDatabase database;
  late final PlatformRepository platform;
  int _now;

  int nextTime([int step = 1000]) => _now += step;

  String organization(
    String id, {
    OrganizationKind kind = OrganizationKind.club,
  }) {
    platform.createOrganization(
      id: id,
      name: id,
      kind: kind,
      nowUtcUs: nextTime(),
    );
    return id;
  }

  String user(String id) {
    platform.createUser(id: id, displayName: id, nowUtcUs: nextTime());
    return id;
  }

  void membership({
    required String organizationId,
    required String userId,
    required PlatformRole role,
    String? teamId,
  }) => platform.grantMembership(
    id: '$organizationId-$userId-${role.name}${teamId ?? ''}',
    organizationId: organizationId,
    userId: userId,
    role: role,
    teamId: teamId,
    nowUtcUs: nextTime(),
  );

  String athlete(String id, String organizationId, {String? userId}) {
    platform.createAthlete(
      id: id,
      organizationId: organizationId,
      name: id,
      userId: userId,
      nowUtcUs: nextTime(),
    );
    return id;
  }

  String device(String id, String organizationId) {
    platform.registerDevice(
      id: id,
      organizationId: organizationId,
      bleIdentifier: 'ble-$id',
      displayName: id,
      nowUtcUs: nextTime(),
    );
    for (final side in SensorSide.values) {
      platform.registerSensor(
        id: '$id-${side.name}',
        deviceId: id,
        side: side.name,
        serviceUuid: 'service',
        measurementUuid: 'measurement',
      );
    }
    return id;
  }

  void dispose() => database.dispose();
}

RawSensorSample rawSample({
  required String sensorId,
  required SensorSide side,
  required int timeUs,
  required int sequence,
  bool? pulling,
  double? angularVelocityRadPerSecond,
  int? strokeEventTimeUs,
  String? strokeSource,
  bool firmwareStrokeEventsAvailable = false,
}) => RawSensorSample(
  sensorId: sensorId,
  side: side,
  deviceTimeUs: timeUs - 100,
  receivedAtUs: timeUs,
  sequence: sequence,
  forceNewton: 200,
  velocityMetresPerSecond: 1.2,
  powerWatt: 240,
  batteryPercent: 82,
  packetValid: true,
  pulling: pulling,
  angularVelocityRadPerSecond: angularVelocityRadPerSecond,
  strokeEventTimeUs: strokeEventTimeUs,
  strokeSource: strokeSource,
  firmwareStrokeEventsAvailable: firmwareStrokeEventsAvailable,
  payload: Uint8List.fromList([1, sequence]),
);
