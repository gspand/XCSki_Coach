/// English labels for the fixed workout library in the Mirco device trial.
/// User-created workout names remain exactly as their authors entered them.
library;

import '../app/mirco_preview.dart';
import 'workout_engine.dart';
import 'workout_library.dart';

/// Zielwerte ohne stilles Runden auf ganze Watt oder Prozent.
String formatWorkoutValue(double value) => value
    .toStringAsFixed(6)
    .replaceFirst(RegExp(r'0+$'), '')
    .replaceFirst(RegExp(r'\.$'), '');

String formatWorkoutRange(MetricRange range) => range.minimum == range.maximum
    ? formatWorkoutValue(range.minimum)
    : '${formatWorkoutValue(range.minimum)}–${formatWorkoutValue(range.maximum)}';

String previewWorkoutName(String id, String original) {
  if (!mircoPreview) return original;
  return switch (id) {
    'threshold-4x6' => '4 × 6 min Threshold',
    'vo2-30-30' => '30/30 VO2max',
    'base-45' => 'Base endurance 45 min',
    'technique-doublepoling' => 'Double poling technique',
    'power-10x15' => '10 × 15 s Max power',
    'E0_TECH_EASY' => 'E0 · Easy technique · 20 min',
    'E1_TECH_ECON' => 'E1 · Technique & economy · 25 min',
    'E2_EB_5x3' => 'E2 · Strength endurance · 5 × 3 min',
    'E2_GA2toEB_3x8' => 'E2 · Tempo to strength endurance · 3 × 8 min',
    'E3_SPEED' => 'E3 · Speed · 8 × 30 s',
    'E4_LONG_EASY' => 'E4 · Long & easy · 55 min',
    'E5_VO2_5x3' => 'E5 · VO2max · 5 × 3 min',
    'E6_BASE_I1' => 'E6 · Base endurance · 75 min',
    'E7_LONG_I2' => 'E7 · Long endurance · 3 × 25 min',
    'E8_TEMPO_I3' => 'E8 · Tempo · 3 × 15 min',
    'E9_SCHWELLE_6x10' => 'E9 · Threshold · 6 × 10 min',
    'E10_VO2_5x5' => 'E10 · VO2max · 5 × 5 min',
    'E11_ANAEROB_2x8x1' => 'E11 · Anaerobic · 2 × 8 × 1 min',
    'E12_SPRINT_12x10s' => 'E12 · Sprint · 12 × 10 s',
    'E13_OVERUNDER_4x9' => 'E13 · Over / under · 4 × 9 min',
    'E14_PROGRESSIV' => 'E14 · Progressive · 60 min',
    'E15_SKIMARA_3x30' => 'E15 · Ski marathon · 3 × 30 min',
    'FTP_TEST_20MIN' => 'FTP · 20-minute time trial',
    _ => original,
  };
}

String previewWorkoutPurpose(WorkoutBlueprint workout) {
  if (!mircoPreview) return workout.purpose;
  return switch (workout.id) {
    'threshold-4x6' => 'Build power you can sustain for about an hour.',
    'vo2-30-30' => 'Repeated high-intensity efforts with controlled technique.',
    'base-45' => 'A steady base endurance session.',
    'technique-doublepoling' =>
      'Lengthen each stroke while keeping the rate controlled.',
    'power-10x15' => 'Peak power and stroke force with full recovery.',
    'E0_TECH_EASY' =>
      'Very easy effort. Keep shoulders low and the core stable.',
    'E1_TECH_ECON' =>
      '10 min warm-up, 6 × (30 s brisk / 60 s easy), 1 min easy, 5 min cool-down.',
    'E2_EB_5x3' =>
      '10 min warm-up, 5 × (3 min strength endurance / 2 min easy), 5 min cool-down.',
    'E2_GA2toEB_3x8' =>
      'Build from tempo to strength endurance. Warm-up and cool-down adjusted to a 40-minute session.',
    'E3_SPEED' =>
      '5 min warm-up, 8 × (30 s fast / 60 s easy), 3 min cool-down.',
    'E4_LONG_EASY' =>
      '10 min easy, then 3 × (10 min diagonal / 5 min double poling).',
    'E5_VO2_5x3' =>
      'Five 3-minute efforts. Warm-up adjusted to a 35-minute session.',
    'E6_BASE_I1' =>
      'An easy I1 session. If the power is difficult to sustain, reduce resistance.',
    'E7_LONG_I2' =>
      'Three 25-minute I2 blocks with 5 min easy recovery. Keep the rhythm steady through the final block.',
    'E8_TEMPO_I3' =>
      'Controlled tempo work. Stay below threshold throughout the session.',
    'E9_SCHWELLE_6x10' =>
      'Six 10-minute threshold efforts with 2 min easy recovery. Pace the start so the final two efforts remain sustainable.',
    'E10_VO2_5x5' =>
      'Five 5-minute efforts with 3 min recovery. Aim for time near VO2max, with consistent power.',
    'E11_ANAEROB_2x8x1' =>
      'Two sets of 8 × 1 min, with 90 s recovery and 5 min between sets. Stop if technique breaks down.',
    'E12_SPRINT_12x10s' =>
      'Twelve 10-second sprints with almost 3 min recovery. The 200% reference is a display guide; the effort is maximal.',
    'E13_OVERUNDER_4x9' =>
      'Four blocks of 3 × (2 min below threshold / 1 min above). The below-threshold section is part of the effort.',
    'E14_PROGRESSIV' =>
      'One intensity level per block, without recovery between levels. Explore your training zones.',
    'E15_SKIMARA_3x30' =>
      'Three 30-minute blocks from I2 to I3, back to I2, then 2 min at I4. Simulate late-race climbs.',
    'FTP_TEST_20MIN' =>
      '8 min warm-up, 3 × (1 min brisk / 1 min easy), 5 min easy, 20-minute time trial, 10 min cool-down.',
    _ => workout.purpose,
  };
}

String previewWorkoutCategory(WorkoutCategory category) =>
    previewText(category.label, switch (category) {
      WorkoutCategory.endurance => 'Endurance',
      WorkoutCategory.intervals => 'Intervals',
      WorkoutCategory.power => 'Power',
      WorkoutCategory.technique => 'Technique',
      WorkoutCategory.test => 'Tests',
    });

String previewWorkoutIntensity(Intensity intensity) =>
    previewText(intensity.label, switch (intensity) {
      Intensity.recovery => 'Recovery',
      Intensity.base => 'Base',
      Intensity.tempo => 'Tempo',
      Intensity.threshold => 'Threshold',
      Intensity.vo2 => 'VO2max',
      Intensity.maximal => 'Maximal',
      Intensity.technique => 'Technique',
    });

String previewWorkoutStepKind(WorkoutStepKind kind) => previewText(
  switch (kind) {
    WorkoutStepKind.warmup => 'Einfahren',
    WorkoutStepKind.work => 'Belastung',
    WorkoutStepKind.recovery => 'Pause',
    WorkoutStepKind.cooldown => 'Ausfahren',
    WorkoutStepKind.technique => 'Technik',
  },
  switch (kind) {
    WorkoutStepKind.warmup => 'Warm-up',
    WorkoutStepKind.work => 'Work',
    WorkoutStepKind.recovery => 'Recovery',
    WorkoutStepKind.cooldown => 'Cool-down',
    WorkoutStepKind.technique => 'Technique',
  },
);

String? previewThresholdSource(String? source) {
  if (!mircoPreview || source == null) return source;
  if (source == 'selbst eingetragen') return 'Manual';
  if (source == 'aus der Ercolina-Diagnostik') {
    return 'From Ercolina assessment';
  }
  if (source.startsWith('aus deinen Einheiten')) return 'From your sessions';
  return source;
}

/// Only use for the fixed library, never for an athlete's free-text notes.
String previewLibraryNote(String note) {
  if (!mircoPreview) return note;
  const phrases = {
    'locker einfahren Technik sauber': 'Easy warm-up, controlled technique',
    'locker einfahren': 'Easy warm-up',
    'kurze Aktivierung': 'Short activation',
    'locker ausrollen': 'Easy recovery',
    'locker traben': 'Easy recovery',
    'vollstaendig erholen': 'Full recovery',
    'Technik halten Schulter tief': 'Maintain technique, shoulders low',
    'gleichmaessig zu Ende': 'Finish steadily',
    'ruhig und gleichmaessig': 'Easy and steady',
    'Serienpause locker': 'Easy recovery between sets',
    'letzte Pause': 'Final recovery',
    'ausfahren': 'Cool-down',
    'einfahren': 'Warm-up',
    'EB steady': 'Steady strength endurance',
    'GA2->EB': 'Tempo to strength endurance',
    'TEST 20min TT': '20-minute time trial',
    'zurueck ins Grundtempo': 'back to base pace',
    'ruhiger Rhythmus': 'steady rhythm',
    'zuegig kontrolliert': 'controlled tempo',
    'gleiche Leistung': 'same power',
    'gleicher Rhythmus': 'same rhythm',
    'Technik nicht verlieren': 'maintain technique',
    'sauber zu Ende': 'finish with clean technique',
    'Schlussanstieg': 'final climb',
    'Grundtempo': 'base pace',
    'Ende Serie': 'End of set',
    'Serie': 'Set',
    'anaerob': 'anaerobic',
    'Schwelle': 'Threshold',
    'Stufe': 'Level',
    'Dauerbereich': 'endurance',
    'zuegig': 'tempo',
    'locker': 'easy',
    'SPRINT maximal': 'Maximal sprint',
  };
  var translated = note;
  for (final entry in phrases.entries) {
    translated = translated.replaceAll(entry.key, entry.value);
  }
  return translated;
}
