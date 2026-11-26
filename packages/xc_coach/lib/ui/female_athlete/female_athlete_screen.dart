/// Oberfläche für Zyklus & weibliche Gesundheit im ATHLETEN-Bereich.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Kein Klischee-Design, ruhige und evidenzbasierte GIULIA-Designsprache.
/// - Zeigt:
///   * Zykluskontext (Hormoneller Status, Zyklustag, Phasen-Schätzung mit ehrlicher Konfidenz)
///   * Perioden-Historie & Blutungstage
///   * Beobachtete persönliche Muster (nur wenn >= 3 Zyklen und wiederholt!)
///   * Aktive Gesundheitssignale (Health Signals mit medizinischem Disclaimer)
///   * Opt-In & Privatsphäre-Einstellungen
library;

import 'package:flutter/material.dart';

import '../../database/female_athlete_repository.dart';
import '../../intelligence/female_athlete/female_athlete_models.dart';
import '../design_system.dart';
import 'daily_cycle_symptom_sheet.dart';

class FemaleAthleteScreen extends StatefulWidget {
  const FemaleAthleteScreen({
    super.key,
    required this.athleteId,
    required this.femaleRepository,
    required this.femaleContext,
    required this.onChanged,
  });

  final String athleteId;
  final SqliteFemaleAthleteRepository femaleRepository;
  final FemaleAthleteContext femaleContext;
  final VoidCallback onChanged;

  @override
  State<FemaleAthleteScreen> createState() => _FemaleAthleteScreenState();
}

class _FemaleAthleteScreenState extends State<FemaleAthleteScreen> {
  late FemaleCycleTrackingOptIn _optIn;
  late HormonalStatus _hormonalStatus;

  @override
  void initState() {
    super.initState();
    _optIn = widget.femaleContext.cycleContext.optIn;
    _hormonalStatus = widget.femaleContext.cycleContext.hormonalStatus;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ctx = widget.femaleContext;
    final cycle = ctx.cycleContext;
    final evidence = ctx.evidence;
    final health = ctx.healthContext;

    return Scaffold(
      backgroundColor: GiuliaTokens.surface0,
      appBar: AppBar(
        title: const Text('Zyklus & Weibliche Gesundheit'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 1. Opt-in & Statuskarte
          _OptInCard(
            optIn: _optIn,
            hormonalStatus: _hormonalStatus,
            onChanged: (opt, status) {
              setState(() {
                _optIn = opt;
                _hormonalStatus = status;
              });
              final profile = widget.femaleRepository.getProfile(widget.athleteId);
              widget.femaleRepository.saveProfile(
                FemaleAthleteProfileData(
                  athleteId: widget.athleteId,
                  optIn: opt,
                  hormonalStatus: status,
                  isRegularCycle: profile?.isRegularCycle,
                  typicalCycleLengthDays: profile?.typicalCycleLengthDays,
                  contraceptiveDetails: profile?.contraceptiveDetails,
                  contraceptiveStartedAtUtcUs: profile?.contraceptiveStartedAtUtcUs,
                  updatedAtUtcUs: DateTime.now().toUtc().microsecondsSinceEpoch,
                ),
              );
              widget.onChanged();
            },
          ),
          const SizedBox(height: 16),

          if (_optIn.isEnabled) ...[
            // 2. Aktiver Zykluskontext & Tag
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Aktueller Zykluskontext', style: text.titleMedium),
                      if (cycle.currentCycleDay != null)
                        Chip(
                          label: Text('Tag ${cycle.currentCycleDay}'),
                          backgroundColor: GiuliaTokens.accent.withValues(alpha: 0.15),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Geschätzte Phase', style: text.labelSmall),
                  Text(
                    cycle.estimatedPhase.label,
                    style: text.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        cycle.phaseConfidence >= 0.7 ? Icons.check_circle_outline : Icons.info_outline,
                        size: 16,
                        color: GiuliaTokens.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Verlässlichkeit: ${(cycle.phaseConfidence * 100).round()}% (${cycle.inferenceMethod.label})',
                        style: text.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => _openRecordPeriodDialog(context),
                    icon: const Icon(Icons.water_drop_outlined),
                    label: const Text('Periode / Blutung eintragen'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

            // 3. Tägliche Symptome Button
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Row(
                    children: [
                      const Icon(Icons.favorite_outline, color: GiuliaTokens.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Heutige Symptome & Befinden', style: text.titleMedium),
                            Text(
                              ctx.todaysSymptoms != null
                                  ? 'Heute eingetragen: ${ctx.todaysSymptoms!.describeActiveSymptoms().join(", ")}'
                                  : 'Für heute noch keine Symptome erfasst.',
                              style: text.bodySmall?.copyWith(color: GiuliaTokens.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () {
                      DailyCycleSymptomSheet.show(
                        context: context,
                        initialReport: ctx.todaysSymptoms,
                        onSave: (report) {
                          widget.femaleRepository.saveSymptomReport(
                            widget.athleteId,
                            report,
                            nowUtcUs: DateTime.now().toUtc().microsecondsSinceEpoch,
                          );
                          widget.onChanged();
                        },
                      );
                    },
                    child: const Text('Symptome aktualisieren'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

            // 4. Persönliche Muster (Within-Athlete Evidence)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Beobachtete persönliche Muster', style: text.titleMedium),
                    const SizedBox(height: 8),
                    if (evidence.insufficientHistory || evidence.patterns.isEmpty) ...[
                      Text(
                        'Noch keine belastbaren Muster. GIULIA leitet persönliche Zusammenhänge erst nach mindestens 3 beobachteten Zyklen und wiederholten Einheiten ab.',
                        style: text.bodySmall?.copyWith(color: GiuliaTokens.textSecondary),
                      ),
                    ] else ...[
                      for (final p in evidence.patterns) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.insights, color: GiuliaTokens.accent),
                          title: Text(p.outcome.label),
                          subtitle: Text(
                            '${p.contextDescription} · ${p.magnitudeDescriptor}\n'
                            'Konfidenz: ${p.confidence.label} (${p.observationsCount} Beobachtungen)',
                          ),
                        ),
                        const Divider(),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 5. Gesundheitssignale (Health Signals)
            if (health.hasActiveHealthSignals) ...[
              Card(
                color: GiuliaTokens.warning.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: GiuliaTokens.warning),
                          const SizedBox(width: 8),
                          Text('Gesundheitssignale', style: text.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final s in health.activeSignals) ...[
                        Text(s.title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(s.description, style: text.bodySmall),
                        const SizedBox(height: 4),
                        Text(s.medicalDisclaimer, style: text.labelSmall?.copyWith(color: GiuliaTokens.textMuted)),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 6. Datenverwaltung / Privatsphäre
            OutlinedButton.icon(
              onPressed: () => _confirmDeleteData(context),
              icon: const Icon(Icons.delete_outline, color: GiuliaTokens.error),
              label: const Text('Alle Zyklusdaten unwiderruflich löschen', style: TextStyle(color: GiuliaTokens.error)),
            ),
          ],
        ],
      ),
    );
  }

  void _openRecordPeriodDialog(BuildContext context) {
    var startDate = DateTime.now();
    var intensity = BleedingIntensity.medium;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('Periodenbeginn erfassen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Erster Tag der Blutung (Tag 1):', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              ListTile(
                title: Text('${startDate.day}.${startDate.month}.${startDate.year}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: startDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) {
                    setDlgState(() => startDate = picked);
                  }
                },
              ),
              const SizedBox(height: 12),
              Text('Blutungsstärke:', style: Theme.of(context).textTheme.bodySmall),
              DropdownButton<BleedingIntensity>(
                value: intensity,
                isExpanded: true,
                items: [
                  for (final b in BleedingIntensity.values.where((v) => v != BleedingIntensity.none))
                    DropdownMenuItem(value: b, child: Text(b.label)),
                ],
                onChanged: (v) {
                  if (v != null) setDlgState(() => intensity = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                final nowUs = DateTime.now().toUtc().microsecondsSinceEpoch;
                widget.femaleRepository.savePeriod(
                  widget.athleteId,
                  RecordedCyclePeriod(
                    id: 'period_${widget.athleteId}_$nowUs',
                    startDate: startDate,
                    averageBleeding: intensity,
                  ),
                  nowUtcUs: nowUs,
                );
                widget.onChanged();
                Navigator.of(ctx).pop();
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteData(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zyklusdaten löschen?'),
        content: const Text(
          'Möchtest du wirklich alle gespeicherten Zyklus- und Symptomdaten unwiderruflich löschen? '
          'Der Coach funktioniert anschließend ohne Zyklusbezug normal weiter.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GiuliaTokens.error),
            onPressed: () {
              widget.femaleRepository.deleteCycleData(widget.athleteId);
              setState(() {
                _optIn = FemaleCycleTrackingOptIn.disabled;
              });
              widget.onChanged();
              Navigator.of(ctx).pop();
            },
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }
}

class _OptInCard extends StatelessWidget {
  const _OptInCard({
    required this.optIn,
    required this.hormonalStatus,
    required this.onChanged,
  });

  final FemaleCycleTrackingOptIn optIn;
  final HormonalStatus hormonalStatus;
  final void Function(FemaleCycleTrackingOptIn opt, HormonalStatus status) onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_outlined, color: GiuliaTokens.accent),
                const SizedBox(width: 8),
                Text('Zyklus-Tracking & Privatsphäre', style: text.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Freiwillig und evidenzbasiert. GIULIA nutzt keine pauschalen Phasenregeln, '
              'sondern beobachtet vorsichtig, ob bei dir persönlich wiederkehrende Muster existieren.',
              style: text.bodySmall?.copyWith(color: GiuliaTokens.textSecondary),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Zyklusdaten berücksichtigen'),
              subtitle: Text(optIn.label),
              value: optIn.isEnabled,
              activeThumbColor: GiuliaTokens.accent,
              onChanged: (val) {
                onChanged(
                  val ? FemaleCycleTrackingOptIn.enabled : FemaleCycleTrackingOptIn.disabled,
                  hormonalStatus,
                );
              },
            ),
            if (optIn.isEnabled) ...[
              const SizedBox(height: 12),
              Text('Hormoneller Status', style: text.titleSmall),
              const SizedBox(height: 6),
              DropdownButtonFormField<HormonalStatus>(
                initialValue: hormonalStatus,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: [
                  for (final s in HormonalStatus.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (val) {
                  if (val != null) onChanged(optIn, val);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
