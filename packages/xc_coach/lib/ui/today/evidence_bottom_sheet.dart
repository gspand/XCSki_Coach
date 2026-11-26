/// Ebene 4 – Evidence Bottom Sheet.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Verbirgt technische Berechnungen, bietet aber bei Bedarf 100 % Transparenz.
/// - Zeigt Ziel, aktuellen Trainingsschwerpunkt, berücksichtigte Leitplanken
///   und den lückenlosen Rückwärts-Trace bis zur State-Evidenz.
library;

import 'package:flutter/material.dart';

import '../design_system.dart';
import 'today_view_model.dart';

class EvidenceBottomSheet extends StatefulWidget {
  const EvidenceBottomSheet({
    super.key,
    required this.viewModel,
  });

  final TodayViewModel viewModel;

  static Future<void> show(BuildContext context, TodayViewModel viewModel) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EvidenceBottomSheet(viewModel: viewModel),
    );
  }

  @override
  State<EvidenceBottomSheet> createState() => _EvidenceBottomSheetState();
}

class _EvidenceBottomSheetState extends State<EvidenceBottomSheet> {
  bool _showRawTrace = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final vm = widget.viewModel;

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
              'Warum empfiehlt GIULIA das?',
              style: text.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: GiuliaTokens.textPrimary,
              ),
            ),
            const SizedBox(height: GiuliaTokens.spacingM),

            // Übersichtliche Fakten
            if (vm.decisionVersion != null)
              _FactRow(label: 'Entscheidung', value: '${vm.decisionId} · ${vm.decisionVersion!.substring(0, 10)}'),
            _FactRow(label: 'Empfohlene Einheit', value: vm.heroTitle),
            _FactRow(label: 'Sportart', value: vm.modalityLabel),
            _FactRow(label: 'Dauer', value: '${vm.durationMinutes} Minuten'),
            _FactRow(label: 'Intensität', value: vm.qualitativeIntensity.label),
            _FactRow(label: 'Datenlage', value: vm.confidenceLabel),

            if (vm.importantNotes.isNotEmpty) ...[
              const SizedBox(height: GiuliaTokens.spacingM),
              Text(
                'Berücksichtigte Hinweise',
                style: text.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: GiuliaTokens.textSecondary,
                ),
              ),
              const SizedBox(height: GiuliaTokens.spacingXs),
              for (final note in vm.importantNotes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(color: GiuliaTokens.accent)),
                      Expanded(
                        child: Text(
                          note,
                          style: text.bodyMedium?.copyWith(
                            color: GiuliaTokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            const SizedBox(height: GiuliaTokens.spacingL),

            // Toggle für technischen Rückwärts-Trace
            InkWell(
              onTap: () => setState(() => _showRawTrace = !_showRawTrace),
              child: Row(
                children: [
                  Icon(
                    _showRawTrace ? Icons.expand_less : Icons.expand_more,
                    size: GiuliaTokens.iconM,
                    color: GiuliaTokens.textMuted,
                  ),
                  const SizedBox(width: GiuliaTokens.spacingS),
                  Expanded(
                    child: Text(
                      _showRawTrace ? 'Technische Details verbergen' : 'Technische Details & Trace anzeigen',
                      style: text.bodyMedium?.copyWith(
                        color: GiuliaTokens.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_showRawTrace) ...[
              const SizedBox(height: GiuliaTokens.spacingM),
              Container(
                padding: const EdgeInsets.all(GiuliaTokens.spacingM),
                decoration: BoxDecoration(
                  color: GiuliaTokens.surface2,
                  borderRadius: BorderRadius.circular(GiuliaTokens.radiusM),
                  border: Border.all(color: GiuliaTokens.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LÜCKENLOSER ENTSCHEIDUNGS-TRACE (CORE)',
                      style: text.labelSmall?.copyWith(
                        color: GiuliaTokens.textMuted,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: GiuliaTokens.spacingS),
                    for (final entry in vm.evidenceTrace.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '${entry.key}: ${entry.value}',
                          style: text.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: GiuliaTokens.textSecondary,
                          ),
                        ),
                      ),
                    if (vm.evidenceTrace.isEmpty)
                      Text(
                        'Kein Trace für diese Einheit hinterlegt.',
                        style: text.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: GiuliaTokens.spacingL),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(GiuliaTokens.radiusButton),
                ),
              ),
              child: const Text('Schließen'),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: text.bodyMedium?.copyWith(color: GiuliaTokens.textSecondary)),
          const SizedBox(width: GiuliaTokens.spacingM),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: GiuliaTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
