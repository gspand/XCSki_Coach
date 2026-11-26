/// Ziel und Trainingszeiten: das Einzige, was der Athlet GIULIA sagen muss.
///
/// Die Zeiten sind Grenzen, keine Vorgaben: «Dienstag 60 min Ercolina
/// möglich» heisst nicht, dass am Dienstag Ercolina trainiert wird.
library;

import 'package:flutter/material.dart';

import '../../domain/training_plan.dart';
import '../../intelligence/planning/planning_models.dart';
import '../../intelligence/training_need/goal_feasibility.dart';
import '../../intelligence/xc_athlete_state/diagnostics_state.dart';
import '../design_system.dart';

class TrainingGoalResult {
  const TrainingGoalResult({required this.goal, required this.availability});

  final TrainingGoal goal;
  final WeeklyAvailability availability;
}

class TrainingGoalScreen extends StatefulWidget {
  const TrainingGoalScreen({
    super.key,
    this.goal,
    this.availability,
    this.today,
    this.diagnostics,
  });

  final TrainingGoal? goal;
  final WeeklyAvailability? availability;
  final CalendarDay? today;
  final DiagnosticsState? diagnostics;

  @override
  State<TrainingGoalScreen> createState() => _TrainingGoalScreenState();
}

const _weekdays = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];
const _minuteChoices = [0, 30, 45, 60, 75, 90, 120, 150, 180, 240, 300];

class _TrainingGoalScreenState extends State<TrainingGoalScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.goal?.name ?? '',
  );
  late final TextEditingController _distance = TextEditingController(
    text: widget.goal?.distanceKm == null
        ? ''
        : _number(widget.goal!.distanceKm!),
  );
  late final TextEditingController _time = TextEditingController(
    text: widget.goal?.targetSeconds == null
        ? ''
        : _clock(widget.goal!.targetSeconds!),
  );
  late GoalKind _kind = widget.goal?.kind ?? GoalKind.race;
  late GoalPriority _priority = widget.goal?.priority ?? GoalPriority.a;
  late TrainingModality _modality =
      widget.goal?.modality ?? TrainingModality.skiSkating;
  late CalendarDay? _day = widget.goal?.day;
  late final List<WeekdayAvailability> _days = [
    for (var weekday = 1; weekday <= 7; weekday++)
      widget.availability?.weekday(weekday) ?? WeekdayAvailability(weekday:weekday,minutes:60,modalities:const {TrainingModality.skiClassic,TrainingModality.skiSkating}),
  ];
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _distance.dispose();
    _time.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Gib dem Ziel einen Namen.');
      return;
    }
    if (_kind == GoalKind.race && _day == null) {
      setState(() => _error = 'Ein Wettkampf braucht ein Datum.');
      return;
    }
    final seconds = _parseClock(_time.text);
    if (_time.text.trim().isNotEmpty && seconds == null) {
      setState(() => _error = 'Zielzeit bitte als h:mm:ss, z. B. 2:15:00.');
      return;
    }
    Navigator.of(context).pop(
      TrainingGoalResult(
        goal: TrainingGoal(
          id: widget.goal?.id,
          name: name,
          kind: _kind,
          priority: _priority,
          day: _kind == GoalKind.race ? _day : null,
          modality: _modality,
          distanceKm: double.tryParse(_distance.text.replaceAll(',', '.')),
          targetSeconds: seconds,
        ),
        availability: WeeklyAvailability(List.of(_days)),
      ),
    );
  }

  GoalFeasibilityVerdict? _checkFeasibility() {
    final dist = double.tryParse(_distance.text.replaceAll(',', '.'));
    final seconds = _parseClock(_time.text);
    if (dist == null || dist <= 0 || seconds == null || seconds <= 0) return null;
    return const GoalFeasibilityEngine().evaluate(
      modality: _modality,
      distanceKm: dist,
      targetSeconds: seconds,
      diagnostics: widget.diagnostics,
    );
  }

  Widget _buildFeasibilityCard(BuildContext context, GoalFeasibilityVerdict verdict) {
    final isIssue = verdict.status.isIssue;
    final color = switch (verdict.status) {
      FeasibilityStatus.realistic => GiuliaTokens.success,
      FeasibilityStatus.ambitious => GiuliaTokens.warning,
      FeasibilityStatus.unrealistic => GiuliaTokens.warning,
      FeasibilityStatus.infeasible => GiuliaTokens.error,
    };
    final icon = switch (verdict.status) {
      FeasibilityStatus.realistic => Icons.check_circle_outline,
      FeasibilityStatus.ambitious => Icons.trending_up,
      FeasibilityStatus.unrealistic => Icons.warning_amber_rounded,
      FeasibilityStatus.infeasible => Icons.dangerous_outlined,
    };

    return Card(
      color: color.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    verdict.headline,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    verdict.targetPaceMinPerKm != null
                        ? '${verdict.targetPaceMinPerKm} min/km'
                        : '${verdict.targetSpeedKmh.toStringAsFixed(1)} km/h',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              verdict.reasoning,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: GiuliaTokens.textPrimary,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final today = widget.today ?? CalendarDay.ofLocal(DateTime.now());
    final initial = _day ?? today.addDays(90);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 3),
    );
    if (picked != null) setState(() => _day = CalendarDay.ofLocal(picked));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ziel & Trainingszeiten'),
        actions: [
          TextButton(
            key: const Key('goal-save'),
            onPressed: _save,
            child: const Text('Speichern'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(GiuliaTokens.spacingL),
        children: [
          Text('Dein Ziel', style: text.titleLarge),
          const SizedBox(height: GiuliaTokens.spacingM),
          SegmentedButton<GoalKind>(
            segments: [
              for (final kind in GoalKind.values)
                ButtonSegment(value: kind, label: Text(kind.label)),
            ],
            selected: {_kind},
            onSelectionChanged: (value) => setState(() => _kind = value.first),
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          TextField(
            key: const Key('goal-name'),
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'z. B. 50 km Skating',
            ),
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          DropdownButtonFormField<TrainingModality>(
            initialValue: _modality,
            decoration: const InputDecoration(labelText: 'Sportart'),
            items: [
              for (final modality in {TrainingModality.skiSkating, TrainingModality.skiClassic, _modality})
                DropdownMenuItem(value: modality, child: Text(modality.label)),
            ],
            onChanged: (value) =>
                setState(() => _modality = value ?? _modality),
          ),
          if (_kind == GoalKind.race) ...[
            const SizedBox(height: GiuliaTokens.spacingM),
            OutlinedButton.icon(
              key: const Key('goal-date'),
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _day == null
                    ? 'Datum wählen'
                    : '${_day!.day}.${_day!.month}.${_day!.year}',
              ),
            ),
            const SizedBox(height: GiuliaTokens.spacingM),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('goal-distance'),
                    controller: _distance,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Distanz (km)',
                    ),
                  ),
                ),
                const SizedBox(width: GiuliaTokens.spacingM),
                Expanded(
                  child: TextField(
                    key: const Key('goal-time'),
                    controller: _time,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Zielzeit (h:mm:ss)',
                    ),
                  ),
                ),
              ],
            ),
            if (_checkFeasibility() case final verdict?) ...[
              const SizedBox(height: GiuliaTokens.spacingM),
              _buildFeasibilityCard(context, verdict),
            ],
          ],
          const SizedBox(height: GiuliaTokens.spacingM),
          Text('Priorität', style: text.labelLarge),
          const SizedBox(height: GiuliaTokens.spacingXs),
          SegmentedButton<GoalPriority>(
            segments: const [
              ButtonSegment(
                value: GoalPriority.a,
                label: Text('A · Hauptziel'),
              ),
              ButtonSegment(value: GoalPriority.b, label: Text('B')),
              ButtonSegment(value: GoalPriority.c, label: Text('C')),
            ],
            selected: {_priority},
            onSelectionChanged: (value) =>
                setState(() => _priority = value.first),
          ),
          if (_error != null) ...[
            const SizedBox(height: GiuliaTokens.spacingM),
            Text(
              _error!,
              style: text.bodyMedium?.copyWith(color: GiuliaTokens.error),
            ),
          ],
          const SizedBox(height: GiuliaTokens.spacingXl),
          Text('Wann kannst du trainieren?', style: text.titleLarge),
          const SizedBox(height: GiuliaTokens.spacingXs),
          Text(
            'Das sind Grenzen, keine Vorgaben: GIULIA wählt innerhalb dieser '
            'Zeiten, was dir am meisten bringt – auch einen Ruhetag.',
            style: text.bodyMedium?.copyWith(color: GiuliaTokens.textSecondary),
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          for (final (index, day) in _days.indexed)
            _WeekdayRow(
              key: Key('availability-${day.weekday}'),
              label: _weekdays[index],
              value: day,
              onChanged: (value) => setState(() => _days[index] = value),
            ),
        ],
      ),
    );
  }
}

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final WeekdayAvailability value;
  final ValueChanged<WeekdayAvailability> onChanged;

  WeekdayAvailability _copy({
    int? minutes,
    Set<TrainingModality>? modalities,
    bool? restDay,
    bool? longDay,
  }) => WeekdayAvailability(
    weekday: value.weekday,
    minutes: minutes ?? value.minutes,
    modalities: modalities ?? value.modalities,
    restDay: restDay ?? value.restDay,
    longDay: longDay ?? value.longDay,
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final minutes = _minuteChoices.contains(value.minutes) ? value.minutes : 60;
    return Padding(
      padding: const EdgeInsets.only(bottom: GiuliaTokens.spacingM),
      child: GiuliaPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: text.titleMedium)),
                Text('kein Training', style: text.bodySmall),
                Switch(
                  value: value.restDay,
                  onChanged: (rest) => onChanged(_copy(restDay: rest)),
                ),
              ],
            ),
            if (!value.restDay) ...[
              Row(
                children: [
                  Text('bis', style: text.bodyMedium),
                  const SizedBox(width: GiuliaTokens.spacingS),
                  DropdownButton<int>(
                    value: minutes,
                    items: [
                      for (final choice in _minuteChoices)
                        DropdownMenuItem(
                          value: choice,
                          child: Text('$choice min'),
                        ),
                    ],
                    onChanged: (choice) =>
                        onChanged(_copy(minutes: choice ?? minutes)),
                  ),
                  const Spacer(),
                  Text('langer Tag', style: text.bodySmall),
                  Checkbox(
                    value: value.longDay,
                    onChanged: (long) =>
                        onChanged(_copy(longDay: long ?? false)),
                  ),
                ],
              ),
              Wrap(
                spacing: GiuliaTokens.spacingS,
                runSpacing: GiuliaTokens.spacingXs,
                children: [
                  for (final modality in TrainingModality.values)
                    FilterChip(
                      label: Text(modality.label),
                      selected: value.modalities.contains(modality),
                      onSelected: (selected) => onChanged(
                        _copy(
                          modalities: selected
                              ? {...value.modalities, modality}
                              : ({...value.modalities}..remove(modality)),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _number(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';

String _clock(int seconds) =>
    '${seconds ~/ 3600}:${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}'
    ':${(seconds % 60).toString().padLeft(2, '0')}';

int? _parseClock(String text) {
  final parts = text.trim().split(':');
  if (parts.isEmpty || parts.length > 3 || parts.first.isEmpty) return null;
  final values = [for (final part in parts) int.tryParse(part)];
  if (values.any((value) => value == null || value < 0)) return null;
  final padded = [...List.filled(3 - values.length, 0), ...values.cast<int>()];
  return padded[0] * 3600 + padded[1] * 60 + padded[2];
}
