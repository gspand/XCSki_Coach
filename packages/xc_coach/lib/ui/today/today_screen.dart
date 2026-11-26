/// GIULIA HEUTE (Today Screen) – Premium XC Coach Experience (V1).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE & UX-LEITPLANKEN:
/// - GIULIA darf sich NICHT wie ein wissenschaftliches Analyseprogramm anfühlen.
/// - Die zentrale UX-Frage lautet: «Was muss der Athlet jetzt wissen oder tun?»
/// - 4-Ebenen-Informationshierarchie:
///   1. ACTION: Hero Workout Card (Titel, Dauer, qualitative Intensität, Phasen, Start-Button)
///   2. WHY: Warum heute? (2–4 verständliche Sätze)
///   3. CONTEXT: Heute beachten (nur wenn nötig), Quick Check-in, Alternativen, Ausblick
///   4. EVIDENCE: Bottom Sheet («Mehr erfahren...») ohne kognitiven Zwang
/// - Responsives Design für iPhone (Single Column) und iPad (Split/Zwei-Spalten-Layout).
library;

import 'package:flutter/material.dart';

import '../../branding.dart';
import '../../domain/training_plan.dart';
import '../../intelligence/training_need/training_need_result.dart';
import '../../intelligence/workout_selection/availability_context.dart';
import '../../intelligence/workout_selection/daily_coaching_decision.dart';
import '../../intelligence/workout_selection/daily_decision_engine.dart';
import '../../intelligence/workout_selection/user_override_context.dart';
import '../../intelligence/xc_athlete_state/subjective_readiness_state.dart';
import '../../intelligence/xc_athlete_state/xc_athlete_state.dart';
import '../design_system.dart';
import '../../database/coach_storage_repository.dart';
import '../../external_data/strava/strava_sync_service.dart';
import '../../app/athlete_state_service.dart';
import '../../intelligence/training_need/training_need_engine.dart';
import '../../intelligence/workout_selection/coach_validation_mode.dart';
import '../debug/debug_sync_screen.dart';
import 'evidence_bottom_sheet.dart';
import '../../app/coach_plan_service.dart' show blueprintById;
import '../ercolina/pre_workout_sheet.dart';
import 'outdoor_pre_workout_sheet.dart';
import 'quick_check_in_sheet.dart';
import '../../intelligence/female_athlete/female_athlete_models.dart';
import '../../database/female_athlete_repository.dart';
import '../female_athlete/daily_cycle_symptom_sheet.dart';
import '../athlete/athlete_load_snapshot.dart';
import 'safe_alternatives_sheet.dart';
import 'today_view_model.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.initialState,
    required this.initialNeeds,
    this.initialAvailability,
    this.initialFemaleContext,
    this.initialDecision,
    this.recommendationHeader,
    this.plannedOutlook,
    this.onInputsChanged,
    this.femaleRepository,
    this.plannedWorkout,
    this.athleteName = 'Jan',
    this.athleteId = 'default',
    this.availableAthletes = const [],
    this.onSelectAthlete,
    this.onAddAthlete,
    this.decisionEngine = const DailyDecisionEngine(),
    this.storage,
    this.stateService,
    this.syncService,
    this.onStartErcolinaWorkout,
    this.onStartFreeErcolina,
    this.onOpenSettings,
    this.onNavigateToSection,
    this.onOpenGiulia,
    this.onOpenDevelopment,
    this.showAppBar = true,
    this.showAthleteSwitcher = true,
  });

  final XCAthleteState initialState;
  final TrainingNeedResult initialNeeds;
  final DayAvailability? initialAvailability;
  final FemaleAthleteContext? initialFemaleContext;
  final SqliteFemaleAthleteRepository? femaleRepository;
  final PlannedWorkout? plannedWorkout;
  final String athleteName;
  final String athleteId;
  final List<({String id, String name})> availableAthletes;
  final ValueChanged<String>? onSelectAthlete;
  final VoidCallback? onAddAthlete;
  final DailyDecisionEngine decisionEngine;

  /// Die kanonische heutige Entscheidung, bereits gerechnet und persistiert.
  ///
  /// Gesetzt heisst: HEUTE zeigt genau das, was PLAN(today) und GIULIA
  /// zeigen — dieselbe Instanz, nicht eine zweite Rechnung. Aendert der
  /// Athlet seine Verfuegbarkeit oder sein Befinden, rechnet dieser
  /// Bildschirm mit **derselben** Engine neu; eine zweite Auswahl- oder
  /// Dosislogik gibt es nicht mehr.
  final DailyCoachingDecision? initialDecision;
  final Widget Function(TodayViewModel)? recommendationHeader;
  final List<String>? plannedOutlook;
  final SqliteCoachStorageRepository? storage;
  final AthleteStateService? stateService;
  final StravaSyncService? syncService;
  final VoidCallback? onInputsChanged;
  final void Function(String workoutTitle, String? templateId)?
  onStartErcolinaWorkout;
  final VoidCallback? onStartFreeErcolina;
  final VoidCallback? onOpenSettings;
  final ValueChanged<String>? onNavigateToSection;
  final VoidCallback? onOpenGiulia;
  final VoidCallback? onOpenDevelopment;

  /// False when the screen lives inside the COACH hub, whose shell already
  /// owns title, profile and navigation. Nested app bars made the hierarchy
  /// look like two applications stacked on top of each other.
  final bool showAppBar;
  final bool showAthleteSwitcher;

  /// Die eine Tagesentscheidung, die auch TRAIN anzeigt. Ist sie gesetzt,
  /// berechnet dieser Bildschirm keine zweite Empfehlung.

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late XCAthleteState _athleteState;
  late TrainingNeedResult _needs;
  late DayAvailability _availability;
  FemaleAthleteContext? _femaleContext;
  UserOverrideContext? _userOverride;
  DailyCoachingDecision? _decision;
  TodayViewModel? _viewModel;
  bool _isLoading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _athleteState = widget.initialState;
    _needs = widget.initialNeeds;
    _femaleContext = widget.initialFemaleContext;
    _availability =
        widget.initialAvailability ??
        DayAvailability(
          date: DateTime.now().toUtc(),
          availableMinutes: 60,
          environment: TrainingEnvironment.outdoorSnow,
          hasSnow: true,
          hasErcolina: true,
        );
    final provided = widget.initialDecision;
    if (provided != null) {
      // Schon gerechnet und persistiert: uebernehmen, nicht neu rechnen.
      _decision = provided;
      _viewModel = TodayViewModel.fromDecision(
        decision: provided,
        state: _athleteState,
        availability: _availability,
        athleteName: widget.athleteName,
      );
    } else {
      _refreshRecommendation();
    }
  }

  /// Es gibt genau einen Weg zu «was trainiere ich heute».
  ///
  /// Hier stand eine Umschaltung: Lag ein `canonicalPlanning` vor — der
  /// Katalogpfad aus `planning/` —, wurde die Entscheidung des
  /// [DailyDecisionEngine] *verworfen* (`_decision = null`). Damit konnte
  /// derselbe Athlet am selben Tag zwei verschiedene Einheiten bekommen:
  /// HEUTE eine, PLAN eine andere. Im Replay waren das «Rad drinnen 180 min»
  /// gegen «Ercolina-DP 60 min».
  void _refreshRecommendation() {
    if (widget.onInputsChanged != null) {
      widget.onInputsChanged!();
    } else {
      _recomputeDecision();
    }
  }

  void _recomputeDecision() {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final decision = widget.decisionEngine.decide(
        state: _athleteState,
        needResult: _needs,
        availability: _availability,
        userOverride: _userOverride,
        femaleContext: _femaleContext,
        plannedWorkout: widget.plannedWorkout,
      );

      final vm = TodayViewModel.fromDecision(
        decision: decision,
        state: _athleteState,
        availability: _availability,
        athleteName: widget.athleteName,
      );

      // Persist decision & validation record if storage is available
      final storage = widget.storage;
      if (storage != null) {
        final nowUs = DateTime.now().toUtc().microsecondsSinceEpoch;
        storage.saveDailyDecision(
          athleteId: widget.athleteId,
          decision: decision,
          decidedAtUtcUs: nowUs,
        );

        final validationRecord = CoachValidationRecord(
          scenarioId: 'field_decision_${widget.athleteId}_$nowUs',
          timestamp: DateTime.now().toUtc(),
          versions: const CoachCoreVersions(),
          inputSnapshot: {
            'athleteState': _athleteState.toJson(),
            'needs': _needs.toJson(),
            'availability': _availability.toJson(),
            if (_userOverride != null) 'userOverride': _userOverride!.toJson(),
          },
          decision: decision,
          nextDayImplication: decision.prescribedWorkout != null
              ? 'Erholungsbedarf: ${decision.prescribedWorkout!.recoveryCost.label}'
              : decision.coachingReason,
        );
        storage.saveValidationRecord(
          athleteId: widget.athleteId,
          record: validationRecord,
          createdAtUtcUs: nowUs,
        );
      }

      setState(() {
        _decision = decision;
        _viewModel = vm;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }
  }

  void _handleQuickCheckInSave(SubjectiveReadinessState updatedReadiness) {
    _athleteState = _athleteState.copyWith(
      subjectiveReadiness: updatedReadiness,
    );
    final storage = widget.storage;
    if (storage != null) {
      storage.saveCheckIn(
        athleteId: widget.athleteId,
        readiness: updatedReadiness,
        recordedAtUtcUs: DateTime.now().toUtc().microsecondsSinceEpoch,
      );
    }
    _refreshRecommendation();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '$giuliaWordmark hat dein Training an deine Tagesform angepasst.',
        ),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _handleApplyOverride(
    UserOverrideContext override,
    int? overrideMinutes,
  ) {
    if (overrideMinutes != null) {
      _availability = _availability.copyWith(availableMinutes: overrideMinutes);
    }
    _userOverride = override;
    final storage = widget.storage;
    if (storage != null) {
      storage.saveUserOverride(
        athleteId: widget.athleteId,
        override: override,
        recordedAtUtcUs: DateTime.now().toUtc().microsecondsSinceEpoch,
      );
    }
    _refreshRecommendation();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Empfehlung mit deinen Präferenzen neu berechnet.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _refreshFromDatabase() {
    final stateService = widget.stateService;
    if (stateService != null) {
      final updatedState = stateService.buildCurrentState(
        athleteId: widget.athleteId,
      );
      final updatedNeeds = const TrainingNeedEngine().evaluate(
        state: updatedState,
      );
      final updatedFemaleContext = stateService.buildFemaleAthleteContext(
        athleteId: widget.athleteId,
      );
      setState(() {
        _athleteState = updatedState;
        _needs = updatedNeeds;
        _femaleContext = updatedFemaleContext;
      });
    }
    _refreshRecommendation();
  }

  void _openDebugSync() {
    final storage = widget.storage;
    final syncService = widget.syncService;
    if (storage == null || syncService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debug/Sync Service nicht verfügbar.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DebugSyncScreen(
          storage: storage,
          syncService: syncService,
          athleteId: widget.athleteId,
          currentState: _athleteState,
          onStateRefreshRequested: _refreshFromDatabase,
        ),
      ),
    );
  }

  void _startCurrentWorkout() {
    final vm = _viewModel;
    final dec = _decision;
    if (vm == null || dec == null || vm.isRestDay) return;

    if (vm.isErcolinaStartable && widget.onStartErcolinaWorkout != null) {
      final prescription = dec.prescribedWorkout;
      final blueprint = blueprintById(prescription?.templateId);
      void start() => widget.onStartErcolinaWorkout?.call(
        vm.heroTitle,
        prescription?.templateId,
      );
      if (blueprint == null) {
        // Keine ausfuehrbare Einheit hinter der Verschreibung: Dann startet
        // freies Training, und es gibt nichts anzuzeigen.
        start();
      } else {
        ErcolinaPreWorkoutSheet.show(
          context: context,
          blueprint: blueprint,
          prescribedMinutes: prescription?.totalDurationMinutes,
          coachingReason: dec.coachingReason,
          onStartConfirmed: start,
        );
      }
    } else {
      OutdoorPreWorkoutSheet.show(
        context: context,
        viewModel: vm,

      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isTablet = media.size.width >= 768;

    return Scaffold(
      backgroundColor: GiuliaTokens.surface0,
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: GiuliaTokens.surface0,
              elevation: 0,
              scrolledUnderElevation: 0,
              title: Text(
                giuliaWordmark,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: GiuliaTokens.textPrimary,
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(
                    Icons.refresh,
                    color: GiuliaTokens.textSecondary,
                  ),
                  tooltip: 'Aktualisieren',
                  onPressed: _refreshFromDatabase,
                ),
                if (widget.syncService != null && widget.storage != null)
                  IconButton(
                    icon: const Icon(
                      Icons.sync_alt,
                      color: GiuliaTokens.textSecondary,
                    ),
                    tooltip: 'Sync & Debug',
                    onPressed: _openDebugSync,
                  ),
                IconButton(
                  icon: const Icon(
                    Icons.person_outline,
                    color: GiuliaTokens.textSecondary,
                  ),
                  tooltip: 'Profil & Einstellungen',
                  onPressed: widget.onOpenSettings,
                ),
              ],
            )
          : null,
      body: SafeArea(child: _buildBody(context, isTablet)),
    );
  }

  Widget _buildBody(BuildContext context, bool isTablet) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: GiuliaTokens.accent),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(GiuliaTokens.spacingL),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: GiuliaTokens.error,
              ),
              const SizedBox(height: GiuliaTokens.spacingM),
              Text(
                '$giuliaWordmark konnte die heutige Empfehlung nicht berechnen.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: GiuliaTokens.spacingM),
              FilledButton.tonal(
                onPressed: _refreshRecommendation,
                child: const Text('Erneut versuchen'),
              ),
            ],
          ),
        ),
      );
    }

    final vm = _viewModel;
    if (vm == null) {
      return const Center(child: Text('Keine Trainingsdaten verfügbar.'));
    }

    if (isTablet) {
      return _buildTabletLayout(context, vm);
    } else {
      return _buildPhoneLayout(context, vm);
    }
  }

  // --- IPHONE LAYOUT (KLAR VERTISCH) ---
  Widget _buildPhoneLayout(BuildContext context, TodayViewModel vm) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        widget.recommendationHeader?.call(vm) ?? _buildHeroGreeting(context, vm),
        if (widget.onOpenDevelopment != null) ...[
          const SizedBox(height: GiuliaTokens.spacingM),
          AthleteLoadSnapshot(
            athleteState: _athleteState,
            onOpenFullEvaluation: widget.onOpenDevelopment,
          ),
        ],
        const SizedBox(height: GiuliaTokens.spacingL),
        _buildHeroWorkoutCard(context, vm),
        const SizedBox(height: GiuliaTokens.spacingL),
        _buildWhyTodayCard(context, vm),
        if (vm.importantNotes.isNotEmpty || vm.dataLimitations.isNotEmpty) ...[
          const SizedBox(height: GiuliaTokens.spacingM),
          _buildImportantCard(context, vm),
        ],
        const SizedBox(height: GiuliaTokens.spacingL),
        _buildSafeAlternativesCard(context, vm),
        const SizedBox(height: GiuliaTokens.spacingL),
        _buildQuickCheckInCard(context, vm),
        const SizedBox(height: GiuliaTokens.spacingL),
        _buildLookAheadCard(context, vm),
      ],
    );
  }

  // --- IPAD LAYOUT (SPLIT ZWEI-SPALTEN) ---
  Widget _buildTabletLayout(BuildContext context, TodayViewModel vm) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          children: [
            widget.recommendationHeader?.call(vm) ?? _buildHeroGreeting(context, vm),
            if (widget.onOpenDevelopment != null) ...[
              const SizedBox(height: GiuliaTokens.spacingM),
              AthleteLoadSnapshot(
                athleteState: _athleteState,
                onOpenFullEvaluation: widget.onOpenDevelopment,
              ),
            ],
            const SizedBox(height: GiuliaTokens.spacingL),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Linke Spalte: Hero Workout Card & Aktion
                Expanded(
                  flex: 6,
                  child: Column(
                    children: [
                      _buildHeroWorkoutCard(context, vm),
                      const SizedBox(height: GiuliaTokens.spacingM),
                      _buildSafeAlternativesCard(context, vm),
                    ],
                  ),
                ),
                const SizedBox(width: GiuliaTokens.spacingL),
                // Rechte Spalte: Warum, Hinweise, Check-in & Lookahead
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      _buildWhyTodayCard(context, vm),
                      if (vm.importantNotes.isNotEmpty ||
                          vm.dataLimitations.isNotEmpty) ...[
                        const SizedBox(height: GiuliaTokens.spacingM),
                        _buildImportantCard(context, vm),
                      ],
                      const SizedBox(height: GiuliaTokens.spacingM),
                      _buildQuickCheckInCard(context, vm),
                      const SizedBox(height: GiuliaTokens.spacingM),
                      _buildLookAheadCard(context, vm),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- HERO GREETING ---
  Widget _buildHeroGreeting(BuildContext context, TodayViewModel vm) {
    final text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                vm.greetingName,
                style: text.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: GiuliaTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                vm.coachPunchline,
                style: text.bodyLarge?.copyWith(
                  color: GiuliaTokens.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        if (widget.showAthleteSwitcher &&
            (widget.availableAthletes.isNotEmpty ||
                widget.onAddAthlete != null))
          PopupMenuButton<String>(
            tooltip: 'Athletenprofil wechseln',
            offset: const Offset(0, 40),
            color: GiuliaTokens.surface1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GiuliaTokens.radiusM),
              side: const BorderSide(color: GiuliaTokens.border),
            ),
            onSelected: (val) {
              if (val == '__add__') {
                widget.onAddAthlete?.call();
              } else {
                widget.onSelectAthlete?.call(val);
              }
            },
            itemBuilder: (ctx) => [
              for (final a in widget.availableAthletes)
                PopupMenuItem<String>(
                  value: a.id,
                  child: Row(
                    children: [
                      Icon(
                        a.id == widget.athleteId
                            ? Icons.check_circle_rounded
                            : Icons.person_outline,
                        size: 18,
                        color: a.id == widget.athleteId
                            ? GiuliaTokens.accent
                            : GiuliaTokens.textSecondary,
                      ),
                      const SizedBox(width: GiuliaTokens.spacingS),
                      Text(
                        a.name,
                        style: TextStyle(
                          fontWeight: a.id == widget.athleteId
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: GiuliaTokens.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              if (widget.onAddAthlete != null) ...[
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: '__add__',
                  child: Row(
                    children: [
                      Icon(Icons.add, size: 18, color: GiuliaTokens.accent),
                      SizedBox(width: GiuliaTokens.spacingS),
                      Text(
                        'Neues Profil...',
                        style: TextStyle(
                          color: GiuliaTokens.accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: GiuliaTokens.surface2,
                borderRadius: BorderRadius.circular(GiuliaTokens.radiusButton),
                border: Border.all(color: GiuliaTokens.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.person,
                    size: 16,
                    color: GiuliaTokens.accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.athleteName.split(' ').first,
                    style: text.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: GiuliaTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_drop_down,
                    size: 16,
                    color: GiuliaTokens.textSecondary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // --- EBENE 1: HERO WORKOUT CARD ---
  Widget _buildHeroWorkoutCard(BuildContext context, TodayViewModel vm) {
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: GiuliaTokens.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GiuliaTokens.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if(widget.recommendationHeader == null)...[
          // Row: Modality Badge & Duration
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: GiuliaTokens.accentSoft,
                    borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
                  ),
                  child: Text(
                    vm.modalityLabel.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(
                      color: GiuliaTokens.accent,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: GiuliaTokens.spacingS),
              if (!vm.isRestDay)
                Text(
                  '${vm.durationMinutes} MIN',
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: GiuliaTokens.textPrimary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingM),

          // Workout Title
          Text(
            vm.heroTitle,
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: GiuliaTokens.textPrimary,
              height: 1.15,
            ),
          ),
          const SizedBox(height: GiuliaTokens.spacingS),

          // Qualitative Intensity Pill
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: GiuliaTokens.surface2,
                borderRadius: BorderRadius.circular(GiuliaTokens.radiusButton),
                border: Border.all(color: GiuliaTokens.border),
              ),
              child: Text(
                vm.qualitativeIntensity.label,
                style: text.bodyMedium?.copyWith(
                  color: GiuliaTokens.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          ] else Text('Einheit im Detail',style:text.titleLarge?.copyWith(fontWeight:FontWeight.bold)),
          if (widget.onOpenGiulia != null) ...[
            const SizedBox(height: GiuliaTokens.spacingS),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('today-open-giulia'),
                onPressed: widget.onOpenGiulia,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('GIULIA FRAGEN: WARUM DIESE EINHEIT?'),
                style: TextButton.styleFrom(
                  foregroundColor: GiuliaTokens.accent,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],

          if (!vm.isRestDay) ...[
            const SizedBox(height: GiuliaTokens.spacingM),
            // Phase Breakdown
            Text(
              vm.phases.summaryText,
              style: text.bodySmall?.copyWith(
                color: GiuliaTokens.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              vm.structureText,
              style: text.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
            ),
          ],

          // Terrain Guidance (if present)
          if (vm.terrainGuidance != null) ...[
            const SizedBox(height: GiuliaTokens.spacingM),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: GiuliaTokens.surface0,
                borderRadius: BorderRadius.circular(GiuliaTokens.radiusM),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.terrain_outlined,
                    size: 18,
                    color: GiuliaTokens.accent,
                  ),
                  const SizedBox(width: GiuliaTokens.spacingS),
                  Expanded(
                    child: Text(
                      vm.terrainGuidance!,
                      style: text.bodySmall?.copyWith(
                        color: GiuliaTokens.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: GiuliaTokens.spacingL),

          // Primary Action Button
          if (!vm.isRestDay) ...[
            FilledButton(
              onPressed: _startCurrentWorkout,
              style: FilledButton.styleFrom(
                backgroundColor: GiuliaTokens.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    GiuliaTokens.radiusButton,
                  ),
                ),
                elevation: 0,
              ),
              child: Text(
                vm.isErcolinaStartable && widget.onStartErcolinaWorkout != null
                    ? 'TRAINING AUF ERCOLINA STARTEN'
                    : 'TRAINING ANSEHEN',
                style: text.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: Colors.white,
                ),
              ),
            ),
            if (widget.onStartFreeErcolina != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: widget.onStartFreeErcolina,
                icon: const Icon(Icons.play_circle_outline, size: 20),
                label: const Text('FREIES ERCOLINA-TRAINING STARTEN'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: GiuliaTokens.textPrimary,
                  side: const BorderSide(color: GiuliaTokens.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      GiuliaTokens.radiusButton,
                    ),
                  ),
                ),
              ),
            ],
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: GiuliaTokens.surface2,
                borderRadius: BorderRadius.circular(GiuliaTokens.radiusButton),
              ),
              alignment: Alignment.center,
              child: Text(
                'AKTIVE ODER PASSIVE ERHOLUNG',
                style: text.labelLarge?.copyWith(
                  color: GiuliaTokens.textSecondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (widget.onStartFreeErcolina != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: widget.onStartFreeErcolina,
                icon: const Icon(Icons.play_circle_outline, size: 20),
                label: const Text('TROTZDEM FREI TRAINIEREN'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: GiuliaTokens.textPrimary,
                  side: const BorderSide(color: GiuliaTokens.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      GiuliaTokens.radiusButton,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // --- EBENE 2: WARUM HEUTE? ---
  Widget _buildWhyTodayCard(BuildContext context, TodayViewModel vm) {
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: GiuliaTokens.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GiuliaTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline,
                size: 20,
                color: GiuliaTokens.accent,
              ),
              const SizedBox(width: GiuliaTokens.spacingS),
              Text(
                'Warum heute?',
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: GiuliaTokens.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          Text(
            vm.whyTodayText,
            style: text.bodyMedium?.copyWith(
              color: GiuliaTokens.textPrimary,
              height: 1.45,
            ),
          ),
          if (vm.whyReasons.isNotEmpty) ...[
            const SizedBox(height: GiuliaTokens.spacingM),
            for (final r in vm.whyReasons)
              InkWell(
                onTap: widget.onNavigateToSection != null
                    ? () => widget.onNavigateToSection!(r.targetSectionAnchor)
                    : () => EvidenceBottomSheet.show(context, vm),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '• ',
                        style: TextStyle(
                          color: GiuliaTokens.accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          r.text,
                          style: text.bodySmall?.copyWith(
                            color: GiuliaTokens.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: GiuliaTokens.spacingS),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: GiuliaTokens.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: GiuliaTokens.spacingM),
          InkWell(
            onTap: () => EvidenceBottomSheet.show(context, vm),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'Mehr erfahren & Evidenz',
                      style: text.bodySmall?.copyWith(
                        color: GiuliaTokens.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: GiuliaTokens.accent,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- EBENE 3: HEUTE BEACHTEN (SAFETY & DATENLÜCKEN) ---
  Widget _buildImportantCard(BuildContext context, TodayViewModel vm) {
    final text = Theme.of(context).textTheme;
    final isSevere = vm.hasActiveSafetyConstraint;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSevere ? const Color(0xFFFDF6F5) : GiuliaTokens.surface2,
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusM),
        border: Border.all(
          color: isSevere ? const Color(0xFFEBB5B0) : GiuliaTokens.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSevere
                    ? Icons.health_and_safety_outlined
                    : Icons.info_outline,
                size: 18,
                color: isSevere ? GiuliaTokens.error : GiuliaTokens.warning,
              ),
              const SizedBox(width: GiuliaTokens.spacingS),
              Text(
                'Heute beachten',
                style: text.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isSevere
                      ? GiuliaTokens.error
                      : GiuliaTokens.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          for (final note in vm.importantNotes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $note',
                style: text.bodySmall?.copyWith(
                  color: GiuliaTokens.textPrimary,
                ),
              ),
            ),
          for (final lim in vm.dataLimitations)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $lim',
                style: text.bodySmall?.copyWith(
                  color: GiuliaTokens.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- EBENE 3: HEUTE ANDERS TRAINIEREN? ---
  Widget _buildSafeAlternativesCard(BuildContext context, TodayViewModel vm) {
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: () => SafeAlternativesSheet.show(
        context: context,
        viewModel: vm,
        onApplyOverride: _handleApplyOverride,
      ),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: GiuliaTokens.surface1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GiuliaTokens.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.tune_outlined,
              size: 20,
              color: GiuliaTokens.textSecondary,
            ),
            const SizedBox(width: GiuliaTokens.spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Heute anders trainieren?',
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: GiuliaTokens.textPrimary,
                    ),
                  ),
                  Text(
                    'Zeit anpassen, Indoor/Outdoor oder Ruhetag wählen',
                    style: text.bodySmall?.copyWith(
                      color: GiuliaTokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: GiuliaTokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  // --- EBENE 3: QUICK CHECK-IN ---
  Widget _buildQuickCheckInCard(BuildContext context, TodayViewModel vm) {
    final text = Theme.of(context).textTheme;
    final readiness = _athleteState.subjectiveReadiness;
    final rec = readiness.perceivedRecovery != null
        ? '${readiness.perceivedRecovery!.toStringAsFixed(1)} / 10'
        : 'Noch nicht erfasst';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GiuliaTokens.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GiuliaTokens.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.self_improvement_outlined,
            size: 22,
            color: GiuliaTokens.accent,
          ),
          const SizedBox(width: GiuliaTokens.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tagesform & Erholung',
                  style: text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: GiuliaTokens.textPrimary,
                  ),
                ),
                Text(
                  'Erholung: $rec',
                  style: text.bodySmall?.copyWith(
                    color: GiuliaTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => QuickCheckInSheet.show(
              context: context,
              initialState: readiness,
              onSave: _handleQuickCheckInSave,
            ),
            child: const Text('Anpassen'),
          ),
          if (_femaleContext != null &&
              _femaleContext!.isTrackingActive &&
              widget.femaleRepository != null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(
                Icons.water_drop_outlined,
                size: 20,
                color: GiuliaTokens.accent,
              ),
              tooltip: 'Zyklus & Symptome',
              onPressed: () {
                DailyCycleSymptomSheet.show(
                  context: context,
                  initialReport: _femaleContext!.todaysSymptoms,
                  onSave: (report) {
                    widget.femaleRepository!.saveSymptomReport(
                      widget.athleteId,
                      report,
                      nowUtcUs: DateTime.now().toUtc().microsecondsSinceEpoch,
                    );
                    _refreshFromDatabase();
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  // --- EBENE 3: AUSBLICK / LOOK-AHEAD ---
  Widget _buildLookAheadCard(BuildContext context, TodayViewModel vm) {
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GiuliaTokens.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GiuliaTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: GiuliaTokens.textMuted,
              ),
              const SizedBox(width: GiuliaTokens.spacingS),
              Text(
                'Als Nächstes',
                style: text.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: GiuliaTokens.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          for (final outlook in widget.plannedOutlook ?? vm.nextDaysOutlook)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                outlook,
                style: text.bodySmall?.copyWith(
                  color: GiuliaTokens.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
