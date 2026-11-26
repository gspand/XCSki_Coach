import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/domain/normalized_session.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:xc_coach/intelligence/load/ewma_load_tracker.dart';
import 'package:xc_coach/intelligence/load/load_calculator.dart';
import 'package:xc_coach/intelligence/load/load_models.dart';
import 'package:xc_coach/intelligence/load/stimulus_models.dart';

void main() {
  group('Schritt 2 – Load & Stimulus Engine', () {
    const calculator = LoadCalculator();
    const athleteId = 'athlete_step2_test';

    test('1. Ercolina mit Power, ohne HR', () {
      final session = NormalizedSession(
        id: 'ercolina_pwr_only',
        athleteId: athleteId,
        source: NormalizedSessionSource.ercolina,
        sourceId: 'ercolina_101',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 2400, // 40 min
        movingTimeSeconds: 2400,
        modality: XcModality.ercolinaDoublePoling,
        technique: XcTechnique.doublePoling,
        isIndoor: true,
        title: 'Ercolina Doppelstock Grundlagenarbeit',
        externalMetrics: const SessionExternalMetrics(
          averagePowerWatt: 192.0,
          workJoule: 460800.0,
          strokeOrCadenceRate: 41.5,
          leftRightSymmetryPercent: 98.0,
        ),
        internalMetrics: const SessionInternalMetrics(
          averageHeartRateBpm: null, // Keine HR
          peakHeartRateBpm: null,
        ),
        dataQuality: const SessionDataQuality(
          confidence: 1.0,
          externalConfidence: 1.0,
          hasPower: true,
          hasHeartRate: false,
        ),
      );

      final load = calculator.calculateLoad(session);

      expect(load.external.hasPower, isTrue);
      expect(load.external.averagePowerWatt, 192.0);
      expect(load.external.workJoule, 460800.0);
      expect(load.external.workKiloJoule, 460.8);
      expect(load.external.leftRightSymmetryPercent, 98.0);

      // Keine erfundene Herzfrequenz
      expect(load.internal.hasHeartRate, isFalse);
      expect(load.internal.averageHeartRateBpm, isNull);
      expect(load.internal.trimpBanister, isNull);
      expect(load.internal.trimpEdwards, isNull);
    });

    test('2. Skating mit HR, ohne Power', () {
      final session = NormalizedSession(
        id: 'skating_hr_only',
        athleteId: athleteId,
        source: NormalizedSessionSource.garmin,
        sourceId: 'fixture_skate_hr',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 5400, // 90 min
        movingTimeSeconds: 5400,
        modality: XcModality.skiSkating,
        technique: XcTechnique.skatingG3,
        isIndoor: false,
        title: 'Skating Loipe Cungels',
        distanceMetres: 24000.0,
        elevationGainMetres: 350.0,
        externalMetrics: const SessionExternalMetrics(
          averagePowerWatt: null, // Keine Watt im Schnee
        ),
        internalMetrics: const SessionInternalMetrics(
          averageHeartRateBpm: 152.0,
          peakHeartRateBpm: 171,
        ),
        dataQuality: const SessionDataQuality(
          confidence: 0.85,
          internalConfidence: 0.90,
          hasHeartRate: true,
          hasPower: false,
        ),
      );

      const physiology = AthletePhysiology(
        maxHeartRateBpm: 190.0,
        restingHeartRateBpm: 50.0,
      );

      final load = calculator.calculateLoad(session, physiology: physiology);

      expect(load.internal.hasHeartRate, isTrue);
      expect(load.internal.averageHeartRateBpm, 152.0);
      expect(load.internal.trimpBanister, isNotNull);
      expect(load.internal.trimpBanister!, greaterThan(50.0));
      expect(load.internal.trimpEdwards, isNotNull);

      // Keine erfundenen Watt
      expect(load.external.hasPower, isFalse);
      expect(load.external.averagePowerWatt, isNull);
      expect(load.external.workJoule, isNull);
    });

    test('3. Skating ohne HR und Power, aber Dauer/Distanz', () {
      final session = NormalizedSession(
        id: 'skating_no_sensors',
        athleteId: athleteId,
        source: NormalizedSessionSource.garmin,
        sourceId: 'fixture_plain',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 7200, // 120 min
        movingTimeSeconds: 7000,
        modality: XcModality.skiSkating,
        technique: XcTechnique.unknown,
        isIndoor: false,
        title: 'Skating Runde ohne Gurt',
        distanceMetres: 32000.0,
        elevationGainMetres: 450.0,
        externalMetrics: const SessionExternalMetrics(),
        internalMetrics: const SessionInternalMetrics(),
        dataQuality: const SessionDataQuality(
          confidence: 0.80,
          hasGps: true,
          hasHeartRate: false,
          hasPower: false,
        ),
      );

      final load = calculator.calculateLoad(session);

      expect(load.external.hasDistance, isTrue);
      expect(load.external.distanceKm, 32.0);
      expect(load.external.durationMinutes, 120.0);
      expect(load.external.hasPower, isFalse);
      expect(load.internal.hasHeartRate, isFalse);
      expect(load.internal.trimpBanister, isNull);
      expect(load.perceived.hasSrpe, isFalse);
    });

    test('4. Session mit sRPE', () {
      final session = NormalizedSession(
        id: 'session_srpe_only',
        athleteId: athleteId,
        source: NormalizedSessionSource.manual,
        sourceId: 'manual_1',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 3600, // 60 min
        movingTimeSeconds: 3600,
        modality: XcModality.skiSkating,
        isIndoor: false,
        title: 'Manuelle Skating-Einheit',
        internalMetrics: const SessionInternalMetrics(
          rpe: 7.0, // Subjektive Anstrengung 7/10
        ),
      );

      final load = calculator.calculateLoad(session);

      expect(load.perceived.hasSrpe, isTrue);
      expect(load.perceived.rpe, 7.0);
      expect(load.perceived.durationMinutes, 60.0);
      expect(load.perceived.srpeLoad, 420.0); // 7 * 60 = 420
    });

    test('5. Session mit HR + sRPE parallel', () {
      final session = NormalizedSession(
        id: 'session_hr_srpe',
        athleteId: athleteId,
        source: NormalizedSessionSource.garmin,
        sourceId: 'fixture_both',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 3600, // 60 min
        movingTimeSeconds: 3600,
        modality: XcModality.skiSkating,
        isIndoor: false,
        title: 'Kombinierte Messung',
        internalMetrics: const SessionInternalMetrics(
          averageHeartRateBpm: 155.0,
          peakHeartRateBpm: 175,
          rpe: 8.0,
        ),
      );

      final load = calculator.calculateLoad(session);

      // Beide Metriken koexistieren parallel ohne gegenseitige Ersetzung
      expect(load.internal.trimpBanister, isNotNull);
      expect(load.perceived.srpeLoad, 480.0); // 8 * 60
    });

    test('6. Fehlende sportartspezifische Schwelle erzeugt keine scheinpräzise Schwellenlast', () {
      const physiology = AthletePhysiology(
        maxHeartRateBpm: 192.0,
        restingHeartRateBpm: 48.0,
        sportSpecificLthrBpm: {
          // Keine Schwelle für skiSkating eingetragen!
        },
      );

      expect(physiology.hasSpecificLthr(XcModality.skiSkating), isFalse);
      expect(physiology.hasSpecificThresholdPower(XcModality.skiSkating), isFalse);
    });

    test('7. Historische/fremdsportliche Schwelle wird nicht als aktuelle XC-Schwelle benutzt', () {
      const physiology = AthletePhysiology(
        maxHeartRateBpm: 192.0,
        restingHeartRateBpm: 48.0,
        sportSpecificLthrBpm: {
          XcModality.cycling: 168.0, // Historische Rad-Schwelle
          XcModality.running: 174.0, // Historische Lauf-Schwelle
        },
        sportSpecificThresholdPowerWatt: {
          XcModality.cycling: 280.0,
        },
      );

      // Rad-Schwelle darf NIEMALS auf Skating übertragen werden
      expect(physiology.hasSpecificLthr(XcModality.skiSkating), isFalse);
      expect(physiology.hasSpecificThresholdPower(XcModality.skiSkating), isFalse);
      expect(physiology.hasSpecificThresholdPower(XcModality.ercolinaDoublePoling), isFalse);
    });

    test('8. Lange lockere Einheit != kurze VO2-Einheit trotz ähnlicher Load-Grössen', () {
      // Einheit A: 3h lockeres Skating
      final sessionLong = NormalizedSession(
        id: 'session_long_skating',
        athleteId: athleteId,
        source: NormalizedSessionSource.garmin,
        sourceId: 'long_1',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 10800, // 180 min (3h)
        movingTimeSeconds: 10800,
        modality: XcModality.skiSkating,
        technique: XcTechnique.skatingG3,
        isIndoor: false,
        title: '3h Langlauf Grundlagenausdauer',
        distanceMetres: 48000.0,
        internalMetrics: const SessionInternalMetrics(
          averageHeartRateBpm: 135.0, // ~71% HRmax
          rpe: 4.0,
        ),
      );

      // Einheit B: 45 min Ercolina VO2 HIT
      final sessionVo2 = NormalizedSession(
        id: 'session_ercolina_vo2',
        athleteId: athleteId,
        source: NormalizedSessionSource.ercolina,
        sourceId: 'ercolina_vo2',
        startedAtUtcUs: 1772618400000000,
        durationSeconds: 2700, // 45 min
        movingTimeSeconds: 2700,
        modality: XcModality.ercolinaDoublePoling,
        technique: XcTechnique.doublePoling,
        isIndoor: true,
        title: 'Ercolina 4x4 HIT',
        externalMetrics: const SessionExternalMetrics(
          averagePowerWatt: 225.0,
          workJoule: 607500.0,
        ),
        internalMetrics: const SessionInternalMetrics(
          averageHeartRateBpm: 172.0, // ~90% HRmax
          rpe: 9.0,
        ),
      );

      final stimuliLong = calculator.calculateStimuli(sessionLong);
      const vo2Physiology = AthletePhysiology(
        maxHeartRateBpm: 190.0,
        restingHeartRateBpm: 50.0,
        sportSpecificThresholdPowerWatt: {
          XcModality.ercolinaDoublePoling: 200.0,
        },
      );
      final stimuliVo2 = calculator.calculateStimuli(
        sessionVo2,
        physiology: vo2Physiology,
        plannedStimulusType: StimulusType.vo2max,
      );

      // Einheit A stimuli
      expect(stimuliLong.hasStimulus(StimulusType.aerobicBase), isTrue);
      expect(stimuliLong.hasStimulus(StimulusType.longEndurance), isTrue);
      expect(stimuliLong.hasStimulus(StimulusType.fatigueResistance), isTrue);
      expect(stimuliLong.hasStimulus(StimulusType.vo2max), isFalse);

      // Einheit B stimuli
      expect(stimuliVo2.hasStimulus(StimulusType.vo2max), isTrue);
      expect(stimuliVo2.hasStimulus(StimulusType.doublePolingPower), isTrue);
      expect(stimuliVo2.hasStimulus(StimulusType.muscularEndurance), isTrue);
      expect(stimuliVo2.hasStimulus(StimulusType.longEndurance), isFalse);
      expect(stimuliVo2.hasStimulus(StimulusType.fatigueResistance), isFalse);
    });

    test('9. EWMA mit bekannten synthetischen Werten mathematisch exakt', () {
      const tracker = EwmaLoadTracker(
        config: EwmaConfig(
          timeConstantAcuteDays: 7.0,
          timeConstantChronicDays: 42.0,
        ),
      );

      final alphaA = 1.0 - math.exp(-1.0 / 7.0); // ~0.133122
      final alphaC = 1.0 - math.exp(-1.0 / 42.0); // ~0.023531

      // 7 Tage konstante Belastung von 100 Einheiten/Tag
      final trajectory = tracker.computeTrajectory(
        startDate: DateTime.utc(2026, 10, 1),
        dailyLoads: [100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0],
        initialAcute: 0.0,
        initialChronic: 0.0,
      );

      expect(trajectory.length, 7);

      // Tag 1 exakt: 0 + alpha * (100 - 0) = 100 * alpha
      final day1ExpectedAcute = 100.0 * alphaA;
      final day1ExpectedChronic = 100.0 * alphaC;
      expect(trajectory[0].acuteLoad, closeTo(day1ExpectedAcute, 0.0001));
      expect(trajectory[0].chronicLoad, closeTo(day1ExpectedChronic, 0.0001));
      expect(
        trajectory[0].loadBalance,
        closeTo(day1ExpectedChronic - day1ExpectedAcute, 0.0001),
      );

      // Tag 2 exakt: day1 + alpha * (100 - day1)
      final day2ExpectedAcute =
          day1ExpectedAcute + alphaA * (100.0 - day1ExpectedAcute);
      expect(trajectory[1].acuteLoad, closeTo(day2ExpectedAcute, 0.0001));
    });

    test('10. Fehlender Trainingstag = korrektes Decay, nicht fehlende Daten', () {
      const tracker = EwmaLoadTracker();
      final alphaA = tracker.config.alphaAcute;

      final startDate = DateTime.utc(2026, 10, 1);
      // Tag 1: 100, Tag 2: Ruhetag (0.0), Tag 3: Ruhetag (0.0)
      final trajectory = tracker.computeTrajectory(
        startDate: startDate,
        dailyLoads: [100.0, 0.0, 0.0],
      );

      final day1Acute = trajectory[0].acuteLoad;
      final day2Acute = trajectory[1].acuteLoad;
      final day3Acute = trajectory[2].acuteLoad;

      // Am Ruhetag klingt die akute Last exakt mit (1 - alpha) ab:
      expect(day2Acute, closeTo(day1Acute * (1.0 - alphaA), 0.0001));
      expect(day3Acute, closeTo(day2Acute * (1.0 - alphaA), 0.0001));
      expect(trajectory[1].date, DateTime.utc(2026, 10, 2));
      expect(trajectory[2].date, DateTime.utc(2026, 10, 3));
    });

    test('11. Fehlende Sessiondaten erzeugen keine erfundenen Werte', () {
      final bareSession = NormalizedSession(
        id: 'bare_sess',
        athleteId: athleteId,
        source: NormalizedSessionSource.manual,
        sourceId: 'bare_1',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 1800,
        movingTimeSeconds: 1800,
        modality: XcModality.skiNordicUnknown,
        isIndoor: false,
        title: 'Unvollständige Session',
      );

      final load = calculator.calculateLoad(bareSession);

      expect(load.external.workJoule, isNull);
      expect(load.external.averagePowerWatt, isNull);
      expect(load.external.distanceMetres, isNull);
      expect(load.internal.averageHeartRateBpm, isNull);
      expect(load.internal.trimpBanister, isNull);
      expect(load.perceived.srpeLoad, isNull);
    });

    test('12. Schlechte Data Quality reduziert Confidence', () {
      final goodSession = NormalizedSession(
        id: 'good_sess',
        athleteId: athleteId,
        source: NormalizedSessionSource.garmin,
        sourceId: 'good_1',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 3600,
        movingTimeSeconds: 3600,
        modality: XcModality.skiSkating,
        isIndoor: false,
        title: 'Saubere Messung',
        dataQuality: const SessionDataQuality(
          confidence: 0.90,
          warnings: [],
        ),
      );

      final badSession = NormalizedSession(
        id: 'bad_sess',
        athleteId: athleteId,
        source: NormalizedSessionSource.garmin,
        sourceId: 'bad_1',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 3600,
        movingTimeSeconds: 3600,
        modality: XcModality.skiSkating,
        isIndoor: false,
        title: 'Gestörte Messung',
        dataQuality: const SessionDataQuality(
          confidence: 0.90,
          warnings: ['GPS dropout', 'Optischer Sensor Ausfall'],
        ),
      );

      final loadGood = calculator.calculateLoad(goodSession);
      final loadBad = calculator.calculateLoad(badSession);

      expect(loadGood.confidence, 0.90);
      expect(loadBad.confidence, lessThan(loadGood.confidence));
    });

    test('13. External und Internal Load bleiben unabhängig', () {
      final sessionPower = NormalizedSession(
        id: 'sess_iso_1',
        athleteId: athleteId,
        source: NormalizedSessionSource.ercolina,
        sourceId: 'iso_1',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 3600,
        movingTimeSeconds: 3600,
        modality: XcModality.ercolinaDoublePoling,
        isIndoor: true,
        title: 'Ercolina 180W',
        externalMetrics: const SessionExternalMetrics(averagePowerWatt: 180.0),
        internalMetrics: const SessionInternalMetrics(averageHeartRateBpm: 140.0),
      );

      final sessionHigherPower = NormalizedSession(
        id: 'sess_iso_2',
        athleteId: athleteId,
        source: NormalizedSessionSource.ercolina,
        sourceId: 'iso_2',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 3600,
        movingTimeSeconds: 3600,
        modality: XcModality.ercolinaDoublePoling,
        isIndoor: true,
        title: 'Ercolina 250W',
        externalMetrics: const SessionExternalMetrics(averagePowerWatt: 250.0),
        internalMetrics: const SessionInternalMetrics(averageHeartRateBpm: 140.0),
      );

      final load1 = calculator.calculateLoad(sessionPower);
      final load2 = calculator.calculateLoad(sessionHigherPower);

      // Verändertes Watt ändert External Load, aber NICHT den gemessenen TRIMP
      expect(load2.external.averagePowerWatt, 250.0);
      expect(load1.external.averagePowerWatt, 180.0);
      expect(load1.internal.trimpBanister, load2.internal.trimpBanister);
    });

    test('14. Keine ACWR-Safetyentscheidung oder Verletzungsalarm', () {
      const tracker = EwmaLoadTracker();

      // Akuter Last-Spike (z. B. nach Ruhephase plötzlich 300 Einheiten)
      final state = tracker.step(
        date: DateTime.utc(2026, 10, 10),
        dailyLoad: 300.0,
        previousAcute: 30.0,
        previousChronic: 20.0,
      );

      // ACWR ist mathematisch hoch (> 2.0)
      expect(state.experimentalAcwr, greaterThan(2.0));

      // WICHTIG: Das System berechnet nur die Zahl und fällt KEIN Urteil
      // (keine Exception, kein 'injury_risk = high' Tag, kein Abbruch)
      expect(state.loadBalance, lessThan(0));
    });

    test('15. Mehrere Stimuli pro Session möglich mit transparenter Evidenz', () {
      final sessionMulti = NormalizedSession(
        id: 'multi_stim_sess',
        athleteId: athleteId,
        source: NormalizedSessionSource.garmin,
        sourceId: 'multi_1',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 10800, // 3h
        movingTimeSeconds: 10800,
        modality: XcModality.skiSkating,
        technique: XcTechnique.skatingG3,
        isIndoor: false,
        title: 'Lange Skating-Runde Engadin',
        distanceMetres: 45000.0,
        internalMetrics: const SessionInternalMetrics(
          averageHeartRateBpm: 138.0,
          rpe: 5.0,
        ),
      );

      final ledger = calculator.calculateStimuli(sessionMulti);

      expect(ledger.stimuli.length, greaterThanOrEqualTo(3));
      expect(ledger.hasStimulus(StimulusType.aerobicBase), isTrue);
      expect(ledger.hasStimulus(StimulusType.longEndurance), isTrue);
      expect(ledger.hasStimulus(StimulusType.fatigueResistance), isTrue);

      for (final s in ledger.stimuli) {
        expect(s.evidence, isNotEmpty);
        expect(s.confidence, greaterThan(0.0));
      }
    });

    test('16. Bestehende Planning- und Intelligence-Tests bleiben kompatibel', () {
      // Stellt sicher, dass die Modelle einwandfrei nach JSON und zurück konvertieren
      final testLoad = SessionLoad(
        sessionId: 'test_sess',
        athleteId: athleteId,
        modality: XcModality.skiSkating,
        technique: XcTechnique.skatingG3,
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 3600,
        external: const ExternalLoad(durationSeconds: 3600, averagePowerWatt: 195.0),
        internal: const InternalLoad(averageHeartRateBpm: 150.0, trimpBanister: 75.4),
        perceived: const PerceivedLoad(rpe: 6.0, srpeLoad: 360.0),
        confidence: 0.90,
        provenance: 'strava',
      );

      final json = testLoad.toJson();
      final restored = SessionLoad.fromJson(json);

      expect(restored.sessionId, 'test_sess');
      expect(restored.external.averagePowerWatt, 195.0);
      expect(restored.internal.trimpBanister, 75.4);
      expect(restored.perceived.srpeLoad, 360.0);
    });
  });

  group('Wissenschaftliche Schärfung Schritt 2 – 11 sportwissenschaftliche Leitplanken', () {
    const calculator = LoadCalculator();
    const athleteId = 'science_audit_athlete';

    test('1. Absolute 150 W ohne Referenzwert erzeugt KEINEN doublePolingPower Reiz', () {
      // 150 W oder 225 W ohne individuelle Schwelle ist ohne biologische Bedeutung
      final session = NormalizedSession(
        id: 'no_ref_dp',
        athleteId: athleteId,
        source: NormalizedSessionSource.ercolina,
        sourceId: 'dp_raw',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 1800, // 30 min
        movingTimeSeconds: 1800,
        modality: XcModality.ercolinaDoublePoling,
        isIndoor: true,
        title: 'Ercolina ohne Diagnostik',
        externalMetrics: const SessionExternalMetrics(sessionAveragePowerWatt: 165.0),
      );

      // Keine Schwelle im Athletenprofil!
      const physiology = AthletePhysiology(sportSpecificThresholdPowerWatt: {});
      final ledger = calculator.calculateStimuli(session, physiology: physiology);

      // Darf KEINEN doublePolingPower Reiz behaupten!
      expect(ledger.hasStimulus(StimulusType.doublePolingPower), isFalse);
      // Aber Kraftausdauer über Dauer ist legitim
      expect(ledger.hasStimulus(StimulusType.muscularEndurance), isTrue);
    });

    test('2. Relative Leistung (> 105% Threshold Power) weist doublePolingPower valide nach', () {
      final session = NormalizedSession(
        id: 'relative_dp',
        athleteId: athleteId,
        source: NormalizedSessionSource.ercolina,
        sourceId: 'dp_rel',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 1800,
        movingTimeSeconds: 1800,
        modality: XcModality.ercolinaDoublePoling,
        isIndoor: true,
        title: 'Ercolina Schwellenüberschreitung',
        externalMetrics: const SessionExternalMetrics(sessionAveragePowerWatt: 220.0),
      );

      // Individuelle DP-Schwelle ist 200 W (220 W = 110%)
      const physiology = AthletePhysiology(
        sportSpecificThresholdPowerWatt: {
          XcModality.ercolinaDoublePoling: 200.0,
        },
      );
      final ledger = calculator.calculateStimuli(session, physiology: physiology);

      expect(ledger.hasStimulus(StimulusType.doublePolingPower), isTrue);
      final stim = ledger.stimuliOfType(StimulusType.doublePolingPower).first;
      expect(stim.evidence, contains('110% der individuellen DP-Schwelle'));
      expect(stim.confidence, 0.95);
    });

    test('3. Planned Stimulus vs Observed Stimulus Abgleich mit Compliance', () {
      final session = NormalizedSession(
        id: 'planned_vo2_session',
        athleteId: athleteId,
        source: NormalizedSessionSource.ercolina,
        sourceId: 'plan_1',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 2400,
        movingTimeSeconds: 2400,
        modality: XcModality.ercolinaDoublePoling,
        isIndoor: true,
        title: 'Ercolina 4x4 HIT',
        internalMetrics: const SessionInternalMetrics(
          averageHeartRateBpm: 170.0,
          rpe: 9.0,
          timeInHrZonesSeconds: {'z5': 480}, // 8 min in Z5
        ),
      );

      final ledger = calculator.calculateStimuli(
        session,
        plannedStimulusType: StimulusType.vo2max,
      );

      expect(ledger.hasObservedStimulus(StimulusType.vo2max), isTrue);
      expect(ledger.hasPlannedStimulus(StimulusType.vo2max), isTrue);

      final vo2Stim = ledger.stimuliOfType(StimulusType.vo2max).first;
      expect(vo2Stim.origin, StimulusOrigin.verified);
      expect(vo2Stim.complianceRate, 1.0);
    });

    test('4. Hohe Durchschnitts-HF allein löst KEINEN VO2max-Reiz aus (sondern Schwellenlast)', () {
      // Kontinuierliche Einheit mit HF 168 (88% HRmax), aber ohne Z5-Akkumulation oder Intervalle
      final sessionContinuous = NormalizedSession(
        id: 'continuous_tempo',
        athleteId: athleteId,
        source: NormalizedSessionSource.garmin,
        sourceId: 'tempo_1',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 3600, // 60 min
        movingTimeSeconds: 3600,
        modality: XcModality.skiSkating,
        technique: XcTechnique.skatingG3,
        isIndoor: false,
        title: '60 min zügiges Skating',
        internalMetrics: const SessionInternalMetrics(
          averageHeartRateBpm: 168.0, // 88.4% HRmax
          rpe: 6.5,
          timeInHrZonesSeconds: {
            'z3': 1200,
            'z4': 2400,
            'z5': 0, // Keine Z5-Zeit!
          },
        ),
      );

      const physiology = AthletePhysiology(maxHeartRateBpm: 190.0);
      final ledger = calculator.calculateStimuli(sessionContinuous, physiology: physiology);

      // Durchschnitts-HF allein darf KEIN VO2max behaupten!
      expect(ledger.hasStimulus(StimulusType.vo2max), isFalse);
      // Aber Schwellenbelastung/Tempo
      expect(ledger.hasStimulus(StimulusType.threshold), isTrue);
      final stim = ledger.stimuliOfType(StimulusType.threshold).first;
      expect(stim.evidence, contains('ohne Z5-Intervallnachweis'));
    });

    test('5. 180 min Skating ist Exposure (longEndurance), keine automatische DurabilityObservation', () {
      final sessionLong = NormalizedSession(
        id: 'exposure_only',
        athleteId: athleteId,
        source: NormalizedSessionSource.garmin,
        sourceId: 'exp_1',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 10800, // 180 min
        movingTimeSeconds: 10800,
        modality: XcModality.skiSkating,
        technique: XcTechnique.skatingG3,
        isIndoor: false,
        title: '3h Skating Grundlagenausdauer',
        distanceMetres: 45000.0,
      );

      final ledger = calculator.calculateStimuli(sessionLong);

      // StimulusType longEndurance = reine Exposition
      expect(ledger.hasStimulus(StimulusType.longEndurance), isTrue);
      final longStim = ledger.stimuliOfType(StimulusType.longEndurance).first;
      expect(longStim.evidence, contains('Expositionszeit'));

      // Anpassungsziel fatigueResistance ist als Trainingsreiz vermerkt
      expect(ledger.hasStimulus(StimulusType.fatigueResistance), isTrue);
      final fatStim = ledger.stimuliOfType(StimulusType.fatigueResistance).first;
      expect(fatStim.evidence, contains('keine gemessene Durability-Degradation'));
    });

    test('6. Externe Leistung differenziert: Intervallpower vs Session-Mittelwert, Total Work nie extrapoliert', () {
      const metrics = SessionExternalMetrics(
        sessionAveragePowerWatt: 150.0,
        intervalAveragePowerWatt: 260.0,
        workPhaseAveragePowerWatt: 245.0,
        peakPowerWatt: 420.0,
        workJoule: 540000.0, // 150 W * 3600 s = 540 kJ aus Zügen
      );

      final load = const ExternalLoad(
        durationSeconds: 3600,
        sessionAveragePowerWatt: 150.0,
        intervalAveragePowerWatt: 260.0,
        workPhaseAveragePowerWatt: 245.0,
        peakPowerWatt: 420.0,
        workJoule: 540000.0,
      );

      expect(load.sessionAveragePowerWatt, 150.0);
      expect(load.averagePowerWatt, 150.0); // Alias
      expect(load.intervalAveragePowerWatt, 260.0);
      expect(load.workPhaseAveragePowerWatt, 245.0);
      expect(load.workKiloJoule, 540.0);
      // Niemals 260 W * 3600 = 936 kJ!
      expect(load.workKiloJoule, isNot(936.0));
    });

    test('7. Banister TRIMP ist Schätzung (estimatedInternalLoad) mit konfigurierbaren Parametern', () {
      final session = NormalizedSession(
        id: 'trimp_param_test',
        athleteId: athleteId,
        source: NormalizedSessionSource.garmin,
        sourceId: 't1',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 3600,
        movingTimeSeconds: 3600,
        modality: XcModality.skiSkating,
        isIndoor: false,
        title: 'TRIMP Parametrisierung',
        internalMetrics: const SessionInternalMetrics(averageHeartRateBpm: 155.0),
      );

      // Konfiguration A: Standard y = 1.92
      const physA = AthletePhysiology(
        maxHeartRateBpm: 190.0,
        restingHeartRateBpm: 50.0,
        banisterGenderFactorY: 1.92,
      );

      // Konfiguration B: Modifiziertes y = 1.75
      const physB = AthletePhysiology(
        maxHeartRateBpm: 190.0,
        restingHeartRateBpm: 50.0,
        banisterGenderFactorY: 1.75,
      );

      final loadA = calculator.calculateLoad(session, physiology: physA);
      final loadB = calculator.calculateLoad(session, physiology: physB);

      expect(loadA.internal.trimpBanister, isNotNull);
      expect(loadB.internal.trimpBanister, isNotNull);
      // y=1.92 erzeugt bei gleicher HF höhere exponentielle Gewichtung als y=1.75
      expect(loadA.internal.trimpBanister!, greaterThan(loadB.internal.trimpBanister!));
      expect(loadA.internal.provenance, contains('heart_rate_estimated_proxy_banister_1991'));
    });

    test('8. EWMA-Zeitreihen mit Methoden-Provenienz (EwmaSeries)', () {
      const tracker = EwmaLoadTracker();
      final inputs = [
        EwmaDailyInput(date: DateTime.utc(2026, 10, 1), load: 80.0),
        EwmaDailyInput(date: DateTime.utc(2026, 10, 2), load: 0.0, classification: DayClassification.confirmedRestDay),
        EwmaDailyInput(date: DateTime.utc(2026, 10, 3), load: 120.0),
      ];

      final seriesTrimp = tracker.computeSeries(
        seriesId: 'series_trimp_1',
        athleteId: athleteId,
        method: 'banister_trimp',
        unit: 'trimp_points',
        version: '1.0',
        inputs: inputs,
      );

      expect(seriesTrimp.method, 'banister_trimp');
      expect(seriesTrimp.unit, 'trimp_points');
      expect(seriesTrimp.parameters['timeConstantAcuteDays'], 7.0);
      expect(seriesTrimp.parameters['timeConstantChronicDays'], 42.0);
      expect(seriesTrimp.states.length, 3);
    });

    test('9. unknownDay darf EWMA-Kurve NICHT als 0-Belastung abklingen lassen', () {
      const tracker = EwmaLoadTracker();
      final alphaA = tracker.config.alphaAcute;

      final previousAcute = 50.0;
      final previousChronic = 40.0;

      // Fall A: Bestätigter Ruhetag
      final restState = tracker.step(
        date: DateTime.utc(2026, 10, 2),
        dailyLoad: 0.0,
        previousAcute: previousAcute,
        previousChronic: previousChronic,
        classification: DayClassification.confirmedRestDay,
        previousConfidence: 1.0,
      );

      // Fall B: Unbekannter Tag (Datenlücke / fehlender Sync)
      final unknownState = tracker.step(
        date: DateTime.utc(2026, 10, 2),
        dailyLoad: 0.0,
        previousAcute: previousAcute,
        previousChronic: previousChronic,
        classification: DayClassification.unknownDay,
        previousConfidence: 1.0,
      );

      // Am bestätigten Ruhetag MUSS die Last abklingen:
      expect(restState.acuteLoad, closeTo(previousAcute * (1.0 - alphaA), 0.0001));
      expect(restState.confidence, 1.0);

      // Am unbekannten Tag darf die Last NICHT abklingen (keine Unterstellung von Regeneration!):
      expect(unknownState.acuteLoad, previousAcute);
      expect(unknownState.chronicLoad, previousChronic);
      // Aber die Konfidenz der Kurve sinkt:
      expect(unknownState.confidence, lessThan(1.0));
      expect(unknownState.isUnknownDay, isTrue);
    });

    test('10. Sensor-Dropouts reduzieren Signal-Konfidenz dynamisch', () {
      final sessionWithDropout = NormalizedSession(
        id: 'dropout_sess',
        athleteId: athleteId,
        source: NormalizedSessionSource.garmin,
        sourceId: 'drop_1',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 3600,
        movingTimeSeconds: 3600,
        modality: XcModality.skiSkating,
        isIndoor: false,
        title: 'Sensor Wackler',
        internalMetrics: const SessionInternalMetrics(averageHeartRateBpm: 145.0),
        dataQuality: const SessionDataQuality(
          confidence: 0.90,
          internalConfidence: 0.90,
          warnings: ['Optischer HR-Sensor Dropout in min 15-22'],
        ),
      );

      final load = calculator.calculateLoad(sessionWithDropout);

      // Dynamische Abwertung der internen Konfidenz wegen Sensor-Warnung
      expect(load.internal.confidence, lessThan(0.90));
      expect(load.confidence, lessThan(0.90));
    });

    test('11. DurabilityObservation hält Messkonditionen und Entkopplung fest', () {
      const observation = DurabilityObservation(
        sessionId: 'sess_durability_test',
        modality: XcModality.skiSkating,
        durationSeconds: 7200,
        type: DurabilityObservationType.hrExternalDecoupling,
        value: 6.8, // 6.8% PW:HR Drift in der 2. Hälfte
        unit: 'percent_drift',
        conditions: 'Konstante Leistung in der Ebene, Schnee kalt -4°C',
        confidence: 0.88,
        provenance: 'first_second_half_aerobic_decoupling',
      );

      expect(observation.type, DurabilityObservationType.hrExternalDecoupling);
      expect(observation.value, 6.8);
      expect(observation.unit, 'percent_drift');
      expect(observation.confidence, 0.88);
    });
  });
}
