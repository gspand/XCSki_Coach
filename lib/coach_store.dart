import 'dart:io';
import 'package:xc_coach/app/athlete_state_service.dart';
import 'package:xc_coach/app/canonical_today.dart';
import 'package:xc_coach/database/coach_storage_repository.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_coach/database/standalone_archive.dart';
import 'package:xc_coach/database/platform_repository.dart';
import 'package:xc_coach/database/training_goal_repository.dart';
import 'package:xc_coach/database/training_plan_repository.dart';
import 'package:xc_coach/domain/platform.dart';
import 'package:xc_coach/domain/normalized_session_adapters.dart';
import 'package:xc_coach/external_data/activity_import.dart';
import 'package:xc_coach/external_data/activity_import_repository.dart';

const organization = 'local-organization';
const owner = 'local-user';
const privateProfiles = {'own-athlete': 'Jan', 'karina-puercher': 'Karina'};

class CoachStore {
  CoachStore(this.db);
  final GiuliaDatabase db;
  late final platform = PlatformRepository(db);
  late final storage = SqliteCoachStorageRepository(db);
  late final goals = SqliteTrainingGoalRepository(db);
  late final plans = SqliteTrainingPlanRepository(db);
  late final state = AthleteStateService(
    database: db,
    storage: storage,
    goalRepository: goals,
  );
  late final today = CanonicalTodayService(
    stateService: state,
    goalRepository: goals,
    planRepository: plans,
    storage: storage,
  );

  List<AthleteSummary> get athletes => platform
      .visibleAthleteSummaries(userId: owner, organizationId: organization)
      .where(
        (a) =>
            privateProfiles.containsKey(a.id) ||
            platform.appState('xc.profile.${a.id}.enabled') == '1',
      )
      .toList();

  void createProfiles({Map<String, String> profiles = privateProfiles}) {
    final now = DateTime.now().microsecondsSinceEpoch;
    db.transaction(() {
      platform.createOrganization(
        id: organization,
        name: 'XC Ski Coach',
        kind: OrganizationKind.private,
        nowUtcUs: now,
      );
      platform.createUser(
        id: owner,
        displayName: 'Privater Coach',
        nowUtcUs: now,
      );
      platform.grantMembership(
        id: 'xc-owner',
        organizationId: organization,
        userId: owner,
        role: PlatformRole.admin,
        nowUtcUs: now,
      );
      for (final a in profiles.entries) {
        platform.createAthlete(
          id: a.key,
          organizationId: organization,
          name: a.value,
          nowUtcUs: now,
        );
        if (!privateProfiles.containsKey(a.key))
          platform.setAppState(
            key: 'xc.profile.${a.key}.enabled',
            value: '1',
            nowUtcUs: now,
          );
      }
    });
  }

  void importFit(String athlete, ExternalActivityImport fit) {
    final now = DateTime.now().microsecondsSinceEpoch;
    db.transaction(() {
      final result = ActivityImportRepository(db).write(
        fit,
        organizationId: organization,
        athleteId: athlete,
        actorUserId: owner,
        importedAtUtcUs: now,
      );
      if (result.athleteId != athlete) {
        throw StateError('Diese FIT-Datei gehört bereits zum anderen Profil.');
      }
      storage.saveNormalizedSession(
        ExternalActivityAdapter.toNormalized(fit, athleteId: athlete),
        nowUtcUs: now,
      );
    });
    today.invalidate(athlete);
  }
}

/// Creates a consistent private snapshot including committed WAL transactions.
/// Publish the finished file only after validation. The caller holds the
/// first-run lock and has not created a live coach database yet.
void initializeArchive(String destination, String? source) {
  final target = File(destination);
  final lock = File('$destination.lock').openSync(mode: FileMode.append);
  try {
    lock.lockSync(FileLock.exclusive);
    if (target.existsSync()) {
      throw StateError('An diesem Ort existiert bereits ein Trainingsarchiv.');
    }
    final staging = target.parent.createTempSync('xc-archive-');
    try {
      final path = '${staging.path}/coach.db';
      if (source != null) {
        copyGiuliaTrainingArchive(
          source,
          path,
          allowedAthletes: privateProfiles.keys.toSet(),
        );
      }
      final db = GiuliaDatabase.open(path);
      try {
        final store = CoachStore(db);
        if (source == null) {
          store.createProfiles();
        } else {
          if (store.athletes.length != privateProfiles.length) {
            throw const FormatException(
              'Im Archiv fehlen die privaten Profile von Jan oder Karina.',
            );
          }
          if (db.raw.select('PRAGMA quick_check').single.values.single !=
              'ok') {
            throw const FormatException('Archivprüfung fehlgeschlagen.');
          }
        }
        final checkpoint = db.raw
            .select('PRAGMA wal_checkpoint(TRUNCATE)')
            .single;
        if (checkpoint['busy'] != 0 ||
            checkpoint['log'] != checkpoint['checkpointed']) {
          throw StateError(
            'Das Trainingsarchiv konnte nicht vollständig gesichert werden.',
          );
        }
        // Publish a portable single-file checkpoint. The next ordinary app
        // connection re-enables WAL after the file is in its final location.
        final mode = db.raw
            .select('PRAGMA journal_mode=DELETE')
            .single
            .values
            .single;
        if (mode != 'delete') {
          throw StateError(
            'Das Trainingsarchiv konnte nicht als Einzeldatei gesichert werden.',
          );
        }
      } finally {
        db.dispose();
      }
      File(path).renameSync(destination);
    } finally {
      staging.deleteSync(recursive: true);
    }
  } finally {
    lock.closeSync();
  }
}
