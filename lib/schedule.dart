import 'package:flutter/material.dart';
import 'package:xc_coach/app/coach_plan_service.dart';
import 'package:xc_coach/database/platform_repository.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'package:xc_coach/intelligence/planning/planning_models.dart';
import 'package:xc_coach/intelligence/planning/workout_catalogue.dart';
import 'coach_store.dart';

class Schedule extends StatefulWidget {
  const Schedule({
    super.key,
    required this.store,
    required this.athlete,
    this.initialDay,
  });
  final CoachStore store;
  final AthleteSummary athlete;
  final CalendarDay? initialDay;
  @override
  State<Schedule> createState() => _ScheduleState();
}

class _ScheduleState extends State<Schedule> {
  late DateTime date = widget.initialDay == null
      ? DateUtils.dateOnly(DateTime.now())
      : DateTime(
          widget.initialDay!.year,
          widget.initialDay!.month,
          widget.initialDay!.day,
        );
  TrainingModality mode = TrainingModality.skiSkating;
  int minutes = 60;
  @override
  Widget build(BuildContext context) {
    final day = CalendarDay.ofLocal(date);
    final templates = workoutCatalogue.where(
      (t) => t.modalities.contains(mode),
    );
    final plans = widget.store.plans.planOf(
      widget.athlete.id,
      from: day,
      to: day,
    );
    final service = CoachPlanService(
      repository: widget.store.plans,
      organizationId: organization,
      userId: owner,
    );
    final options = [for (final t in templates) ?t.build(minutes, mode)];
    return Scaffold(
      appBar: AppBar(title: Text('Einheit für ${widget.athlete.name} planen')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(
            leading: const Icon(Icons.calendar_month),
            title: Text(MaterialLocalizations.of(context).formatFullDate(date)),
            onTap: () async {
              final now = DateTime.now();
              final selected = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateUtils.dateOnly(now),
                lastDate: date.year > now.year + 5
                    ? date
                    : DateTime(now.year + 5, 12, 31),
              );
              if (selected != null && mounted) setState(() => date = selected);
            },
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final m in TrainingModality.values)
                ChoiceChip(
                  label: Text(m.label),
                  selected: m == mode,
                  onSelected: (_) => setState(() => mode = m),
                ),
            ],
          ),
          DropdownButton<int>(
            value: minutes,
            items: [
              for (final m in [30, 45, 60, 90, 120, 180, 240])
                DropdownMenuItem(value: m, child: Text('Zeitfenster: $m min')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => minutes = v);
            },
          ),
          for (final w in plans.workouts.where((w) => w.isOpen))
            ListTile(
              title: Text(w.goal),
              subtitle: Text('Geplant · ${w.durationSeconds ~/ 60} min'),
              trailing: TextButton(
                onPressed: w.isStarted
                    ? null
                    : () {
                        service.skip(w);
                        setState(() {});
                      },
                child: const Text('Auslassen'),
              ),
            ),
          const Divider(),
          if (options.isEmpty)
            const Text(
              'Für dieses Zeitfenster gibt es keine passende Vorlage.',
            ),
          for (final workout in options)
            ListTile(
              title: Text(workout.name),
              subtitle: Text(
                '${workout.duration.inMinutes} min · ${workout.purpose}',
              ),
              trailing: const Icon(Icons.add),
              onTap: () {
                service.planBlueprint(
                  athleteId: widget.athlete.id,
                  day: day,
                  sport: mode.sportKey,
                  blueprint: workout,
                );
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }
}
