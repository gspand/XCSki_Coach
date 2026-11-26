/// Test- und Simulationsharness für den geschlossenen Regelkreis (Closed Loop Simulation).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE & ARCHITEKTONISCHE LEITPLANKEN:
/// - COMPLETED SESSIONS DÜRFEN IN PRODUKTION NIEMALS AUS PRESCRIPTIONS SIMULIERT WERDEN!
/// - In der produktiven GIULIA-App entstehen Belastungen (Load & Stimulus) ausschließlich
///   aus real gemessenen und synchronisierten Beobachtungen (NormalizedSession via Strava/Garmin/Ercolina).
/// - Diese Klasse dient AUSSCHLIESSLICH als deterministisches Test- und Benchmark-Harness
///   für Golden Coach Scenarios und Regressionstests.
library;

import 'package:meta/meta.dart';

import '../../domain/normalized_session.dart';
import '../../domain/xc_modality.dart';
import '../load/stimulus_models.dart';
import 'workout_prescription.dart';

@visibleForTesting
class ClosedLoopSimulator {
  const ClosedLoopSimulator();

  /// Erzeugt eine voll valide [NormalizedSession] aus einer durchgeführten [WorkoutPrescription].
  ///
  /// Ausschließlich für Test- und Benchmarkzwecke bestimmt!
  NormalizedSession simulateCompletedSession({
    required WorkoutPrescription prescription,
    required String athleteId,
    required DateTime performedAt,
    double perceivedRpe = 7.0,
    double? averageHrBpm,
    double? maxHrBpm,
    double? averagePowerWatt,
  }) {
    final durationSeconds = prescription.totalDurationMinutes * 60;
    final isErcolina = prescription.modality == XcModality.ercolinaDoublePoling;
    final isSkating = prescription.modality == XcModality.skiSkating;

    // Errechne realistische mechanische Arbeit (kJ)
    final avgWatt = averagePowerWatt ??
        prescription.workIntensity.minPowerWatt ??
        (isErcolina ? 160.0 : (isSkating ? 210.0 : 180.0));
    final workKiloJoule = (avgWatt * durationSeconds) / 1000.0;

    return NormalizedSession(
      id: 'sim_${prescription.id}_${performedAt.millisecondsSinceEpoch}',
      athleteId: athleteId,
      source: isErcolina ? NormalizedSessionSource.ercolina : NormalizedSessionSource.manual,
      sourceId: 'sim_src_${performedAt.millisecondsSinceEpoch}',
      startedAtUtcUs: performedAt.toUtc().microsecondsSinceEpoch,
      durationSeconds: durationSeconds,
      movingTimeSeconds: durationSeconds,
      modality: prescription.modality,
      technique: isErcolina
          ? XcTechnique.classicDoublePoling
          : (isSkating ? XcTechnique.skatingG3 : XcTechnique.unknown),
      isIndoor: isErcolina,
      title: prescription.title,
      externalMetrics: SessionExternalMetrics(
        sessionAveragePowerWatt: avgWatt,
        intervalAveragePowerWatt: prescription.family == WorkoutFamilyType.vo2maxIntervals ||
                prescription.family == WorkoutFamilyType.thresholdIntervals
            ? avgWatt * 1.15
            : null,
        workJoule: workKiloJoule * 1000.0,
      ),
      internalMetrics: SessionInternalMetrics(
        averageHeartRateBpm: averageHrBpm ?? 152.0,
        peakHeartRateBpm: (maxHrBpm ?? 178.0).round(),
        rpe: perceivedRpe,
        timeInHrZonesSeconds: {
          if (prescription.intendedStimuli.contains(StimulusType.vo2max)) 'z5': 360,
          if (prescription.intendedStimuli.contains(StimulusType.threshold)) 'z4': 1200,
          'z2': 1800,
        },
      ),
      rawMetadata: {
        'simulation': true,
        'prescriptionId': prescription.id,
      },
    );
  }
}
