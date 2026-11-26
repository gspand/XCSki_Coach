import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/domain/normalized_session.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:xc_coach/intelligence/load/load_models.dart';
import 'package:xc_coach/intelligence/load/stimulus_models.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/diagnostics_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/elite_analysis_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/evidence_model.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/goal_context.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/subjective_readiness_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/xc_athlete_state_builder.dart';

void main() {
  group('Schritt 3 – XCAthleteState & Readiness Evidence (20 Kern-Tests)', () {
    const builder = XCAthleteStateBuilder();
    const athleteId = 'xc_athlete_test_1';
    final asOf = DateTime.utc(2026, 10, 3, 12, 0);

    test('1. Historischer Rad-LTP2 bleibt Cycling Evidence', () {
      final diag = DiagnosticReference(
        modality: XcModality.cycling,
        date: DateTime.utc(2024, 6, 1), // 2 Jahre alt
        protocol: 'FTP 20min Test',
        lt2Ltp2Watt: 285.0,
        lt2Ltp2Bpm: 172.0,
        source: 'zwift_lab',
        sourceId: 'diag_bike_2024',
        freshness: FreshnessLevel.historical,
      );

      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        diagnostics: [diag],
      );

      expect(state.diagnostics.hasReferenceFor(XcModality.cycling), isTrue);
      expect(state.diagnostics.cycling?.lt2Ltp2Watt, 285.0);
      expect(state.diagnostics.cycling?.freshness, FreshnessLevel.historical);
    });

    test('2. Historischer Lauf-LTP2 bleibt Running Evidence', () {
      final diag = DiagnosticReference(
        modality: XcModality.running,
        date: DateTime.utc(2025, 4, 15),
        protocol: 'Laufband Laktat-Stufentest',
        lt2Ltp2Bpm: 175.0,
        lt2Ltp2PaceSecPerKm: 235.0, // 3:55 min/km
        source: 'med_base_zurich',
        sourceId: 'diag_run_2025',
        freshness: FreshnessLevel.stale,
      );

      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        diagnostics: [diag],
      );

      expect(state.diagnostics.hasReferenceFor(XcModality.running), isTrue);
      expect(state.diagnostics.running?.lt2Ltp2Bpm, 175.0);
      expect(state.diagnostics.running?.protocol, 'Laufband Laktat-Stufentest');
    });

    test('3. Keine Skating-Schwelle wird aus Rad/Lauf erfunden', () {
      final diagBike = DiagnosticReference(
        modality: XcModality.cycling,
        date: DateTime.utc(2025, 5, 1),
        protocol: 'FTP Test',
        lt2Ltp2Watt: 300.0,
        source: 'bike_lab',
        freshness: FreshnessLevel.stale,
      );
      final diagRun = DiagnosticReference(
        modality: XcModality.running,
        date: DateTime.utc(2025, 5, 1),
        protocol: 'Laufbandtest',
        lt2Ltp2Bpm: 176.0,
        source: 'run_lab',
        freshness: FreshnessLevel.stale,
      );

      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        diagnostics: [diagBike, diagRun],
      );

      // Skating MUSS null/unknown sein!
      expect(state.diagnostics.hasReferenceFor(XcModality.skiSkating), isFalse);
      expect(state.diagnostics.skating, isNull);
      expect(state.diagnostics.hasCurrentSkatingDiagnostics, isFalse);
    });

    test(
      '4. Neue Skating-Diagnostik wird aktuellste relevante Evidence, überschreibt Altes nicht destruktiv',
      () {
        final oldSkate = DiagnosticReference(
          modality: XcModality.skiSkating,
          date: DateTime.utc(2025, 1, 15),
          protocol: 'Feldstufentest Davos',
          lt2Ltp2Watt: null,
          lt2Ltp2Bpm: 168.0,
          source: 'swiss_ski_test_1',
          freshness: FreshnessLevel.stale,
        );
        final newSkate = DiagnosticReference(
          modality: XcModality.skiSkating,
          date: DateTime.utc(2026, 9, 20), // 2 Wochen vor asOf
          protocol: 'Rollski-Laufband Spiroergometrie',
          lt2Ltp2Watt: 240.0,
          lt2Ltp2Bpm: 171.0,
          vo2maxMlPerKgMin: 68.5,
          source: 'magglingen_lab_2026',
          freshness: FreshnessLevel.fresh,
        );

        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          diagnostics: [oldSkate, newSkate],
        );

        expect(state.diagnostics.hasCurrentSkatingDiagnostics, isTrue);
        expect(state.diagnostics.skating?.lt2Ltp2Watt, 240.0);
        expect(state.diagnostics.skating?.vo2maxMlPerKgMin, 68.5);
        expect(state.diagnostics.skating?.freshness, FreshnessLevel.fresh);
      },
    );

    test('5. 3 h Skating erhöht ski-specific exposure', () {
      final session3h = NormalizedSession(
        id: 'skate_3h',
        athleteId: athleteId,
        source: NormalizedSessionSource.garmin,
        sourceId: 's1',
        startedAtUtcUs: asOf
            .subtract(const Duration(days: 3))
            .microsecondsSinceEpoch,
        durationSeconds: 10800,
        movingTimeSeconds: 10800,
        modality: XcModality.skiSkating,
        technique: XcTechnique.skatingG3,
        isIndoor: false,
        title: '3h Skatingrunde Cungels',
        distanceMetres: 46000.0,
        elevationGainMetres: 650.0,
      );

      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        sessions: [session3h],
      );

      final exp = state.skiExposure.exposureOf(XcModality.skiSkating);
      expect(exp.durationSeconds7d, 10800);
      expect(exp.durationHours7d, 3.0);
      expect(exp.sessionCount7d, 1);
      expect(exp.distanceMetres7d, 46000.0);
      expect(state.skiExposure.onSnowDurationSeconds28d, 10800);
    });

    test(
      '6. 3 h Skating allein erzeugt keine Durability-Leistungsbehauptung',
      () {
        final session3h = NormalizedSession(
          id: 'skate_3h_pure',
          athleteId: athleteId,
          source: NormalizedSessionSource.garmin,
          sourceId: 's2',
          startedAtUtcUs: asOf
              .subtract(const Duration(days: 2))
              .microsecondsSinceEpoch,
          durationSeconds: 10800,
          movingTimeSeconds: 10800,
          modality: XcModality.skiSkating,
          isIndoor: false,
          title: 'Lange Runde ohne gemessene Entkopplung',
        );

        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          sessions: [session3h],
        );

        // Exposition ist dokumentiert:
        expect(state.durability.longSessionExposureHours28d, 3.0);
        expect(state.durability.longSessionCount28d, 1);
        // Aber KEINE gemessenen Beobachtungen!
        expect(state.durability.hasMeasuredObservations, isFalse);
        expect(state.durability.observations.isEmpty, isTrue);
      },
    );

    test('7. Valide DecouplingObservation erscheint im DurabilityState', () {
      const decouplingObs = DurabilityObservation(
        sessionId: 'skate_with_drift_calc',
        modality: XcModality.skiSkating,
        durationSeconds: 9000,
        type: DurabilityObservationType.hrExternalDecoupling,
        value: 4.8, // 4.8% Drift (aerob sehr stabil)
        unit: 'percent_drift',
        conditions: 'Flache Loipe, -3°C',
        confidence: 0.90,
        provenance: 'first_second_half_aerobic_decoupling',
      );

      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        explicitDurabilityObservations: [decouplingObs],
      );

      expect(state.durability.hasMeasuredObservations, isTrue);
      expect(state.durability.decouplingObservations.length, 1);
      expect(state.durability.decouplingObservations.first.value, 4.8);
      expect(state.durability.confidence, 0.90);
    });

    test('8. Ercolina Session aktualisiert DP Exposure', () {
      final ercolinaSess = NormalizedSession(
        id: 'ercolina_dp_sess',
        athleteId: athleteId,
        source: NormalizedSessionSource.ercolina,
        sourceId: 'erc_1',
        startedAtUtcUs: asOf
            .subtract(const Duration(days: 1))
            .microsecondsSinceEpoch,
        durationSeconds: 3600,
        movingTimeSeconds: 3600,
        modality: XcModality.ercolinaDoublePoling,
        isIndoor: true,
        title: 'Ercolina DP Training',
        externalMetrics: const SessionExternalMetrics(
          sessionAveragePowerWatt: 185.0,
          workPhaseAveragePowerWatt: 195.0,
          peakPowerWatt: 360.0,
          workJoule: 666000.0, // 666 kJ
          strokeCount: 1500,
        ),
        dataQuality: const SessionDataQuality(
          confidence: 1.0,
          calibrationConfidence: 0.92,
        ),
      );

      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        sessions: [ercolinaSess],
      );

      expect(state.doublePoling.recentSessionAveragePowerWatt, 185.0);
      expect(state.doublePoling.workPhaseAveragePowerWatt, 195.0);
      expect(state.doublePoling.totalWorkKiloJoule28d, 666.0);
      expect(state.doublePoling.hasValidCalibration, isTrue);
      expect(state.skiExposure.ercolinaDurationSeconds28d, 3600);
    });

    test(
      '9. Ercolina ohne valide Kalibrierung erzeugt keine hochsichere absolute DP-Leistungsfähigkeit',
      () {
        final uncalibratedSess = NormalizedSession(
          id: 'uncalibrated_ercolina',
          athleteId: athleteId,
          source: NormalizedSessionSource.ercolina,
          sourceId: 'erc_uncal',
          startedAtUtcUs: asOf
              .subtract(const Duration(days: 1))
              .microsecondsSinceEpoch,
          durationSeconds: 2400,
          movingTimeSeconds: 2400,
          modality: XcModality.ercolinaDoublePoling,
          isIndoor: true,
          title: 'Ercolina vor Bremsskalibrierung',
          externalMetrics: const SessionExternalMetrics(
            sessionAveragePowerWatt: 210.0,
          ),
          dataQuality: const SessionDataQuality(
            confidence: 0.70,
            calibrationConfidence: 0.40, // Schlechte Kalibrierung!
            warnings: ['Drop-Test Kalibrierung fehlt'],
          ),
        );

        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          sessions: [uncalibratedSess],
        );

        expect(state.doublePoling.hasValidCalibration, isFalse);
        expect(state.doublePoling.calibrationConfidence, 0.40);
        // Diagnostische Konfidenz MUSS niedrig sein:
        expect(state.doublePoling.diagnosticConfidence, lessThan(0.50));
      },
    );

    test(
      '10. Mehrere vergleichbare Ercolina Sessions erzeugen intraindividuellen Trend',
      () {
        final sess1 = NormalizedSession(
          id: 'erc_hit_1',
          athleteId: athleteId,
          source: NormalizedSessionSource.ercolina,
          sourceId: 'e1',
          startedAtUtcUs: asOf
              .subtract(const Duration(days: 14))
              .microsecondsSinceEpoch,
          durationSeconds: 2400,
          movingTimeSeconds: 2400,
          modality: XcModality.ercolinaDoublePoling,
          isIndoor: true,
          title: 'Ercolina Standard 40min',
          externalMetrics: const SessionExternalMetrics(
            sessionAveragePowerWatt: 190.0,
          ),
        );

        final sess2 = NormalizedSession(
          id: 'erc_hit_2',
          athleteId: athleteId,
          source: NormalizedSessionSource.ercolina,
          sourceId: 'e2',
          startedAtUtcUs: asOf
              .subtract(const Duration(days: 2))
              .microsecondsSinceEpoch,
          durationSeconds: 2400,
          movingTimeSeconds: 2400,
          modality: XcModality.ercolinaDoublePoling,
          isIndoor: true,
          title: 'Ercolina Standard 40min',
          externalMetrics: const SessionExternalMetrics(
            sessionAveragePowerWatt: 198.0,
          ),
        );

        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          sessions: [sess1, sess2],
        );

        final trends = state.performanceTrends.trendsFor(
          XcModality.ercolinaDoublePoling,
        );
        expect(trends.isNotEmpty, isTrue);
        final trend = trends.first;
        expect(trend.powerDeltaWatt, 8.0); // +8 Watt Steigerung
        expect(trend.evidenceSummary, contains('+8.0 W'));
      },
    );

    test('11. NordicSki unknown wird nicht als Skating Exposure gezählt', () {
      final sessUnknown = NormalizedSession(
        id: 'unknown_nordic',
        athleteId: athleteId,
        source: NormalizedSessionSource.garmin,
        sourceId: 'unk_1',
        startedAtUtcUs: asOf
            .subtract(const Duration(days: 4))
            .microsecondsSinceEpoch,
        durationSeconds: 5400,
        movingTimeSeconds: 5400,
        modality: XcModality.skiNordicUnknown,
        technique: XcTechnique.unknown,
        isIndoor: false,
        title: 'Langlauf Runde',
      );

      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        sessions: [sessUnknown],
      );

      // Skating-Exposition darf hier NICHT steigen!
      expect(
        state.skiExposure.exposureOf(XcModality.skiSkating).durationSeconds28d,
        0,
      );
      // Aber skiNordicUnknown wird sauber getrennt geführt:
      expect(
        state.skiExposure
            .exposureOf(XcModality.skiNordicUnknown)
            .durationSeconds28d,
        5400,
      );
      expect(state.skiExposure.onSnowDurationSeconds28d, 5400);
    });

    test('12. Missing subjective data bleibt unknown', () {
      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        subjectiveReadiness: const SubjectiveReadinessState(), // Leer
      );

      expect(state.subjectiveReadiness.hasData, isFalse);
      expect(state.subjectiveReadiness.perceivedRecovery, isNull);
      expect(state.subjectiveReadiness.muscleSoreness, isNull);
      expect(state.subjectiveReadiness.hasIllnessSymptoms, isFalse);
    });

    test('13. Unknown training day reduziert DataCoverage', () {
      // 28 Tage ohne Sessions und ohne bestätigte Ruhetage
      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        sessions: [],
        confirmedRestDays: {},
      );

      expect(state.dataCoverage.unknownDays28d, 28);
      expect(state.dataCoverage.overallCoverageRatio, lessThan(0.50));
      expect(
        state.dataCoverage.coverageAssessmentText,
        contains('Trainingshistorie unvollständig'),
      );
    });

    test('14. Confirmed rest day wird korrekt erkannt', () {
      final restDay = DateTime.utc(2026, 10, 2);
      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        confirmedRestDays: {restDay},
      );

      expect(state.dataCoverage.confirmedRestDays28d, 1);
    });

    test('15. Banister und sRPE Load History bleiben getrennt', () {
      final sess = NormalizedSession(
        id: 'load_sep_sess',
        athleteId: athleteId,
        source: NormalizedSessionSource.garmin,
        sourceId: 'ls_1',
        startedAtUtcUs: asOf
            .subtract(const Duration(days: 1))
            .microsecondsSinceEpoch,
        durationSeconds: 3600,
        movingTimeSeconds: 3600,
        modality: XcModality.skiSkating,
        isIndoor: false,
        title: 'Skating mit HF und sRPE',
        internalMetrics: const SessionInternalMetrics(
          averageHeartRateBpm: 150.0,
          rpe: 6.0,
        ),
      );

      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        sessions: [sess],
        physiology: const AthletePhysiologyState(
          maxHeartRateBpm: 190,
          restingHeartRateBpm: 50,
        ),
      );

      expect(state.trainingLoad.banisterTrimpSeries, isNotNull);
      expect(state.trainingLoad.srpeSeries, isNotNull);
      expect(state.trainingLoad.banisterTrimpSeries!.method, 'banister_trimp');
      expect(state.trainingLoad.srpeSeries!.method, 'srpe_load');
      expect(state.trainingLoad.banisterTrimpSeries!.unit, 'trimp_points');
      expect(state.trainingLoad.srpeSeries!.unit, 'srpe_points');
    });

    test('16. Planned VO2 stimulus != observed VO2 stimulus', () {
      final sess = NormalizedSession(
        id: 'sess_planned_vo2',
        athleteId: athleteId,
        source: NormalizedSessionSource.ercolina,
        sourceId: 'pv_1',
        startedAtUtcUs: asOf
            .subtract(const Duration(days: 2))
            .microsecondsSinceEpoch,
        durationSeconds: 2400,
        movingTimeSeconds: 2400,
        modality: XcModality.ercolinaDoublePoling,
        isIndoor: true,
        title: 'Ercolina Grundlageneinheit statt geplanter VO2',
        externalMetrics: const SessionExternalMetrics(
          sessionAveragePowerWatt: 140.0,
        ),
        internalMetrics: const SessionInternalMetrics(
          averageHeartRateBpm: 130.0,
        ),
      );

      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        sessions: [sess],
      );

      final vo2Entry = state.stimulusHistory.entryFor(StimulusType.vo2max);
      // Wenn der Reiz nicht nachgewiesen wurde, darf lastVerifiedAt nicht gesetzt sein
      expect(vo2Entry.lastVerifiedAt, isNull);
    });

    test('17. Alte Evidence verliert Freshness', () {
      final measuredAt = DateTime.utc(2024, 1, 1);
      final fresh = evaluateFreshness(measuredAt, asOf: asOf);

      // Über 2 Jahre alt = historical
      expect(fresh, FreshnessLevel.historical);

      final recent = DateTime.utc(2026, 9, 25);
      final freshRecent = evaluateFreshness(recent, asOf: asOf);
      expect(freshRecent, FreshnessLevel.fresh);
    });

    test(
      '18. Evidence bleibt zur Originalsession rückverfolgbar (traceEvidenceFor)',
      () {
        final diag = DiagnosticReference(
          modality: XcModality.skiSkating,
          date: DateTime.utc(2026, 9, 10),
          protocol: 'Laufband-Stufentest Magglingen',
          lt2Ltp2Watt: 245.0,
          source: 'lab_spiro',
          sourceId: 'lab_test_99',
          freshness: FreshnessLevel.fresh,
          confidence: 0.95,
        );

        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          diagnostics: [diag],
        );

        final trace = state.traceEvidenceFor('skating_lt2');
        expect(trace, contains('State: Skating LTP2 245.0'));
        expect(trace, contains('Laufband-Stufentest Magglingen'));
        expect(trace, contains('lab_spiro'));
        expect(trace, contains('lab_test_99'));
      },
    );

    test('19. Goal Context verändert keine historischen Messdaten', () {
      const goal = GoalContext(
        name: '50 km Skating Engadin',
        modality: XcModality.skiSkating,
        targetDistanceMetres: 50000.0,
        targetDurationSeconds: 8100, // 2h15
        priority: 'A',
      );

      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        goal: goal,
      );

      expect(state.goal?.name, '50 km Skating Engadin');
      expect(state.goal?.targetSpeedKmh, closeTo(22.22, 0.05));
      // Keine erfundenen Schwellenwerte aus dem Ziel!
      expect(state.diagnostics.skating, isNull);
      expect(state.threshold.observedThresholdPowerWatt, isNull);
    });

    test(
      '20. AthleteState kann vollständig mit vielen UNKNOWN-Werten existieren',
      () {
        final emptyState = builder.buildState(
          athleteId: 'blank_athlete',
          asOf: asOf,
        );

        // State wirft keine Exceptions und deklariert Lücken transparent
        expect(emptyState.diagnostics.references.isEmpty, isTrue);
        expect(emptyState.doublePoling.recentSessionAveragePowerWatt, isNull);
        expect(emptyState.durability.hasMeasuredObservations, isFalse);
        expect(emptyState.subjectiveReadiness.hasData, isFalse);

        final factSheet = emptyState.toFactSheetText();
        expect(factSheet, contains('Skating LT2 / LTP2: UNKNOWN'));
        expect(factSheet, contains('Ercolina DP Schwellendiagnostik: UNKNOWN'));
        expect(factSheet, contains('Subjektive Rückmeldungen: UNKNOWN'));
        expect(
          factSheet,
          contains(
            'Gemessene aerobe Entkopplung / Durability-Evidenz: KEINE VORHANDEN',
          ),
        );
      },
    );
  });
}
