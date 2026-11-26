/// Eine Einheit so zusammenfassen, dass ein Mensch sie vor dem Start liest.
///
/// E11 hat einundvierzig Schritte. Einundvierzig Zeilen sind keine Antwort auf
/// die Frage «was trainiere ich da?». Was ein Trainer sagen würde, ist
/// «zehn Minuten einfahren, dann zwei mal acht mal eine Minute hart» — also
/// Wiederholungen als Wiederholungen.
library;

import 'workout_engine.dart';
import 'workout_library.dart';

/// Ein zusammengefasster Abschnitt einer Einheit.
class BlueprintOutlineGroup {
  const BlueprintOutlineGroup({
    required this.repeats,
    required this.steps,
    required this.originalSteps,
  });

  /// Wie oft [steps] hintereinander vorkommen.
  final int repeats;

  /// Der Zyklus: ein Schritt, oder ein Paar aus Belastung und Erholung.
  final List<BlueprintStep> steps;

  /// All occurrences, including repetition-specific instructions. A compact
  /// outline must not discard a note merely because its targets repeat.
  final List<BlueprintStep> originalSteps;

  bool get hasVaryingNotes => originalSteps.indexed.any(
    (entry) => entry.$2.note != steps[entry.$1 % steps.length].note,
  );

  int get totalSeconds =>
      repeats * steps.fold(0, (sum, step) => sum + step.seconds);
}

/// Fasst gleiche und abwechselnde Schritte zusammen.
///
/// Erkannt werden Zyklen der Länge eins («drei mal fünf Minuten Technik») und
/// zwei («sechs mal dreißig Sekunden zügig, eine Minute locker»). Längere
/// Muster werden nicht geraten: Sie stehen dann einzeln da, und das ist
/// ehrlicher als eine falsche Klammer.
List<BlueprintOutlineGroup> outlineOf(List<BlueprintStep> steps) {
  bool same(BlueprintStep a, BlueprintStep b) =>
      a.kind == b.kind &&
      a.intensity == b.intensity &&
      a.powerTargetMode == b.powerTargetMode &&
      a.customPercent?.minimum == b.customPercent?.minimum &&
      a.customPercent?.maximum == b.customPercent?.maximum &&
      a.fixedWatts?.minimum == b.fixedWatts?.minimum &&
      a.fixedWatts?.maximum == b.fixedWatts?.maximum &&
      a.heartRate?.minimum == b.heartRate?.minimum &&
      a.heartRate?.maximum == b.heartRate?.maximum &&
      a.strokeRate?.minimum == b.strokeRate?.minimum &&
      a.strokeRate?.maximum == b.strokeRate?.maximum &&
      a.editorBlockId == b.editorBlockId &&
      a.seconds == b.seconds &&
      a.completionType == b.completionType &&
      a.completionAmount == b.completionAmount;

  /// Wie oft sich der Zyklus [length] ab [start] wiederholt.
  int repeatsAt(int start, int length) {
    var count = 1;
    var next = start + length;
    while (next + length <= steps.length) {
      var matches = true;
      for (var offset = 0; offset < length; offset++) {
        if (!same(steps[start + offset], steps[next + offset])) {
          matches = false;
          break;
        }
      }
      if (!matches) break;
      count++;
      next += length;
    }
    return count;
  }

  final groups = <BlueprintOutlineGroup>[];
  var index = 0;
  while (index < steps.length) {
    // Das Paar zuerst: Belastung und Erholung gehören zusammen, auch wenn
    // die Belastung allein ebenfalls ein Zyklus waere.
    final pairRepeats = index + 1 < steps.length ? repeatsAt(index, 2) : 1;
    final singleRepeats = repeatsAt(index, 1);
    if (pairRepeats > 1 && pairRepeats >= singleRepeats) {
      groups.add(
        BlueprintOutlineGroup(
          repeats: pairRepeats,
          steps: [steps[index], steps[index + 1]],
          originalSteps: steps.sublist(index, index + pairRepeats * 2),
        ),
      );
      index += pairRepeats * 2;
      continue;
    }
    groups.add(
      BlueprintOutlineGroup(
        repeats: singleRepeats,
        steps: [steps[index]],
        originalSteps: steps.sublist(index, index + singleRepeats),
      ),
    );
    index += singleRepeats;
  }
  return groups;
}

/// «30 s», «5 min», «1:30».
String formatStepDuration(int seconds) {
  if (seconds < 60) return '$seconds s';
  if (seconds % 60 == 0) return '${seconds ~/ 60} min';
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}

/// Wie der Abschnitt heißt, wenn man ihn ansagt.
String labelOfStepKind(WorkoutStepKind kind) => switch (kind) {
  WorkoutStepKind.warmup => 'Einfahren',
  WorkoutStepKind.work => 'Belastung',
  WorkoutStepKind.recovery => 'Erholung',
  WorkoutStepKind.cooldown => 'Ausfahren',
  WorkoutStepKind.technique => 'Technik',
};
