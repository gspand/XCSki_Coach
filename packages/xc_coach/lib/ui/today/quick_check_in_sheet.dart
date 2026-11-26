/// Tägliche subjektive Rückmeldung (Quick Check-in).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Extrem kurze, unkomplizierte Eingabe (keine 20 Fragen).
/// - Erholung (1–10), Schlaf (1–10), Beine & Oberkörper (Frisch/Normal/Schwer),
///   Schmerzen (Ja/Nein), Krankheitssymptome (Ja/Nein).
/// - Aktualisiert den [SubjectiveReadinessState] und leitet die Neuberechnung
///   des Cores ein.
library;

import 'package:flutter/material.dart';

import '../../intelligence/xc_athlete_state/subjective_readiness_state.dart';
import '../design_system.dart';

class QuickCheckInSheet extends StatefulWidget {
  const QuickCheckInSheet({
    super.key,
    required this.initialState,
    required this.onSave,
  });

  final SubjectiveReadinessState initialState;
  final ValueChanged<SubjectiveReadinessState> onSave;

  static Future<void> show({
    required BuildContext context,
    required SubjectiveReadinessState initialState,
    required ValueChanged<SubjectiveReadinessState> onSave,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuickCheckInSheet(
        initialState: initialState,
        onSave: onSave,
      ),
    );
  }

  @override
  State<QuickCheckInSheet> createState() => _QuickCheckInSheetState();
}

enum MuscleSorenessLevel {
  none('Frisch', 1.0),
  mild('Normal', 4.0),
  severe('Schwer', 8.0);

  const MuscleSorenessLevel(this.label, this.numericScore);
  final String label;
  final double numericScore;

  static MuscleSorenessLevel fromScore(double? score) {
    if (score == null || score <= 2.0) return MuscleSorenessLevel.none;
    if (score <= 5.0) return MuscleSorenessLevel.mild;
    return MuscleSorenessLevel.severe;
  }
}

class _QuickCheckInSheetState extends State<QuickCheckInSheet> {
  late double _recovery;
  late double _sleep;
  late MuscleSorenessLevel _legs;
  late MuscleSorenessLevel _upperBody;
  late bool _hasPain;
  late String _painLocation;
  late bool _hasIllness;

  @override
  void initState() {
    super.initState();
    _recovery = widget.initialState.perceivedRecovery ?? 7.0;
    _sleep = widget.initialState.sleepQuality ?? 7.0;
    _legs = MuscleSorenessLevel.fromScore(widget.initialState.legSoreness);
    _upperBody = MuscleSorenessLevel.fromScore(widget.initialState.upperBodySoreness);
    _hasPain = widget.initialState.hasPainSymptoms;
    _painLocation = widget.initialState.painSymptoms.isNotEmpty
        ? widget.initialState.painSymptoms.first
        : '';
    _hasIllness = widget.initialState.hasIllnessSymptoms;
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
                'Wie fühlst du dich heute?',
                style: text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: GiuliaTokens.textPrimary,
                ),
              ),
              const SizedBox(height: GiuliaTokens.spacingXs),
              Text(
                'GIULIA passt dein Training bei Bedarf an deine Tagesform an.',
                style: text.bodyMedium?.copyWith(color: GiuliaTokens.textSecondary),
              ),
              const SizedBox(height: GiuliaTokens.spacingL),

              // 1. Erholung
              _SliderSection(
                title: 'Erholung',
                value: _recovery,
                minLabel: 'Erschöpft (1)',
                maxLabel: 'Topfit (10)',
                onChanged: (val) => setState(() => _recovery = val),
              ),
              const SizedBox(height: GiuliaTokens.spacingM),

              // 2. Schlaf
              _SliderSection(
                title: 'Schlafqualität',
                value: _sleep,
                minLabel: 'Schlecht (1)',
                maxLabel: 'Ausgezeichnet (10)',
                onChanged: (val) => setState(() => _sleep = val),
              ),
              const SizedBox(height: GiuliaTokens.spacingL),

              // 3. Beine & Oberkörper
              Text(
                'Muskuläre Frische',
                style: text.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: GiuliaTokens.textPrimary,
                ),
              ),
              const SizedBox(height: GiuliaTokens.spacingS),
              Row(
                children: [
                  Expanded(
                    child: _MuscleSelector(
                      label: 'Beine',
                      current: _legs,
                      onSelected: (val) => setState(() => _legs = val),
                    ),
                  ),
                  const SizedBox(width: GiuliaTokens.spacingM),
                  Expanded(
                    child: _MuscleSelector(
                      label: 'Oberkörper',
                      current: _upperBody,
                      onSelected: (val) => setState(() => _upperBody = val),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: GiuliaTokens.spacingL),

              // 4. Schmerzen / Orthopädische Beschwerden
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                activeColor: GiuliaTokens.accent,
                title: Text(
                  'Schmerzen oder Beschwerden?',
                  style: text.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: GiuliaTokens.textPrimary,
                  ),
                ),
                subtitle: Text(
                  _hasPain ? 'Gelenk- oder Muskelbeschwerden vorhanden' : 'Keine Beschwerden',
                  style: text.bodySmall?.copyWith(color: GiuliaTokens.textSecondary),
                ),
                value: _hasPain,
                onChanged: (val) => setState(() => _hasPain = val),
              ),
              if (_hasPain) ...[
                const SizedBox(height: GiuliaTokens.spacingXs),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Z. B. Leichtes Ziehen im Knie, Trizeps...',
                    filled: true,
                    fillColor: GiuliaTokens.surface0,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(GiuliaTokens.radiusButton),
                      borderSide: const BorderSide(color: GiuliaTokens.border),
                    ),
                  ),
                  onChanged: (val) => _painLocation = val,
                ),
              ],
              const SizedBox(height: GiuliaTokens.spacingS),

              // 5. Krankheitssymptome / Infekt
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                activeColor: GiuliaTokens.error,
                title: Text(
                  'Infekt- oder Krankheitssymptome?',
                  style: text.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: GiuliaTokens.textPrimary,
                  ),
                ),
                subtitle: Text(
                  _hasIllness ? 'Fieber, Halskratzen, Frösteln' : 'Vollkommen gesund',
                  style: text.bodySmall?.copyWith(color: GiuliaTokens.textSecondary),
                ),
                value: _hasIllness,
                onChanged: (val) => setState(() => _hasIllness = val),
              ),
              const SizedBox(height: GiuliaTokens.spacingL),

              // Speichern Button
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
                child: const Text('Angaben aktualisieren'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  }

  void _handleSave() {
    final updated = SubjectiveReadinessState(
      recordedAt: DateTime.now().toUtc(),
      perceivedRecovery: _recovery,
      sleepQuality: _sleep,
      legSoreness: _legs.numericScore,
      upperBodySoreness: _upperBody.numericScore,
      painSymptoms: _hasPain
          ? [
              _painLocation.trim().isEmpty
                  ? 'Schmerzen gemeldet'
                  : _painLocation.trim(),
            ]
          : const [],
      illnessSymptoms: _hasIllness
          ? const ['Infektsymptome gemeldet']
          : const [],
      unusualFatigue: _recovery <= 3.5,
      confidence: 0.9,
    );
    widget.onSave(updated);
    Navigator.of(context).pop();
  }
}

class _SliderSection extends StatelessWidget {
  const _SliderSection({
    required this.title,
    required this.value,
    required this.minLabel,
    required this.maxLabel,
    required this.onChanged,
  });

  final String title;
  final double value;
  final String minLabel;
  final String maxLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: text.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: GiuliaTokens.textPrimary,
              ),
            ),
            Text(
              value.toStringAsFixed(1),
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: GiuliaTokens.accent,
              ),
            ),
          ],
        ),
        Slider.adaptive(
          value: value,
          min: 1.0,
          max: 10.0,
          divisions: 18,
          activeColor: GiuliaTokens.accent,
          onChanged: onChanged,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(minLabel, style: text.bodySmall?.copyWith(color: GiuliaTokens.textMuted)),
            ),
            const SizedBox(width: GiuliaTokens.spacingS),
            Flexible(
              child: Text(
                maxLabel,
                textAlign: TextAlign.end,
                style: text.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MuscleSelector extends StatelessWidget {
  const _MuscleSelector({
    required this.label,
    required this.current,
    required this.onSelected,
  });

  final String label;
  final MuscleSorenessLevel current;
  final ValueChanged<MuscleSorenessLevel> onSelected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: text.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: GiuliaTokens.textSecondary,
          ),
        ),
        const SizedBox(height: GiuliaTokens.spacingXs),
        SegmentedButton<MuscleSorenessLevel>(
          segments: const [
            ButtonSegment(value: MuscleSorenessLevel.none, label: Text('Frisch')),
            ButtonSegment(value: MuscleSorenessLevel.mild, label: Text('Normal')),
            ButtonSegment(value: MuscleSorenessLevel.severe, label: Text('Schwer')),
          ],
          selected: {current},
          onSelectionChanged: (set) => onSelected(set.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStateProperty.all(text.bodySmall),
          ),
        ),
      ],
    );
  }
}
