import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/app/athlete_state_service.dart';
import 'package:xc_coach/database/coach_storage_repository.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_coach/database/training_goal_repository.dart';
import 'package:xc_coach/domain/normalized_session.dart';
import 'package:xc_coach/domain/normalized_session_adapters.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:xc_coach/external_data/strava/strava_activity.dart';
import 'package:xc_coach/intelligence/load/stimulus_models.dart';
import 'package:xc_coach/intelligence/planning/planning_models.dart'
    hide DayAvailability;
import 'package:xc_coach/intelligence/training_need/need_types.dart';
import 'package:xc_coach/intelligence/training_need/training_need_engine.dart';
import 'package:xc_coach/intelligence/workout_selection/availability_context.dart';
import 'package:xc_coach/intelligence/workout_selection/daily_decision_engine.dart';
import 'package:xc_coach/intelligence/workout_selection/intensity_prescription.dart';
import 'package:xc_coach/intelligence/workout_selection/session_matching_service.dart';
import 'package:xc_coach/intelligence/workout_selection/user_override_context.dart';
import 'package:xc_coach/intelligence/workout_selection/workout_prescription.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/subjective_readiness_state.dart';
import 'package:xc_coach/app/session_recap.dart';

void main() {
  group('GIULIA Closed Loop End-to-End Integration Tests', () {
    late GiuliaDatabase db;
    late SqliteCoachStorageRepository storage;
    late SqliteTrainingGoalRepository goalRepo;
    late AthleteStateService stateService;

    setUp(() {
      db = GiuliaDatabase.inMemory();
      // Fixture: Organization and Athlete for foreign keys
      final nowUs = DateTime.now().toUtc().microsecondsSinceEpoch;
      db.raw.execute(
        "INSERT INTO organization(id, name, kind, created_at_utc_us, updated_at_utc_us) VALUES ('org_1', 'Test Org', 'club', ?, ?)",
        [nowUs, nowUs],
      );
      db.raw.execute(
        "INSERT INTO athlete(id, organization_id, name, created_at_utc_us, updated_at_utc_us) VALUES ('ath_1', 'org_1', 'Test Athlete', ?, ?)",
        [nowUs, nowUs],
      );
      db.raw.execute(
        "INSERT INTO athlete(id, organization_id, name, created_at_utc_us, updated_at_utc_us) VALUES ('ath_new', 'org_1', 'New Athlete', ?, ?)",
        [nowUs, nowUs],
      );

      storage = SqliteCoachStorageRepository(db);
      goalRepo = SqliteTrainingGoalRepository(db);
      stateService = AthleteStateService(
        database: db,
        storage: storage,
        goalRepository: goalRepo,
      );
    });

    test('Test A: a Strava adapter result cannot reach the XC archive', () {
      final nowUtc = DateTime.now().toUtc();
      final stravaActivity = StravaActivity(
        id: 'strava_123456',
        name: 'Gondelrunde Skating Intervall',
        sportType: 'NordicSki',
        startDateLocal: nowUtc.subtract(const Duration(days: 2)).toLocal(),
        elapsedTimeSeconds: 4200,
        movingTimeSeconds: 3600,
        distanceMetres: 16500.0,
        totalElevationGainMetres: 280.0,
        averageHeartRateBpm: 156.0,
        maxHeartRateBpm: 178,
        sufferScore: 78,
      );

      final normalized = StravaActivityAdapter.toNormalized(
        stravaActivity,
        athleteId: 'ath_1',
      );

      expect(normalized.modality, XcModality.skiSkating);
      expect(normalized.distanceMetres, 16500.0);
      expect(normalized.internalMetrics.averageHeartRateBpm, 156.0);

      final nowUs = nowUtc.microsecondsSinceEpoch;
      expect(() => storage.saveNormalizedSession(normalized, nowUtcUs: nowUs),
          throwsUnsupportedError);
      expect(storage.loadNormalizedSessions('ath_1'), isEmpty);
    });

    test('Test B: AthleteState + Goal + Availability -> DailyDecisionEngine closed loop', () {
      final nowUtc = DateTime.now().toUtc();
      
      // Goal setzen: Engadin Skimarathon (50km Skating)
      final goal = TrainingGoal(
        id: 'goal_engadin',
        name: 'Engadin Skimarathon',
        day: CalendarDay.ofLocal(nowUtc.add(const Duration(days: 90))),
        distanceKm: 50.0,
        modality: TrainingModality.skiSkating,
        priority: GoalPriority.a,
      );
      goalRepo.saveGoal(
        goal,
        id: 'goal_engadin',
        organizationId: 'org_1',
        athleteId: 'ath_1',
        nowUtcUs: nowUtc.microsecondsSinceEpoch,
      );

      // Echte Sessions einfügen
      final session = NormalizedSession(
        id: 'ses_1',
        athleteId: 'ath_1',
        source: NormalizedSessionSource.manual,
        sourceId: 'manual_999',
        startedAtUtcUs: nowUtc.subtract(const Duration(days: 1)).microsecondsSinceEpoch,
        durationSeconds: 3600,
        movingTimeSeconds: 3600,
        modality: XcModality.skiSkating,
        technique: XcTechnique.unknown,
        isIndoor: false,
        title: 'Locker Skating',
        dataQuality: const SessionDataQuality(confidence: 1.0),
      );
      storage.saveNormalizedSession(session, nowUtcUs: nowUtc.microsecondsSinceEpoch);

      // State aus DB aufbauen
      final athleteState = stateService.buildCurrentState(
        athleteId: 'ath_1',
        asOf: nowUtc,
      );

      expect(athleteState.athleteId, 'ath_1');
      expect(athleteState.goal?.name, 'Engadin Skimarathon');
      expect(athleteState.skiExposure.exposureOf(XcModality.skiSkating).sessionCount28d, 1);

      // Needs ermitteln
      final needs = const TrainingNeedEngine().evaluate(state: athleteState);
      expect(needs.developmentNeeds.isNotEmpty || needs.informationNeeds.isNotEmpty, isTrue);

      // DailyDecisionEngine ausführen
      final availability = DayAvailability(
        date: nowUtc,
        availableMinutes: 90,
        environment: TrainingEnvironment.outdoorSnow,
        hasSnow: true,
        hasErcolina: true,
      );

      final decision = const DailyDecisionEngine().decide(
        state: athleteState,
        needResult: needs,
        availability: availability,
      );

      expect(decision.athleteId, 'ath_1');
      expect(decision.prescribedWorkout, isNotNull);
      expect(decision.coachingReason.isNotEmpty, isTrue);

      // Decision und Validation Record persistieren
      storage.saveDailyDecision(
        athleteId: 'ath_1',
        decision: decision,
        decidedAtUtcUs: nowUtc.microsecondsSinceEpoch,
      );

      final loadedDecision = storage.latestDailyDecision('ath_1');
      expect(loadedDecision, isNotNull);
      expect(loadedDecision?.coachingReason, decision.coachingReason);
    });

    test('Test C & D: Quick Check-in and User Override persist & reshape state/decisions', () {
      final nowUtc = DateTime.now().toUtc();
      final nowUs = nowUtc.microsecondsSinceEpoch;

      // 1. Quick Check-In speichern
      const readiness = SubjectiveReadinessState(
        sleepQuality: 3.0, // schlecht geschlafen
        muscleSoreness: 7.0, // hohe Erschöpfung
        perceivedRecovery: 4.0,
      );
      storage.saveCheckIn(
        athleteId: 'ath_1',
        readiness: readiness,
        recordedAtUtcUs: nowUs,
      );

      final loadedCheckIn = storage.latestCheckIn('ath_1');
      expect(loadedCheckIn, isNotNull);
      expect(loadedCheckIn?.sleepQuality, 3.0);
      expect(loadedCheckIn?.muscleSoreness, 7.0);

      // State neu laden -> Check-In muss im XCAthleteState präsent sein
      final updatedState = stateService.buildCurrentState(
        athleteId: 'ath_1',
        asOf: nowUtc,
      );
      expect(updatedState.subjectiveReadiness.muscleSoreness, 7.0);

      // 2. User Override speichern
      const override = UserOverrideContext(
        heavyLegs: true,
        forcedRestDay: false,
        notes: 'Waden verhärtet',
      );
      storage.saveUserOverride(
        athleteId: 'ath_1',
        override: override,
        recordedAtUtcUs: nowUs + 10,
      );

      final loadedOverride = storage.latestUserOverride('ath_1');
      expect(loadedOverride, isNotNull);
      expect(loadedOverride?.heavyLegs, isTrue);
      expect(loadedOverride?.notes, 'Waden verhärtet');
    });

    test('Test E: Ercolina session -> NormalizedSession -> Storage -> AthleteState update', () {
      final nowUtc = DateTime.now().toUtc();
      final recap = SessionRecap(
        sessionId: 'erc_test_001',
        startedAtUtcUs: nowUtc.subtract(const Duration(hours: 2)).microsecondsSinceEpoch,
        duration: const Duration(minutes: 30),
        averagePowerWatt: 185.0,
        strokeRatePerMinute: 42.0,
        symmetryPercent: 98.0,
      );

      final normalized = ErcolinaRecapAdapter.toNormalized(
        recap,
        athleteId: 'ath_1',
      );

      expect(normalized.id, 'ercolina_erc_test_001');
      expect(normalized.modality, XcModality.ercolinaDoublePoling);
      expect(normalized.externalMetrics.averagePowerWatt, 185.0);

      storage.saveNormalizedSession(normalized, nowUtcUs: nowUtc.microsecondsSinceEpoch);

      final state = stateService.buildCurrentState(
        athleteId: 'ath_1',
        asOf: nowUtc,
      );

      expect(state.doublePoling.recentSessionAveragePowerWatt, 185.0);
    });

    test('Test G: Data Coverage tracking correctly calculates unknown days when sync is incomplete', () {
      final nowUtc = DateTime.now().toUtc();
      
      // Keinerlei Sessions vorhanden, kein Strava Sync
      final emptyState = stateService.buildCurrentState(
        athleteId: 'ath_new',
        asOf: nowUtc,
      );

      expect(emptyState.dataCoverage.unknownDays28d, 28);
      expect(emptyState.dataCoverage.overallCoverageRatio, 0.0);
      expect(emptyState.dataCoverage.coverageAssessmentText.contains('unvollständig'), isTrue);
    });

    test('Test H: SessionMatchingService matches prescription with completed NormalizedSession', () {
      final nowUtc = DateTime.now().toUtc();
      final matchingService = const SessionMatchingService();

      final prescription = WorkoutPrescription(
        id: 'presc_1',
        title: '30 min Ercolina Grundlagenausdauer',
        modality: XcModality.ercolinaDoublePoling,
        family: WorkoutFamilyType.easyBase,
        totalDurationMinutes: 30,
        warmupMinutes: 5,
        workMinutes: 20,
        cooldownMinutes: 5,
        structureDescription: '30 min gleichmäßig GA1',
        workIntensity: const IntensityPrescription(
          modality: XcModality.ercolinaDoublePoling,
          targetType: IntensityTargetType.multiAnchor,
          zoneLabel: 'Z1/Z2',
          rationale: 'GA1',
        ),
        recoveryIntensity: const IntensityPrescription(
          modality: XcModality.ercolinaDoublePoling,
          targetType: IntensityTargetType.multiAnchor,
          zoneLabel: 'Z1',
          rationale: 'Trab',
        ),
        intendedStimuli: const [StimulusType.doublePolingEndurance],
        primaryNeedAddressed: TrainingNeedType.doublePolingEndurance,
      );

      final completedSession = NormalizedSession(
        id: 'erc_comp_1',
        athleteId: 'ath_1',
        source: NormalizedSessionSource.ercolina,
        sourceId: 'erc_comp_1',
        startedAtUtcUs: nowUtc.microsecondsSinceEpoch,
        durationSeconds: 1800, // 30 min
        movingTimeSeconds: 1800,
        modality: XcModality.ercolinaDoublePoling,
        technique: XcTechnique.doublePoling,
        isIndoor: true,
        title: 'Ercolina Doppelstock',
      );

      final match = matchingService.evaluateMatch(
        prescription: prescription,
        session: completedSession,
      );

      expect(match.isMatched, isTrue);
      expect(match.confidence, MatchConfidence.exactMatch);
    });
  });
}
