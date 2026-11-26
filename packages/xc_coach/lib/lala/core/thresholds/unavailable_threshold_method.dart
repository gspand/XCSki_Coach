import 'package:xc_coach/lala/core/models/analysis_input.dart';
import 'package:xc_coach/lala/core/models/method_metadata.dart';
import 'package:xc_coach/lala/core/models/threshold_result.dart';
import 'package:xc_coach/lala/core/preprocessing/preprocessing_result.dart';
import 'package:xc_coach/lala/core/thresholds/threshold_method.dart';

/// A documented method slot that is intentionally unavailable for production.
class UnavailableThresholdMethod implements ThresholdMethod {
  const UnavailableThresholdMethod({
    required this.metadata,
    required this.reason,
  });

  @override
  final MethodMetadata metadata;
  final String reason;

  @override
  ThresholdResult calculate(
    AnalysisInput input,
    PreprocessingResult preprocessing,
  ) {
    return ThresholdResult(
      status: ThresholdComputationStatus.notValidated,
      thresholdType: metadata.thresholdType,
      methodId: metadata.methodId,
      algorithmVersion: metadata.algorithmVersion.semanticVersion,
      applicabilityStatus: MethodApplicabilityStatus.notApplicable,
      implementationStatus: metadata.implementationStatus,
      usedStageNumbers: preprocessing.sortedValidStages
          .map((stage) => stage.stageNumber)
          .toList(growable: false),
      excludedStageNumbers: preprocessing.excludedStages
          .map((stage) => stage.stageNumber)
          .toList(growable: false),
      calculationSteps: <String>[
        'Produktive Berechnung ist deaktiviert.',
        reason,
      ],
      qualityWarnings: preprocessing.validationWarnings,
      validityViolations: <String>[reason],
      interpretation:
          'Fuer dieses Verfahren liegt derzeit keine ausreichend eindeutige und validierte Implementierung vor.',
      computedAt: DateTime.now(),
      methodDetails: <String, Object?>{
        'statusReason': metadata.implementationStatus.name,
      },
    );
  }
}
