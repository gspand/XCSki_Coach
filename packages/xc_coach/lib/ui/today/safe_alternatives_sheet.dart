/// Ebene 3 – «Heute anders trainieren?» Bottom Sheet.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE & ARCHITEKTONISCHE LEITPLANKEN:
/// - Die Benutzeroberfläche tauscht NIEMALS eigenmächtig ein Workout aus.
/// - Jede Nutzerpräferenz (z. B. «lieber Rad», «nur 30 min», «drinnen») erzeugt einen
///   [UserOverrideContext] bzw. [DayAvailability] und läuft durch den deterministischen
///   Core neu!
library;

import 'package:flutter/material.dart';

import '../../domain/xc_modality.dart';
import '../../intelligence/workout_selection/user_override_context.dart';
import '../design_system.dart';
import 'today_view_model.dart';

class SafeAlternativesSheet extends StatelessWidget {
  const SafeAlternativesSheet({
    super.key,
    required this.viewModel,
    required this.onApplyOverride,
  });

  final TodayViewModel viewModel;
  final void Function(UserOverrideContext override, int? newAvailableMinutes) onApplyOverride;

  static Future<void> show({
    required BuildContext context,
    required TodayViewModel viewModel,
    required void Function(UserOverrideContext override, int? newAvailableMinutes) onApplyOverride,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeAlternativesSheet(
        viewModel: viewModel,
        onApplyOverride: onApplyOverride,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

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
              // Handle bar
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
              Text(
                'Heute anders trainieren?',
                style: text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: GiuliaTokens.textPrimary,
                ),
              ),
              const SizedBox(height: GiuliaTokens.spacingXs),
              Text(
                'Wähle eine Option. GIULIA prüft die Sicherheit und berechnet die Empfehlung neu.',
                style: text.bodyMedium?.copyWith(color: GiuliaTokens.textSecondary),
              ),
              const SizedBox(height: GiuliaTokens.spacingL),

              // Option 1: Zeitfenster verkürzen
              _AlternativeTile(
                icon: Icons.timer_outlined,
                title: 'Ich habe heute nur wenig Zeit',
                subtitle: 'Kompakte 30–45 Minuten Einheit berechnen',
                onTap: () {
                  Navigator.of(context).pop();
                  onApplyOverride(const UserOverrideContext(), 35);
                },
              ),

              // Option 2: Lieber drinnen / Ercolina
              if (viewModel.modality != XcModality.ercolinaDoublePoling)
                _AlternativeTile(
                  icon: Icons.precision_manufacturing_outlined,
                  title: 'Lieber Ercolina (Indoor)',
                  subtitle: 'Fokus auf Doppelstockzug & Oberkörper',
                  onTap: () {
                    Navigator.of(context).pop();
                    onApplyOverride(
                      const UserOverrideContext(preferredModality: XcModality.ercolinaDoublePoling),
                      null,
                    );
                  },
                ),

              // Option 3: Lieber draußen / Skating
              if (viewModel.modality != XcModality.skiSkating)
                _AlternativeTile(
                  icon: Icons.downhill_skiing_outlined,
                  title: 'Lieber Langlauf Skating (Outdoor)',
                  subtitle: 'Skispezifische Bewegung im Schnee',
                  onTap: () {
                    Navigator.of(context).pop();
                    onApplyOverride(
                      const UserOverrideContext(preferredModality: XcModality.skiSkating),
                      null,
                    );
                  },
                ),

              // Option 4: Ausdauertraining auf dem Rad
              if (viewModel.modality != XcModality.cycling)
                _AlternativeTile(
                  icon: Icons.directions_bike_outlined,
                  title: 'Lieber Rad (Cross-Training)',
                  subtitle: 'Geringere Oberkörperbelastung, rein aerob',
                  onTap: () {
                    Navigator.of(context).pop();
                    onApplyOverride(
                      const UserOverrideContext(preferredModality: XcModality.cycling),
                      null,
                    );
                  },
                ),

              // Option 5: Ruhetag einlegen
              if (!viewModel.isRestDay)
                _AlternativeTile(
                  icon: Icons.hotel_outlined,
                  title: 'Heute vollständiger Ruhetag',
                  subtitle: 'Keine körperliche Belastung · Regeneration',
                  accent: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    onApplyOverride(
                      const UserOverrideContext(forcedRestDay: true),
                      null,
                    );
                  },
                ),

              const SizedBox(height: GiuliaTokens.spacingL),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GiuliaTokens.radiusButton),
                  ),
                ),
                child: const Text('Abbrechen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlternativeTile extends StatelessWidget {
  const _AlternativeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: GiuliaTokens.spacingS),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusM),
        child: Container(
          padding: const EdgeInsets.all(GiuliaTokens.spacingM),
          decoration: BoxDecoration(
            color: GiuliaTokens.surface0,
            borderRadius: BorderRadius.circular(GiuliaTokens.radiusM),
            border: Border.all(color: GiuliaTokens.border),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: GiuliaTokens.iconL,
                color: accent ? GiuliaTokens.warning : GiuliaTokens.accent,
              ),
              const SizedBox(width: GiuliaTokens.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: GiuliaTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(color: GiuliaTokens.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: GiuliaTokens.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
