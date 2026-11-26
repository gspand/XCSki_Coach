/// Presentation models for the LaLa module.
///
/// **What this layer is allowed to do:** read persisted rows and arrange them
/// for display — pick the row that a run declared as selected, format a load,
/// subtract two stored thresholds to show a delta.
///
/// **What it must never do:** determine a threshold, choose a method, or
/// interpolate. Those decisions happened once, inside the engine, and were
/// written down in Phase D. The screen shows that record; it does not
/// re-derive it. If a number is not in the database, it is not shown.
///
/// This file therefore imports the core only for two read-only things: the
/// declared standard method ids, and method metadata for a human-readable
/// name. Neither computes anything.
library;

import 'package:xc_coach/database/diagnostics_repository.dart';
import 'package:xc_coach/domain/diagnostic_catalogue.dart';
import 'package:xc_coach/domain/diagnostic_comparability.dart';
import 'package:xc_coach/domain/diagnostics.dart';
import 'package:xc_coach/lala/core/knowledge/analysis_defaults.dart';
import 'package:xc_coach/lala/core/registry/method_registry.dart';
import 'package:xc_coach/measurement/contracts/test_session.dart';
import 'package:xc_coach/measurement/contracts/test_stage.dart';

/// Human-readable name of a method, taken from the engine's own registry.
///
/// The label is not invented here. If a method is unknown to the registry the
/// raw id is shown rather than a guessed name — an unexplained id is honest,
/// a wrong name is not.
String lalaMethodLabel(String? methodId) {
  if (methodId == null) return 'Keine Methode';
  final definition = MethodRegistry().findById(methodId);
  return definition?.metadata.shortName ?? methodId;
}

/// Formats a load with its unit, e.g. `232 W` or `13,4 km/h`.
String formatLoad(double? value, String unit) {
  if (value == null) return '—';
  final digits = LoadUnits.isPower(unit) ? 0 : 1;
  return '${_decimal(value, digits)} $unit';
}

/// Formats a signed difference, e.g. `+8 W` or `−0,4 km/h`.
String formatLoadDelta(double? value, String unit) {
  if (value == null) return '—';
  final digits = LoadUnits.isPower(unit) ? 0 : 1;
  final sign = value > 0
      ? '+'
      : value < 0
      ? '−'
      : '±';
  return '$sign${_decimal(value.abs(), digits)} $unit';
}

String _decimal(double value, int digits) =>
    value.toStringAsFixed(digits).replaceAll('.', ',');

/// How a threshold ended up being the one shown.
enum LalaMethodOrigin {
  /// The scientifically preferred method for this threshold type.
  standard,

  /// The engine could not apply the standard method and used its defined
  /// fallback. This is regular engine behaviour, not an error.
  fallback,

  /// A human explicitly requested this method for this run.
  expert,
}

/// One threshold exactly as it was persisted.
class LalaThresholdView {
  const LalaThresholdView({
    required this.type,
    required this.methodId,
    required this.methodLabel,
    required this.methodVersion,
    required this.engineVersion,
    required this.status,
    required this.origin,
    required this.loadUnit,
    this.loadValue,
    this.heartRateBpm,
    this.lactateMmolPerLitre,
    this.interpretation,
    this.usedStageNumbers = const <int>[],
  });

  /// `lt1` or `lt2`, as stored.
  final String type;

  final String methodId;
  final String methodLabel;
  final String methodVersion;
  final String engineVersion;
  final String status;
  final LalaMethodOrigin origin;
  final String loadUnit;
  final double? loadValue;
  final int? heartRateBpm;
  final double? lactateMmolPerLitre;

  /// The engine's own interpretation text, if it wrote one.
  final String? interpretation;

  final List<int> usedStageNumbers;

  bool get isLt1 => type == 'lt1';
  String get typeLabel => isLt1 ? 'LT1' : 'LT2';
  String get loadLabel => formatLoad(loadValue, loadUnit);

  /// The method the engine would normally have used for this threshold type.
  String get expectedStandardMethodId =>
      isLt1 ? standardLt1MethodId : standardLt2MethodId;

  /// Sentence shown when the standard method could not be applied.
  ///
  /// Phrased as information, not as a failure: a fallback means the protocol
  /// did not satisfy the standard method's preconditions, and LaLa said so.
  String? get originNotice => switch (origin) {
    LalaMethodOrigin.standard => null,
    LalaMethodOrigin.fallback =>
      '${lalaMethodLabel(expectedStandardMethodId)} konnte mit diesem '
          'Stufenprotokoll nicht bestimmt werden; LaLa verwendete die '
          'definierte Fallback-Methode $methodLabel.',
    LalaMethodOrigin.expert =>
      'Für diese Auswertung wurde $methodLabel bewusst als Expertenmethode '
          'gewählt.',
  };
}

/// One complete, persisted LaLa evaluation.
class LalaRunView {
  const LalaRunView({
    required this.id,
    required this.testId,
    required this.runIndex,
    required this.engineVersion,
    required this.engineSourceCommit,
    required this.createdAtUtcUs,
    required this.stageCount,
    required this.inputFingerprint,
    required this.outputFingerprint,
    required this.coreInputHash,
    required this.allThresholds,
    required this.zoneSets,
    this.lt1,
    this.lt2,
    this.triggeredByUserId,
  });

  final String id;
  final String testId;

  /// 1-based. Run 2 of a test is a second opinion, not a correction.
  final int runIndex;

  final String engineVersion;
  final String engineSourceCommit;
  final int createdAtUtcUs;
  final int stageCount;
  final String inputFingerprint;
  final String outputFingerprint;
  final String coreInputHash;

  /// The two thresholds this run declared as selected, if it found them.
  final LalaThresholdView? lt1;
  final LalaThresholdView? lt2;

  /// Every method the engine evaluated, including those without a result.
  final List<LalaThresholdView> allThresholds;

  final List<LalaZoneSetView> zoneSets;
  final String? triggeredByUserId;

  /// True when at least one shown threshold did not come from its standard
  /// method. The result view surfaces this instead of hiding it.
  bool get usedFallback =>
      lt1?.origin == LalaMethodOrigin.fallback ||
      lt2?.origin == LalaMethodOrigin.fallback;

  /// Methods that produced no value. Shown in the scientific detail only.
  List<LalaThresholdView> get methodsWithoutResult => allThresholds
      .where((threshold) => threshold.loadValue == null)
      .toList(growable: false);
}

/// One zone model as generated for a run.
class LalaZoneSetView {
  const LalaZoneSetView({
    required this.id,
    required this.modelId,
    required this.modelName,
    required this.modelVersion,
    required this.quality,
    required this.loadUnit,
    required this.zones,
    required this.issues,
  });

  final String id;
  final String modelId;
  final String modelName;
  final String modelVersion;

  /// Quality label as the engine assigned it.
  final String quality;

  final String loadUnit;
  final List<PersistedTrainingZone> zones;
  final List<PersistedZoneIssue> issues;

  bool get hasProvisionalBoundary =>
      zones.any((zone) => zone.provisionalBoundary);
}

/// A test with everything needed to draw it.
class LalaTestView {
  const LalaTestView({
    required this.head,
    required this.data,
    required this.runs,
  });

  final PerformanceTestHead head;

  /// The measured data as persisted, used for the curve and the raw table.
  final MeasurementSession data;

  /// All runs, oldest first. Several runs of one test stay distinguishable.
  final List<LalaRunView> runs;

  /// The newest run, which is what the overview shows by default.
  LalaRunView? get latestRun => runs.isEmpty ? null : runs.last;

  bool get hasDevice => head.deviceId != null;

  /// Measured points for the lactate/load curve.
  List<LalaCurvePoint> get curve => <LalaCurvePoint>[
    for (final stage in data.stages)
      if (data.sampleOfStage(stage.id) case final sample?)
        LalaCurvePoint(
          stageId: stage.id,
          stageNumber: stage.stageIndex,
          load: stage.loadValue,
          lactate: sample.lactateMmolPerLitre,
          heartRateBpm: stage.heartRateBpm,
          rpe: stage.rpe,
          excluded: stage.excluded,
          exclusionReason: stage.exclusionReason,
        ),
  ];
}

/// One measured step of the curve.
class LalaCurvePoint {
  const LalaCurvePoint({
    required this.stageId,
    required this.stageNumber,
    required this.load,
    required this.lactate,
    required this.excluded,
    this.heartRateBpm,
    this.rpe,
    this.exclusionReason,
  });

  final String stageId;
  final int stageNumber;
  final double load;
  final double lactate;
  final int? heartRateBpm;
  final int? rpe;

  /// An excluded step is drawn, but marked. Hiding it would hide a decision.
  final bool excluded;

  final String? exclusionReason;
}

/// The sport under which a stored test is compared: an older Ercolina test
/// stored as `generic` is the same sport as a new one stored as `ercolina`.
String _comparisonSport(PerformanceTestHead head) => diagnosticComparisonSport(
  sport: head.sport,
  protocol: head.protocol,
  measurementSource: head.measurementSource,
);

/// One entry of the athlete's test history.
/// Why two tests must not be compared numerically, or null if they may be.
///
/// The one place this question is answered. The squad overview and the
/// comparison screen both ask it, and a second, more permissive answer
/// anywhere would mean the overview could show a change the detail view
/// refuses to show.
String? lalaIncomparability({
  String? earlierSport,
  String? laterSport,
  required String earlierLoadUnit,
  required String laterLoadUnit,
  required LalaStepStructure? earlierStructure,
  required LalaStepStructure? laterStructure,
  String earlierLoadSemantics = 'load.protocol_target',
  String laterLoadSemantics = 'load.protocol_target',
}) {
  return diagnosticIncomparability(
    earlierSport: earlierSport,
    laterSport: laterSport,
    earlierLoadUnit: earlierLoadUnit,
    laterLoadUnit: laterLoadUnit,
    earlierStructure: earlierStructure,
    laterStructure: laterStructure,
    earlierLoadSemantics: earlierLoadSemantics,
    laterLoadSemantics: laterLoadSemantics,
  );
}

/// The two properties of a step protocol that decide whether two tests may be
/// subtracted: how big the step is and how long it lasts.
///
/// The **start load is deliberately not part of it.** Two cycling tests with a
/// 20 W step and 3 min stages describe the same protocol whether they began at
/// 60 W or at 100 W; refusing that comparison would hide real development.
/// A different increment or a different stage duration, however, moves the
/// lactate curve itself — the difference would then be the protocol's, not the
/// athlete's.
///
/// The name of the protocol is not consulted anywhere. A name is a label a
/// human typed; the steps are what happened.
class LalaStepStructure extends DiagnosticStepStructure {
  const LalaStepStructure({
    required super.increment,
    required super.stageSeconds,
  });

  /// Reads the structure out of the stored steps, or null when the steps do
  /// not describe one unambiguously. Null is a valid, honest answer and blocks
  /// the comparison; it is never silently treated as "probably the same".
  ///
  /// Excluded steps are ignored: they are documented decisions not to use a
  /// step, and they must not change what the protocol was.
  static LalaStepStructure? of(List<PersistedTestStage> stages) {
    final used = stages.where((stage) => !stage.excluded).toList()
      ..sort((a, b) => a.stageIndex.compareTo(b.stageIndex));
    final structure = DiagnosticStepStructure.fromStages(
      used.map(
        (stage) =>
            (load: stage.loadValue, durationSeconds: stage.durationSeconds),
      ),
    );
    return structure == null
        ? null
        : LalaStepStructure(
            increment: structure.increment,
            stageSeconds: structure.stageSeconds,
          );
  }
}

class LalaHistoryEntry {
  const LalaHistoryEntry({
    required this.testId,
    required this.startedAtUtcUs,
    required this.sport,
    required this.loadUnit,
    required this.runCount,
    required this.measurementSource,
    this.lt1Load,
    this.lt2Load,
    this.lt1HeartRate,
    this.lt2HeartRate,
    this.lt1MethodId,
    this.lt2MethodId,
    this.latestRunId,
    this.protocol,
    this.modality,
  });

  final String testId;
  final int startedAtUtcUs;
  final String sport;
  final String loadUnit;

  /// Stored protocol id and test type (`performance_test.modality`).
  final String? protocol;
  final String? modality;

  /// The TEST sport this entry belongs to, or null when it fits none.
  DiagnosticSport? get diagnosticSport => DiagnosticSport.classify(
    sport: sport,
    protocol: protocol,
    measurementSource: measurementSource,
  );

  DiagnosticTestType? get testType => DiagnosticTestType.ofModality(modality);

  /// How many evaluations exist for this test.
  final int runCount;

  final MeasurementSource measurementSource;
  final double? lt1Load;
  final double? lt2Load;
  final int? lt1HeartRate;
  final int? lt2HeartRate;
  final String? lt1MethodId;
  final String? lt2MethodId;
  final String? latestRunId;

  bool get hasResult => latestRunId != null;
  bool get hasSeveralRuns => runCount > 1;
}

/// Everything the LaLa overview of one athlete shows.
class LalaAthleteOverview {
  const LalaAthleteOverview({
    required this.athleteId,
    required this.athleteName,
    required this.history,
    this.latestTest,
    this.previousTest,
    this.previousComparableTest,
  });

  final String athleteId;
  final String athleteName;

  /// Newest first.
  final List<LalaHistoryEntry> history;

  final LalaTestView? latestTest;

  /// The evaluated test before [latestTest], used for the change indicator.
  final LalaTestView? previousTest;

  /// The newest evaluated test before [latestTest] that may be compared with
  /// it numerically: same sport, test type, load unit, load semantics and
  /// step structure. Null when there is none — never a fallback to an
  /// incompatible test.
  final LalaTestView? previousComparableTest;

  /// No test at all — the empty state, not an error.
  bool get isEmpty => history.isEmpty;

  /// Tests exist but none has been evaluated yet.
  bool get hasUnevaluatedOnly =>
      history.isNotEmpty && history.every((entry) => !entry.hasResult);

  LalaRunView? get latestRun => latestTest?.latestRun;

  /// Change against the previous test, if both are evaluated.
  LalaComparison? get change {
    final current = latestTest;
    final previous = previousTest;
    if (current == null || previous == null) return null;
    if (current.latestRun == null || previous.latestRun == null) return null;
    return LalaComparison.between(earlier: previous, later: current);
  }

  /// Change against [previousComparableTest]; always comparable when present.
  LalaComparison? get comparableChange {
    final current = latestTest;
    final previous = previousComparableTest;
    if (current == null || previous == null) return null;
    return LalaComparison.between(earlier: previous, later: current);
  }
}

/// Difference between two evaluated tests of the same athlete.
///
/// Only subtraction of stored values. No trend is named, no cause is
/// suggested, no verdict is given: LaLa did not say any of that, so neither
/// does this class.
class LalaComparison {
  const LalaComparison({
    required this.earlier,
    required this.later,
    required this.loadUnit,
    this.lt1LoadDelta,
    this.lt2LoadDelta,
    this.lt1HeartRateDelta,
    this.lt2HeartRateDelta,
    this.comparable = true,
    this.incomparableReason,
  });

  factory LalaComparison.between({
    required LalaTestView earlier,
    required LalaTestView later,
  }) {
    final a = earlier.latestRun;
    final b = later.latestRun;
    if (a == null || b == null) {
      return LalaComparison(
        earlier: earlier,
        later: later,
        loadUnit: later.head.loadUnit,
        comparable: false,
        incomparableReason:
            'Mindestens einer der beiden Tests wurde noch nicht ausgewertet.',
      );
    }
    if (earlier.head.modality != later.head.modality) {
      return LalaComparison(
        earlier: earlier,
        later: later,
        loadUnit: later.head.loadUnit,
        comparable: false,
        incomparableReason:
            'Die Tests gehören zu unterschiedlichen Testtypen '
            '(${earlier.head.modality} und ${later.head.modality}). '
            'Ein Zahlenvergleich ist nicht zulässig.',
      );
    }
    final blocked = lalaIncomparability(
      earlierSport: _comparisonSport(earlier.head),
      laterSport: _comparisonSport(later.head),
      earlierLoadUnit: earlier.head.loadUnit,
      laterLoadUnit: later.head.loadUnit,
      earlierStructure: LalaStepStructure.of(earlier.data.stages),
      laterStructure: LalaStepStructure.of(later.data.stages),
      earlierLoadSemantics: earlier.head.loadSemantics,
      laterLoadSemantics: later.head.loadSemantics,
    );
    if (blocked != null) {
      return LalaComparison(
        earlier: earlier,
        later: later,
        loadUnit: later.head.loadUnit,
        comparable: false,
        incomparableReason: blocked,
      );
    }
    return LalaComparison(
      earlier: earlier,
      later: later,
      loadUnit: later.head.loadUnit,
      lt1LoadDelta: _delta(a.lt1?.loadValue, b.lt1?.loadValue),
      lt2LoadDelta: _delta(a.lt2?.loadValue, b.lt2?.loadValue),
      lt1HeartRateDelta: _deltaInt(a.lt1?.heartRateBpm, b.lt1?.heartRateBpm),
      lt2HeartRateDelta: _deltaInt(a.lt2?.heartRateBpm, b.lt2?.heartRateBpm),
    );
  }

  final LalaTestView earlier;
  final LalaTestView later;
  final String loadUnit;
  final double? lt1LoadDelta;
  final double? lt2LoadDelta;
  final int? lt1HeartRateDelta;
  final int? lt2HeartRateDelta;
  final bool comparable;
  final String? incomparableReason;

  /// True when the two tests were evaluated with different engine versions.
  /// The comparison stays valid, but the reader must be told.
  bool get mixedEngineVersions =>
      earlier.latestRun != null &&
      later.latestRun != null &&
      earlier.latestRun!.engineVersion != later.latestRun!.engineVersion;

  /// True when the two runs used different methods for the same threshold.
  /// Comparing a Hofmann LT1 with a Log-Log LT1 is a methodological caveat,
  /// not a physiological finding.
  bool get mixedMethods =>
      earlier.latestRun?.lt1?.methodId != later.latestRun?.lt1?.methodId ||
      earlier.latestRun?.lt2?.methodId != later.latestRun?.lt2?.methodId;

  static double? _delta(double? from, double? to) =>
      (from == null || to == null) ? null : to - from;

  static int? _deltaInt(int? from, int? to) =>
      (from == null || to == null) ? null : to - from;
}

// --------------------------------------------------------------- assembling

/// Builds a [LalaThresholdView] from a persisted row.
///
/// [selectedMethodId] is the id the *run* recorded, and [expertMethodId] the
/// id a human asked for. The origin is derived by comparing ids, never by
/// re-running any selection rule.
LalaThresholdView buildThresholdView(
  PersistedThresholdResult row, {
  String? expertMethodId,
}) {
  final isLt1 = row.thresholdType == 'lt1';
  final standard = isLt1 ? standardLt1MethodId : standardLt2MethodId;
  final origin = row.methodId == expertMethodId && row.methodId != standard
      ? LalaMethodOrigin.expert
      : row.methodId == standard
      ? LalaMethodOrigin.standard
      : LalaMethodOrigin.fallback;

  return LalaThresholdView(
    type: row.thresholdType,
    methodId: row.methodId,
    methodLabel: lalaMethodLabel(row.methodId),
    methodVersion: row.methodVersion,
    engineVersion: row.engineVersion,
    status: row.status,
    origin: origin,
    loadUnit: row.loadUnit ?? LoadUnits.watt,
    loadValue: row.loadValue,
    heartRateBpm: row.heartRateBpm,
    lactateMmolPerLitre: row.lactateMmolPerLitre,
    interpretation: row.interpretation,
    usedStageNumbers: row.usedStageNumbers,
  );
}
