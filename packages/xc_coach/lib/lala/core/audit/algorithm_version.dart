class AlgorithmVersion {
  const AlgorithmVersion({
    required this.methodId,
    required this.major,
    required this.minor,
    required this.patch,
  });

  final String methodId;
  final int major;
  final int minor;
  final int patch;

  String get semanticVersion => '$major.$minor.$patch';
}
