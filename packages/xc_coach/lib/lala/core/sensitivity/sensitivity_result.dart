class SensitivityResult {
  const SensitivityResult({
    required this.successfulRuns,
    required this.failedRuns,
    required this.minimumThreshold,
    required this.maximumThreshold,
    required this.meanAbsoluteDeviation,
    required this.medianAbsoluteShift,
    required this.maxSinglePointImpact,
    required this.influentialStageNumbers,
    required this.notes,
  });

  final int successfulRuns;
  final int failedRuns;
  final double? minimumThreshold;
  final double? maximumThreshold;
  final double? meanAbsoluteDeviation;
  final double? medianAbsoluteShift;
  final double? maxSinglePointImpact;
  final List<int> influentialStageNumbers;
  final List<String> notes;
}
