import 'package:xc_coach/lala/core/audit/algorithm_version.dart';

class AnalysisAuditRecord {
  const AnalysisAuditRecord({
    required this.inputHash,
    required this.originalInputPoints,
    required this.testId,
    required this.timestamp,
    required this.methodIds,
    required this.algorithmVersions,
    required this.parameters,
    required this.includedStageNumbers,
    required this.excludedStageNumbers,
    required this.validationErrors,
    required this.validationWarnings,
    required this.qualityMessages,
    required this.resultSummary,
    required this.errors,
    required this.warnings,
  });

  final String inputHash;
  final List<Map<String, Object?>> originalInputPoints;
  final String testId;
  final DateTime timestamp;
  final List<String> methodIds;
  final List<AlgorithmVersion> algorithmVersions;
  final Map<String, Object?> parameters;
  final List<int> includedStageNumbers;
  final List<int> excludedStageNumbers;
  final List<String> validationErrors;
  final List<String> validationWarnings;
  final List<String> qualityMessages;
  final Map<String, Object?> resultSummary;
  final List<String> errors;
  final List<String> warnings;
}
