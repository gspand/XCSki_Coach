import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:xc_coach/app/canonical_today.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'package:xc_coach/domain/training_sessions.dart';
import 'package:xc_coach/intelligence/planning/planning_models.dart';
import 'package:xc_coach/ui/today/today_view_model.dart';

import 'coach_store.dart';
import 'workout_header.dart';
import 'dashboard_history.dart';
import 'health_trend.dart';
import 'garmin_connect_screen.dart';
import 'garmin_personal.dart';
import 'garmin_training_status.dart';

const _ink = Color(0xff172d29),
    _muted = Color(0xff526760),
    _lime = Color(0xffd8f170),
    _border = Color(0xffd7dfd9),
    _green = Color(0xff15745e),
    _paper = Color(0xfff3f5f0);
const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const _months = [
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember',
];
String _date(CalendarDay d) => '${d.day}. ${_months[d.month - 1]}';
String _duration(int seconds) {
  final m = (seconds / 60).round();
  if (m < 60) return '$m min';
  return m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${m % 60} min';
}

TextStyle _type(
  double size, {
  Color color = _ink,
  FontWeight weight = FontWeight.w600,
  double spacing = 0,
}) => TextStyle(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: spacing,
  height: 1.17,
);
Widget _label(String text, {Color color = _muted}) => Text(
  text,
  style: _type(11, color: color, weight: FontWeight.w700, spacing: 1.2),
);
BoxDecoration _surface({Color color = Colors.white}) => BoxDecoration(
  color: color,
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: _border),
);

class SkiDashboard extends StatefulWidget {
  const SkiDashboard({
    super.key,
    required this.store,
    required this.athlete,
    required this.name,
    required this.day,
    required this.today,
    required this.onWorkout,
    required this.onPlan,
    required this.onGoals,
    required this.onSchedule,
    required this.onChanged,
  });
  final CoachStore store;
  final String athlete, name;
  final CalendarDay day;
  final CanonicalToday today;
  final VoidCallback onWorkout, onPlan, onGoals, onChanged;
  final ValueChanged<CalendarDay> onSchedule;
  @override
  State<SkiDashboard> createState() => _SkiDashboardState();
}

class _SkiDashboardState extends State<SkiDashboard> {
  late CalendarDay selected = widget.day;
  int weekOffset = 0;
  GarminArchive get archive => GarminArchive(widget.store, widget.athlete);
  static const panels = {
    'training': 'Trainingswoche und Umfang',
    'recovery': 'Erholung',
    'garmin': 'Letzte Garmin-Einheit',
  };
  late List<String> layout = [
    ...(archive.setting('dashboardOrder') ?? '')
        .split(',')
        .where(panels.containsKey),
    ...panels.keys,
  ].toSet().toList();
  late Set<String> hidden = (archive.setting('dashboardHidden') ?? '')
      .split(',')
      .where(panels.containsKey)
      .toSet();
  Future<void> customize() async {
    final order = [...layout], off = {...hidden};
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: const Text('Übersicht anpassen'),
          content: SizedBox(
            width: 390,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < order.length; i++)
                  Row(
                    children: [
                      Checkbox(
                        value: !off.contains(order[i]),
                        onChanged: (v) => refresh(() {
                          if (v == true) {
                            off.remove(order[i]);
                          } else {
                            off.add(order[i]);
                          }
                        }),
                      ),
                      Expanded(child: Text(panels[order[i]]!)),
                      IconButton(
                        tooltip: 'Nach oben',
                        onPressed: i == 0
                            ? null
                            : () => refresh(() {
                                final item = order.removeAt(i);
                                order.insert(i - 1, item);
                              }),
                        icon: const Icon(Icons.keyboard_arrow_up),
                      ),
                      IconButton(
                        tooltip: 'Nach unten',
                        onPressed: i == order.length - 1
                            ? null
                            : () => refresh(() {
                                final item = order.removeAt(i);
                                order.insert(i + 1, item);
                              }),
                        icon: const Icon(Icons.keyboard_arrow_down),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    if (save != true || !mounted) return;
    widget.store.db.transaction(() {
      archive.set('dashboardOrder', order.join(','));
      archive.set('dashboardHidden', off.join(','));
    });
    setState(() {
      layout = order;
      hidden = off;
    });
  }

  Future<void> connect() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            GarminConnectScreen(archive: archive, name: widget.name),
      ),
    );
    if (mounted) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.day, first = now.weekStart.addDays(weekOffset * 7);
    final last = first.addDays(6), until = first.addDays(7);
    final sessions = trainingSessions(
      widget.store.storage.loadNormalizedSessions(
        widget.athlete,
        fromUtcUs: DateTime(
          first.year,
          first.month,
          first.day,
        ).microsecondsSinceEpoch,
        toUtcUs:
            DateTime(
              until.year,
              until.month,
              until.day,
            ).microsecondsSinceEpoch -
            1,
        limit: null,
      ),
    );
    final workouts = widget.store.plans
        .planOf(widget.athlete, from: first, to: last)
        .workouts
        .where((w) => w.status != PlannedWorkoutStatus.skipped)
        .toList();
    final goal = TrainingGoal.primary(
      widget.store.goals
          .goalsOf(widget.athlete)
          .where((g) => g.day == null || !g.day!.isBefore(now)),
      now,
    );
    final vm = TodayViewModel.fromDecision(
      decision: widget.today.decision,
      state: widget.today.state,
      availability: widget.today.availability,
      athleteName: widget.name,
    );
    final actual = [
      for (int i = 0; i < 7; i++)
        sessions
            .where(
              (s) => CalendarDay.ofUtcUs(s.startedAtUtcUs) == first.addDays(i),
            )
            .fold(0, (sum, s) => sum + s.movingTimeSeconds),
    ];
    final plan = [
      for (int i = 0; i < 7; i++)
        workouts
            .where((w) => w.day == first.addDays(i))
            .fold(0, (sum, w) => sum + w.durationSeconds),
    ];
    final dayWorkouts = workouts.where((w) => w.day == selected);
    final daySessions = sessions.where(
      (s) => CalendarDay.ofUtcUs(s.startedAtUtcUs) == selected,
    );
    final yMax = math.max(1, [...actual, ...plan].reduce(math.max));
    final weekly = Container(
      decoration: _surface(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Trainingswoche', style: _type(23, spacing: -.7)),
              ),
              IconButton(
                tooltip: 'Vorherige Woche',
                onPressed: () => setState(() {
                  weekOffset--;
                  selected = selected.addDays(-7);
                }),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Nächste Woche',
                onPressed: () => setState(() {
                  weekOffset++;
                  selected = selected.addDays(7);
                }),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Text(
            '${_date(first)} – ${_date(last)} ${last.year}',
            style: _type(13, color: _muted, weight: FontWeight.w500),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              _legend(
                _green,
                'Absolviert · ${_duration(actual.reduce((a, b) => a + b))}',
              ),
              _legend(
                const Color(0xffb0c1b7),
                'Geplant · ${_duration(plan.reduce((a, b) => a + b))}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: selected == first.addDays(i),
                    label:
                        '${_weekdays[i]}, ${_date(first.addDays(i))}, ${_duration(actual[i])} absolviert, ${_duration(plan[i])} geplant',
                    child: ExcludeSemantics(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(9),
                        onTap: () =>
                            setState(() => selected = first.addDays(i)),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: selected == first.addDays(i)
                                ? const Color(0xffeaf0e7)
                                : null,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 62,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _bar(actual[i], yMax, _green),
                                    const SizedBox(width: 3),
                                    _bar(
                                      plan[i],
                                      yMax,
                                      const Color(0xffb0c1b7),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                _weekdays[i],
                                style: _type(
                                  12,
                                  color: selected == first.addDays(i)
                                      ? _ink
                                      : _muted,
                                ),
                              ),
                              Text(
                                '${first.addDays(i).day}',
                                style: _type(
                                  12,
                                  color: _muted,
                                  weight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 24),
          _label(
            '${_weekdays[(DateTime(selected.year, selected.month, selected.day).weekday) - 1]} · ${_date(selected)}'
                .toUpperCase(),
          ),
          const SizedBox(height: 6),
          if (dayWorkouts.isEmpty && daySessions.isEmpty)
            Text(
              selected == now
                  ? 'Kein fester Planeintrag. Heute empfiehlt dein Coach: ${vm.heroTitle}.'
                  : 'Keine Einheit eingetragen.',
              style: _type(14, color: _muted, weight: FontWeight.w400),
            ),
          for (final w in dayWorkouts)
            Text('${w.goal} · ${_duration(w.durationSeconds)} (Plan)'),
          for (final s in daySessions)
            Text('${s.title} · ${_duration(s.movingTimeSeconds)} (absolviert)'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: widget.onPlan,
                icon: const Icon(Icons.calendar_view_week, size: 16),
                label: const Text('Zum Plan'),
              ),
              TextButton.icon(
                onPressed: selected.isBefore(now)
                    ? null
                    : () => widget.onSchedule(selected),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Einheit planen'),
              ),
            ],
          ),
        ],
      ),
    );
    final goalDay = goal?.day;
    final goalCard = DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff123b3c),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: CustomPaint(
          painter: const _Contour(),
          child: Container(
            constraints: const BoxConstraints(minHeight: 218),
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    const Icon(Icons.flag_outlined, color: _lime),
                    const SizedBox(width: 9),
                    Expanded(child: _label('SAISONZIEL', color: _lime)),
                  ],
                ),
                const SizedBox(height: 20),
                if (goalDay != null) ...[
                  Text(
                    '${now.daysUntil(goalDay)}',
                    style: _type(
                      48,
                      color: Colors.white,
                      weight: FontWeight.w700,
                      spacing: -2.5,
                    ),
                  ),
                  Text(
                    now.daysUntil(goalDay) == 1
                        ? 'Tag bis zum Ziel'
                        : 'Tage bis zum Ziel',
                    style: _type(13, color: const Color(0xffc2d5ce)),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  goal?.name ?? 'Dein nächstes Ziel',
                  style: _type(23, color: Colors.white, spacing: -.5),
                ),
                const SizedBox(height: 5),
                Text(
                  goal == null
                      ? 'Distanz, Technik und Wettkampftag festlegen.'
                      : [
                          if (goalDay != null) _date(goalDay),
                          goal.modality.label,
                          if (goal.distanceKm != null)
                            '${goal.distanceKm!.toStringAsFixed(goal.distanceKm! % 1 == 0 ? 0 : 1)} km',
                          'Priorität ${goal.priority.name.toUpperCase()}',
                        ].join(' · '),
                  style: _type(
                    14,
                    color: const Color(0xffc2d5ce),
                    weight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: widget.onGoals,
                  style: TextButton.styleFrom(foregroundColor: _lime),
                  icon: const Icon(Icons.arrow_outward, size: 15),
                  label: Text(goal == null ? 'Ziel anlegen' : 'Wettkampfziele'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return ColoredBox(
      color: _paper,
      child: LayoutBuilder(
        builder: (context, box) {
          final pad = box.maxWidth < 550 ? 16.0 : 28.0;
          return ListView(
            padding: EdgeInsets.fromLTRB(pad, 20, pad, 30),
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1300),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _label(
                        '${_weekdays[DateTime(now.year, now.month, now.day).weekday - 1]} · ${_date(now)} ${now.year}'
                            .toUpperCase(),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Trainingsübersicht',
                              style: _type(
                                box.maxWidth < 540 ? 32 : 40,
                                spacing: -1.7,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Übersicht anpassen',
                            onPressed: customize,
                            icon: const Icon(Icons.tune),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (box.maxWidth >= 780)
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 7,
                                child: WorkoutHeader(
                                  workout: vm,
                                  planNote: widget.today.dayNote,
                                  label: 'Training ansehen',
                                  onPressed: widget.onWorkout,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(flex: 4, child: goalCard),
                            ],
                          ),
                        )
                      else ...[
                        WorkoutHeader(
                          workout: vm,
                          planNote: widget.today.dayNote,
                          label: 'Training ansehen',
                          onPressed: widget.onWorkout,
                        ),
                        const SizedBox(height: 12),
                        goalCard,
                      ],
                      const SizedBox(height: 16),
                      for (final panel in layout.where(
                        (name) => !hidden.contains(name),
                      )) ...[
                        switch (panel) {
                          'training' =>
                            box.maxWidth >= 820
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(flex: 6, child: weekly),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        flex: 5,
                                        child: TrainingHistory(
                                          store: widget.store,
                                          athlete: widget.athlete,
                                          week: first,
                                          onWeek: (w) => setState(() {
                                            weekOffset =
                                                now.weekStart.daysUntil(w) ~/ 7;
                                            selected = w;
                                          }),
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      weekly,
                                      const SizedBox(height: 12),
                                      TrainingHistory(
                                        store: widget.store,
                                        athlete: widget.athlete,
                                        week: first,
                                        onWeek: (w) => setState(() {
                                          weekOffset =
                                              now.weekStart.daysUntil(w) ~/ 7;
                                          selected = w;
                                        }),
                                      ),
                                    ],
                                  ),
                          'recovery' => _Recovery(
                            archive: archive,
                            today: now,
                            onConnect: connect,
                          ),
                          _ => GarminTrainingStatus(
                            archive: archive,
                            state: widget.today.state,
                            onConnect: connect,
                          ),
                        },
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bar(int seconds, int max, Color color) => Container(
    width: 7,
    height: seconds == 0 ? 1 : math.max(3, seconds / max * 60),
    decoration: BoxDecoration(
      color: seconds == 0 ? _border : color,
      borderRadius: BorderRadius.circular(3),
    ),
  );
  Widget _legend(Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(text, style: _type(12, color: _muted)),
    ],
  );
}

class _Recovery extends StatefulWidget {
  const _Recovery({
    required this.archive,
    required this.today,
    required this.onConnect,
  });
  final GarminArchive archive;
  final CalendarDay today;
  final VoidCallback onConnect;
  @override
  State<_Recovery> createState() => _RecoveryState();
}

class _RecoveryState extends State<_Recovery> {
  String? selected;
  @override
  Widget build(BuildContext context) {
    final a = widget.archive, dates = a.dates();
    final day = selected != null && dates.contains(selected)
        ? selected!
        : dates.firstOrNull ?? widget.today.key;
    final end = CalendarDay.parse(day);
    final metrics = HealthMeasure.values.where(
      (m) => m != HealthMeasure.cycle || a.cycleEnabled,
    );
    return Container(
      decoration: _surface(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('GARMIN CONNECT'),
          const SizedBox(height: 5),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Erholung & Gesundheit', style: _type(24, spacing: -.7)),
              if (dates.isNotEmpty)
                SizedBox(
                  width: 205,
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: day,
                    items: [
                      for (final d in dates)
                        DropdownMenuItem(
                          value: d,
                          child: Text(
                            '${_date(CalendarDay.parse(d))} ${d.substring(0, 4)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (d) => setState(() => selected = d),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (dates.isEmpty)
            Text(
              'Nach dem ersten Gesundheitsabruf siehst du hier Schlaf, HRV und weitere Messwerte im Wochenverlauf.',
              style: _type(14, color: _muted, weight: FontWeight.w400),
            ),
          const SizedBox(height: 14),
          if (dates.isNotEmpty) ...[
            _label('VERLAUF · LETZTE 7 TAGE'),
            const SizedBox(height: 9),
            LayoutBuilder(
              builder: (ctx, box) {
                final cols = box.maxWidth >= 990
                    ? metrics.length
                    : box.maxWidth >= 670
                    ? 4
                    : box.maxWidth >= 440
                    ? 3
                    : 2;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in metrics)
                      SizedBox(
                        width: (box.maxWidth - 8 * (cols - 1)) / cols,
                        child: HealthTrendTile(
                          metric: m,
                          values: m.series(a, end),
                          end: end,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 5,
            children: [
              OutlinedButton.icon(
                onPressed: widget.onConnect,
                icon: const Icon(Icons.sync, size: 17),
                label: Text(
                  dates.isEmpty && a.setting('lastPushCheck') == null
                      ? 'Garmin verbinden'
                      : 'Garmin-Verbindung',
                ),
              ),
              if (a.undatedKeys().isNotEmpty)
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: const Text('Garmin-Daten ohne Tagesdatum'),
                        ),
                        body: ListView(
                          children: [
                            for (final key in a.undatedKeys())
                              ExpansionTile(
                                title: Text(_seriesName(key)),
                                children: [
                                  _RecordFields(
                                    value: jsonDecode(
                                      a.setting('undated.$key')!,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Weitere Garmin-Daten'),
                ),
              if (dates.isNotEmpty)
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GarminDayDetails(archive: a, day: day),
                    ),
                  ),
                  icon: const Icon(Icons.insights, size: 17),
                  label: const Text('Alle Tagesdaten'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _seriesName(String key) {
  final parts = key.split('.');
  if (parts.length < 3) return garminSeries[key] ?? key;
  final labels = {
    'dailies': 'Tagesübersicht',
    'sleeps': 'Schlaf',
    'hrv': 'Herzfrequenzvariabilität',
    'stressDetails': 'Stress und Body Battery',
    'epochs': 'Aktivitätsintervalle',
    'pulseox': 'Sauerstoffsättigung',
    'activityDetails': 'Aktivitätsdetails',
    'bodyComps': 'Körperzusammensetzung',
    'allDayRespiration': 'Atmung',
  };
  if (parts.first == 'cyclePush') return 'Zyklus · ${parts[1]}';
  return labels[parts[1]] ?? parts[1];
}

class GarminDayDetails extends StatelessWidget {
  const GarminDayDetails({super.key, required this.archive, required this.day});
  final GarminArchive archive;
  final String day;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Garmin-Tagesdaten')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '${_date(CalendarDay.parse(day))} ${day.substring(0, 4)}',
          style: _type(28),
        ),
        const SizedBox(height: 12),
        for (final s in archive.series(day))
          ExpansionTile(
            key: PageStorageKey(s),
            title: Text(_seriesName(s)),
            children: [_RecordFields(value: archive.read(day, s))],
          ),
      ],
    ),
  );
}

/// Keep long time series collapsed and page their rows on demand.
class _RecordFields extends StatefulWidget {
  const _RecordFields({required this.value});
  final dynamic value;
  @override
  State<_RecordFields> createState() => _RecordFieldsState();
}

class _RecordFieldsState extends State<_RecordFields> {
  int limit = 32;
  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final entries = value is Map
        ? value.entries
              .where((e) => e.value != null)
              .map((e) => MapEntry(e.key.toString(), e.value))
        : value is List
        ? value.asMap().entries.map((e) => MapEntry('${e.key + 1}', e.value))
        : null;
    if (entries == null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: SelectableText(value.toString()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in entries.take(limit))
          if (e.value is Map || e.value is List)
            ExpansionTile(
              title: Text(e.key),
              childrenPadding: const EdgeInsets.only(left: 10),
              children: [_RecordFields(value: e.value)],
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SelectableText('${e.key}   ${e.value}'),
            ),
        if (entries.length > limit)
          TextButton(
            onPressed: () => setState(() => limit += 32),
            child: const Text('Weitere Werte anzeigen'),
          ),
      ],
    );
  }
}

class _Contour extends CustomPainter {
  const _Contour();
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = const Color(0x294f948b);
    canvas.save();
    canvas.translate(size.width * 1.04, size.height * .55);
    canvas.rotate(-.5);
    for (var i = 0; i < 12; i++) {
      final r = 22.0 + 14 * i;
      final path = Path();
      for (var step = 0; step <= 90; step++) {
        final t = step * math.pi / 45;
        final shape = 1 + .09 * math.sin(3 * t + .3) + .06 * math.cos(5 * t);
        final x = r * shape * math.cos(t), y = r * .78 * shape * math.sin(t);
        if (step == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path..close(), pen);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Contour oldDelegate) => false;
}
