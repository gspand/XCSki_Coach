/// Ein Zug, je Seite, mit seinen Kurven.
///
/// ## Warum es diese Klasse gibt
///
/// [Stroke] beschreibt den Zug als Ganzes und in Skalaren. Für die Zugdynamik
/// reicht das nicht: die Frage ist nicht «wie viel», sondern «wie» — wo im Zug
/// die Kraft steht, wie lang der Weg war, wie sich die beiden Arme über den
/// Zug verteilen. Das sind Kurven, und sie gehören je Seite getrennt.
///
/// ## Die Regel, die dieser Datei ihre Form gibt
///
/// **Was nicht validiert ist, ist null — nicht null Newton.**
///
/// Leistung und Zeit kommen aus der Messkette und sind belegt. Kraft und
/// Zugweg sind es nicht: Auf der Ercolina folgen beide aus einem mechanischen
/// Modell, das effektives Trägheitsmoment, Rückholsystem, Verluste, wirksame
/// Radien und den tatsächlichen Seilweg enthält — und dieses Modell ist noch
/// nicht gegen eine Referenz geprüft. Eine Vereinfachung wie `F = P/v` wäre bei
/// kleiner Geschwindigkeit und in der Systemdynamik schlicht falsch, und ein
/// falscher Newton-Wert auf einem Bildschirm ist schlimmer als gar keiner.
///
/// Deshalb bleiben [StrokeMetrics.peakForceNewton], [strokeLengthMetres] und
/// [forceDistanceCurve] leer, solange [ErcolinaMechanics.forceModelValidated]
/// falsch ist. Die Oberfläche zeigt an diesen Stellen keinen Strich und keine
/// Null, sondern nichts — und sagt einmal, warum.
library;

import 'package:flutter/foundation.dart';

/// Welche Seite ein Zug beschreibt.
enum StrokeSide { left, right }

/// Der Stand des mechanischen Modells der Ercolina.
///
/// Eine Konstante und kein Schalter in den Einstellungen: ob eine Kraftangabe
/// physikalisch trägt, ist keine Frage des Geschmacks. Sie wird hier auf true
/// gesetzt, wenn das Modell gegen eine Referenzmessung geprüft ist — und erst
/// dann erscheinen Kraft und Zugweg im Produktivbetrieb.
abstract final class ErcolinaMechanics {
  static const String prototypeNotice =
      'Prototyp: Leistung und Arbeit sind Modellwerte, noch nicht physikalisch validiert.';
  static const String prototypeNoticeEnglish =
      'Prototype: power and work are model estimates, not yet physically validated.';
  /// Noch nicht validiert: es fehlen effektives Trägheitsmoment, die Kennlinie
  /// des Rückholsystems, die mechanischen Verluste, die wirksamen Radien und
  /// der tatsächliche Seilweg je Trommelumdrehung.
  static const bool forceModelValidated = false;

  /// Was der Oberfläche zu sagen bleibt, solange das so ist.
  static const String pendingValidation =
      'Kraft und Zugweg erscheinen, sobald das mechanische Modell der '
      'Ercolina gegen eine Referenzmessung geprüft ist. Bis dahin zeigt '
      'GIULIA hier keine Zahl — eine gerechnete Kraft ohne geprüftes Modell '
      'wäre eine Behauptung.';
}

/// Ein Punkt der Kraft-Weg-Kurve.
@immutable
class ForceDistanceSample {
  const ForceDistanceSample({
    required this.distanceMetres,
    required this.forceNewton,
  });

  final double distanceMetres;
  final double forceNewton;
}

/// Ein Punkt der Leistungs-Phasen-Kurve.
@immutable
class PowerPhaseSample {
  const PowerPhaseSample({required this.phase, required this.powerWatt});

  /// Stelle im Zug, 0 bis 1.
  final double phase;

  final double powerWatt;
}

/// Ein Punkt der gemessenen Geschwindigkeits-Phasen-Kurve.
///
/// Modellbasierte Vergleichsgeschwindigkeit der Ercolina-Messkette. Sie ist
/// keine unabhängig gemessene Seilgeschwindigkeit.
@immutable
class SpeedPhaseSample {
  const SpeedPhaseSample({required this.phase, required this.metresPerSecond});

  /// Stelle im Zug, 0 bis 1.
  final double phase;

  final double metresPerSecond;
}

/// Ein Zug einer Seite.
@immutable
class StrokeMetrics {
  const StrokeMetrics({
    required this.side,
    required this.startUs,
    required this.endUs,
    required this.workJoule,
    required this.averagePowerWatt,
    required this.peakPowerWatt,
    required this.peakPowerPhase,
    required this.powerPhaseCurve,
    this.peakSpeedMetresPerSecond,
    this.peakSpeedPhase,
    this.speedPhaseCurve = const <SpeedPhaseSample>[],
    this.strokeLengthMetres,
    this.averageForceNewton,
    this.peakForceNewton,
    this.peakForcePosition,
    this.forceDistanceCurve = const <ForceDistanceSample>[],
  });

  final StrokeSide side;
  final int startUs;
  final int endUs;

  double get durationSeconds =>
      (endUs - startUs) / Duration.microsecondsPerSecond;

  final double workJoule;
  final double averagePowerWatt;
  final double peakPowerWatt;

  /// Wo im Zug die Leistungsspitze lag, 0 bis 1.
  final double peakPowerPhase;

  /// Leistung über den Zugverlauf. Immer vorhanden: Leistung und Zeit sind
  /// gemessen.
  final List<PowerPhaseSample> powerPhaseCurve;

  /// Gemessene Geschwindigkeit ueber den normierten Zugverlauf. Bei alten
  /// Archivstaenden leer; es wird keine Ersatzkurve aus Leistung oder Kraft
  /// berechnet.
  final List<SpeedPhaseSample> speedPhaseCurve;
  final double? peakSpeedMetresPerSecond;
  final double? peakSpeedPhase;

  // ------------------------------------------------- noch nicht validiert
  final double? strokeLengthMetres;
  final double? averageForceNewton;
  final double? peakForceNewton;

  /// Position des Kraftmaximums, bezogen auf den Zugweg, 0 bis 1.
  final double? peakForcePosition;

  /// Kraft über den Zugweg. Leer, solange das mechanische Modell ungeprüft ist.
  final List<ForceDistanceSample> forceDistanceCurve;

  /// Ob diese Seite eine belegte Kraftangabe trägt.
  bool get hasForce =>
      ErcolinaMechanics.forceModelValidated && peakForceNewton != null;
}

/// Beide Seiten eines Zuges.
@immutable
class StrokeSides {
  const StrokeSides({required this.left, required this.right});

  final StrokeMetrics left;
  final StrokeMetrics right;

  StrokeMetrics operator [](StrokeSide side) =>
      side == StrokeSide.left ? left : right;
}
