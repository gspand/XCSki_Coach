/// The LaLa area: overview of one athlete's lactate diagnostics.
///
/// Everything on this screen is read back from the database. The screen never
/// asks the engine anything; it shows the calculation run that was stored.
library;

import 'package:flutter/material.dart';
import 'package:xc_coach/database/platform_repository.dart';
import 'package:xc_coach/ui/lala/measured_test.dart';
import 'package:xc_coach/lala/application/lala_controller.dart';
import 'package:xc_coach/lala/application/lala_view_models.dart';
import 'package:xc_coach/ui/design_system.dart';
import 'package:xc_coach/ui/vocabulary.dart';
import 'package:xc_coach/external_data/activity_import.dart';
import 'package:xc_coach/ui/lala/lala_comparison_screen.dart';
import 'package:xc_coach/ui/lala/lala_metabolic_technique_screen.dart';
import 'package:xc_coach/ui/lala/lala_new_test_screen.dart';
import 'package:xc_coach/ui/lala/lala_test_detail_screen.dart';
import 'package:xc_coach/ui/lala/lala_widgets.dart';
import 'package:xc_coach/ui/lala/lactate_import.dart';
import 'package:xc_coach/ui/lala/tests_screen.dart';

/// Full name of the module. The abbreviation stays visible everywhere.
const String lalaModuleName = 'LaLa – Lactate Lab';

class LalaArea extends StatefulWidget {
  const LalaArea({
    super.key,
    required this.controller,
    this.measuredTest,
    this.lactateImport,
    this.activityImport,
  });

  final LalaController controller;

  /// Present when this installation can measure with a device. LaLa itself is
  /// unaffected by it: every screen below works identically without one.
  final MeasuredTestAccess? measuredTest;

  /// Present when this installation can read a lactate meter's memory.
  final LactateImportAccess? lactateImport;

  /// Present when a local activity file can provide the measured load curve.
  final ActivityImportAccess? activityImport;

  @override
  State<LalaArea> createState() => _LalaAreaState();
}

class _LalaAreaState extends State<LalaArea> {
  @override
  void initState() {
    super.initState();
    // Selected first, listened to afterwards: the initial selection notifies
    // synchronously, and a setState from inside initState would be a rebuild
    // requested during the very build that created this state.
    final athletes = widget.controller.athletes;
    if (widget.controller.selectedAthleteId == null && athletes.isNotEmpty) {
      widget.controller.selectAthlete(athletes.first.id);
    }
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final athletes = controller.athletes;

    if (athletes.isEmpty) {
      return const _LalaScaffold(
        child: GiuliaEmptyState(
          icon: Icons.person_outline,
          title: 'Noch kein Athlet angelegt',
          description:
              'LaLa ordnet jeden Laktattest einem Athleten zu. Lege zuerst '
              'einen Athleten an; ein Messgerät wird dafür nicht benötigt.',
        ),
      );
    }

    return _LalaScaffold(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AthleteSelector(
            athletes: athletes,
            selected: controller.selectedAthleteId,
            onSelect: controller.selectAthlete,
          ),
          if (widget.lactateImport case final access?) ...[
            const SizedBox(height: GiuliaTokens.spacingS),
            OutlinedButton.icon(
              key: const Key('lala-overview-import-lactate'),
              onPressed: () => openLactateImport(
                context,
                controller: controller,
                access: access,
                activityImport: widget.activityImport,
                athletes: athletes,
              ),
              icon: const Icon(Icons.download_outlined),
              label: Text('${access.sourceLabel} importieren'),
            ),
            if (widget.activityImport case final activity?) ...[
              const SizedBox(height: GiuliaTokens.spacingXs),
              Text(
                '${activity.sourceLabel} kann im nächsten Schritt als '
                'Belastungsverlauf ergänzt werden.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
              ),
            ],
          ],
          if (widget.activityImport case final activity?) ...[
            const SizedBox(height: GiuliaTokens.spacingS),
            OutlinedButton.icon(
              key: const Key('lala-overview-import-activity'),
              onPressed: () => openActivityImport(
                context,
                controller: controller,
                access: activity,
                athletes: athletes,
              ),
              icon: const Icon(Icons.watch_outlined),
              label: Text('${activity.sourceLabel}-Aktivität importieren'),
            ),
          ],
        ],
      ),
      child: _body(controller),
    );
  }

  Widget _body(LalaController controller) {
    if (controller.failure case final failure? when failure.isPermission) {
      return GiuliaEmptyState(
        icon: Icons.lock_outline,
        title: 'Kein Zugriff auf diesen Athleten',
        description: failure.message,
      );
    }
    final overview = controller.overview;
    if (overview == null) {
      return const GiuliaEmptyState(
        icon: Icons.science_outlined,
        title: 'Athlet wählen',
        description: 'Wähle einen Athleten, um seine LaLa-Diagnostik zu sehen.',
      );
    }
    if (overview.isEmpty) {
      return _EmptyLalaState(
        athleteName: overview.athleteName,
        onCreate: () =>
            _openNewTest(controller, overview.athleteId, overview.athleteName),
      );
    }
    return _Overview(
      controller: controller,
      overview: overview,
      onNewTest: () =>
          _openNewTest(controller, overview.athleteId, overview.athleteName),
    );
  }

  Future<void> _openNewTest(
    LalaController controller,
    String athleteId,
    String athleteName,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LalaNewTestScreen(
          controller: controller,
          athleteId: athleteId,
          athleteName: athleteName,
          measuredTest: widget.measuredTest,
        ),
      ),
    );
  }
}

class _LalaScaffold extends StatelessWidget {
  const _LalaScaffold({required this.child, this.header});
  final Widget child;
  final Widget? header;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
    children: [
      Text(lalaModuleName, style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 6),
      Text(
        'Laktatdiagnostik, Schwellen und Trainingszonen — geräteunabhängig.',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      if (header != null) ...[const SizedBox(height: 20), header!],
      const SizedBox(height: GiuliaTokens.spacingL),
      child,
    ],
  );
}

class _AthleteSelector extends StatelessWidget {
  const _AthleteSelector({
    required this.athletes,
    required this.selected,
    required this.onSelect,
  });

  final List<AthleteSummary> athletes;
  final String? selected;
  final ValueChanged<String> onSelect;

  /// Only an athlete that is actually in the list may be the selected value.
  /// Selecting someone the user may not see is refused elsewhere; the
  /// dropdown must not fall over while that is being explained.
  String? get _value =>
      athletes.any((athlete) => athlete.id == selected) ? selected : null;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    padding: const EdgeInsets.all(GiuliaTokens.spacingM),
    child: Row(
      children: [
        Text('ATHLET', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(width: 16),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: const Key('lala-athlete-selector'),
              isExpanded: true,
              value: _value,
              hint: const Text('Athlet wählen'),
              items: [
                for (final athlete in athletes)
                  DropdownMenuItem(
                    value: athlete.id,
                    child: Text(athlete.name),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onSelect(value);
              },
            ),
          ),
        ),
      ],
    ),
  );
}

/// Shown when an athlete has no test at all.
class _EmptyLalaState extends StatelessWidget {
  const _EmptyLalaState({required this.athleteName, required this.onCreate});
  final String athleteName;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GiuliaEmptyState(
        icon: Icons.biotech_outlined,
        title: 'Noch kein Laktattest für $athleteName',
        description:
            'LaLa wertet Stufentests wissenschaftlich aus: LT1, LT2, die '
            'tatsächlich verwendete Methode und daraus abgeleitete '
            'Trainingszonen.',
        action: FilledButton.icon(
          key: const Key('lala-empty-create'),
          onPressed: onCreate,
          icon: const Icon(Icons.add),
          label: const Text('Ersten Test anlegen'),
        ),
      ),
      const SizedBox(height: GiuliaTokens.spacingM),
      const GiuliaPanel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.sensors_off_outlined,
              size: GiuliaTokens.iconM,
              color: GiuliaTokens.textMuted,
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kein Ercolina-Gerät notwendig',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Ein Laktatstufentest lässt sich vollständig manuell '
                    'erfassen: Belastung, Herzfrequenz, RPE und Laktat pro '
                    'Stufe. Ein angeschlossenes Ergometer liefert die '
                    'Leistung später automatisch, ändert an der Auswertung '
                    'aber nichts.',
                    style: TextStyle(color: GiuliaTokens.textSecondary),
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

class _Overview extends StatelessWidget {
  const _Overview({
    required this.controller,
    required this.overview,
    required this.onNewTest,
  });

  final LalaController controller;
  final LalaAthleteOverview overview;
  final VoidCallback onNewTest;

  @override
  Widget build(BuildContext context) {
    final latest = overview.latestTest;
    final run = overview.latestRun;
    final change = overview.change;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                latest == null
                    ? 'Noch keine ausgewertete Messung'
                    : 'Letzter Test: ${formatTestDate(latest.head.startedAtUtcUs)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            FilledButton.icon(
              key: const Key('lala-new-test'),
              onPressed: onNewTest,
              icon: const Icon(Icons.add),
              label: const Text('Neuer Test'),
            ),
          ],
        ),
        const SizedBox(height: GiuliaTokens.spacingM),

        if (overview.hasUnevaluatedOnly)
          const GiuliaPanel(
            child: Text(
              'Für diesen Athleten sind Tests erfasst, aber noch keiner wurde '
              'ausgewertet.',
            ),
          )
        else if (latest != null && run != null) ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 700;
              final cards = [
                Expanded(
                  child: LalaThresholdCard(
                    threshold: run.lt1,
                    bodyMassKg: latest.data.bodyMassKg,
                    deltaLabel: change?.lt1LoadDelta == null
                        ? null
                        : formatLoadDelta(
                            change!.lt1LoadDelta,
                            change.loadUnit,
                          ),
                  ),
                ),
                const SizedBox(width: GiuliaTokens.spacingM),
                Expanded(
                  child: LalaThresholdCard(
                    threshold: run.lt2,
                    bodyMassKg: latest.data.bodyMassKg,
                    deltaLabel: change?.lt2LoadDelta == null
                        ? null
                        : formatLoadDelta(
                            change!.lt2LoadDelta,
                            change.loadUnit,
                          ),
                  ),
                ),
              ];
              return wide
                  ? IntrinsicHeight(
                      // Both cards get the height of the taller one; without
                      // the intrinsic pass a stretched row inside a scroll
                      // view has no height to stretch to.
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: cards,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LalaThresholdCard(
                          threshold: run.lt1,
                          bodyMassKg: latest.data.bodyMassKg,
                        ),
                        const SizedBox(height: GiuliaTokens.spacingM),
                        LalaThresholdCard(
                          threshold: run.lt2,
                          bodyMassKg: latest.data.bodyMassKg,
                        ),
                      ],
                    );
            },
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          FilledButton.icon(
            key: const Key('lala-open-metabolic-profile'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LalaMetabolicTechniqueScreen(
                  controller: controller,
                  athleteId: overview.athleteId,
                ),
              ),
            ),
            icon: const Icon(Icons.monitor_heart_outlined),
            label: const Text('Metabolik & Technik · Vollauswertung'),
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          LalaLactateCurve(
            points: latest.curve,
            loadUnit: latest.head.loadUnit,
            lt1Load: run.lt1?.loadValue,
            lt2Load: run.lt2?.loadValue,
            lt1Lactate: run.lt1?.lactateMmolPerLitre,
            lt2Lactate: run.lt2?.lactateMmolPerLitre,
            bodyMassKg: latest.data.bodyMassKg,
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('lala-open-detail'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LalaTestDetailScreen(
                        controller: controller,
                        testId: latest.head.id,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Testdetail öffnen'),
                ),
              ),
              if (overview.previousTest != null) ...[
                const SizedBox(width: GiuliaTokens.spacingM),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('lala-open-comparison'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LalaComparisonScreen(
                          controller: controller,
                          earlierTestId: overview.previousTest!.head.id,
                          laterTestId: latest.head.id,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.compare_arrows_outlined),
                    label: const Text('Mit Vortest vergleichen'),
                  ),
                ),
              ],
            ],
          ),
          if (run.zoneSets.isNotEmpty) ...[
            const SizedBox(height: GiuliaTokens.spacingL),
            Text(
              'AKTUELLE TRAININGSZONEN',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: GiuliaTokens.spacingS),
            LalaZoneTable(
              zoneSet: run.zoneSets.first,
              bodyMassKg: latest.data.bodyMassKg,
            ),
            if (run.zoneSets.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: GiuliaTokens.spacingS),
                child: Text(
                  '${run.zoneSets.length} Zonenmodelle wurden berechnet; die '
                  'weiteren stehen im Testdetail.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
          ],
        ],

        const SizedBox(height: GiuliaTokens.spacingL),
        Text('TESTHISTORIE', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: GiuliaTokens.spacingS),
        _HistoryList(controller: controller, entries: overview.history),
      ],
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.controller, required this.entries});

  final LalaController controller;
  final List<LalaHistoryEntry> entries;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    padding: const EdgeInsets.symmetric(vertical: GiuliaTokens.spacingS),
    child: Material(
      // The panel paints its own background, so the tiles need a Material of
      // their own for their ink response to be visible at all.
      type: MaterialType.transparency,
      child: Column(
        children: [
          for (final entry in entries)
            ListTile(
              key: Key('lala-history-${entry.testId}'),
              title: Text(
                '${formatTestDate(entry.startedAtUtcUs)} · '
                '${sportLabel(entry.sport)}',
              ),
              subtitle: Text(
                entry.hasResult
                    ? 'LT1 ${formatLoad(entry.lt1Load, entry.loadUnit)}  ·  '
                          'LT2 ${formatLoad(entry.lt2Load, entry.loadUnit)}'
                          '${entry.hasSeveralRuns ? '  ·  ${entry.runCount} Auswertungen' : ''}'
                    : 'Noch nicht ausgewertet',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LalaTestDetailScreen(
                    controller: controller,
                    testId: entry.testId,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
