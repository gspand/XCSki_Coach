import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:xc_coach/lala/core/analysis/heart_rate_curve_analysis.dart';
import 'package:xc_coach/lala/core/audit/analysis_audit_record.dart';
import 'package:xc_coach/lala/core/models/analysis_input.dart';
import 'package:xc_coach/lala/core/models/analysis_result.dart';
import 'package:xc_coach/lala/core/models/quality_result.dart';
import 'package:xc_coach/lala/core/models/threshold_result.dart';
import 'package:xc_coach/lala/core/preprocessing/input_validator.dart';
import 'package:xc_coach/lala/core/preprocessing/preprocessing_result.dart';
import 'package:xc_coach/lala/core/preprocessing/stage_sorter.dart';
import 'package:xc_coach/lala/core/quality/quality_assessor.dart';
import 'package:xc_coach/lala/core/quality/quality_rule.dart';
import 'package:xc_coach/lala/core/quality/rules.dart';
import 'package:xc_coach/lala/core/registry/method_registry.dart';
import 'package:xc_coach/lala/core/sensitivity/leave_one_out_analysis.dart';
import 'package:xc_coach/lala/core/uncertainty/uncertainty_model.dart';

class LactateAnalyzer {
  LactateAnalyzer({
    MethodRegistry? methodRegistry,
    InputValidator? inputValidator,
    StageSorter? stageSorter,
    QualityAssessor? qualityAssessor,
    LeaveOneOutAnalysis? leaveOneOut,
    UncertaintyModel? uncertaintyModel,
  }) : _methodRegistry = methodRegistry ?? MethodRegistry(),
       _inputValidator = inputValidator ?? const InputValidator(),
       _stageSorter = stageSorter ?? const StageSorter(),
       _qualityAssessor =
           qualityAssessor ??
           QualityAssessor(
             rules: <QualityRule>[
               MinimumValidStagesRule(),
               ExcludedPointsRule(),
               UnevenIncrementRule(),
               FallingLactateRule(),
               MissingHeartRateRule(),
             ],
           ),
       _leaveOneOut = leaveOneOut ?? const LeaveOneOutAnalysis(),
       _uncertaintyModel = uncertaintyModel ?? const UncertaintyModel();

  final MethodRegistry _methodRegistry;
  final InputValidator _inputValidator;
  final StageSorter _stageSorter;
  final QualityAssessor _qualityAssessor;
  final LeaveOneOutAnalysis _leaveOneOut;
  final UncertaintyModel _uncertaintyModel;

  AnalysisResult analyze(AnalysisInput input) {
    final inputHash = _canonicalInputHash(input);
    final validation = _inputValidator.validate(input);

    final validStages = input.stages
        .where((stage) => stage.isValid)
        .toList(growable: false);
    final sortedValid = _stageSorter.sortByStageThenTime(validStages);
    final excludedStages = input.stages
        .where((stage) => !stage.isValid)
        .toList(growable: false);

    final preprocessing = PreprocessingResult(
      rawStages: input.stages,
      validStages: validStages,
      sortedValidStages: sortedValid,
      excludedStages: excludedStages,
      validationErrors: validation.errors
          .map((it) => it.message)
          .toList(growable: false),
      validationWarnings: validation.warnings
          .map((it) => it.message)
          .toList(growable: false),
    );

    final quality = _qualityAssessor.assess(input, preprocessing);

    final results = <ThresholdResult>[];
    for (final definition in _methodRegistry.allMethods) {
      final method = definition.method;
      final baseResult = method.calculate(input, preprocessing);
      final sensitivity =
          (baseResult.status == ThresholdComputationStatus.success ||
              baseResult.status ==
                  ThresholdComputationStatus.successWithWarnings)
          ? _leaveOneOut.run(
              input: input,
              preprocessing: preprocessing,
              method: method,
              referenceResult: baseResult,
            )
          : null;

      final withSensitivity =
          (baseResult.status == ThresholdComputationStatus.success ||
              baseResult.status ==
                  ThresholdComputationStatus.successWithWarnings)
          ? ThresholdResult(
              status: baseResult.status,
              thresholdType: baseResult.thresholdType,
              methodId: baseResult.methodId,
              algorithmVersion: baseResult.algorithmVersion,
              applicabilityStatus: baseResult.applicabilityStatus,
              implementationStatus: baseResult.implementationStatus,
              thresholdLoad: baseResult.thresholdLoad,
              interpolatedHeartRate: baseResult.interpolatedHeartRate,
              interpolatedLactate: baseResult.interpolatedLactate,
              usedStageNumbers: baseResult.usedStageNumbers,
              excludedStageNumbers: baseResult.excludedStageNumbers,
              calculationSteps: baseResult.calculationSteps,
              qualityWarnings: <String>[
                ...baseResult.qualityWarnings,
                if (baseResult.methodId.startsWith('HOFMANN_GRAZ_RECON_V1') &&
                    sensitivity!.maxSinglePointImpact != null &&
                    sensitivity.maxSinglePointImpact! >
                        .05 * sortedValid.last.load)
                  'Turnpoint ist empfindlich gegenüber einem einzelnen Messwert.',
              ],
              validityViolations: baseResult.validityViolations,
              interpolationDetail: baseResult.interpolationDetail,
              sensitivity: sensitivity,
              uncertainty: null,
              interpretation: baseResult.interpretation,
              computedAt: baseResult.computedAt,
              methodDetails: baseResult.methodDetails,
              inputDataHash: baseResult.inputDataHash,
            )
          : baseResult;

      final uncertainty = _uncertaintyModel.build(
        result: withSensitivity,
        hasMissingHeartRate: sortedValid.any(
          (stage) => stage.heartRate == null,
        ),
      );

      results.add(
        ThresholdResult(
          status: withSensitivity.status,
          thresholdType: withSensitivity.thresholdType,
          methodId: withSensitivity.methodId,
          algorithmVersion: withSensitivity.algorithmVersion,
          applicabilityStatus: withSensitivity.applicabilityStatus,
          implementationStatus: withSensitivity.implementationStatus,
          thresholdLoad: withSensitivity.thresholdLoad,
          interpolatedHeartRate: withSensitivity.interpolatedHeartRate,
          interpolatedLactate: withSensitivity.interpolatedLactate,
          usedStageNumbers: withSensitivity.usedStageNumbers,
          excludedStageNumbers: withSensitivity.excludedStageNumbers,
          calculationSteps: withSensitivity.calculationSteps,
          qualityWarnings: withSensitivity.qualityWarnings,
          validityViolations: withSensitivity.validityViolations,
          interpolationDetail: withSensitivity.interpolationDetail,
          sensitivity: withSensitivity.sensitivity,
          uncertainty: uncertainty,
          interpretation: withSensitivity.interpretation,
          computedAt: withSensitivity.computedAt,
          methodDetails: withSensitivity.methodDetails,
          inputDataHash: inputHash,
        ),
      );
    }

    final heartRateCurveAnalysis = const HeartRateCurveAnalysisService()
        .analyze(stages: sortedValid, thresholdResults: results);
    final audit = _buildAuditRecord(
      input: input,
      preprocessing: preprocessing,
      quality: quality,
      results: results,
      heartRateCurveAnalysis: heartRateCurveAnalysis,
      inputHash: inputHash,
    );

    return AnalysisResult(
      validationErrors: preprocessing.validationErrors,
      validationWarnings: preprocessing.validationWarnings,
      qualityResult: quality,
      thresholdResults: results,
      heartRateCurveAnalysis: heartRateCurveAnalysis,
      auditRecord: audit,
    );
  }

  AnalysisAuditRecord _buildAuditRecord({
    required AnalysisInput input,
    required PreprocessingResult preprocessing,
    required QualityResult quality,
    required List<ThresholdResult> results,
    required HeartRateCurveAnalysis heartRateCurveAnalysis,
    required String inputHash,
  }) {
    final methodIds = results
        .map((result) => result.methodId)
        .toList(growable: false);
    final versions = _methodRegistry.allMethods
        .where((method) => methodIds.contains(method.metadata.methodId))
        .map((method) => method.metadata.algorithmVersion)
        .toList(growable: false);

    return AnalysisAuditRecord(
      inputHash: inputHash,
      originalInputPoints: input.stages
          .map((stage) => stage.toJson())
          .toList(growable: false),
      testId: input.testId,
      timestamp: input.analysisTimestamp ?? DateTime.now(),
      methodIds: methodIds,
      algorithmVersions: versions,
      parameters: <String, Object?>{
        'interpolation': 'linear_no_extrapolation',
        'heartRateCurveAnalysis': heartRateCurveAnalysis.toJson(),
      },
      includedStageNumbers: preprocessing.sortedValidStages
          .map((stage) => stage.stageNumber)
          .toList(growable: false),
      excludedStageNumbers: preprocessing.excludedStages
          .map((stage) => stage.stageNumber)
          .toList(growable: false),
      validationErrors: preprocessing.validationErrors,
      validationWarnings: preprocessing.validationWarnings,
      qualityMessages: quality.findings
          .map((finding) => finding.message)
          .toList(growable: false),
      resultSummary: <String, Object?>{
        for (final result in results)
          result.methodId: {
            'status': result.status.name,
            'thresholdLoad': result.thresholdLoad,
            'algorithmVersion': result.algorithmVersion,
          },
        'heartRateCurveAnalysis': heartRateCurveAnalysis.toJson(),
      },
      errors: results
          .where(
            (result) =>
                result.status != ThresholdComputationStatus.success &&
                result.status != ThresholdComputationStatus.successWithWarnings,
          )
          .map((result) => '${result.methodId}: ${result.interpretation}')
          .toList(growable: false),
      warnings: results
          .expand((result) => result.qualityWarnings)
          .toSet()
          .toList(growable: false),
    );
  }

  String _canonicalInputHash(AnalysisInput input) {
    final canonicalStages = List.of(input.stages)
      ..sort((first, second) {
        final stageComparison = first.stageNumber.compareTo(second.stageNumber);
        if (stageComparison != 0) {
          return stageComparison;
        }
        return first.load.compareTo(second.load);
      });
    final canonicalInput = <String, Object?>{
      'testId': input.testId,
      'sportType': input.sportType,
      'protocolName': input.protocolName,
      'stageIncrementHint': input.stageIncrementHint,
      'stages': canonicalStages.map((stage) => stage.toJson()).toList(),
    };
    return sha256.convert(utf8.encode(jsonEncode(canonicalInput))).toString();
  }
}
