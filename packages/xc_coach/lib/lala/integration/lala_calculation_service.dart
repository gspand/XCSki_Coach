/// Runs the LaLa engine for one persisted test.
///
/// This is the adapter that owns the *entire* contact surface with the
/// scientific core. It calls the core, it never reimplements it: no threshold
/// is derived here, no zone boundary is computed here, no value is rounded,
/// smoothed or substituted here.
///
/// The service is deliberately stateless and database-free. It takes
/// [MeasurementSession] and returns [LalaCalculationOutcome]; persisting that outcome
/// is the repository's job.
library;

import 'package:xc_coach/lala/adapter/measurement_to_lala_adapter.dart';
import 'package:xc_coach/lala/core/knowledge/analysis_defaults.dart';
import 'package:xc_coach/lala/core/lactate_analyzer.dart';
import 'package:xc_coach/lala/core/models/analysis_result.dart';
import 'package:xc_coach/lala/core/models/method_metadata.dart';
import 'package:xc_coach/lala/core/models/threshold_result.dart';
import 'package:xc_coach/lala/core/models/training_zone.dart';
import 'package:xc_coach/lala/core/training_zones/training_zone_calculator.dart';
import 'package:xc_coach/lala/core/training_zones/training_zone_model.dart';
import 'package:xc_coach/lala/core/training_zones/zone_anchor_builder.dart';
import 'package:xc_coach/lala/integration/lala_fingerprint.dart';
import 'package:xc_coach/measurement/contracts/test_session.dart';
import 'package:xc_coach/lala/lala_engine.dart';

/// Everything one evaluation produced, ready to be written down.
class LalaCalculationOutcome {
  const LalaCalculationOutcome({
    required this.analysis,
    required this.anchors,
    required this.zoneSets,
    required this.inputFingerprint,
    required this.outputFingerprint,
    required this.engineVersion,
    required this.engineSourceCommit,
    required this.loadUnit,
    required this.sport,
    required this.stageCount,
    this.selectedLt1MethodId,
    this.selectedLt2MethodId,
  });

  final AnalysisResult analysis;
  final PhysiologicalAnchorSet anchors;

  /// All zone models the engine offers, generated side by side. None of them
  /// is "the" model; picking one is a later, user-facing decision.
  final List<GeneratedTrainingZoneSet> zoneSets;

  final String inputFingerprint;
  final String outputFingerprint;
  final String engineVersion;
  final String engineSourceCommit;
  final String loadUnit;
  final String sport;
  final int stageCount;

  /// The method whose LT1 was actually used for the anchors of this run.
  ///
  /// Stored per run and not as a global setting, so a historical test always
  /// answers "which method produced this number" by itself. `null` means the
  /// engine found no usable LT1 at all — an honest empty result, never a
  /// substituted one.
  final String? selectedLt1MethodId;

  /// See [selectedLt1MethodId].
  final String? selectedLt2MethodId;

  List<ThresholdResult> get thresholds => analysis.thresholdResults;

  /// The canonical input hash the core itself computed. Kept alongside the
  /// Giulia fingerprint: two independent witnesses of the same data state.
  String get coreInputHash => analysis.auditRecord.inputHash;
}

class LalaCalculationService {
  const LalaCalculationService();

  /// Evaluates [data] with the current engine.
  ///
  /// [generatedAt] is passed through to zone generation so a run is
  /// reproducible: the engine would otherwise stamp `DateTime.now()`, which
  /// would make two evaluations of the same data differ in metadata.
  LalaCalculationOutcome evaluate({
    required MeasurementSession data,
    required DateTime generatedAt,
    String? expertLt1MethodId,
    String? expertLt2MethodId,
  }) {
    final input = data.toAnalysisInput();
    final analysis = LactateAnalyzer().analyze(input);

    // `displayThreshold` is the core's own selection rule, including its
    // fallback chain. It is called, not re-implemented, so the persisted
    // method id is exactly the one the science layer would name.
    final lt1 = displayThreshold(
      analysis.thresholdResults,
      ThresholdType.lt1,
      expertMethodId: expertLt1MethodId,
    );
    final lt2 = displayThreshold(
      analysis.thresholdResults,
      ThresholdType.lt2,
      expertMethodId: expertLt2MethodId,
    );

    final anchors = const ZoneAnchorBuilder().build(
      analysis: analysis,
      sportType: data.sport,
      loadUnit: data.loadUnit,
      peakLoad: data.peakLoad,
      peakHeartRate: data.peakHeartRate,
      selectedLt1MethodId: lt1?.result.methodId,
      selectedLt2MethodId: lt2?.result.methodId,
    );

    final zoneSets = <GeneratedTrainingZoneSet>[
      for (final model in builtInZoneModels)
        const TrainingZoneService().generate(
          anchors: anchors,
          model: model,
          generatedAt: generatedAt,
        ),
    ];

    return LalaCalculationOutcome(
      analysis: analysis,
      anchors: anchors,
      zoneSets: zoneSets,
      inputFingerprint: LalaFingerprint.ofInput(data),
      outputFingerprint: LalaFingerprint.ofOutput(
        thresholds: analysis.thresholdResults,
        zoneSets: zoneSets,
        engineVersion: lalaEngineVersion,
      ),
      engineVersion: lalaEngineVersion,
      engineSourceCommit: lalaEngineSourceCommit,
      loadUnit: data.loadUnit,
      sport: data.sport,
      stageCount: input.stages.length,
      selectedLt1MethodId: lt1?.result.methodId,
      selectedLt2MethodId: lt2?.result.methodId,
    );
  }
}
