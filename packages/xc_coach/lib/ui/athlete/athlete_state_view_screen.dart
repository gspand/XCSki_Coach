/// ATHLET (Zustandsebene) – Premium XC Coach Experience (UX-4).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE & UX-LEITPLANKEN:
/// - Beantwortet in der ersten Bildschirmhöhe: «Wie stehe ich gerade da?»
/// - Hero: Athlet + Hauptziel + Countdown + 1 prägnanter Zustandssatz
/// - 4 Hauptbereiche via Progressive Disclosure:
///   1. Belastung & Erholung (bereits vorhanden via [LoadAndRecoverySection])
///   2. Leistungsfähigkeit (Aerobe Basis, Schwelle, HIT, Durability)
///   3. Langlauf-Spezifität (Schnee-Exposition 7d/28d, Doppelstock, Symmetrie)
///   4. Diagnostik & Daten (Status, Konfidenz, Datenabdeckung, Trace)
/// - Presentation entscheidet NICHT: Rendert ausschließlich das [AthletePresentationState].
library;

import 'package:flutter/material.dart';

import '../../app/athlete_ercolina_profile.dart';
import '../../app/mirco_preview.dart';
import '../../intelligence/load/stimulus_models.dart';
import '../../intelligence/xc_athlete_state/diagnostics_state.dart';
import '../../intelligence/xc_athlete_state/xc_athlete_state.dart';
import '../../presentation/athlete_presentation_state.dart';
import '../../presentation/canonical_terminology.dart';
import '../design_system.dart';
import 'athlete_elite_analysis.dart';
import 'athlete_load_snapshot.dart';
import 'athlete_scientific_charts.dart';
import 'load_and_recovery_section.dart';

class AthleteStateViewScreen extends StatefulWidget {
  const AthleteStateViewScreen({
    super.key,
    required this.athleteState,
    this.athleteName = 'Athlet',
    this.initialSectionAnchor,
    this.onAskGiulia,
    this.onEditProfile,
    this.ercolinaProfile,
    this.prioritizeErcolina = false,
  });

  final XCAthleteState athleteState;
  final String athleteName;
  final String? initialSectionAnchor;
  final VoidCallback? onAskGiulia;
  final VoidCallback? onEditProfile;
  final AthleteErcolinaProfile? ercolinaProfile;

  /// Put the device's measured power history first in the device product.
  /// The complete athlete evaluation remains available below it.
  final bool prioritizeErcolina;

  @override
  State<AthleteStateViewScreen> createState() => _AthleteStateViewScreenState();
}

class _TrainingDays extends StatelessWidget {
  const _TrainingDays({required this.state});
  final XCAthleteState state;
  @override
  Widget build(BuildContext context) {
    final data=state.dataCoverage;
    final days=[
      (data.observedTrainingDays28d,'Training',const Color(0xff17634f)),
      (data.confirmedRestDays28d,'Ruhe bestätigt',const Color(0xffa4c264)),
      (data.unknownDays28d,'Offen',const Color(0xffb8c4c0)),
    ];
    return Container(padding:const EdgeInsets.all(18),
      decoration:BoxDecoration(color:const Color(0xffeff4ef),borderRadius:BorderRadius.circular(18)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Deine letzten 28 Tage',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w700)),
        const SizedBox(height:12),
        if(days.any((d)=>d.$1>0)) ClipRRect(borderRadius:BorderRadius.circular(5),child:Row(children:[
          for(final d in days) if(d.$1>0) Expanded(flex:d.$1,child:ColoredBox(color:d.$3,child:const SizedBox(height:9)))
        ])),
        const SizedBox(height:10),
        Wrap(spacing:18,runSpacing:5,children:[for(final d in days) Text('${d.$1} · ${d.$2}')]),
      ]));
  }
}

class _AthleteStateViewScreenState extends State<AthleteStateViewScreen> {
  bool _longitudinalExpanded = true;
  bool _performanceExpanded = true;
  bool _xcExpanded = true;
  bool _doublePolingExpanded = true;
  bool _stimuliExpanded = false;
  bool _trendsExpanded = false;
  bool _evidenceExpanded = true;
  bool _diagnosticsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final presentation = AthletePresentationState.fromDomain(
      state: widget.athleteState,
      athleteName: widget.athleteName,
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: GiuliaTokens.spacingL,
            vertical: GiuliaTokens.spacingM,
          ),
          children: [
            if (widget.prioritizeErcolina &&
                widget.ercolinaProfile != null) ...[
              ErcolinaLongitudinalProfile(profile: widget.ercolinaProfile!),
              const SizedBox(height: GiuliaTokens.spacingL),
            ],
            // --- 1. HERO: ATHLET + ZIEL + COUNTDOWN + ZUSTANDSSATZ ---
            _HeroSection(hero: presentation.hero),
            const SizedBox(height: GiuliaTokens.spacingM),
            _TrainingDays(state:widget.athleteState),
            if (widget.athleteState.goal != null) ...[
              const SizedBox(height: GiuliaTokens.spacingM),
              _GoalDetailCard(state: widget.athleteState),
            ],
            const SizedBox(height: GiuliaTokens.spacingL),

            // --- BEREICH 1: BELASTUNG & ERHOLUNG ---
            LoadAndRecoverySection(
              key: const Key('section-load-and-recovery'),
              athleteState: widget.athleteState,
            ),
            const SizedBox(height: GiuliaTokens.spacingM),
            AthleteLoadTrendCard(athleteState: widget.athleteState),
            const SizedBox(height: GiuliaTokens.spacingL),

            _ExpandableSection(
              key: const Key('section-longitudinal-analysis'),
              title: previewText(
                'LANGZEIT & PERIODISIERUNG',
                'LONG-TERM DEVELOPMENT',
              ),
              subtitle: previewText(
                '7 / 28 / 90 / 180 / 365 Tage und gesamte Datenhistorie',
                '7 / 28 / 90 / 180 / 365 days and all-time history',
              ),
              isExpanded: _longitudinalExpanded,
              onToggle: () => setState(
                () => _longitudinalExpanded = !_longitudinalExpanded,
              ),
              content: AthleteEliteLongitudinalSection(
                athleteState: widget.athleteState,
                onEditPhysiology: widget.onEditProfile,
                ercolinaProfile: widget.prioritizeErcolina
                    ? null
                    : widget.ercolinaProfile,
              ),
            ),
            const SizedBox(height: GiuliaTokens.spacingL),

            // --- BEREICH 2: LEISTUNGSFÄHIGKEIT (Progressive Disclosure) ---
            _ExpandableSection(
              key: const Key('section-performance'),
              title: previewText(
                CanonicalTerminology.sectionPerformance,
                'PERFORMANCE',
              ),
              subtitle: previewText(
                'Aerobe Basis, Schwellen und Ermüdungsresistenz',
                'Aerobic base, thresholds and fatigue resistance',
              ),
              isExpanded: _performanceExpanded,
              onToggle: () =>
                  setState(() => _performanceExpanded = !_performanceExpanded),
              content: _PerformanceSectionContent(
                perf: presentation.performance,
                state: widget.athleteState,
              ),
            ),
            const SizedBox(height: GiuliaTokens.spacingL),

            // --- BEREICH 3: LANGLAUF-SPEZIFITÄT ---
            _ExpandableSection(
              key: const Key('section-xc-specificity'),
              title: previewText(
                CanonicalTerminology.sectionXcSpecificity,
                'CROSS-COUNTRY SPECIFICITY',
              ),
              subtitle: previewText(
                'Schnee-Exposition, Rollski und Oberkörper-Doppelstock',
                'Snow exposure, roller skiing and double poling',
              ),
              isExpanded: _xcExpanded,
              onToggle: () => setState(() => _xcExpanded = !_xcExpanded),
              content: _XcSpecificitySectionContent(
                xc: presentation.xcSpecificity,
                state: widget.athleteState,
              ),
            ),
            const SizedBox(height: GiuliaTokens.spacingL),

            _ExpandableSection(
              key: const Key('section-double-poling'),
              title: previewText(
                'DOPPELSTOCK & TECHNIK',
                'DOUBLE POLING & TECHNIQUE',
              ),
              subtitle: previewText(
                'Leistung, Zugökonomie, Symmetrie und Ermüdungsverhalten',
                'Power, work per stroke, symmetry and fatigue',
              ),
              isExpanded: _doublePolingExpanded,
              onToggle: () => setState(
                () => _doublePolingExpanded = !_doublePolingExpanded,
              ),
              content: _DoublePolingSectionContent(state: widget.athleteState),
            ),
            const SizedBox(height: GiuliaTokens.spacingL),

            _ExpandableSection(
              key: const Key('section-stimulus-ledger'),
              title: previewText('TRAININGSREIZE', 'TRAINING STIMULI'),
              subtitle: previewText(
                'Alle 14 Reize · geplant, beobachtet und verifiziert',
                'All 14 stimuli · planned, observed and verified',
              ),
              isExpanded: _stimuliExpanded,
              onToggle: () =>
                  setState(() => _stimuliExpanded = !_stimuliExpanded),
              content: _StimulusLedgerContent(state: widget.athleteState),
            ),
            const SizedBox(height: GiuliaTokens.spacingL),

            _ExpandableSection(
              key: const Key('section-performance-trends'),
              title: previewText('LEISTUNGSENTWICKLUNG', 'PERFORMANCE TRENDS'),
              subtitle:
                  'Nur vergleichbare Einheiten unter vergleichbaren Bedingungen',
              isExpanded: _trendsExpanded,
              onToggle: () =>
                  setState(() => _trendsExpanded = !_trendsExpanded),
              content: _PerformanceTrendsContent(state: widget.athleteState),
            ),
            const SizedBox(height: GiuliaTokens.spacingL),

            _ExpandableSection(
              key: const Key('section-best-evidence'),
              title: previewText(
                'BESTWERTE & EVIDENZLÜCKEN',
                'PERSONAL BESTS & MISSING DATA',
              ),
              subtitle: previewText(
                'Belegte persönliche Bestwerte und noch fehlende Messungen',
                'Recorded personal bests and measurements still needed',
              ),
              isExpanded: _evidenceExpanded,
              onToggle: () =>
                  setState(() => _evidenceExpanded = !_evidenceExpanded),
              content: AthleteEliteEvidenceSection(
                athleteState: widget.athleteState,
              ),
            ),
            const SizedBox(height: GiuliaTokens.spacingL),

            // --- BEREICH 4: DIAGNOSTIK & DATEN ---
            _ExpandableSection(
              key: const Key('section-diagnostics-and-data'),
              title: previewText(
                CanonicalTerminology.sectionDiagnosticsAndData,
                'DIAGNOSTICS & DATA',
              ),
              subtitle: previewText(
                'Lückenlose Rückverfolgbarkeit und Test-Referenzen',
                'Data provenance and test references',
              ),
              isExpanded: _diagnosticsExpanded,
              onToggle: () =>
                  setState(() => _diagnosticsExpanded = !_diagnosticsExpanded),
              content: _DiagnosticsSectionContent(
                diag: presentation.diagnosticsAndCoverage,
                state: widget.athleteState,
              ),
            ),
            const SizedBox(height: GiuliaTokens.spacingXl),

            if (widget.onAskGiulia != null)
              OutlinedButton.icon(
                onPressed: widget.onAskGiulia,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('GIULIA nach deinen Fortschritten fragen'),
              ),
            const SizedBox(height: GiuliaTokens.spacingXl),
          ],
        ),
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.hero});

  final AthleteHeroPresentation hero;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return GiuliaPanel(
      tone: GiuliaTokens.surface1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hero.athleteName,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: GiuliaTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: GiuliaTokens.spacingXs),
                    Text(
                      hero.goalTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        color: GiuliaTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (hero.daysUntilGoal != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GiuliaTokens.spacingM,
                    vertical: GiuliaTokens.spacingS,
                  ),
                  decoration: BoxDecoration(
                    color: GiuliaTokens.surface2,
                    borderRadius: BorderRadius.circular(GiuliaTokens.radiusM),
                    border: Border.all(color: GiuliaTokens.surface3),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${hero.daysUntilGoal}',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: GiuliaTokens.accent,
                        ),
                      ),
                      Text(
                        'Tage',
                        style: textTheme.labelSmall?.copyWith(
                          color: GiuliaTokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          const Divider(height: 1),
          const SizedBox(height: GiuliaTokens.spacingM),
          Row(
            children: [
              const Icon(
                Icons.insights_rounded,
                color: GiuliaTokens.accent,
                size: 20,
              ),
              const SizedBox(width: GiuliaTokens.spacingS),
              Expanded(
                child: Text(
                  hero.summarySentence,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: GiuliaTokens.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpandableSection extends StatelessWidget {
  const _ExpandableSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isExpanded,
    required this.onToggle,
    required this.content,
  });

  final String title;
  final String subtitle;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(GiuliaTokens.radiusM),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: GiuliaTokens.spacingXs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: GiuliaTokens.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: GiuliaTokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: GiuliaTokens.textMuted,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        if (isExpanded) content,
      ],
    );
  }
}

class _PerformanceSectionContent extends StatelessWidget {
  const _PerformanceSectionContent({required this.perf, required this.state});

  final PerformancePresentation perf;
  final XCAthleteState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MetricRow(
          label: 'Aerobe Grundlagenausdauer',
          detail: perf.aerobicBaseText,
          icon: Icons.directions_run_rounded,
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        _MetricRow(
          label: 'Schwellenleistungsfähigkeit (LTP2)',
          detail: perf.thresholdText,
          icon: Icons.speed_rounded,
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        _MetricRow(
          label: 'Hochintensive Kapazität (VO2max / HIT)',
          detail: perf.highIntensityText,
          icon: Icons.bolt_rounded,
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        _MetricRow(
          label: 'Durability / Ermüdungsresistenz',
          detail: perf.durabilityText,
          icon: Icons.battery_charging_full_rounded,
        ),
        const SizedBox(height: GiuliaTokens.spacingM),
        _DetailGrid(
          items: [
            (
              label: 'Grundlage 7 / 28 / 90 Tage',
              value:
                  '${_hours(state.aerobic.lowIntensityDurationSeconds7d)} / '
                  '${_hours(state.aerobic.lowIntensityDurationSeconds28d)} / '
                  '${_hours(state.aerobic.lowIntensityDurationSeconds90d)}',
            ),
            (
              label: 'Grundlageneinheiten 28 Tage',
              value: '${state.aerobic.aerobicSessionCount28d}',
            ),
            (
              label: 'Schwellenreize 28 Tage',
              value: '${state.threshold.thresholdSessionCount28d}',
            ),
            (
              label: 'HIT 28 Tage',
              value:
                  '${state.highIntensity.hitSessionCount28d} Einheiten · '
                  '${state.highIntensity.accumulatedZ5Minutes28d.toStringAsFixed(0)} min Z5',
            ),
            (
              label: 'Lange Einheiten 28 Tage',
              value:
                  '${state.durability.longSessionCount28d} · '
                  '${state.durability.longSessionExposureHours28d.toStringAsFixed(1)} h Exposition',
            ),
            (
              label: 'Gemessene Durability',
              value: state.durability.hasMeasuredObservations
                  ? '${state.durability.observations.length} Beobachtungen · '
                        '${_percent(state.durability.confidence)} Konfidenz'
                  : 'Nicht erfasst · Exposition ist kein Leistungsnachweis',
            ),
          ],
        ),
        if (state.aerobic.hrResponseTrend != null) ...[
          const SizedBox(height: GiuliaTokens.spacingS),
          _EvidenceNote(
            title: 'Kardiovaskulärer Trend',
            text: state.aerobic.hrResponseTrend!,
          ),
        ],
        if (state.durability.observations.isNotEmpty) ...[
          const SizedBox(height: GiuliaTokens.spacingS),
          for (final observation in state.durability.observations) ...[
            _EvidenceNote(
              title: observation.type.label,
              text:
                  '${observation.value?.toStringAsFixed(1) ?? 'Wert nicht erfasst'}'
                  '${observation.unit == null ? '' : ' ${observation.unit}'} · '
                  '${observation.conditions ?? 'Bedingungen nicht dokumentiert'} · '
                  '${_percent(observation.confidence)} Konfidenz',
            ),
            const SizedBox(height: GiuliaTokens.spacingXs),
          ],
        ],
      ],
    );
  }
}

class _GoalDetailCard extends StatelessWidget {
  const _GoalDetailCard({required this.state});

  final XCAthleteState state;

  @override
  Widget build(BuildContext context) {
    final goal = state.goal!;
    return GiuliaPanel(
      key: const Key('athlete-goal-detail'),
      tone: GiuliaTokens.surface2,
      child: _DetailGrid(
        items: [
          (label: 'Zielmodalität', value: goal.modality.label),
          (label: 'Priorität', value: '${goal.priority}-Ziel'),
          (
            label: 'Wettkampftag',
            value: goal.raceDate == null
                ? 'Nicht festgelegt'
                : _date(goal.raceDate),
          ),
          (
            label: 'Distanz',
            value: goal.targetDistanceKm == null
                ? 'Nicht festgelegt'
                : '${goal.targetDistanceKm!.toStringAsFixed(1)} km',
          ),
          (
            label: 'Zielzeit',
            value: goal.targetDurationSeconds == null
                ? 'Nicht festgelegt'
                : _duration(goal.targetDurationSeconds!),
          ),
          (
            label: 'Verfügbare Trainingszeit',
            value: goal.weeklyAvailableMinutes.isEmpty
                ? 'Nicht festgelegt'
                : '${goal.weeklyAvailableMinutes.values.fold<int>(0, (sum, value) => sum + value)} min / Woche',
          ),
        ],
      ),
    );
  }
}

class _DoublePolingSectionContent extends StatelessWidget {
  const _DoublePolingSectionContent({required this.state});

  final XCAthleteState state;

  @override
  Widget build(BuildContext context) {
    final dp = state.doublePoling;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailGrid(
          items: [
            (
              label: 'Jüngste Einheit Ø',
              value: _number(dp.recentSessionAveragePowerWatt, 'W'),
            ),
            (
              label: 'Arbeitsphasen Ø',
              value: _number(dp.workPhaseAveragePowerWatt, 'W'),
            ),
            (label: 'Spitzenleistung', value: _number(dp.peakPowerWatt, 'W')),
            (
              label: 'Arbeit 28 Tage',
              value: _number(dp.totalWorkKiloJoule28d, 'kJ'),
            ),
            (
              label: 'Zugfrequenz',
              value: _number(dp.recentStrokeRate, 'Züge/min'),
            ),
            (
              label: 'Arbeit pro Zug',
              value: _number(dp.recentWorkPerStrokeJoule, 'J'),
            ),
            (
              label: 'Links / Rechts',
              value: dp.leftRightBalancePercent == null
                  ? 'Nicht erfasst'
                  : '${dp.leftRightBalancePercent!.toStringAsFixed(1)} / '
                        '${(100 - dp.leftRightBalancePercent!).toStringAsFixed(1)} %',
            ),
            (
              label: 'Intervall-Wiederholbarkeit',
              value: dp.intervalRepeatabilityScore == null
                  ? 'Nicht erfasst'
                  : _percent(dp.intervalRepeatabilityScore!),
            ),
            (
              label: 'Leistungsabfall',
              value: _number(dp.powerDegradationPercent, '%'),
            ),
            (
              label: 'Zugmechanik-Abfall',
              value: _number(dp.strokeDegradationPercent, '%'),
            ),
            (
              label: 'Kalibrierung',
              value: dp.calibrationConfidence == null
                  ? 'Nicht erfasst'
                  : '${_percent(dp.calibrationConfidence!)} · '
                        '${dp.hasValidCalibration ? 'valide' : 'nicht diagnostisch valide'}',
            ),
            (
              label: 'Diagnostische Konfidenz',
              value: _percent(dp.diagnosticConfidence),
            ),
            (label: 'Letzte Einheit', value: _date(dp.lastSessionAt)),
          ],
        ),
        const SizedBox(height: GiuliaTokens.spacingM),
        _EvidenceNote(
          title: dp.hasValidCalibration
              ? 'Absolute Leistung interpretierbar'
              : 'Absolute Wattwerte mit Vorbehalt',
          text: dp.hasValidCalibration
              ? 'Die hinterlegte Kalibrierung erfüllt die diagnostische '
                    'Mindestgüte. Bedingungen und Provenienz bleiben für '
                    'Vergleiche trotzdem maßgeblich.'
              : 'Ohne valide aktuelle Kalibrierung sind absolute Wattwerte '
                    'kein belastbarer Diagnostikwert. Intraindividuelle '
                    'Vergleiche unter identischen Bedingungen bleiben möglich.',
        ),
        if (dp.intraIndividualTrend != null) ...[
          const SizedBox(height: GiuliaTokens.spacingS),
          _EvidenceNote(
            title: 'Intraindividueller Trend',
            text: dp.intraIndividualTrend!,
          ),
        ],
      ],
    );
  }
}

class _StimulusLedgerContent extends StatelessWidget {
  const _StimulusLedgerContent({required this.state});

  final XCAthleteState state;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      AthleteStimulusFrequencyChart(athleteState: state),
      const SizedBox(height: GiuliaTokens.spacingM),
      for (final type in StimulusType.values) ...[
        Builder(
          builder: (context) {
            final entry = state.stimulusHistory.entryFor(type);
            return _MetricRow(
              key: ValueKey('stimulus-${type.key}'),
              label: type.label,
              detail:
                  '${entry.frequency28d}× · '
                  '${entry.accumulatedExposureMinutes28d.toStringAsFixed(0)} min in 28 Tagen\n'
                  'Beobachtet: ${_date(entry.lastObservedAt)} · '
                  'Geplant: ${_date(entry.lastPlannedAt)} · '
                  'Verifiziert: ${_date(entry.lastVerifiedAt)} · '
                  '${entry.sourceModality?.label ?? 'Modalität nicht erfasst'} · '
                  '${_percent(entry.confidence)} Konfidenz',
              icon: _stimulusIcon(type),
            );
          },
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
      ],
    ],
  );
}

class _PerformanceTrendsContent extends StatelessWidget {
  const _PerformanceTrendsContent({required this.state});

  final XCAthleteState state;

  @override
  Widget build(BuildContext context) {
    final comparisons = state.performanceTrends.comparisons;
    if (comparisons.isEmpty) {
      return const _EvidenceNote(
        title: 'Noch kein belastbarer Leistungsvergleich',
        text:
            'Es fehlen zwei ausreichend vergleichbare Einheiten derselben '
            'Modalität und Struktur. Einzelne Bestwerte werden nicht zu einem '
            'Trend umgedeutet.',
      );
    }
    return Column(
      children: [
        for (final comparison in comparisons) ...[
          _MetricRow(
            label:
                '${comparison.modality.label} · ${comparison.comparisonType}',
            detail:
                '${comparison.evidenceSummary}\n'
                'Leistung Δ ${_delta(comparison.powerDeltaWatt, 'W')} · '
                'HF Δ ${_delta(comparison.hrDeltaAtComparablePower, 'bpm')} · '
                'RPE Δ ${_delta(comparison.rpeDeltaAtComparableWork, '')}\n'
                'von ${comparison.sessionAId} auf ${comparison.sessionBId} · '
                '${_percent(comparison.confidence)} Konfidenz',
            icon: Icons.trending_up_rounded,
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
        ],
      ],
    );
  }
}

class _XcSpecificitySectionContent extends StatelessWidget {
  const _XcSpecificitySectionContent({required this.xc, required this.state});

  final XcSpecificityPresentation xc;
  final XCAthleteState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MetricRow(
          label: 'Schnee-Exposition',
          detail: '${xc.snowExposure7d} · ${xc.snowExposure28d}',
          icon: Icons.ac_unit_rounded,
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        _MetricRow(
          label: 'Doppelstock / Oberkörper (Ercolina)',
          detail: xc.doublePolingPower,
          icon: Icons.fitness_center_rounded,
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        _MetricRow(
          label: 'Symmetrie Links / Rechts',
          detail: xc.techniqueSymmetry,
          icon: Icons.balance_rounded,
        ),
        const SizedBox(height: GiuliaTokens.spacingM),
        _DetailGrid(
          items: [
            (
              label: 'Skispezifisch 28 Tage',
              value:
                  '${_hours(state.skiExposure.totalSkiSpecificDurationSeconds28d)} · '
                  '${_percent(state.skiExposure.skiSpecificityRatio28d)} der erfassten Ausdauerzeit',
            ),
            (
              label: 'Davon Schnee / Rollski / Ercolina',
              value:
                  '${_hours(state.skiExposure.onSnowDurationSeconds28d)} / '
                  '${_hours(state.skiExposure.rollerSkiDurationSeconds28d)} / '
                  '${_hours(state.skiExposure.ercolinaDurationSeconds28d)}',
            ),
            (
              label: 'Unspezifische Ausdauer 28 Tage',
              value: _hours(state.skiExposure.totalNonSkiDurationSeconds28d),
            ),
          ],
        ),
        const SizedBox(height: GiuliaTokens.spacingM),
        AthleteModalityExposureChart(athleteState: state),
        const SizedBox(height: GiuliaTokens.spacingM),
        ..._modalityRows(state),
      ],
    );
  }

  List<Widget> _modalityRows(XCAthleteState state) {
    final exposures = state.skiExposure.byModality.values.toList()
      ..sort((a, b) => b.durationSeconds28d.compareTo(a.durationSeconds28d));
    if (exposures.isEmpty) {
      return const [
        _EvidenceNote(
          title: 'Modalitäten',
          text: 'Noch keine skispezifische Einheit erfasst.',
        ),
      ];
    }
    return [
      for (final exposure in exposures) ...[
        _MetricRow(
          label: exposure.modality.label,
          detail:
              '7 / 28 / 90 Tage: '
              '${exposure.durationHours7d.toStringAsFixed(1)} / '
              '${exposure.durationHours28d.toStringAsFixed(1)} / '
              '${exposure.durationHours90d.toStringAsFixed(1)} h · '
              '${exposure.sessionCount28d} Einheiten (28 T) · '
              '${exposure.daysSinceLastSession == null ? 'zuletzt nicht erfasst' : 'zuletzt vor ${exposure.daysSinceLastSession} Tagen'}',
          icon: exposure.modality.isSnowSkiing
              ? Icons.ac_unit_rounded
              : exposure.modality.isErcolina
              ? Icons.fitness_center_rounded
              : Icons.route_outlined,
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
      ],
    ];
  }
}

class _DiagnosticsSectionContent extends StatelessWidget {
  const _DiagnosticsSectionContent({required this.diag, required this.state});

  final DiagnosticsAndCoveragePresentation diag;
  final XCAthleteState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MetricRow(
          label: 'Leistungsdiagnostik-Status',
          detail: diag.diagnosticsStatus,
          icon: Icons.biotech_rounded,
        ),
        const SizedBox(height: GiuliaTokens.spacingS),
        _MetricRow(
          label: 'Konfidenz & Datenabdeckung',
          detail: '${diag.confidenceLabel} (${diag.coverageSummary})',
          icon: Icons.verified_user_outlined,
        ),
        const SizedBox(height: GiuliaTokens.spacingM),
        AthleteDataCoverageChart(athleteState: state),
        const SizedBox(height: GiuliaTokens.spacingM),
        _DetailGrid(
          items: [
            (
              label: 'Externe Aktivitäten',
              value: _percent(state.dataCoverage.externalActivityCoverage),
            ),
            (
              label: 'Ercolina',
              value: _percent(state.dataCoverage.ercolinaCoverage),
            ),
            (
              label: 'Herzfrequenz',
              value: _percent(state.dataCoverage.hrCoverage),
            ),
            (
              label: 'Leistung',
              value: _percent(state.dataCoverage.powerCoverage),
            ),
            (
              label: 'Subjektive Rückmeldung',
              value: _percent(state.dataCoverage.subjectiveCoverage),
            ),
            (
              label: 'Leistungsdiagnostik',
              value: _percent(state.dataCoverage.diagnosticsCoverage),
            ),
            (
              label: 'Tage 28 Tage',
              value:
                  '${state.dataCoverage.observedTrainingDays28d} Training · '
                  '${state.dataCoverage.confirmedRestDays28d} bestätigt frei · '
                  '${state.dataCoverage.unknownDays28d} unbekannt',
            ),
            (
              label: 'Letzte Synchronisation',
              value:
                  'Garmin ${_date(state.dataCoverage.lastGarminSync)} · '
                  'Ercolina ${_date(state.dataCoverage.lastErcolinaSession)}',
            ),
          ],
        ),
        const SizedBox(height: GiuliaTokens.spacingM),
        if (state.diagnostics.references.isEmpty)
          const _EvidenceNote(
            title: 'Sportartspezifische Diagnostik',
            text:
                'Nicht erfasst. Es werden keine Schwellen oder VO2max-Werte '
                'aus anderen Sportarten übertragen.',
          )
        else
          for (final reference in _sortedDiagnostics(state)) ...[
            _DiagnosticReferenceCard(reference: reference),
            const SizedBox(height: GiuliaTokens.spacingS),
          ],
        for (final entry in diag.traceDetails.entries) ...[
          _MetricRow(
            label: 'Evidenz: ${entry.key}',
            detail: entry.value,
            icon: Icons.timeline_rounded,
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
        ],
      ],
    );
  }
}

class _DiagnosticReferenceCard extends StatelessWidget {
  const _DiagnosticReferenceCard({required this.reference});

  final DiagnosticReference reference;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    key: ValueKey('diagnostic-${reference.modality.key}'),
    tone: GiuliaTokens.surface1,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.science_outlined, color: GiuliaTokens.accent),
            const SizedBox(width: GiuliaTokens.spacingS),
            Expanded(
              child: Text(
                reference.modality.label,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              reference.freshness.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: GiuliaTokens.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: GiuliaTokens.spacingM),
        _DetailGrid(
          items: [
            (label: 'Testdatum', value: _date(reference.date)),
            (label: 'Protokoll', value: reference.protocol),
            (
              label: 'LT1 / LTP1',
              value: _diagnosticValues(
                watt: reference.lt1Ltp1Watt,
                bpm: reference.lt1Ltp1Bpm,
                paceSeconds: reference.lt1Ltp1PaceSecPerKm,
              ),
            ),
            (
              label: 'LT2 / LTP2',
              value: _diagnosticValues(
                watt: reference.lt2Ltp2Watt,
                bpm: reference.lt2Ltp2Bpm,
                paceSeconds: reference.lt2Ltp2PaceSecPerKm,
              ),
            ),
            (
              label: 'VO2max',
              value: reference.vo2maxMlPerKgMin == null
                  ? 'Nicht erfasst'
                  : '${reference.vo2maxMlPerKgMin!.toStringAsFixed(1)} ml/kg/min',
            ),
            (
              label: 'HF max im Test',
              value: _number(reference.maxHeartRateBpm, 'bpm'),
            ),
            (
              label: 'Quelle',
              value:
                  '${reference.source}${reference.sourceId == null ? '' : ' · ${reference.sourceId}'}',
            ),
            (label: 'Konfidenz', value: _percent(reference.confidence)),
          ],
        ),
        if (reference.notes != null) ...[
          const SizedBox(height: GiuliaTokens.spacingS),
          Text(
            reference.notes!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: GiuliaTokens.textSecondary),
          ),
        ],
      ],
    ),
  );
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.items});

  final List<({String label, String value})> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 680 ? 3 : 2;
      final spacing = GiuliaTokens.spacingS;
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final item in items)
            SizedBox(
              width: width,
              child: Container(
                constraints: const BoxConstraints(minHeight: 72),
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
                      item.label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: GiuliaTokens.textMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.value,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: GiuliaTokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _EvidenceNote extends StatelessWidget {
  const _EvidenceNote({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
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
          title,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: GiuliaTokens.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    super.key,
    required this.label,
    required this.detail,
    required this.icon,
  });

  final String label;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GiuliaPanel(
      tone: GiuliaTokens.surface1,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: GiuliaTokens.accent, size: 20),
          const SizedBox(width: GiuliaTokens.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: GiuliaTokens.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: GiuliaTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<DiagnosticReference> _sortedDiagnostics(XCAthleteState state) {
  final references = state.diagnostics.references.values.toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  return references;
}

IconData _stimulusIcon(StimulusType type) => switch (type) {
  StimulusType.recovery => Icons.self_improvement_rounded,
  StimulusType.aerobicBase => Icons.favorite_outline_rounded,
  StimulusType.longEndurance => Icons.route_rounded,
  StimulusType.threshold => Icons.speed_rounded,
  StimulusType.vo2max => Icons.air_rounded,
  StimulusType.speedNeuromuscular => Icons.flash_on_rounded,
  StimulusType.maxStrength => Icons.fitness_center_rounded,
  StimulusType.explosiveStrength => Icons.bolt_rounded,
  StimulusType.muscularEndurance => Icons.repeat_rounded,
  StimulusType.doublePolingPower => Icons.vertical_align_top_rounded,
  StimulusType.doublePolingEndurance => Icons.swap_vert_rounded,
  StimulusType.technique => Icons.auto_graph_rounded,
  StimulusType.fatigueResistance => Icons.battery_charging_full_rounded,
  StimulusType.raceSpecific => Icons.flag_outlined,
};

String _hours(int seconds) => '${(seconds / 3600).toStringAsFixed(1)} h';

String _percent(double value) => '${(value * 100).toStringAsFixed(0)} %';

String _date(DateTime? value) =>
    value == null ? 'Nicht erfasst' : value.toIso8601String().split('T').first;

String _number(double? value, String unit) => value == null
    ? 'Nicht erfasst'
    : '${value.toStringAsFixed(1)}${unit.isEmpty ? '' : ' $unit'}';

String _delta(double? value, String unit) {
  if (value == null) return 'nicht erfasst';
  final sign = value >= 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(1)}${unit.isEmpty ? '' : ' $unit'}';
}

String _duration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainingSeconds = seconds % 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${remainingSeconds.toString().padLeft(2, '0')}';
}

String _diagnosticValues({
  required double? watt,
  required double? bpm,
  required double? paceSeconds,
}) {
  final values = <String>[];
  if (watt != null) values.add('${watt.toStringAsFixed(0)} W');
  if (bpm != null) values.add('${bpm.toStringAsFixed(0)} bpm');
  if (paceSeconds != null) {
    final minutes = paceSeconds ~/ 60;
    final seconds = (paceSeconds % 60).round();
    values.add('$minutes:${seconds.toString().padLeft(2, '0')} min/km');
  }
  return values.isEmpty ? 'Nicht erfasst' : values.join(' · ');
}
