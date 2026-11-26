import 'package:flutter/material.dart';
import 'package:xc_coach/database/platform_repository.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'package:xc_coach/domain/training_sessions.dart';
import 'package:xc_coach/presentation/decision_card.dart';
import 'coach_store.dart';
import 'schedule.dart';

class MonthPlan extends StatefulWidget {
  const MonthPlan({super.key, required this.store, required this.athlete});
  final CoachStore store;
  final AthleteSummary athlete;
  @override
  State<MonthPlan> createState() => _MonthPlanState();
}

class _MonthPlanState extends State<MonthPlan> {
  CalendarDay selected = CalendarDay.ofLocal(DateTime.now());
  void move(int by) => setState(
    () => selected = CalendarDay.ofLocal(
      DateTime(selected.year, selected.month + by, 1),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final today = CalendarDay.ofLocal(DateTime.now());
    final first = CalendarDay(selected.year, selected.month, 1);
    final firstWeekday = DateTime.utc(first.year, first.month, 1).weekday;
    final end = CalendarDay.ofLocal(
      DateTime(selected.year, selected.month + 1, 0),
    );
    final planned = widget.store.plans
        .planOf(widget.athlete.id, from: first, to: end)
        .workouts;
    final measured = trainingSessions(
      widget.store.storage.loadNormalizedSessions(
        widget.athlete.id,
        fromUtcUs: DateTime(first.year, first.month, 1).microsecondsSinceEpoch,
        toUtcUs:
            DateTime(end.year, end.month + 1, 1).microsecondsSinceEpoch - 1,
        limit: null,
      ),
    );
    final goals = widget.store.goals
        .goalsOf(widget.athlete.id)
        .where(
          (g) =>
              g.day != null && !g.day!.isBefore(first) && !end.isBefore(g.day!),
        );
    final decision = selected == today
        ? widget.store.today.of(widget.athlete.id).decision
        : null;
    final agenda = <Widget>[
      for (final g in goals.where((g) => g.day == selected))
        ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: Text(g.name),
          subtitle: const Text('Wettkampfziel'),
        ),
      if (decision != null)
        ListTile(
          leading: const Icon(Icons.nordic_walking),
          title: Text(decision.displayTitle),
          subtitle: Text(
            'Tagesempfehlung · ${decision.displayMinutes} min\n${decision.decisionId} · ${decision.decisionVersion.substring(0, 10)}',
          ),
        ),
      for (final p in planned.where((p) => p.day == selected))
        ListTile(
          leading: const Icon(Icons.calendar_month_outlined),
          title: Text(p.goal),
          subtitle: Text(
            '${switch (p.status) {
              PlannedWorkoutStatus.planned => 'Geplant',
              PlannedWorkoutStatus.completed => 'Plan erfüllt',
              PlannedWorkoutStatus.modified => 'Angepasst',
              PlannedWorkoutStatus.skipped => 'Ausgelassen',
            }} · ${(p.durationSeconds / 60).round()} min',
          ),
        ),
      for (final s in measured.where(
        (s) => CalendarDay.ofUtcUs(s.startedAtUtcUs) == selected,
      ))
        ListTile(
          leading: const Icon(Icons.done),
          title: Text(s.title),
          subtitle: Text(
            'Absolviert · ${(s.movingTimeSeconds / 60).round()} min · ${s.modality.label}',
          ),
        ),
    ];
    final month = DateTime(selected.year, selected.month, selected.day);
    final strings = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Kalender · ${widget.athlete.name}')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.formatMonthYear(month),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Vorheriger Monat',
                      onPressed: () => move(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      tooltip: 'Nächster Monat',
                      onPressed: () => move(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                Row(
                  children: [
                    for (final w in ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'])
                      Expanded(child: Center(child: Text(w))),
                  ],
                ),
                for (
                  int row = 0;
                  row < (firstWeekday - 1 + end.day + 6) ~/ 7;
                  row++
                )
                  Row(
                    children: [
                      for (int col = 0; col < 7; col++)
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final d = first.addDays(
                                row * 7 + col - (firstWeekday - 1),
                              );
                              if (d.month != first.month)
                                return const SizedBox(height: 52);
                              final hasPlan = planned.any((p) => p.day == d);
                              final hasActivity = measured.any(
                                (s) =>
                                    CalendarDay.ofUtcUs(s.startedAtUtcUs) == d,
                              );
                              final hasGoal = goals.any((g) => g.day == d);
                              return Semantics(
                                button: true,
                                selected: d == selected,
                                label: [
                                  d.key,
                                  if (hasPlan) 'Plan',
                                  if (hasActivity) 'Training',
                                  if (hasGoal) 'Ziel',
                                ].join(', '),
                                child: InkWell(
                                  onTap: () => setState(() => selected = d),
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      minHeight: 52,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: d == selected
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.secondaryContainer
                                          : null,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${d.day}',
                                          style: TextStyle(
                                            fontWeight: d == today
                                                ? FontWeight.bold
                                                : null,
                                          ),
                                        ),
                                        Wrap(
                                          children: [
                                            if (hasGoal)
                                              const Icon(Icons.flag, size: 12),
                                            if (hasPlan)
                                              const Icon(
                                                Icons.event_outlined,
                                                size: 12,
                                              ),
                                            if (hasActivity)
                                              const Icon(Icons.done, size: 12),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.formatFullDate(month)),
                  trailing: selected.isBefore(today)
                      ? null
                      : IconButton(
                          tooltip: 'Einheit planen',
                          icon: const Icon(Icons.add),
                          onPressed: () async {
                            await Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => Schedule(
                                  store: widget.store,
                                  athlete: widget.athlete,
                                  initialDay: selected,
                                ),
                              ),
                            );
                            if (mounted) {
                              widget.store.today.invalidate(widget.athlete.id);
                              setState(() {});
                            }
                          },
                        ),
                ),
                if (agenda.isEmpty)
                  const Text('Für diesen Tag ist kein Training eingetragen.'),
                ...agenda,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
