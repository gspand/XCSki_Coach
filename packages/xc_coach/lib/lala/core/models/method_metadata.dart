import 'package:xc_coach/lala/core/audit/algorithm_version.dart';
import 'package:xc_coach/lala/core/models/scientific_reference.dart';

enum ThresholdType { lt1, lt2 }

enum ThresholdMethodCategory {
  lowerTransition,
  upperTransition,
  fixedBloodLactate,
  breakpointModel,
  validationProtocol,
  expertAssessment,
}

enum TargetConstruct {
  firstLactateRise,
  lowerTransition,
  upperTransition,
  fixedBloodLactateConcentration,
  lactateTurnPoint1,
  lactateTurnPoint2,
  individualAnaerobicThreshold,
  maximalLactateSteadyState,
  expertDefinedThreshold,
}

enum MethodImplementationStatus {
  architectureOnly,
  researchRequired,
  implemented,
  internallyVerified,
  externallyValidated,
  disabled,
}

enum MethodApplicabilityStatus {
  applicable,
  applicableWithWarnings,
  notApplicable,
  insufficientData,
  unsupportedProtocol,
}

enum MethodValidationStatus { validated, provisional, notValidated }

class ProtocolRequirements {
  const ProtocolRequirements({
    required this.minimumValidStages,
    this.minimumStageDurationSeconds,
    this.maximumStageDurationSeconds,
    this.requiresRecoverySamples = false,
    this.supportedSports = const <String>[],
    this.notes = const <String>[],
  });

  final int minimumValidStages;
  final int? minimumStageDurationSeconds;
  final int? maximumStageDurationSeconds;
  final bool requiresRecoverySamples;
  final List<String> supportedSports;
  final List<String> notes;
}

class MethodMetadata {
  const MethodMetadata({
    required this.methodId,
    required this.fullName,
    required this.shortName,
    required this.methodVersion,
    required this.category,
    required this.targetConstruct,
    required this.algorithmVersion,
    required this.thresholdType,
    required this.mathematicalDescription,
    required this.protocolRequirements,
    required this.interpretation,
    required this.requiredInputs,
    required this.minimumDataPoints,
    required this.validityRequirements,
    required this.knownLimitations,
    required this.references,
    required this.implementationStatus,
    required this.validationStatus,
  });

  final String methodId;
  final String fullName;
  final String shortName;
  final String methodVersion;
  final ThresholdMethodCategory category;
  final TargetConstruct targetConstruct;
  final AlgorithmVersion algorithmVersion;
  final ThresholdType thresholdType;
  final String mathematicalDescription;
  final ProtocolRequirements protocolRequirements;
  final String interpretation;
  final List<String> requiredInputs;
  final int minimumDataPoints;
  final List<String> validityRequirements;
  final List<String> knownLimitations;
  final List<ScientificReference> references;
  final MethodImplementationStatus implementationStatus;
  final MethodValidationStatus validationStatus;
}
