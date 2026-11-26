import '../metrics/metrics_engine.dart';

/// A workout step ends by exactly one well-defined physical criterion.
enum CompletionType { duration, strokes, work, energy }

enum WorkoutStepKind { warmup, work, recovery, cooldown, technique }

class MetricRange {
  const MetricRange(this.minimum, this.maximum) : assert(minimum <= maximum);
  final double minimum;
  final double maximum;
  bool contains(double value) => value >= minimum && value <= maximum;
}

class WorkoutStep {
  const WorkoutStep({
    required this.id,
    required this.kind,
    required this.completionType,
    required this.target,
    this.powerWatt,
    this.heartRateBpm,
    this.strokeRatePerMinute,
    this.forceNewton,
    this.symmetryShare,
    this.relativeIntensity,
  });
  final String id;
  final WorkoutStepKind kind;
  final CompletionType completionType;
  final double target;
  final MetricRange? powerWatt;
  final MetricRange? heartRateBpm;
  final MetricRange? strokeRatePerMinute;
  final MetricRange? forceNewton;
  final MetricRange? symmetryShare;

  /// Anteil der Schwellenleistung, falls dieser Schritt relativ vorgegeben ist.
  final MetricRange? relativeIntensity;

  WorkoutStep withPowerWatt(MetricRange? powerWatt) => WorkoutStep(
    id: id,
    kind: kind,
    completionType: completionType,
    target: target,
    powerWatt: powerWatt,
    heartRateBpm: heartRateBpm,
    strokeRatePerMinute: strokeRatePerMinute,
    forceNewton: forceNewton,
    symmetryShare: symmetryShare,
    relativeIntensity: relativeIntensity,
  );
}

class WorkoutDefinition {
  const WorkoutDefinition({
    required this.id,
    required this.name,
    required this.steps,
  });
  final String id;
  final String name;
  final List<WorkoutStep> steps;

  /// Passt die Leistungsziele aller Schritte an eine neue Schwellenleistung an.
  WorkoutDefinition rescaleToThreshold(double? newThresholdWatt) =>
      WorkoutDefinition(
        id: id,
        name: name,
        steps: [
          for (final step in steps)
            if (step.relativeIntensity != null)
              step.withPowerWatt(
                newThresholdWatt == null
                    ? null
                    : MetricRange(
                        newThresholdWatt * step.relativeIntensity!.minimum,
                        newThresholdWatt * step.relativeIntensity!.maximum,
                      ),
              )
            else
              step,
        ],
      );
}

class WorkoutProgress {
  const WorkoutProgress({
    required this.stepIndex,
    required this.step,
    required this.remaining,
    required this.completed,
  });
  final int stepIndex;
  final WorkoutStep? step;
  final double remaining;
  final bool completed;
}

/// Deterministic state machine. Wall time and metric counters are injected so
/// the engine remains independent of Flutter and testable with synthetic data.
class WorkoutEngine {
  WorkoutEngine(this.workout);
  WorkoutDefinition workout;

  void updateWorkout(WorkoutDefinition newWorkout) {
    workout = newWorkout;
  }

  int _stepIndex = 0;
  int? _startedAtUs;
  int? _stepStartedAtUs;
  int _startStrokes = 0;
  double _startWorkJoule = 0;

  WorkoutProgress update({required int nowUs, required LiveMetrics metrics}) {
    if (_startedAtUs == null) {
      _startedAtUs = nowUs;
      _beginStep(nowUs, metrics);
    }
    while (_stepIndex < workout.steps.length && _isComplete(nowUs, metrics)) {
      _stepIndex++;
      if (_stepIndex < workout.steps.length) _beginStep(nowUs, metrics);
    }
    if (_stepIndex >= workout.steps.length) {
      return const WorkoutProgress(
        stepIndex: -1,
        step: null,
        remaining: 0,
        completed: true,
      );
    }
    final step = workout.steps[_stepIndex];
    return WorkoutProgress(
      stepIndex: _stepIndex,
      step: step,
      remaining: _remaining(step, nowUs, metrics),
      completed: false,
    );
  }

  void _beginStep(int nowUs, LiveMetrics metrics) {
    _stepStartedAtUs = nowUs;
    _startStrokes = metrics.strokeCount;
    _startWorkJoule = metrics.totalWorkJoule;
  }

  bool _isComplete(int nowUs, LiveMetrics metrics) {
    final step = workout.steps[_stepIndex];
    return _progress(step, nowUs, metrics) >= step.target;
  }

  double _remaining(WorkoutStep step, int nowUs, LiveMetrics metrics) =>
      (step.target - _progress(step, nowUs, metrics)).clamp(0, double.infinity);

  double _progress(WorkoutStep step, int nowUs, LiveMetrics metrics) =>
      switch (step.completionType) {
        CompletionType.duration =>
          (nowUs - _stepStartedAtUs!) / Duration.microsecondsPerSecond,
        CompletionType.strokes =>
          (metrics.strokeCount - _startStrokes).toDouble(),
        CompletionType.work ||
        CompletionType.energy => metrics.totalWorkJoule - _startWorkJoule,
      };
}
