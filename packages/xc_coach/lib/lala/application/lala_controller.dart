/// Orchestration for the LaLa module.
///
/// The controller is the only place the UI talks to. It does three things:
/// load persisted evaluations, write a manually entered test, and ask the
/// repository to run an evaluation.
///
/// It contains **no** threshold logic. `evaluate` is a single call into
/// [DiagnosticsRepository], which in turn calls the engine. Whatever comes
/// back is read from the database again, so the screen can only ever show what
/// was actually stored — a bug here can make the UI empty, never wrong.
library;

import 'package:flutter/foundation.dart';
import 'package:xc_coach/database/diagnostics_repository.dart';
import 'package:xc_coach/database/platform_repository.dart';
import 'package:xc_coach/domain/diagnostic_catalogue.dart';
import 'package:xc_coach/domain/diagnostic_facts.dart';
import 'package:xc_coach/domain/diagnostics.dart';
import 'package:xc_coach/domain/platform.dart';
import 'package:xc_coach/lala/application/lala_test_draft.dart';
import 'package:xc_coach/lala/application/lala_view_models.dart';
import 'package:xc_coach/measurement/contracts/measurement_sample.dart';
import 'package:xc_coach/measurement/contracts/test_stage.dart';

/// Identity of the person using the app, as far as LaLa needs it.
class LalaSession {
  const LalaSession({
    required this.userId,
    required this.organizationId,
    required this.roles,
  });

  final String userId;
  final String organizationId;
  final Set<PlatformRole> roles;

  bool get mayRecordDiagnostics =>
      AccessPolicy.hasCapability(roles, Capability.recordDiagnostics);

  bool get mayViewDiagnostics =>
      AccessPolicy.hasCapability(roles, Capability.viewAthleteData) ||
      AccessPolicy.hasCapability(roles, Capability.viewOwnData);
}

/// What went wrong, in words a diagnostician can act on.
class LalaControllerFailure {
  const LalaControllerFailure(this.message, {this.isPermission = false});

  final String message;
  final bool isPermission;
}

class LalaController extends ChangeNotifier {
  LalaController({
    required this.diagnostics,
    required this.session,
    PlatformRepository? platform,
    this.clock = _systemClock,
  }) : platform = platform ?? diagnostics.platform {
    _repairLegacyScoutImports();
  }

  final DiagnosticsRepository diagnostics;
  final PlatformRepository platform;
  final LalaSession session;

  /// Injectable so a test does not depend on wall-clock time and so a run is
  /// reproducible. Microseconds UTC.
  final int Function() clock;

  static int _systemClock() => DateTime.now().toUtc().microsecondsSinceEpoch;

  /// Version 13 deutete den Scout-Sentinel 0xFF als Puls 255. Die
  /// Datenbankmigration repariert die Stufen, aber frühere Berechnungsläufe
  /// sind absichtlich unveränderlich. Deshalb wird genau einmal ein neuer,
  /// nachvollziehbarer Lauf über die korrigierten Rohdaten gehängt.
  void _repairLegacyScoutImports() {
    const repairKey = 'repair.lactate_scout.v14';
    if (platform.appState(repairKey) == 'done') return;
    final rows = diagnostics.database.raw.select('''SELECT DISTINCT run.test_id
           FROM lala_calculation_run run
           JOIN xc_threshold_result threshold
             ON threshold.calculation_run_id = run.id
          WHERE threshold.heart_rate_bpm = 255
            AND run.run_index = (
              SELECT MAX(latest.run_index)
                FROM lala_calculation_run latest
               WHERE latest.test_id = run.test_id
            )
            AND run.test_id IN (
              SELECT DISTINCT test_id FROM external_measurement_import
               WHERE provider_id = 'lactate_scout'
            )''');
    var complete = true;
    for (final (index, row) in rows.indexed) {
      try {
        diagnostics.evaluate(
          testId: row['test_id'] as String,
          nowUtcUs: clock() + index,
          triggeredByUserId: session.userId,
        );
      } on Object {
        complete = false;
      }
    }
    if (complete) {
      platform.setAppState(key: repairKey, value: 'done', nowUtcUs: clock());
    }
  }

  String? _selectedAthleteId;
  LalaAthleteOverview? _overview;
  LalaControllerFailure? _failure;
  bool _busy = false;

  String? get selectedAthleteId => _selectedAthleteId;
  LalaAthleteOverview? get overview => _overview;
  LalaControllerFailure? get failure => _failure;
  bool get busy => _busy;

  /// Read-only history for a currently visible athlete, used when a test
  /// detail offers comparison with any older result.
  LalaAthleteOverview overviewFor(String athleteId) {
    if (!platform.canViewAthlete(
      userId: session.userId,
      athleteId: athleteId,
    )) {
      throw const PlatformAccessException(
        'Für diesen Athleten liegt keine Freigabe vor.',
      );
    }
    return _buildOverview(athleteId);
  }

  /// Athletes the signed-in user may see.
  List<AthleteSummary> get athletes => platform.visibleAthleteSummaries(
    userId: session.userId,
    organizationId: session.organizationId,
  );

  /// Machine-readable facts of every stored test of [athleteId], newest
  /// first — read back from the database, nothing recomputed.
  List<DiagnosticTestFact> factsOf(String athleteId) {
    if (!platform.canViewAthlete(
      userId: session.userId,
      athleteId: athleteId,
    )) {
      throw const PlatformAccessException(
        'Für diesen Athleten liegt keine Freigabe vor.',
      );
    }
    return [
      for (final head in diagnostics.testsOfAthlete(athleteId))
        _factOf(_buildTestView(head)),
    ];
  }

  DiagnosticTestFact _factOf(LalaTestView view) {
    final head = view.head;
    final run = view.latestRun;
    final zoneSet = run == null || run.zoneSets.isEmpty
        ? null
        : run.zoneSets.first;
    return DiagnosticTestFact(
      testId: head.id,
      athleteId: head.athleteId,
      storedSport: head.sport,
      sport: DiagnosticSport.classify(
        sport: head.sport,
        protocol: head.protocol,
        measurementSource: head.measurementSource,
      ),
      modality: head.modality,
      testType: DiagnosticTestType.ofModality(head.modality),
      protocolId: head.protocol,
      measurementSource: head.measurementSource,
      status: head.status,
      performedAtUtcUs: head.startedAtUtcUs,
      loadUnit: head.loadUnit,
      ltp1Load: run?.lt1?.loadValue,
      ltp2Load: run?.lt2?.loadValue,
      heartRateAtLtp1: run?.lt1?.heartRateBpm,
      heartRateAtLtp2: run?.lt2?.heartRateBpm,
      lactateAtLtp1: run?.lt1?.lactateMmolPerLitre,
      lactateAtLtp2: run?.lt2?.lactateMmolPerLitre,
      zones: [
        for (final zone in zoneSet?.zones ?? const <PersistedTrainingZone>[])
          DiagnosticZoneFact(
            ordinal: zone.ordinal,
            name: zone.name,
            loadUnit: zone.loadUnit,
            lowerLoad: zone.lowerLoadDisplay ?? zone.lowerLoadExact,
            upperLoad: zone.upperLoadDisplay ?? zone.upperLoadExact,
            lowerHeartRateBpm:
                zone.lowerHeartRateDisplay ?? zone.lowerHeartRateExact?.round(),
            upperHeartRateBpm:
                zone.upperHeartRateDisplay ?? zone.upperHeartRateExact?.round(),
          ),
      ],
    );
  }

  // ------------------------------------------------------------------ read

  /// Selects an athlete and loads their LaLa record.
  void selectAthlete(String athleteId) {
    _selectedAthleteId = athleteId;
    refresh();
  }

  /// Re-reads everything from the database.
  void refresh() {
    final athleteId = _selectedAthleteId;
    if (athleteId == null) {
      _overview = null;
      notifyListeners();
      return;
    }
    _failure = null;
    try {
      if (!platform.canViewAthlete(
        userId: session.userId,
        athleteId: athleteId,
      )) {
        _overview = null;
        _failure = const LalaControllerFailure(
          'Für diesen Athleten liegt keine Freigabe vor.',
          isPermission: true,
        );
        notifyListeners();
        return;
      }
      _overview = _buildOverview(athleteId);
    } on PlatformAccessException catch (error) {
      _overview = null;
      _failure = LalaControllerFailure(error.toString(), isPermission: true);
    }
    notifyListeners();
  }

  /// Loads one test with all its runs. Used by the detail and comparison view.
  LalaTestView loadTest(String testId) {
    final head = diagnostics
        .testsOfAthlete(_requireAthlete())
        .firstWhere((test) => test.id == testId);
    return _buildTestView(head);
  }

  /// Compares two tests of the selected athlete.
  LalaComparison compare({
    required String earlierTestId,
    required String laterTestId,
  }) => LalaComparison.between(
    earlier: loadTest(earlierTestId),
    later: loadTest(laterTestId),
  );

  // ----------------------------------------------------------------- write

  /// Persists a manually entered test and evaluates it in one go.
  ///
  /// Returns the id of the created calculation run, or null when the write
  /// failed. Nothing is computed here: [DiagnosticsRepository.evaluate] calls
  /// the engine, and the result is read back from the database afterwards.
  String? saveAndEvaluate(LalaTestDraft draft, {String? testId}) {
    if (!draft.canSave) {
      _failure = LalaControllerFailure(draft.blockingReason!);
      notifyListeners();
      return null;
    }
    _busy = true;
    _failure = null;
    notifyListeners();

    final now = clock();
    final id = testId ?? 'test-${draft.athleteId}-$now';
    try {
      diagnostics.createTest(
        id: id,
        organizationId: session.organizationId,
        athleteId: draft.athleteId,
        sport: draft.sport,
        modality: 'step_test',
        protocol: draft.preset.id,
        protocolVersion: '1.0.0',
        loadUnit: draft.loadUnit,
        measurementSource: MeasurementSource.manual,
        startedAtUtcUs: draft.startedAtUtcUs,
        createdByUserId: session.userId,
        stageIncrementHint: draft.preset.increment,
        notes: draft.notes,
      );

      for (final stage in draft.completeStages) {
        final stageId = '$id-s${stage.stageNumber}';
        diagnostics.addStage(
          testId: id,
          nowUtcUs: now,
          stage: PersistedTestStage(
            id: stageId,
            stageIndex: stage.stageNumber,
            loadValue: stage.load!,
            durationSeconds:
                stage.durationSeconds ?? draft.preset.stageDurationSeconds,
            heartRateBpm: stage.heartRateBpm,
            rpe: stage.rpe,
            excluded: stage.excluded,
            exclusionReason: stage.exclusionReason,
          ),
        );
        diagnostics.addLactateSample(
          testId: id,
          nowUtcUs: now,
          sample: PersistedLactateSample(
            id: '$id-l${stage.stageNumber}',
            stageId: stageId,
            lactateMmolPerLitre: stage.lactateMmolPerLitre!,
            sampledAtUtcUs: now,
            context: LactateSampleContext.stage,
            site: LactateSampleSite.ear,
            enteredByUserId: session.userId,
          ),
        );
      }

      diagnostics.completeTest(testId: id, endedAtUtcUs: now);

      final runId = diagnostics.evaluate(
        testId: id,
        nowUtcUs: now,
        triggeredByUserId: session.userId,
      );
      _selectedAthleteId = draft.athleteId;
      _busy = false;
      refresh();
      return runId;
    } on PlatformAccessException catch (error) {
      _busy = false;
      _failure = LalaControllerFailure(
        'Keine Berechtigung, für diesen Athleten Diagnostik zu erfassen. '
        '$error',
        isPermission: true,
      );
      notifyListeners();
      return null;
    } on DiagnosticsDataException catch (error) {
      _busy = false;
      _failure = LalaControllerFailure(error.message);
      notifyListeners();
      return null;
    }
  }

  /// Adds an auditable correction and immediately creates a new calculation
  /// run from the corrected working values. Original raw rows and every prior
  /// result are preserved.
  String? correctStageAndEvaluate({
    required String testId,
    required String stageId,
    required String reason,
    required double loadValue,
    required double lactateMmolPerLitre,
    int? heartRateBpm,
    int? rpe,
  }) {
    _busy = true;
    _failure = null;
    notifyListeners();
    final now = clock();
    try {
      diagnostics.correctStageData(
        id: 'correction-$stageId-$now',
        stageId: stageId,
        actorUserId: session.userId,
        reason: reason,
        correctedAtUtcUs: now,
        loadValue: loadValue,
        heartRateBpm: heartRateBpm,
        rpe: rpe,
        lactateMmolPerLitre: lactateMmolPerLitre,
      );
      final runId = diagnostics.evaluate(
        testId: testId,
        nowUtcUs: now,
        triggeredByUserId: session.userId,
      );
      _busy = false;
      refresh();
      return runId;
    } on PlatformAccessException catch (error) {
      _busy = false;
      _failure = LalaControllerFailure(error.message, isPermission: true);
    } on DiagnosticsDataException catch (error) {
      _busy = false;
      _failure = LalaControllerFailure(error.message);
    }
    notifyListeners();
    return null;
  }

  /// Stores the diagnostician's assessment on a test.
  ///
  /// Deliberately does **not** re-evaluate. The text is commentary; if writing
  /// it produced a new calculation run, every saved sentence would look like a
  /// new scientific result in the test's history.
  bool saveNotes({required String testId, required String? notes}) {
    _failure = null;
    try {
      diagnostics.recordTestNotes(
        testId: testId,
        actorUserId: session.userId,
        notes: notes,
      );
      refresh();
      return true;
    } on PlatformAccessException catch (error) {
      _failure = LalaControllerFailure(error.message, isPermission: true);
    } on DiagnosticsDataException catch (error) {
      _failure = LalaControllerFailure(error.message);
    }
    notifyListeners();
    return false;
  }

  /// Runs the engine again over an unchanged test.
  ///
  /// Appends a run; the earlier one stays readable. This is what makes a 2026
  /// test re-analysable in 2028 without losing the original reading.
  String? reevaluate(
    String testId, {
    String? expertLt1MethodId,
    String? expertLt2MethodId,
  }) {
    _failure = null;
    try {
      final runId = diagnostics.evaluate(
        testId: testId,
        nowUtcUs: clock(),
        triggeredByUserId: session.userId,
        expertLt1MethodId: expertLt1MethodId,
        expertLt2MethodId: expertLt2MethodId,
      );
      refresh();
      return runId;
    } on PlatformAccessException catch (error) {
      _failure = LalaControllerFailure(error.toString(), isPermission: true);
      notifyListeners();
      return null;
    } on DiagnosticsDataException catch (error) {
      _failure = LalaControllerFailure(error.message);
      notifyListeners();
      return null;
    }
  }

  // ------------------------------------------------------------- assembling

  String _requireAthlete() {
    final athleteId = _selectedAthleteId;
    if (athleteId == null) {
      throw StateError('Kein Athlet ausgewählt.');
    }
    return athleteId;
  }

  LalaAthleteOverview _buildOverview(String athleteId) {
    final heads = diagnostics.testsOfAthlete(athleteId);
    final history = <LalaHistoryEntry>[];
    for (final head in heads) {
      final runs = diagnostics.runsOfTest(head.id);
      final latest = runs.isEmpty ? null : runs.last;
      final thresholds = latest == null
          ? const <PersistedThresholdResult>[]
          : diagnostics.thresholdsOfRun(latest.id);
      final lt1 = _selected(thresholds, latest?.selectedLt1MethodId, 'lt1');
      final lt2 = _selected(thresholds, latest?.selectedLt2MethodId, 'lt2');
      history.add(
        LalaHistoryEntry(
          testId: head.id,
          startedAtUtcUs: head.startedAtUtcUs,
          sport: head.sport,
          loadUnit: head.loadUnit,
          runCount: runs.length,
          measurementSource: head.measurementSource,
          lt1Load: lt1?.loadValue,
          lt2Load: lt2?.loadValue,
          lt1HeartRate: lt1?.heartRateBpm,
          lt2HeartRate: lt2?.heartRateBpm,
          lt1MethodId: latest?.selectedLt1MethodId,
          lt2MethodId: latest?.selectedLt2MethodId,
          latestRunId: latest?.id,
          protocol: head.protocol,
          modality: head.modality,
        ),
      );
    }

    final evaluated = history.where((entry) => entry.hasResult).toList();
    final latestTest = evaluated.isEmpty
        ? null
        : _buildTestView(
            heads.firstWhere((head) => head.id == evaluated.first.testId),
          );
    final previousSameSport = latestTest == null
        ? null
        : evaluated
              .skip(1)
              .where((entry) => entry.sport == latestTest.head.sport)
              .firstOrNull;
    final previousTest = previousSameSport == null
        ? null
        : _buildTestView(
            heads.firstWhere((head) => head.id == previousSameSport.testId),
          );

    // Der jüngste frühere Test, der sich mit dem letzten wirklich vergleichen
    // lässt. Es wird nicht auf einen unvergleichbaren Test ausgewichen.
    LalaTestView? previousComparableTest;
    if (latestTest != null) {
      for (final entry in evaluated.skip(1)) {
        final candidate = entry.testId == previousTest?.head.id
            ? previousTest!
            : _buildTestView(
                heads.firstWhere((head) => head.id == entry.testId),
              );
        if (LalaComparison.between(
          earlier: candidate,
          later: latestTest,
        ).comparable) {
          previousComparableTest = candidate;
          break;
        }
      }
    }

    return LalaAthleteOverview(
      athleteId: athleteId,
      athleteName: _athleteName(athleteId),
      history: history,
      latestTest: latestTest,
      previousTest: previousTest,
      previousComparableTest: previousComparableTest,
    );
  }

  LalaTestView _buildTestView(PerformanceTestHead head) => LalaTestView(
    head: head,
    data: diagnostics.loadTestData(head.id),
    runs: <LalaRunView>[
      for (final run in diagnostics.runsOfTest(head.id)) _buildRunView(run),
    ],
  );

  LalaRunView _buildRunView(CalculationRunRecord run) {
    final thresholds = diagnostics.thresholdsOfRun(run.id);
    final lt1Row = _selected(thresholds, run.selectedLt1MethodId, 'lt1');
    final lt2Row = _selected(thresholds, run.selectedLt2MethodId, 'lt2');

    return LalaRunView(
      id: run.id,
      testId: run.testId,
      runIndex: run.runIndex,
      engineVersion: run.engineVersion,
      engineSourceCommit: run.engineSourceCommit,
      createdAtUtcUs: run.createdAtUtcUs,
      stageCount: run.stageCount,
      inputFingerprint: run.inputFingerprint,
      outputFingerprint: run.outputFingerprint,
      coreInputHash: run.coreInputHash,
      triggeredByUserId: run.triggeredByUserId,
      lt1: lt1Row == null
          ? null
          : buildThresholdView(lt1Row, expertMethodId: run.expertLt1MethodId),
      lt2: lt2Row == null
          ? null
          : buildThresholdView(lt2Row, expertMethodId: run.expertLt2MethodId),
      allThresholds: <LalaThresholdView>[
        for (final row in thresholds)
          buildThresholdView(
            row,
            expertMethodId: row.thresholdType == 'lt1'
                ? run.expertLt1MethodId
                : run.expertLt2MethodId,
          ),
      ],
      zoneSets: <LalaZoneSetView>[
        for (final set in diagnostics.zoneSetsOfRun(run.id))
          LalaZoneSetView(
            id: set.id,
            modelId: set.modelId,
            modelName: set.modelName,
            modelVersion: set.modelVersion,
            quality: set.quality,
            loadUnit: set.loadUnit,
            zones: diagnostics.zonesOfSet(set.id),
            issues: diagnostics.issuesOfZoneSet(set.id),
          ),
      ],
    );
  }

  /// Picks the row a run named as selected.
  ///
  /// Matching is by method id and threshold type only. No preference rule is
  /// applied here — the run already recorded which method won.
  PersistedThresholdResult? _selected(
    List<PersistedThresholdResult> rows,
    String? methodId,
    String type,
  ) {
    if (methodId == null) return null;
    for (final row in rows) {
      if (row.methodId == methodId && row.thresholdType == type) return row;
    }
    return null;
  }

  String _athleteName(String athleteId) {
    final match = athletes.where((athlete) => athlete.id == athleteId);
    return match.isEmpty ? athleteId : match.first.name;
  }
}
