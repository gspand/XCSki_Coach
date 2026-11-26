/// Ein Messvertrag der GIULIA-Plattform.
///
/// ## Warum diese Verträge nicht in LaLa liegen
///
/// Weil sonst kein Gerät gebaut werden kann, ohne die Diagnostik mitzuliefern.
/// Die Gerätesoftware schreibt Stufen, Proben und Sitzungen; die Diagnostik
/// liest sie. Beide sprechen diesen Vertrag, und keines der beiden kennt das
/// andere:
///
/// ```text
///   Ercolina ──▶  Measurement  ◀── LaLa
/// ```
///
/// Für einen OEM-Vertrag ist das der Unterschied zwischen «die Diagnostik ist
/// unsichtbar» und «die Diagnostik ist nicht im Artefakt».
library;

/// One step of a step test as Giulia stores it.
///
/// [loadValue] is the sport-neutral intensity handed to the science layer:
/// watt on an ergometer, km/h on a treadmill. Everything else is context that
/// LaLa may use but never requires.
class PersistedTestStage {
  const PersistedTestStage({
    required this.id,
    required this.stageIndex,
    required this.loadValue,
    required this.durationSeconds,
    this.startedAtUtcUs,
    this.endedAtUtcUs,
    this.targetValue,
    this.heartRateBpm,
    this.speedKilometresPerHour,
    this.paceSecondsPerKilometre,
    this.cadencePerMinute,
    this.strokeRatePerMinute,
    this.meanPowerWatt,
    this.rpe,
    this.excluded = false,
    this.exclusionReason,
    this.notes,
    this.partial = false,
    this.workJoule,
    this.peakPowerWatt,
    this.steadyEndPowerWatt,
    this.strokeCount,
    this.leftWorkShare,
    this.rawSampleCount,
    this.windowStartUs,
    this.windowEndUs,
  });

  final String id;

  /// 1-based step number, identical to the scientific `TestStage.stageNumber`.
  final int stageIndex;

  final double loadValue;
  final int durationSeconds;
  final int? startedAtUtcUs;
  final int? endedAtUtcUs;
  final double? targetValue;
  final int? heartRateBpm;
  final double? speedKilometresPerHour;
  final int? paceSecondsPerKilometre;
  final double? cadencePerMinute;
  final double? strokeRatePerMinute;
  final double? meanPowerWatt;
  final int? rpe;

  /// Excluded by the diagnostician, for example an aborted or invalid step.
  /// The row is kept: an exclusion is a documented decision, not a deletion.
  final bool excluded;
  final String? exclusionReason;
  final String? notes;

  /// True when the step was cut short — the athlete stopped, or the recording
  /// ended before the step was over.
  ///
  /// Separate from [excluded] on purpose. `excluded` says a human decided not
  /// to use the step; `partial` says the measurement itself is incomplete.
  /// Conflating the two would make it impossible to see whether an incomplete
  /// step was ever looked at.
  final bool partial;

  // ------------------------------------------------------ device provenance
  // Filled only for a step a device measured. They explain where [loadValue]
  // came from and are never inputs of the evaluation.

  final double? workJoule;
  final double? peakPowerWatt;

  /// Mean power of the settled end phase of the step.
  final double? steadyEndPowerWatt;

  final int? strokeCount;

  /// Share of the work produced by the left side. 0.5 is symmetric.
  final double? leftWorkShare;

  /// How many raw sensor samples backed this step.
  final int? rawSampleCount;

  /// The exact aggregation window, in aligned monotonic microseconds, so the
  /// step values can be recomputed from the stored raw data.
  final int? windowStartUs;
  final int? windowEndUs;
}
