/// LaLas erste Fläche.
///
/// Ein Werkzeug beginnt bei der Arbeit. Deshalb steht hier kein Willkommen und
/// keine Übersicht, sondern das, was eine Diagnostikerin wöchentlich tut:
///
/// 1. **Einen neuen Test beginnen** — die eine grosse Handlung.
/// 2. **Angefangenes zu Ende bringen** — gemessen, aber noch nicht bewertet.
/// 3. **Nachsehen, was zuletzt herauskam.**
///
/// Mehr nicht. Athleten, Protokolle und Berichte haben eigene Bereiche; wer
/// hier steht, will messen.
library;

import 'package:flutter/material.dart';

import '../../database/platform_repository.dart';
import '../../lala/application/lala_controller.dart';
import '../../lala/application/lala_view_models.dart';
import '../design_system.dart';
import '../vocabulary.dart';
import '../../database/observation_repository_sqlite.dart';
import '../../external_data/activity_import.dart';
import '../../external_data/activity_import_repository.dart';
import '../../external_data/external_import_registry.dart';
import '../../external_data/import_writer.dart';
import '../../external_data/normalization/measurement_grouping.dart';
import 'import_review_screen.dart';
import 'lactate_import_selection_screen.dart';
import 'lactate_import.dart';
import 'measured_test.dart';
import 'lala_new_test_screen.dart';
import 'lala_test_detail_screen.dart';
import 'lala_widgets.dart';

class TestsScreen extends StatelessWidget {
  const TestsScreen({
    super.key,
    required this.controller,
    this.measuredTest,
    this.lactateImport,
    this.activityImport,
  });

  final LalaController controller;

  /// Optionaler Gerätezugang. Der manuelle Test bleibt immer verfügbar; ist
  /// ein Gerät vorhanden, bietet derselbe Ablauf nach der Protokollwahl den
  /// gemessenen Weg an.
  final MeasuredTestAccess? measuredTest;

  /// Ohne Gerät, das gespeicherte Werte hergibt, fehlt der Knopf. Nicht ein
  /// Knopf, der dann nichts tut.
  final LactateImportAccess? lactateImport;

  /// Optionaler Belastungsverlauf, der beim Messwertimport zeitlich mit den
  /// Laktatproben zusammengeführt wird.
  final ActivityImportAccess? activityImport;

  @override
  Widget build(BuildContext context) {
    final density = GiuliaDensity.of(context);
    final athletes = controller.athletes;
    final open = <(AthleteSummary, LalaHistoryEntry)>[];
    final done = <(AthleteSummary, LalaHistoryEntry)>[];
    for (final athlete in athletes) {
      for (final entry in controller.overviewFor(athlete.id).history) {
        (entry.hasResult ? done : open).add((athlete, entry));
      }
    }
    open.sort((a, b) => b.$2.startedAtUtcUs.compareTo(a.$2.startedAtUtcUs));
    done.sort((a, b) => b.$2.startedAtUtcUs.compareTo(a.$2.startedAtUtcUs));

    return ListView(
      padding: density.pageInsets,
      children: [
        FilledButton.icon(
          key: const Key('lala-new-test'),
          onPressed: athletes.isEmpty ? null : () => _begin(context, athletes),
          icon: const Icon(Icons.add),
          label: const Text('Neuer Test'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              vertical: GiuliaTokens.spacingM,
            ),
            textStyle: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (lactateImport != null) ...[
          SizedBox(height: density.cardGap),
          OutlinedButton.icon(
            key: const Key('lala-import-lactate'),
            onPressed: athletes.isEmpty
                ? null
                : () => _import(context, athletes),
            icon: const Icon(Icons.download_outlined),
            label: Text('${lactateImport!.sourceLabel} importieren'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                vertical: GiuliaTokens.spacingM,
              ),
            ),
          ),
          if (activityImport != null) ...[
            const SizedBox(height: GiuliaTokens.spacingXs),
            Text(
              '${activityImport!.sourceLabel} kann dabei als gemessener '
              'Belastungs- und Pulsverlauf zugeordnet werden.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
            ),
          ],
        ],
        if (activityImport != null) ...[
          SizedBox(height: density.cardGap),
          OutlinedButton.icon(
            key: const Key('lala-import-activity'),
            onPressed: athletes.isEmpty
                ? null
                : () => openActivityImport(
                    context,
                    controller: controller,
                    access: activityImport!,
                    athletes: athletes,
                  ),
            icon: const Icon(Icons.watch_outlined),
            label: Text('${activityImport!.sourceLabel}-Aktivität importieren'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                vertical: GiuliaTokens.spacingM,
              ),
            ),
          ),
        ],
        if (athletes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: GiuliaTokens.spacingS),
            child: Text(
              'Ein Test gehört zu einem Menschen. Zuerst einen Athleten '
              'anlegen.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
            ),
          ),
        if (open.isNotEmpty) ...[
          SizedBox(height: density.sectionGap),
          const GiuliaSectionHeader(title: 'Ohne Auswertung'),
          SizedBox(height: density.cardGap),
          for (final (athlete, entry) in open) ...[
            _TestRow(
              name: athlete.name,
              entry: entry,
              onOpen: () => _openTest(context, controller, entry.testId),
            ),
            SizedBox(height: density.cardGap),
          ],
        ],
        if (done.isNotEmpty) ...[
          SizedBox(height: density.sectionGap),
          const GiuliaSectionHeader(title: 'Letzte Tests'),
          SizedBox(height: density.cardGap),
          for (final (athlete, entry) in done.take(10)) ...[
            _TestRow(
              name: athlete.name,
              entry: entry,
              onOpen: () => _openTest(context, controller, entry.testId),
            ),
            SizedBox(height: density.cardGap),
          ],
        ],
        if (open.isEmpty && done.isEmpty && athletes.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: density.sectionGap),
            child: const GiuliaEmptyState(
              icon: Icons.biotech_outlined,
              title: 'Noch kein Test',
              description:
                  'Der erste Test beginnt oben. Alles Weitere ergibt sich '
                  'aus dem Protokoll.',
            ),
          ),
      ],
    );
  }

  /// Für wen — dann beginnt derselbe Testeditor für manuelle und gemessene
  /// Tests.
  ///
  /// Der frühere Weg sprang hier direkt in eine Gerätesitzung und verweigerte
  /// in der eigenständigen LaLa-App jeden neuen Test, obwohl der vollständige
  /// manuelle Editor bereits existierte. Jetzt ist das Gerät ein optionaler
  /// Messweg *innerhalb* des Tests und keine Zugangsvoraussetzung.
  /// Holt, was im Messgerät steht, und legt es einem Menschen vor.
  ///
  /// Drei Fragen in dieser Reihenfolge: für wen, was ist da, stimmt die
  /// Zuordnung. Die dritte beantwortet der [ImportReviewScreen] — und erst
  /// danach entsteht ein Test.
  Future<void> _import(BuildContext context, List<AthleteSummary> athletes) =>
      openLactateImport(
        context,
        controller: controller,
        access: lactateImport!,
        activityImport: activityImport,
        athletes: athletes,
      );

  Future<void> _begin(
    BuildContext context,
    List<AthleteSummary> athletes,
  ) async {
    final athlete = await showModalBottomSheet<AthleteSummary>(
      context: context,
      showDragHandle: true,
      builder: (context) => _ChoiceSheet(
        title: 'Für wen?',
        children: [
          for (final athlete in athletes)
            ListTile(
              title: Text(athlete.name),
              onTap: () => Navigator.of(context).pop(athlete),
            ),
        ],
      ),
    );
    if (athlete == null || !context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => LalaNewTestScreen(
          controller: controller,
          athleteId: athlete.id,
          athleteName: athlete.name,
          measuredTest: measuredTest,
          onOpenMeasuredResult: (testId) =>
              _openTest(context, controller, testId),
        ),
      ),
    );
    controller.refresh();
  }
}

/// Der vollständige Importweg, auch für Oberflächen, die nicht die
/// [TestsScreen]-Liste als Startseite verwenden.
Future<void> openLactateImport(
  BuildContext context, {
  required LalaController controller,
  required LactateImportAccess access,
  ActivityImportAccess? activityImport,
  List<AthleteSummary>? athletes,
}) async {
  final availableAthletes = athletes ?? controller.athletes;
  if (availableAthletes.isEmpty) {
    _say(context, 'Zuerst einen Athleten anlegen.');
    return;
  }
  final athlete = await _chooseImportAthlete(context, availableAthletes);
  if (athlete == null || !context.mounted) return;

  final LactateImportBatch batch;
  try {
    batch = await _fetchLactateWithProgress(context, access);
  } on Exception catch (failure) {
    if (context.mounted) {
      _say(context, 'Übertragung fehlgeschlagen: $failure');
    }
    return;
  }
  if (!context.mounted) return;
  final registry = ExternalImportRegistry(controller.diagnostics.database);
  final measurements = registry.unimported(batch.measurements);
  final group = await Navigator.of(context).push<MeasurementGroup>(
    MaterialPageRoute<MeasurementGroup>(
      fullscreenDialog: true,
      builder: (_) =>
          LactateImportSelectionScreen(batch: batch, unimported: measurements),
    ),
  );
  if (group == null || !context.mounted) return;
  final remaining = measurements.length - group.measurements.length;
  final importedActivity = activityImport == null
      ? null
      : await _chooseActivityImport(context, activityImport);
  if (!context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ImportReviewScreen(
        group: group,
        activity: importedActivity?.activity,
        sourceLabel: access.sourceLabel,
        onCreate: (review) async {
          try {
            final writer = ImportWriter(
              diagnostics: controller.diagnostics,
              observations: SqliteObservationRepository(
                controller.diagnostics.database,
              ),
            );
            final now = controller.clock();
            final imported = writer.write(
              review,
              organizationId: controller.session.organizationId,
              athleteId: athlete.id,
              actorUserId: controller.session.userId,
              nowUtcUs: now,
              idOf: (kind, ordinal) => 'import-$now-$kind-$ordinal',
            );
            controller.diagnostics.evaluate(
              testId: imported.testId,
              nowUtcUs: now,
              triggeredByUserId: controller.session.userId,
            );
            controller.refresh();
            if (!context.mounted) return;
            Navigator.of(context).pop();
            controller.selectAthlete(athlete.id);
            if (remaining > 0) {
              _say(
                context,
                '$remaining weitere neue '
                '${remaining == 1 ? 'Messung bleibt' : 'Messungen bleiben'} '
                'für den nächsten Import sichtbar.',
              );
            }
            _openTest(context, controller, imported.testId);
          } on Exception catch (failure) {
            if (context.mounted) {
              _say(context, 'Import fehlgeschlagen: $failure');
            }
          }
        },
      ),
    ),
  );
  controller.refresh();
}

/// Imports a complete external activity into the shared session archive.
Future<void> openActivityImport(
  BuildContext context, {
  required LalaController controller,
  required ActivityImportAccess access,
  List<AthleteSummary>? athletes,
}) async {
  final availableAthletes = athletes ?? controller.athletes;
  if (availableAthletes.isEmpty) {
    _say(context, 'Zuerst einen Athleten anlegen.');
    return;
  }
  final athlete = await _chooseImportAthlete(context, availableAthletes);
  if (athlete == null || !context.mounted) return;
  try {
    final imported = await access.pick();
    if (imported == null || !context.mounted) return;
    final result =
        ActivityImportRepository(
          controller.diagnostics.database,
          platform: controller.platform,
        ).write(
          imported,
          organizationId: controller.session.organizationId,
          athleteId: athlete.id,
          actorUserId: controller.session.userId,
          importedAtUtcUs: controller.clock(),
        );
    if (!context.mounted) return;
    if (result.alreadyImported) {
      final owners = availableAthletes.where(
        (candidate) => candidate.id == result.athleteId,
      );
      final owner = owners.isEmpty ? null : owners.first;
      _say(
        context,
        owner == null || owner.id == athlete.id
            ? 'Diese Aktivität wurde bereits importiert.'
            : 'Diese Aktivität ist bereits ${owner.name} zugeordnet.',
      );
    } else {
      _say(
        context,
        result.mergedWithExistingActivity
            ? '${imported.fileName}: als weitere Quelle derselben Aktivität '
                  'erkannt und nicht doppelt gezählt.'
            : '${imported.fileName}: ${result.samplesWritten} Messpunkte als '
                  'Training für ${athlete.name} importiert.',
      );
    }
  } on Exception catch (failure) {
    if (context.mounted) {
      _say(context, '${access.sourceLabel}-Import fehlgeschlagen: $failure');
    }
  }
}

Future<ExternalActivityImport?> _chooseActivityImport(
  BuildContext context,
  ActivityImportAccess access,
) async {
  final useActivity = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => _ChoiceSheet(
      title: 'Belastungsverlauf zuordnen?',
      children: [
        ListTile(
          key: const Key('import-activity-fit'),
          leading: const Icon(Icons.watch_outlined),
          title: Text('${access.sourceLabel}-Datei auswählen'),
          subtitle: const Text(
            'Leistung oder Tempo und Herzfrequenz werden über die Uhrzeit '
            'den Laktatproben zugeordnet.',
          ),
          onTap: () => Navigator.of(sheet).pop(true),
        ),
        ListTile(
          key: const Key('import-activity-skip'),
          leading: const Icon(Icons.arrow_forward),
          title: const Text('Ohne Aktivitätsdatei fortfahren'),
          subtitle: const Text(
            'Die Belastungen bleiben nominell aus dem gewählten Protokoll.',
          ),
          onTap: () => Navigator.of(sheet).pop(false),
        ),
      ],
    ),
  );
  if (useActivity != true || !context.mounted) return null;

  try {
    final imported = await access.pick();
    if (imported == null || !context.mounted) return null;
    final heartRateCount = imported.activity.samples
        .where((sample) => sample.heartRateBpm != null)
        .length;
    _say(
      context,
      '${imported.fileName}: ${imported.recordCount} Belastungspunkte, '
      '$heartRateCount Pulspunkte gelesen.',
    );
    if (imported.warnings.isNotEmpty) {
      _say(context, imported.warnings.join(' '));
    }
    return imported;
  } on Exception catch (failure) {
    if (context.mounted) {
      _say(context, '${access.sourceLabel}-Import fehlgeschlagen: $failure');
    }
    return null;
  }
}

Future<LactateImportBatch> _fetchLactateWithProgress(
  BuildContext context,
  LactateImportAccess access,
) async {
  final progress = ValueNotifier(LactateImportProgress.searching);
  var dialogOpen = true;
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder<LactateImportProgress>(
          valueListenable: progress,
          builder: (context, phase, _) => Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: GiuliaTokens.spacingM),
              Expanded(
                child: Text(phase.label, key: const Key('import-progress')),
              ),
            ],
          ),
        ),
      ),
    ),
  ).whenComplete(() => dialogOpen = false);

  try {
    return await access.fetch(
      onProgress: (phase) {
        progress.value = phase;
      },
    );
  } finally {
    if (dialogOpen && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    await dialog;
    progress.dispose();
  }
}

Future<AthleteSummary?> _chooseImportAthlete(
  BuildContext context,
  List<AthleteSummary> athletes,
) async {
  if (athletes.length == 1) return athletes.single;
  return showModalBottomSheet<AthleteSummary>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => _ChoiceSheet(
      title: 'Für wen?',
      children: [
        for (final athlete in athletes)
          ListTile(
            key: Key('import-athlete-${athlete.id}'),
            title: Text(athlete.name),
            onTap: () => Navigator.of(sheet).pop(athlete),
          ),
      ],
    ),
  );
}

void _openTest(
  BuildContext context,
  LalaController controller,
  String testId,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) =>
        LalaTestDetailScreen(controller: controller, testId: testId),
  ),
);

void _say(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));

class _TestRow extends StatelessWidget {
  const _TestRow({
    required this.name,
    required this.entry,
    required this.onOpen,
  });

  final String name;
  final LalaHistoryEntry entry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GiuliaPanel(
      onTap: onOpen,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(name, style: text.titleSmall)),
                    Text(
                      formatTestDate(entry.startedAtUtcUs),
                      style: text.bodySmall?.copyWith(
                        color: GiuliaTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GiuliaTokens.spacingXs),
                Text(
                  entry.hasResult
                      ? [
                          sportLabel(entry.sport),
                          if (entry.lt1Load != null)
                            'LTP1 ${formatLoad(entry.lt1Load, entry.loadUnit)}',
                          if (entry.lt2Load != null)
                            'LTP2 ${formatLoad(entry.lt2Load, entry.loadUnit)}',
                        ].join(' · ')
                      // Kein «Fortsetzen»: Eine unterbrochene Messung lässt
                      // sich nicht wieder aufnehmen. Was da ist, ist da.
                      : '${sportLabel(entry.sport)} · gemessen, noch '
                            'nicht ausgewertet',
                  style: text.bodySmall?.copyWith(
                    color: entry.hasResult
                        ? GiuliaTokens.textSecondary
                        : GiuliaTokens.warning,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: GiuliaTokens.spacingS),
          const Icon(Icons.chevron_right, color: GiuliaTokens.textMuted),
        ],
      ),
    );
  }
}

class _ChoiceSheet extends StatelessWidget {
  const _ChoiceSheet({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GiuliaTokens.spacingL,
            0,
            GiuliaTokens.spacingL,
            GiuliaTokens.spacingS,
          ),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Flexible(child: ListView(shrinkWrap: true, children: children)),
        const SizedBox(height: GiuliaTokens.spacingM),
      ],
    ),
  );
}
