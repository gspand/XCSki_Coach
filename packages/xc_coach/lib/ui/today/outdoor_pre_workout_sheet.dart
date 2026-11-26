/// Pre-Workout Übersicht für Outdoor-Einheiten (Skating, Classic, Lauf, Rad).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Bereitet den Athleten auf das Außentraining vor.
/// - Zeigt Struktur, Talk-Test-Cues, Pacing und Geländeleitplanken.
library;

import 'package:flutter/material.dart';

import '../design_system.dart';
import 'today_view_model.dart';

class OutdoorPreWorkoutSheet extends StatelessWidget {
  const OutdoorPreWorkoutSheet({
    super.key,
    required this.viewModel,
    this.onStartConfirmed,
  });

  final TodayViewModel viewModel;
  final VoidCallback? onStartConfirmed;

  static Future<void> show({
    required BuildContext context,
    required TodayViewModel viewModel,
    VoidCallback? onStartConfirmed,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OutdoorPreWorkoutSheet(
        viewModel: viewModel,
        onStartConfirmed: onStartConfirmed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final vm = viewModel;

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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: GiuliaTokens.accentSoft,
                      borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
                    ),
                    child: Text(
                      vm.modalityLabel.toUpperCase(),
                      style: text.labelSmall?.copyWith(
                        color: GiuliaTokens.accent,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${vm.durationMinutes} MIN',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: GiuliaTokens.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: GiuliaTokens.spacingS),
              Text(
                vm.heroTitle,
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: GiuliaTokens.textPrimary,
                ),
              ),
              const SizedBox(height: GiuliaTokens.spacingXs),
              Text(
                vm.qualitativeIntensity.label,
                style: text.bodyMedium?.copyWith(
                  color: GiuliaTokens.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: GiuliaTokens.spacingL),

              // Struktur
              _InfoCard(
                title: 'STRUKTUR',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vm.phases.summaryText,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: GiuliaTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      vm.structureText,
                      style: text.bodySmall?.copyWith(color: GiuliaTokens.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: GiuliaTokens.spacingM),

              // Intensität & Atmung
              _InfoCard(
                title: 'INTENSITÄT & SPRECHTEST',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vm.talkTestCue,
                      style: text.bodyMedium?.copyWith(color: GiuliaTokens.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Gefühlte Anstrengung: ${vm.effortGuidance}',
                      style: text.bodySmall?.copyWith(
                        color: GiuliaTokens.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (vm.secondaryIntensityCue != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Orientierungsbereich: ${vm.secondaryIntensityCue}',
                        style: text.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: GiuliaTokens.spacingM),

              // Gelände
              if (vm.terrainGuidance != null) ...[
                _InfoCard(
                  title: 'GELÄNDE-HINWEIS',
                  child: Text(
                    vm.terrainGuidance!,
                    style: text.bodyMedium?.copyWith(color: GiuliaTokens.textPrimary),
                  ),
                ),
                const SizedBox(height: GiuliaTokens.spacingM),
              ],

              // Externe Aufzeichnung (Garmin/Watch)
              _InfoCard(
                title: 'AUFZEICHNUNG',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.watch_outlined,
                      size: 20,
                      color: GiuliaTokens.accent,
                    ),
                    const SizedBox(width: GiuliaTokens.spacingS),
                    Expanded(
                      child: Text(
                        'Zeichne die Einheit wie gewohnt mit deiner Sportuhr auf. GIULIA analysiert sie nach der Synchronisierung.',
                        style: text.bodyMedium?.copyWith(
                          color: GiuliaTokens.textPrimary,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
                    borderRadius: BorderRadius.circular(GiuliaTokens.radiusButton),
                  ),
                ),
                child: const Text('BEREIT'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.child});

  final String title;
  final Widget child;

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
            title,
            style: text.labelSmall?.copyWith(
              color: GiuliaTokens.textMuted,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          child,
        ],
      ),
    );
  }
}
