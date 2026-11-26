/// Diagnostics domain vocabulary (Phase D).
///
/// These types describe **how a test was produced and administered** — not how
/// it is interpreted. The scientific meaning of a threshold lives entirely in
/// `lib/lala/core/**` and is never encoded here.
///
/// The central design constraint: a performance test must be fully
/// representable without any measuring device. A coach with a lactate meter,
/// a stopwatch and a treadmill produces a first-class test.
library;

/// Where the intensity values of a test came from.
///
/// This is provenance, not capability. A [MeasurementSource.manual] test is
/// not "lesser" than an Ercolina test; it is differently sourced.
enum MeasurementSource {
  /// Entered by a human: treadmill speed, ergometer display, track splits.
  manual,

  /// Recorded by an Ercolina device through the Giulia session pipeline.
  ercolina,

  /// Imported from an external system or file.
  imported,

  /// Recorded by a third-party device (bike ergometer, treadmill, power meter).
  externalDevice,
}

/// Lifecycle of a performance test.
///
/// Only [PerformanceTestStatus.completed] tests are eligible for evaluation:
/// a running test has no final data state, so a fingerprint over it would be
/// meaningless.
enum PerformanceTestStatus { planned, running, completed, aborted, invalid }

/// Why a lactate sample was taken.
///
/// [LactateSampleContext.stage] samples belong to a step and take part in the
/// analysis. Rest, recovery and spot samples are stored with the test but are
/// not stage measurements, which is why `test_stage_id` stays nullable.
enum LactateSampleContext { rest, warmUp, stage, postExercise, recovery, spot }

/// Puncture site, mirrors the scientific `SampleSite` without importing it.
///
/// The core enum is not reused here on purpose: the persistence layer must not
/// force the science layer to keep a database-compatible shape.
enum LactateSampleSite { ear, finger, unknown }

/// Load units the platform can persist. The string form is what reaches the
/// scientific core as `TestStage.loadUnit`.
abstract final class LoadUnits {
  static const String watt = 'W';
  static const String kilometresPerHour = 'km/h';
  static const String metresPerSecond = 'm/s';

  /// True when a unit denotes power, which is the only case in which the
  /// legacy `threshold_result.power_w` column may be filled.
  static bool isPower(String unit) => unit == watt;
}

/// A test that cannot be evaluated, with a reason a human can act on.
class DiagnosticsDataException implements Exception {
  const DiagnosticsDataException(this.message);
  final String message;
  @override
  String toString() => 'DiagnosticsDataException: $message';
}
