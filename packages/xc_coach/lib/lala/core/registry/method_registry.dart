import 'package:xc_coach/lala/core/audit/algorithm_version.dart';
import 'package:xc_coach/lala/core/models/method_metadata.dart';
import 'package:xc_coach/lala/core/models/scientific_reference.dart';
import 'package:xc_coach/lala/core/thresholds/baseline_rise_threshold.dart';
import 'package:xc_coach/lala/core/thresholds/fixed_lactate_threshold.dart';
import 'package:xc_coach/lala/core/thresholds/threshold_method.dart';
import 'package:xc_coach/lala/core/thresholds/hofmann_ltp_method.dart';
import 'package:xc_coach/lala/core/thresholds/unavailable_threshold_method.dart';
import 'package:xc_coach/lala/core/thresholds/versioned_threshold_methods.dart';

class ThresholdMethodDefinition {
  const ThresholdMethodDefinition({
    required this.metadata,
    required this.method,
  });

  final MethodMetadata metadata;
  final ThresholdMethod method;
}

class MethodRegistry {
  MethodRegistry() : _methods = _buildDefaults();

  final List<ThresholdMethodDefinition> _methods;

  static List<ThresholdMethodDefinition> _buildDefaults() {
    final methods = <ThresholdMethodDefinition>[
      for (final target in <double>[2.0, 2.5, 3.0, 4.0])
        _definition(FixedLactateThresholdMethod(targetLactate: target)),
      _definition(
        BaselineRiseThresholdMethod(
          delta: 0.5,
          baselineDefinition: BaselineDefinition.firstValidStage,
        ),
      ),
      _definition(
        BaselineRiseThresholdMethod(
          delta: 1.0,
          baselineDefinition: BaselineDefinition.firstValidStage,
        ),
      ),
      _definition(DmaxCubicWorkloadMethod()),
      _definition(ModifiedDmaxBishopAllDataMethod()),
      _definition(LogLogWorkloadTwoLineRssMethod()),
      _definition(DickhuthLeMinDiscreteLinearMethod()),
      _definition(HofmannLtpMethod(thresholdType: ThresholdType.lt1)),
      _definition(HofmannLtpMethod(thresholdType: ThresholdType.lt2)),
      ..._unavailableDefinitions,
    ];
    if (methods
            .map((definition) => definition.metadata.methodId)
            .toSet()
            .length !=
        methods.length) {
      throw StateError('Method registry contains duplicate method IDs.');
    }
    return List.unmodifiable(methods);
  }

  static ThresholdMethodDefinition _definition(ThresholdMethod method) =>
      ThresholdMethodDefinition(metadata: method.metadata, method: method);

  static List<ThresholdMethodDefinition> get _unavailableDefinitions => [
    _unavailable(
      id: 'lt_lower.sustained_rise.v1',
      name: 'Erster nachhaltiger Laktatanstieg',
      category: ThresholdMethodCategory.lowerTransition,
      target: TargetConstruct.firstLactateRise,
      status: MethodImplementationStatus.researchRequired,
      reason:
          'Anstiegsdefinition, Rauschmodell, erforderliche Folgepunkte und der Umgang mit unregelmaessigen Stufen sind nicht quellenklar festgelegt.',
    ),
    _unavailable(
      id: 'lt_lower.log_log_breakpoint.v1',
      name: 'Log-Log-Breakpoint',
      category: ThresholdMethodCategory.breakpointModel,
      target: TargetConstruct.lowerTransition,
      status: MethodImplementationStatus.researchRequired,
      reason:
          'Logarithmierte Variablen, Regressionsmodell, Breakpoint-Suche und Nullwertbehandlung sind noch nicht aus der Originalquelle spezifiziert.',
    ),
    _unavailable(
      id: 'lt_lower.segmented_regression.v1',
      name: 'Segmentierte Regression (Framework)',
      category: ThresholdMethodCategory.breakpointModel,
      target: TargetConstruct.lowerTransition,
      status: MethodImplementationStatus.architectureOnly,
      reason:
          'Dies ist ein Framework, keine eindeutig definierte produktive Methode; jede Modellvariante braucht eine eigene ID und Quelle.',
    ),
    _unavailable(
      id: 'lt_upper.dmax.standardized.v1',
      name: 'Standardisiertes Dmax',
      category: ThresholdMethodCategory.breakpointModel,
      target: TargetConstruct.lactateTurnPoint2,
      status: MethodImplementationStatus.researchRequired,
      reason:
          'Eine eindeutige publizierte Standardisierung ist nicht dokumentiert.',
    ),
    _unavailable(
      id: 'lt_upper.dmax.modified_standardized.v1',
      name: 'Standardisiertes Modified Dmax',
      category: ThresholdMethodCategory.breakpointModel,
      target: TargetConstruct.lactateTurnPoint2,
      status: MethodImplementationStatus.researchRequired,
      reason:
          'Eine eindeutige publizierte Standardisierung ist nicht dokumentiert.',
    ),
    _unavailable(
      id: 'iat.dickhuth.v1',
      name: 'Dickhuth-IAT',
      category: ThresholdMethodCategory.upperTransition,
      target: TargetConstruct.individualAnaerobicThreshold,
      status: MethodImplementationStatus.researchRequired,
      reason:
          'Die konkrete Publikationsvariante, Basisbestimmung und Protokollbedingungen sind nicht festgelegt.',
    ),
    _unavailable(
      id: 'iat.stegmann.v1',
      name: 'Stegmann-IAT',
      category: ThresholdMethodCategory.upperTransition,
      target: TargetConstruct.individualAnaerobicThreshold,
      status: MethodImplementationStatus.researchRequired,
      requiresRecoverySamples: true,
      reason:
          'Standardisierte Erholungslaktatproben und die vollständige Berechnungsdefinition sind erforderlich.',
    ),
    _unavailable(
      id: 'lt_upper.segmented_regression.v1',
      name: 'Segmentierte Regression zweiter Breakpoint (Framework)',
      category: ThresholdMethodCategory.breakpointModel,
      target: TargetConstruct.upperTransition,
      status: MethodImplementationStatus.architectureOnly,
      reason:
          'Dies ist ein Framework, keine eindeutig definierte produktive Methode.',
    ),
    _unavailable(
      id: 'validation.mlss.v1',
      name: 'Maximal Lactate Steady State',
      category: ThresholdMethodCategory.validationProtocol,
      target: TargetConstruct.maximalLactateSteadyState,
      status: MethodImplementationStatus.architectureOnly,
      reason:
          'MLSS erfordert mehrere Konstantlasttests und wird nie aus einer einzelnen Stufentestkurve geschaetzt.',
    ),
    _unavailable(
      id: 'validation.vt1.v1',
      name: 'Ventilatorische Schwelle 1',
      category: ThresholdMethodCategory.validationProtocol,
      target: TargetConstruct.lowerTransition,
      status: MethodImplementationStatus.architectureOnly,
      reason:
          'VT1 wird vorerst nur als externer Spiroergometrie-Referenzwert erfasst.',
    ),
    _unavailable(
      id: 'validation.vt2.v1',
      name: 'Ventilatorische Schwelle 2',
      category: ThresholdMethodCategory.validationProtocol,
      target: TargetConstruct.upperTransition,
      status: MethodImplementationStatus.architectureOnly,
      reason:
          'VT2 wird vorerst nur als externer Spiroergometrie-Referenzwert erfasst.',
    ),
    _unavailable(
      id: 'validation.critical_power.v1',
      name: 'Critical Power',
      category: ThresholdMethodCategory.validationProtocol,
      target: TargetConstruct.upperTransition,
      status: MethodImplementationStatus.architectureOnly,
      reason:
          'Critical Power ist ein separates Leistungsmodell und nicht mit LT2 oder MLSS gleichzusetzen.',
    ),
  ];

  static ThresholdMethodDefinition _unavailable({
    required String id,
    required String name,
    required ThresholdMethodCategory category,
    required TargetConstruct target,
    required MethodImplementationStatus status,
    required String reason,
    bool requiresRecoverySamples = false,
  }) {
    final metadata = MethodMetadata(
      methodId: id,
      fullName: name,
      shortName: name,
      methodVersion: '1.0.0',
      category: category,
      targetConstruct: target,
      algorithmVersion: AlgorithmVersion(
        methodId: id,
        major: 1,
        minor: 0,
        patch: 0,
      ),
      thresholdType:
          target == TargetConstruct.lowerTransition ||
              target == TargetConstruct.firstLactateRise ||
              target == TargetConstruct.lactateTurnPoint1
          ? ThresholdType.lt1
          : ThresholdType.lt2,
      mathematicalDescription: 'Nicht produktiv: $reason',
      protocolRequirements: ProtocolRequirements(
        minimumValidStages: 0,
        requiresRecoverySamples: requiresRecoverySamples,
      ),
      interpretation: 'Keine produktive Schwellenzahl.',
      requiredInputs: const <String>[],
      minimumDataPoints: 0,
      validityRequirements: const <String>[],
      knownLimitations: <String>[reason],
      references: const <ScientificReference>[],
      implementationStatus: status,
      validationStatus: MethodValidationStatus.notValidated,
    );
    return _definition(
      UnavailableThresholdMethod(metadata: metadata, reason: reason),
    );
  }

  List<ThresholdMethod> get all =>
      List.unmodifiable(_methods.map((definition) => definition.method));

  List<ThresholdMethodDefinition> get allMethods => List.unmodifiable(_methods);

  ThresholdMethod? byId(String methodId) => findById(methodId)?.method;

  ThresholdMethodDefinition? findById(String methodId) {
    for (final definition in _methods) {
      if (definition.metadata.methodId == methodId) return definition;
    }
    return null;
  }

  List<ThresholdMethodDefinition> findByTarget(TargetConstruct target) =>
      _methods
          .where((definition) => definition.metadata.targetConstruct == target)
          .toList(growable: false);
}
