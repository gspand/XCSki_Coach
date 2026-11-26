import 'dart:typed_data';

import 'stroke_metrics.dart';

/// Immutable, unit-explicit domain records. Device and aligned timestamps use
/// monotonic microseconds; persisted session start/end timestamps use UTC.
enum SensorSide { left, right }

enum SignalQuality { good, degraded, invalid }

/// The exact notification received at the BLE boundary.
///
/// This is deliberately separate from [RawSensorSample]. A frame exists even
/// when its checksum, protocol version or numeric fields are invalid and no
/// sample can be constructed from it. Keeping that distinction is what makes
/// decoder defects reproducible instead of silently turning them into missing
/// measurements.
class RawSensorFrame {
  RawSensorFrame({
    required this.sensorId,
    required this.side,
    required this.receivedAtUs,
    required List<int> bytes,
    required this.decoderVersion,
    required this.valid,
    this.failureCode,
    this.deviceTimeUs,
    this.sequence,
  }) : bytes = Uint8List.fromList(bytes);

  final String sensorId;
  final SensorSide side;

  /// Monotonic application receive time. It is not a wall-clock timestamp.
  final int receivedAtUs;

  /// Exact bytes as received, defensively copied at the transport boundary.
  final Uint8List bytes;
  final String decoderVersion;
  final bool valid;

  /// Stable, non-personal diagnostic category. Never a guessed semantic
  /// interpretation of unknown protocol bytes.
  final String? failureCode;

  /// Present only when the decoder could prove them from a valid frame.
  final int? deviceTimeUs;
  final int? sequence;
}

class RawSensorSample {
  const RawSensorSample({
    required this.sensorId,
    required this.side,
    required this.deviceTimeUs,
    required this.receivedAtUs,
    required this.sequence,
    required this.forceNewton,
    required this.velocityMetresPerSecond,
    required this.powerWatt,
    required this.batteryPercent,
    required this.packetValid,
    this.pulling,
    this.payload,
    this.sourceEpoch,
    this.mappedTimeUs,
    this.statusFlags,
    this.positionMetres,
    this.opticalRaw,
    this.opticalMinimum,
    this.opticalMaximum,
    this.hallPasses,
    this.flywheelRevolutions,
    this.strokeCounter,
    this.batteryMillivolts,
    this.missedSamples,
    this.adcErrors,
    this.angularVelocityRadPerSecond,
    this.strokeEventTimeUs,
    this.strokeSource,
    this.firmwareStrokeEventsAvailable = false,
  });

  final String sensorId;
  final SensorSide side;
  final int deviceTimeUs;
  final int receivedAtUs;
  final int sequence;
  final double forceNewton;
  final double velocityMetresPerSecond;
  final double powerWatt;
  final int? batteryPercent;
  final bool packetValid;
  final bool? pulling;

  /// Exact notification bytes retained for protocol-level replay and audit.
  /// A defensive copy is made by the parser before creating a sample.
  final Uint8List? payload;
  final int? sourceEpoch;
  final int? mappedTimeUs;
  final int? statusFlags;
  final double? positionMetres;
  final int? opticalRaw;
  final int? opticalMinimum;
  final int? opticalMaximum;
  final int? hallPasses;
  final int? flywheelRevolutions;
  final int? strokeCounter;
  final int? batteryMillivolts;
  final int? missedSamples;
  final int? adcErrors;
  final double? angularVelocityRadPerSecond;
  final int? strokeEventTimeUs;
  final String? strokeSource;
  final bool firmwareStrokeEventsAvailable;
}

class DerivedSample {
  const DerivedSample({
    required this.raw,
    required this.alignedTimeUs,
    required this.calibratedForceNewton,
    required this.calibratedVelocityMetresPerSecond,
    required this.calibratedPowerWatt,
    required this.filteredForceNewton,
    required this.filteredPowerWatt,
    required this.quality,
    double? displayPowerWatt,
  }) : displayPowerWatt = displayPowerWatt ?? filteredPowerWatt;

  final RawSensorSample raw;
  final int alignedTimeUs;
  final double calibratedForceNewton;
  final double calibratedVelocityMetresPerSecond;
  final double calibratedPowerWatt;
  final double filteredForceNewton;
  final double filteredPowerWatt;
  final SignalQuality quality;

  /// Leistung für die Anzeige: Mittel der letzten drei Sekunden. Der Sensor
  /// schickt seit 0.22.30 den 100-ms-Mittelwert, der den Zugverlauf zeigt.
  final double displayPowerWatt;

  /// Leistung für die Zugkurve: ungefiltert, ungültige Proben als 0.
  double get curvePowerWatt =>
      quality == SignalQuality.invalid ? 0 : calibratedPowerWatt;
}

class PairedSample {
  const PairedSample({required this.left, required this.right});
  final DerivedSample left;
  final DerivedSample right;

  int get timeUs => (left.alignedTimeUs + right.alignedTimeUs) ~/ 2;
  double get powerWatt => left.filteredPowerWatt + right.filteredPowerWatt;
  double get displayPowerWatt => left.displayPowerWatt + right.displayPowerWatt;
  double get forceNewton =>
      left.filteredForceNewton + right.filteredForceNewton;
  bool? get pulling {
    final leftPulling = left.raw.pulling;
    final rightPulling = right.raw.pulling;
    if (leftPulling == null && rightPulling == null) return null;
    return leftPulling == true || rightPulling == true;
  }

  double get leftShare =>
      displayPowerWatt <= 0 ? 0.5 : left.displayPowerWatt / displayPowerWatt;
  double get symmetryIndex => displayPowerWatt <= 0
      ? 1
      : 1 -
            ((left.displayPowerWatt - right.displayPowerWatt).abs() /
                displayPowerWatt);
}

class FirmwareStrokeEvent {
  const FirmwareStrokeEvent({
    required this.side,
    required this.counter,
    required this.eventTimeUs,
    required this.source,
    this.missedBefore = 0,
  });

  final SensorSide side;
  final int counter;
  final int eventTimeUs;
  final String source;
  final int missedBefore;
}

enum StrokeTechnique { leftArm, rightArm, doublePole, legacy }

class Stroke {
  const Stroke({
    required this.startUs,
    required this.endUs,
    required this.recoveryUs,
    required this.workJoule,
    required this.impulseNewtonSecond,
    required this.meanPowerWatt,
    required this.peakPowerWatt,
    required this.peakForceNewton,
    required this.leftWorkJoule,
    required this.rightWorkJoule,
    required this.quality,
    this.peakLeftPowerWatt,
    this.peakRightPowerWatt,
    this.leftPeakAtUs,
    this.rightPeakAtUs,
    this.sides,
    this.firmwareEvents = const [],
    this.technique = StrokeTechnique.legacy,
  });

  final int startUs;
  final int endUs;
  final int recoveryUs;
  final double workJoule;
  final double impulseNewtonSecond;
  final double meanPowerWatt;
  final double peakPowerWatt;
  final double peakForceNewton;
  final double leftWorkJoule;
  final double rightWorkJoule;
  final SignalQuality quality;

  /// Spitzenleistung der einzelnen Seite. Null für Züge, die aus einem
  /// Archivstand ohne diese Felder gelesen wurden — «unbekannt» und «null
  /// Watt» sind verschiedene Aussagen.
  final double? peakLeftPowerWatt;
  final double? peakRightPowerWatt;

  /// Wann die jeweilige Seite ihre Spitze erreicht hat, als Zeitstempel.
  ///
  /// Der Unterschied zwischen den Seiten ist die eigentliche Technikfrage:
  /// zwei Arme können dieselbe Arbeit leisten und sie doch an verschiedenen
  /// Stellen des Zuges aufbringen.
  final int? leftPeakAtUs;
  final int? rightPeakAtUs;

  /// Der Zug je Seite, mit seinen Kurven. Null für Züge aus einem Archivstand,
  /// der die Kurven nicht enthält.
  final StrokeSides? sides;
  final List<FirmwareStrokeEvent> firmwareEvents;
  final StrokeTechnique technique;

  bool get supportsSymmetry =>
      technique == StrokeTechnique.doublePole ||
      technique == StrokeTechnique.legacy;

  double get durationSeconds =>
      (endUs - startUs) / Duration.microsecondsPerSecond;
  double get frequencyPerMinute =>
      durationSeconds <= 0 ? 0 : 60 / durationSeconds;
  double get leftWorkShare => workJoule <= 0 ? 0.5 : leftWorkJoule / workJoule;

  /// Dauer der Rückholphase vor diesem Zug, in Sekunden.
  double get recoverySeconds => recoveryUs / Duration.microsecondsPerSecond;

  /// Wo im Zug die Spitze lag, 0 bis 1. Null, wenn der Zeitpunkt fehlt.
  double? get leftPeakPosition => _position(leftPeakAtUs);
  double? get rightPeakPosition => _position(rightPeakAtUs);

  /// Hoechste gemessene Geschwindigkeit einer Seite. Null bei alten
  /// Archivstaenden oder wenn keine valide Geschwindigkeitsprobe vorliegt.
  double? get peakSpeedMetresPerSecond {
    final left = sides?.left.peakSpeedMetresPerSecond;
    final right = sides?.right.peakSpeedMetresPerSecond;
    if (left == null) return right;
    if (right == null) return left;
    return left > right ? left : right;
  }

  double? _position(int? peakAtUs) {
    if (peakAtUs == null || endUs <= startUs) return null;
    return ((peakAtUs - startUs) / (endUs - startUs)).clamp(0.0, 1.0);
  }
}

class SensorHealth {
  const SensorHealth({
    required this.connected,
    required this.packetLossRate,
    required this.latencyMs,
    required this.jitterMs,
    required this.lastSeenUs,
    this.batteryPercent,
  });

  final bool connected;
  final double packetLossRate;
  final double latencyMs;
  final double jitterMs;
  final int lastSeenUs;
  final int? batteryPercent;

  SignalQuality get quality =>
      !connected || packetLossRate > .05 || jitterMs > 40
      ? SignalQuality.degraded
      : SignalQuality.good;
}

/// Ein Herzschlagwert, wie ihn ein Gurt liefert.
///
/// Steht bei den Modellen und nicht beim Funk: Es ist ein Messwert. Lag er in
/// `ble/`, zog jedes Produkt die Funkschicht mit — auch die, die nie eine
/// Verbindung aufbauen.
/// Standard Bluetooth SIG Heart Rate Service parser (0x180D / 0x2A37).
/// RR intervals, when present, are preserved in milliseconds for later HRV
/// analysis instead of being discarded after displaying BPM.
class HeartRateSample {
  const HeartRateSample({
    required this.recordedAtUs,
    required this.bpm,
    required this.rrIntervalsMs,
    required this.contactDetected,
  });
  final int recordedAtUs;
  final int bpm;
  final List<double> rrIntervalsMs;
  final bool? contactDetected;
}
