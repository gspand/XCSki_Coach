import 'package:flutter/material.dart';

import '../../intelligence/load/stimulus_models.dart';
import '../../intelligence/xc_athlete_state/stimulus_history_state.dart';
import '../../intelligence/xc_athlete_state/xc_athlete_state.dart';
import '../design_system.dart';

/// Prominenter Bereich: «Belastung & Erholung» im ATHLET-Tab.
///
/// Basiert ausschließlich auf bestehender wissenschaftlicher Evidence im [XCAthleteState]:
/// - Banister TRIMP EWMA (Akute Last 7d, Chronische Last 42d, LoadBalance)
/// - Datenabdeckung & Konfidenz (Unknown Days Semantik)
/// - Subjektive Rückmeldung heute (Erholung, Schlaf, DOMS Beine/Oberkörper, Symptome)
/// - Letzte relevante Trainingsreize aus [StimulusHistoryState]
///
/// WICHTIG: KEIN künstlicher 0-100 Recovery Score!
class LoadAndRecoverySection extends StatelessWidget {
  const LoadAndRecoverySection({
    super.key,
    required this.athleteState,
  });

  final XCAthleteState athleteState;

  @override
  Widget build(BuildContext context) {
    final trimp = athleteState.trainingLoad.latestBanisterState;
    final subj = athleteState.subjectiveReadiness;
    final cov = athleteState.dataCoverage;
    final stimuli = athleteState.stimulusHistory;
    final asOf = athleteState.asOf;

    final summary = _deriveQualitativeStatus(trimp, subj, cov);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GiuliaSectionHeader(
          title: 'Belastung & Erholung',
          subtitle: 'Kombinierte Evidenz aus Trainingshistorie und heutiger Rückmeldung',
        ),
        const SizedBox(height: GiuliaTokens.spacingS),

        // 1. Qualitative Zusammenfassung (oben)
        GiuliaPanel(
          tone: summary.tone,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(summary.icon, color: summary.color, size: 28),
              const SizedBox(width: GiuliaTokens.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: summary.color,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: GiuliaTokens.spacingXs),
                    Text(
                      summary.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: GiuliaTokens.textPrimary,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: GiuliaTokens.spacingM),

        // 2. Belastungskennzahlen (Acute, Chronic, Balance)
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 600;
            final itemWidth = wide
                ? (constraints.maxWidth - GiuliaTokens.spacingS * 2) / 3
                : constraints.maxWidth;

            return Wrap(
              spacing: GiuliaTokens.spacingS,
              runSpacing: GiuliaTokens.spacingS,
              children: [
                SizedBox(
                  width: itemWidth,
                  child: _LoadMetricCard(
                    title: 'Kurzfristige Last',
                    subtitle: '7-Tage EWMA (akut)',
                    value: trimp != null
                        ? trimp.acuteLoad.toStringAsFixed(1)
                        : '—',
                    unit: 'TRIMP',
                    detail: trimp != null
                        ? 'Aktuelle Ermüdungskomponente'
                        : 'Noch keine Zeitreihe',
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _LoadMetricCard(
                    title: 'Langfristige Last',
                    subtitle: '42-Tage EWMA (chronisch)',
                    value: trimp != null
                        ? trimp.chronicLoad.toStringAsFixed(1)
                        : '—',
                    unit: 'TRIMP',
                    detail: trimp != null
                        ? 'Aufgebaute Grundfitness'
                        : 'Noch keine Zeitreihe',
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _LoadMetricCard(
                    title: 'Belastungsbalance',
                    subtitle: 'Chronisch - Akut',
                    value: trimp != null
                        ? '${trimp.loadBalance >= 0 ? '+' : ''}${trimp.loadBalance.toStringAsFixed(1)}'
                        : '—',
                    unit: 'Punkte',
                    valueColor: trimp != null
                        ? (trimp.loadBalance < -15.0
                            ? GiuliaTokens.warning
                            : GiuliaTokens.accent)
                        : null,
                    detail: trimp != null
                        ? (trimp.loadBalance >= 0
                            ? 'Chronische Last übersteigt akute Last'
                            : 'Akute Last übersteigt chronische Last')
                        : 'Rein deskriptive Differenz',
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: GiuliaTokens.spacingM),

        // 3. Deine Rückmeldung heute
        GiuliaPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Deine Rückmeldung heute',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: GiuliaTokens.spacingS),
              if (!subj.hasData)
                Text(
                  'Heute noch kein Check-in erfasst (fehlende Rückmeldung wird strikt als unvollständig und nicht als erholt gewertet).',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: GiuliaTokens.textMuted,
                      ),
                )
              else
                Wrap(
                  spacing: GiuliaTokens.spacingM,
                  runSpacing: GiuliaTokens.spacingS,
                  children: [
                    if (subj.perceivedRecovery != null)
                      _FeedbackChip(
                        label: 'Erholung',
                        value: '${subj.perceivedRecovery!.toStringAsFixed(1)} / 10',
                        isWarn: subj.perceivedRecovery! <= 4.0,
                      ),
                    if (subj.sleepQuality != null)
                      _FeedbackChip(
                        label: 'Schlaf',
                        value: '${subj.sleepQuality!.toStringAsFixed(1)} / 10',
                        isWarn: subj.sleepQuality! <= 4.0,
                      ),
                    if (subj.legSoreness != null)
                      _FeedbackChip(
                        label: 'Beine (DOMS)',
                        value: '${subj.legSoreness!.toStringAsFixed(1)} / 10',
                        isWarn: subj.legSoreness! >= 6.0,
                      ),
                    if (subj.upperBodySoreness != null)
                      _FeedbackChip(
                        label: 'Oberkörper (DOMS)',
                        value: '${subj.upperBodySoreness!.toStringAsFixed(1)} / 10',
                        isWarn: subj.upperBodySoreness! >= 6.0,
                      ),
                    if (subj.hasIllnessSymptoms)
                      _FeedbackChip(
                        label: 'Symptome',
                        value: subj.illnessSymptoms.join(', '),
                        isCritical: true,
                      ),
                    if (subj.hasPainSymptoms)
                      _FeedbackChip(
                        label: 'Schmerzen',
                        value: subj.painSymptoms.join(', '),
                        isWarn: true,
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: GiuliaTokens.spacingM),

        // 4. Letzte wichtige Trainingsreize
        GiuliaPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Letzte wichtige Trainingsreize',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: GiuliaTokens.spacingS),
              _StimulusRow(
                title: 'Hochintensiver Reiz (VO2max / HIT)',
                entry: stimuli.entries[StimulusType.vo2max],
                asOf: asOf,
              ),
              const Divider(height: 16),
              _StimulusRow(
                title: 'Schwellenreiz (LTP2 / EB)',
                entry: stimuli.entries[StimulusType.threshold],
                asOf: asOf,
              ),
              const Divider(height: 16),
              _StimulusRow(
                title: 'Langer Ausdauerreiz (Fatigue Resistance)',
                entry: stimuli.entries[StimulusType.fatigueResistance] ??
                    stimuli.entries[StimulusType.aerobicBase],
                asOf: asOf,
              ),
            ],
          ),
        ),
        const SizedBox(height: GiuliaTokens.spacingM),

        // 5. Datenlage & Unknown Days
        GiuliaPanel(
          tone: GiuliaTokens.surface2,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                cov.unknownDays28d > 3
                    ? Icons.info_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: cov.unknownDays28d > 3
                    ? GiuliaTokens.warning
                    : GiuliaTokens.success,
                size: 20,
              ),
              const SizedBox(width: GiuliaTokens.spacingS),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cov.unknownDays28d > 0
                          ? '${cov.unknownDays28d} Tage ohne Synchronisation'
                          : 'Hohe Datenabdeckung',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cov.unknownDays28d > 0
                          ? 'In den letzten 28 Tagen sind ${cov.unknownDays28d} Tage unbekannt. Sie werden nicht fälschlich als Ruhetage gewertet, reduzieren aber die Konfidenz.'
                          : 'Trainingshistorie der letzten 28 Tage ist lückenlos (${cov.observedTrainingDays28d} Trainingstage, ${cov.confirmedRestDays28d} bestätigte Ruhetage).',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: GiuliaTokens.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static _QualitativeStatus _deriveQualitativeStatus(
    dynamic trimpState,
    dynamic subj,
    dynamic cov,
  ) {
    if (cov.unknownDays28d > 5 || trimpState == null) {
      return const _QualitativeStatus(
        title: 'Datenlage unklar',
        description: 'Aufgrund fehlender Daten der letzten Tage ist die Belastungseinschätzung eingeschränkt.',
        tone: GiuliaTokens.surface3,
        color: GiuliaTokens.textMuted,
        icon: Icons.help_outline_rounded,
      );
    }

    if (subj.hasIllnessSymptoms || subj.hasPainSymptoms) {
      return const _QualitativeStatus(
        title: 'Hohe Belastung / Erholung priorisieren',
        description: 'Körperliche Symptome oder Beschwerden erfordern heute gezielte Entlastung.',
        tone: GiuliaTokens.surface2,
        color: GiuliaTokens.error,
        icon: Icons.warning_amber_rounded,
      );
    }

    final double balance = trimpState.loadBalance;
    final double? recovery = subj.perceivedRecovery;

    if (balance < -25.0 || (recovery != null && recovery <= 3.5)) {
      return const _QualitativeStatus(
        title: 'Hohe Belastung / Erholung priorisieren',
        description: 'Die akute Trainingslast übersteigt das gewohnte Niveau deutlich oder die Erholung ist stark reduziert.',
        tone: GiuliaTokens.surface2,
        color: GiuliaTokens.warning,
        icon: Icons.battery_alert_rounded,
      );
    }

    if (balance < -10.0 || (recovery != null && recovery <= 5.5)) {
      return const _QualitativeStatus(
        title: 'Erhöhte Belastung',
        description: 'Du befindest dich in einem fordernden Belastungsblock. Reize gezielt dosieren.',
        tone: GiuliaTokens.surface2,
        color: GiuliaTokens.warning,
        icon: Icons.trending_up_rounded,
      );
    }

    if (balance >= 5.0 && (recovery == null || recovery >= 7.0)) {
      return const _QualitativeStatus(
        title: 'Gut erholt',
        description: 'Ausreichende Anpassungsreserve und gute Frische für fordernde Trainingsreize vorhanden.',
        tone: GiuliaTokens.surface1,
        color: GiuliaTokens.success,
        icon: Icons.check_circle_rounded,
      );
    }

    return const _QualitativeStatus(
      title: 'Normale Trainingsbelastung',
      description: 'Ausgewogenes Verhältnis von akuter Beanspruchung und chronischer Belastungsverträglichkeit.',
      tone: GiuliaTokens.surface1,
      color: GiuliaTokens.accent,
      icon: Icons.fitness_center_rounded,
    );
  }
}

class _QualitativeStatus {
  const _QualitativeStatus({
    required this.title,
    required this.description,
    required this.tone,
    required this.color,
    required this.icon,
  });

  final String title;
  final String description;
  final Color tone;
  final Color color;
  final IconData icon;
}

class _LoadMetricCard extends StatelessWidget {
  const _LoadMetricCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.unit,
    required this.detail,
    this.valueColor,
  });

  final String title;
  final String subtitle;
  final String value;
  final String unit;
  final String detail;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: GiuliaTokens.textMuted,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: GiuliaTokens.textSecondary,
                  fontSize: 11,
                ),
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: valueColor ?? GiuliaTokens.textPrimary,
                    ),
              ),
              const SizedBox(width: GiuliaTokens.spacingXs),
              Text(
                unit,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: GiuliaTokens.textMuted,
                    ),
              ),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingXs),
          Text(
            detail,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: GiuliaTokens.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackChip extends StatelessWidget {
  const _FeedbackChip({
    required this.label,
    required this.value,
    this.isWarn = false,
    this.isCritical = false,
  });

  final String label;
  final String value;
  final bool isWarn;
  final bool isCritical;

  @override
  Widget build(BuildContext context) {
    final color = isCritical
        ? GiuliaTokens.error
        : (isWarn ? GiuliaTokens.warning : GiuliaTokens.textSecondary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isCritical
            ? GiuliaTokens.error.withValues(alpha: 0.1)
            : (isWarn
                ? GiuliaTokens.warning.withValues(alpha: 0.1)
                : GiuliaTokens.surface2),
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
        border: Border.all(
          color: isCritical
              ? GiuliaTokens.error.withValues(alpha: 0.3)
              : (isWarn
                  ? GiuliaTokens.warning.withValues(alpha: 0.3)
                  : GiuliaTokens.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: GiuliaTokens.textMuted,
                  fontSize: 10,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

class _StimulusRow extends StatelessWidget {
  const _StimulusRow({
    required this.title,
    required this.entry,
    required this.asOf,
  });

  final String title;
  final StimulusHistoryEntry? entry;
  final DateTime asOf;

  @override
  Widget build(BuildContext context) {
    final days = entry?.daysSinceLastObserved(asOf: asOf);
    final text = days == null
        ? 'Keine Beobachtung in den letzten 28 Tagen'
        : (days == 0
            ? 'Heute'
            : (days == 1 ? 'Gestern (vor 1 Tag)' : 'vor $days Tagen'));

    final mod = entry?.sourceModality?.label;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (mod != null)
                Text(
                  'Sportart: $mod',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: GiuliaTokens.textMuted,
                      ),
                ),
            ],
          ),
        ),
        const SizedBox(width: GiuliaTokens.spacingM),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: days != null && days <= 2
                      ? GiuliaTokens.accent
                      : GiuliaTokens.textSecondary,
                  fontWeight: days != null && days <= 2
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
          ),
        ),
      ],
    );
  }
}
