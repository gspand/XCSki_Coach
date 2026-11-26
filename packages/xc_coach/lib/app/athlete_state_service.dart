/// Orchestriert den Aufbau des kanonischen [XCAthleteState] aus realen,
/// persistierten Datenquellen:
/// - Persistierte [NormalizedSession]s aus zugelassenen Quellen
/// - Echte Diagnostik-Schwellenwerte aus dem Test-Archiv
/// - Aktuelles [TrainingGoal]
/// - Subjektiver Check-In ([SubjectiveReadinessState])
/// - Trainingsabdeckung aus zugelassenen Trainingsdaten
library;

import '../app/diagnostic_summary.dart';
import '../app/athlete_ercolina_profile.dart';
import '../database/coach_storage_repository.dart';
import '../database/diagnostic_summary_reader.dart';
import '../database/giulia_database.dart';
import '../database/female_athlete_repository.dart';
import '../database/platform_repository.dart';
import '../database/session_repository.dart';
import '../database/training_goal_repository.dart';
import '../domain/diagnostic_catalogue.dart';
import '../domain/normalized_session.dart';
import '../domain/training_sessions.dart';
import '../domain/training_plan.dart';
import '../domain/xc_modality.dart';
import '../domain/platform.dart';
import '../intelligence/female_athlete/cycle_evidence_engine.dart';
import '../intelligence/female_athlete/female_athlete_models.dart';
import '../intelligence/planning/planning_models.dart';
import '../intelligence/xc_athlete_state/diagnostics_state.dart';
import '../intelligence/xc_athlete_state/elite_analysis_state.dart';
import '../intelligence/xc_athlete_state/evidence_model.dart';
import '../intelligence/xc_athlete_state/goal_context.dart';
import '../intelligence/xc_athlete_state/subjective_readiness_state.dart';
import '../intelligence/xc_athlete_state/xc_athlete_state.dart';
import '../intelligence/xc_athlete_state/xc_athlete_state_builder.dart';

class AthleteStateService {
  AthleteStateService({
    required this.database,
    required this.storage,
    required this.goalRepository,
    SqliteFemaleAthleteRepository? femaleRepository,
    DiagnosticSummaryReader? diagnosticReader,
    CycleEvidenceEngine? cycleEngine,
  }) : _diagnosticReader =
           diagnosticReader ?? DiagnosticSummaryReader(database),
       _femaleRepository =
           femaleRepository ?? SqliteFemaleAthleteRepository(database),
       _cycleEngine = cycleEngine ?? const CycleEvidenceEngine();

  final GiuliaDatabase database;
  final SqliteCoachStorageRepository storage;
  final SqliteTrainingGoalRepository goalRepository;
  final SqliteFemaleAthleteRepository _femaleRepository;
  SqliteFemaleAthleteRepository get femaleRepository => _femaleRepository;
  final DiagnosticSummaryReader _diagnosticReader;
  final CycleEvidenceEngine _cycleEngine;
  final Map<String, ({int revision, AthleteErcolinaProfile profile})>
  _ercolinaProfileCache = {};

  /// Vollstaendiges Ercolina-Langzeitprofil, getrennt vom haeufig neu
  /// aufgebauten Tageszustand. Die teure Zug-fuer-Zug-Rekonstruktion laeuft
  /// nur, wenn sich eine Sessionzeile des Athleten geaendert hat.
  AthleteErcolinaProfile buildErcolinaProfile(String athleteId) {
    final revisionRows = database.raw.select(
      '''SELECT COALESCE(MAX(updated_at_utc_us), 0) AS revision
           FROM xc_session WHERE athlete_id = ?''',
      [athleteId],
    );
    final revision = revisionRows.single['revision'] as int? ?? 0;
    final cached = _ercolinaProfileCache[athleteId];
    if (cached != null && cached.revision == revision) return cached.profile;
    final profile = AthleteErcolinaProfileReader(
      SessionRepository(database),
    ).of(athleteId);
    _ercolinaProfileCache[athleteId] = (revision: revision, profile: profile);
    return profile;
  }

  /// Erstellt den aktuellen, vollständig geeichten [XCAthleteState] für einen Athleten.
  XCAthleteState buildCurrentState({
    required String athleteId,
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();
    final nowUtc = now.toUtc();
    final nowUtcUs = nowUtc.microsecondsSinceEpoch;

    // 1. Echte persistierte Sessions laden (vollständige Historie für Profil & Chronic Load)
    final sessions = trainingSessions(storage.loadNormalizedSessions(
      athleteId,
      toUtcUs: nowUtcUs,
      // Die Vollauswertung darf nicht am Repository-Standardlimit enden.
      // SQLite interpretiert LIMIT -1 als unlimitiert; der Bestand ist lokal
      // und wird hier bewusst vollständig für die Langzeitanalyse gelesen.
      limit: null,
    ));

    // 2. Diagnostik-Ergebnisse laden und in DiagnosticReference umwandeln
    final diagnostics = _loadDiagnostics(athleteId);

    // 3. Primäres Ziel laden
    final todayCal = CalendarDay.ofLocal(now);
    final goals = goalRepository.goalsOf(athleteId);
    final trainingGoal = TrainingGoal.primary(goals, todayCal);
    final goalContext = trainingGoal != null
        ? GoalContext(
            name: trainingGoal.name,
            modality: _mapTrainingModality(trainingGoal.modality),
            targetDistanceMetres: trainingGoal.distanceKm != null
                ? trainingGoal.distanceKm! * 1000.0
                : null,
            targetDurationSeconds: trainingGoal.targetSeconds,
            raceDate: trainingGoal.day != null
                ? DateTime(
                    trainingGoal.day!.year,
                    trainingGoal.day!.month,
                    trainingGoal.day!.day,
                  )
                : null,
            priority: switch (trainingGoal.priority) {
              GoalPriority.a => 'A',
              GoalPriority.b => 'B',
              GoalPriority.c => 'C',
            },
          )
        : null;

    // 4. Subjektiven Check-in laden
    final checkIn =
        storage.latestCheckIn(athleteId, onDay:now) ?? const SubjectiveReadinessState();

    final physiology = _loadPhysiology(athleteId, nowUtcUs);
    final ercolinaSessions = sessions
        .where((session) => session.source == NormalizedSessionSource.ercolina)
        .toList();
    final lastErcolinaSession = ercolinaSessions.isEmpty
        ? null
        : ercolinaSessions
              .map((session) => session.startedAtUtc)
              .reduce((a, b) => a.isAfter(b) ? a : b);

    // 6. XCAthleteStateBuilder ausführen
    return const XCAthleteStateBuilder().buildState(
      athleteId: athleteId,
      asOf: nowUtc,
      sessions: sessions,
      diagnostics: diagnostics,
      goal: goalContext,
      subjectiveReadiness: checkIn,
      lastErcolinaSession: lastErcolinaSession,
      physiology: physiology,
    );
  }

  AthletePhysiologyState _loadPhysiology(String athleteId, int asOfUtcUs) {
    final platform = PlatformRepository(database);
    final athleteRows = database.raw.select(
      'SELECT sex FROM athlete WHERE id = ? LIMIT 1',
      [athleteId],
    );
    return AthletePhysiologyState(
      bodyMassKg: platform.attributeAt(
        athleteId: athleteId,
        attribute: AthleteAttribute.bodyMassKg,
        asOfUtcUs: asOfUtcUs,
      ),
      maxHeartRateBpm: platform
          .attributeAt(
            athleteId: athleteId,
            attribute: AthleteAttribute.maxHeartRateBpm,
            asOfUtcUs: asOfUtcUs,
          )
          ?.round(),
      restingHeartRateBpm: platform
          .attributeAt(
            athleteId: athleteId,
            attribute: AthleteAttribute.restingHeartRateBpm,
            asOfUtcUs: asOfUtcUs,
          )
          ?.round(),
      sex: athleteRows.isEmpty ? null : athleteRows.first['sex'] as String?,
    );
  }

  /// Erstellt den [FemaleAthleteContext] für die Athletin (Opt-in, Zyklus, Evidenz, Symptome).
  FemaleAthleteContext buildFemaleAthleteContext({
    required String athleteId,
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();
    final profile = _femaleRepository.getProfile(athleteId);

    final optIn = profile?.optIn ?? FemaleCycleTrackingOptIn.undecided;
    final hormonalStatus = profile?.hormonalStatus ?? HormonalStatus.unknown;

    if (!optIn.isEnabled) {
      return FemaleAthleteContext(
        cycleContext: CycleContext(
          optIn: optIn,
          hormonalStatus: hormonalStatus,
          asOf: now,
        ),
        evidence: const CycleResponseEvidence(insufficientHistory: true),
        healthContext: const FemaleAthleteHealthContext(),
      );
    }

    final periods = _femaleRepository.loadPeriods(athleteId);
    final symptoms = _femaleRepository.loadSymptomReports(athleteId);
    final ironRecords = _femaleRepository.loadIronRecords(athleteId);
    final todaysSymptoms = _femaleRepository.getSymptomReportForDate(
      athleteId,
      now,
    );

    final cycleContext = _cycleEngine.buildCycleContext(
      optIn: optIn,
      hormonalStatus: hormonalStatus,
      periods: periods,
      isRegularCycle: profile?.isRegularCycle,
      configuredCycleLength: profile?.typicalCycleLengthDays,
      contraceptiveDetails: profile?.contraceptiveDetails,
      contraceptiveStartDate: profile?.contraceptiveStartedAtUtcUs != null
          ? DateTime.fromMicrosecondsSinceEpoch(
              profile!.contraceptiveStartedAtUtcUs!,
              isUtc: true,
            )
          : null,
      asOfDate: now,
    );

    final oneYearAgoUs = now
        .toUtc()
        .subtract(const Duration(days: 365))
        .microsecondsSinceEpoch;
    final sessions = trainingSessions(storage.loadNormalizedSessions(
      athleteId,
      fromUtcUs: oneYearAgoUs,
      limit:null,
      toUtcUs: now.toUtc().microsecondsSinceEpoch,
    ));

    final evidence = _cycleEngine.analyzePatterns(
      athleteId: athleteId,
      periods: periods,
      symptomReports: symptoms,
      sessions: sessions,
      asOfDate: now,
    );

    final healthContext = _cycleEngine.evaluateHealthSignals(
      athleteId: athleteId,
      hormonalStatus: hormonalStatus,
      periods: periods,
      symptomReports: symptoms,
      ironRecords: ironRecords,
      asOfDate: now,
    );

    return FemaleAthleteContext(
      cycleContext: cycleContext,
      evidence: evidence,
      healthContext: healthContext,
      todaysSymptoms: todaysSymptoms,
    );
  }

  /// Lädt Diagnostik-Schwellen und mappt sie in kanonische [DiagnosticReference]s.
  List<DiagnosticReference> _loadDiagnostics(String athleteId) {
    final summaries = _diagnosticReader.summariesOf(athleteId, limit: 10);
    final list = <DiagnosticReference>[];

    for (final s in summaries) {
      if (!s.hasResult) continue;

      final lt1 = s.thresholds
          .where((t) => t.type == SummaryThreshold.lt1)
          .firstOrNull;
      final lt2 = s.thresholds
          .where((t) => t.type == SummaryThreshold.lt2)
          .firstOrNull;
      if (lt1 == null && lt2 == null) continue;

      final testDate = DateTime.fromMicrosecondsSinceEpoch(
        s.startedAtUtcUs,
        isUtc: true,
      );
      final modality = s.diagnosticSport != null
          ? _mapDiagnosticSport(s.diagnosticSport!)
          : XcModality.skiSkating;

      final isRunning = modality == XcModality.running;
      final lt1SpeedKmh =
          isRunning &&
              lt1 != null &&
              (lt1.loadUnit.contains('km/h') || lt1.loadValue < 30)
          ? lt1.loadValue
          : null;
      final lt2SpeedKmh =
          isRunning &&
              lt2 != null &&
              (lt2.loadUnit.contains('km/h') || lt2.loadValue < 30)
          ? lt2.loadValue
          : null;

      list.add(
        DiagnosticReference(
          modality: modality,
          date: testDate,
          protocol: s.sport,
          lt1Ltp1Watt: isRunning ? null : lt1?.loadValue,
          lt2Ltp2Watt: isRunning ? null : lt2?.loadValue,
          lt1Ltp1PaceSecPerKm: lt1SpeedKmh != null && lt1SpeedKmh > 0
              ? (3600.0 / lt1SpeedKmh)
              : null,
          lt2Ltp2PaceSecPerKm: lt2SpeedKmh != null && lt2SpeedKmh > 0
              ? (3600.0 / lt2SpeedKmh)
              : null,
          lt1Ltp1Bpm: lt1?.heartRateBpm?.toDouble(),
          lt2Ltp2Bpm: lt2?.heartRateBpm?.toDouble(),
          source: 'LaLa Diagnostik-Archiv Test #${s.testId}',
          freshness: evaluateFreshness(testDate, asOf: DateTime.now().toUtc()),
          confidence: 1.0,
        ),
      );
    }

    return list;
  }

  static XcModality _mapTrainingModality(TrainingModality modality) =>
      switch (modality) {
        TrainingModality.ercolina => XcModality.ercolinaDoublePoling,
        TrainingModality.skiSkating => XcModality.skiSkating,
        TrainingModality.skiClassic => XcModality.skiClassic,
        TrainingModality.bikeIndoor ||
        TrainingModality.bikeOutdoor => XcModality.cycling,
        TrainingModality.running => XcModality.running,
      };

  XcModality _mapDiagnosticSport(DiagnosticSport sport) => switch (sport) {
    DiagnosticSport.ercolina => XcModality.ercolinaDoublePoling,
    DiagnosticSport.xcSki => XcModality.skiSkating,
    DiagnosticSport.running => XcModality.running,
    DiagnosticSport.cycling => XcModality.cycling,
  };
}
