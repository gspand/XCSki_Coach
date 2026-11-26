import 'dart:math' as math;

import 'package:xc_coach/lala/core/audit/algorithm_version.dart';
import 'package:xc_coach/lala/core/models/analysis_input.dart';
import 'package:xc_coach/lala/core/models/method_metadata.dart';
import 'package:xc_coach/lala/core/models/test_stage.dart';
import 'package:xc_coach/lala/core/models/threshold_result.dart';
import 'package:xc_coach/lala/core/preprocessing/interpolation.dart';
import 'package:xc_coach/lala/core/preprocessing/preprocessing_result.dart';
import 'package:xc_coach/lala/core/quality/hofmann_protocol_compatibility.dart';
import 'package:xc_coach/lala/core/thresholds/curve_math.dart';
import 'package:xc_coach/lala/core/thresholds/threshold_method.dart';

const String hofmannLtpAlgorithmId = 'HOFMANN_GRAZ_RECON_V1';
const String hofmannLtp1MethodId = 'HOFMANN_GRAZ_RECON_V1_LTP1';
const String hofmannLtp2MethodId = 'HOFMANN_GRAZ_RECON_V1_LTP2';

/// Reconstructed Hofmann/Graz two-line breakpoint analysis.
///
/// This is a transparent reference implementation, not a claim of bit-exact
/// PA7Win behavior. It does not use fixed lactate concentrations.
class HofmannLtpMethod implements ThresholdMethod {
  HofmannLtpMethod({required this.thresholdType})
    : metadata = _metadataFor(thresholdType);

  final ThresholdType thresholdType;

  @override
  final MethodMetadata metadata;

  @override
  ThresholdResult calculate(
    AnalysisInput input,
    PreprocessingResult preprocessing,
  ) {
    final stages = preprocessing.sortedValidStages;
    if (preprocessing.hasErrors) {
      return _failure(
        preprocessing,
        ThresholdComputationStatus.invalidInput,
        'Eingabedaten verletzen die Voraussetzungen fuer Hofmann/Graz Turnpoint.',
      );
    }
    if (stages.isEmpty) {
      return _failure(
        preprocessing,
        ThresholdComputationStatus.insufficientData,
        'Hofmann/Graz Turnpoint benoetigt mindestens eine gueltige Belastungsstufe.',
      );
    }
    if (stages.map((stage) => stage.loadUnit).toSet().length != 1) {
      return _failure(
        preprocessing,
        ThresholdComputationStatus.invalidInput,
        'Hofmann/Graz Turnpoint akzeptiert nur eine einheitliche originale Belastungseinheit.',
      );
    }

    final firstLoad = stages.first.load;
    final maximumLoad = stages.last.load;
    final allCompatibility = HofmannProtocolCompatibility.allPublishedRois(
      stages,
    );
    final compatibility = allCompatibility['ROI_70']!;
    final ltp1RoiEnd = compatibility.roiEnd;
    if (!compatibility.historicalMethodSupported) {
      return _failure(
        preprocessing,
        ThresholdComputationStatus.methodNotApplicable,
        'Hinweis: Das gewaehlte Testprotokoll enthaelt zu wenige Belastungsstufen fuer die rekonstruierte Hofmann/Graz-Breakpointmethode; sie waere mathematisch unterbestimmt. Die Berechnung wird daher nicht durchgefuehrt.',
        details: _baseDetails(
          stages: stages,
          ltp1RoiEnd: ltp1RoiEnd,
          ltp1: _BreakpointSearch.invalid(
            'Protokollklasse C: historische Methode nicht anwendbar.',
            roiStart: firstLoad,
            roiEnd: ltp1RoiEnd,
          ),
          ltp2: null,
          compatibility: allCompatibility,
        ),
      );
    }
    if (stages.length < 6) {
      return _failure(
        preprocessing,
        ThresholdComputationStatus.insufficientData,
        'Hofmann/Graz Turnpoint benoetigt mindestens sechs gueltige Belastungsstufen.',
        details: _baseDetails(
          stages: stages,
          ltp1RoiEnd: ltp1RoiEnd,
          ltp1: _BreakpointSearch.invalid(
            'Zu wenige Gesamtstufen fuer eine robuste historische Auswertung.',
            roiStart: firstLoad,
            roiEnd: ltp1RoiEnd,
          ),
          ltp2: null,
          compatibility: allCompatibility,
        ),
      );
    }
    final ltp1Points = stages
        .where((stage) => stage.load >= firstLoad && stage.load <= ltp1RoiEnd)
        .toList(growable: false);
    final ltp1 = _findBreakpoint(
      points: ltp1Points,
      roiStart: firstLoad,
      roiEnd: ltp1RoiEnd,
      label: 'LTP1',
    );
    if (ltp1.selected == null) {
      return _failure(
        preprocessing,
        ThresholdComputationStatus.methodNotApplicable,
        'LTP1 nicht zuverlässig bestimmbar: ${ltp1.reason}',
        details: _baseDetails(
          stages: stages,
          ltp1RoiEnd: ltp1RoiEnd,
          ltp1: ltp1,
          ltp2: null,
          compatibility: allCompatibility,
        ),
      );
    }
    if (thresholdType == ThresholdType.lt1) {
      return _success(
        preprocessing: preprocessing,
        stages: stages,
        turnpoint: ltp1.selected!,
        ltp1RoiEnd: ltp1RoiEnd,
        ltp1: ltp1,
        ltp2: null,
        compatibility: allCompatibility,
      );
    }

    final ltp1Load = ltp1.selected!.load;
    final ltp2Start = stages.lastIndexWhere((stage) => stage.load <= ltp1Load);
    final ltp2Points = stages.sublist(ltp2Start);
    final ltp2 = _findBreakpoint(
      points: ltp2Points,
      roiStart: ltp2Points.first.load,
      roiEnd: maximumLoad,
      label: 'LTP2',
    );
    if (ltp2.selected == null) {
      return _failure(
        preprocessing,
        ThresholdComputationStatus.methodNotApplicable,
        'LTP2 nicht zuverlässig bestimmbar: ${ltp2.reason}',
        details: _baseDetails(
          stages: stages,
          ltp1RoiEnd: ltp1RoiEnd,
          ltp1: ltp1,
          ltp2: ltp2,
          compatibility: allCompatibility,
        ),
      );
    }
    if (ltp2.selected!.load <= ltp1Load ||
        ltp2.selected!.lactate <= ltp1.selected!.lactate) {
      return _failure(
        preprocessing,
        ThresholdComputationStatus.methodNotApplicable,
        'LTP2 muss oberhalb von LTP1 in Belastung und Laktat liegen.',
        details: _baseDetails(
          stages: stages,
          ltp1RoiEnd: ltp1RoiEnd,
          ltp1: ltp1,
          ltp2: ltp2,
          compatibility: allCompatibility,
        ),
      );
    }
    return _success(
      preprocessing: preprocessing,
      stages: stages,
      turnpoint: ltp2.selected!,
      ltp1RoiEnd: ltp1RoiEnd,
      ltp1: ltp1,
      ltp2: ltp2,
      hrtp: _findHeartRateBreakpoint(ltp2Points),
      compatibility: allCompatibility,
    );
  }

  ThresholdResult _success({
    required PreprocessingResult preprocessing,
    required List<TestStage> stages,
    required _HofmannCandidate turnpoint,
    required double ltp1RoiEnd,
    required _BreakpointSearch ltp1,
    required _BreakpointSearch? ltp2,
    _BreakpointSearch? hrtp,
    required Map<String, HofmannProtocolCompatibility> compatibility,
  }) {
    final warnings = <String>[
      ...preprocessing.validationWarnings,
      ...turnpoint.warnings,
      if ((thresholdType == ThresholdType.lt1 ? ltp1 : ltp2!)
              .iterativeRefinement?['status'] ==
          'ITERATIVE_REFINEMENT_FAILED')
        'Die iterative Verfeinerung war nicht stabil; der diskrete Breakpoint wird verwendet.',
    ];
    final interpolation = _interpolateAt(stages, turnpoint.load);
    return ThresholdResult(
      status: warnings.isEmpty
          ? ThresholdComputationStatus.success
          : ThresholdComputationStatus.successWithWarnings,
      thresholdType: thresholdType,
      methodId: metadata.methodId,
      algorithmVersion: metadata.algorithmVersion.semanticVersion,
      applicabilityStatus: warnings.isEmpty
          ? MethodApplicabilityStatus.applicable
          : MethodApplicabilityStatus.applicableWithWarnings,
      implementationStatus: metadata.implementationStatus,
      thresholdLoad: turnpoint.load,
      interpolatedLactate: turnpoint.lactate,
      interpolatedHeartRate: interpolation?.heartRate,
      usedStageNumbers: stages.map((stage) => stage.stageNumber).toList(),
      excludedStageNumbers: preprocessing.excludedStages
          .map((stage) => stage.stageNumber)
          .toList(),
      calculationSteps: <String>[
        'LTP1: Zwei-Geraden-OLS im ROI ${stages.first.load.toStringAsFixed(3)} bis ${ltp1RoiEnd.toStringAsFixed(3)} ${stages.first.loadUnit}; minimale gepoolte Residual-Standardabweichung gewaehlt.',
        if (thresholdType == ThresholdType.lt2)
          'LTP2: Neue Zwei-Geraden-OLS ab der letzten realen Stufe vor LTP1; kein synthetischer LTP1-Punkt wurde eingefuegt.',
        'Positive Steigungsaenderung, endlicher Schnittpunkt und iterative Verfeinerung wurden geprueft.',
      ],
      qualityWarnings: warnings,
      validityViolations: const <String>[],
      interpretation: metadata.interpretation,
      computedAt: DateTime.now(),
      methodDetails: <String, Object?>{
        ..._baseDetails(
          stages: stages,
          ltp1RoiEnd: ltp1RoiEnd,
          ltp1: ltp1,
          ltp2: ltp2,
          compatibility: compatibility,
        ),
        'formulaLatex':
            r'\hat L_A=a_A+b_Ax,\ \hat L_B=a_B+b_Bx,\ x_{LTP}=\frac{a_B-a_A}{b_A-b_B}',
        'selectedTurnpoint': <String, Object?>{
          ...turnpoint.toJson(),
          'analysisRoi': (thresholdType == ThresholdType.lt1 ? ltp1 : ltp2!)
              .analysisRoiToJson(),
        },
        'qualityLevel': turnpoint.qualityLevel,
        'qualityWarnings': warnings,
        if (hrtp != null) 'hrtpSearch': hrtp.toJson(),
        if (hrtp?.selected != null)
          'hrtp': <String, Object?>{
            'load': hrtp!.selected!.load,
            'heartRate': hrtp.selected!.lactate,
            'deltaHrtpLtp2':
                hrtp.selected!.load - (ltp2?.selected?.load ?? turnpoint.load),
            'relativeDifferenceToPmax':
                (hrtp.selected!.load - (ltp2?.selected?.load ?? turnpoint.load))
                    .abs() /
                stages.last.load,
            'agreement': _hrtpAgreement(
              (hrtp.selected!.load - (ltp2?.selected?.load ?? turnpoint.load))
                      .abs() /
                  stages.last.load,
            ),
          },
      },
    );
  }

  ThresholdResult _failure(
    PreprocessingResult preprocessing,
    ThresholdComputationStatus status,
    String reason, {
    Map<String, Object?> details = const <String, Object?>{},
  }) => ThresholdResult(
    status: status,
    thresholdType: thresholdType,
    methodId: metadata.methodId,
    algorithmVersion: metadata.algorithmVersion.semanticVersion,
    applicabilityStatus: MethodApplicabilityStatus.insufficientData,
    implementationStatus: metadata.implementationStatus,
    usedStageNumbers: preprocessing.sortedValidStages
        .map((stage) => stage.stageNumber)
        .toList(),
    excludedStageNumbers: preprocessing.excludedStages
        .map((stage) => stage.stageNumber)
        .toList(),
    calculationSteps: <String>[reason],
    qualityWarnings: preprocessing.validationWarnings,
    validityViolations: <String>[reason, ...preprocessing.validationErrors],
    interpretation: 'Kein verwertbares Hofmann-LTP-Ergebnis: $reason',
    computedAt: DateTime.now(),
    methodDetails: <String, Object?>{
      ...details,
      'method': hofmannLtpAlgorithmId,
      'qualityLevel': 'invalid',
      'qualityWarnings': <String>[reason],
    },
  );
}

String _hrtpAgreement(double relativeDifferenceToPmax) {
  if (relativeDifferenceToPmax <= .05) return 'HIGH_AGREEMENT';
  if (relativeDifferenceToPmax <= .10) return 'MEDIUM_AGREEMENT';
  return 'LOW_AGREEMENT';
}

_BreakpointSearch _findHeartRateBreakpoint(List<TestStage> points) {
  final heartRatePoints = points
      .where((stage) => stage.heartRate != null)
      .map((stage) => stage.copyWith(lactate: stage.heartRate!.toDouble()))
      .toList(growable: false);
  if (heartRatePoints.length < 4) {
    return _BreakpointSearch.invalid(
      'HRTP nicht bestimmbar: weniger als vier reale HF-Stufen zwischen LTP1 und Pmax.',
      roiStart: points.first.load,
      roiEnd: points.last.load,
    );
  }
  return _findBreakpoint(
    points: heartRatePoints,
    roiStart: heartRatePoints.first.load,
    roiEnd: heartRatePoints.last.load,
    label: 'HRTP',
  );
}

_BreakpointSearch _findBreakpoint({
  required List<TestStage> points,
  required double roiStart,
  required double roiEnd,
  required String label,
}) {
  if (points.length < 4) {
    return _BreakpointSearch.invalid(
      '$label-ROI enthält weniger als vier reale Belastungsstufen.',
      roiStart: roiStart,
      roiEnd: roiEnd,
    );
  }
  final increments = <double>[
    for (var index = 1; index < points.length; index++)
      points[index].load - points[index - 1].load,
  ]..sort();
  final medianIncrement = increments[increments.length ~/ 2];
  final tolerance = math.max(1e-9, 0.01 * medianIncrement);
  final accepted = <_HofmannCandidate>[];
  final rejected = <Map<String, Object?>>[];

  for (var split = 1; split <= points.length - 3; split++) {
    final left = points.sublist(0, split + 1);
    final right = points.sublist(split + 1);
    final leftFit = _regression(left);
    final rightFit = _regression(right);
    if (leftFit == null || rightFit == null) {
      rejected.add(<String, Object?>{
        'splitAfterStage': points[split].stageNumber,
        'reason': 'Regression numerisch nicht bestimmbar.',
      });
      continue;
    }
    final denominator = leftFit.slope - rightFit.slope;
    if (denominator.abs() <= absoluteEpsilon) {
      rejected.add(<String, Object?>{
        'splitAfterStage': points[split].stageNumber,
        'reason': 'Regressionsgeraden sind numerisch parallel.',
      });
      continue;
    }
    final load = (rightFit.intercept - leftFit.intercept) / denominator;
    final lactate = leftFit.intercept + leftFit.slope * load;
    final splitStart = points[split].load;
    final splitEnd = points[split + 1].load;
    if (rightFit.slope <= leftFit.slope) {
      rejected.add(<String, Object?>{
        'splitAfterStage': points[split].stageNumber,
        'reason': 'Steigungszunahme nicht positiv.',
        'leftSlope': leftFit.slope,
        'rightSlope': rightFit.slope,
      });
      continue;
    }
    if (!load.isFinite ||
        !lactate.isFinite ||
        load < roiStart - tolerance ||
        load > roiEnd + tolerance ||
        lactate <= 0) {
      rejected.add(<String, Object?>{
        'splitAfterStage': points[split].stageNumber,
        'reason': 'Schnittpunkt liegt ausserhalb der Analyse-ROI.',
        'intersectionLoad': load,
        'intersectionLactate': lactate,
        'splitStart': splitStart,
        'splitEnd': splitEnd,
      });
      continue;
    }
    accepted.add(
      _HofmannCandidate(
        left: left,
        right: right,
        leftFit: leftFit,
        rightFit: rightFit,
        load: load,
        splitStart: splitStart,
        splitEnd: splitEnd,
      ),
    );
  }
  if (accepted.isEmpty) {
    return _BreakpointSearch(
      roiStart: roiStart,
      roiEnd: roiEnd,
      candidates: const <_HofmannCandidate>[],
      rejectedCandidates: rejected,
      reason: '$label besitzt keinen zulaessigen Breakpoint-Kandidaten.',
    );
  }
  final statisticallySupported = accepted
      .where((candidate) => candidate.minimumSegmentLength >= 3)
      .toList(growable: false);
  final primaryCandidates = statisticallySupported.isEmpty
      ? accepted
      : statisticallySupported;
  primaryCandidates.sort(_compareCandidates);
  final discrete = primaryCandidates.first;
  final refinement = _iterativelyRefine(
    points: points,
    initial: discrete,
    roiStart: roiStart,
    roiEnd: roiEnd,
  );
  return _BreakpointSearch(
    roiStart: roiStart,
    roiEnd: roiEnd,
    candidates: accepted,
    rejectedCandidates: rejected,
    selectedCandidate: refinement.candidate ?? discrete,
    iterativeRefinement: refinement.toJson(),
  );
}

int _compareCandidates(_HofmannCandidate left, _HofmannCandidate right) {
  final leftPooledSd = left.pooledResidualSd;
  final rightPooledSd = right.pooledResidualSd;
  if (leftPooledSd == null && rightPooledSd != null) return 1;
  if (leftPooledSd != null && rightPooledSd == null) return -1;
  final denominator = math.max(
    math.max((leftPooledSd ?? 0).abs(), (rightPooledSd ?? 0).abs()),
    absoluteEpsilon,
  );
  if (((leftPooledSd ?? 0) - (rightPooledSd ?? 0)).abs() / denominator >
      1e-12) {
    return (leftPooledSd ?? double.infinity).compareTo(
      rightPooledSd ?? double.infinity,
    );
  }
  final segmentLength = right.minimumSegmentLength.compareTo(
    left.minimumSegmentLength,
  );
  if (segmentLength != 0) return segmentLength;
  final slopeChange = right.slopeChange.compareTo(left.slopeChange);
  if (slopeChange != 0) return slopeChange;
  return left.left.last.stageNumber.compareTo(right.left.last.stageNumber);
}

Map<String, Object?> _baseDetails({
  required List<TestStage> stages,
  required double ltp1RoiEnd,
  required _BreakpointSearch ltp1,
  required _BreakpointSearch? ltp2,
  required Map<String, HofmannProtocolCompatibility> compatibility,
}) => <String, Object?>{
  'method': hofmannLtpAlgorithmId,
  'configuration': <String, Object?>{
    'ltp1RoiFractionOfMaximum': 0.70,
    'minimumValidStages': 6,
    'minimumPointsPerRegression': 2,
    'preferredPointsPerRegression': 3,
    'relativeSseTieTolerance': 0.005,
    'requiresPositiveSlopeChange': true,
    'requiresIntersectionInsideAnalysisRoi': true,
    'ltp2RoiStartRule': 'last_real_stage_at_or_below_ltp1',
  },
  'input': <String, Object?>{
    'intensityUnit': stages.first.loadUnit,
    'validStageCount': stages.length,
    'firstStageIntensity': stages.first.load,
    'maximumCompletedIntensity': stages.last.load,
  },
  'audit': <String, Object?>{
    'excludedRestMeasurements': const <String>[],
    'excludedRecoveryMeasurements': const <String>[],
    'invalidMeasurements': const <String>[],
    'manuallyExcludedMeasurements': const <String>[],
  },
  'ltp1Roi': <String, Object?>{'start': stages.first.load, 'end': ltp1RoiEnd},
  'protocolCompatibility': <String, Object?>{
    for (final entry in compatibility.entries) entry.key: entry.value.toJson(),
  },
  'ltp1Search': ltp1.toJson(),
  if (ltp2 != null) 'ltp2Search': ltp2.toJson(),
};

class _BreakpointSearch {
  const _BreakpointSearch({
    required this.roiStart,
    required this.roiEnd,
    required this.candidates,
    required this.rejectedCandidates,
    this.selectedCandidate,
    this.iterativeRefinement,
    this.reason,
  });

  factory _BreakpointSearch.invalid(
    String reason, {
    required double roiStart,
    required double roiEnd,
  }) => _BreakpointSearch(
    roiStart: roiStart,
    roiEnd: roiEnd,
    candidates: const <_HofmannCandidate>[],
    rejectedCandidates: const <Map<String, Object?>>[],
    reason: reason,
  );

  final double roiStart;
  final double roiEnd;
  final List<_HofmannCandidate> candidates;
  final List<Map<String, Object?>> rejectedCandidates;
  final _HofmannCandidate? selectedCandidate;
  final Map<String, Object?>? iterativeRefinement;
  final String? reason;

  _HofmannCandidate? get selected =>
      selectedCandidate ?? (candidates.isEmpty ? null : candidates.first);

  Map<String, Object?> analysisRoiToJson() => <String, Object?>{
    'start': roiStart,
    'end': roiEnd,
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'analysisRoi': analysisRoiToJson(),
    'candidateCount': candidates.length + rejectedCandidates.length,
    'validCandidateCount': candidates.length,
    'acceptedCandidates': candidates
        .map((candidate) => candidate.toJson())
        .toList(growable: false),
    'selectedBreakpoint': selected?.toJson(),
    if (iterativeRefinement != null) 'iterativeRefinement': iterativeRefinement,
    'rejectedCandidates': rejectedCandidates,
    if (reason != null) 'reason': reason,
  };
}

class _HofmannCandidate {
  const _HofmannCandidate({
    required this.left,
    required this.right,
    required this.leftFit,
    required this.rightFit,
    required this.load,
    required this.splitStart,
    required this.splitEnd,
  });

  final List<TestStage> left;
  final List<TestStage> right;
  final _RegressionMetrics leftFit;
  final _RegressionMetrics rightFit;
  final double load;
  final double splitStart;
  final double splitEnd;

  double get lactate => leftFit.intercept + leftFit.slope * load;
  double get totalSse => leftFit.sse + rightFit.sse;
  double get slopeChange => rightFit.slope - leftFit.slope;
  double get slopeRatio =>
      rightFit.slope / math.max(leftFit.slope.abs(), absoluteEpsilon);
  int get minimumSegmentLength => math.min(left.length, right.length);
  int get degreesOfFreedom =>
      leftFit.degreesOfFreedom + rightFit.degreesOfFreedom;
  double? get pooledResidualSd =>
      degreesOfFreedom <= 0 ? null : math.sqrt(totalSse / degreesOfFreedom);
  double get distanceToSplitCentre =>
      (load - (splitStart + splitEnd) / 2).abs();
  String get qualityLevel => minimumSegmentLength >= 3 ? 'high' : 'low';
  List<String> get warnings => minimumSegmentLength >= 3
      ? const <String>[]
      : const <String>[
          'Mindestens eine Regression basiert nur auf zwei Punkten; der Turnpoint ist statistisch schwach.',
        ];

  Map<String, Object?> toJson() => <String, Object?>{
    'intensity': load,
    'lactate': lactate,
    'regressionCoverage': <String, Object?>{
      'start': left.first.load,
      'end': right.last.load,
    },
    // Retained for existing overlay readers; `regressionCoverage` is explicit.
    'roi': <String, Object?>{'start': left.first.load, 'end': right.last.load},
    'split': <String, Object?>{
      'leftLastStageIndex': left.last.stageNumber,
      'rightFirstStageIndex': right.first.stageNumber,
      'intervalStart': splitStart,
      'intervalEnd': splitEnd,
    },
    'leftRegression': leftFit.toJson(),
    'rightRegression': rightFit.toJson(),
    'totalSse': totalSse,
    'pooledResidualSd': pooledResidualSd,
    'leftResidualSd': leftFit.residualSd,
    'rightResidualSd': rightFit.residualSd,
    'leftDegreesOfFreedom': leftFit.degreesOfFreedom,
    'rightDegreesOfFreedom': rightFit.degreesOfFreedom,
    'slopeChange': slopeChange,
    'slopeRatio': slopeRatio,
    'distanceToNearestMeasuredStage': math.min(
      (load - splitStart).abs(),
      (splitEnd - load).abs(),
    ),
    'quality': qualityLevel,
    'warnings': warnings,
  };
}

class _RegressionMetrics {
  const _RegressionMetrics({
    required this.intercept,
    required this.slope,
    required this.sse,
    required this.rmse,
    required this.rSquared,
    required this.pointCount,
    required this.startIntensity,
    required this.endIntensity,
  });

  final double intercept;
  final double slope;
  final double sse;
  final double rmse;
  final double? rSquared;
  final int pointCount;
  final double startIntensity;
  final double endIntensity;

  int get degreesOfFreedom => pointCount - 2;
  double? get residualSd =>
      degreesOfFreedom <= 0 ? null : math.sqrt(sse / degreesOfFreedom);

  Map<String, Object?> toJson() => <String, Object?>{
    'slope': slope,
    'intercept': intercept,
    'sse': sse,
    'rmse': rmse,
    'rSquared': rSquared,
    'pointCount': pointCount,
    'degreesOfFreedom': degreesOfFreedom,
    'residualSd': residualSd,
    'startIntensity': startIntensity,
    'endIntensity': endIntensity,
  };
}

class _IterativeRefinement {
  const _IterativeRefinement({
    required this.candidate,
    required this.status,
    required this.steps,
  });

  final _HofmannCandidate? candidate;
  final String status;
  final List<Map<String, Object?>> steps;

  Map<String, Object?> toJson() => <String, Object?>{
    'status': status,
    'maxIterations': 100,
    'steps': steps,
  };
}

_IterativeRefinement _iterativelyRefine({
  required List<TestStage> points,
  required _HofmannCandidate initial,
  required double roiStart,
  required double roiEnd,
}) {
  var current = initial;
  final tolerance = 1e-8 * math.max(1, roiEnd - roiStart);
  final seenAssignments = <String>{};
  final steps = <Map<String, Object?>>[];
  for (var iteration = 1; iteration <= 100; iteration++) {
    final left = points.where((point) => point.load <= current.load).toList();
    final right = points.where((point) => point.load >= current.load).toList();
    final assignment =
        '${left.map((point) => point.stageNumber).join(',')}|${right.map((point) => point.stageNumber).join(',')}';
    if (!seenAssignments.add(assignment)) {
      return _IterativeRefinement(
        candidate: iteration == 1 ? current : null,
        status: iteration == 1 ? 'CONVERGED' : 'ITERATIVE_REFINEMENT_FAILED',
        steps: steps,
      );
    }
    final refit = _candidateFromGroups(
      left: left,
      right: right,
      roiStart: roiStart,
      roiEnd: roiEnd,
    );
    if (refit == null) {
      return _IterativeRefinement(
        candidate: null,
        status: 'ITERATIVE_REFINEMENT_FAILED',
        steps: steps,
      );
    }
    final shift = (refit.load - current.load).abs();
    steps.add(<String, Object?>{
      'iteration': iteration,
      'previousIntersection': current.load,
      'newIntersection': refit.load,
      'absoluteShift': shift,
      'tolerance': tolerance,
      'leftStageNumbers': left.map((point) => point.stageNumber).toList(),
      'rightStageNumbers': right.map((point) => point.stageNumber).toList(),
    });
    if (shift < tolerance) {
      return _IterativeRefinement(
        candidate: refit,
        status: 'CONVERGED',
        steps: steps,
      );
    }
    current = refit;
  }
  return _IterativeRefinement(
    candidate: null,
    status: 'ITERATIVE_REFINEMENT_FAILED',
    steps: steps,
  );
}

_HofmannCandidate? _candidateFromGroups({
  required List<TestStage> left,
  required List<TestStage> right,
  required double roiStart,
  required double roiEnd,
}) {
  if (left.length < 2 || right.length < 2) return null;
  final leftFit = _regression(left);
  final rightFit = _regression(right);
  if (leftFit == null || rightFit == null || rightFit.slope <= leftFit.slope) {
    return null;
  }
  final denominator = leftFit.slope - rightFit.slope;
  if (denominator.abs() < 1e-12) return null;
  final load = (rightFit.intercept - leftFit.intercept) / denominator;
  final lactate = leftFit.intercept + leftFit.slope * load;
  if (!load.isFinite ||
      !lactate.isFinite ||
      load < roiStart ||
      load > roiEnd ||
      lactate <= 0) {
    return null;
  }
  return _HofmannCandidate(
    left: left,
    right: right,
    leftFit: leftFit,
    rightFit: rightFit,
    load: load,
    splitStart: left.last.load,
    splitEnd: right.first.load,
  );
}

_RegressionMetrics? _regression(List<TestStage> points) {
  final fit = LinearFit.fit(
    points.map((point) => point.load).toList(),
    points.map((point) => point.lactate).toList(),
  );
  if (fit == null) return null;
  final mean =
      points.map((point) => point.lactate).reduce((a, b) => a + b) /
      points.length;
  final totalSumSquares = points.fold(
    0.0,
    (sum, point) => sum + math.pow(point.lactate - mean, 2),
  );
  return _RegressionMetrics(
    intercept: fit.intercept,
    slope: fit.slope,
    sse: fit.rss,
    rmse: math.sqrt(fit.rss / points.length),
    rSquared: totalSumSquares <= absoluteEpsilon
        ? null
        : 1 - fit.rss / totalSumSquares,
    pointCount: points.length,
    startIntensity: points.first.load,
    endIntensity: points.last.load,
  );
}

InterpolationOutcome? _interpolateAt(List<TestStage> stages, double load) {
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

MethodMetadata _metadataFor(ThresholdType type) {
  final isLtp1 = type == ThresholdType.lt1;
  return MethodMetadata(
    methodId: isLtp1 ? hofmannLtp1MethodId : hofmannLtp2MethodId,
    fullName:
        'Hofmann/Graz Turnpoint – rekonstruierte lineare Breakpoint-Methode (${isLtp1 ? 'LTP1' : 'LTP2'})',
    shortName: isLtp1 ? 'Hofmann/Graz LTP1' : 'Hofmann/Graz LTP2',
    methodVersion: '1.0.0',
    category: ThresholdMethodCategory.breakpointModel,
    targetConstruct: isLtp1
        ? TargetConstruct.lactateTurnPoint1
        : TargetConstruct.lactateTurnPoint2,
    algorithmVersion: const AlgorithmVersion(
      methodId: hofmannLtpAlgorithmId,
      major: 1,
      minor: 0,
      patch: 0,
    ),
    thresholdType: type,
    mathematicalDescription:
        'Rekonstruierte Zwei-Geraden-OLS-Breakpoint-Analyse mit minimaler gepoolter Residual-Standardabweichung: LTP1 bis 70 % der Maximalintensitaet, LTP2 ab der letzten realen Stufe vor LTP1. Die Methode beansprucht keine bitgenaue PA7Win-Reproduktion.',
    protocolRequirements: const ProtocolRequirements(
      minimumValidStages: 4,
      minimumStageDurationSeconds: 120,
      supportedSports: <String>['running', 'cycling', 'rowing'],
    ),
    interpretation:
        'Rekonstruierte Hofmann/Graz-Turnpoint-Methode; keine fixe Laktatkonzentration wird zur Bestimmung verwendet. Schwache oder instabile Kandidaten werden als Warnung ausgewiesen.',
    requiredInputs: const <String>[
      'original workload',
      'whole blood lactate',
      'heart rate optional for interpolation only',
    ],
    minimumDataPoints: 4,
    validityRequirements: const <String>[
      'Mindestens vier reale Punkte in der gewaehlten 70-%-ROI; sechs ROI-Punkte sind das robuste Ziel.',
      'Monoton steigende, eindeutige Belastungsintensitaeten.',
      'Mindestens zwei reale Punkte pro Regression.',
      'Positiver Steigungswechsel, positiver Laktatwert und Schnittpunkt innerhalb der Analyse-ROI.',
    ],
    knownLimitations: const <String>[
      'Klasse C mit weniger als vier Punkten in der 70-%-ROI wird nicht berechnet; weder ROI-Erweiterung noch Interpolation oder HRTP-Ersatz sind erlaubt.',
      'Eine Zweipunktregression wird als statistisch schwach markiert.',
      'Die Methode ist eine dokumentierte Rekonstruktion und nicht der originale PA7Win-Algorithmus.',
      'Das Verfahren ersetzt keine MLSS- oder Spiroergometrie-Bestaetigung.',
    ],
    references: const [],
    implementationStatus: MethodImplementationStatus.internallyVerified,
    validationStatus: MethodValidationStatus.provisional,
  );
}
