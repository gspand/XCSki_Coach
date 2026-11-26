/// Die virtuelle Loipe: ein Langläufer im Flachen, angetrieben von der
/// gemessenen Leistung.
///
/// ## Warum ein Modell und keine Formel
///
/// `m·dv/dt = P/v − μ·m·g − ½·ρ·CdA·v²`. Mit der Masse im Modell baut sich
/// das Tempo über ein paar Schübe auf, und in einer Pause gleitet der Läufer
/// aus, statt auf der Stelle zu stehen — so wie auf Schnee.
///
/// ## Warum aus den Zügen
///
/// Live und Zusammenfassung rechnen über dieselben gespeicherten Züge: die
/// Arbeit eines Zugs gleichmässig über seine Dauer, dazwischen nichts. So
/// zeigen beide dieselbe Distanz.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/models.dart';

/// Wie gut die Ski auf dem Schnee gleiten.
enum SnowGlide {
  fast('Sehr gut', 0.025),
  normal('Normal', 0.035),
  slow('Stumpf', 0.05);

  const SnowGlide(this.label, this.friction);

  final String label;

  /// Reibwert Ski/Schnee.
  final double friction;

  static SnowGlide decode(String? name) =>
      values.firstWhere((glide) => glide.name == name, orElse: () => fast);
}

/// Schlüssel der gewählten Gleitstufe in `app_state`.
const String snowGlideStateKey = 'track.glide';

/// Ereignis, mit dem eine Aufzeichnung ihre Loipe festhält.
const String virtualTrackEventKind = 'virtual_track';

@immutable
class VirtualTrackSetup {
  const VirtualTrackSetup({required this.massKg, required this.friction});

  /// Ohne eingetragenes Körpergewicht: 75 kg Athlet.
  static const double defaultBodyMassKg = 75;

  /// Ski, Stöcke, Schuhe, Kleidung.
  static const double equipmentKg = 3;

  factory VirtualTrackSetup.forAthlete({
    double? bodyMassKg,
    required SnowGlide glide,
  }) => VirtualTrackSetup(
    massKg:
        (bodyMassKg != null && bodyMassKg > 20
            ? bodyMassKg
            : defaultBodyMassKg) +
        equipmentKg,
    friction: glide.friction,
  );

  /// Läufer mit Ausrüstung.
  final double massKg;
  final double friction;

  String encode() => jsonEncode({'mass_kg': massKg, 'friction': friction});

  static VirtualTrackSetup? decode(String? detail) {
    if (detail == null) return null;
    try {
      final json = jsonDecode(detail) as Map<String, Object?>;
      final mass = (json['mass_kg'] as num?)?.toDouble();
      final friction = (json['friction'] as num?)?.toDouble();
      if (mass == null || mass <= 0 || friction == null || friction < 0) {
        return null;
      }
      return VirtualTrackSetup(massKg: mass, friction: friction);
    } on Object {
      return null;
    }
  }
}

class VirtualSkiTrack {
  VirtualSkiTrack(this.setup);

  /// Kalte Luft.
  static const double airDensity = 1.2;

  /// Aufrechter Doppelstockschub.
  static const double dragAreaM2 = 0.5;
  static const double gravity = 9.81;
  static const double _stepSeconds = .05;

  /// Unterhalb davon begrenzt die Kraft, nicht die Leistung: Aus dem Stand
  /// wäre P/v unendlich.
  static const double _propulsionFloorMetresPerSecond = 1;

  final VirtualTrackSetup setup;
  double speedMetresPerSecond = 0;
  double distanceMetres = 0;
  int? _lastUs;

  /// Rechnet eine ganze Einheit nach.
  static VirtualSkiTrack replay(
    VirtualTrackSetup setup,
    Iterable<Stroke> strokes,
  ) {
    final track = VirtualSkiTrack(setup);
    strokes.forEach(track.addStroke);
    return track;
  }

  void addStroke(Stroke stroke) {
    final last = _lastUs;
    final startUs = last == null
        ? stroke.startUs
        : math.max(stroke.startUs, last);
    if (last != null)
      _run(0, (startUs - last) / Duration.microsecondsPerSecond);
    final seconds = (stroke.endUs - startUs) / Duration.microsecondsPerSecond;
    if (seconds > 0) _run(math.max(0, stroke.workJoule) / seconds, seconds);
    _lastUs = math.max(startUs, stroke.endUs);
  }

  void _run(double powerWatt, double seconds) {
    final rolling = setup.friction * setup.massKg * gravity;
    var left = seconds;
    while (left > 0) {
      if (powerWatt <= 0 && speedMetresPerSecond <= 0) return;
      final dt = math.min(_stepSeconds, left);
      final speed = speedMetresPerSecond;
      final drive =
          powerWatt / math.max(speed, _propulsionFloorMetresPerSecond);
      final air = .5 * airDensity * dragAreaM2 * speed * speed;
      final next = math.max(
        0.0,
        speed + (drive - rolling - air) / setup.massKg * dt,
      );
      distanceMetres += (speed + next) / 2 * dt;
      speedMetresPerSecond = next;
      left -= dt;
    }
  }
}
