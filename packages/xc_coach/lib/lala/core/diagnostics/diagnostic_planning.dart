import 'package:xc_coach/lala/core/diagnostics/threshold_consensus.dart';
import 'package:xc_coach/lala/core/models/method_metadata.dart';
import 'package:xc_coach/lala/core/models/threshold_result.dart';

enum DiagnosticStatus {
  draft,
  estimated,
  confirmationRequired,
  scheduled,
  inProgress,
  completed,
  confirmed,
  invalid,
  cancelled,
}

enum FollowUpTestType { mlssConfirmation, lt1SteadyState, criticalPower }

class ThresholdConsensus {
  const ThresholdConsensus({
    required this.thresholdType,
    required this.status,
    required this.lowerLoad,
    required this.upperLoad,
    required this.centralLoad,
    required this.contributingMethodIds,
    required this.explanation,
    required this.detail,
  });

  final ThresholdType thresholdType;
  final DiagnosticStatus status;
  final double? lowerLoad;
  final double? upperLoad;
  final double? centralLoad;
  final List<String> contributingMethodIds;
  final String explanation;

  /// Aufschluesselung nach Verfahren, Leitverfahren und Vergleichswerten.
  final ThresholdConsensusData detail;

  double? get centralHeartRate => detail.centralHeartRate;
  ThresholdAgreement get agreement => detail.agreement;
  String get leadingMethodName => detail.leadingMethodName;
}

class PlannedDiagnosticTest {
  const PlannedDiagnosticTest({
    required this.type,
    required this.target,
    required this.protocol,
    required this.plannedLoad,
    required this.plannedDurationMinutes,
    required this.measurementMinutes,
    this.label,
  });

  final FollowUpTestType type;
  final String target;
  final String protocol;
  final double? plannedLoad;
  final int plannedDurationMinutes;
  final List<int> measurementMinutes;
  final String? label;
}

class DiagnosticPlanningService {
  const DiagnosticPlanningService({
    this.consensusBuilder = const ThresholdConsensusBuilder(),
  });

  final ThresholdConsensusBuilder consensusBuilder;

  ThresholdConsensus buildConsensus({
    required ThresholdType thresholdType,
    required Iterable<ThresholdResult> results,
  }) {
    final detail = consensusBuilder.build(
      thresholdType: thresholdType,
      results: results,
    );
    final contributing = detail.contributingMethods;
    final status = !detail.isDetermined
        ? DiagnosticStatus.confirmationRequired
        : contributing.length >= 2 && !detail.basedOnFixedValuesOnly
        ? DiagnosticStatus.estimated
        : DiagnosticStatus.confirmationRequired;
    return ThresholdConsensus(
      thresholdType: thresholdType,
      status: status,
      lowerLoad: detail.lowerLoad,
      upperLoad: detail.upperLoad,
      centralLoad: detail.centralLoad,
      contributingMethodIds: contributing
          .map((entry) => entry.methodId)
          .toList(growable: false),
      explanation: detail.explanation,
      detail: detail,
    );
  }

  List<PlannedDiagnosticTest> planFollowUps({
    required ThresholdConsensus lt1,
    required ThresholdConsensus lt2,
    double? preferredLt1Load,
    double? preferredLt2Load,
  }) {
    final plans = <PlannedDiagnosticTest>[];
    if (lt1.lowerLoad != null) {
      plans.add(
        PlannedDiagnosticTest(
          type: FollowUpTestType.lt1SteadyState,
          target: 'LT1-Steady-State-Bestaetigung',
          protocol:
              '30 Minuten konstante Belastung; Laktat bei Minute 10, 20 und 30; HF kontinuierlich; RPE bei jeder Messung.',
          plannedLoad: preferredLt1Load ?? lt1.lowerLoad,
          plannedDurationMinutes: 30,
          measurementMinutes: const <int>[10, 20, 30],
        ),
      );
    }
    if (lt2.lowerLoad != null) {
      plans.add(
        PlannedDiagnosticTest(
          type: FollowUpTestType.mlssConfirmation,
          target: 'MLSS-Bestaetigung',
          protocol:
              '30 Minuten konstante Belastung; Laktat bei Minute 10, 20 und 30; HF kontinuierlich; RPE bei jeder Messung.',
          plannedLoad: preferredLt2Load ?? lt2.lowerLoad,
          plannedDurationMinutes: 30,
          measurementMinutes: const <int>[10, 20, 30],
        ),
      );
    }
    for (final duration in const <int>[3, 7, 12]) {
      plans.add(
        PlannedDiagnosticTest(
          type: FollowUpTestType.criticalPower,
          target: 'Critical-Power-Testserie',
          protocol:
              'Maximaler Einzeltest ueber $duration Minuten. Critical Power wird erst nach vollstaendiger Serie berechnet.',
          plannedLoad: null,
          plannedDurationMinutes: duration,
          measurementMinutes: const <int>[],
          label: 'CP-Test $duration min',
        ),
      );
    }
    return List.unmodifiable(plans);
  }

  /// Bewertet die Laktatstabilitaet eines Dauertests.
  /// Konvention nach Heck/Beneke: ein Anstieg bis 1,0 mmol/l zwischen
  /// Minute 10 und Minute 30 gilt als stabil.
  MlssStability classifyStability({
    required double? lactateAtMinute10,
    required double? lactateAtMinute30,
  }) {
    if (lactateAtMinute10 == null || lactateAtMinute30 == null) {
      return MlssStability.notEvaluable;
    }
    final rise = lactateAtMinute30 - lactateAtMinute10;
    if (rise <= 1.0) {
      return MlssStability.stable;
    }
    if (rise <= 1.5) {
      return MlssStability.borderline;
    }
    return MlssStability.notStable;
  }

  PlannedDiagnosticTest nextMlssPlan({
    required double currentLoad,
    required MlssStability outcome,
  }) {
    final nextLoad = switch (outcome) {
      MlssStability.stable => currentLoad + 5,
      MlssStability.notStable => currentLoad - 5,
      MlssStability.borderline => currentLoad,
      MlssStability.notEvaluable => currentLoad,
    };
    return PlannedDiagnosticTest(
      type: FollowUpTestType.mlssConfirmation,
      target: 'MLSS-Folgetest',
      protocol:
          '30 Minuten konstante Belastung; Laktat bei Minute 10, 20 und 30.',
      plannedLoad: nextLoad,
      plannedDurationMinutes: 30,
      measurementMinutes: const <int>[10, 20, 30],
    );
  }
}

enum MlssStability { stable, borderline, notStable, notEvaluable }
