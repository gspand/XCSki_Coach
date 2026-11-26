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

import 'package:xc_coach/domain/diagnostics.dart';
import 'package:xc_coach/measurement/contracts/measurement_sample.dart';
import 'package:xc_coach/measurement/contracts/test_stage.dart';

/// A complete, evaluable test: identity, protocol, steps and samples.
class MeasurementSession {
  MeasurementSession({
    required this.testId,
    required this.organizationId,
    required this.athleteId,
    required this.sport,
    required this.modality,
    required this.protocol,
    required this.protocolVersion,
    required this.loadUnit,
    required this.measurementSource,
    required this.startedAtUtcUs,
    required List<PersistedTestStage> stages,
    required List<PersistedLactateSample> samples,
    this.deviceId,
    this.stageIncrementHint,
    this.bodyMassKg,
  }) : stages = List<PersistedTestStage>.unmodifiable(
         stages.toList()..sort((a, b) => a.stageIndex.compareTo(b.stageIndex)),
       ),
       samples = List<PersistedLactateSample>.unmodifiable(
         samples.toList()..sort((a, b) => a.id.compareTo(b.id)),
       );

  final String testId;
  final String organizationId;
  final String athleteId;
  final String sport;
  final String modality;
  final String protocol;
  final String protocolVersion;
  final String loadUnit;
  final MeasurementSource measurementSource;
  final int startedAtUtcUs;

  /// Optional by design. A lactate test is complete without a device.
  final String? deviceId;

  final double? stageIncrementHint;
  final double? bodyMassKg;

  /// Ordered by [PersistedTestStage.stageIndex]; ordering is part of the
  /// fingerprint contract.
  final List<PersistedTestStage> stages;

  /// Ordered by id so the fingerprint does not depend on query order.
  final List<PersistedLactateSample> samples;

  /// The one lactate value that belongs to a step.
  ///
  /// If several samples were taken during the same step, the **last** one is
  /// used: in a step protocol the end-of-stage sample is the one that
  /// represents the steady state. Earlier samples remain stored and remain
  /// visible; they are simply not the stage value.
  PersistedLactateSample? sampleOfStage(String stageId) {
    PersistedLactateSample? chosen;
    for (final sample in samples) {
      if (sample.stageId != stageId) continue;
      if (chosen == null || sample.sampledAtUtcUs >= chosen.sampledAtUtcUs) {
        chosen = sample;
      }
    }
    return chosen;
  }

  /// Steps that carry a lactate value and are therefore analysable.
  List<PersistedTestStage> get analysableStages => stages
      .where((stage) => sampleOfStage(stage.id) != null)
      .toList(growable: false);

  double? get peakLoad {
    double? peak;
    for (final stage in analysableStages) {
      if (stage.excluded) continue;
      if (peak == null || stage.loadValue > peak) peak = stage.loadValue;
    }
    return peak;
  }

  /// Highest valid heart rate, used as the peak heart-rate anchor.
  int? get peakHeartRate {
    int? peak;
    for (final stage in analysableStages) {
      final heartRate = stage.heartRateBpm;
      if (stage.excluded || heartRate == null) continue;
      if (peak == null || heartRate > peak) peak = heartRate;
    }
    return peak;
  }
}
