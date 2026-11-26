/// Bibliothek mit relativen Standardzielen; eigene Schritte können auch feste
/// Wattwerte tragen. Die gewählte Zielart bleibt über Speichern und Ausführen
/// erhalten.
library;

import '../coaching/training_target.dart';
import '../domain/platform.dart';
import 'workout_engine.dart';

/// Wofür eine Einheit da ist. Die fünf Fragen, nach denen jemand sucht.
enum WorkoutCategory {
  endurance('Ausdauer'),
  intervals('Intervalle'),
  power('Leistung'),
  technique('Technik'),
  test('Tests');

  const WorkoutCategory(this.label);
  final String label;
}

/// Ein Intensitätsbereich, relativ zur Schwellenleistung.
///
/// Die Anteile folgen der üblichen Dreiteilung unterhalb/um/oberhalb der
/// zweiten Schwelle. Sie sind Trainingslehre, keine Diagnostik — die Schwelle
/// selbst zu bestimmen ist LaLas Aufgabe, nicht die dieser Datei.
enum Intensity {
  recovery('Regeneration', 0.50, 0.65),
  base('Grundlage', 0.65, 0.80),
  tempo('Tempo', 0.80, 0.92),
  threshold('Schwelle', 0.95, 1.05),
  vo2('VO2max', 1.06, 1.20),
  maximal('Maximal', 1.20, 1.60),
  technique('Technik', 0.55, 0.75);

  const Intensity(this.label, this.lower, this.upper);
  final String label;

  /// Anteil der Schwellenleistung.
  final double lower;
  final double upper;

  /// Der Bereich in Watt — oder null, solange keine Schwelle bekannt ist.
  MetricRange? watts(double? thresholdWatt) => thresholdWatt == null
      ? null
      : MetricRange(thresholdWatt * lower, thresholdWatt * upper);

  /// Dieselbe Vorgabe als Trainingsziel.
  ///
  /// Damit läuft die Auflösung durch **einen** Weg
  /// ([resolveTrainingTarget](../coaching/training_target.dart)): erst das
  /// Zonenmodell, dann die Schwelle, dann keine Zahl. Die Umrechnung oben
  /// bleibt für den einfachen Fall, in dem nur eine Schwelle vorliegt und
  /// nichts aufzulösen ist.
  RelativeThresholdTarget get asTarget => RelativeThresholdTarget(
    // Die Anteile sind auf die zweite Schwelle bezogen: Sie ist die Grösse,
    // die in jeder Diagnostik vorkommt.
    threshold: ThresholdType.lt2,
    minPercent: lower,
    maxPercent: upper,
  );
}

/// Wie die Leistung eines einzelnen Schritts vorgegeben wird.
enum PowerTargetMode { preset, percentOfThreshold, fixedWatts, none }

/// Ein Schritt, wie ihn ein Mensch beschreibt: «6 Minuten an der Schwelle».
class BlueprintStep {
  const BlueprintStep({
    required this.kind,
    required this.intensity,
    required this.seconds,
    this.completionType = CompletionType.duration,
    this.completionAmount,
    this.heartRate,
    this.strokeRate,
    this.note,
    this.powerTargetMode = PowerTargetMode.preset,
    this.customPercent,
    this.fixedWatts,
    this.editorBlockId,
  }) : assert(
         completionType == CompletionType.duration ||
             (completionAmount != null && completionAmount > 0),
       ),
       assert(
         powerTargetMode != PowerTargetMode.percentOfThreshold ||
             customPercent != null,
       ),
       assert(
         powerTargetMode != PowerTargetMode.fixedWatts || fixedWatts != null,
       );

  final WorkoutStepKind kind;
  final Intensity intensity;

  /// Zeitanteil dieses Schritts. Bei zeitbasierten Schritten ist das die
  /// Zielzeit; bei Zugzahl- oder Arbeitszielen null Sekunden, weil die App
  /// keine Dauer erfinden darf.
  final int seconds;

  final CompletionType completionType;

  /// Ziel in der nativen Einheit des Kriteriums: Züge oder Joule. Bei Zeit
  /// kommt das Ziel aus [seconds].
  final double? completionAmount;

  double get target => completionType == CompletionType.duration
      ? seconds.toDouble()
      : completionAmount!;

  /// Optionaler Herzfrequenzbereich. Er bleibt unabhängig von der relativen
  /// Leistungsintensität: ein Coach kann beides oder nur eines lesen.
  final MetricRange? heartRate;

  /// Vorgabe für die Zugfrequenz, wo sie zur Aufgabe gehört — bei
  /// Technikeinheiten ist sie die Aufgabe.
  final MetricRange? strokeRate;
  final String? note;
  final PowerTargetMode powerTargetMode;

  /// Anteil der individuellen Schwelle, etwa 0,95 bis 1,05.
  final MetricRange? customPercent;

  /// Explizite, vom Trainer festgelegte Leistung in Watt.
  final MetricRange? fixedWatts;

  /// Authoring boundary only. The engine executes the flat step sequence.
  /// Explicit boundaries survive individual edits and adjacent equal blocks.
  final String? editorBlockId;

  BlueprintStep inEditorBlock(String id) => BlueprintStep(
    kind: kind,
    intensity: intensity,
    seconds: seconds,
    completionType: completionType,
    completionAmount: completionAmount,
    heartRate: heartRate,
    strokeRate: strokeRate,
    note: note,
    powerTargetMode: powerTargetMode,
    customPercent: customPercent,
    fixedWatts: fixedWatts,
    editorBlockId: id,
  );

  MetricRange? get relativePowerRange => switch (powerTargetMode) {
    PowerTargetMode.preset => MetricRange(intensity.lower, intensity.upper),
    PowerTargetMode.percentOfThreshold => customPercent,
    PowerTargetMode.fixedWatts || PowerTargetMode.none => null,
  };

  MetricRange? resolvedPowerWatt(double? thresholdWatt) {
    if (powerTargetMode == PowerTargetMode.fixedWatts) return fixedWatts;
    final range = relativePowerRange;
    if (range == null || thresholdWatt == null) return null;
    return MetricRange(
      range.minimum * thresholdWatt,
      range.maximum * thresholdWatt,
    );
  }
}

/// Eine Einheit, bevor sie jemandem gehört.
class WorkoutBlueprint {
  const WorkoutBlueprint({
    required this.id,
    required this.name,
    required this.category,
    required this.purpose,
    required this.steps,
  });

  final String id;
  final String name;
  final WorkoutCategory category;

  /// Ein Satz: wozu diese Einheit gut ist. Wer das nicht sagen kann, sollte
  /// die Einheit nicht anbieten.
  final String purpose;
  final List<BlueprintStep> steps;

  Duration get duration =>
      Duration(seconds: steps.fold(0, (sum, step) => sum + step.seconds));

  /// Die Bereiche, in denen diese Einheit arbeitet — ohne Auf- und Auslaufen.
  Set<Intensity> get intensities => {
    for (final step in steps)
      if ((step.kind == WorkoutStepKind.work ||
              step.kind == WorkoutStepKind.technique) &&
          step.powerTargetMode == PowerTargetMode.preset)
        step.intensity,
  };

  /// Wie oft der Hauptteil wiederholt wird, falls die Einheit so gebaut ist.
  int get workBlocks =>
      steps.where((step) => step.kind == WorkoutStepKind.work).length;

  /// Die ausführbare Einheit. Feste Wattziele funktionieren ohne Schwelle;
  /// relative Ziele bleiben dann ohne Wattbereich.
  WorkoutDefinition resolve({double? thresholdWatt}) => WorkoutDefinition(
    id: id,
    name: name,
    steps: [
      for (final (index, step) in steps.indexed)
        WorkoutStep(
          id: '$id.$index',
          kind: step.kind,
          completionType: step.completionType,
          target: step.target,
          powerWatt: step.resolvedPowerWatt(thresholdWatt),
          heartRateBpm: step.heartRate,
          strokeRatePerMinute: step.strokeRate,
          relativeIntensity: step.relativePowerRange,
        ),
    ],
  );
}

const _warmup = BlueprintStep(
  kind: WorkoutStepKind.warmup,
  intensity: Intensity.base,
  seconds: 600,
);
const _cooldown = BlueprintStep(
  kind: WorkoutStepKind.cooldown,
  intensity: Intensity.recovery,
  seconds: 480,
);

/// Was ohne weiteres Zutun zur Verfügung steht.
///
/// Bewusst kurz. Eine Bibliothek mit vierzig Einheiten ist keine Hilfe,
/// sondern eine zweite Entscheidung, die niemand treffen wollte.
const List<WorkoutBlueprint> workoutLibrary = [
  WorkoutBlueprint(
    id: 'threshold-4x6',
    name: '4 × 6 min Schwelle',
    category: WorkoutCategory.intervals,
    purpose: 'Hebt die Leistung, die du über eine Stunde halten kannst.',
    steps: [
      _warmup,
      _ThresholdSet.step,
      _ThresholdSet.rest,
      _ThresholdSet.step,
      _ThresholdSet.rest,
      _ThresholdSet.step,
      _ThresholdSet.rest,
      _ThresholdSet.step,
      _cooldown,
    ],
  ),
  WorkoutBlueprint(
    id: 'vo2-30-30',
    name: '30/30 VO2max',
    category: WorkoutCategory.intervals,
    purpose:
        'Bringt dich oft an die maximale Sauerstoffaufnahme, ohne dass '
        'die Technik zerfällt.',
    steps: [_warmup, ..._Repeat.thirtyThirty, _cooldown],
  ),
  WorkoutBlueprint(
    id: 'base-45',
    name: 'Grundlage 45 min',
    category: WorkoutCategory.endurance,
    purpose: 'Die Einheit, die den grössten Teil des Jahres ausmacht.',
    steps: [
      BlueprintStep(
        kind: WorkoutStepKind.work,
        intensity: Intensity.base,
        seconds: 2700,
      ),
    ],
  ),
  WorkoutBlueprint(
    id: 'technique-doublepoling',
    name: 'Doppelstock Technik',
    category: WorkoutCategory.technique,
    purpose:
        'Gleiche Arbeit bei niedrigerer Frequenz — der Zug wird länger, '
        'nicht schneller.',
    steps: [
      _warmup,
      BlueprintStep(
        kind: WorkoutStepKind.technique,
        intensity: Intensity.technique,
        seconds: 300,
        strokeRate: MetricRange(40, 46),
        note: 'Bewusst tief: der Druck kommt aus dem Rumpf.',
      ),
      BlueprintStep(
        kind: WorkoutStepKind.technique,
        intensity: Intensity.technique,
        seconds: 300,
        strokeRate: MetricRange(50, 56),
      ),
      BlueprintStep(
        kind: WorkoutStepKind.technique,
        intensity: Intensity.technique,
        seconds: 300,
        strokeRate: MetricRange(60, 68),
      ),
      _cooldown,
    ],
  ),
  WorkoutBlueprint(
    id: 'power-10x15',
    name: '10 × 15 s Maximal',
    category: WorkoutCategory.power,
    purpose: 'Spitzenleistung und Zugkraft, mit vollständiger Erholung.',
    steps: [_warmup, ..._Repeat.tenFifteen, _cooldown],
  ),
];

/// Hilfskonstrukte, damit die Liste oben lesbar bleibt.
abstract final class _ThresholdSet {
  static const step = BlueprintStep(
    kind: WorkoutStepKind.work,
    intensity: Intensity.threshold,
    seconds: 360,
  );
  static const rest = BlueprintStep(
    kind: WorkoutStepKind.recovery,
    intensity: Intensity.recovery,
    seconds: 180,
  );
}

abstract final class _Repeat {
  static const thirtyThirty = [
    _v,
    _p,
    _v,
    _p,
    _v,
    _p,
    _v,
    _p,
    _v,
    _p,
    _v,
    _p,
    _v,
    _p,
    _v,
    _p,
    _v,
    _p,
    _v,
    _p,
    _v,
    _p,
    _v,
  ];
  static const _v = BlueprintStep(
    kind: WorkoutStepKind.work,
    intensity: Intensity.vo2,
    seconds: 30,
  );
  static const _p = BlueprintStep(
    kind: WorkoutStepKind.recovery,
    intensity: Intensity.recovery,
    seconds: 30,
  );

  static const tenFifteen = [
    _m,
    _l,
    _m,
    _l,
    _m,
    _l,
    _m,
    _l,
    _m,
    _l,
    _m,
    _l,
    _m,
    _l,
    _m,
    _l,
    _m,
    _l,
    _m,
  ];
  static const _m = BlueprintStep(
    kind: WorkoutStepKind.work,
    intensity: Intensity.maximal,
    seconds: 15,
  );
  static const _l = BlueprintStep(
    kind: WorkoutStepKind.recovery,
    intensity: Intensity.recovery,
    seconds: 165,
  );
}
