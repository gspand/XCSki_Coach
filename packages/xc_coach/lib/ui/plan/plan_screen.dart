/// GIULIA PLAN (Plan Screen) – Premium XC Coach Experience (V1).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE & UX-LEITPLANKEN:
/// - GIULIA darf sich NICHT wie ein starres Kalenderprogramm anfühlen.
/// - Informationshierarchie:
///   1. ZIEL: Target Goal Card oben (Name, Distanz/Technik, Countdown, Status).
///   2. WOCHE: 7-Tage-Karten («Diese Woche») mit klaren Zuständen:
///      completed, today, recommended, tentative, unavailable, skipped, modified.
///   3. SCHWERPUNKT: Warum diese Woche so geplant ist (abgeleitet aus Core-Needs).
///   4. ANPASSUNG / AUSFALL: Deutliche Banner mit Erklärung bei Planänderung oder Ausfall.
/// - iPad: Responsive Zwei-Spalten-Layout (links 7-Tage-Woche, rechts Tages-Detail-Panel).
/// - iPhone: Vertikaler, flüssiger Scroll-Flow mit Tagesauswahl.
library;

import 'package:flutter/material.dart';

import '../design_system.dart';
import 'plan_view_model.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({
    super.key,
    required this.viewModel,
    this.onSelectDay,
    this.onEditGoal,
    this.onStartWorkout,
    this.showAppBar = true,
  });

  final PlanViewModel viewModel;
  final ValueChanged<DayPlanItem>? onSelectDay;
  final VoidCallback? onEditGoal;
  final ValueChanged<String>? onStartWorkout;
  final bool showAppBar;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  late int _selectedDayIndex;

  @override
  void initState() {
    super.initState();
    _selectedDayIndex = widget.viewModel.activeDayIndex;
  }

  @override
  void didUpdateWidget(covariant PlanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      _selectedDayIndex = widget.viewModel.activeDayIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final isTablet = shortestSide >= 600;

    return Scaffold(
      backgroundColor: GiuliaTokens.surface0,
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: GiuliaTokens.surface0,
              elevation: 0,
              scrolledUnderElevation: 0,
              title: Text(
                'PLAN',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: GiuliaTokens.textPrimary,
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: isTablet
            ? _buildTabletLayout(context)
            : _buildPhoneLayout(context),
      ),
    );
  }

  // --- IPHONE LAYOUT ---
  Widget _buildPhoneLayout(BuildContext context) {
    final vm = widget.viewModel;
    final selectedDay = vm.days.isNotEmpty
        ? vm.days[_selectedDayIndex.clamp(0, vm.days.length - 1)]
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        _buildGoalCard(context, vm.goal),
        const SizedBox(height: GiuliaTokens.spacingL),
        if (vm.activeAdaptationBanner != null) ...[
          _buildAdaptationBanner(context, vm.activeAdaptationBanner!),
          const SizedBox(height: GiuliaTokens.spacingM),
        ],
        _buildWeekSectionHeader(context, vm),
        const SizedBox(height: GiuliaTokens.spacingS),
        _buildWeekDaysRow(context, vm),
        const SizedBox(height: GiuliaTokens.spacingL),
        if (selectedDay != null) _buildSelectedDayDetail(context, selectedDay),
        const SizedBox(height: GiuliaTokens.spacingL),
        _buildWeekFocusCard(context, vm.weekFocus),
      ],
    );
  }

  // --- IPAD SPLIT LAYOUT ---
  Widget _buildTabletLayout(BuildContext context) {
    final vm = widget.viewModel;
    final selectedDay = vm.days.isNotEmpty
        ? vm.days[_selectedDayIndex.clamp(0, vm.days.length - 1)]
        : null;

    return Padding(
      padding: const EdgeInsets.all(GiuliaTokens.spacingL),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Linke Spalte (Flex 7): Ziel, Woche, Schwerpunkt
          Expanded(
            flex: 7,
            child: ListView(
              children: [
                _buildGoalCard(context, vm.goal),
                const SizedBox(height: GiuliaTokens.spacingL),
                if (vm.activeAdaptationBanner != null) ...[
                  _buildAdaptationBanner(context, vm.activeAdaptationBanner!),
                  const SizedBox(height: GiuliaTokens.spacingM),
                ],
                _buildWeekSectionHeader(context, vm),
                const SizedBox(height: GiuliaTokens.spacingS),
                _buildWeekDaysRow(context, vm),
                const SizedBox(height: GiuliaTokens.spacingL),
                _buildWeekFocusCard(context, vm.weekFocus),
              ],
            ),
          ),
          const SizedBox(width: GiuliaTokens.spacingXl),
          // Rechte Spalte (Flex 5): Detail-Panel des ausgewählten Tags
          Expanded(
            flex: 5,
            child: selectedDay != null
                ? _buildSelectedDayDetail(context, selectedDay, elevated: true)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // --- ZIEL-KARTE (OBEN) ---
  Widget _buildGoalCard(BuildContext context, PlanGoalView goal) {
    final text = Theme.of(context).textTheme;

    return GiuliaPanel(
      tone: GiuliaTokens.surface1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: GiuliaTokens.accentSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'SAISONZIEL',
                  style: text.labelSmall?.copyWith(
                    color: GiuliaTokens.accent,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Spacer(),
              if (widget.onEditGoal != null)
                InkWell(
                  onTap: widget.onEditGoal,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      'Bearbeiten',
                      style: text.bodySmall?.copyWith(
                        color: GiuliaTokens.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.name,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      goal.detail,
                      style: text.bodyMedium?.copyWith(
                        color: GiuliaTokens.textSecondary,
                      ),
                    ),
                    if (goal.targetPaceText != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        goal.targetPaceText!,
                        style: text.bodySmall?.copyWith(
                          color: GiuliaTokens.accent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: GiuliaTokens.spacingM),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: GiuliaTokens.surface2,
                  borderRadius: BorderRadius.circular(GiuliaTokens.radiusM),
                  border: Border.all(color: GiuliaTokens.border),
                ),
                child: Text(
                  goal.countdownText,
                  style: text.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: GiuliaTokens.accent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- PLANANPASSUNGS-BANNER ---
  Widget _buildAdaptationBanner(BuildContext context, String bannerText) {
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(GiuliaTokens.spacingM),
      decoration: BoxDecoration(
        color: GiuliaTokens.surface1,
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusCard),
        border: Border.all(color: GiuliaTokens.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.tune_outlined,
            size: 20,
            color: GiuliaTokens.warning,
          ),
          const SizedBox(width: GiuliaTokens.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PLAN ANGEPASST',
                  style: text.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: GiuliaTokens.warning,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  bannerText,
                  style: text.bodyMedium?.copyWith(
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

  // --- WOCHEN-HEADER ---
  Widget _buildWeekSectionHeader(BuildContext context, PlanViewModel vm) {
    final text = Theme.of(context).textTheme;

    return Container(
      decoration:BoxDecoration(color:const Color(0xffe7efea),borderRadius:BorderRadius.circular(16)),
      padding:const EdgeInsets.symmetric(horizontal:16,vertical:12),
      child:Wrap(alignment:WrapAlignment.spaceBetween,crossAxisAlignment:WrapCrossAlignment.center,
        spacing:16,runSpacing:4,children:[
          Text('DIESE WOCHE',style:text.titleMedium?.copyWith(fontWeight:FontWeight.w700)),
          Text('${vm.weekFocus.plannedSessionsCount} Einheiten · ${vm.weekFocus.plannedHoursText}',
              style:text.bodyMedium?.copyWith(color:const Color(0xff245b4a))),
          if(vm.days.isNotEmpty) Text('${vm.days.first.shortDate} – ${vm.days.last.shortDate}',style:text.labelMedium),
        ]));
  }

  // --- 7-TAGE-ÜBERSICHT (KARTEN) ---
  Widget _buildWeekDaysRow(BuildContext context, PlanViewModel vm) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < vm.days.length; i++) ...[
            _buildDayCard(context, vm.days[i], i),
            if (i < vm.days.length - 1)
              const SizedBox(width: GiuliaTokens.spacingS),
          ],
        ],
      ),
    );
  }

  Widget _buildDayCard(BuildContext context, DayPlanItem item, int index) {
    final text = Theme.of(context).textTheme;
    final isSelected = index == _selectedDayIndex;

    Color badgeColor;
    Color badgeTextColor;
    switch (item.status) {
      case DayPlanStatus.completed:
        badgeColor = GiuliaTokens.accentSoft;
        badgeTextColor = GiuliaTokens.accent;
      case DayPlanStatus.today:
        badgeColor = GiuliaTokens.accent;
        badgeTextColor = Colors.white;
      case DayPlanStatus.recommended:
        badgeColor = GiuliaTokens.surface3;
        badgeTextColor = GiuliaTokens.textPrimary;
      case DayPlanStatus.unknown:
      case DayPlanStatus.tentative:
        badgeColor = GiuliaTokens.surface2;
        badgeTextColor = GiuliaTokens.textMuted;
      case DayPlanStatus.unavailable:
        badgeColor = GiuliaTokens.surface3;
        badgeTextColor = GiuliaTokens.textMuted;
      case DayPlanStatus.skipped:
        badgeColor = GiuliaTokens.error.withValues(alpha: 0.15);
        badgeTextColor = GiuliaTokens.error;
      case DayPlanStatus.modified:
        badgeColor = GiuliaTokens.warning.withValues(alpha: 0.2);
        badgeTextColor = GiuliaTokens.warning;
    }

    return InkWell(
      onTap: () {
        setState(() => _selectedDayIndex = index);
        widget.onSelectDay?.call(item);
      },
      borderRadius: BorderRadius.circular(GiuliaTokens.radiusM),
      child: Container(
        width: 116,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? GiuliaTokens.surface1 : GiuliaTokens.surface2,
          borderRadius: BorderRadius.circular(GiuliaTokens.radiusM),
          border: Border.all(
            color: isSelected
                ? GiuliaTokens.accent
                : (item.status == DayPlanStatus.today
                      ? GiuliaTokens.accent.withValues(alpha: 0.4)
                      : GiuliaTokens.border),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.weekdayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? GiuliaTokens.accent
                          : GiuliaTokens.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  item.shortDate,
                  style: text.bodySmall?.copyWith(
                    color: GiuliaTokens.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: GiuliaTokens.spacingS),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                item.status.label,
                style: text.labelSmall?.copyWith(
                  color: badgeTextColor,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: GiuliaTokens.spacingS),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: GiuliaTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.isRestDay ? 'Ruhetag' : '${item.durationMinutes} min',
              style: text.labelSmall?.copyWith(
                color: GiuliaTokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- DETAIL-PANEL DES AUSGEWÄHLTEN TAGES ---
  Widget _buildSelectedDayDetail(
    BuildContext context,
    DayPlanItem item, {
    bool elevated = false,
  }) {
    final text = Theme.of(context).textTheme;

    return GiuliaPanel(
      tone: GiuliaTokens.surface1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${item.weekdayName}, ${item.shortDate}',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: item.status == DayPlanStatus.today
                      ? GiuliaTokens.accentSoft
                      : GiuliaTokens.surface2,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.isTentative
                      ? 'VORAUSSICHTLICH'
                      : item.status.label.toUpperCase(),
                  style: text.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    color: item.status == DayPlanStatus.today
                        ? GiuliaTokens.accent
                        : GiuliaTokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          Text(
            item.title,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (item.decisionVersion != null)
            Text('${item.decisionId} · ${item.decisionVersion!.substring(0,10)}', style: text.labelSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.schedule_outlined,
                    size: 16,
                    color: GiuliaTokens.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.isRestDay
                        ? 'Keine Belastung'
                        : '${item.durationMinutes} Minuten',
                    style: text.bodyMedium?.copyWith(
                      color: GiuliaTokens.textSecondary,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.directions_run_outlined,
                    size: 16,
                    color: GiuliaTokens.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.modalityLabel,
                    style: text.bodyMedium?.copyWith(
                      color: GiuliaTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (item.missedNotice != null) ...[
            const SizedBox(height: GiuliaTokens.spacingM),
            Container(
              padding: const EdgeInsets.all(GiuliaTokens.spacingM),
              decoration: BoxDecoration(
                color: GiuliaTokens.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(GiuliaTokens.radiusM),
                border: Border.all(
                  color: GiuliaTokens.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: GiuliaTokens.error,
                  ),
                  const SizedBox(width: GiuliaTokens.spacingS),
                  Expanded(
                    child: Text(
                      item.missedNotice!,
                      style: text.bodySmall?.copyWith(
                        color: GiuliaTokens.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (item.adaptationNotice != null) ...[
            const SizedBox(height: GiuliaTokens.spacingM),
            Container(
              padding: const EdgeInsets.all(GiuliaTokens.spacingM),
              decoration: BoxDecoration(
                color: GiuliaTokens.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(GiuliaTokens.radiusM),
                border: Border.all(
                  color: GiuliaTokens.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.tune_outlined,
                    size: 18,
                    color: GiuliaTokens.warning,
                  ),
                  const SizedBox(width: GiuliaTokens.spacingS),
                  Expanded(
                    child: Text(
                      item.adaptationNotice!,
                      style: text.bodySmall?.copyWith(
                        color: GiuliaTokens.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (item.isTentative) ...[
            const SizedBox(height: GiuliaTokens.spacingM),
            Text(
              'Zukünftige Einheiten sind adaptive Richtwerte. GIULIA berechnet jeden Morgen auf Basis deiner tatsächlichen Erholung und Daten neu.',
              style: text.bodySmall?.copyWith(
                color: GiuliaTokens.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- WOCHENSCHWERPUNKT (WARUM) ---
  Widget _buildWeekFocusCard(BuildContext context, WeekFocusView focus) {
    final text = Theme.of(context).textTheme;

    return GiuliaPanel(
      tone: GiuliaTokens.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline,
                size: 20,
                color: GiuliaTokens.accent,
              ),
              const SizedBox(width: GiuliaTokens.spacingS),
              Expanded(
                child: Text(
                  'SCHWERPUNKT DIESER WOCHE',
                  style: text.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: GiuliaTokens.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: GiuliaTokens.spacingM),
          Text(
            focus.title,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: GiuliaTokens.spacingS),
          Text(
            focus.reasoning,
            style: text.bodyMedium?.copyWith(
              color: GiuliaTokens.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
