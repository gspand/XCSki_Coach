import 'dart:math' as math;

import 'package:xc_coach/lala/core/audit/algorithm_version.dart';
import 'package:xc_coach/lala/core/models/analysis_input.dart';
import 'package:xc_coach/lala/core/models/method_metadata.dart';
import 'package:xc_coach/lala/core/models/test_stage.dart';
import 'package:xc_coach/lala/core/models/threshold_result.dart';
import 'package:xc_coach/lala/core/preprocessing/interpolation.dart';
import 'package:xc_coach/lala/core/preprocessing/preprocessing_result.dart';
import 'package:xc_coach/lala/core/thresholds/curve_math.dart';
import 'package:xc_coach/lala/core/thresholds/threshold_method.dart';

class DmaxCubicWorkloadMethod extends _ContractMethod {
  DmaxCubicWorkloadMethod()
    : super(
        metadata: _metadata(
          id: 'DMAX_CUBIC_WORKLOAD_V1',
          name: 'Dmax (kubisch, Belastung)',
          thresholdType: ThresholdType.lt2,
          target: TargetConstruct.lactateTurnPoint2,
          minimumStages: 6,
          description:
              'Kubischer OLS-Fit aller gueltigen Punkte; maximiert wird der senkrechte Abstand zur Rohdaten-Endpunktgeraden kontinuierlich im Messintervall.',
        ),
      );

  @override
  ThresholdResult calculate(
    AnalysisInput input,
    PreprocessingResult preprocessing,
  ) => _calculateDmax(input, preprocessing, metadata, lowerBoundIndex: 0);
}

class ModifiedDmaxBishopAllDataMethod extends _ContractMethod {
  ModifiedDmaxBishopAllDataMethod()
    : super(
        metadata: _metadata(
          id: 'MODDMAX_BISHOP_ALLDATA_V1',
          name: 'Modified Dmax (Bishop, All Data)',
          thresholdType: ThresholdType.lt2,
          target: TargetConstruct.lactateTurnPoint2,
          minimumStages: 6,
          description:
              'Kubischer OLS-Fit aller gueltigen Punkte; Referenzgerade beginnt vor dem ersten Laktatanstieg ueber 0,4 mmol/l.',
        ),
      );

  @override
  ThresholdResult calculate(
    AnalysisInput input,
    PreprocessingResult preprocessing,
  ) {
    final stages = preprocessing.sortedValidStages;
    final riseIndex = List.generate(stages.length - 1, (index) => index + 1)
        .where(
          (index) => stages[index].lactate - stages[index - 1].lactate > 0.4,
        )
        .cast<int?>()
        .firstOrNull;
    if (riseIndex == null ||
        riseIndex == 1 ||
        stages.length - (riseIndex - 1) < 4) {
      return _failure(
        preprocessing,
        metadata,
        ThresholdComputationStatus.insufficientData,
        'Modified Dmax benoetigt einen nicht-fruehen Laktatanstieg >0,4 mmol/l und mindestens vier Punkte ab dem Anfangsanker.',
      );
    }
    return _calculateDmax(
      input,
      preprocessing,
      metadata,
      lowerBoundIndex: riseIndex - 1,
      details: <String, Object?>{
        'anchorRule': 'first_rise_gt_0_4_mmol_l_previous_stage',
        'anchorStageNumber': stages[riseIndex - 1].stageNumber,
      },
    );
  }
}

class LogLogWorkloadTwoLineRssMethod extends _ContractMethod {
  LogLogWorkloadTwoLineRssMethod()
    : super(
        metadata: _metadata(
          id: 'LOGLOG_WORKLOAD_TWO_LINE_RSS_V1',
          name: 'Log-Log (2 Linien, RSS)',
          thresholdType: ThresholdType.lt1,
          target: TargetConstruct.lowerTransition,
          minimumStages: 6,
          description:
              'Zwei unabhängige lineare Regressionen im logarithmierten Laktat-Belastungs-Raum mit globaler RSS-Split-Suche.',
        ),
      );

  @override
  ThresholdResult calculate(
    AnalysisInput input,
    PreprocessingResult preprocessing,
  ) {
    final stages = preprocessing.sortedValidStages;
    if (preprocessing.hasErrors || stages.length < 6) {
      return _failure(
        preprocessing,
        metadata,
        ThresholdComputationStatus.insufficientData,
        'Log-Log benoetigt mindestens sechs gueltige Punkte.',
      );
    }
    if (stages.any((stage) => stage.load <= 0 || stage.lactate <= 0)) {
      return _failure(
        preprocessing,
        metadata,
        ThresholdComputationStatus.methodNotApplicable,
        'Log-Log ist bei nicht-positiver Belastung oder nicht-positivem Laktat nicht definiert; es wird kein Offset hinzugefuegt.',
      );
    }
    final candidates = <_LogLogCandidate>[];
    for (var split = 2; split <= stages.length - 4; split++) {
      final left = stages.take(split + 1).toList();
      final right = stages.skip(split + 1).toList();
      final leftFit = LinearFit.fit(
        left.map((s) => math.log(s.load)).toList(),
        left.map((s) => math.log(s.lactate)).toList(),
      );
      final rightFit = LinearFit.fit(
        right.map((s) => math.log(s.load)).toList(),
        right.map((s) => math.log(s.lactate)).toList(),
      );
      if (leftFit == null ||
          rightFit == null ||
          rightFit.slope <= leftFit.slope ||
          (leftFit.slope - rightFit.slope).abs() < 1e-9) {
        continue;
      }
      final logLoad =
          (rightFit.intercept - leftFit.intercept) /
          (leftFit.slope - rightFit.slope);
      final load = math.exp(logLoad);
      if (load < stages[split].load || load > stages[split + 1].load) {
        continue;
      }
      final candidate = _LogLogCandidate(split, load, leftFit, rightFit);
      candidates.add(candidate);
    }
    if (candidates.isEmpty) {
      return _failure(
        preprocessing,
        metadata,
        ThresholdComputationStatus.methodNotApplicable,
        'Kein gueltiger Log-Log-Schnittpunkt innerhalb eines zulässigen Split-Intervalls gefunden.',
      );
    }
    candidates.sort((first, second) => first.rss.compareTo(second.rss));
    final best = candidates.first;
    final tied = candidates
        .where(
          (candidate) =>
              (candidate.rss - best.rss).abs() <=
              relativeEpsilon * math.max(best.rss.abs(), absoluteEpsilon) * 100,
        )
        .toList(growable: false);
    if (tied.length > 1) {
      return _failure(
        preprocessing,
        metadata,
        ThresholdComputationStatus.ambiguous,
        'Mehrere zulaessige Log-Log-Splits haben praktisch identische RSS; es wird keine willkuerliche Schwelle ausgewaehlt.',
        details: <String, Object?>{
          'candidateSplits': tied
              .map((candidate) => stages[candidate.split].stageNumber)
              .toList(),
          'bestRss': best.rss,
          'relativeRssTolerance': 1e-6,
        },
      );
    }
    final interpolation = _atLoad(stages, best.load);
    return _success(
      preprocessing,
      metadata,
      load: best.load,
      lactate: math.exp(
        best.left.intercept + best.left.slope * math.log(best.load),
      ),
      heartRate: interpolation?.heartRate,
      steps: <String>[
        'Logarithmische Transformation von Belastung und Laktat.',
        'Globale Split-Suche mit mindestens drei Punkten je Regression.',
        'Schnittpunkt der RSS-optimalen Geraden bestimmt.',
      ],
      details: <String, Object?>{
        'splitAfterStage': stages[best.split].stageNumber,
        'rss': best.rss,
        'leftSlope': best.left.slope,
        'rightSlope': best.right.slope,
        'leftIntercept': best.left.intercept,
        'rightIntercept': best.right.intercept,
        'segmentStartLoad': stages.first.load,
        'segmentEndLoad': stages.last.load,
        'logBase': 'natural',
      },
    );
  }
}

class DickhuthLeMinDiscreteLinearMethod extends _ContractMethod {
  DickhuthLeMinDiscreteLinearMethod()
    : super(
        metadata: _metadata(
          id: 'DICKHUTH_LEMIN_DISCRETE_LINEAR_V1',
          name: 'Dickhuth IANS (LE-Minimum, linear)',
          thresholdType: ThresholdType.lt2,
          target: TargetConstruct.individualAnaerobicThreshold,
          minimumStages: 3,
          description:
              'Minimum des gemessenen Laktataequi­valents Laktat/Belastung; Ziel ist das zugehörige Laktat + 1,5 mmol/l, interpoliert auf dem ansteigenden Ast.',
        ),
      );

  @override
  ThresholdResult calculate(
    AnalysisInput input,
    PreprocessingResult preprocessing,
  ) {
    final stages = preprocessing.sortedValidStages;
    if (preprocessing.hasErrors ||
        stages.length < 3 ||
        stages.any((s) => s.load <= 0)) {
      return _failure(
        preprocessing,
        metadata,
        ThresholdComputationStatus.insufficientData,
        'Dickhuth benoetigt mindestens drei gueltige Punkte mit positiver Belastung.',
      );
    }
    final equivalents = stages
        .map((stage) => _LactateEquivalent(stage, stage.lactate / stage.load))
        .toList(growable: false);
    final minimumValue = equivalents
        .map((equivalent) => equivalent.value)
        .reduce(math.min);
    final minima = equivalents
        .where(
          (equivalent) => approximatelyEqual(equivalent.value, minimumValue),
        )
        .toList(growable: false);
    if (minima.length > 1) {
      return _failure(
        preprocessing,
        metadata,
        ThresholdComputationStatus.ambiguous,
        'Mehrere Messpunkte besitzen ein numerisch gleichwertiges Laktataequi­valent-Minimum.',
        details: <String, Object?>{
          'leDefinition': 'lactate_per_workload',
          'minimumStages': minima
              .map((equivalent) => equivalent.stage.stageNumber)
              .toList(),
        },
      );
    }
    final minimum = minima.single.stage;
    final start = stages.indexOf(minimum);
    final target = minimum.lactate + 1.5;
    final interpolation = _interpolateRisingTarget(
      stages.sublist(start),
      target,
    );
    if (interpolation == null) {
      return _failure(
        preprocessing,
        metadata,
        ThresholdComputationStatus.methodNotApplicable,
        'Die Zielkonzentration Basis des Laktataequi­valent-Minimums +1,5 mmol/l wird auf dem ansteigenden Ast nicht umschlossen.',
      );
    }
    return _success(
      preprocessing,
      metadata,
      load: interpolation.load,
      lactate: target,
      heartRate: interpolation.heartRate,
      steps: <String>[
        'Laktataequi­valent fuer jeden Rohdatenpunkt berechnet.',
        'Gemessenes LE-Minimum bestimmt.',
        'Zielkonzentration Laktat am LE-Minimum + 1,5 mmol/l linear auf dem ansteigenden Ast interpoliert.',
      ],
      details: <String, Object?>{
        'leDefinition': 'lactate_per_workload',
        'leUnit': '(mmol/L)/${minimum.loadUnit}',
        'leMinimumStage': minimum.stageNumber,
        'leMinimum': minimum.lactate / minimum.load,
        'baseLactate': minimum.lactate,
        'targetLactate': target,
      },
    );
  }
}

abstract class _ContractMethod implements ThresholdMethod {
  _ContractMethod({required this.metadata});

  @override
  final MethodMetadata metadata;
}

ThresholdResult _calculateDmax(
  AnalysisInput input,
  PreprocessingResult preprocessing,
  MethodMetadata metadata, {
  required int lowerBoundIndex,
  Map<String, Object?> details = const <String, Object?>{},
}) {
  final stages = preprocessing.sortedValidStages;
  if (preprocessing.hasErrors || stages.length < 6) {
    return _failure(
      preprocessing,
      metadata,
      ThresholdComputationStatus.insufficientData,
      'Die Methode benoetigt mindestens sechs gueltige, monoton steigende Belastungspunkte.',
    );
  }
  if (stages.map((stage) => stage.loadUnit).toSet().length != 1) {
    return _failure(
      preprocessing,
      metadata,
      ThresholdComputationStatus.invalidInput,
      'Dmax akzeptiert nur eine einheitliche Belastungseinheit pro Berechnung.',
    );
  }
  final polynomial = CubicPolynomial.fit(
    stages.map((s) => s.load).toList(),
    stages.map((s) => s.lactate).toList(),
  );
  if (polynomial == null) {
    return _failure(
      preprocessing,
      metadata,
      ThresholdComputationStatus.numericalFailure,
      'Kubischer OLS-Fit ist singulaer oder numerisch nicht bestimmbar.',
    );
  }
  final first = stages[lowerBoundIndex];
  final last = stages.last;
  final a = last.lactate - first.lactate;
  final b = -(last.load - first.load);
  final c = last.load * first.lactate - last.lactate * first.load;
  final denominator = math.sqrt(a * a + b * b);
  if (denominator <= absoluteEpsilon) {
    return _failure(
      preprocessing,
      metadata,
      ThresholdComputationStatus.numericalFailure,
      'Die Dmax-Referenzgerade ist numerisch nicht definiert.',
      details: details,
    );
  }
  final coefficients = <double>[
    b * polynomial.coefficients[0] + c,
    a + b * polynomial.coefficients[1],
    b * polynomial.coefficients[2],
    b * polynomial.coefficients[3],
  ];
  final candidates = _uniqueCandidates(
    <double>[
      first.load,
      last.load,
      ...quadraticRoots(
        3 * coefficients[3],
        2 * coefficients[2],
        coefficients[1],
      ),
    ].where((load) => load >= first.load && load <= last.load),
  );
  double distance(double load) =>
      (coefficients[0] +
              coefficients[1] * load +
              coefficients[2] * load * load +
              coefficients[3] * load * load * load)
          .abs() /
      denominator;
  candidates.sort((left, right) => distance(right).compareTo(distance(left)));
  final load = candidates.first;
  final tiedCandidates = candidates
      .where(
        (candidate) => approximatelyEqual(distance(candidate), distance(load)),
      )
      .toList(growable: false);
  if (tiedCandidates.length > 1) {
    return _failure(
      preprocessing,
      metadata,
      ThresholdComputationStatus.ambiguous,
      'Mehrere Dmax-Kandidaten haben numerisch gleich grosse Distanzen.',
      details: <String, Object?>{...details, 'candidateLoads': tiedCandidates},
    );
  }
  if (approximatelyEqual(load, first.load) ||
      approximatelyEqual(load, last.load)) {
    return _failure(
      preprocessing,
      metadata,
      ThresholdComputationStatus.methodNotApplicable,
      'Das Distanzmaximum liegt am Rand des zulässigen Intervalls und wird nicht als verwertbares Dmax-Ergebnis ausgegeben.',
      details: details,
    );
  }
  final interpolation = _atLoad(stages, load);
  return _success(
    preprocessing,
    metadata,
    load: load,
    lactate: polynomial(load),
    heartRate: interpolation?.heartRate,
    steps: <String>[
      'Kubischer OLS-Fit auf allen gueltigen Rohdatenpunkten.',
      'Referenzgerade zwischen den definierten Rohdatenankern.',
      'Kontinuierliche Maximierung der senkrechten Distanz ueber stationäre Kandidaten und Intervallränder.',
    ],
    details: <String, Object?>{
      ...details,
      'xVariable': 'workload',
      'xUnit': stages.first.loadUnit,
      'yVariable': 'whole_blood_lactate',
      'yUnit': 'mmol/L',
      'fit': polynomial.coefficients,
      'anchorStartStage': first.stageNumber,
      'anchorEndStage': last.stageNumber,
      'anchorStartLoad': first.load,
      'anchorStartLactate': first.lactate,
      'anchorEndLoad': last.load,
      'anchorEndLactate': last.lactate,
      'distance': distance(load),
    },
  );
}

ThresholdResult _success(
  PreprocessingResult preprocessing,
  MethodMetadata metadata, {
  required double load,
  required double lactate,
  required double? heartRate,
  required List<String> steps,
  required Map<String, Object?> details,
}) => ThresholdResult(
  status: preprocessing.validationWarnings.isEmpty
      ? ThresholdComputationStatus.success
      : ThresholdComputationStatus.successWithWarnings,
  thresholdType: metadata.thresholdType,
  methodId: metadata.methodId,
  algorithmVersion: metadata.algorithmVersion.semanticVersion,
  applicabilityStatus: preprocessing.validationWarnings.isEmpty
      ? MethodApplicabilityStatus.applicable
      : MethodApplicabilityStatus.applicableWithWarnings,
  implementationStatus: metadata.implementationStatus,
  thresholdLoad: load,
  interpolatedLactate: lactate,
  interpolatedHeartRate: heartRate,
  usedStageNumbers: preprocessing.sortedValidStages
      .map((s) => s.stageNumber)
      .toList(),
  excludedStageNumbers: preprocessing.excludedStages
      .map((s) => s.stageNumber)
      .toList(),
  calculationSteps: steps,
  qualityWarnings: preprocessing.validationWarnings,
  validityViolations: const <String>[],
  interpretation: metadata.interpretation,
  computedAt: DateTime.now(),
  methodDetails: <String, Object?>{
    ...details,
    'formulaLatex': _formulaLatexFor(metadata.methodId),
  },
);

ThresholdResult _failure(
  PreprocessingResult preprocessing,
  MethodMetadata metadata,
  ThresholdComputationStatus status,
  String reason, {
  Map<String, Object?> details = const <String, Object?>{},
}) => ThresholdResult(
  status: status,
  thresholdType: metadata.thresholdType,
  methodId: metadata.methodId,
  algorithmVersion: metadata.algorithmVersion.semanticVersion,
  applicabilityStatus: MethodApplicabilityStatus.insufficientData,
  implementationStatus: metadata.implementationStatus,
  usedStageNumbers: preprocessing.sortedValidStages
      .map((s) => s.stageNumber)
      .toList(),
  excludedStageNumbers: preprocessing.excludedStages
      .map((s) => s.stageNumber)
      .toList(),
  calculationSteps: <String>[reason],
  qualityWarnings: preprocessing.validationWarnings,
  validityViolations: <String>[reason, ...preprocessing.validationErrors],
  interpretation: 'Kein verwertbares Ergebnis: $reason',
  computedAt: DateTime.now(),
  methodDetails: <String, Object?>{
    ...details,
    'formulaLatex': _formulaLatexFor(metadata.methodId),
  },
);

String _formulaLatexFor(String methodId) {
  switch (methodId) {
    case 'DMAX_CUBIC_WORKLOAD_V1':
    case 'MODDMAX_BISHOP_ALLDATA_V1':
      return r'p(x)=\beta_0+\beta_1x+\beta_2x^2+\beta_3x^3,\quad d(x)=\frac{|(y_n-y_0)x-(x_n-x_0)p(x)+x_ny_0-y_nx_0|}{\sqrt{(y_n-y_0)^2+(x_n-x_0)^2}}';
    case 'LOGLOG_WORKLOAD_TWO_LINE_RSS_V1':
      return r'X=\ln(x),\ Y=\ln(y),\quad X^*=\frac{b_2-b_1}{m_1-m_2},\quad x^*=\exp(X^*)';
    case 'DICKHUTH_LEMIN_DISCRETE_LINEAR_V1':
      return r'LE_i=\frac{lactate_i}{workload_i},\quad L_{target}=L_{LE\text{-}min}+1.5';
    default:
      return '';
  }
}

InterpolationOutcome? _atLoad(List<TestStage> stages, double load) {
  for (var index = 0; index < stages.length - 1; index++) {
    final lower = stages[index];
    final upper = stages[index + 1];
    if (load < lower.load || load > upper.load) continue;
    final ratio = (load - lower.load) / (upper.load - lower.load);
    return InterpolationOutcome(
      load: load,
      lactate: lower.lactate + ratio * (upper.lactate - lower.lactate),
      heartRate: lower.heartRate == null || upper.heartRate == null
          ? null
          : lower.heartRate! + ratio * (upper.heartRate! - lower.heartRate!),
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

InterpolationOutcome? _interpolateRisingTarget(
  List<TestStage> stages,
  double target,
) {
  for (var index = 0; index < stages.length - 1; index++) {
    final lower = stages[index];
    final upper = stages[index + 1];
    if (lower.lactate <= target &&
        upper.lactate >= target &&
        upper.lactate > lower.lactate) {
      final ratio = (target - lower.lactate) / (upper.lactate - lower.lactate);
      return InterpolationOutcome(
        load: lower.load + ratio * (upper.load - lower.load),
        lactate: target,
        heartRate: lower.heartRate == null || upper.heartRate == null
            ? null
            : lower.heartRate! + ratio * (upper.heartRate! - lower.heartRate!),
        trace: InterpolationTrace(
          lowerStageNumber: lower.stageNumber,
          upperStageNumber: upper.stageNumber,
          lowerLoad: lower.load,
          upperLoad: upper.load,
        ),
      );
    }
  }
  return null;
}

List<double> _uniqueCandidates(Iterable<double> values) {
  final unique = <double>[];
  for (final value in values) {
    if (!unique.any((existing) => approximatelyEqual(existing, value))) {
      unique.add(value);
    }
  }
  return unique;
}

class _LactateEquivalent {
  const _LactateEquivalent(this.stage, this.value);

  final TestStage stage;
  final double value;
}

MethodMetadata _metadata({
  required String id,
  required String name,
  required ThresholdType thresholdType,
  required TargetConstruct target,
  required int minimumStages,
  required String description,
}) => MethodMetadata(
  methodId: id,
  fullName: name,
  shortName: name,
  methodVersion: '1.0.0',
  category: ThresholdMethodCategory.breakpointModel,
  targetConstruct: target,
  algorithmVersion: AlgorithmVersion(
    methodId: id,
    major: 1,
    minor: 0,
    patch: 0,
  ),
  thresholdType: thresholdType,
  mathematicalDescription: description,
  protocolRequirements: ProtocolRequirements(
    minimumValidStages: minimumStages,
    minimumStageDurationSeconds: 120,
    supportedSports: const <String>['running', 'cycling', 'rowing'],
  ),
  interpretation:
      '$name nach versioniertem LaLa-Methodenvertrag. Nicht als direkte MLSS- oder universelle LT-Gleichsetzung interpretieren.',
  requiredInputs: const <String>[
    'workload',
    'whole_blood_lactate',
    'heartRate optional',
  ],
  minimumDataPoints: minimumStages,
  validityRequirements: const <String>[
    'Monoton steigende Belastung.',
    'Keine Extrapolation ausserhalb des Messbereichs.',
  ],
  knownLimitations: const <String>[
    'Protokoll, Belastungsinkrement und Achsenskalierung beeinflussen das Ergebnis.',
  ],
  references: const [],
  implementationStatus: MethodImplementationStatus.internallyVerified,
  validationStatus: MethodValidationStatus.provisional,
);

class _LogLogCandidate {
  const _LogLogCandidate(this.split, this.load, this.left, this.right);
  final int split;
  final double load;
  final LinearFit left;
  final LinearFit right;
  double get rss => left.rss + right.rss;
}
