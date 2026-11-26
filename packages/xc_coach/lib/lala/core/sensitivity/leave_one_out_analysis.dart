import 'package:xc_coach/lala/core/models/analysis_input.dart';
import 'package:xc_coach/lala/core/models/threshold_result.dart';
import 'package:xc_coach/lala/core/preprocessing/preprocessing_result.dart';
import 'package:xc_coach/lala/core/sensitivity/sensitivity_result.dart';
import 'package:xc_coach/lala/core/thresholds/threshold_method.dart';

class LeaveOneOutAnalysis {
  const LeaveOneOutAnalysis();

  SensitivityResult run({
    required AnalysisInput input,
    required PreprocessingResult preprocessing,
    required ThresholdMethod method,
    required ThresholdResult referenceResult,
  }) {
    final valid = preprocessing.sortedValidStages;
    if (valid.length < 3 || referenceResult.thresholdLoad == null) {
      return const SensitivityResult(
        successfulRuns: 0,
        failedRuns: 0,
        minimumThreshold: null,
        maximumThreshold: null,
        meanAbsoluteDeviation: null,
        medianAbsoluteShift: null,
        maxSinglePointImpact: null,
        influentialStageNumbers: <int>[],
        notes: <String>['Leave-one-out nicht anwendbar.'],
      );
    }

    final thresholdValues = <double>[];
    final stageImpacts = <int, double>{};
    var failed = 0;

    // Randpunkte definieren die Hofmann-ROIs und bleiben deshalb erhalten.
    for (var i = 1; i < valid.length - 1; i++) {
      final removed = valid[i];
      final reducedValid = <dynamic>[];
      for (var j = 0; j < valid.length; j++) {
        if (j != i) {
          reducedValid.add(valid[j]);
        }
      }

      final reducedPreprocessing = PreprocessingResult(
        rawStages: preprocessing.rawStages,
        validStages: reducedValid.cast(),
        sortedValidStages: reducedValid.cast(),
        excludedStages: preprocessing.excludedStages,
        validationErrors: preprocessing.validationErrors,
        validationWarnings: preprocessing.validationWarnings,
      );

      final result = method.calculate(input, reducedPreprocessing);
      if (result.status == ThresholdComputationStatus.success ||
          result.status == ThresholdComputationStatus.successWithWarnings) {
        if (result.thresholdLoad != null) {
          thresholdValues.add(result.thresholdLoad!);
          final impact =
              (result.thresholdLoad! - referenceResult.thresholdLoad!).abs();
          stageImpacts[removed.stageNumber] = impact;
        } else {
          failed++;
        }
      } else {
        failed++;
      }
    }

    if (thresholdValues.isEmpty) {
      return SensitivityResult(
        successfulRuns: 0,
        failedRuns: failed,
        minimumThreshold: null,
        maximumThreshold: null,
        meanAbsoluteDeviation: null,
        medianAbsoluteShift: null,
        maxSinglePointImpact: null,
        influentialStageNumbers: const <int>[],
        notes: const <String>[
          'Keine erfolgreiche Wiederholungsberechnung in Leave-one-out.',
        ],
      );
    }

    final min = thresholdValues.reduce((a, b) => a < b ? a : b);
    final max = thresholdValues.reduce((a, b) => a > b ? a : b);

    final deviations = thresholdValues
        .map((value) => (value - referenceResult.thresholdLoad!).abs())
        .toList(growable: false);
    final mad = deviations.reduce((a, b) => a + b) / deviations.length;
    final maxImpact = deviations.reduce((a, b) => a > b ? a : b);
    final sortedDeviations = List<double>.from(deviations)..sort();
    final middle = sortedDeviations.length ~/ 2;
    final median = sortedDeviations.length.isOdd
        ? sortedDeviations[middle]
        : (sortedDeviations[middle - 1] + sortedDeviations[middle]) / 2;

    final influential =
        stageImpacts.entries
            .where((entry) => entry.value >= maxImpact * 0.8)
            .map((entry) => entry.key)
            .toList(growable: false)
          ..sort();

    return SensitivityResult(
      successfulRuns: thresholdValues.length,
      failedRuns: failed,
      minimumThreshold: min,
      maximumThreshold: max,
      meanAbsoluteDeviation: mad,
      medianAbsoluteShift: median,
      maxSinglePointImpact: maxImpact,
      influentialStageNumbers: influential,
      notes: <String>[
        'Leave-one-out ist eine Robustheitspruefung und kein statistisches Konfidenzintervall.',
      ],
    );
  }
}
