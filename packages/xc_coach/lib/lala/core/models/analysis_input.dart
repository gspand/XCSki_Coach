import 'package:xc_coach/lala/core/models/test_stage.dart';

class AnalysisInput {
  const AnalysisInput({
    required this.testId,
    required this.stages,
    this.sportType,
    this.protocolName,
    this.stageIncrementHint,
    this.operatorId,
    this.analysisTimestamp,
  });

  final String testId;
  final List<TestStage> stages;
  final String? sportType;
  final String? protocolName;
  final double? stageIncrementHint;
  final String? operatorId;
  final DateTime? analysisTimestamp;

  List<TestStage> get validStages =>
      stages.where((stage) => stage.isValid).toList(growable: false);
}
