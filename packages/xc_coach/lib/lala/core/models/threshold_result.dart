import 'package:xc_coach/lala/core/models/method_metadata.dart';
import 'package:xc_coach/lala/core/models/uncertainty_result.dart';
import 'package:xc_coach/lala/core/sensitivity/sensitivity_result.dart';

enum ThresholdComputationStatus {
  success,
  successWithWarnings,
  ambiguous,
  qualityRejected,
  insufficientData,
  invalidProtocol,
  invalidInput,
  methodNotApplicable,
  numericalFailure,
  notValidated,
}

class InterpolationDetail {
  const InterpolationDetail({
    required this.betweenLoadLower,
    required this.betweenLoadUpper,
    required this.message,
  });

  final double betweenLoadLower;
  final double betweenLoadUpper;
  final String message;
}

class ThresholdResult {
  const ThresholdResult({
    required this.status,
    required this.thresholdType,
    required this.methodId,
    required this.algorithmVersion,
    required this.usedStageNumbers,
    required this.excludedStageNumbers,
    required this.calculationSteps,
    required this.qualityWarnings,
    required this.validityViolations,
    required this.interpretation,
    required this.computedAt,
    this.applicabilityStatus,
    this.implementationStatus,
    this.thresholdLoad,
    this.interpolatedHeartRate,
    this.interpolatedLactate,
    this.interpolationDetail,
    this.uncertainty,
    this.sensitivity,
    this.methodDetails,
    this.inputDataHash,
  });

  final ThresholdComputationStatus status;
  final ThresholdType thresholdType;
  final String methodId;
  final String algorithmVersion;
  final double? thresholdLoad;
  final double? interpolatedHeartRate;
  final double? interpolatedLactate;
  final List<int> usedStageNumbers;
  final List<int> excludedStageNumbers;
  final List<String> calculationSteps;
  final List<String> qualityWarnings;
  final List<String> validityViolations;
  final InterpolationDetail? interpolationDetail;
  final UncertaintyResult? uncertainty;
  final SensitivityResult? sensitivity;
  final String interpretation;
  final DateTime computedAt;
  final MethodApplicabilityStatus? applicabilityStatus;
  final MethodImplementationStatus? implementationStatus;
  final Map<String, Object?>? methodDetails;
  final String? inputDataHash;
}
