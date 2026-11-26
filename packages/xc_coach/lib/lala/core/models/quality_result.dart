enum QualitySeverity { info, warning, error }

enum QualityOverallLevel { high, medium, limited }

class QualityFinding {
  const QualityFinding({
    required this.ruleId,
    required this.severity,
    required this.message,
    required this.affectedStageNumbers,
    required this.impact,
    required this.suggestedMitigation,
  });

  final String ruleId;
  final QualitySeverity severity;
  final String message;
  final List<int> affectedStageNumbers;
  final String impact;
  final String suggestedMitigation;
}

class QualityResult {
  const QualityResult({required this.overallLevel, required this.findings});

  final QualityOverallLevel overallLevel;
  final List<QualityFinding> findings;
}
