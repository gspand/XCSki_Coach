/// Schneller, optionaler Zyklus- und Symptom-Check-In für den täglichen Ablauf.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Kein 20-Fragen-Marathon, sondern 5 gezielte, relevante Fragen:
///   1. Blutung (Keine / Schmierblutung / Leicht / Mittel / Stark)
///   2. Krämpfe & Schmerzen (Keine / Leicht / Mäßig / Stark)
///   3. Ungewöhnliche Müdigkeit (Keine / Leicht / Mäßig / Stark)
///   4. Kopfschmerzen / Magen-Darm / Brustspannen (nur bei Bedarf)
///   5. Wahrgenommene Trainingsbereitschaft
/// - Klare, neutrale Sprache im eleganten GIULIA Design (keine Klischee-Rosa-Ästhetik).
library;

import 'package:flutter/material.dart';

import '../../intelligence/female_athlete/female_athlete_models.dart';
import '../design_system.dart';

class DailyCycleSymptomSheet extends StatefulWidget {
  const DailyCycleSymptomSheet({
    super.key,
    required this.initialReport,
    required this.onSave,
  });

  final DailyCycleSymptomReport? initialReport;
  final ValueChanged<DailyCycleSymptomReport> onSave;

  static Future<void> show({
    required BuildContext context,
    DailyCycleSymptomReport? initialReport,
    required ValueChanged<DailyCycleSymptomReport> onSave,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DailyCycleSymptomSheet(
        initialReport: initialReport,
        onSave: onSave,
      ),
    );
  }

  @override
  State<DailyCycleSymptomSheet> createState() => _DailyCycleSymptomSheetState();
}

class _DailyCycleSymptomSheetState extends State<DailyCycleSymptomSheet> {
  late BleedingIntensity _bleeding;
  late SymptomSeverity _cramps;
  late SymptomSeverity _unusualFatigue;
  late SymptomSeverity _headache;
  late SymptomSeverity _giSymptoms;
  late SymptomSeverity _breastTenderness;
  late double _energyLevel;

  @override
  void initState() {
    super.initState();
    final r = widget.initialReport;
    _bleeding = r?.bleeding ?? BleedingIntensity.none;
    _cramps = r?.cramps ?? SymptomSeverity.none;
    _unusualFatigue = r?.unusualFatigue ?? SymptomSeverity.none;
    _headache = r?.headache ?? SymptomSeverity.none;
    _giSymptoms = r?.giSymptoms ?? SymptomSeverity.none;
    _breastTenderness = r?.breastTenderness ?? SymptomSeverity.none;
    _energyLevel = r?.energyLevel ?? 7.0;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: const BoxDecoration(
        color: GiuliaTokens.surface1,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.transparent,
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
                Text(
                  'Zyklus & Befinden heute',
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Deine Symptome fließen direkt in die heutige Trainingsbereitschaft ein.',
                  style: text.bodyMedium?.copyWith(color: GiuliaTokens.textSecondary),
                ),
                const SizedBox(height: 24),

                // 1. Blutung
                Text('Blutung', style: text.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final b in BleedingIntensity.values)
                      ChoiceChip(
                        label: Text(b.label),
                        selected: _bleeding == b,
                        onSelected: (selected) {
                          if (selected) setState(() => _bleeding = b);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                // 2. Krämpfe & Schmerzen
                Text('Krämpfe / Unterleibsschmerzen', style: text.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in SymptomSeverity.values)
                      ChoiceChip(
                        label: Text(s.label),
                        selected: _cramps == s,
                        onSelected: (selected) {
                          if (selected) setState(() => _cramps = s);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                // 3. Ungewöhnliche Müdigkeit
                Text('Ungewöhnliche Müdigkeit', style: text.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in SymptomSeverity.values)
                      ChoiceChip(
                        label: Text(s.label),
                        selected: _unusualFatigue == s,
                        onSelected: (selected) {
                          if (selected) setState(() => _unusualFatigue = s);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                // 4. Energie-Niveau Slider
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Subjektives Energiegefühl', style: text.titleSmall),
                    Text(
                      '${_energyLevel.round()} / 10',
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Slider(
                  value: _energyLevel,
                  min: 1,
                  max: 10,
                  divisions: 9,
                  activeColor: GiuliaTokens.accent,
                  onChanged: (v) => setState(() => _energyLevel = v),
                ),
                const SizedBox(height: 16),

                // 5. Weitere Beschwerden (Optionale Checks)
                ExpansionTile(
                  title: Text('Weitere Symptome (optional)', style: text.bodyMedium),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    _SeveritySelector(
                      label: 'Kopfschmerzen',
                      value: _headache,
                      onChanged: (v) => setState(() => _headache = v),
                    ),
                    const SizedBox(height: 12),
                    _SeveritySelector(
                      label: 'Magen-Darm-Beschwerden',
                      value: _giSymptoms,
                      onChanged: (v) => setState(() => _giSymptoms = v),
                    ),
                    const SizedBox(height: 12),
                    _SeveritySelector(
                      label: 'Brustspannen',
                      value: _breastTenderness,
                      onChanged: (v) => setState(() => _breastTenderness = v),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
                const SizedBox(height: 24),

                FilledButton(
                  onPressed: _handleSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: GiuliaTokens.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(GiuliaTokens.radiusButton),
                    ),
                  ),
                  child: const Text('Angaben speichern'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleSave() {
    final report = DailyCycleSymptomReport(
      date: DateTime.now(),
      bleeding: _bleeding,
      cramps: _cramps,
      unusualFatigue: _unusualFatigue,
      energyLevel: _energyLevel,
      headache: _headache,
      giSymptoms: _giSymptoms,
      breastTenderness: _breastTenderness,
      recordedAtUtcUs: DateTime.now().toUtc().microsecondsSinceEpoch,
    );
    widget.onSave(report);
    Navigator.of(context).pop();
  }
}

class _SeveritySelector extends StatelessWidget {
  const _SeveritySelector({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final SymptomSeverity value;
  final ValueChanged<SymptomSeverity> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Wrap(
          spacing: 6,
          children: [
            for (final s in SymptomSeverity.values)
              ChoiceChip(
                label: Text(s.label),
                selected: value == s,
                onSelected: (selected) {
                  if (selected) onChanged(s);
                },
              ),
          ],
        ),
      ],
    );
  }
}
