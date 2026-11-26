/// Was du gleich machst — vor dem Start, nicht während.
///
/// Für Ercolina-Einheiten gab es diese Ansicht nicht: Ein Tippen auf HEUTE
/// startete sofort. Der Athlet erfuhr den Ablauf erst, als er schon zog. Für
/// Außeneinheiten gab es sie längst ([OutdoorPreWorkoutSheet]) — die
/// Asymmetrie war keine Entscheidung, sondern eine Lücke.
library;

import 'package:flutter/material.dart';

import '../../app/mirco_preview.dart';
import '../../workout_engine/blueprint_outline.dart';
import '../../workout_engine/workout_engine.dart';
import '../../workout_engine/workout_library.dart';
import '../design_system.dart';
import 'workout_preview_labels.dart';

class ErcolinaPreWorkoutSheet extends StatelessWidget {
  const ErcolinaPreWorkoutSheet({
    super.key,
    required this.blueprint,
    this.prescribedMinutes,
    this.coachingReason,
    this.onStartConfirmed,
  });

  /// Die Einheit, die wirklich startet. Nicht eine Beschreibung davon.
  final WorkoutBlueprint blueprint;

  /// Was der Coach verschrieben hat. Weicht sie von [WorkoutBlueprint.duration]
  /// ab, ist das ein Fehler und wird gezeigt, nicht versteckt.
  final int? prescribedMinutes;

  final String? coachingReason;
  final VoidCallback? onStartConfirmed;

  static Future<void> show({
    required BuildContext context,
    required WorkoutBlueprint blueprint,
    int? prescribedMinutes,
    String? coachingReason,
    VoidCallback? onStartConfirmed,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ErcolinaPreWorkoutSheet(
        blueprint: blueprint,
        prescribedMinutes: prescribedMinutes,
        coachingReason: coachingReason,
        onStartConfirmed: onStartConfirmed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final minutes = (blueprint.duration.inSeconds / 60).round();
    final groups = outlineOf(blueprint.steps);
    final mismatch = prescribedMinutes != null && prescribedMinutes != minutes;

    return Container(
      decoration: const BoxDecoration(
        color: GiuliaTokens.surface1,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: GiuliaTokens.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: GiuliaTokens.accentSoft,
                      borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
                    ),
                    child: Text(
                      blueprint.category.label.toUpperCase(),
                      style: text.labelSmall?.copyWith(
                        color: GiuliaTokens.accent,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$minutes min',
                    style: text.titleMedium?.copyWith(
                      color: GiuliaTokens.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: GiuliaTokens.spacingS),
              Text(
                blueprint.name,
                style: text.headlineSmall?.copyWith(
                  color: GiuliaTokens.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: GiuliaTokens.spacingXs),
              Text(
                blueprint.purpose,
                style: text.bodyMedium?.copyWith(
                  color: GiuliaTokens.textSecondary,
                  height: 1.35,
                ),
              ),
              if (mismatch) ...[
                const SizedBox(height: GiuliaTokens.spacingM),
                Container(
                  padding: const EdgeInsets.all(GiuliaTokens.spacingS),
                  decoration: BoxDecoration(
                    color: GiuliaTokens.surface3,
                    borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
                  ),
                  child: Text(
                    'Verschrieben waren $prescribedMinutes min, diese Einheit '
                    'dauert $minutes min.',
                    style: text.bodySmall?.copyWith(
                      color: GiuliaTokens.textPrimary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: GiuliaTokens.spacingL),
              WorkoutOutline(groups: groups),
              if (coachingReason != null && coachingReason!.isNotEmpty) ...[
                const SizedBox(height: GiuliaTokens.spacingL),
                Text(
                  'WARUM HEUTE',
                  style: text.labelSmall?.copyWith(
                    color: GiuliaTokens.textMuted,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: GiuliaTokens.spacingXs),
                Text(
                  coachingReason!,
                  style: text.bodySmall?.copyWith(
                    color: GiuliaTokens.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: GiuliaTokens.spacingL),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onStartConfirmed?.call();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: GiuliaTokens.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      GiuliaTokens.radiusButton,
                    ),
                  ),
                ),
                child: const Text('TRAINING STARTEN'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WorkoutOutline extends StatelessWidget {
  const WorkoutOutline({
    super.key,
    required this.groups,
    this.thresholdWatt,
    this.translateLibraryNotes = false,
  });

  final double? thresholdWatt;
  final bool translateLibraryNotes;
  String _note(String note) =>
      translateLibraryNotes ? previewLibraryNote(note) : note;

  final List<BlueprintOutlineGroup> groups;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(GiuliaTokens.spacingM),
      decoration: BoxDecoration(
        color: GiuliaTokens.surface0,
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusM),
        border: Border.all(color: GiuliaTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            previewText('ABLAUF', 'STRUCTURE'),
            style: text.labelSmall?.copyWith(
              color: GiuliaTokens.textMuted,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      group.repeats > 1 ? '${group.repeats} ×' : '',
                      style: text.bodyMedium?.copyWith(
                        color: GiuliaTokens.accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final step in group.steps)
                          Text(
                            _lineOf(step),
                            style: text.bodyMedium?.copyWith(
                              color: GiuliaTokens.textPrimary,
                            ),
                          ),
                        if (group.hasVaryingNotes)
                          Material(
                            color: Colors.transparent,
                            child: ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                previewText(
                                  'Hinweise je Wiederholung',
                                  'Notes by repetition',
                                ),
                                style: text.bodySmall,
                              ),
                              children: [
                                for (final (index, step)
                                    in group.originalSteps.indexed)
                                  if (step.note != null)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '${index ~/ group.steps.length + 1}. ${_note(step.note!)}',
                                        style: text.bodySmall?.copyWith(
                                          color: GiuliaTokens.textSecondary,
                                        ),
                                      ),
                                    ),
                              ],
                            ),
                          )
                        else
                          for (final note in {
                            for (final step in group.steps)
                              if (step.note != null) step.note!,
                          })
                            Text(
                              _note(note),
                              style: text.bodySmall?.copyWith(
                                color: GiuliaTokens.textMuted,
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// «30 s Belastung · VO2max 106–120 %».
  String _lineOf(BlueprintStep step) {
    final duration = switch (step.completionType) {
      CompletionType.duration => formatStepDuration(step.seconds),
      CompletionType.strokes =>
        '${formatWorkoutValue(step.target)} '
            '${previewText('Züge', 'strokes')}',
      CompletionType.work ||
      CompletionType.energy => '${formatWorkoutValue(step.target / 1000)} kJ',
    };
    final relative = step.relativePowerRange;
    final power = switch (step.powerTargetMode) {
      PowerTargetMode.fixedWatts => '${formatWorkoutRange(step.fixedWatts!)} W',
      PowerTargetMode.none => previewText(
        'ohne Leistungsziel',
        'no power target',
      ),
      PowerTargetMode.preset || PowerTargetMode.percentOfThreshold =>
        '${step.powerTargetMode == PowerTargetMode.preset ? '${previewWorkoutIntensity(step.intensity)} ' : ''}'
            '${formatWorkoutRange(MetricRange(relative!.minimum * 100, relative.maximum * 100))} %',
    };
    final rate = step.strokeRate == null
        ? ''
        : ' · ${step.strokeRate!.minimum.round()}–'
              '${step.strokeRate!.maximum.round()} ${previewText('Züge/min', 'strokes/min')}';
    final heartRate = step.heartRate == null
        ? ''
        : ' · ${step.heartRate!.minimum.round()}–${step.heartRate!.maximum.round()} bpm';
    final watts = step.powerTargetMode == PowerTargetMode.fixedWatts
        ? null
        : step.resolvedPowerWatt(thresholdWatt);
    final wattLabel = watts == null ? '' : ' · ${formatWorkoutRange(watts)} W';
    return '$duration ${previewWorkoutStepKind(step.kind)} · '
        '$power$wattLabel$rate$heartRate';
  }
}
