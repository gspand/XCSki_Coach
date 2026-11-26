/// Interner Debug- und Synchronisations-Bildschirm für den End-to-End Testbetrieb von GIULIA:
/// - Ercolina Session Status & Rohdaten-Zustand
/// - AthleteState & Core Version Inspektion
/// - Manuelle Daten-Wipe / Reset Möglichkeiten für Feldtests
library;

import 'package:flutter/material.dart';

import '../../database/coach_storage_repository.dart';
import '../../domain/normalized_session.dart';
import '../../external_data/strava/strava_sync_service.dart';
import '../../intelligence/workout_selection/coach_validation_mode.dart';
import '../../intelligence/xc_athlete_state/xc_athlete_state.dart';
import '../design_system.dart';

class DebugSyncScreen extends StatefulWidget {
  const DebugSyncScreen({
    super.key,
    required this.storage,
    required this.syncService,
    required this.athleteId,
    required this.currentState,
    this.onStateRefreshRequested,
  });

  final SqliteCoachStorageRepository storage;
  final StravaSyncService syncService;
  final String athleteId;
  final XCAthleteState currentState;
  final VoidCallback? onStateRefreshRequested;

  @override
  State<DebugSyncScreen> createState() => _DebugSyncScreenState();
}

class _DebugSyncScreenState extends State<DebugSyncScreen> {
  List<NormalizedSession> _recentSessions = const [];
  List<CoachValidationRecord> _validationRecords = const [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final sessions = widget.storage.loadNormalizedSessions(
      widget.athleteId,
      limit: 15,
    );
    final valRecords = widget.storage.loadValidationRecords(
      widget.athleteId,
      limit: 10,
    );
    setState(() {
      _recentSessions = sessions;
      _validationRecords = valRecords;
    });
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: GiuliaTokens.surface0,
      appBar: AppBar(
        title: const Text('GIULIA Debug & Sync Hub'),
        backgroundColor: GiuliaTokens.surface0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(GiuliaTokens.spacingM),
        children: [
          // 2. ATHLETE STATE & CORE STATUS
          _buildCard(
            title: 'COACH CORE & ATHLETE STATE',
            icon: Icons.memory,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kvRow('Core Baseline', 'Validation Baseline v1 (FROZEN)'),
                _kvRow('Athleten-ID', widget.athleteId),
                _kvRow(
                  'Datenabdeckung 28d',
                  '${28 - widget.currentState.dataCoverage.unknownDays28d} Tage (${(widget.currentState.dataCoverage.overallCoverageRatio * 100).round()} %)',
                ),
                _kvRow(
                  'Beobachtete Trainingstage',
                  '${widget.currentState.dataCoverage.observedTrainingDays28d} d',
                ),
                _kvRow(
                  'Persistierte Sessions',
                  '${_recentSessions.length} im Puffer geladen',
                ),
                _kvRow(
                  'Diagnostik Ercolina',
                  widget.currentState.diagnostics.hasCurrentErcolinaDiagnostics
                      ? 'Gültig (${widget.currentState.diagnostics.ercolina?.lt2Ltp2Watt?.round()} W)'
                      : 'Keine Messung',
                ),
                _kvRow(
                  'Diagnostik Skating',
                  widget.currentState.diagnostics.hasCurrentSkatingDiagnostics
                      ? 'Gültig'
                      : 'Keine Messung',
                ),
                _kvRow(
                  'Subjektive Erholung',
                  widget.currentState.subjectiveReadiness.perceivedRecovery !=
                          null
                      ? 'RPE ${widget.currentState.subjectiveReadiness.perceivedRecovery!.toStringAsFixed(1)}/10'
                      : 'Nicht erfasst',
                ),
              ],
            ),
          ),
          const SizedBox(height: GiuliaTokens.spacingM),

          // 3. PERSISTIERTE SESSIONS (NORMALIZED SESSIONS)
          _buildCard(
            title: 'ZULETZT GESPEICHERTE SESSIONS (${_recentSessions.length})',
            icon: Icons.history,
            child: _recentSessions.isEmpty
                ? const Text(
                    'Noch keine Sessions gespeichert. Starte einen Sync oder ein Ercolina Workout.',
                  )
                : Column(
                    children: [
                      for (final s in _recentSessions)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text('${s.title} (${s.modality.label})'),
                          subtitle: Text(
                            '${s.startedAtLocal} · ${s.durationMinutes.round()} min · Quelle: ${s.source.label}',
                          ),
                          trailing: s.externalMetrics.averagePowerWatt != null
                              ? Text(
                                  '${s.externalMetrics.averagePowerWatt!.round()} W',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : (s.internalMetrics.averageHeartRateBpm != null
                                    ? Text(
                                        '${s.internalMetrics.averageHeartRateBpm!.round()} bpm',
                                      )
                                    : null),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: GiuliaTokens.spacingM),

          // 4. AUTOMATISCHE VALIDATION RECORDS
          _buildCard(
            title:
                'AUTOMATISCHE VALIDATION RECORDS (${_validationRecords.length})',
            icon: Icons.fact_check_outlined,
            child: _validationRecords.isEmpty
                ? const Text('Noch keine Entscheidungen aufgezeichnet.')
                : Column(
                    children: [
                      for (final vr in _validationRecords)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(
                            '${vr.decision.actionType.name} · ${vr.timestamp.toLocal()}',
                          ),
                          subtitle: Text(
                            'ID: ${vr.scenarioId} · Core: ${vr.versions.coachCoreVersion}',
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: GiuliaTokens.surface1,
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusCard),
        border: Border.all(color: GiuliaTokens.border),
      ),
      padding: const EdgeInsets.all(GiuliaTokens.spacingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: GiuliaTokens.accent),
              const SizedBox(width: GiuliaTokens.spacingS),
              Text(
                title,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.bold,
                  color: GiuliaTokens.textSecondary,
                ),
              ),
            ],
          ),
          const Divider(
            height: GiuliaTokens.spacingL,
            color: GiuliaTokens.border,
          ),
          child,
        ],
      ),
    );
  }

  Widget _kvRow(String label, String value, {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: GiuliaTokens.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: isError ? GiuliaTokens.error : GiuliaTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
