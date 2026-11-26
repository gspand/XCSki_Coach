/// Von der Messung zur Auswertung.
///
/// ## Die einzige Stelle, an der beide Welten aufeinandertreffen
///
/// Die Gerätesoftware schreibt Messverträge und weiß nichts von Schwellen. Der
/// wissenschaftliche Kern rechnet und weiß nichts von Datenbanken, Geräten und
/// Sitzungen. Dieser Adapter übersetzt das eine ins andere — und er liegt
/// bewusst **in LaLa**, nicht in der Messung: er ist Teil der Diagnostik, und
/// wer nur das Gerät lizenziert, bekommt ihn nicht.
///
/// Übersetzt heißt: umgeschichtet. Hier wird nicht geglättet, nicht
/// interpoliert, nicht umgerechnet und nichts plausibilisiert — das sind
/// wissenschaftliche Entscheidungen und gehören in den Kern.
library;

import 'package:xc_coach/domain/diagnostics.dart';
import 'package:xc_coach/lala/core/models/analysis_input.dart';
import 'package:xc_coach/lala/core/models/test_stage.dart';
import 'package:xc_coach/measurement/contracts/measurement_sample.dart';
import 'package:xc_coach/measurement/contracts/test_session.dart';
import 'package:xc_coach/measurement/contracts/test_stage.dart';

extension MeasurementToLala on MeasurementSession {
  /// Builds the scientific input.
  ///
  /// This is the only place where Giulia data becomes LaLa data. It performs
  /// no smoothing, no interpolation, no unit conversion and no plausibility
  /// correction — those are scientific decisions and belong to the core.
  ///
  /// Throws [DiagnosticsDataException] when the test carries no stage-bound
  /// lactate value at all. That is a data problem, not a scientific finding,
  /// and must not be disguised as an empty analysis.
  AnalysisInput toAnalysisInput() {
    final usable = analysableStages;
    if (usable.isEmpty) {
      throw const DiagnosticsDataException(
        'Der Test enthaelt keine stufenbezogene Laktatprobe. '
        'Ohne Laktatwert je Stufe ist keine Auswertung moeglich.',
      );
    }
    return AnalysisInput(
      testId: testId,
      sportType: sport,
      protocolName: protocol,
      stageIncrementHint: stageIncrementHint,
      stages: <TestStage>[
        for (final stage in usable)
          _toCoreStage(stage, sampleOfStage(stage.id)!),
      ],
    );
  }

  TestStage _toCoreStage(
    PersistedTestStage stage,
    PersistedLactateSample sample,
  ) => TestStage(
    stageNumber: stage.stageIndex,
    load: stage.loadValue,
    loadUnit: loadUnit,
    durationSeconds: stage.durationSeconds,
    lactate: sample.lactateMmolPerLitre,
    heartRate: stage.heartRateBpm,
    rpe: stage.rpe,
    // Deliberately null: the core uses `sampleTime` only for reporting, and a
    // wall-clock timestamp would make the analysis input non-reproducible
    // across time zones without adding scientific value.
    sampleTime: null,
    sampleSite: switch (sample.site) {
      LactateSampleSite.ear => SampleSite.ear,
      LactateSampleSite.finger => SampleSite.finger,
      LactateSampleSite.unknown => SampleSite.unknown,
    },
    isValid: !stage.excluded,
    exclusionReason: stage.exclusionReason,
    note: stage.notes,
  );

  /// Highest valid load, used as the peak anchor for zone generation.
}
