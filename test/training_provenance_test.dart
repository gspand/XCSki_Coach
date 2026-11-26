import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/app/intelligence_data_source.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_coach/database/session_repository.dart';
import 'package:xc_coach/domain/normalized_session.dart';
import 'package:xc_coach/domain/training_sessions.dart';
import 'package:xc_coach/external_data/activity_import.dart';
import 'package:xc_coach/external_data/activity_import_repository.dart';
import 'package:xc_coach/external_data/normalization/external_data.dart';
import 'package:xc_ski_coach/coach_store.dart';
import 'package:xc_ski_coach/provider_import.dart';

void main() {
  const athlete = 'own-athlete';
  const other = 'karina-puercher';
  final observed = DateTime.utc(2026, 10, 18);
  final now = observed.microsecondsSinceEpoch;

  test(
    'previously imported Strava rows and cached decisions stay quarantined after reopen',
    () {
      final folder = Directory.systemTemp.createTempSync('xc-origin-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final path = '${folder.path}/fixture.db';
      final db = GiuliaDatabase.open(path);
      final store = CoachStore(db)..createProfiles();
      final direct = garminSession({
        'providerActivityId': 'skiing-test-123',
        'activityType': 'cross_country_skiing',
        'title': 'Klassisch',
        'startedAt': observed.toIso8601String(),
        'elapsedTime': 1800,
        'distance': 6.5,
      }, athlete);
      final restricted = direct.copyWith(
        id: 'legacy-fixture',
        source: NormalizedSessionSource.strava,
        rawMetadata: {
          'sufferScore': 100,
          'streams': {
            'watts': {
              'data': [300, 400],
            },
          },
        },
      );
      expect(
        () => store.storage.saveNormalizedSession(restricted, nowUtcUs: now),
        throwsUnsupportedError,
      );
      expect(
        () => store.storage.saveNormalizedSession(
          restricted.copyWith(source: NormalizedSessionSource.manual),
          nowUtcUs: now,
        ),
        throwsUnsupportedError,
      );
      for (var replay = 0; replay < 2; replay++) {
        store.storage.saveNormalizedSession(direct, nowUtcUs: now + replay);
      }
      db.raw.execute(
        '''INSERT INTO normalized_session_record
      (id, athlete_id, source, source_id, started_at_utc_us, duration_seconds,
       moving_time_seconds, modality, technique, provenance, is_indoor,
       title, data_json, created_at_utc_us)
      VALUES (?,?,'strava',?,?,?,?,?,?,?,0,?,?,?)''',
        [
          restricted.id,
          athlete,
          restricted.sourceId,
          now,
          1800,
          1800,
          restricted.modality.key,
          restricted.technique.key,
          restricted.classificationProvenance.key,
          restricted.title,
          jsonEncode(restricted.toJson()),
          now,
        ],
      );
      expect(trainingSessions([restricted, direct]).single.id, direct.id);
      expect(trainingSessions([direct, restricted]).single.id, direct.id);

      db.raw.execute(
        "INSERT INTO coach_chat_message (id, athlete_id, sender, text, created_at_utc_us) VALUES ('old',?,'coach','legacy-derived',?)",
        [athlete, now],
      );
      db.raw.execute(
        "INSERT INTO coach_decision_record VALUES ('old',?,?,?,?)",
        [athlete, now, 'invalid legacy JSON', now],
      );
      db.raw.execute(
        "INSERT INTO coach_validation_record_store VALUES ('old',?,?,?)",
        [athlete, now, 'invalid legacy JSON'],
      );
      store.storage.saveChatMessage(
        athleteId: athlete,
        sender: 'coach',
        text: 'clean',
        createdAtUtcUs: now,
      );
      db.dispose();

      final reopened = GiuliaDatabase.open(path);
      addTearDown(reopened.dispose);
      final reader = CoachStore(reopened);
      expect(reader.storage.loadNormalizedSessions(athlete).map((s) => s.id), [
        direct.id,
      ]);
      expect(reader.storage.loadNormalizedSessions(other), isEmpty);
      expect(
        reader.storage.savedStreams(
          athlete,
          NormalizedSessionSource.strava,
          restricted.sourceId,
        ),
        isNull,
      );
      expect(
        reader.storage.hasNormalizedSession(
          athleteId: athlete,
          source: NormalizedSessionSource.strava,
          sourceId: restricted.sourceId,
        ),
        isFalse,
      );
      expect(reader.storage.latestDailyDecision(athlete), isNull);
      expect(reader.storage.loadValidationRecords(athlete), isEmpty);
      expect(reader.storage.loadChatMessages(athlete).map((m) => m.text), [
        'clean',
      ]);
      final raw = reopened.raw.select(
        'SELECT data_json, analysis_json FROM normalized_session_record WHERE id=?',
        [restricted.id],
      ).single;
      expect(
        raw['analysis_json'],
        isNull,
        reason: 'quarantine precedes projection on every startup',
      );
      expect(raw['data_json'], jsonEncode(restricted.toJson()));
      final state = reader.state.buildCurrentState(
        athleteId: athlete,
        asOf: observed.add(const Duration(hours: 1)),
      );
      expect(state.eliteAnalysis.allTime!.sessionCount, 1);
      expect(state.eliteAnalysis.allTime!.durationSeconds, 1800);
    },
  );

  test(
    'session, observations and direct FIT are governed independently per source',
    () {
      final store = CoachStore(GiuliaDatabase.inMemory())..createProfiles();
      addTearDown(store.db.dispose);
      final db = store.db;
      final intel = GiuliaIntelligenceDataSource(
        database: db,
        platform: store.platform,
        organizationId: organization,
        userId: owner,
      );
      db.raw.execute(
        '''INSERT INTO session(id, organization_id, athlete_id, started_at_utc_us,
      ended_at_utc_us, movement_type, algorithm_version, processing_config_json, updated_at_utc_us)
      VALUES ('legacy',?,?,?,?,'running','fixture','{}',?)''',
        [organization, athlete, now, now + 60 * 1000000, now],
      );
      db.raw.execute(
        '''INSERT INTO external_activity_import
      (organization_id,provider_id,source_id,athlete_id,session_id,decoder_version,imported_at_utc_us)
      VALUES (?,'strava','old',?,'legacy','old',?)''',
        [organization, athlete, now],
      );
      db.raw.execute(
        '''INSERT INTO observation(id,athlete_id,observed_at_utc_us,type,value,source,quality,session_id)
      VALUES ('obs',?,?,'rpe',7,'manual','recorded','legacy')''',
        [athlete, now],
      );
      expect(SessionRepository(db).sessionById('legacy'), isNull);
      expect(
        SessionRepository(db).recentStrokeSessionsOfAthlete(athlete, limit: 4),
        isEmpty,
      );
      db.raw.execute(
        '''INSERT INTO athlete_state_snapshot VALUES
        ('old-state',?,?,?,?,'old-engine','old-fingerprint','invalid-legacy-json')''',
        [organization, athlete, now, now],
      );
      db.raw.execute(
        "INSERT INTO athlete_state_current VALUES (?,?,'old-state',?)",
        [athlete, organization, now],
      );
      db.raw.execute(
        'DELETE FROM athlete_state_refresh_queue WHERE athlete_id=?',
        [athlete],
      );
      expect(intel.getAthleteState(athlete, nowUtcUs: now), isNotNull);
      expect(
        db.raw
            .select(
              'SELECT snapshot_id FROM athlete_state_current WHERE athlete_id=?',
              [athlete],
            )
            .single
            .values
            .single,
        startsWith('athlete-state-xc-origin-v1-'),
      );
      expect(intel.getRecentTraining(athlete), isEmpty);
      expect(intel.getObservations(athlete), isEmpty);
      ExternalActivityImport fixture(
        ExternalProvider provider,
        FitFileOrigin? origin,
      ) => ExternalActivityImport(
        activity: ExternalActivity(
          provider: provider,
          sourceId: 'fit:fixture:0',
          fitFileOrigin: origin,
          sport: 'running',
          startedAtUtcUs: now,
          endedAtUtcUs: now + 60 * 1000000,
          samples: [
            ExternalLoadSample(atUtcUs: now, loadValue: 10, loadUnit: 'km/h'),
          ],
        ),
        fileName: 'fixture.fit',
        recordCount: 1,
        summary: const ExternalActivitySummary(
          elapsedSeconds: 60,
          activeSeconds: 60,
        ),
      );
      final imports = ActivityImportRepository(db);
      void write(ExternalActivityImport file) => imports.write(
        file,
        organizationId: organization,
        athleteId: athlete,
        actorUserId: owner,
        importedAtUtcUs: now,
      );
      expect(
        () => write(
          fixture(ExternalProvider.strava, FitFileOrigin.recordingDevice),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => write(fixture(ExternalProvider.garmin, null)),
        throwsUnsupportedError,
      );
      final clean = fixture(
        ExternalProvider.garmin,
        FitFileOrigin.recordingDevice,
      );
      store.importFit(athlete, clean);
      store.importFit(athlete, clean);
      expect(
        store.storage
            .loadNormalizedSessions(athlete)
            .single
            .rawMetadata['fileOrigin'],
        'recordingDevice',
      );
      expect(intel.getRecentTraining(athlete).length, 1);
      expect(store.storage.loadNormalizedSessions(other), isEmpty);
      expect(
        db.raw.select('SELECT COUNT(*) FROM session').single.values.single,
        2,
      );
      // Reconstruct an old canonical group with a blocked preferred source.
      final group = db.raw
          .select('SELECT id FROM canonical_activity')
          .single['id'];
      db.raw.execute(
        "INSERT INTO canonical_activity_source VALUES (?,'strava','old',?,'legacy',999,?)",
        [organization, group, now],
      );
      db.raw.execute(
        "UPDATE canonical_activity SET preferred_provider_id='strava',preferred_session_id='legacy',preferred_source_id='old' WHERE id=?",
        [group],
      );
      write(fixture(ExternalProvider.wahoo, FitFileOrigin.recordingDevice));
      final eligible = intel.getRecentTraining(athlete);
      expect(
        eligible,
        hasLength(1),
        reason:
            'only one independent duplicate contributes, including after new imports',
      );
      expect(eligible.single.id, isNot('legacy'));
      expect(
        db.raw
            .select('SELECT COUNT(*) FROM canonical_activity')
            .single
            .values
            .single,
        1,
      );
    },
  );
}
