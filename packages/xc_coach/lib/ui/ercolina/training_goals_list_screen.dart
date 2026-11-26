/// Verwaltung aller Trainingsziele eines Athleten (A-, B-, C-Rennen & Zwischenziele).
library;

import 'package:flutter/material.dart';

import '../../database/training_goal_repository.dart';
import '../../domain/training_plan.dart';
import '../../intelligence/planning/planning_models.dart';
import '../../intelligence/training_need/goal_feasibility.dart';
import '../../intelligence/xc_athlete_state/diagnostics_state.dart';
import '../design_system.dart';
import 'training_goal_screen.dart';

class TrainingGoalsListScreen extends StatefulWidget {
  const TrainingGoalsListScreen({
    super.key,
    required this.athleteId,
    required this.organizationId,
    required this.goalRepository,
    this.today,
    this.diagnostics,
    this.onGoalsChanged,
  });

  final String athleteId;
  final String organizationId;
  final SqliteTrainingGoalRepository goalRepository;
  final CalendarDay? today;
  final DiagnosticsState? diagnostics;
  final VoidCallback? onGoalsChanged;

  @override
  State<TrainingGoalsListScreen> createState() => _TrainingGoalsListScreenState();
}

class _TrainingGoalsListScreenState extends State<TrainingGoalsListScreen> {
  late List<TrainingGoal> _goals;
  late WeeklyAvailability? _availability;
  late CalendarDay _today;

  @override
  void initState() {
    super.initState();
    _today = widget.today ?? CalendarDay.ofLocal(DateTime.now());
    _load();
  }

  void _load() {
    _goals = widget.goalRepository.goalsOf(widget.athleteId);
    _availability = widget.goalRepository.availabilityOf(widget.athleteId);
  }

  Future<void> _openGoalEditor({TrainingGoal? goal}) async {
    final res = await Navigator.of(context).push<TrainingGoalResult>(
      MaterialPageRoute(
        builder: (_) => TrainingGoalScreen(
          goal: goal,
          availability: _availability,
          today: _today,
          diagnostics: widget.diagnostics,
        ),
      ),
    );
    if (res != null) {
      final nowUs = DateTime.now().toUtc().microsecondsSinceEpoch;
      widget.goalRepository.database.transaction(() {
      widget.goalRepository.saveGoal(
        res.goal,
        id: res.goal.id ?? 'goal-$nowUs',
        organizationId: widget.organizationId,
        athleteId: widget.athleteId,
        nowUtcUs: nowUs,
      );
      widget.goalRepository.saveAvailability(
        res.availability,
        organizationId: widget.organizationId,
        athleteId: widget.athleteId,
        nowUtcUs: nowUs,
      );
      });
      setState(_load);
      widget.onGoalsChanged?.call();
    }
  }

  Future<void> _archiveGoal(TrainingGoal goal) async {
    if (goal.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ziel archivieren?'),
        content: Text('Möchtest du "${goal.name}" wirklich aus deinen Zielen entfernen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: GiuliaTokens.error),
            child: const Text('Archivieren'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final nowUs = DateTime.now().toUtc().microsecondsSinceEpoch;
      widget.goalRepository.archiveGoal(goal.id!, nowUtcUs: nowUs);
      setState(_load);
      widget.onGoalsChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final primaryGoal = TrainingGoal.primary(_goals, _today);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trainingsziele'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(GiuliaTokens.spacingL),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Deine Saisonziele', style: text.titleLarge),
                    const SizedBox(height: GiuliaTokens.spacingXs),
                    Text(
                      'GIULIA periodisiert dein Training auf dein Hauptziel (A-Rennen) aus '
                      'und berücksichtigt Zwischenwettkämpfe (B & C).',
                      style: text.bodySmall?.copyWith(color: GiuliaTokens.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          FilledButton.icon(
            key: const Key('add-goal-btn'),
            onPressed: () => _openGoalEditor(),
            icon: const Icon(Icons.add),
            label: const Text('Weiteres Ziel hinzufügen'),
          ),
          const SizedBox(height: GiuliaTokens.spacingL),
          if (_goals.isEmpty)
            GiuliaPanel(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: GiuliaTokens.spacingL),
                child: Column(
                  children: [
                    Icon(Icons.flag_outlined, size: 48, color: GiuliaTokens.textSecondary),
                    const SizedBox(height: GiuliaTokens.spacingM),
                    Text('Noch keine Ziele hinterlegt', style: text.titleMedium),
                    const SizedBox(height: GiuliaTokens.spacingXs),
                    Text(
                      'Hinterlege dein erstes Wettkampf- oder Saisonziel.',
                      style: text.bodySmall?.copyWith(color: GiuliaTokens.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else ...[
            for (final goal in _goals)
              _GoalCard(
                goal: goal,
                isPrimary: goal == primaryGoal,
                today: _today,
                diagnostics: widget.diagnostics,
                onTap: () => _openGoalEditor(goal: goal),
                onArchive: () => _archiveGoal(goal),
              ),
          ],
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.isPrimary,
    required this.today,
    this.diagnostics,
    required this.onTap,
    required this.onArchive,
  });

  final TrainingGoal goal;
  final bool isPrimary;
  final CalendarDay today;
  final DiagnosticsState? diagnostics;
  final VoidCallback onTap;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final day = goal.day;
    final daysUntil = day?.daysUntil(today);

    final priorityLabel = switch (goal.priority) {
      GoalPriority.a => 'A · Hauptziel',
      GoalPriority.b => 'B · Vorbereitung',
      GoalPriority.c => 'C · Trainingsrennen',
    };

    final priorityColor = switch (goal.priority) {
      GoalPriority.a => GiuliaTokens.accent,
      GoalPriority.b => Colors.amber,
      GoalPriority.c => GiuliaTokens.textSecondary,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: GiuliaTokens.spacingM),
      child: GiuliaPanel(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(GiuliaTokens.radiusM),
          child: Padding(
            padding: const EdgeInsets.all(GiuliaTokens.spacingM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: GiuliaTokens.spacingS,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: priorityColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
                        border: Border.all(color: priorityColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        priorityLabel,
                        style: text.labelSmall?.copyWith(
                          color: priorityColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (isPrimary) ...[
                      const SizedBox(width: GiuliaTokens.spacingS),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GiuliaTokens.spacingS,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: GiuliaTokens.accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
                        ),
                        child: Text(
                          'AKTIV IM COACH',
                          style: text.labelSmall?.copyWith(
                            color: GiuliaTokens.accent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: GiuliaTokens.textSecondary,
                      tooltip: 'Archivieren',
                      onPressed: onArchive,
                    ),
                  ],
                ),
                const SizedBox(height: GiuliaTokens.spacingS),
                Text(goal.name, style: text.titleMedium),
                const SizedBox(height: GiuliaTokens.spacingXs),
                Wrap(
                  spacing: GiuliaTokens.spacingM,
                  runSpacing: 4,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sports_score, size: 16, color: GiuliaTokens.textSecondary),
                        const SizedBox(width: 4),
                        Text(goal.modality.label, style: text.bodySmall),
                      ],
                    ),
                    if (goal.distanceKm != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.straighten, size: 16, color: GiuliaTokens.textSecondary),
                          const SizedBox(width: 4),
                          Text('${goal.distanceKm!.toStringAsFixed(0)} km', style: text.bodySmall),
                        ],
                      ),
                    if (day != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.event, size: 16, color: GiuliaTokens.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            '${day.day}.${day.month}.${day.year}'
                            '${daysUntil != null ? " (in ${daysUntil.abs()} Tagen)" : ""}',
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                  ],
                ),
                if (goal.targetSeconds != null) ...[
                  const SizedBox(height: GiuliaTokens.spacingXs),
                  Text(
                    'Zielzeit: ${goal.targetSeconds! ~/ 3600}:${((goal.targetSeconds! % 3600) ~/ 60).toString().padLeft(2, '0')}:00',
                    style: text.bodySmall?.copyWith(color: GiuliaTokens.textSecondary),
                  ),
                ],
                Builder(
                  builder: (context) {
                    final verdict = GoalFeasibilityEngine().evaluateGoal(
                      goal: goal,
                      diagnostics: diagnostics,
                      now: DateTime(today.year, today.month, today.day),
                    );
                    if (verdict.isAchievable && verdict.status != FeasibilityStatus.ambitious) {
                      return const SizedBox.shrink();
                    }
                    final isImpossible = verdict.status == FeasibilityStatus.infeasible;
                    final badgeColor = isImpossible ? GiuliaTokens.error : Colors.amber;
                    final badgeLabel = isImpossible
                        ? 'Physiologisch nicht erreichbar'
                        : 'Sehr ambitioniert / riskant';

                    return Container(
                      margin: const EdgeInsets.only(top: GiuliaTokens.spacingS),
                      padding: const EdgeInsets.symmetric(
                        horizontal: GiuliaTokens.spacingM,
                        vertical: GiuliaTokens.spacingS,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
                        border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isImpossible ? Icons.cancel_outlined : Icons.warning_amber_rounded,
                            size: 18,
                            color: badgeColor,
                          ),
                          const SizedBox(width: GiuliaTokens.spacingS),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  badgeLabel,
                                  style: text.labelSmall?.copyWith(
                                    color: badgeColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  verdict.reasoning,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodySmall?.copyWith(
                                    color: GiuliaTokens.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
