enum SampleSite { ear, finger, unknown }

class TestStage {
  const TestStage({
    required this.stageNumber,
    required this.load,
    required this.loadUnit,
    required this.durationSeconds,
    required this.lactate,
    required this.heartRate,
    required this.rpe,
    required this.sampleTime,
    required this.sampleSite,
    required this.isValid,
    this.exclusionReason,
    this.note,
  });

  final int stageNumber;
  final double load;
  final String loadUnit;
  final int durationSeconds;
  final double lactate;
  final int? heartRate;
  final int? rpe;
  final DateTime? sampleTime;
  final SampleSite sampleSite;
  final bool isValid;
  final String? exclusionReason;
  final String? note;

  TestStage copyWith({
    int? stageNumber,
    double? load,
    String? loadUnit,
    int? durationSeconds,
    double? lactate,
    int? heartRate,
    int? rpe,
    DateTime? sampleTime,
    SampleSite? sampleSite,
    bool? isValid,
    String? exclusionReason,
    String? note,
  }) {
    return TestStage(
      stageNumber: stageNumber ?? this.stageNumber,
      load: load ?? this.load,
      loadUnit: loadUnit ?? this.loadUnit,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      lactate: lactate ?? this.lactate,
      heartRate: heartRate ?? this.heartRate,
      rpe: rpe ?? this.rpe,
      sampleTime: sampleTime ?? this.sampleTime,
      sampleSite: sampleSite ?? this.sampleSite,
      isValid: isValid ?? this.isValid,
      exclusionReason: exclusionReason ?? this.exclusionReason,
      note: note ?? this.note,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'stageNumber': stageNumber,
      'load': load,
      'loadUnit': loadUnit,
      'durationSeconds': durationSeconds,
      'lactate': lactate,
      'heartRate': heartRate,
      'rpe': rpe,
      'sampleTime': sampleTime?.toIso8601String(),
      'sampleSite': sampleSite.name,
      'isValid': isValid,
      'exclusionReason': exclusionReason,
      'note': note,
    };
  }
}
