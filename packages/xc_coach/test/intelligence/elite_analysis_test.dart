import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/database/coach_storage_repository.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_coach/domain/normalized_session.dart';
import 'package:xc_coach/domain/normalized_session_stream_analysis.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/elite_analysis_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/xc_athlete_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/xc_athlete_state_builder.dart';

void main() {
  const builder = XCAthleteStateBuilder();
  const athleteId = 'elite-athlete';
  final asOf = DateTime.utc(2026, 10, 6, 18);

  NormalizedSession session({
    required String id,
    required DateTime start,
    int durationSeconds = 3600,
    XcModality modality = XcModality.skiSkating,
    double? distanceMetres,
    double? elevationGainMetres,
    SessionExternalMetrics external = const SessionExternalMetrics(),
    SessionInternalMetrics internal = const SessionInternalMetrics(),
    SessionDataQuality quality = const SessionDataQuality(confidence: .9),
    Map<String, dynamic> rawMetadata = const {},
  }) => NormalizedSession(
    id: id,
    athleteId: athleteId,
    source: NormalizedSessionSource.garmin,
    sourceId: id,
    startedAtUtcUs: start.microsecondsSinceEpoch,
    durationSeconds: durationSeconds,
    movingTimeSeconds: durationSeconds,
    modality: modality,
    isIndoor: false,
    title: 'Standard $id',
    distanceMetres: distanceMetres,
    elevationGainMetres: elevationGainMetres,
    externalMetrics: external,
    internalMetrics: internal,
    dataQuality: quality,
    rawMetadata: rawMetadata,
  );

  group('EliteAnalysisState', () {
    test('wertet 7/28/90/180/365 Tage und die gesamte Historie aus', () {
      final old = session(
        id: 'old',
        start: DateTime.utc(2024, 1, 15),
        durationSeconds: 7200,
        distanceMetres: 30000,
        elevationGainMetres: 900,
      );
      final recent = session(
        id: 'recent',
        start: asOf.subtract(const Duration(days: 3)),
        durationSeconds: 5400,
        distanceMetres: 22000,
        elevationGainMetres: 650,
      );

      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        sessions: [recent, old],
      );

      expect(state.eliteAnalysis.windows.map((window) => window.key), [
        '7d',
        '28d',
        '90d',
        '180d',
        '365d',
        'all',
      ]);
      expect(state.eliteAnalysis.window('365d')!.sessionCount, 1);
      expect(state.eliteAnalysis.allTime!.sessionCount, 2);
      expect(state.eliteAnalysis.allTime!.durationSeconds, 12600);
      expect(state.eliteAnalysis.allTime!.distanceMetres, 52000);
      expect(
        state.eliteAnalysis.months.any(
          (month) =>
              month.year == 2024 && month.month == 2 && month.sessionCount == 0,
        ),
        isTrue,
        reason:
            'Trainingsfreie Monate müssen in der Historie sichtbar bleiben.',
      );
    });

    test('leitet HF-Zonen nur aus Stream plus individueller HFmax ab', () {
      final streamed = session(
        id: 'stream',
        start: asOf.subtract(const Duration(days: 1)),
        durationSeconds: 40,
        internal: const SessionInternalMetrics(
          averageHeartRateBpm: 150,
          peakHeartRateBpm: 185,
        ),
        rawMetadata: const {
          'streams': {
            'time': {
              'data': [0, 10, 20, 30, 40],
            },
            'heartrate': {
              'data': [100, 125, 150, 175, 190],
            },
          },
        },
      );

      final withoutAnchor = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        sessions: [streamed],
      );
      expect(withoutAnchor.eliteAnalysis.allTime!.classifiedHrZoneSeconds, 0);

      final individualized = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        sessions: [streamed],
        physiology: const AthletePhysiologyState(maxHeartRateBpm: 200),
      );
      final all = individualized.eliteAnalysis.allTime!;
      expect(all.sessionsWithDerivedHeartRateZones, 1);
      expect(all.classifiedHrZoneSeconds, 40);
      expect(all.hrZoneSeconds, {'z1': 10, 'z2': 10, 'z3': 10, 'z4': 10});
    });

    test(
      'kompakte Stream-Merkmale erhalten die wissenschaftliche Auswertung',
      () {
        final streamed = session(
          id: 'compact-stream',
          start: asOf.subtract(const Duration(days: 1)),
          durationSeconds: 50,
          internal: const SessionInternalMetrics(
            averageHeartRateBpm: 151,
            peakHeartRateBpm: 190,
          ),
          rawMetadata: const {
            'originalSportType': 'NordicSki',
            'streams': {
              'time': {
                'data': [0, 10, 20, 30, 40, 50, 200],
              },
              'heartrate': {
                'data': [100, 125, 150, 175, 190, 195, 200],
              },
              'watts': {
                'data': [100, 240, 310, 280],
              },
              'distance': {
                'data': [0, 100, 200, 300],
              },
            },
          },
        );
        final compact = NormalizedSession.fromJson(
          compactNormalizedSessionForAnalysis(streamed.toJson()),
        );

        final directState = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          sessions: [streamed],
          physiology: const AthletePhysiologyState(maxHeartRateBpm: 200),
        );
        final compactState = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          sessions: [compact],
          physiology: const AthletePhysiologyState(maxHeartRateBpm: 200),
        );

        expect(compact.rawMetadata, isNot(contains('streams')));
        expect(compact.rawMetadata, contains(normalizedStreamFeaturesKey));
        expect(compactState.toJson(), directState.toJson());
      },
    );

    test('berechnet keinen Banister-TRIMP aus unsichtbaren Standardwerten', () {
      final withHeartRate = session(
        id: 'hr',
        start: asOf.subtract(const Duration(days: 1)),
        internal: const SessionInternalMetrics(averageHeartRateBpm: 150),
      );

      final unknownPhysiology = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        sessions: [withHeartRate],
      );
      expect(unknownPhysiology.trainingLoad.banisterTrimpSeries, isNull);

      final individualized = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        sessions: [withHeartRate],
        physiology: const AthletePhysiologyState(
          maxHeartRateBpm: 190,
          restingHeartRateBpm: 50,
        ),
      );
      expect(individualized.trainingLoad.banisterTrimpSeries, isNotNull);
      expect(
        individualized
            .trainingLoad
            .banisterTrimpSeries!
            .parameters['individualHeartRateReference'],
        isTrue,
      );
    });

    test(
      'behandelt Tage nach dem letzten vollständigen Sync nicht als Ruhe',
      () {
        final withWork = session(
          id: 'work',
          start: DateTime.utc(2026, 10, 1, 8),
          external: const SessionExternalMetrics(workJoule: 600000),
        );

        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          sessions: [withWork],
          hasCompleteTrainingHistory: true,
          completeTrainingHistoryThrough: DateTime(2026, 10, 3, 23),
        );
        final states = state.trainingLoad.workKjSeries!.states;

        expect(states[1].isConfirmedRestDay, isTrue);
        expect(states[2].isConfirmedRestDay, isTrue);
        expect(states[3].isUnknownDay, isTrue);
        expect(states.last.isUnknownDay, isTrue);
      },
    );

    test(
      'Eliteanalyse und unbekannte Kalibrierung überleben JSON round-trip',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          sessions: [
            session(
              id: 'erc',
              start: asOf.subtract(const Duration(days: 2)),
              modality: XcModality.ercolinaDoublePoling,
              external: const SessionExternalMetrics(
                workPhaseAveragePowerWatt: 210,
                workJoule: 500000,
              ),
            ),
          ],
        );

        final restored = XCAthleteState.fromJson(state.toJson());
        expect(restored.eliteAnalysis.allTime!.sessionCount, 1);
        expect(restored.eliteAnalysis.personalBests, isNotEmpty);
        expect(restored.doublePoling.calibrationConfidence, isNull);
      },
    );
  });

  test('Repository kann für Vollauswertung mehr als 500 Sessions liefern', () {
    final database = GiuliaDatabase.inMemory();
    addTearDown(database.dispose);
    final nowUs = asOf.microsecondsSinceEpoch;
    database.raw.execute(
      "INSERT INTO organization(id, name, kind, created_at_utc_us, updated_at_utc_us) "
      "VALUES ('org', 'Test', 'private', ?, ?)",
      [nowUs, nowUs],
    );
    database.raw.execute(
      "INSERT INTO athlete(id, organization_id, name, created_at_utc_us, updated_at_utc_us) "
      "VALUES (?, 'org', 'Elite', ?, ?)",
      [athleteId, nowUs, nowUs],
    );
    final storage = SqliteCoachStorageRepository(database);
    for (var index = 0; index < 505; index++) {
      storage.saveNormalizedSession(
        session(
          id: 'history-$index',
          start: asOf.subtract(Duration(days: index)),
        ),
        nowUtcUs: nowUs,
      );
    }

    expect(storage.loadNormalizedSessions(athleteId), hasLength(500));
    expect(
      storage.loadNormalizedSessions(athleteId, limit: null),
      hasLength(505),
    );
  });

  test('Repository lädt kompakt und bewahrt die Originalstreams', () {
    final database = GiuliaDatabase.inMemory();
    addTearDown(database.dispose);
    final nowUs = asOf.microsecondsSinceEpoch;
    database.raw.execute(
      "INSERT INTO organization(id, name, kind, created_at_utc_us, updated_at_utc_us) "
      "VALUES ('org', 'Test', 'private', ?, ?)",
      [nowUs, nowUs],
    );
    database.raw.execute(
      "INSERT INTO athlete(id, organization_id, name, created_at_utc_us, updated_at_utc_us) "
      "VALUES (?, 'org', 'Elite', ?, ?)",
      [athleteId, nowUs, nowUs],
    );
    final storage = SqliteCoachStorageRepository(database);
    final streamed = session(
      id: 'retained-stream',
      start: asOf,
      durationSeconds: 20,
      rawMetadata: const {
        'streams': {
          'time': {
            'data': [0, 10, 20],
          },
          'heartrate': {
            'data': [120, 140, 160],
          },
          'distance': {
            'data': [0, 100, 200],
          },
        },
      },
    );
    storage.saveNormalizedSession(streamed, nowUtcUs: nowUs);

    final loaded = storage.loadNormalizedSessions(athleteId).single;
    final stored = database.raw.select(
      'SELECT data_json, analysis_json FROM normalized_session_record '
      'WHERE id = ?',
      [streamed.id],
    ).single;
    final sourceJson =
        jsonDecode(stored['data_json'] as String) as Map<String, dynamic>;
    final analysisJson =
        jsonDecode(stored['analysis_json'] as String) as Map<String, dynamic>;

    expect(
      (sourceJson['rawMetadata'] as Map<String, dynamic>),
      contains('streams'),
    );
    expect(
      (analysisJson['rawMetadata'] as Map<String, dynamic>),
      isNot(contains('streams')),
    );
    expect(loaded.rawMetadata, contains(normalizedStreamFeaturesKey));
  });
}
