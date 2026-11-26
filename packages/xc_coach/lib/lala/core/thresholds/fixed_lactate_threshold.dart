import 'package:xc_coach/lala/core/audit/algorithm_version.dart';
import 'package:xc_coach/lala/core/models/analysis_input.dart';
import 'package:xc_coach/lala/core/models/method_metadata.dart';
import 'package:xc_coach/lala/core/models/scientific_reference.dart';
import 'package:xc_coach/lala/core/models/test_protocol_metadata.dart';
import 'package:xc_coach/lala/core/models/threshold_result.dart';
import 'package:xc_coach/lala/core/preprocessing/interpolation.dart';
import 'package:xc_coach/lala/core/preprocessing/preprocessing_result.dart';
import 'package:xc_coach/lala/core/thresholds/default_applicability_evaluator.dart';
import 'package:xc_coach/lala/core/thresholds/threshold_method.dart';

class FixedLactateThresholdMethod implements ThresholdMethod {
  FixedLactateThresholdMethod({required this.targetLactate});

  final double targetLactate;
  final LinearInterpolator _interpolator = const LinearInterpolator();

  @override
  MethodMetadata get metadata => MethodMetadata(
    methodId:
        'fixed_blood_lactate.generic.v1.${targetLactate.toStringAsFixed(1).replaceAll('.', '_')}mmol',
    fullName:
        'Fixe Blutlaktatkonzentration ${targetLactate.toStringAsFixed(1)} mmol/l',
    shortName: '${targetLactate.toStringAsFixed(1)} mmol/l',
    methodVersion: '1.0.0',
    category: ThresholdMethodCategory.fixedBloodLactate,
    targetConstruct: TargetConstruct.fixedBloodLactateConcentration,
    algorithmVersion: const AlgorithmVersion(
      methodId: 'fixed_blood_lactate.generic',
      major: 1,
      minor: 0,
      patch: 0,
    ),
    // 2.0 mmol/l ist historisch die aerobe Schwelle und gehoert damit zur
    // unteren Transition. Hoehere feste Werte beschreiben die obere Transition.
    thresholdType: targetLactate <= 2.0 ? ThresholdType.lt1 : ThresholdType.lt2,
    mathematicalDescription:
        'Bestimmung der Belastung bei fixer Blutlaktatkonzentration mit linearer Interpolation ohne Extrapolation.',
    protocolRequirements: const ProtocolRequirements(
      minimumValidStages: 2,
      minimumStageDurationSeconds: 120,
      maximumStageDurationSeconds: 600,
      supportedSports: <String>['running', 'cycling', 'rowing'],
      notes: <String>[
        'Nur innerhalb des gemessenen Lastbereichs interpretieren (keine Extrapolation).',
      ],
    ),
    interpretation:
        'Fixe Laktatkonzentrationen sind Vergleichsmarker und keine automatische individuelle LT2-Definition.',
    requiredInputs: const <String>['load', 'lactate', 'heartRate optional'],
    minimumDataPoints: 2,
    validityRequirements: const <String>[
      'Mindestens ein gueltiger Punkt unterhalb der Zielkonzentration.',
      'Mindestens ein gueltiger Punkt oberhalb oder exakt auf der Zielkonzentration.',
      'Monoton steigende Belastung.',
    ],
    knownLimitations: const <String>[
      'Fixe Konzentration ist nicht gleichzusetzen mit individueller physiologischer LT2.',
      'Empfindlich gegen grosse Stufenspruenge.',
    ],
    references: const <ScientificReference>[
      ScientificReference(
        authors: 'Mader A et al.',
        title:
            'Zur Beurteilung der sportartspezifischen Ausdauerleistungsfaehigkeit',
        year: 1976,
        journal: 'Sportarzt und Sportmedizin',
        relevance:
            'Historische Grundlage fuer fixe Laktatbezuege in der Leistungsdiagnostik.',
      ),
    ],
    implementationStatus: MethodImplementationStatus.internallyVerified,
    validationStatus: MethodValidationStatus.provisional,
  );

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

    if (!targetLactate.isFinite || targetLactate <= 0) {
      return ThresholdResult(
        status: ThresholdComputationStatus.invalidInput,
        thresholdType: metadata.thresholdType,
        methodId: metadata.methodId,
        algorithmVersion: metadata.algorithmVersion.semanticVersion,
        applicabilityStatus: MethodApplicabilityStatus.notApplicable,
        implementationStatus: metadata.implementationStatus,
        usedStageNumbers: usedStages,
        excludedStageNumbers: excluded,
        calculationSteps: const <String>[
          'Zielkonzentration muss eine endliche positive Zahl sein.',
        ],
        qualityWarnings: const <String>[],
        validityViolations: const <String>['Ungueltige Zielkonzentration.'],
        interpretation:
            'Die fixe Blutlaktatkonzentration wurde nicht berechnet.',
        computedAt: DateTime.now(),
        methodDetails: <String, Object?>{'targetLactate': targetLactate},
      );
    }

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
          'targetLactate': targetLactate,
          'applicabilityWarnings': applicability.warnings,
        },
      );
    }

    final below = valid
        .where((stage) => stage.lactate < targetLactate)
        .toList(growable: false);
    final above = valid
        .where((stage) => stage.lactate >= targetLactate)
        .toList(growable: false);

    if (below.isEmpty || above.isEmpty) {
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
          'Keine gueltige Schwellenumklammerung fuer Zielkonzentration gefunden.',
        ],
        qualityWarnings: preprocessing.validationWarnings,
        validityViolations: const <String>[
          'Mindestens ein gueltiger Punkt unterhalb und oberhalb der Zielkonzentration erforderlich.',
        ],
        interpretation:
            'Fixe Laktatschwelle konnte nicht berechnet werden, da die Zielkonzentration nicht von gueltigen Messpunkten umschlossen wird.',
        computedAt: DateTime.now(),
        methodDetails: <String, Object?>{
          'targetLactate': targetLactate,
          'applicabilityWarnings': applicability.warnings,
        },
      );
    }

    final exact = valid
        .where((stage) => (stage.lactate - targetLactate).abs() < 1e-12)
        .toList(growable: false);
    if (exact.isNotEmpty) {
      final stage = exact.first;
      return ThresholdResult(
        status: preprocessing.validationWarnings.isEmpty
            ? ThresholdComputationStatus.success
            : ThresholdComputationStatus.successWithWarnings,
        thresholdType: metadata.thresholdType,
        methodId: metadata.methodId,
        algorithmVersion: metadata.algorithmVersion.semanticVersion,
        applicabilityStatus: applicability.status,
        implementationStatus: metadata.implementationStatus,
        thresholdLoad: stage.load,
        interpolatedHeartRate: stage.heartRate?.toDouble(),
        interpolatedLactate: stage.lactate,
        usedStageNumbers: usedStages,
        excludedStageNumbers: excluded,
        calculationSteps: const <String>[
          'Exakter Schwellentreffer in den Rohdaten.',
        ],
        qualityWarnings: preprocessing.validationWarnings,
        validityViolations: const <String>[],
        interpolationDetail: InterpolationDetail(
          betweenLoadLower: stage.load,
          betweenLoadUpper: stage.load,
          message:
              'Exakter Treffer bei ${stage.load.toStringAsFixed(1)} ${stage.loadUnit}.',
        ),
        interpretation:
            'Fixe Konzentration erreicht. Hinweis: Dies ist eine fixe Blutlaktatkonzentration und keine automatische physiologische LT2-Gleichsetzung.',
        computedAt: DateTime.now(),
        methodDetails: <String, Object?>{
          'targetLactate': targetLactate,
          'applicabilityWarnings': applicability.warnings,
        },
      );
    }

    final interpolated = _interpolator.atTargetLactate(valid, targetLactate);
    if (interpolated == null) {
      return ThresholdResult(
        status: ThresholdComputationStatus.numericalFailure,
        thresholdType: metadata.thresholdType,
        methodId: metadata.methodId,
        algorithmVersion: metadata.algorithmVersion.semanticVersion,
        applicabilityStatus: applicability.status,
        implementationStatus: metadata.implementationStatus,
        usedStageNumbers: usedStages,
        excludedStageNumbers: excluded,
        calculationSteps: const <String>[
          'Interpolation numerisch nicht stabil oder nicht moeglich.',
        ],
        qualityWarnings: preprocessing.validationWarnings,
        validityViolations: const <String>[
          'Lineare Interpolation konnte nicht durchgefuehrt werden.',
        ],
        interpretation: 'Keine stabile Berechnung moeglich.',
        computedAt: DateTime.now(),
        methodDetails: <String, Object?>{
          'targetLactate': targetLactate,
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
      interpolatedLactate: targetLactate,
      usedStageNumbers: usedStages,
      excludedStageNumbers: excluded,
      calculationSteps: <String>[
        'Zielkonzentration ${targetLactate.toStringAsFixed(1)} mmol/l bestimmt.',
        'Lineare Interpolation innerhalb des Messbereichs ohne Extrapolation.',
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
          'Ergebnis einer fixen Blutlaktatkonzentration. Die physiologische Einordnung muss im Gesamtkontext des Testprotokolls erfolgen.',
      computedAt: DateTime.now(),
      methodDetails: <String, Object?>{
        'targetLactate': targetLactate,
        'applicabilityWarnings': applicability.warnings,
      },
    );
  }
}
