/// Deterministischer Builder für den XCAthleteState.
///
/// Baut aus den kanonischen Datenquellen ([NormalizedSession], [DiagnosticReference],
/// [SubjectiveReadinessState], [GoalContext]) den vollständigen Zustand des Athleten auf.
library;

import '../../domain/normalized_session.dart';
import '../../domain/normalized_session_stream_analysis.dart';
import '../../domain/normalized_session_adapters.dart'
    show isRunningDoseEvidence;
import '../../domain/xc_modality.dart';
import '../load/ewma_load_tracker.dart';
import '../load/load_calculator.dart';
import '../load/load_models.dart';
import '../load/stimulus_models.dart';
import 'aerobic_threshold_hit_states.dart';
import 'data_coverage_state.dart';
import 'diagnostics_state.dart';
import 'double_poling_state.dart';
import 'durability_state.dart';
import 'elite_analysis_state.dart';
import 'evidence_model.dart';
import 'goal_context.dart';
import 'performance_trend_state.dart';
import 'ski_exposure_state.dart';
import 'stimulus_history_state.dart';
import 'subjective_readiness_state.dart';
import 'training_load_state.dart';
import 'xc_athlete_state.dart';

class XCAthleteStateBuilder {
  const XCAthleteStateBuilder({
    this.loadCalculator = const LoadCalculator(),
    this.ewmaTracker = const EwmaLoadTracker(),
  });

  final LoadCalculator loadCalculator;
  final EwmaLoadTracker ewmaTracker;

  /// Baut den vollständigen, transparenten [XCAthleteState] auf.
  XCAthleteState buildState({
    required String athleteId,
    required DateTime asOf,
    List<NormalizedSession> sessions = const [],
    List<DiagnosticReference> diagnostics = const [],
    SubjectiveReadinessState subjectiveReadiness =
        const SubjectiveReadinessState(),
    Set<DateTime> confirmedRestDays = const {},
    GoalContext? goal,
    DateTime? lastStravaSync,
    DateTime? lastGarminSync,
    DateTime? lastErcolinaSession,
    List<DurabilityObservation> explicitDurabilityObservations = const [],
    AthletePhysiologyState physiology = const AthletePhysiologyState(),
    bool hasCompleteTrainingHistory = false,
    DateTime? completeTrainingHistoryThrough,
  }) {
    // Inputs may also arrive directly from an in-memory archive reader.
    sessions = sessions.where((s) => s.eligibleForCoach).toList(growable: false);
    // 1. Diagnostik aufbauen
    final diagState = _buildDiagnosticsState(diagnostics, asOf);
    final resolvedPhysiology = _resolvePhysiology(physiology, diagState);
    final loadPhysiology = _buildAthletePhysiology(
      resolvedPhysiology,
      diagState,
    );
    final hasIndividualMaxHeartRate =
        resolvedPhysiology.maxHeartRateBpm != null;
    final hasIndividualHeartRateReserve =
        hasIndividualMaxHeartRate &&
        resolvedPhysiology.restingHeartRateBpm != null;

    // 2. Skispezifische Exposition aufbauen
    final exposureState = _buildExposureState(sessions, asOf);

    // 3. Doppelstock / Ercolina Zustand
    final dpState = _buildDoublePolingState(sessions, asOf);

    // 4. Durability Zustand
    final durabilityState = _buildDurabilityState(
      sessions,
      asOf,
      explicitDurabilityObservations,
    );

    // 5. Belastungsverlauf (EWMA Zeitreihen getrennt nach Methoden)
    final loadState = _buildTrainingLoadState(
      sessions,
      asOf,
      confirmedRestDays,
      loadPhysiology,
      hasIndividualHeartRateReference: hasIndividualHeartRateReserve,
      hasCompleteTrainingHistory: hasCompleteTrainingHistory,
      completeTrainingHistoryThrough: completeTrainingHistoryThrough,
    );

    // 6. Stimulus-Historie (geplant vs beobachtet vs verifiziert)
    final stimHistory = _buildStimulusHistory(
      sessions,
      asOf,
      loadPhysiology,
      hasIndividualHeartRateReference: hasIndividualMaxHeartRate,
    );

    // 7. Aerobic, Threshold, High-Intensity
    final aerobicState = _buildAerobicState(
      sessions,
      asOf,
      diagState,
      loadPhysiology,
      hasIndividualHeartRateReference: hasIndividualMaxHeartRate,
    );
    final thresholdState = _buildThresholdState(
      sessions,
      asOf,
      diagState,
      loadPhysiology,
      hasIndividualHeartRateReference: hasIndividualMaxHeartRate,
    );
    final hitState = _buildHighIntensityState(
      sessions,
      asOf,
      diagState,
      loadPhysiology,
      hasIndividualHeartRateReference: hasIndividualMaxHeartRate,
    );

    // 8. Performance Trends (Apples-to-Apples)
    final trendState = _buildPerformanceTrends(sessions);

    // 9. Data Coverage
    final coverageState = _buildDataCoverage(
      sessions,
      asOf,
      confirmedRestDays,
      diagnostics,
      null,
      lastGarminSync,
      lastErcolinaSession,
    );

    final eliteAnalysis = _buildEliteAnalysis(
      sessions: sessions,
      asOf: asOf,
      physiology: resolvedPhysiology,
      diagnostics: diagState,
      doublePoling: dpState,
      durability: durabilityState,
    );

    return XCAthleteState(
      athleteId: athleteId,
      asOf: asOf,
      diagnostics: diagState,
      aerobic: aerobicState,
      threshold: thresholdState,
      highIntensity: hitState,
      skiExposure: exposureState,
      doublePoling: dpState,
      durability: durabilityState,
      trainingLoad: loadState,
      stimulusHistory: stimHistory,
      subjectiveReadiness: subjectiveReadiness,
      performanceTrends: trendState,
      dataCoverage: coverageState,
      eliteAnalysis: eliteAnalysis,
      goal: goal,
    );
  }

  DiagnosticsState _buildDiagnosticsState(
    List<DiagnosticReference> diagnostics,
    DateTime asOf,
  ) {
    if (diagnostics.isEmpty) {
      return const DiagnosticsState();
    }

    final byModality = <XcModality, DiagnosticReference>{};
    // Neueste Diagnostik je Modalität gewinnt
    final sorted = List<DiagnosticReference>.from(diagnostics)
      ..sort((a, b) => b.date.compareTo(a.date));

    for (final diag in sorted) {
      if (!byModality.containsKey(diag.modality)) {
        // Frische neu bewerten bezogen auf asOf
        final fresh = evaluateFreshness(diag.date, asOf: asOf);
        byModality[diag.modality] = DiagnosticReference(
          modality: diag.modality,
          date: diag.date,
          protocol: diag.protocol,
          lt1Ltp1Bpm: diag.lt1Ltp1Bpm,
          lt1Ltp1Watt: diag.lt1Ltp1Watt,
          lt1Ltp1PaceSecPerKm: diag.lt1Ltp1PaceSecPerKm,
          lt2Ltp2Bpm: diag.lt2Ltp2Bpm,
          lt2Ltp2Watt: diag.lt2Ltp2Watt,
          lt2Ltp2PaceSecPerKm: diag.lt2Ltp2PaceSecPerKm,
          vo2maxMlPerKgMin: diag.vo2maxMlPerKgMin,
          maxHeartRateBpm: diag.maxHeartRateBpm,
          source: diag.source,
          sourceId: diag.sourceId,
          freshness: fresh,
          confidence: diag.confidence,
          notes: diag.notes,
        );
      }
    }

    return DiagnosticsState(references: byModality);
  }

  AthletePhysiology _buildAthletePhysiology(
    AthletePhysiologyState profile,
    DiagnosticsState diagnostics,
  ) {
    final diagnosticMaxHeartRates = diagnostics.references.values
        .map((reference) => reference.maxHeartRateBpm)
        .whereType<double>();
    final maxHeartRate =
        profile.maxHeartRateBpm?.toDouble() ??
        (diagnosticMaxHeartRates.isEmpty
            ? null
            : diagnosticMaxHeartRates.reduce(
                (current, value) => value > current ? value : current,
              ));
    final lthr = <XcModality, double>{};
    final thresholdPower = <XcModality, double>{};
    for (final entry in diagnostics.references.entries) {
      if (entry.value.lt2Ltp2Bpm case final value?) {
        lthr[entry.key] = value;
      }
      if (entry.value.lt2Ltp2Watt case final value?) {
        thresholdPower[entry.key] = value;
      }
    }
    return AthletePhysiology(
      maxHeartRateBpm: maxHeartRate ?? 190,
      restingHeartRateBpm: profile.restingHeartRateBpm?.toDouble() ?? 50,
      isFemale: profile.isFemale,
      sportSpecificLthrBpm: Map.unmodifiable(lthr),
      sportSpecificThresholdPowerWatt: Map.unmodifiable(thresholdPower),
    );
  }

  AthletePhysiologyState _resolvePhysiology(
    AthletePhysiologyState profile,
    DiagnosticsState diagnostics,
  ) {
    final diagnosticMaxHeartRates = diagnostics.references.values
        .map((reference) => reference.maxHeartRateBpm)
        .whereType<double>();
    final diagnosticMaximum = diagnosticMaxHeartRates.isEmpty
        ? null
        : diagnosticMaxHeartRates.reduce(
            (current, value) => value > current ? value : current,
          );
    return AthletePhysiologyState(
      bodyMassKg: profile.bodyMassKg,
      maxHeartRateBpm: profile.maxHeartRateBpm ?? diagnosticMaximum?.round(),
      restingHeartRateBpm: profile.restingHeartRateBpm,
      sex: profile.sex,
    );
  }

  SkiSpecificExposureState _buildExposureState(
    List<NormalizedSession> sessions,
    DateTime asOf,
  ) {
    final modStats = <XcModality, _MutableModalityExposure>{};
    var totalNonSki28d = 0;

    for (final session in sessions) {
      final sessionDate = session.startedAtLocal;
      final ageDays = asOf.difference(sessionDate).inDays;
      if (ageDays < 0 || ageDays > 90) continue;

      // Eine Wanderung ist keine Laufexposition.
      //
      // Der Importadapter fasst `Run`, `Walk` und `Hike` zu
      // [XcModality.running] zusammen — fuer ein Trainingstagebuch
      // vertretbar, es war in allen Faellen zu Fuss. Fuer die Frage, welche
      // *Laufdauer* ein Athlet gewohnt ist, ist es falsch: Am 05.10.2026
      // waren von siebzehn «Lauf»-Einheiten des Jahres neun Wanderungen —
      // und zwar alle langen. Die laengste echte Laufeinheit dauerte 57
      // Minuten, die laengste als Laufen gefuehrte Einheit 229.
      //
      // Die Einheit bleibt gespeichert, wie sie ist; sie beantwortet nur
      // diese eine Frage nicht mehr. Die Rohsportart der Quelle steht dafuer
      // in [NormalizedSession.rawMetadata] — es braucht keine Enum-Migration
      // und keine Wander-Taxonomie.
      if (!isRunningDoseEvidence(session)) continue;

      final durSec = session.movingTimeSeconds;
      final distM = session.distanceMetres;
      final elevM = session.elevationGainMetres;
      final modality = session.modality;

      final isSkiOrSpecific =
          modality.isSkiing ||
          modality == XcModality.rollerSkiSkating ||
          modality == XcModality.rollerSkiClassic ||
          modality == XcModality.rollerSkiDoublePoling ||
          modality == XcModality.ercolinaDoublePoling;

      if (!isSkiOrSpecific && ageDays <= 28) {
        totalNonSki28d += durSec;
      }

      final stat = modStats.putIfAbsent(
        modality,
        () => _MutableModalityExposure(modality),
      );

      if (stat.lastSessionDate == null ||
          sessionDate.isAfter(stat.lastSessionDate!)) {
        stat.lastSessionDate = sessionDate;
      }

      if (ageDays <= 7) {
        stat.duration7d += durSec;
        stat.count7d += 1;
        if (distM != null) stat.dist7d = (stat.dist7d ?? 0) + distM;
        if (elevM != null) stat.elev7d = (stat.elev7d ?? 0) + elevM;
      }
      if (ageDays <= 28) {
        stat.duration28d += durSec;
        stat.count28d += 1;
        if (distM != null) stat.dist28d = (stat.dist28d ?? 0) + distM;
        if (elevM != null) stat.elev28d = (stat.elev28d ?? 0) + elevM;
        if (durSec > stat.longestSec28d) stat.longestSec28d = durSec;
      }
      if (ageDays <= 90) {
        stat.duration90d += durSec;
        stat.count90d += 1;
        if (distM != null) stat.dist90d = (stat.dist90d ?? 0) + distM;
        if (elevM != null) stat.elev90d = (stat.elev90d ?? 0) + elevM;
        if (durSec > stat.longestSec90d) stat.longestSec90d = durSec;
        stat.durationsSec90d.add(durSec);
      }
    }

    final immutableMap = modStats.map(
      (k, v) => MapEntry(k, v.toImmutable(asOf: asOf)),
    );

    return SkiSpecificExposureState(
      byModality: immutableMap,
      totalNonSkiDurationSeconds28d: totalNonSki28d,
    );
  }

  DoublePolingState _buildDoublePolingState(
    List<NormalizedSession> sessions,
    DateTime asOf,
  ) {
    final dpSessions =
        sessions
            .where((s) => s.modality == XcModality.ercolinaDoublePoling)
            .toList()
          ..sort((a, b) => b.startedAtUtcUs.compareTo(a.startedAtUtcUs));

    if (dpSessions.isEmpty) {
      return const DoublePolingState();
    }

    final latest = dpSessions.first;
    var totalWorkJoule28d = 0.0;
    final recentIds = <String>[];

    for (final s in dpSessions) {
      final ageDays = asOf.difference(s.startedAtLocal).inDays;
      if (ageDays >= 0 && ageDays <= 28) {
        recentIds.add(s.id);
        if (s.externalMetrics.workJoule != null) {
          totalWorkJoule28d += s.externalMetrics.workJoule!;
        }
      }
    }

    final calibConf = latest.dataQuality.calibrationConfidence;
    final diagConf = calibConf != null
        ? (calibConf * latest.dataQuality.confidence).clamp(0.1, 1.0)
        : (0.40 * latest.dataQuality.confidence).clamp(0.1, 1.0);

    return DoublePolingState(
      recentSessionAveragePowerWatt:
          latest.externalMetrics.sessionAveragePowerWatt ??
          latest.externalMetrics.averagePowerWatt,
      workPhaseAveragePowerWatt:
          latest.externalMetrics.workPhaseAveragePowerWatt,
      peakPowerWatt: latest.externalMetrics.peakPowerWatt,
      totalWorkJoule28d: totalWorkJoule28d > 0 ? totalWorkJoule28d : null,
      recentStrokeRate: latest.externalMetrics.strokeOrCadenceRate,
      recentWorkPerStrokeJoule:
          (latest.externalMetrics.workJoule != null &&
              (latest.externalMetrics.strokeCount ?? 0) > 0)
          ? latest.externalMetrics.workJoule! /
                latest.externalMetrics.strokeCount!
          : null,
      leftRightBalancePercent: latest.externalMetrics.leftRightSymmetryPercent,
      calibrationConfidence: calibConf,
      diagnosticConfidence: diagConf,
      lastSessionAt: latest.startedAtLocal,
      recentSessionIds: recentIds,
    );
  }

  DurabilityState _buildDurabilityState(
    List<NormalizedSession> sessions,
    DateTime asOf,
    List<DurabilityObservation> explicitObservations,
  ) {
    var longExposureSec = 0;
    var longCount = 0;

    for (final s in sessions) {
      final ageDays = asOf.difference(s.startedAtLocal).inDays;
      if (ageDays >= 0 && ageDays <= 28) {
        if (s.movingTimeSeconds >= 5400 && s.modality.isSkiing) {
          // >= 90 min
          longExposureSec += s.movingTimeSeconds;
          longCount += 1;
        }
      }
    }

    return DurabilityState(
      longSessionExposureHours28d: longExposureSec / 3600.0,
      longSessionCount28d: longCount,
      observations: explicitObservations,
      confidence: explicitObservations.isNotEmpty ? 0.90 : 0.50,
    );
  }

  TrainingLoadState _buildTrainingLoadState(
    List<NormalizedSession> sessions,
    DateTime asOf,
    Set<DateTime> confirmedRestDays,
    AthletePhysiology physiology, {
    required bool hasIndividualHeartRateReference,
    required bool hasCompleteTrainingHistory,
    DateTime? completeTrainingHistoryThrough,
  }) {
    if (sessions.isEmpty && confirmedRestDays.isEmpty) {
      return const TrainingLoadState();
    }

    // Die EWMA braucht ihre gesamte Vorgeschichte. Eine 42-Tage-Zeitkonstante
    // darf nicht aus nur 28 Tagen mit einem künstlichen Nullzustand gestartet
    // werden. Die Reihe beginnt deshalb am ersten beobachteten Trainingstag.
    final asOfLocal = asOf.toLocal();
    final asOfDay = DateTime(asOfLocal.year, asOfLocal.month, asOfLocal.day);
    final completeThroughLocal = completeTrainingHistoryThrough?.toLocal();
    final completeThroughDay = completeThroughLocal == null
        ? null
        : DateTime(
            completeThroughLocal.year,
            completeThroughLocal.month,
            completeThroughLocal.day,
          );
    final eligibleSessions = sessions
        .where((session) => !session.startedAtLocal.isAfter(asOfLocal))
        .toList();
    final earliestSession = eligibleSessions.isEmpty
        ? null
        : eligibleSessions.reduce(
            (earlier, candidate) =>
                candidate.startedAtUtcUs < earlier.startedAtUtcUs
                ? candidate
                : earlier,
          );
    final earliestRest = confirmedRestDays.isEmpty
        ? null
        : confirmedRestDays.reduce(
            (earlier, candidate) =>
                candidate.isBefore(earlier) ? candidate : earlier,
          );
    final earliestDate = earliestSession?.startedAtLocal;
    final rawStart = earliestDate == null
        ? earliestRest!
        : earliestRest == null || earliestDate.isBefore(earliestRest)
        ? earliestDate
        : earliestRest;
    final startDate = DateTime(rawStart.year, rawStart.month, rawStart.day);
    final dayCount = asOfDay.difference(startDate).inDays + 1;

    // Sessions nach Tag gruppieren
    final sessionsByDay = <String, List<NormalizedSession>>{};
    for (final s in eligibleSessions) {
      final d = s.startedAtLocal;
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      sessionsByDay.putIfAbsent(key, () => []).add(s);
    }

    final confirmedKeys = confirmedRestDays
        .map(
          (d) =>
              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
        )
        .toSet();

    final trimpInputs = <EwmaDailyInput>[];
    final srpeInputs = <EwmaDailyInput>[];
    final workInputs = <EwmaDailyInput>[];
    var hasTrimp = false;
    var hasSrpe = false;
    var hasWork = false;

    for (var i = 0; i < dayCount; i++) {
      final date = startDate.add(Duration(days: i));
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final daySessions = sessionsByDay[key];

      if (daySessions != null && daySessions.isNotEmpty) {
        var dayTrimp = 0.0;
        var daySrpe = 0.0;
        var dayWorkKj = 0.0;
        var dayHasTrimp = false;
        var dayHasSrpe = false;
        var dayHasWork = false;

        for (final s in daySessions) {
          final load = loadCalculator.calculateLoad(
            s,
            physiology: physiology,
            allowGenericHeartRateReference: hasIndividualHeartRateReference,
          );
          if (load.internal.trimpBanister != null) {
            dayTrimp += load.internal.trimpBanister!;
            dayHasTrimp = true;
            hasTrimp = true;
          }
          if (load.perceived.srpeLoad != null) {
            daySrpe += load.perceived.srpeLoad!;
            dayHasSrpe = true;
            hasSrpe = true;
          }
          if (load.external.workKiloJoule != null) {
            dayWorkKj += load.external.workKiloJoule!;
            dayHasWork = true;
            hasWork = true;
          }
        }

        trimpInputs.add(
          EwmaDailyInput(
            date: date,
            load: dayTrimp,
            classification: dayHasTrimp
                ? DayClassification.observedTrainingDay
                : DayClassification.unknownDay,
          ),
        );
        srpeInputs.add(
          EwmaDailyInput(
            date: date,
            load: daySrpe,
            classification: dayHasSrpe
                ? DayClassification.observedTrainingDay
                : DayClassification.unknownDay,
          ),
        );
        workInputs.add(
          EwmaDailyInput(
            date: date,
            load: dayWorkKj,
            classification: dayHasWork
                ? DayClassification.observedTrainingDay
                : DayClassification.unknownDay,
          ),
        );
      } else if (confirmedKeys.contains(key) ||
          (hasCompleteTrainingHistory &&
              (completeThroughDay == null ||
                  !date.isAfter(completeThroughDay)))) {
        trimpInputs.add(
          EwmaDailyInput(
            date: date,
            load: 0.0,
            classification: DayClassification.confirmedRestDay,
          ),
        );
        srpeInputs.add(
          EwmaDailyInput(
            date: date,
            load: 0.0,
            classification: DayClassification.confirmedRestDay,
          ),
        );
        workInputs.add(
          EwmaDailyInput(
            date: date,
            load: 0.0,
            classification: DayClassification.confirmedRestDay,
          ),
        );
      } else {
        trimpInputs.add(
          EwmaDailyInput(
            date: date,
            load: 0.0,
            classification: DayClassification.unknownDay,
          ),
        );
        srpeInputs.add(
          EwmaDailyInput(
            date: date,
            load: 0.0,
            classification: DayClassification.unknownDay,
          ),
        );
        workInputs.add(
          EwmaDailyInput(
            date: date,
            load: 0.0,
            classification: DayClassification.unknownDay,
          ),
        );
      }
    }

    final athleteId = sessions.isNotEmpty
        ? sessions.first.athleteId
        : 'unknown';
    // Confirmed rest is observed zero load even without an HR measurement.
    // Unknown or unmeasured training days remain unknown in the inputs.
    final hasKnownRest = trimpInputs.any(
      (day) => day.classification == DayClassification.confirmedRestDay,
    );
    final trimpSeries = !hasTrimp && !hasKnownRest
        ? null
        : ewmaTracker.computeSeries(
            seriesId: 'series_banister_trimp',
            athleteId: athleteId,
            method: 'banister_trimp',
            unit: 'trimp_points',
            version: '2.0',
            inputs: trimpInputs,
            parameters: {
              'individualHeartRateReference': hasTrimp,
              'historyStart': startDate.toIso8601String(),
            },
          );

    final srpeSeries = !hasSrpe && !hasKnownRest
        ? null
        : ewmaTracker.computeSeries(
            seriesId: 'series_srpe_load',
            athleteId: athleteId,
            method: 'srpe_load',
            unit: 'srpe_points',
            version: '2.0',
            inputs: srpeInputs,
            parameters: {'historyStart': startDate.toIso8601String()},
          );

    final workSeries = !hasWork && !hasKnownRest
        ? null
        : ewmaTracker.computeSeries(
            seriesId: 'series_work_kj',
            athleteId: athleteId,
            method: 'work_kj',
            unit: 'kj',
            version: '2.0',
            inputs: workInputs,
            parameters: {'historyStart': startDate.toIso8601String()},
          );

    final last28 = trimpInputs.length > 28
        ? trimpInputs.sublist(trimpInputs.length - 28)
        : trimpInputs;
    final knownDays28 = last28
        .where((input) => input.classification != DayClassification.unknownDay)
        .length;

    return TrainingLoadState(
      banisterTrimpSeries: trimpSeries,
      srpeSeries: srpeSeries,
      workKjSeries: workSeries,
      dataCoverageRatio28d: last28.isEmpty ? 0 : knownDays28 / last28.length,
    );
  }

  StimulusHistoryState _buildStimulusHistory(
    List<NormalizedSession> sessions,
    DateTime asOf,
    AthletePhysiology physiology, {
    required bool hasIndividualHeartRateReference,
  }) {
    final entryMap = <StimulusType, _MutableStimulusHistoryEntry>{};

    for (final s in sessions) {
      final ledger = loadCalculator.calculateStimuli(
        s,
        physiology: physiology,
        allowGenericHeartRateReference: hasIndividualHeartRateReference,
      );
      final sessionDate = s.startedAtLocal;
      final ageDays = asOf.difference(sessionDate).inDays;

      for (final stim in ledger.stimuli) {
        final entry = entryMap.putIfAbsent(
          stim.type,
          () => _MutableStimulusHistoryEntry(stim.type),
        );

        if (stim.origin == StimulusOrigin.planned ||
            stim.origin == StimulusOrigin.verified) {
          if (entry.lastPlannedAt == null ||
              sessionDate.isAfter(entry.lastPlannedAt!)) {
            entry.lastPlannedAt = sessionDate;
          }
        }
        if (stim.origin == StimulusOrigin.observed ||
            stim.origin == StimulusOrigin.verified) {
          if (entry.lastObservedAt == null ||
              sessionDate.isAfter(entry.lastObservedAt!)) {
            entry.lastObservedAt = sessionDate;
            entry.sourceModality = s.modality;
          }
        }
        if (stim.origin == StimulusOrigin.verified) {
          if (entry.lastVerifiedAt == null ||
              sessionDate.isAfter(entry.lastVerifiedAt!)) {
            entry.lastVerifiedAt = sessionDate;
          }
        }

        if (ageDays >= 0 && ageDays <= 28 && stim.isObserved) {
          entry.frequency28d += 1;
          entry.accumulatedMin28d += s.movingTimeSeconds / 60.0;
          if (!entry.recentSessionIds.contains(s.id)) {
            entry.recentSessionIds.add(s.id);
          }
        }
      }
    }

    final result = <StimulusType, StimulusHistoryEntry>{};
    for (final type in StimulusType.values) {
      final mut = entryMap[type];
      if (mut != null) {
        result[type] = mut.toImmutable();
      } else {
        result[type] = StimulusHistoryEntry(type: type);
      }
    }

    return StimulusHistoryState(entries: result);
  }

  AerobicState _buildAerobicState(
    List<NormalizedSession> sessions,
    DateTime asOf,
    DiagnosticsState diagState,
    AthletePhysiology physiology, {
    required bool hasIndividualHeartRateReference,
  }) {
    var sec7d = 0;
    var sec28d = 0;
    var sec90d = 0;
    var count28d = 0;

    for (final s in sessions) {
      final ageDays = asOf.difference(s.startedAtLocal).inDays;
      if (ageDays < 0 || ageDays > 90) continue;

      final ledger = loadCalculator.calculateStimuli(
        s,
        physiology: physiology,
        allowGenericHeartRateReference: hasIndividualHeartRateReference,
      );
      if (ledger.hasStimulus(StimulusType.aerobicBase)) {
        if (ageDays <= 7) sec7d += s.movingTimeSeconds;
        if (ageDays <= 28) {
          sec28d += s.movingTimeSeconds;
          count28d += 1;
        }
        if (ageDays <= 90) sec90d += s.movingTimeSeconds;
      }
    }

    Evidence<double>? diagLt1;
    final skRef = diagState.skating;
    if (skRef?.lt1Ltp1Watt != null) {
      diagLt1 = Evidence<double>(
        id: 'diag_lt1_skating',
        value: skRef!.lt1Ltp1Watt!,
        measuredAtUtcUs: skRef.date.microsecondsSinceEpoch,
        source: skRef.source,
        modality: XcModality.skiSkating,
        method: skRef.protocol,
        confidence: skRef.confidence,
        freshness: skRef.freshness,
        provenance: 'lab_diagnostics',
        unit: 'W',
      );
    }

    return AerobicState(
      diagnosticLt1Evidence: diagLt1,
      lowIntensityDurationSeconds7d: sec7d,
      lowIntensityDurationSeconds28d: sec28d,
      lowIntensityDurationSeconds90d: sec90d,
      aerobicSessionCount28d: count28d,
    );
  }

  ThresholdState _buildThresholdState(
    List<NormalizedSession> sessions,
    DateTime asOf,
    DiagnosticsState diagState,
    AthletePhysiology physiology, {
    required bool hasIndividualHeartRateReference,
  }) {
    final threshSessions = <String>[];
    for (final s in sessions) {
      final ageDays = asOf.difference(s.startedAtLocal).inDays;
      if (ageDays >= 0 && ageDays <= 28) {
        final ledger = loadCalculator.calculateStimuli(
          s,
          physiology: physiology,
          allowGenericHeartRateReference: hasIndividualHeartRateReference,
        );
        if (ledger.hasStimulus(StimulusType.threshold)) {
          threshSessions.add(s.id);
        }
      }
    }

    Evidence<double>? diagLt2;
    final skRef = diagState.skating;
    if (skRef?.lt2Ltp2Watt != null) {
      diagLt2 = Evidence<double>(
        id: 'diag_lt2_skating',
        value: skRef!.lt2Ltp2Watt!,
        measuredAtUtcUs: skRef.date.microsecondsSinceEpoch,
        source: skRef.source,
        modality: XcModality.skiSkating,
        method: skRef.protocol,
        confidence: skRef.confidence,
        freshness: skRef.freshness,
        provenance: 'lab_diagnostics',
        unit: 'W',
      );
    }

    return ThresholdState(
      diagnosticLt2Evidence: diagLt2,
      recentThresholdSessionIds: threshSessions,
      thresholdSessionCount28d: threshSessions.length,
    );
  }

  HighIntensityState _buildHighIntensityState(
    List<NormalizedSession> sessions,
    DateTime asOf,
    DiagnosticsState diagState,
    AthletePhysiology physiology, {
    required bool hasIndividualHeartRateReference,
  }) {
    final hitSessions = <String>[];
    var z5Sec28d = 0;

    for (final s in sessions) {
      final ageDays = asOf.difference(s.startedAtLocal).inDays;
      if (ageDays >= 0 && ageDays <= 28) {
        final ledger = loadCalculator.calculateStimuli(
          s,
          physiology: physiology,
          allowGenericHeartRateReference: hasIndividualHeartRateReference,
        );
        if (ledger.hasStimulus(StimulusType.vo2max)) {
          hitSessions.add(s.id);
        }
        final z5 = s.internalMetrics.timeInHrZonesSeconds['z5'] ?? 0;
        z5Sec28d += z5;
      }
    }

    Evidence<double>? vo2Evidence;
    final skRef = diagState.skating;
    if (skRef?.vo2maxMlPerKgMin != null) {
      vo2Evidence = Evidence<double>(
        id: 'diag_vo2max_skating',
        value: skRef!.vo2maxMlPerKgMin!,
        measuredAtUtcUs: skRef.date.microsecondsSinceEpoch,
        source: skRef.source,
        modality: XcModality.skiSkating,
        method: skRef.protocol,
        confidence: skRef.confidence,
        freshness: skRef.freshness,
        provenance: 'spiroergometry',
        unit: 'ml/kg/min',
      );
    }

    return HighIntensityState(
      diagnosticVo2maxEvidence: vo2Evidence,
      recentHitSessionIds: hitSessions,
      hitSessionCount28d: hitSessions.length,
      accumulatedZ5DurationSeconds28d: z5Sec28d,
    );
  }

  PerformanceTrendState _buildPerformanceTrends(
    List<NormalizedSession> sessions,
  ) {
    if (sessions.length < 2) {
      return const PerformanceTrendState();
    }

    final comparisons = <ComparableSessionComparison>[];
    // Vergleiche nur Ercolina-Einheiten gleicher benannter Struktur und
    // ähnlicher Dauer. Dauer allein wäre bei freiem Training kein belastbarer
    // Nachweis identischer Bedingungen.
    final ercolinaSessions =
        sessions
            .where(
              (s) =>
                  s.modality == XcModality.ercolinaDoublePoling &&
                  s.externalMetrics.hasPower,
            )
            .toList()
          ..sort((a, b) => a.startedAtUtcUs.compareTo(b.startedAtUtcUs));

    if (ercolinaSessions.length >= 2) {
      for (var i = 0; i < ercolinaSessions.length - 1; i++) {
        final a = ercolinaSessions[i];
        final b = ercolinaSessions[i + 1];

        final durRatio =
            b.durationSeconds / (a.durationSeconds > 0 ? a.durationSeconds : 1);
        final sameNamedStructure =
            a.title.trim().toLowerCase() == b.title.trim().toLowerCase();
        final calibrationA = a.dataQuality.calibrationConfidence;
        final calibrationB = b.dataQuality.calibrationConfidence;
        final calibrationClassComparable =
            (calibrationA == null && calibrationB == null) ||
            (calibrationA != null &&
                calibrationB != null &&
                ((calibrationA >= .85 && calibrationB >= .85) ||
                    (calibrationA < .85 && calibrationB < .85)));
        if (sameNamedStructure &&
            calibrationClassComparable &&
            durRatio >= 0.85 &&
            durRatio <= 1.15) {
          final pwrA =
              a.externalMetrics.workPhaseAveragePowerWatt ??
              a.externalMetrics.sessionAveragePowerWatt ??
              a.externalMetrics.averagePowerWatt ??
              0.0;
          final pwrB =
              b.externalMetrics.workPhaseAveragePowerWatt ??
              b.externalMetrics.sessionAveragePowerWatt ??
              b.externalMetrics.averagePowerWatt ??
              0.0;
          if (pwrA <= 0 || pwrB <= 0) continue;
          final deltaPwr = pwrB - pwrA;
          final comparablePower = (pwrB - pwrA).abs() / pwrA <= .05;
          final hrA = a.internalMetrics.averageHeartRateBpm;
          final hrB = b.internalMetrics.averageHeartRateBpm;
          final rpeA = a.internalMetrics.rpe;
          final rpeB = b.internalMetrics.rpe;
          final hasValidatedCalibration =
              (calibrationA ?? 0) >= .85 && (calibrationB ?? 0) >= .85;

          comparisons.add(
            ComparableSessionComparison(
              sessionAId: a.id,
              sessionBId: b.id,
              modality: XcModality.ercolinaDoublePoling,
              comparisonType: 'ercolina_gleiche_struktur_und_dauer',
              powerDeltaWatt: deltaPwr,
              hrDeltaAtComparablePower:
                  comparablePower && hrA != null && hrB != null
                  ? hrB - hrA
                  : null,
              rpeDeltaAtComparableWork:
                  comparablePower && rpeA != null && rpeB != null
                  ? rpeB - rpeA
                  : null,
              confidence: hasValidatedCalibration ? 0.90 : 0.60,
              evidenceSummary:
                  'Gleicher Einheitsname und ähnliche Dauer: '
                  '${deltaPwr >= 0 ? "+" : ""}${deltaPwr.toStringAsFixed(1)} W Veränderung'
                  '${hasValidatedCalibration ? "" : "; absolute Kalibrierung nicht validiert"}',
            ),
          );
        }
      }
    }

    return PerformanceTrendState(comparisons: comparisons);
  }

  DataCoverageState _buildDataCoverage(
    List<NormalizedSession> sessions,
    DateTime asOf,
    Set<DateTime> confirmedRestDays,
    List<DiagnosticReference> diagnostics,
    DateTime? lastStravaSync,
    DateTime? lastGarminSync,
    DateTime? lastErcolinaSession,
  ) {
    final confirmedDates = confirmedRestDays
        .map(
          (d) =>
              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
        )
        .toSet();

    final sessionDays = <String>{};
    var recentSessionCount = 0;
    var hrSessions = 0;
    var powerSessions = 0;

    for (final s in sessions) {
      final d = s.startedAtLocal;
      final ageDays = asOf.difference(d).inDays;
      if (ageDays >= 0 && ageDays <= 28) {
        recentSessionCount++;
        final key =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        sessionDays.add(key);
        if (s.internalMetrics.hasHeartRate) hrSessions++;
        if (s.externalMetrics.hasPower) powerSessions++;
      }
    }

    var unknownDays = 0;
    final startDate = DateTime.utc(
      asOf.year,
      asOf.month,
      asOf.day,
    ).subtract(const Duration(days: 27));

    for (var i = 0; i < 28; i++) {
      final date = startDate.add(Duration(days: i));
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      if (!sessionDays.contains(key) && !confirmedDates.contains(key)) {
        unknownDays++;
      }
    }

    final totalSess = recentSessionCount > 0 ? recentSessionCount : 1;

    return DataCoverageState(
      lastStravaSync: lastStravaSync,
      lastGarminSync: lastGarminSync,
      lastErcolinaSession: lastErcolinaSession,
      hrCoverage: sessions.isNotEmpty ? hrSessions / totalSess : 1.0,
      powerCoverage: sessions.isNotEmpty ? powerSessions / totalSess : 1.0,
      diagnosticsCoverage: diagnostics.isNotEmpty ? 1.0 : 0.0,
      unknownDays28d: unknownDays,
      confirmedRestDays28d: confirmedDates.length,
      observedTrainingDays28d: sessionDays.length,
    );
  }

  EliteAnalysisState _buildEliteAnalysis({
    required List<NormalizedSession> sessions,
    required DateTime asOf,
    required AthletePhysiologyState physiology,
    required DiagnosticsState diagnostics,
    required DoublePolingState doublePoling,
    required DurabilityState durability,
  }) {
    final asOfLocal = asOf.toLocal();
    final asOfDay = DateTime(asOfLocal.year, asOfLocal.month, asOfLocal.day);
    final eligible =
        sessions
            .where((session) => !session.startedAtLocal.isAfter(asOfLocal))
            .toList()
          ..sort((a, b) => a.startedAtUtcUs.compareTo(b.startedAtUtcUs));
    if (eligible.isEmpty) {
      return EliteAnalysisState(
        physiology: physiology,
        missingEvidence: [
          ...physiology.missing,
          'vollständige Trainingshistorie',
          'sportartspezifische Leistungsdiagnostik',
        ],
      );
    }

    final historyStart = eligible.first.startedAtLocal;
    final historyEnd = eligible.last.startedAtLocal;
    TrainingWindowAnalysis rolling(int days, String key, String label) {
      final start = asOfDay.subtract(Duration(days: days - 1));
      return _buildWindowAnalysis(
        sessions: eligible.where((session) {
          final day = _localDay(session.startedAtLocal);
          return !day.isBefore(start) && !day.isAfter(asOfDay);
        }).toList(),
        key: key,
        label: label,
        periodStart: start,
        periodEnd: asOfDay,
        physiology: physiology,
      );
    }

    final allStart = _localDay(historyStart);
    final allTime = _buildWindowAnalysis(
      sessions: eligible,
      key: 'all',
      label: 'Gesamte Zeit',
      periodStart: allStart,
      periodEnd: asOfDay,
      physiology: physiology,
    );
    final current28 = rolling(28, '28d', '28 Tage');
    final current90 = rolling(90, '90d', '90 Tage');
    final previous28 = _buildPreviousWindow(
      sessions: eligible,
      asOfDay: asOfDay,
      physiology: physiology,
      days: 28,
      key: 'previous28d',
      label: 'Vorherige 28 Tage',
    );
    final previous90 = _buildPreviousWindow(
      sessions: eligible,
      asOfDay: asOfDay,
      physiology: physiology,
      days: 90,
      key: 'previous90d',
      label: 'Vorherige 90 Tage',
    );

    final bests = <AthleteBestEvidence>[
      ?_bestEvidence(
        eligible,
        key: 'longest_duration',
        label: 'Längste aufgezeichnete Einheit',
        unit: 'min',
        valueOf: (session) => session.movingTimeSeconds / 60.0,
      ),
      ?_bestEvidence(
        eligible,
        key: 'longest_distance',
        label: 'Größte aufgezeichnete Distanz',
        unit: 'km',
        valueOf: (session) => session.distanceMetres == null
            ? null
            : session.distanceMetres! / 1000.0,
      ),
      ?_bestEvidence(
        eligible,
        key: 'highest_elevation',
        label: 'Meiste Höhenmeter in einer Einheit',
        unit: 'm',
        valueOf: (session) => session.elevationGainMetres,
      ),
      ?_bestEvidence(
        eligible,
        key: 'greatest_work',
        label: 'Größte gemessene mechanische Arbeit',
        unit: 'kJ',
        valueOf: (session) => session.externalMetrics.workJoule == null
            ? null
            : session.externalMetrics.workJoule! / 1000.0,
      ),
      ?_bestEvidence(
        eligible,
        key: 'peak_power',
        label: 'Höchste aufgezeichnete Leistungsprobe',
        unit: 'W',
        valueOf: _observedPeakPower,
        powerCaveat: true,
        caveat:
            'Höchster gespeicherter Zug oder Quell-Sample; kein standardisierter 5-s-, 1-min- oder Sprint-Test.',
      ),
      ?_bestEvidence(
        eligible
            .where(
              (session) => session.modality == XcModality.ercolinaDoublePoling,
            )
            .toList(),
        key: 'ercolina_work_phase_power',
        label: 'Beste Ercolina-Arbeitsphasenleistung',
        unit: 'W',
        valueOf: (session) => session.externalMetrics.workPhaseAveragePowerWatt,
        powerCaveat: true,
      ),
      ?_bestEvidence(
        eligible,
        key: 'highest_observed_heart_rate',
        label: 'Höchste aufgezeichnete Herzfrequenz',
        unit: 'bpm',
        valueOf: (session) =>
            session.internalMetrics.peakHeartRateBpm?.toDouble(),
        caveat:
            'Beobachteter Trainingswert; kein Ersatz für eine dokumentierte HFmax-Diagnostik.',
      ),
    ];

    final missing = <String>{
      ...physiology.missing,
      if (diagnostics.skating?.lt1Ltp1Watt == null &&
          diagnostics.skating?.lt1Ltp1Bpm == null)
        'Skating-LTP1 aus standardisierter Diagnostik',
      if (diagnostics.skating?.lt2Ltp2Watt == null &&
          diagnostics.skating?.lt2Ltp2Bpm == null)
        'Skating-LTP2 aus standardisierter Diagnostik',
      if (diagnostics.skating?.vo2maxMlPerKgMin == null)
        'spirometrisch gemessene VO2max',
      if (!durability.hasMeasuredObservations)
        'gemessene Durability/Entkopplung bei langer Belastung',
      if (!doublePoling.hasValidCalibration)
        'aktuelle reproduzierbare Ercolina-Fallgewichtskalibrierung',
      if (allTime.classifiedHrZoneSeconds == 0)
        'zeitaufgelöste Intensitätsverteilung',
      if (allTime.rpeSessionCoverage < 0.5) 'regelmäßiges Session-RPE',
      if (allTime.powerSessionCoverage == 0)
        'mechanische Leistung für Leistungs- und Ermüdungsprofile',
      'Schnee-, Temperatur-, Höhen- und Streckenbedingungen für normierte Außenvergleiche',
      'zeitaufgelöste Technik- und Zugphasendaten für Ermüdungsbiomechanik',
    };

    return EliteAnalysisState(
      physiology: physiology,
      historyStart: historyStart,
      historyEnd: historyEnd,
      latestGarminSessionId: eligible.reversed.where((s) => s.source == NormalizedSessionSource.garmin).firstOrNull?.id,
      windows: [
        rolling(7, '7d', '7 Tage'),
        current28,
        current90,
        rolling(180, '180d', '180 Tage'),
        rolling(365, '365d', '365 Tage'),
        allTime,
      ],
      months: _buildMonthlyHistory(eligible, asOfDay),
      personalBests: bests,
      volumeChange28dPercent: _relativeChange(
        current28.durationSeconds,
        previous28.durationSeconds,
      ),
      volumeChange90dPercent: _relativeChange(
        current90.durationSeconds,
        previous90.durationSeconds,
      ),
      missingEvidence: missing.toList(growable: false),
    );
  }

  TrainingWindowAnalysis _buildPreviousWindow({
    required List<NormalizedSession> sessions,
    required DateTime asOfDay,
    required AthletePhysiologyState physiology,
    required int days,
    required String key,
    required String label,
  }) {
    final end = asOfDay.subtract(Duration(days: days));
    final start = end.subtract(Duration(days: days - 1));
    return _buildWindowAnalysis(
      sessions: sessions.where((session) {
        final day = _localDay(session.startedAtLocal);
        return !day.isBefore(start) && !day.isAfter(end);
      }).toList(),
      key: key,
      label: label,
      periodStart: start,
      periodEnd: end,
      physiology: physiology,
    );
  }

  TrainingWindowAnalysis _buildWindowAnalysis({
    required List<NormalizedSession> sessions,
    required String key,
    required String label,
    required DateTime periodStart,
    required DateTime periodEnd,
    required AthletePhysiologyState physiology,
  }) {
    var durationSeconds = 0;
    var distanceMetres = 0.0;
    var elevationGainMetres = 0.0;
    var workJoule = 0.0;
    var withHeartRate = 0;
    var withHeartRateZones = 0;
    var withDerivedHeartRateZones = 0;
    var withPower = 0;
    var withRpe = 0;
    final modalities = <XcModality, int>{};
    final zones = <String, int>{};
    final activeDays = <DateTime>{};
    final activeWeeks = <int>{};

    for (final session in sessions) {
      durationSeconds += session.movingTimeSeconds;
      distanceMetres += session.distanceMetres ?? 0;
      elevationGainMetres += session.elevationGainMetres ?? 0;
      workJoule += session.externalMetrics.workJoule ?? 0;
      modalities.update(
        session.modality,
        (value) => value + session.movingTimeSeconds,
        ifAbsent: () => session.movingTimeSeconds,
      );
      final sourceZones = session.internalMetrics.timeInHrZonesSeconds;
      final effectiveZones = sourceZones.isNotEmpty
          ? sourceZones
          : _deriveHeartRateZones(
              session,
              maxHeartRateBpm: physiology.maxHeartRateBpm,
            );
      if (effectiveZones.isNotEmpty) {
        withHeartRateZones++;
        if (sourceZones.isEmpty) withDerivedHeartRateZones++;
      }
      for (final entry in effectiveZones.entries) {
        zones.update(
          entry.key,
          (value) => value + entry.value,
          ifAbsent: () => entry.value,
        );
      }
      if (session.internalMetrics.hasHeartRate) withHeartRate++;
      if (session.externalMetrics.hasPower) withPower++;
      if (session.internalMetrics.rpe != null) withRpe++;
      final day = _localDay(session.startedAtLocal);
      activeDays.add(day);
      activeWeeks.add(day.difference(periodStart).inDays ~/ 7);
    }

    return TrainingWindowAnalysis(
      key: key,
      label: label,
      periodDays: periodEnd.difference(periodStart).inDays + 1,
      sessionCount: sessions.length,
      activeDays: activeDays.length,
      activeWeeks: activeWeeks.length,
      durationSeconds: durationSeconds,
      distanceMetres: distanceMetres,
      elevationGainMetres: elevationGainMetres,
      workJoule: workJoule,
      modalityDurationSeconds: Map.unmodifiable(modalities),
      hrZoneSeconds: Map.unmodifiable(zones),
      sessionsWithHeartRate: withHeartRate,
      sessionsWithHeartRateZones: withHeartRateZones,
      sessionsWithDerivedHeartRateZones: withDerivedHeartRateZones,
      sessionsWithPower: withPower,
      sessionsWithRpe: withRpe,
      longestGapDays: _longestGap(
        activeDays.toList()..sort(),
        periodStart: periodStart,
        periodEnd: periodEnd,
      ),
    );
  }

  /// Leitet eine Zonenverteilung nur dann ab, wenn sowohl ein zeitaufgelöster
  /// Strava-HF-Stream als auch eine individuelle HFmax vorliegen. Zeitlücken,
  /// die deutlich größer als das normale Sampling-Intervall sind, werden
  /// ausgelassen statt mit der letzten HF aufgefüllt zu werden.
  Map<String, int> _deriveHeartRateZones(
    NormalizedSession session, {
    required int? maxHeartRateBpm,
  }) {
    if (maxHeartRateBpm == null || maxHeartRateBpm <= 0) return const {};
    final cached = heartRateZonesFromStreamFeatures(
      session.rawMetadata[normalizedStreamFeaturesKey],
      maxHeartRateBpm: maxHeartRateBpm,
    );
    if (cached.isNotEmpty) return cached;
    final streams = session.rawMetadata['streams'];
    if (streams is! Map) return const {};
    final heartRates = _streamNumbers(streams['heartrate']);
    final times = _streamNumbers(streams['time']);
    final sampleCount = heartRates.length < times.length
        ? heartRates.length
        : times.length;
    if (sampleCount < 2) return const {};

    final positiveIntervals = <int>[];
    for (var index = 0; index < sampleCount - 1; index++) {
      final interval = (times[index + 1] - times[index]).round();
      if (interval > 0) positiveIntervals.add(interval);
    }
    if (positiveIntervals.isEmpty) return const {};
    positiveIntervals.sort();
    final medianInterval = positiveIntervals[positiveIntervals.length ~/ 2];
    final largestContinuousInterval = medianInterval * 5 > 10
        ? medianInterval * 5
        : 10;
    final zones = <String, int>{};
    var classifiedSeconds = 0;

    for (var index = 0; index < sampleCount - 1; index++) {
      var interval = (times[index + 1] - times[index]).round();
      final heartRate = heartRates[index];
      if (interval <= 0 ||
          interval > largestContinuousInterval ||
          heartRate <= 0) {
        continue;
      }
      final remaining = session.movingTimeSeconds - classifiedSeconds;
      if (remaining <= 0) break;
      if (interval > remaining) interval = remaining;
      final ratio = heartRate / maxHeartRateBpm;
      final zone = ratio < .60
          ? 'z1'
          : ratio < .70
          ? 'z2'
          : ratio < .80
          ? 'z3'
          : ratio < .90
          ? 'z4'
          : 'z5';
      zones.update(zone, (value) => value + interval, ifAbsent: () => interval);
      classifiedSeconds += interval;
    }
    return Map.unmodifiable(zones);
  }

  List<double> _streamNumbers(dynamic stream) {
    final dynamic data = stream is Map ? stream['data'] : stream;
    if (data is! List) return const [];
    return data.whereType<num>().map((value) => value.toDouble()).toList();
  }

  List<MonthlyTrainingSummary> _buildMonthlyHistory(
    List<NormalizedSession> sessions,
    DateTime asOfDay,
  ) {
    if (sessions.isEmpty) return const [];
    final byMonth = <String, _MutableMonth>{};
    for (final session in sessions) {
      final date = session.startedAtLocal;
      final key = '${date.year}-${date.month}';
      final month = byMonth.putIfAbsent(
        key,
        () => _MutableMonth(date.year, date.month),
      );
      month.sessionCount++;
      month.durationSeconds += session.movingTimeSeconds;
      month.distanceMetres += session.distanceMetres ?? 0;
      month.elevationGainMetres += session.elevationGainMetres ?? 0;
      if (_isSkiSpecific(session.modality)) {
        month.skiSpecificDurationSeconds += session.movingTimeSeconds;
      }
    }
    final first = sessions.first.startedAtLocal;
    var cursor = DateTime(first.year, first.month);
    final end = DateTime(asOfDay.year, asOfDay.month);
    final result = <MonthlyTrainingSummary>[];
    while (!cursor.isAfter(end)) {
      final month =
          byMonth['${cursor.year}-${cursor.month}'] ??
          _MutableMonth(cursor.year, cursor.month);
      result.add(month.toImmutable());
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return result;
  }

  AthleteBestEvidence? _bestEvidence(
    List<NormalizedSession> sessions, {
    required String key,
    required String label,
    required String unit,
    required double? Function(NormalizedSession session) valueOf,
    bool powerCaveat = false,
    String? caveat,
  }) {
    NormalizedSession? bestSession;
    double? bestValue;
    for (final session in sessions) {
      final value = valueOf(session);
      if (value == null || !value.isFinite || value <= 0) continue;
      if (bestValue == null || value > bestValue) {
        bestValue = value;
        bestSession = session;
      }
    }
    if (bestSession == null || bestValue == null) return null;
    final calibrationCaveat =
        powerCaveat &&
            bestSession.modality == XcModality.ercolinaDoublePoling &&
            (bestSession.dataQuality.calibrationConfidence ?? 0) < 0.85
        ? 'Absolute Ercolina-Wattwerte sind ohne aktuelle validierte Kalibrierung nur intraindividuell interpretierbar.'
        : null;
    final caveats = [?caveat, ?calibrationCaveat];
    return AthleteBestEvidence(
      key: key,
      label: label,
      value: bestValue,
      unit: unit,
      achievedAt: bestSession.startedAtLocal,
      modality: bestSession.modality,
      sessionId: bestSession.id,
      source: bestSession.source.label,
      caveat: caveats.isEmpty ? null : caveats.join(' '),
    );
  }

  double? _observedPeakPower(NormalizedSession session) {
    final direct = session.externalMetrics.peakPowerWatt;
    final cached = peakPowerFromStreamFeatures(
      session.rawMetadata[normalizedStreamFeaturesKey],
    );
    final streams = session.rawMetadata['streams'];
    final samples = streams is Map
        ? _streamNumbers(streams['watts'])
        : const <double>[];
    final streamPeak = samples
        .where((value) => value.isFinite && value > 0)
        .fold<double?>(
          null,
          (current, value) =>
              current == null || value > current ? value : current,
        );
    final observed =
        cached == null || (streamPeak != null && streamPeak > cached)
        ? streamPeak
        : cached;
    if (direct == null) return observed;
    if (observed == null) return direct;
    return direct > observed ? direct : observed;
  }

  double? _relativeChange(int current, int previous) {
    if (previous <= 0) return null;
    return (current - previous) / previous * 100.0;
  }

  double _longestGap(
    List<DateTime> activeDays, {
    required DateTime periodStart,
    required DateTime periodEnd,
  }) {
    if (activeDays.isEmpty) {
      return (periodEnd.difference(periodStart).inDays + 1).toDouble();
    }
    var longest = activeDays.first.difference(periodStart).inDays.toDouble();
    for (var index = 1; index < activeDays.length; index++) {
      final gap =
          activeDays[index].difference(activeDays[index - 1]).inDays - 1;
      if (gap > longest) longest = gap.toDouble();
    }
    final tail = periodEnd.difference(activeDays.last).inDays.toDouble();
    if (tail > longest) longest = tail;
    return longest.clamp(0, double.infinity).toDouble();
  }

  DateTime _localDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _isSkiSpecific(XcModality modality) =>
      modality.isSkiing ||
      modality == XcModality.rollerSkiSkating ||
      modality == XcModality.rollerSkiClassic ||
      modality == XcModality.rollerSkiDoublePoling ||
      modality == XcModality.ercolinaDoublePoling;
}

class _MutableMonth {
  _MutableMonth(this.year, this.month);

  final int year;
  final int month;
  int sessionCount = 0;
  int durationSeconds = 0;
  double distanceMetres = 0;
  double elevationGainMetres = 0;
  int skiSpecificDurationSeconds = 0;

  MonthlyTrainingSummary toImmutable() => MonthlyTrainingSummary(
    year: year,
    month: month,
    sessionCount: sessionCount,
    durationSeconds: durationSeconds,
    distanceMetres: distanceMetres,
    elevationGainMetres: elevationGainMetres,
    skiSpecificDurationSeconds: skiSpecificDurationSeconds,
  );
}

class _MutableModalityExposure {
  _MutableModalityExposure(this.modality);
  final XcModality modality;
  int duration7d = 0;
  int count7d = 0;
  double? dist7d;
  double? elev7d;

  int duration28d = 0;
  int count28d = 0;
  double? dist28d;
  double? elev28d;

  int duration90d = 0;
  int count90d = 0;
  double? dist90d;
  double? elev90d;

  int longestSec28d = 0;
  int longestSec90d = 0;

  /// Alle Einheitsdauern im 90-Tage-Fenster, unsortiert.
  ///
  /// Ein Maximum allein sagt nicht, ob eine Dauer wiederholbar war: 368 und
  /// 364 Minuten nebeneinander sind ein Plateau, 229 neben einem Median von
  /// 57 ist ein Ausreisser. Beides unterscheidet nur die Verteilung.
  final List<int> durationsSec90d = [];
  DateTime? lastSessionDate;

  SkiModalityExposure toImmutable({DateTime? asOf}) {
    final daysSinceLast = (asOf != null && lastSessionDate != null)
        ? asOf.difference(lastSessionDate!).inDays
        : null;

    return SkiModalityExposure(
      modality: modality,
      durationSeconds7d: duration7d,
      sessionCount7d: count7d,
      distanceMetres7d: dist7d,
      elevationGainMetres7d: elev7d,
      durationSeconds28d: duration28d,
      sessionCount28d: count28d,
      distanceMetres28d: dist28d,
      elevationGainMetres28d: elev28d,
      durationSeconds90d: duration90d,
      sessionCount90d: count90d,
      distanceMetres90d: dist90d,
      elevationGainMetres90d: elev90d,
      longestSessionSeconds28d: longestSec28d,
      longestSessionSeconds90d: longestSec90d,
      durationsSeconds90d: List.unmodifiable(durationsSec90d),
      daysSinceLastSession: daysSinceLast,
    );
  }
}

class _MutableStimulusHistoryEntry {
  XcModality? sourceModality;
  _MutableStimulusHistoryEntry(this.type);
  final StimulusType type;
  DateTime? lastObservedAt;
  DateTime? lastPlannedAt;
  DateTime? lastVerifiedAt;
  int frequency28d = 0;
  double accumulatedMin28d = 0.0;
  final List<String> recentSessionIds = [];

  StimulusHistoryEntry toImmutable() => StimulusHistoryEntry(
    type: type,
    sourceModality: sourceModality,
    lastObservedAt: lastObservedAt,
    lastPlannedAt: lastPlannedAt,
    lastVerifiedAt: lastVerifiedAt,
    frequency28d: frequency28d,
    accumulatedExposureMinutes28d: accumulatedMin28d,
    recentSessionIds: List.unmodifiable(recentSessionIds),
  );
}
