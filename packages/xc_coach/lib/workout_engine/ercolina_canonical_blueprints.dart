/// Die kanonischen Gerätenheiten als ausführbare Einheiten.
///
/// ## Warum diese Datei existiert
///
/// Vorher gab es eine Zuordnung von Reiztyp zu Blueprint: TECH führte auf
/// `technique-doublepoling`. Das Ergebnis war eine Lüge auf dem Bildschirm.
/// Der Coach verschrieb «E1 Technik und Oekonomie 25min» — gestartet wurde
/// eine andere Einheit mit dreiunddreißig Minuten und einer anderen
/// Struktur. Die Dosisdecke hielt im Datenobjekt und nicht in dem, was der
/// Athlet tatsächlich machte.
///
/// Deshalb wird hier nichts mehr zugeordnet, sondern übersetzt: Dieselben
/// Schritte, die die Firmware von der SD-Karte liest, werden zu Schritten
/// der App. Eine Wahrheit, zwei Formen.
library;

import 'ercolina_canonical_library.dart';
import 'workout_engine.dart';
import 'workout_library.dart';

/// Complete device workout selection, including the familiar quick templates.
/// Keep the source IDs: recent sessions and saved copies refer to these IDs.
final List<WorkoutBlueprint> ercolinaWorkoutLibrary = List.unmodifiable([
  ...workoutLibrary,
  ...([...ercolinaCanonicalLibrary]..sort((a, b) {
        int number(String id) =>
            int.tryParse(RegExp(r'^E(\d+)').firstMatch(id)?.group(1) ?? '') ??
            999;
        final order = number(a.id).compareTo(number(b.id));
        return order == 0 ? a.id.compareTo(b.id) : order;
      }))
      .map(blueprintOfCanonical),
]);

/// Die kanonische Einheit [id] (zum Beispiel «E1») als ausführbare Einheit.
WorkoutBlueprint? canonicalBlueprintById(String? id) {
  if (id == null) return null;
  final workout = ercolinaCanonicalLibrary
      .where((candidate) => candidate.id == id)
      .firstOrNull;
  return workout == null ? null : blueprintOfCanonical(workout);
}

/// Übersetzt eine kanonische Einheit in die Schritte der App.
WorkoutBlueprint blueprintOfCanonical(ErcolinaCanonicalWorkout workout) {
  final steps = workout.steps;
  return WorkoutBlueprint(
    id: workout.id,
    name: workout.title,
    category: _categoryOf(workout.type),
    purpose: workout.notes.isEmpty
        ? 'Einheit ${workout.id} der Gerätebibliothek.'
        : workout.notes,
    steps: [
      for (final (index, step) in steps.indexed)
        BlueprintStep(
          kind: _kindOf(
            index: index,
            count: steps.length,
            hint: step.hint,
            type: workout.type,
            hasEffort: steps.any((other) => other.percentFtp >= _effortFrom),
          ),
          intensity: intensityOfPercent(step.percentFtp, type: workout.type),
          seconds: step.seconds,
          powerTargetMode: PowerTargetMode.percentOfThreshold,
          customPercent: MetricRange(
            step.percentFtp / 100,
            step.percentFtp / 100,
          ),
          note: step.hint.isEmpty ? null : step.hint,
        ),
    ],
  );
}

/// Welchem Intensitätsband ein Prozentwert der Schwellenleistung entspricht.
///
/// Die Bänder stammen aus [Intensity] und werden hier nicht neu erfunden. Der
/// einzige Sonderfall ist `technique`: Es überlappt mit `recovery` und `base`,
/// weil Technik keine eigene Intensität ist, sondern eine Aufgabe. Deshalb
/// gewinnt es nur in Einheiten, die als Technikeinheiten geführt werden.
Intensity intensityOfPercent(int percentFtp, {required String type}) {
  final share = percentFtp / 100.0;
  if ((type == 'TECH' || type == 'SPEED' || type == 'SPRINT') &&
      share >= Intensity.technique.lower &&
      share <= Intensity.technique.upper) {
    return Intensity.technique;
  }
  const bands = [
    Intensity.recovery,
    Intensity.base,
    Intensity.tempo,
    Intensity.threshold,
    Intensity.vo2,
    Intensity.maximal,
  ];
  for (final band in bands) {
    if (share >= band.lower && share <= band.upper) return band;
  }
  // Zwischen zwei Bändern (die Schwelle beginnt erst bei 95 Prozent) oder
  // darüber hinaus: das nächstliegende Band, nicht ein erfundenes.
  var nearest = bands.first;
  var distance = double.infinity;
  for (final band in bands) {
    final middle = (band.lower + band.upper) / 2;
    final delta = (share - middle).abs();
    if (delta < distance) {
      distance = delta;
      nearest = band;
    }
  }
  return nearest;
}

/// Ab wann ein Abschnitt eine Belastung ist und keine Erholung: achtzig
/// Prozent der Schwellenleistung, die Grenze des Tempobereichs.
const _effortFrom = 80;

/// Step roles from the fixed library's position and recovery instructions.
/// Intensity cannot identify recovery: steady I1/I2 work is deliberately low.
/// Warm-up and cool-down keep their existing position semantics; E0 remains
/// technique. Only an explicit recovery instruction allows the workout clock
/// to continue without strokes in the live training flow.
WorkoutStepKind _kindOf({
  required int index,
  required int count,
  required String hint,
  required String type,
  required bool hasEffort,
}) {
  if (index == 0) return WorkoutStepKind.warmup;
  if (index == count - 1 && count > 2) return WorkoutStepKind.cooldown;
  // Low power alone is not a break: E4/E6/E7 include sustained easy work.
  // Only recovery instructions present in the canonical source grant the
  // no-stroke clock exception. Unknown instructions remain active work.
  const recoveryHints = {
    'easy recovery',
    'locker traben',
    'locker ausrollen',
    'Serienpause locker',
    'vollstaendig erholen',
    'letzte Pause',
    'Ende Serie 1',
    'Ende Serie 2',
  };
  if (recoveryHints.contains(hint)) return WorkoutStepKind.recovery;
  return type == 'TECH' && !hasEffort
      ? WorkoutStepKind.technique
      : WorkoutStepKind.work;
}

WorkoutCategory _categoryOf(String type) => switch (type) {
  'TECH' => WorkoutCategory.technique,
  'TEST' => WorkoutCategory.test,
  'EB' || 'SPEED' || 'SPRINT' => WorkoutCategory.power,
  'VO2' || 'ANAEROB' || 'OVERUNDER' || 'THRESHOLD' => WorkoutCategory.intervals,
  _ => WorkoutCategory.endurance,
};
