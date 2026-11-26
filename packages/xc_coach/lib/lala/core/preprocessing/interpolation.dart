import 'package:xc_coach/lala/core/models/test_stage.dart';

class InterpolationTrace {
  const InterpolationTrace({
    required this.lowerStageNumber,
    required this.upperStageNumber,
    required this.lowerLoad,
    required this.upperLoad,
  });

  final int lowerStageNumber;
  final int upperStageNumber;
  final double lowerLoad;
  final double upperLoad;

  String get message {
    return 'Interpoliert zwischen ${lowerLoad.toStringAsFixed(1)} und ${upperLoad.toStringAsFixed(1)}.';
  }
}

class InterpolationOutcome {
  const InterpolationOutcome({
    required this.load,
    required this.lactate,
    required this.heartRate,
    required this.trace,
  });

  final double load;
  final double lactate;
  final double? heartRate;
  final InterpolationTrace trace;
}

class LinearInterpolator {
  const LinearInterpolator();

  InterpolationOutcome? atTargetLactate(
    List<TestStage> sortedValidStages,
    double targetLactate,
  ) {
    if (sortedValidStages.length < 2) {
      return null;
    }

    for (var i = 0; i < sortedValidStages.length - 1; i++) {
      final lower = sortedValidStages[i];
      final upper = sortedValidStages[i + 1];

      final minL = lower.lactate < upper.lactate
          ? lower.lactate
          : upper.lactate;
      final maxL = lower.lactate > upper.lactate
          ? lower.lactate
          : upper.lactate;

      if (targetLactate < minL || targetLactate > maxL) {
        continue;
      }

      final denominator = upper.lactate - lower.lactate;
      if (denominator.abs() < 1e-12) {
        return null;
      }

      final ratio = (targetLactate - lower.lactate) / denominator;
      final interpolatedLoad = lower.load + ratio * (upper.load - lower.load);
      final hr = _interpolateHeartRate(lower.heartRate, upper.heartRate, ratio);

      return InterpolationOutcome(
        load: interpolatedLoad,
        lactate: targetLactate,
        heartRate: hr,
        trace: InterpolationTrace(
          lowerStageNumber: lower.stageNumber,
          upperStageNumber: upper.stageNumber,
          lowerLoad: lower.load,
          upperLoad: upper.load,
        ),
      );
    }

    return null;
  }

  double? _interpolateHeartRate(int? lower, int? upper, double ratio) {
    if (lower == null || upper == null) {
      return null;
    }
    return lower + ratio * (upper - lower);
  }
}
