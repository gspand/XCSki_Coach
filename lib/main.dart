import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show compute;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xc_coach/app/intelligence_factory.dart';
import 'package:xc_coach/app/session_report.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_coach/database/platform_repository.dart';
import 'package:xc_coach/database/session_repository.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'package:xc_coach/intelligence/planning/planning_models.dart';
import 'package:xc_coach/ui/analysis/unified_analysis_screen.dart';
import 'package:xc_coach/ui/athlete/athlete_management_dialog.dart';
import 'package:xc_coach/ui/athlete/athlete_state_view_screen.dart';
import 'package:xc_coach/ui/design_system.dart';
import 'package:xc_coach/ui/ercolina/training_goals_list_screen.dart';
import 'package:xc_coach/ui/female_athlete/female_athlete_screen.dart';
import 'package:xc_coach/ui/intelligence/giulia_coach.dart';
import 'package:xc_coach/ui/plan/plan_screen.dart';
import 'package:xc_coach/ui/plan/plan_view_model.dart';
import 'package:xc_coach/ui/today/today_screen.dart';
import 'evidence_screen.dart';
import 'package:xc_coach/lala/application/lala_controller.dart';
import 'package:xc_coach/database/diagnostics_repository.dart';
import 'package:xc_coach/products/garmin_fit_import.dart';
import 'package:xc_coach/ui/lala/lala_area.dart';
import 'package:xc_coach/ui/academy/academy_home_screen.dart';
import 'coach_store.dart';
import 'dashboard.dart';
import 'workout_header.dart';
import 'watch_snapshot.dart';
import 'garmin_personal.dart';
import 'garmin_training_status.dart';
import 'giulia_garmin.dart';
import 'package:http/http.dart' as http;
import 'garmin_connect_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'schedule.dart';
import 'month_plan.dart';
import 'scout_screen.dart';
import 'package:xc_coach/domain/training_sessions.dart';
import 'connections.dart';

void main() => runApp(
  MaterialApp(
    title: 'XC Ski Coach',
    debugShowCheckedModeBanner: false,
    locale: const Locale('de', 'AT'),
    supportedLocales: const [Locale('de', 'AT')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: giuliaLightTheme(mode: ProductMode.coach).copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff176651),
        primary: const Color(0xff155e4c),
        surface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xff172d29),
        surfaceTintColor: Colors.transparent,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Colors.white,
        indicatorColor: Color(0xffdcebc8),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: Color(0xffdcebc8),
      ),
    ),
    home: const ArchiveStart(),
  ),
);

void _initializeCoachArchive((String, String?) paths) {
  initializeArchive(paths.$1, paths.$2);
}

class ArchiveStart extends StatefulWidget {
  const ArchiveStart({super.key});
  @override
  State<ArchiveStart> createState() => _ArchiveStartState();
}

class _ArchiveStartState extends State<ArchiveStart> {
  CoachStore? store;
  bool busy = true;
  String? error;
  late String path;

  @override
  void initState() {
    super.initState();
    open();
  }

  Future<void> open({bool create = false, bool import = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final directory = await getApplicationSupportDirectory();
      await directory.create(recursive: true);
      path = '${directory.path}/xc-coach.db';
      if (create || import) {
        final file = import
            ? await openFile(
                acceptedTypeGroups: const [
                  XTypeGroup(
                    label: 'GIULIA-Archiv',
                    extensions: ['db', 'sqlite', 'sqlite3'],
                    uniformTypeIdentifiers: ['public.data'],
                  ),
                ],
              )
            : null;
        if (import && file == null) return;
        final destination = path;
        final source = file?.path;
        await compute(_initializeCoachArchive, (destination, source));
      }
      if (File(path).existsSync()) {
        store = CoachStore(GiuliaDatabase.open(path));
      }
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (store case final s?) return CoachHome(store: s);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(Icons.nordic_walking, size: 48),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'XC Ski Coach',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Öffne euer GIULIA-Archiv, um mit Trainingshistorie und Wettkampfzielen zu starten. Der Coach arbeitet mit einer eigenen Kopie.',
                  ),
                  const SizedBox(height: 24),
                  if (busy)
                    const LinearProgressIndicator()
                  else ...[
                    FilledButton.icon(
                      onPressed: () => open(import: true),
                      icon: const Icon(Icons.folder_open),
                      label: const Text('GIULIA-Archiv übernehmen'),
                    ),
                    TextButton(
                      onPressed: () => open(create: true),
                      child: const Text('Mit leeren Profilen starten'),
                    ),
                  ],
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CoachHome extends StatefulWidget {
  const CoachHome({super.key, required this.store});
  final CoachStore store;
  @override
  State<CoachHome> createState() => _CoachHomeState();
}

class _CoachHomeState extends State<CoachHome> with WidgetsBindingObserver {
  CoachStore get s => widget.store;
  late String id;
  int section = 0;
  int revision = 0;
  String? watchKey;
  CalendarDay day = CalendarDay.ofLocal(DateTime.now());
  Timer? midnight;
  Timer? syncTimer;
  final garminClient = http.Client();
  static const watch = MethodChannel('at.skybase.xcski/watch');
  static const areas = [
    ('Übersicht', Icons.dashboard_outlined),
    ('Plan', Icons.calendar_month_outlined),
    ('Verlauf', Icons.show_chart),
    ('Trainingsbuch', Icons.menu_book_outlined),
    ('Coach', Icons.nordic_walking),
  ];

  @override
  void initState() {
    super.initState();
    final saved = s.platform.appState('xc.active');
    id = s.athletes.any((a) => a.id == saved) ? saved! : s.athletes.first.id;
    WidgetsBinding.instance.addObserver(this);
    scheduleDay();
    startGarmin();
  }

  @override
  void dispose() {
    midnight?.cancel();
    syncTimer?.cancel();
    garminClient.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    syncTimer?.cancel();
    if (state == AppLifecycleState.resumed) {
      scheduleDay();
      startGarmin();
    }
  }

  void startGarmin() {
    syncTimer?.cancel();
    unawaited(syncGarmin(id));
    syncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(syncGarmin(id)),
    );
  }

  Future<void> syncGarmin(String profile) async {
    final service = GiuliaGarmin(
      s,
      profile,
      garminClient,
      GiuliaGarmin.deviceVault,
    );
    try {
      final oldCheck = service.archive.setting('lastPushCheck');
      final n = await service.synchronize();
      if (mounted && id == profile) {
        if (n > 0) {
          changed();
        } else if (service.archive.setting('lastPushCheck') != oldCheck) {
          setState(() {});
        }
      }
    } on MissingPluginException {
      // No platform key store when rendering a widget test.
    } catch (error) {
      if (mounted)
        service.archive.set(
          'pushError',
          error is GarminFailure
              ? error.message
              : 'Der automatische Garmin-Abruf wird bei der nächsten Verbindung wiederholt.',
        );
    }
  }

  void scheduleDay() {
    midnight?.cancel();
    final now = DateTime.now();
    final current = CalendarDay.ofLocal(now);
    if (current != day) {
      setState(() {
        day = current;
        revision++;
      });
    }
    midnight = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now),
      scheduleDay,
    );
  }

  void changed() {
    s.today.invalidate(id);
    setState(() => revision++);
  }

  void selectProfile(String value) {
    if (value != id && Platform.isIOS) {
      s.platform.setAppState(
        key: 'xc.watch.v2.profile',
        value: '',
        nowUtcUs: DateTime.now().microsecondsSinceEpoch,
      );
    }
    s.platform.setAppState(
      key: 'xc.active',
      value: value,
      nowUtcUs: DateTime.now().microsecondsSinceEpoch,
    );
    setState(() => id = value);
    startGarmin();
  }

  Future<void> visit(Widget screen, {bool refresh = false}) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted && refresh) changed();
  }

  void goals() {
    visit(
      TrainingGoalsListScreen(
        athleteId: id,
        organizationId: organization,
        goalRepository: s.goals,
        diagnostics: s.today.of(id).state.diagnostics,
      ),
      refresh: true,
    );
  }

  Future<void> diagnostics() async {
    final controller = LalaController(
      diagnostics: DiagnosticsRepository(s.db, platform: s.platform),
      session: LalaSession(
        userId: owner,
        organizationId: organization,
        roles: s.platform.rolesOf(userId: owner, organizationId: organization),
      ),
    )..selectAthlete(id);
    try {
      await visit(
        Scaffold(
          appBar: AppBar(
            title: const Text('Leistungsdiagnostik'),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.water_drop_outlined),
                label: const Text('Einzelproben'),
                onPressed: () {
                  final athlete = s.athletes
                      .where((a) => a.id == controller.selectedAthleteId)
                      .firstOrNull;
                  if (athlete != null)
                    visit(ScoutScreen(store: s, athlete: athlete));
                },
              ),
            ],
          ),
          body: LalaArea(
            controller: controller,
            activityImport: garminFitImport(context: context),
          ),
        ),
        refresh: true,
      );
    } finally {
      controller.dispose();
    }
  }

  void chat(AthleteSummary a) {
    visit(
      GiuliaCoachScreen(
        coach: giuliaCoachFor(
          todayFor: (id) => s.today.of(id).decision,
          database: s.db,
          platform: s.platform,
          organizationId: organization,
          userId: owner,
        ),
        athletes: [a],
        questions: defaultGiuliaQuestions,
        showCloseButton: true,
        initialAthleteId: id,
        storage: s.storage,
      ),
    );
  }

  Future<void> edit() async {
    if (await editAthleteDialog(
          context: context,
          platform: s.platform,
          athleteId: id,
          actorUserId: owner,
        ) &&
        mounted) {
      changed();
    }
  }

  List<String> _outlook() {
    final next =
        s.plans
            .planOf(id, from: day.addDays(1), to: day.addDays(7))
            .workouts
            .where((w) => w.isOpen)
            .toList()
          ..sort((a, b) => a.day.compareTo(b.day));
    return next.isEmpty
        ? ['Für die nächsten sieben Tage ist keine Einheit eingetragen.']
        : [
            for (final w in next)
              '${w.day.day}.${w.day.month}. · ${w.goal} · ${(w.durationSeconds / 60).round()} min',
          ];
  }

  Future<void> sendWatch(Map<String, Object> payload) async {
    try {
      await watch.invokeMethod<void>('update', payload);
    } on PlatformException {
      watchKey = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = s.athletes;
    final a = profiles.firstWhere((x) => x.id == id);
    final today = s.today.of(id);
    if (Platform.isIOS) {
      final bound = s.platform.appState('xc.watch.v2.profile');
      final payload = bound == id
          ? watchSnapshot(today, a.name)
          : <String, Object>{'schema': 2, 'kind': 'clear'};
      final key = [
        payload['kind'],
        payload['decisionId'],
        payload['decisionVersion'],
        payload['planVersion'],
        payload['athlete'],
      ].join('|');
      if (key != watchKey) {
        watchKey = key;
        unawaited(sendWatch(payload));
      }
    }
    final sessions = SessionRepository(s.db);
    final page = switch (section) {
      0 => SkiDashboard(
        key: ValueKey('$id-$revision-${day.key}'),
        store: s,
        athlete: id,
        name: a.name,
        day: day,
        today: today,
        onWorkout: () => setState(() => section = 4),
        onPlan: () => setState(() => section = 1),
        onGoals: goals,
        onSchedule: (date) => visit(
          Schedule(store: s, athlete: a, initialDay: date),
          refresh: true,
        ),
        onChanged: changed,
      ),
      4 => TodayScreen(
        key: ValueKey('$id-$revision'),
        initialState: today.state,
        initialNeeds: today.needs,
        recommendationHeader: (vm) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WorkoutHeader(
              workout: vm,
              planNote: today.dayNote,
              label: 'Coach fragen',
              onPressed: () => chat(a),
            ),
            const SizedBox(height: 12),
            GarminTrainingStatus(
              archive: GarminArchive(s, id),
              state: today.state,
              onConnect: () => visit(
                GarminConnectScreen(
                  archive: GarminArchive(s, id),
                  name: a.name,
                ),
                refresh: true,
              ),
            ),
          ],
        ),
        plannedOutlook: _outlook(),
        initialAvailability: today.availability,
        initialDecision: today.decision,
        initialFemaleContext: today.femaleContext,
        femaleRepository: s.state.femaleRepository,
        plannedWorkout: today.plannedWorkout,
        athleteName: a.name,
        athleteId: id,
        storage: s.storage,
        stateService: s.state,
        onInputsChanged: changed,
        showAppBar: false,
        showAthleteSwitcher: false,
        onOpenGiulia: () => chat(a),
        onOpenDevelopment: () => setState(() => section = 2),
        onNavigateToSection: (_) => setState(() => section = 2),
      ),
      1 => PlanScreen(
        key: ValueKey('$id-$revision'),
        viewModel: PlanViewModel.build(
          today: day,
          primaryGoal: TrainingGoal.primary(s.goals.goalsOf(id), day),
          weekWorkouts: s.plans
              .planOf(id, from: day.weekStart, to: day.weekStart.addDays(6))
              .workouts,
          availability: s.goals.availabilityOf(id),
          observed: trainingSessions(
            s.storage.loadNormalizedSessions(
              id,
              fromUtcUs: DateTime(
                day.weekStart.year,
                day.weekStart.month,
                day.weekStart.day,
              ).microsecondsSinceEpoch,
              toUtcUs: DateTime.now().microsecondsSinceEpoch,
              limit: null,
            ),
          ),
          needs: today.needs,
          state: today.state,
          todayDecision: today.decision,
        ),
        onEditGoal: goals,
        showAppBar: false,
      ),
      2 => AthleteStateViewScreen(
        key: ValueKey(id),
        athleteState: today.state,
        athleteName: a.name,
        onAskGiulia: () => chat(a),
        onEditProfile: edit,
      ),
      _ => UnifiedAnalysisScreen(
        key: ValueKey(id),
        athleteId: id,
        athleteName: a.name,
        storage: s.storage,
        sessions: sessions,
        reports: SessionReportReader(sessions),
      ),
    };
    final wide = MediaQuery.sizeOf(context).width >= 850;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.landscape_outlined, color: Color(0xff196752)),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'XC Ski Coach',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.7,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (section == 1)
            IconButton(
              tooltip: 'Monatskalender',
              onPressed: () =>
                  visit(MonthPlan(store: s, athlete: a), refresh: true),
              icon: const Icon(Icons.calendar_month),
            ),
          IconButton(
            tooltip: 'Garmin Connect',
            onPressed: () => visit(
              GarminConnectScreen(archive: GarminArchive(s, id), name: a.name),
              refresh: true,
            ),
            icon: const Icon(Icons.watch_outlined),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: const ValueKey('athlete-selector'),
              value: id,
              items: [
                for (final p in profiles)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name.split(' ').first),
                  ),
              ],
              onChanged: (v) {
                if (v != null) selectProfile(v);
              },
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Profil und Daten',
            onSelected: (v) {
              switch (v) {
                case 'goals':
                  goals();
                case 'profile':
                  edit();
                case 'chat':
                  chat(a);
                case 'sources':
                  visit(Connections(store: s, athlete: a), refresh: true);
                case 'watch':
                case 'unwatch':
                  s.platform.setAppState(
                    key: 'xc.watch.v2.profile',
                    value: v == 'watch' ? id : '',
                    nowUtcUs: DateTime.now().microsecondsSinceEpoch,
                  );
                  setState(() => watchKey = null);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        v == 'watch'
                            ? 'Tagesplan von ${a.name} zur Übertragung vorgemerkt.'
                            : 'Freigabe beendet. Die Uhr wird beim nächsten Kontakt aktualisiert.',
                      ),
                    ),
                  );
                case 'tests':
                  diagnostics();
                case 'schedule':
                  visit(Schedule(store: s, athlete: a), refresh: true);
                case 'academy':
                  visit(
                    Scaffold(
                      appBar: AppBar(
                        title: const Text('Trainingswissen'),
                        actions: [
                          TextButton.icon(
                            onPressed: () => visit(const EvidenceScreen()),
                            icon: const Icon(Icons.search),
                            label: const Text('Quellen suchen'),
                          ),
                        ],
                      ),
                      body: const AcademyHomeScreen(),
                    ),
                  );
                case 'cycle':
                  visit(
                    FemaleAthleteScreen(
                      athleteId: id,
                      femaleRepository: s.state.femaleRepository,
                      femaleContext: s.state.buildFemaleAthleteContext(
                        athleteId: id,
                      ),
                      onChanged: changed,
                    ),
                    refresh: true,
                  );
              }
            },
            itemBuilder: (_) => [
              if (Platform.isIOS)
                PopupMenuItem(
                  value: "watch",
                  child: Text(
                    "Tagesplan von ${a.name.split(' ').first} auf die Uhr",
                  ),
                ),
              if (Platform.isIOS &&
                  s.platform.appState('xc.watch.v2.profile') == id)
                const PopupMenuItem(
                  value: 'unwatch',
                  child: Text('Watch-Freigabe beenden'),
                ),
              PopupMenuItem(
                value: 'sources',
                child: Text('Datenquellen & Import'),
              ),
              PopupMenuItem(value: 'goals', child: Text('Wettkampfziele')),
              PopupMenuItem(value: 'schedule', child: Text('Einheit planen')),
              PopupMenuItem(value: 'tests', child: Text('Leistungsdiagnostik')),
              PopupMenuItem(value: 'academy', child: Text('Trainingswissen')),
              PopupMenuItem(value: 'chat', child: Text('Coach fragen')),
              PopupMenuItem(value: 'profile', child: Text('Profil bearbeiten')),
              PopupMenuItem(value: 'cycle', child: Text('Zyklus & Befinden')),
            ],
          ),
        ],
      ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1180,
              labelType: MediaQuery.sizeOf(context).width >= 1180
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              selectedIndex: section,
              onDestinationSelected: (i) => setState(() => section = i),
              destinations: [
                for (final x in areas)
                  NavigationRailDestination(
                    icon: Icon(x.$2),
                    label: Text(x.$1),
                  ),
              ],
            ),
          Expanded(child: page),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: section,
              onDestinationSelected: (i) => setState(() => section = i),
              destinations: [
                for (final x in areas)
                  NavigationDestination(icon: Icon(x.$2), label: x.$1),
              ],
            ),
    );
  }
}
