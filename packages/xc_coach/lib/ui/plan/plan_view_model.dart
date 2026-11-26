/// View Model für die PLAN-Ansicht (Wochenplanung & Zielkontext).
///
/// WICHTIGE ARCHITEKTUR-LEITPLANKEN:
/// - Striktes Drei-Schichten-Modell: Domain/Core -> ViewModel -> UI.
/// - Das ViewModel trifft KEINE eigenen Trainingsentscheidungen. Es formatiert
///   ausschließlich Daten aus dem gefrorenen Core und den Planungs-Repositories:
///   [TrainingGoal], [PlannedWorkout], [DayAvailability], [XCAthleteState], [TrainingNeedResult].
/// - Vergangenheit != Zukunft:
///   * Tage in der Vergangenheit: 'completed', 'skipped', 'modified'.
///   * Heute: 'today'.
///   * Zukünftige Tage: 'recommended', 'tentative', 'unavailable'.
/// - Zukünftige Einheiten tragen immer das Label «Voraussichtlich».
/// - Plananpassungen & verpasste Einheiten werden mit ruhigen, nachvollziehbaren Begründungen dargestellt.
library;

import '../../domain/training_plan.dart';
import '../../presentation/decision_card.dart';
import '../../domain/normalized_session.dart';
import '../../intelligence/planning/planning_models.dart';
import '../../intelligence/training_need/training_need_result.dart';
import '../../intelligence/workout_selection/daily_coaching_decision.dart';
import '../../intelligence/xc_athlete_state/xc_athlete_state.dart';

/// Status eines einzelnen Tags in der Wochenansicht.
enum DayPlanStatus {
  unknown('Offen'),
  completed('Absolviert'),
  today('Heute'),
  recommended('Empfohlen'),
  tentative('Voraussichtlich'),
  unavailable('Keine Zeit'),
  skipped('Nicht absolviert'),
  modified('Angepasst');

  const DayPlanStatus(this.label);
  final String label;
}

/// Repräsentation des Hauptwettkampf-/Saisonziels.
class PlanGoalView {
  const PlanGoalView({
    required this.name,
    required this.detail,
    required this.countdownText,
    required this.targetPaceText,
    required this.isConfigured,
  });

  final String name;
  final String detail;
  final String countdownText;
  final String? targetPaceText;
  final bool isConfigured;

  factory PlanGoalView.fromGoal(TrainingGoal? goal, CalendarDay today) {
    if (goal == null) {
      return const PlanGoalView(
        name: 'Kein Hauptziel festgelegt',
        detail: 'Lege ein Saisonziel fest, damit GIULIA deine Wochen gezielt periodisiert.',
        countdownText: 'Ziel definieren',
        targetPaceText: null,
        isConfigured: false,
      );
    }

    final day = goal.day;
    final String countdown;
    if (day == null) {
      countdown = 'Allgemeines Ziel';
    } else {
      // daysUntil in CalendarDay: other.difference(today). So today.daysUntil(day):
      final remaining = today.daysUntil(day);
      if (remaining > 0) {
        countdown = 'Noch $remaining Tage';
      } else if (remaining == 0) {
        countdown = 'Heute Wettkampf';
      } else {
        countdown = 'Vor ${-remaining} Tagen';
      }
    }

    final detailParts = <String>[
      if (goal.distanceKm != null) '${goal.distanceKm!.toStringAsFixed(0)} km',
      goal.modality.label,
      if (goal.targetSeconds != null) _formatClock(goal.targetSeconds!),
    ];

    String? pace;
    if (goal.targetSpeedKmh != null) {
      pace = 'Ziel-Geschw.: ${goal.targetSpeedKmh!.toStringAsFixed(1)} km/h';
    }

    return PlanGoalView(
      name: goal.name,
      detail: detailParts.join(' · '),
      countdownText: countdown,
      targetPaceText: pace,
      isConfigured: true,
    );
  }

  static String _formatClock(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }
}

/// Repräsentiert einen Tag in der 7-Tage-Wochenübersicht.
class DayPlanItem {
  const DayPlanItem({
    required this.day,
    required this.weekdayName,
    required this.shortDate,
    required this.status,
    required this.title,
    required this.durationMinutes,
    required this.modalityLabel,
    required this.isTentative,
    required this.isRestDay,
    this.intensityLabel,
    this.adaptationNotice,
    this.missedNotice,
    this.plannedWorkoutId,
    this.decisionId,
    this.decisionVersion,
  });

  final CalendarDay day;
  final String weekdayName;
  final String shortDate;
  final DayPlanStatus status;
  final String title;
  final int durationMinutes;
  final String modalityLabel;
  final bool isTentative;
  final bool isRestDay;
  final String? intensityLabel;
  final String? adaptationNotice;
  final String? missedNotice;
  final String? plannedWorkoutId;
  final String? decisionId;
  final String? decisionVersion;
}

/// Wochenschwerpunkt & sportwissenschaftliche Begründung.
class WeekFocusView {
  const WeekFocusView({
    required this.title,
    required this.reasoning,
    required this.plannedHoursText,
    required this.plannedSessionsCount,
  });

  final String title;
  final String reasoning;
  final String plannedHoursText;
  final int plannedSessionsCount;
}

/// Gesamtes View Model für die Plan-Ansicht.
class PlanViewModel {
  const PlanViewModel({
    required this.goal,
    required this.weekFocus,
    required this.days,
    required this.activeDayIndex,
    this.activeAdaptationBanner,
  });

  final PlanGoalView goal;
  final WeekFocusView weekFocus;
  final List<DayPlanItem> days;
  final int activeDayIndex;

  /// Wenn der Plan aufgrund von Überlastung oder Ausfall für die Woche modifiziert wurde.
  final String? activeAdaptationBanner;

  DayPlanItem get activeDay =>
      days.isNotEmpty ? days[activeDayIndex.clamp(0, days.length - 1)] : days.first;

  /// Erzeugt das PlanViewModel aus den realen Zustandsobjekten.
  factory PlanViewModel.build({
    required CalendarDay today,
    required TrainingGoal? primaryGoal,
    required List<PlannedWorkout> weekWorkouts,
    required WeeklyAvailability? availability,
    List<NormalizedSession> observed = const [],
    DailyCoachingDecision? todayDecision,
    XCAthleteState? state,
    TrainingNeedResult? needs,
    List<String> recentAdaptationReasons = const [],
    List<String> missedWorkoutNotes = const [],
  }) {
    final goalView = PlanGoalView.fromGoal(primaryGoal, today);

    // 1. Die 7 Tage der aktuellen Kalenderwoche berechnen (Montag bis Sonntag)
    final monday = today.weekStart;
    final weekDays = List.generate(7, (i) => monday.addDays(i));

    final items = <DayPlanItem>[];
    var totalMinutes = 0;
    var sessionCount = 0;

    for (final day in weekDays) {
      final isPast = day.isBefore(today);
      final isToday = day == today;
      final isFuture = !isPast && !isToday;

      final dayAvailability = availability?.on(day);
      final hasZeroTime = dayAvailability != null && dayAvailability.minutes == 0;

      // Vorhandene Workouts für diesen Tag
      final plannedForDay = weekWorkouts.where((w) => w.day == day).toList();
      final workout = plannedForDay.firstOrNull;

      final DayPlanStatus status;
      final String title;
      final int duration;
      final String modality;
      final bool isRest;
      String? intensity;
      String? adaptation;
      String? missed;

      final measured = observed.where((s) => CalendarDay.ofLocal(s.startedAtLocal) == day).toList();
      if (isPast) {
        if (measured.isNotEmpty) {
          status = DayPlanStatus.completed;
          title = measured.map((s) => s.title).join(' · ');
          duration = (measured.fold<int>(0,(sum,s)=>sum+s.movingTimeSeconds)/60).round();
          modality = measured.map((s) => s.modality.label).toSet().join(' / ');
          isRest = false;
        } else if (workout != null) {
          if (workout.status == PlannedWorkoutStatus.completed) {
            status = DayPlanStatus.completed;
            title = workout.goal;
            duration = (workout.durationSeconds / 60).round();
            modality = _modalityLabel(workout.sport);
            isRest = false;
            intensity = workout.intensity;
          } else if (workout.status == PlannedWorkoutStatus.skipped) {
            status = DayPlanStatus.skipped;
            title = 'Nicht absolviert';
            duration = (workout.durationSeconds / 60).round();
            modality = _modalityLabel(workout.sport);
            isRest = false;
            missed = 'Die Einheit wurde als ausgelassen markiert.';
          } else if (workout.status == PlannedWorkoutStatus.modified) {
            status = DayPlanStatus.modified;
            title = workout.goal;
            duration = (workout.durationSeconds / 60).round();
            modality = _modalityLabel(workout.sport);
            isRest = false;
            adaptation = 'Plan wurde situativ angepasst.';
          } else {
            status = DayPlanStatus.unknown;
            title = workout.goal;
            duration = (workout.durationSeconds / 60).round();
            modality = _modalityLabel(workout.sport);
            isRest = false;
            missed = 'Vergangene offene Einheit.';
          }
        } else {
          status = DayPlanStatus.unknown;
          title = 'Keine Einheit erfasst';
          duration = 0;
          modality = '';
          isRest = false;
        }
      } else if (isToday) {
        status = DayPlanStatus.today;
        if (todayDecision != null) {
          title = todayDecision.displayTitle;
          duration = todayDecision.displayMinutes;
          modality = todayDecision.displayModality;
          intensity = todayDecision.displayIntensity.label;
          isRest = todayDecision.actionType == CoachingActionType.restDay;
        } else if (workout != null) {
          title = workout.goal;
          duration = (workout.durationSeconds / 60).round();
          modality = _modalityLabel(workout.sport);
          isRest = false;
          intensity = workout.intensity;
        } else if (hasZeroTime) {
          title = 'Keine Zeit';
          duration = 0;
          modality = 'Regeneration';
          isRest = true;
        } else {
          title = 'Noch keine Tagesempfehlung';
          duration = 0;
          modality = 'Skispezifisch';
          isRest = false;
        }
      } else {
        // isFuture
        if (hasZeroTime) {
          status = DayPlanStatus.unavailable;
          title = 'Kein Zeitfenster';
          duration = 0;
          modality = 'Pause';
          isRest = true;
        } else if (workout != null) {
          status = DayPlanStatus.tentative;
          title = workout.goal;
          duration = (workout.durationSeconds / 60).round();
          modality = _modalityLabel(workout.sport);
          isRest = false;
          intensity = workout.intensity;
        } else {
          status = DayPlanStatus.tentative;
          title = 'Noch offen';
          duration = 0;
          modality = dayAvailability == null ? '' : 'Zeitfenster ${dayAvailability.minutes} min';
          isRest = false;
        }
      }

      if (!isRest && duration > 0) {
        totalMinutes += duration;
        sessionCount++;
      }

      items.add(
        DayPlanItem(
          day: day,
          weekdayName: _germanWeekday(day.weekday),
          shortDate: '${day.day}.${day.month}.',
          status: status,
          title: title,
          durationMinutes: duration,
          modalityLabel: modality,
          isTentative: isFuture,
          isRestDay: isRest,
          intensityLabel: intensity,
          adaptationNotice: adaptation,
          missedNotice: missed,
          plannedWorkoutId: workout?.id,
          decisionId: isToday ? todayDecision?.decisionId : null,
          decisionVersion: isToday ? todayDecision?.decisionVersion : null,
        ),
      );
    }

    // 2. Wochenschwerpunkt formulieren
    final hours = (totalMinutes / 60).toStringAsFixed(1);
    final focus = _deriveWeekFocus(
      goal: primaryGoal,
      needs: needs,
      state: state,
      totalHours: hours,
      sessionsCount: sessionCount,
    );

    // 3. Aktiver Index (heute)
    final todayIndex = weekDays.indexWhere((d) => d == today);

    // 4. Anpassungsbanner
    String? banner;
    if (recentAdaptationReasons.isNotEmpty) {
      banner = recentAdaptationReasons.first;
    } else if (missedWorkoutNotes.isNotEmpty) {
      banner = missedWorkoutNotes.first;
    }

    return PlanViewModel(
      goal: goalView,
      weekFocus: focus,
      days: items,
      activeDayIndex: todayIndex >= 0 ? todayIndex : 0,
      activeAdaptationBanner: banner,
    );
  }

  static String _modalityLabel(String sport) => switch (sport.toLowerCase()) {
    'ercolina' => 'Ercolina',
    'langlauf' || 'skating' || 'classic' => 'Langlauf',
    'cycling' || 'rad' => 'Rad',
    'running' || 'laufen' => 'Laufen',
    _ => 'Training',
  };

  static String _germanWeekday(int weekday) => switch (weekday) {
    DateTime.monday => 'Mo',
    DateTime.tuesday => 'Di',
    DateTime.wednesday => 'Mi',
    DateTime.thursday => 'Do',
    DateTime.friday => 'Fr',
    DateTime.saturday => 'Sa',
    DateTime.sunday => 'So',
    _ => '',
  };

  static WeekFocusView _deriveWeekFocus({
    TrainingGoal? goal,
    TrainingNeedResult? needs,
    XCAthleteState? state,
    required String totalHours,
    required int sessionsCount,
  }) {
    final primaryNeed = needs?.developmentNeeds.firstOrNull ?? needs?.maintenanceNeeds.firstOrNull;
    final title = primaryNeed?.type.label ?? 'Aerobe Basis & skispezifischer Umfang';
    final buffer = StringBuffer();

    if (goal != null) {
      buffer.write('Mit Blick auf ${goal.name} ');
    } else {
      buffer.write('In dieser Phase ');
    }

    if (primaryNeed != null) {
      buffer.write('steht die Entwicklung von ${primaryNeed.type.label.toLowerCase()} im Mittelpunkt. ');
      buffer.write(primaryNeed.reasons.join(' '));
    } else {
      buffer.write('steht die Stabilisierung der Grundlagenausdauer im Vordergrund. ');
      buffer.write('Zukünftige Tage bleiben adaptiv und passen sich deiner tatsächlichen Belastung an.');
    }

    return WeekFocusView(
      title: title,
      reasoning: buffer.toString(),
      plannedHoursText: '$totalHours Std.',
      plannedSessionsCount: sessionsCount,
    );
  }
}

extension on CalendarDay {
  int get weekday => DateTime.utc(year, month, day).weekday;
}
