import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/app/session_recap.dart';
import 'package:xc_coach/domain/normalized_session.dart';
import 'package:xc_coach/domain/normalized_session_adapters.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:xc_coach/external_data/activity_import.dart';
import 'package:xc_coach/external_data/normalization/external_data.dart';
import 'package:xc_coach/external_data/source_authority.dart';
import 'package:xc_coach/external_data/strava/strava_activity.dart';

void main() {
  group('NormalizedSession & XC Modality Taxonomy (Schritt 1)', () {
    const athleteId = 'athlete_123';

    test('1. Ercolina-Einheit erzeugt ercolinaDoublePoling mit korrekter Provenance', () {
      const recap = SessionRecap(
        sessionId: 'ercolina_rec_42',
        startedAtUtcUs: 1772528400000000,
        duration: Duration(minutes: 45),
        averagePowerWatt: 195.5,
        strokeRatePerMinute: 42.0,
        symmetryPercent: 98.2,
      );

      final session = ErcolinaRecapAdapter.toNormalized(
        recap,
        athleteId: athleteId,
      );

      expect(session.source, NormalizedSessionSource.ercolina);
      expect(session.sourceId, 'ercolina_rec_42');
      expect(session.modality, XcModality.ercolinaDoublePoling);
      expect(session.technique, XcTechnique.doublePoling);
      expect(session.classificationProvenance, ClassificationProvenance.explicitSourceMetadata);
      expect(session.isIndoor, isTrue);
      expect(session.durationSeconds, 45 * 60);
      expect(session.externalMetrics.averagePowerWatt, 195.5);
      expect(session.externalMetrics.workJoule, 195.5 * 45 * 60);
      expect(session.externalMetrics.strokeOrCadenceRate, 42.0);
      expect(session.externalMetrics.leftRightSymmetryPercent, 98.2);
      expect(session.dataQuality.confidence, 1.0);
      expect(session.dataQuality.hasPower, isTrue);
      expect(session.dataQuality.hasCadenceOrStroke, isTrue);
      expect(session.dataQuality.hasHeartRate, isFalse);
    });

    test('2. Strava NordicSki ohne Technikangabe erzeugt skiNordicUnknown + technique = unknown', () {
      final strava = StravaActivity(
        id: 'strava_ski_1',
        name: 'Nachmittagsrunde Loipe',
        sportType: 'NordicSki',
        startDateLocal: DateTime.parse('2026-10-04 14:00:00'),
        movingTimeSeconds: 5400,
        elapsedTimeSeconds: 5600,
        distanceMetres: 22000.0,
        totalElevationGainMetres: 350.0,
        averageHeartRateBpm: 148.0,
        maxHeartRateBpm: 168,
      );

      final session = StravaActivityAdapter.toNormalized(
        strava,
        athleteId: athleteId,
      );

      expect(session.modality, XcModality.skiNordicUnknown);
      expect(session.technique, XcTechnique.unknown);
      expect(session.distanceMetres, 22000.0);
      expect(session.isIndoor, isFalse);
    });

    test('3. Strava/Garmin mit belegtem Skating erzeugt skiSkating', () {
      final stravaSkating = StravaActivity(
        id: 'strava_skate_1',
        name: '50 km Skating Engadin Vorbereitung G3 Eintakter',
        sportType: 'NordicSki',
        startDateLocal: DateTime.parse('2026-10-04 09:00:00'),
        movingTimeSeconds: 7200,
        elapsedTimeSeconds: 7300,
        distanceMetres: 35000.0,
      );

      final session = StravaActivityAdapter.toNormalized(
        stravaSkating,
        athleteId: athleteId,
      );

      expect(session.modality, XcModality.skiSkating);
      expect(session.technique, XcTechnique.skatingG3);
    });

    test('4. Strava/Garmin mit belegtem Classic erzeugt skiClassic', () {
      final stravaClassic = StravaActivity(
        id: 'strava_classic_1',
        name: 'Klassisch Diagonalschritt Runde Cierfs',
        sportType: 'NordicSki',
        startDateLocal: DateTime.parse('2026-10-04 10:00:00'),
        movingTimeSeconds: 4800,
        elapsedTimeSeconds: 4900,
        distanceMetres: 18000.0,
      );

      final session = StravaActivityAdapter.toNormalized(
        stravaClassic,
        athleteId: athleteId,
      );

      expect(session.modality, XcModality.skiClassic);
      expect(session.technique, XcTechnique.classicDiagonal);

      // Doppelstock auf Schnee
      final stravaDp = StravaActivity(
        id: 'strava_dp_1',
        name: '30km Doppelstock Flachstück',
        sportType: 'NordicSki',
        startDateLocal: DateTime.parse('2026-10-04 10:00:00'),
        movingTimeSeconds: 4800,
        elapsedTimeSeconds: 4900,
        distanceMetres: 30000.0,
      );

      final dpSession = StravaActivityAdapter.toNormalized(
        stravaDp,
        athleteId: athleteId,
      );
      expect(dpSession.modality, XcModality.doublePoling);
      expect(dpSession.technique, XcTechnique.doublePoling);
      expect(dpSession.classificationProvenance, ClassificationProvenance.titleInferred);
    });

    test('5. Rollerski ohne Technik erzeugt rollerSkiUnknown, mit Beleg spezifisch', () {
      final rollerUnknown = StravaActivity(
        id: 'strava_roller_1',
        name: 'Skiroller Nachmittag',
        sportType: 'RollerSki',
        startDateLocal: DateTime.parse('2026-10-04 16:00:00'),
        movingTimeSeconds: 3600,
        elapsedTimeSeconds: 3600,
        distanceMetres: 15000.0,
      );

      final session = StravaActivityAdapter.toNormalized(
        rollerUnknown,
        athleteId: athleteId,
      );
      expect(session.modality, XcModality.rollerSkiUnknown);
      expect(session.technique, XcTechnique.unknown);
      expect(session.classificationProvenance, ClassificationProvenance.explicitSourceMetadata);

      final rollerSkate = StravaActivity(
        id: 'strava_roller_2',
        name: 'Skiroller Skating G2 Berggang',
        sportType: 'RollerSki',
        startDateLocal: DateTime.parse('2026-10-04 16:00:00'),
        movingTimeSeconds: 3600,
        elapsedTimeSeconds: 3600,
        distanceMetres: 15000.0,
      );
      final skateSession = StravaActivityAdapter.toNormalized(
        rollerSkate,
        athleteId: athleteId,
      );
      expect(skateSession.modality, XcModality.rollerSkiSkating);
      expect(skateSession.technique, XcTechnique.skatingG2);
      expect(skateSession.classificationProvenance, ClassificationProvenance.titleInferred);

      final rollerDp = StravaActivity(
        id: 'strava_roller_3',
        name: 'Rollski DP Intervalle',
        sportType: 'RollerSki',
        startDateLocal: DateTime.parse('2026-10-04 16:00:00'),
        movingTimeSeconds: 3600,
        elapsedTimeSeconds: 3600,
        distanceMetres: 15000.0,
      );
      final dpSession = StravaActivityAdapter.toNormalized(
        rollerDp,
        athleteId: athleteId,
      );
      expect(dpSession.modality, XcModality.rollerSkiDoublePoling);
      expect(dpSession.technique, XcTechnique.doublePoling);
      expect(dpSession.classificationProvenance, ClassificationProvenance.titleInferred);
    });

    test('6. Rad/Lauf wird korrekt zu cycling/running', () {
      final bike = StravaActivity(
        id: 'strava_bike_1',
        name: 'Grundlage Rennrad Pass',
        sportType: 'Ride',
        startDateLocal: DateTime.parse('2026-10-04 09:00:00'),
        movingTimeSeconds: 7200,
        elapsedTimeSeconds: 7500,
        distanceMetres: 60000.0,
        averageWatts: 180.0,
        averageHeartRateBpm: 135.0,
      );
      final bikeSession = StravaActivityAdapter.toNormalized(
        bike,
        athleteId: athleteId,
      );
      expect(bikeSession.modality, XcModality.cycling);
      expect(bikeSession.isIndoor, isFalse);

      final virtualBike = StravaActivity(
        id: 'strava_vbike_1',
        name: 'Zwift Watopia Flat',
        sportType: 'VirtualRide',
        startDateLocal: DateTime.parse('2026-10-04 18:00:00'),
        movingTimeSeconds: 3600,
        elapsedTimeSeconds: 3600,
        distanceMetres: 35000.0,
      );
      final virtualSession = StravaActivityAdapter.toNormalized(
        virtualBike,
        athleteId: athleteId,
      );
      expect(virtualSession.modality, XcModality.cycling);
      expect(virtualSession.isIndoor, isTrue);

      final run = StravaActivity(
        id: 'strava_run_1',
        name: 'Laufrunde Wald',
        sportType: 'Run',
        startDateLocal: DateTime.parse('2026-10-04 07:00:00'),
        movingTimeSeconds: 2700,
        elapsedTimeSeconds: 2700,
        distanceMetres: 8000.0,
      );
      final runSession = StravaActivityAdapter.toNormalized(
        run,
        athleteId: athleteId,
      );
      expect(runSession.modality, XcModality.running);
    });

    test('7. Unbekannte Sportart wird nicht geraten', () {
      final unknownActivity = StravaActivity(
        id: 'strava_other_1',
        name: 'Kajak auf dem See',
        sportType: 'Kayaking',
        startDateLocal: DateTime.parse('2026-10-04 15:00:00'),
        movingTimeSeconds: 3600,
        elapsedTimeSeconds: 3600,
        distanceMetres: 5000.0,
      );
      final session = StravaActivityAdapter.toNormalized(
        unknownActivity,
        athleteId: athleteId,
      );
      expect(session.modality, XcModality.unknown);
      expect(session.technique, XcTechnique.unknown);
    });

    test('8. Fehlende HR erzeugt keine Phantasie-Herzfrequenz', () {
      final noHrActivity = StravaActivity(
        id: 'strava_nohr_1',
        name: 'Lockere Runde ohne Pulsgurt',
        sportType: 'Ride',
        startDateLocal: DateTime.parse('2026-10-04 11:00:00'),
        movingTimeSeconds: 3600,
        elapsedTimeSeconds: 3600,
        distanceMetres: 25000.0,
        averageHeartRateBpm: null,
        maxHeartRateBpm: null,
      );
      final session = StravaActivityAdapter.toNormalized(
        noHrActivity,
        athleteId: athleteId,
      );
      expect(session.internalMetrics.hasHeartRate, isFalse);
      expect(session.internalMetrics.averageHeartRateBpm, isNull);
      expect(session.internalMetrics.peakHeartRateBpm, isNull);
      expect(session.dataQuality.hasHeartRate, isFalse);
    });

    test('9. Fehlende Leistung erzeugt keine Phantasie-Watt', () {
      final noWattActivity = StravaActivity(
        id: 'strava_nowatt_1',
        name: 'Langlauf ohne Leistungsmesser',
        sportType: 'NordicSki',
        startDateLocal: DateTime.parse('2026-10-04 11:00:00'),
        movingTimeSeconds: 3600,
        elapsedTimeSeconds: 3600,
        distanceMetres: 15000.0,
        averageWatts: null,
        weightedAverageWatts: null,
      );
      final session = StravaActivityAdapter.toNormalized(
        noWattActivity,
        athleteId: athleteId,
      );
      expect(session.externalMetrics.hasPower, isFalse);
      expect(session.externalMetrics.averagePowerWatt, isNull);
      expect(session.externalMetrics.normalizedPowerWatt, isNull);
      expect(session.externalMetrics.workJoule, isNull);
      expect(session.dataQuality.hasPower, isFalse);
    });

    test('10. Provenance (source, sourceId, confidence) bleibt erhalten', () {
      const importRecord = ExternalActivityImport(
        activity: ExternalActivity(
          provider: ExternalProvider.garmin,
          sourceId: 'garmin_fit_9988',
          sport: 'CrossCountrySki',
          startedAtUtcUs: 1772532000000000,
          endedAtUtcUs: 1772535600000000,
          samples: [],
        ),
        fileName: 'skating_session_engadin.fit',
        recordCount: 1800,
        summary: ExternalActivitySummary(
          elapsedSeconds: 3600,
          activeSeconds: 3500,
          averageLoad: 175.0,
          averageHeartRateBpm: 152,
          distanceMetres: 16500.0,
        ),
      );

      final session = ExternalActivityAdapter.toNormalized(
        importRecord,
        athleteId: athleteId,
      );

      expect(session.source, NormalizedSessionSource.garmin);
      expect(session.sourceId, 'garmin_fit_9988');
      expect(session.classificationProvenance, ClassificationProvenance.titleInferred);
      expect(session.dataQuality.confidence, 0.90);
      expect(session.modality, XcModality.skiSkating);
      expect(session.externalMetrics.averagePowerWatt, 175.0);
      expect(session.internalMetrics.averageHeartRateBpm, 152.0);
    });

    test('11. Deduplizierung funktioniert weiterhin korrekt mit CanonicalActivitySignature', () {
      const deduplicator = ActivityDeduplicator();
      const startTime = 1772532000000000;

      // Garmin und Strava Aktivitäten desselben Laufs
      const garminSignature = CanonicalActivitySignature(
        sport: 'skiing',
        startedAtUtcUs: startTime,
        elapsedSeconds: 3600,
        distanceMetres: 15000.0,
      );

      final stravaSignature = CanonicalActivitySignature(
        sport: 'skiing',
        startedAtUtcUs: startTime + const Duration(seconds: 45).inMicroseconds,
        elapsedSeconds: 3620,
        distanceMetres: 15050.0,
      );

      expect(
        deduplicator.isSameActivity(garminSignature, stravaSignature),
        isTrue,
      );

      // Verschiedene Sportarten oder unterschiedliche Zeiten werden nicht dedupliziert
      const bikeSignature = CanonicalActivitySignature(
        sport: 'cycling',
        startedAtUtcUs: startTime,
        elapsedSeconds: 3600,
        distanceMetres: 15000.0,
      );
      expect(
        deduplicator.isSameActivity(garminSignature, bikeSignature),
        isFalse,
      );
    });

    test('12. Bestehende historische Daten bleiben lesbar (Serialization Roundtrip)', () {
      final original = NormalizedSession(
        id: 'norm_sess_test_1',
        athleteId: athleteId,
        source: NormalizedSessionSource.strava,
        sourceId: 'strava_777',
        startedAtUtcUs: 1772532000000000,
        durationSeconds: 5400,
        movingTimeSeconds: 5200,
        modality: XcModality.skiSkating,
        technique: XcTechnique.skatingG4,
        isIndoor: false,
        title: '50 km Skating Testlauf',
        distanceMetres: 25000.0,
        elevationGainMetres: 420.0,
        externalMetrics: const SessionExternalMetrics(
          averagePowerWatt: 185.0,
          workJoule: 962000.0,
        ),
        internalMetrics: const SessionInternalMetrics(
          averageHeartRateBpm: 155.0,
          peakHeartRateBpm: 178,
          rpe: 7.5,
        ),
        dataQuality: const SessionDataQuality(
          confidence: 0.85,
          hasHeartRate: true,
          hasPower: true,
          hasGps: true,
        ),
        rawMetadata: {'testKey': 'testVal'},
      );

      final json = original.toJson();
      final restored = NormalizedSession.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.athleteId, original.athleteId);
      expect(restored.source, original.source);
      expect(restored.sourceId, original.sourceId);
      expect(restored.modality, original.modality);
      expect(restored.technique, original.technique);
      expect(restored.distanceMetres, original.distanceMetres);
      expect(restored.externalMetrics.averagePowerWatt, original.externalMetrics.averagePowerWatt);
      expect(restored.internalMetrics.averageHeartRateBpm, original.internalMetrics.averageHeartRateBpm);
      expect(restored.dataQuality.confidence, original.dataQuality.confidence);
      expect(restored.rawMetadata['testKey'], 'testVal');
    });
  });
}
