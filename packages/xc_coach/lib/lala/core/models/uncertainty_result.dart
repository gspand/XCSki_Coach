class UncertaintyResult {
  const UncertaintyResult({
    required this.stabilityBand,
    required this.modelSpreadDescription,
    required this.sensitivityRange,
    required this.sources,
  });

  final String stabilityBand;
  final String modelSpreadDescription;
  final String sensitivityRange;
  final List<String> sources;
}
