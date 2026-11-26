/// Einheitlicher ANALYSE-Screen für alle Trainingsdaten (UX-5).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE & UX-LEITPLANKEN:
/// - Vereinheitlichte Session-Historie für alle Quellen: Ercolina, Garmin, Manuell.
/// - Sortiert: Neueste zuerst.
/// - Jede Session öffnet die kanonische 3-Block-Detailansicht:
///   1. Das Training (Modality, Duration, Work kJ, Power W, Tritt/Zugfrequenz, Distanz)
///   2. Deine Reaktion (Heart Rate, HR Zones, RPE, Laktat)
///   3. Was GIULIA gelernt hat (Erkannter Reiz, Erholungsbedarf, Auswirkung auf Zustand)
/// - Presentation entscheidet NICHT: Rendert ausschließlich das [SessionPresentationModel].
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/session_recap.dart';
import '../../app/session_report.dart';
import '../../database/coach_storage_repository.dart';
import '../../database/session_repository.dart';
import '../../domain/normalized_session.dart';
import '../../domain/normalized_session_adapters.dart';
import '../../domain/xc_modality.dart';
import '../../presentation/session_presentation_model.dart';
import '../design_system.dart';
import '../ercolina/session_inspector_screen.dart';
import '../session/session_report_screen.dart';

String _recordedDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '${h} h ${m} min ${s} s';
  return m > 0 ? '${m} min ${s} s' : '${s} s';
}

class UnifiedAnalysisScreen extends StatelessWidget {
  const UnifiedAnalysisScreen({
    super.key,
    required this.athleteId,
    this.athleteName,
    this.storage,
    this.sessions,
    this.explicitSessions,
    this.reports,
    this.recaps = const [],
    this.profiles = const [],
    this.onSelectProfile,
  });

  final String athleteId;
  final String? athleteName;
  final SqliteCoachStorageRepository? storage;
  final SessionRepository? sessions;
  final List<NormalizedSession>? explicitSessions;
  final SessionReportReader? reports;
  final List<SessionRecap> recaps;
  final List<({String id, String name})> profiles;
  final ValueChanged<String>? onSelectProfile;

  @override
  Widget build(BuildContext context) {
    // 1. Explizite Sessions oder aus CoachStorage laden
    final List<NormalizedSession> displaySessions;
    if (explicitSessions != null) {
      displaySessions = explicitSessions!.where((s) => s.athleteId == athleteId && s.eligibleForCoach).toList();
    } else {
      final normalizedSessions = storage?.loadNormalizedSessions(
            athleteId,
            toUtcUs: DateTime.now().toUtc().microsecondsSinceEpoch,
            limit: null,
          ) ??
          const [];

      if (normalizedSessions.isNotEmpty) {
        displaySessions = normalizedSessions;
      } else if (recaps.isNotEmpty) {
        displaySessions = [
          for (final r in recaps)
            ErcolinaRecapAdapter.toNormalized(
              r,
              athleteId: athleteId,
            ),
        ];
      } else {
        displaySessions = const [];
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Trainingsbuch')),
      body: _BookList(key: ValueKey(athleteId), entries: displaySessions,
        onOpen: (session) => _openSessionDetail(context,session),
        onInspect: kDebugMode && sessions != null ? (session) => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => SessionInspectorScreen(sessionId:session.id,sessions:sessions!))) : null,
        profileHeader: Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          if (profiles.length > 1) ...[
            GiuliaSectionHeader(
              title: 'Historie von',
              subtitle: athleteName != null ? 'Aktuell gewählt: $athleteName' : null,
            ),
            const SizedBox(height: GiuliaTokens.spacingS),
            Wrap(
              spacing: GiuliaTokens.spacingS,
              runSpacing: GiuliaTokens.spacingS,
              children: [
                for (final profile in profiles)
                  ChoiceChip(
                    avatar: const Icon(Icons.person, size: 16),
                    label: Text(profile.name),
                    selected: profile.id == athleteId,
                    showCheckmark: false,
                    selectedColor: GiuliaTokens.surface3,
                    onSelected: onSelectProfile == null ? null : (_) => onSelectProfile!(profile.id),
                  ),
              ],
            ),
            const SizedBox(height: GiuliaTokens.spacingL),
          ],
        ]),
      ),
    );
  }

  void _openSessionDetail(BuildContext context, NormalizedSession session) {
    final model = SessionPresentationModel.fromDomain(session: session);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SessionDetailScreen(
          model: model,
          session: session,
          legacyReport: session.source == NormalizedSessionSource.ercolina ? reports?.of(session.sourceId) : null,
        ),
      ),
    );
  }
}

class _BookList extends StatefulWidget {
  const _BookList({super.key,required this.entries,required this.profileHeader,required this.onOpen,this.onInspect});
  final List<NormalizedSession> entries;
  final Widget profileHeader;
  final ValueChanged<NormalizedSession> onOpen;
  final ValueChanged<NormalizedSession>? onInspect;
  @override
  State<_BookList> createState()=>_BookListState();
}

class _BookListState extends State<_BookList> {
  NormalizedSessionSource? source;
  @override
  Widget build(BuildContext context) {
    final all=widget.entries;
    final rows=source==null ? all : all.where((s)=>s.source==source).toList();
    final counts = <NormalizedSessionSource,int>{};
    for(final s in all){ counts.update(s.source,(n)=>n+1,ifAbsent:()=>1); }
    return ListView.builder(padding:const EdgeInsets.fromLTRB(20,10,20,24),
      itemCount:rows.length+1,itemBuilder:(ctx,i){
        if(i==0) return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          widget.profileHeader,
          Container(padding:const EdgeInsets.all(20),
            decoration:BoxDecoration(color:const Color(0xffe6efea),borderRadius:BorderRadius.circular(18)),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('Aufgezeichnete Einheiten',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w700)),
              const SizedBox(height:12),
              Wrap(spacing:8,runSpacing:4,children:[
                ChoiceChip(label:Text('Alle · ${all.length}'),selected:source==null,onSelected:(_)=>setState(()=>source=null)),
                for(final kind in {NormalizedSessionSource.garmin,...counts.keys})
                  ChoiceChip(label:Text('${kind==NormalizedSessionSource.garmin ? "Garmin / FIT" : kind.label} · ${counts[kind]??0}'),
                    selected:source==kind,onSelected:(_)=>setState(()=>source=kind)),
              ]),
            ])),
          const SizedBox(height:14),
          if(rows.isEmpty) Text(source==null ? 'Noch keine Einheiten vorhanden' : 'Keine Einheiten aus dieser Quelle im Trainingsbuch.'),
        ]);
        final row=rows[i-1];
        return Padding(padding:const EdgeInsets.only(bottom:8),child:_UnifiedSessionRow(session:row,
          onTap:()=>widget.onOpen(row),onInspect:widget.onInspect==null?null:()=>widget.onInspect!(row)));
      });
  }
}

class _UnifiedSessionRow extends StatelessWidget {
  const _UnifiedSessionRow({
    required this.session,
    required this.onTap,
    this.onInspect,
  });

  final NormalizedSession session;
  final VoidCallback onTap;
  final VoidCallback? onInspect;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final model = SessionPresentationModel.fromDomain(session: session);

    return GiuliaPanel(
      onTap: onTap,
      child: Row(
        children: [
          _SourceIcon(source: session.source, modality: session.modality),
          const SizedBox(width: GiuliaTokens.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        model.training.title,
                        style: text.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _recordedDuration(session.movingTimeSeconds),
                      style: text.labelMedium?.copyWith(
                        color: GiuliaTokens.accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GiuliaTokens.spacingXs),
                Text(
                  '${model.dateFormatted} · ${model.training.sourceLabel}',
                  style: text.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  _buildQuickStats(model),
                  style: text.bodySmall?.copyWith(color: GiuliaTokens.textSecondary),
                ),
              ],
            ),
          ),
          if (onInspect != null)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: 'Raw Inspector',
              onPressed: onInspect,
            ),
          const Icon(Icons.chevron_right, color: GiuliaTokens.textMuted),
        ],
      ),
    );
  }

  String _buildQuickStats(SessionPresentationModel model) {
    final parts = <String>[];
    if (model.training.averageStrokePowerWatt != null) {
      parts.add('Ø Zug ${model.training.averageStrokePowerWatt!}');
    } else if (model.training.averagePowerWatt != null) {
      parts.add(model.training.averagePowerWatt!);
    }
    if (model.reaction.averageHeartRateBpm != null) parts.add(model.reaction.averageHeartRateBpm!);
    if (model.training.distanceKm != null) parts.add(model.training.distanceKm!);
    if (model.training.strokeOrCadenceRate != null) parts.add(model.training.strokeOrCadenceRate!);
    return parts.isEmpty ? model.training.modalityLabel : parts.join(' · ');
  }
}

class _SourceIcon extends StatelessWidget {
  const _SourceIcon({required this.source, required this.modality});

  final NormalizedSessionSource source;
  final XcModality modality;

  @override
  Widget build(BuildContext context) {
    final IconData icon = switch (source) {
      NormalizedSessionSource.ercolina => Icons.fitness_center_rounded,
      NormalizedSessionSource.strava => Icons.sync_rounded,
      NormalizedSessionSource.garmin => Icons.watch_rounded,
      NormalizedSessionSource.manual => Icons.edit_note_rounded,
    };

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: GiuliaTokens.surface2,
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusM),
      ),
      child: Icon(icon, color: GiuliaTokens.accent, size: 20),
    );
  }
}

class _SessionDetailScreen extends StatelessWidget {
  const _SessionDetailScreen({
    required this.model,
    required this.session,
    this.legacyReport,
  });

  final SessionPresentationModel model;
  final NormalizedSession session;
  final dynamic legacyReport;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(model.training.title),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: GiuliaTokens.spacingL,
          vertical: GiuliaTokens.spacingM,
        ),
        children: [
          Text(
            model.dateFormatted,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
          ),
          const SizedBox(height: GiuliaTokens.spacingM),

          // BLOCK 1: DAS TRAINING
          const GiuliaSectionHeader(
            title: '1. Das Training',
            subtitle: 'Erbrachte mechanische Leistung und Umfänge (External Load)',
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          GiuliaPanel(
            child: Column(
              children: [
                _DetailRow(label: 'Sportart', value: model.training.modalityLabel),
                _DetailRow(label: 'Gesamtdauer', value: _recordedDuration(session.durationSeconds)),
                if (session.movingTimeSeconds != session.durationSeconds)
                  _DetailRow(label: 'Bewegungszeit', value: _recordedDuration(session.movingTimeSeconds)),
                if (model.training.workKiloJoule != null)
                  _DetailRow(label: 'Arbeit', value: model.training.workKiloJoule!),
                if (model.training.averageStrokePowerWatt != null)
                  _DetailRow(
                    label: 'Ø Zugleistung (Arbeitsphase)',
                    value: model.training.averageStrokePowerWatt!,
                  ),
                if (model.training.averagePowerWatt != null)
                  _DetailRow(
                    label: 'Ø Gesamtleistung (inkl. Pausen)',
                    value: model.training.averagePowerWatt!,
                  ),
                if (model.training.strokeOrCadenceRate != null)
                  _DetailRow(label: 'Frequenz', value: model.training.strokeOrCadenceRate!),
                if (model.training.distanceKm != null)
                  _DetailRow(label: 'Distanz', value: model.training.distanceKm!),
                if (model.training.symmetryText != null)
                  _DetailRow(label: 'Technik', value: model.training.symmetryText!),
              ],
            ),
          ),
          const SizedBox(height: GiuliaTokens.spacingL),

          // BLOCK 2: DEINE REAKTION
          const GiuliaSectionHeader(
            title: '2. Deine Reaktion',
            subtitle: 'Physiologische Antwort deines Körpers (Internal Load)',
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          GiuliaPanel(
            child: Column(
              children: [
                if (model.reaction.averageHeartRateBpm != null)
                  _DetailRow(label: 'Ø Herzfrequenz', value: model.reaction.averageHeartRateBpm!),
                if (model.reaction.peakHeartRateBpm != null)
                  _DetailRow(label: 'Max. Herzfrequenz', value: model.reaction.peakHeartRateBpm!),
                if (model.reaction.rpeText != null)
                  _DetailRow(label: 'Anstrengungsempfinden', value: model.reaction.rpeText!),
                if (model.reaction.lactateText != null)
                  _DetailRow(label: 'Laktatwert', value: model.reaction.lactateText!),
                if (model.reaction.hrZonesBreakdown.isNotEmpty)
                  _DetailRow(
                    label: 'Zonenverteilung',
                    value: model.reaction.hrZonesBreakdown.join(' · '),
                  ),
                if (model.reaction.averageHeartRateBpm == null && model.reaction.rpeText == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Keine physiologischen Reaktionsdaten (HF/RPE) für diese Einheit übermittelt.',
                      style: TextStyle(color: GiuliaTokens.textMuted),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: GiuliaTokens.spacingL),

          // BLOCK 3: WAS GIULIA GELERNT HAT
          const GiuliaSectionHeader(
            title: '3. Was GIULIA gelernt hat',
            subtitle: 'Sportwissenschaftliche Auswertung und Auswirkung auf deinen Zustand',
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          GiuliaPanel(
            tone: GiuliaTokens.surface2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(label: 'Erkannter Reiz', value: model.learnings.detectedStimulusText),
                _DetailRow(label: 'Belastungsverbuchung', value: model.learnings.loadImpactText),
                _DetailRow(label: 'Datenqualität', value: model.learnings.dataConfidenceText),
                const SizedBox(height: GiuliaTokens.spacingS),
                Text(
                  model.learnings.stateUpdateSummary,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: GiuliaTokens.accent,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: GiuliaTokens.spacingL),

          if (legacyReport != null)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SessionReportScreen(report: legacyReport),
                ),
              ),
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Ausführlichen Ercolina-Zugreport öffnen'),
            ),
          const SizedBox(height: GiuliaTokens.spacingXl),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: GiuliaTokens.textSecondary,
                  ),
            ),
          ),
          const SizedBox(width: GiuliaTokens.spacingM),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: GiuliaTokens.textPrimary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
