class RecoveryLactateSample {
  const RecoveryLactateSample({
    required this.timeAfterExercise,
    required this.lactateMmol,
  });

  final Duration timeAfterExercise;
  final double lactateMmol;
}

class TestProtocolMetadata {
  const TestProtocolMetadata({
    this.sportType,
    this.stageDurationSeconds,
    this.plannedIncrement,
    this.sampleSite,
    this.deviceRangeMin,
    this.deviceRangeMax,
    this.recoveryLactateSamples = const <RecoveryLactateSample>[],
    this.hasMaxExertionMarker = false,
  });

  final String? sportType;
  final int? stageDurationSeconds;
  final double? plannedIncrement;
  final String? sampleSite;
  final double? deviceRangeMin;
  final double? deviceRangeMax;
  final List<RecoveryLactateSample> recoveryLactateSamples;
  final bool hasMaxExertionMarker;
}
