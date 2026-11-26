import 'package:xc_coach/lala/core/audit/algorithm_version.dart';
import 'package:xc_coach/lala/core/models/analysis_input.dart';
import 'package:xc_coach/lala/core/models/method_metadata.dart';
import 'package:xc_coach/lala/core/models/scientific_reference.dart';
import 'package:xc_coach/lala/core/models/test_stage.dart';
import 'package:xc_coach/lala/core/models/test_protocol_metadata.dart';
import 'package:xc_coach/lala/core/models/threshold_result.dart';
import 'package:xc_coach/lala/core/preprocessing/interpolation.dart';
import 'package:xc_coach/lala/core/preprocessing/preprocessing_result.dart';
import 'package:xc_coach/lala/core/thresholds/default_applicability_evaluator.dart';
import 'package:xc_coach/lala/core/thresholds/threshold_method.dart';

enum BaselineDefinition {
  firstValidStage,
  minimumValidLactate,
  meanOfFirstTwoValidStages,
  meanOfStableEarlyStages,
  manuallyDefined,
}

class BaselineRiseThresholdMethod implements ThresholdMethod {
  BaselineRiseThresholdMethod({
    required this.delta,
    required this.baselineDefinition,
    this.manualBaseline,
  });

  final double delta;
  final BaselineDefinition baselineDefinition;
  final double? manualBaseline;
  final LinearInterpolator _interpolator = const LinearInterpolator();

  @override
  MethodMetadata get metadata {
    final idSuffix = delta.toStringAsFixed(1).replaceAll('.', '_');
    return MethodMetadata(
      methodId: 'lt_lower.baseline_plus_$idSuffix.v1',
      fullName: 'Basislaktat + ${delta.toStringAsFixed(1)} mmol/l',
      shortName: 'Basis +${delta.toStringAsFixed(1)}',
      methodVersion: '1.0.0',
      category: ThresholdMethodCategory.lowerTransition,
      targetConstruct: TargetConstruct.lowerTransition,
      algorithmVersion: const AlgorithmVersion(
        methodId: 'lt1.baseline_plus',
        major: 1,
        minor: 0,
        patch: 0,
      ),
      thresholdType: ThresholdType.lt1,
      mathematicalDescription:
          'Bestimmung der Belastung beim Schnittpunkt mit Basislaktat + Delta mittels linearer Interpolation ohne Extrapolation.',
      protocolRequirements: const ProtocolRequirements(
        minimumValidStages: 2,
        minimumStageDurationSeconds: 120,
        supportedSports: <String>['running', 'cycling', 'rowing'],
      ),
      interpretation:
          'Das Ergebnis haengt direkt von der Baseline-Definition ab und ist nur mit dokumentierter Baseline vergleichbar.',
      requiredInputs: const <String>['load', 'lactate', 'heartRate optional'],
      minimumDataPoints: 2,
      validityRequirements: const <String>[
        'Mindestens zwei gueltige Messpunkte.',
        'Monoton steigende Belastung.',
        'Dokumentierte Baseline-Definition.',
      ],
      knownLimitations: const <String>[
        'Baseline-Definition beeinflusst Ergebnis stark.',
        'Keine direkte Aussage ueber individuellen metabolischen Uebergang ohne Kontext.',
      ],
      references: const <ScientificReference>[
        ScientificReference(
          authors: 'Stegmann H, Kindermann W, Schnabel A',
          title: 'Lactate kinetics and individual anaerobic threshold',
          year: 1981,
          journal: 'International Journal of Sports Medicine',
          relevance:
              'Methodischer Hintergrund fuer individualisierte Schwellenableitungen.',
        ),
      ],
      implementationStatus:
          baselineDefinition == BaselineDefinition.meanOfStableEarlyStages
          ? MethodImplementationStatus.researchRequired
          : MethodImplementationStatus.internallyVerified,
      validationStatus: MethodValidationStatus.provisional,
    );
  }

  @override
  ThresholdResult calculate(
    AnalysisInput input,
    PreprocessingResult preprocessing,
  ) {
    final protocol = TestProtocolMetadata(
      sportType: input.sportType,
      stageDurationSeconds: preprocessing.sortedValidStages.isNotEmpty
          ? preprocessing.sortedValidStages.first.durationSeconds
          : null,
      plannedIncrement: input.stageIncrementHint,
    );
    final applicability = DefaultApplicabilityEvaluator(
      metadata: metadata,
    ).evaluate(input, protocol);

    final valid = preprocessing.sortedValidStages;
    final usedStages = valid
        .map((stage) => stage.stageNumber)
        .toList(growable: false);
    final excluded = preprocessing.excludedStages
        .map((stage) => stage.stageNumber)
        .toList(growable: false);

    if (preprocessing.hasErrors) {
      return ThresholdResult(
        status: ThresholdComputationStatus.invalidInput,
        thresholdType: metadata.thresholdType,
        methodId: metadata.methodId,
        algorithmVersion: metadata.algorithmVersion.semanticVersion,
        applicabilityStatus: applicability.status,
        implementationStatus: metadata.implementationStatus,
        usedStageNumbers: usedStages,
        excludedStageNumbers: excluded,
        calculationSteps: const <String>[
          'Abbruch wegen Validierungsfehlern in den Eingabedaten.',
        ],
        qualityWarnings: preprocessing.validationWarnings,
        validityViolations: preprocessing.validationErrors,
        interpretation:
            'Methode nicht berechenbar aufgrund ungueltiger Eingangsdaten.',
        computedAt: DateTime.now(),
        methodDetails: <String, Object?>{
          'baselineDefinition': baselineDefinition.name,
          'delta': delta,
          'manualBaseline': manualBaseline,
          'applicabilityWarnings': applicability.warnings,
        },
      );
    }

    if (baselineDefinition == BaselineDefinition.meanOfStableEarlyStages) {
      return ThresholdResult(
        status: ThresholdComputationStatus.notValidated,
        thresholdType: metadata.thresholdType,
        methodId: metadata.methodId,
        algorithmVersion: metadata.algorithmVersion.semanticVersion,
        applicabilityStatus: applicability.status,
        implementationStatus: metadata.implementationStatus,
        usedStageNumbers: usedStages,
        excludedStageNumbers: excluded,
        calculationSteps: const <String>[
          'Methode ist als researchRequired markiert und wird nicht automatisch berechnet.',
        ],
        qualityWarnings: preprocessing.validationWarnings,
        validityViolations: const <String>[
          'Unzureichende methodische Festlegung fuer stabile-Fruehphasen-Definition.',
        ],
        interpretation:
            'Diese Baseline-Variante ist derzeit nicht produktiv freigegeben.',
        computedAt: DateTime.now(),
        methodDetails: <String, Object?>{
          'baselineDefinition': baselineDefinition.name,
          'delta': delta,
          'manualBaseline': manualBaseline,
          'applicabilityWarnings': applicability.warnings,
        },
      );
    }

    final baselineStage = _resolveBaselineStage(valid);
    if (baselineStage == null) {
      return ThresholdResult(
        status: ThresholdComputationStatus.insufficientData,
        thresholdType: metadata.thresholdType,
        methodId: metadata.methodId,
        algorithmVersion: metadata.algorithmVersion.semanticVersion,
        applicabilityStatus: applicability.status,
        implementationStatus: metadata.implementationStatus,
        usedStageNumbers: usedStages,
        excludedStageNumbers: excluded,
        calculationSteps: const <String>[
          'Baseline konnte nicht bestimmt werden.',
        ],
        qualityWarnings: preprocessing.validationWarnings,
        validityViolations: const <String>['Keine Baseline bestimmbar.'],
        interpretation: 'Berechnung nicht moeglich.',
        computedAt: DateTime.now(),
        methodDetails: <String, Object?>{
          'baselineDefinition': baselineDefinition.name,
          'delta': delta,
          'manualBaseline': manualBaseline,
          'applicabilityWarnings': applicability.warnings,
        },
      );
    }

    final target = baselineStage.lactate + delta;
    final interpolated = _interpolator.atTargetLactate(valid, target);
    if (interpolated == null) {
      return ThresholdResult(
        status: ThresholdComputationStatus.insufficientData,
        thresholdType: metadata.thresholdType,
        methodId: metadata.methodId,
        algorithmVersion: metadata.algorithmVersion.semanticVersion,
        applicabilityStatus: applicability.status,
        implementationStatus: metadata.implementationStatus,
        usedStageNumbers: usedStages,
        excludedStageNumbers: excluded,
        calculationSteps: <String>[
          'Baseline (${_baselineDescription()}) = ${baselineStage.lactate.toStringAsFixed(2)} mmol/l.',
          'Zielwert = Baseline + Delta = ${target.toStringAsFixed(2)} mmol/l.',
        ],
        qualityWarnings: preprocessing.validationWarnings,
        validityViolations: const <String>[
          'Zielwert wird innerhalb der gueltigen Messpunkte nicht erreicht.',
        ],
        interpretation:
            'Schwelle konnte nicht berechnet werden, da Basis + Delta nicht durch gueltige Punkte umschlossen ist.',
        computedAt: DateTime.now(),
        methodDetails: <String, Object?>{
          'baselineDefinition': baselineDefinition.name,
          'baselineLactate': baselineStage.lactate,
          'delta': delta,
          'manualBaseline': manualBaseline,
          'applicabilityWarnings': applicability.warnings,
        },
      );
    }

    return ThresholdResult(
      status: preprocessing.validationWarnings.isEmpty
          ? ThresholdComputationStatus.success
          : ThresholdComputationStatus.successWithWarnings,
      thresholdType: metadata.thresholdType,
      methodId: metadata.methodId,
      algorithmVersion: metadata.algorithmVersion.semanticVersion,
      applicabilityStatus: applicability.status,
      implementationStatus: metadata.implementationStatus,
      thresholdLoad: interpolated.load,
      interpolatedHeartRate: interpolated.heartRate,
      interpolatedLactate: target,
      usedStageNumbers: usedStages,
      excludedStageNumbers: excluded,
      calculationSteps: <String>[
        'Baseline-Definition: ${_baselineDescription()}.',
        'Baseline = ${baselineStage.lactate.toStringAsFixed(2)} mmol/l.',
        'Zielwert = Baseline + ${delta.toStringAsFixed(1)} = ${target.toStringAsFixed(2)} mmol/l.',
        'Lineare Interpolation ohne Extrapolation.',
      ],
      qualityWarnings: preprocessing.validationWarnings,
      validityViolations: const <String>[],
      interpolationDetail: InterpolationDetail(
        betweenLoadLower: interpolated.trace.lowerLoad,
        betweenLoadUpper: interpolated.trace.upperLoad,
        message:
            'Schwelle bei ${interpolated.load.toStringAsFixed(1)} zwischen ${interpolated.trace.lowerLoad.toStringAsFixed(1)} und ${interpolated.trace.upperLoad.toStringAsFixed(1)} interpoliert.',
      ),
      interpretation:
          'Ergebnis gemaess dokumentierter Baseline-Definition. Andere Baseline-Definitionen koennen zu systematisch anderen Ergebnissen fuehren.',
      computedAt: DateTime.now(),
      methodDetails: <String, Object?>{
        'baselineDefinition': baselineDefinition.name,
        'baselineLactate': baselineStage.lactate,
        'delta': delta,
        'manualBaseline': manualBaseline,
        'applicabilityWarnings': applicability.warnings,
      },
    );
  }

  TestStage? _resolveBaselineStage(List<TestStage> valid) {
    if (valid.isEmpty) {
      return null;
    }

    switch (baselineDefinition) {
      case BaselineDefinition.firstValidStage:
        return valid.first;
      case BaselineDefinition.minimumValidLactate:
        return valid.reduce((a, b) => a.lactate <= b.lactate ? a : b);
      case BaselineDefinition.meanOfFirstTwoValidStages:
        if (valid.length < 2) {
          return null;
        }
        final first = valid[0];
        final second = valid[1];
        return first.copyWith(
          lactate: (first.lactate + second.lactate) / 2,
          heartRate: (first.heartRate != null && second.heartRate != null)
              ? ((first.heartRate! + second.heartRate!) / 2).round()
              : null,
        );
      case BaselineDefinition.meanOfStableEarlyStages:
        return null;
      case BaselineDefinition.manuallyDefined:
        if (manualBaseline == null) {
          return null;
        }
        return valid.first.copyWith(lactate: manualBaseline);
    }
  }

  String _baselineDescription() {
    switch (baselineDefinition) {
      case BaselineDefinition.firstValidStage:
        return 'erster gueltiger Messwert';
      case BaselineDefinition.minimumValidLactate:
        return 'niedrigster gueltiger Messwert';
      case BaselineDefinition.meanOfFirstTwoValidStages:
        return 'Mittelwert der ersten zwei gueltigen Messwerte';
      case BaselineDefinition.meanOfStableEarlyStages:
        return 'Mittelwert stabiler Fruehstufen (research required)';
      case BaselineDefinition.manuallyDefined:
        return 'manuell gesetzter Baselinewert';
    }
  }
}
