/// Das Protokoll, nach dem gemessen wird.
///
/// Ein Vertrag der Plattform, keine Diagnostik: das Protokoll beschreibt, wie
/// belastet wird — Startlast, Stufenhöhe, Stufendauer. Das Gerät fährt es, die
/// Diagnostik liest es, und keines der beiden muss dafür das andere kennen.
library;

import 'package:xc_coach/domain/diagnostic_catalogue.dart';
import 'package:xc_coach/domain/diagnostics.dart';

/// A named step-test protocol offered in the form.
///
/// These are entry conveniences — a start load, an increment and a step
/// duration. They pre-fill the form and are stored as provenance; they do not
/// influence the calculation.
class TestProtocol {
  const TestProtocol({
    required this.id,
    required this.name,
    required this.sport,
    required this.loadUnit,
    required this.startLoad,
    required this.increment,
    required this.stageDurationSeconds,
    required this.description,
    this.version = '1.0.0',
  });

  final String id;
  final String name;
  final String sport;
  final String loadUnit;
  final double startLoad;
  final double increment;
  final int stageDurationSeconds;
  final String description;
  final String version;

  /// A derived protocol remains explicit provenance. The resulting identifier
  /// contains every setting that changes comparability, including start load.
  /// It is not a claim that the protocol was one of Giulia's presets.
  factory TestProtocol.custom({
    required String name,
    required String sport,
    required String loadUnit,
    required double startLoad,
    required double increment,
    required int stageDurationSeconds,
  }) {
    String number(double value) => value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString().replaceAll('.', '_');
    return TestProtocol(
      id: 'custom_${sport}_${number(startLoad)}_${loadUnit == LoadUnits.watt ? 'w' : 'kmh'}_${number(increment)}_${stageDurationSeconds}s',
      name: name.trim().isEmpty ? 'Eigenes Stufenprotokoll' : name.trim(),
      sport: sport,
      loadUnit: loadUnit,
      startLoad: startLoad,
      increment: increment,
      stageDurationSeconds: stageDurationSeconds,
      description:
          'Eigene Vorgabe: Start ${number(startLoad)} $loadUnit, +${number(increment)} '
          '$loadUnit je Stufe, $stageDurationSeconds s Stufendauer.',
    );
  }

  bool get isCustom => id.startsWith('custom_');

  /// Die Sportart, unter der TEST dieses Protokoll anbietet.
  DiagnosticSport? get diagnosticSport =>
      DiagnosticSport.classify(sport: sport, protocol: id);

  double loadOfStage(int stageNumber) =>
      startLoad + increment * (stageNumber - 1);
}

/// The presets offered in the "new test" form.
///
/// Deliberately few and conventional. A diagnostician who needs a different
/// ramp edits the loads directly; the form does not pretend that these are the
/// only valid protocols.
const List<TestProtocol> testProtocols = [
  TestProtocol(
    id: 'cycling_step_120w_20w_3min',
    name: 'Radergometrie ab 120 W · 20 W / 3 min',
    sport: 'cycling',
    loadUnit: LoadUnits.watt,
    startLoad: 120,
    increment: 20,
    stageDurationSeconds: 180,
    description: 'Start 120 W, +20 W je Stufe, 3 min Stufendauer.',
  ),
  TestProtocol(
    id: 'cycling_step_20w_2min',
    name: 'Radergometrie 20 W / 2 min',
    sport: 'cycling',
    loadUnit: LoadUnits.watt,
    startLoad: 60,
    increment: 20,
    stageDurationSeconds: 120,
    description: 'Start 60 W, +20 W je Stufe, 2 min Stufendauer.',
  ),
  TestProtocol(
    id: 'custom_cycling_120_w_20_180s',
    name: 'Eigenes Stufenprotokoll',
    sport: 'cycling',
    loadUnit: LoadUnits.watt,
    startLoad: 120,
    increment: 20,
    stageDurationSeconds: 180,
    description:
        'Alle Werte selbst wählen: Sportart, Startlast, Steigerung und Stufendauer.',
  ),
  TestProtocol(
    id: 'running_step_1_5kmh_3min',
    name: 'Laufband 1,5 km/h / 3 min',
    sport: 'running',
    loadUnit: LoadUnits.kilometresPerHour,
    startLoad: 8,
    increment: 1.5,
    stageDurationSeconds: 180,
    description: 'Start 8,0 km/h, +1,5 km/h je Stufe, 3 min Stufendauer.',
  ),
  TestProtocol(
    id: 'running_step_2kmh_3min',
    name: 'Laufband 2,0 km/h / 3 min',
    sport: 'running',
    loadUnit: LoadUnits.kilometresPerHour,
    startLoad: 8,
    increment: 2,
    stageDurationSeconds: 180,
    description: 'Start 8,0 km/h, +2,0 km/h je Stufe, 3 min Stufendauer.',
  ),
  // Skilanglauf: auf dem Skiroller-Laufband in km/h, am Ski-Ergometer in W.
  // Gespeichert als `langlauf`, den Schlüssel, den die Auswertung dem
  // Skilanglauf zuordnet.
  TestProtocol(
    id: 'xc_ski_rollerski_1kmh_4min',
    name: 'Skiroller-Laufband 1,0 km/h / 4 min',
    sport: 'langlauf',
    loadUnit: LoadUnits.kilometresPerHour,
    startLoad: 10,
    increment: 1,
    stageDurationSeconds: 240,
    description:
        'Start 10,0 km/h, +1,0 km/h je Stufe, 4 min Stufendauer. '
        'Steigung und Technik über alle Stufen konstant halten.',
  ),
  TestProtocol(
    id: 'xc_ski_ergometer_20w_3min',
    name: 'Ski-Ergometer 20 W / 3 min',
    sport: 'langlauf',
    loadUnit: LoadUnits.watt,
    startLoad: 60,
    increment: 20,
    stageDurationSeconds: 180,
    description: 'Start 60 W, +20 W je Stufe, 3 min Stufendauer.',
  ),
  // The sport is `ercolina`, not `cycling`. An Ercolina is a power ergometer,
  // but the threshold methods were validated on cycle ergometry and treadmill
  // running. Declaring it as cycling would silently borrow that evidence; the
  // engine treats `ercolina` like any sport without specific evidence and
  // says so. Older tests were stored as `generic` and are still recognised
  // as Ercolina through their protocol id.
  TestProtocol(
    id: 'ercolina_step_20w_3min',
    name: 'Ercolina 20 W / 3 min',
    sport: 'ercolina',
    loadUnit: LoadUnits.watt,
    startLoad: 60,
    increment: 20,
    stageDurationSeconds: 180,
    description: 'Start 60 W, +20 W je Stufe, 3 min Stufendauer.',
  ),
  TestProtocol(
    id: 'ercolina_step_25w_4min',
    name: 'Ercolina 25 W / 4 min',
    sport: 'ercolina',
    loadUnit: LoadUnits.watt,
    startLoad: 75,
    increment: 25,
    stageDurationSeconds: 240,
    description: 'Start 75 W, +25 W je Stufe, 4 min Stufendauer.',
  ),
];

/// Die Vorlagen einer Sportart, in der Reihenfolge von [testProtocols].
List<TestProtocol> protocolsForSport(DiagnosticSport sport) => [
  for (final preset in testProtocols)
    if (preset.diagnosticSport == sport) preset,
];
