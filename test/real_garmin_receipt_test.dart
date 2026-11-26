import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/app/canonical_today.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_coach/domain/normalized_session.dart';
import 'package:xc_coach/presentation/decision_card.dart';
import 'package:xc_ski_coach/coach_store.dart';

void main() {
  final path = Platform.environment['XC_PREVIEW_ARCHIVE'];
  final expected = Platform.environment['XC_VERIFY_GARMIN_ACTIVITY'];
  test(
    'real Garmin ID appears once in book and in canonical recommendation inputs',
    () {
      const athlete = 'own-athlete';
      final store = CoachStore(GiuliaDatabase.readOnly(path!));
      addTearDown(store.db.dispose);
      final sessions = store.storage.loadNormalizedSessions(
        athlete,
        limit: null,
      );
      final run = sessions
          .where(
            (s) =>
                s.source == NormalizedSessionSource.garmin &&
                s.sourceId == expected,
          )
          .single;
      final today = CanonicalTodayService(
        stateService: store.state,
        goalRepository: store.goals,
        planRepository: store.plans,
        storage: store.storage,
        persistDecisions: false,
      ).of(athlete);
      expect(today.state.eliteAnalysis.latestGarminSessionId, run.id);
      final persisted = store.storage.latestDailyDecision(athlete)!;
      expect(today.decision.decisionVersion, persisted.decisionVersion);
      // Exclude precisely this ID from the connection's temporary view. The
      // on-disk archive is open read-only and its source filters stay intact.
      final db = store.db.raw;
      final original =
          db
                  .select(
                    "SELECT sql FROM sqlite_temp_master WHERE name='xc_normalized_session'",
                  )
                  .single['sql']
              as String;
      db.execute(
        "CREATE TEMP TABLE excluded_test_session(id TEXT PRIMARY KEY)",
      );
      db.execute("INSERT INTO excluded_test_session VALUES (?)", [run.id]);
      db.execute("DROP VIEW temp.xc_normalized_session");
      final select = original.substring(original.indexOf(' AS') + 3);
      db.execute(
        'CREATE TEMP VIEW xc_normalized_session AS SELECT * FROM ($select) WHERE id NOT IN (SELECT id FROM excluded_test_session)',
      );
      final without = store.state
          .buildCurrentState(athleteId: athlete, asOf: today.state.asOf)
          .eliteAnalysis
          .allTime!;
      final withRun = today.state.eliteAnalysis.allTime!;
      expect(withRun.sessionCount - without.sessionCount, 1);
      expect(
        withRun.durationSeconds - without.durationSeconds,
        run.movingTimeSeconds,
      );
      expect(
        withRun.distanceMetres - without.distanceMetres,
        closeTo(run.distanceMetres!, 0.01),
      );
      print(
        'Differenz im Trainingsumfang: ${withRun.durationSeconds - without.durationSeconds} s. Empfehlung: ${persisted.prescribedWorkout?.title}',
      );
    },
    skip: path == null || expected == null,
  );
}
