/// Datenmodelle für Trainingsbelastung, Ermüdung und Form (TrainingPeaks-Standard).
///
/// Implementiert das Banister/Coggan Impulse-Response Modell:
/// - TSS: Training Stress Score einer einzelnen Einheit (Watt, HF oder RPE)
/// - ATL: Acute Training Load (Ermüdung, 7-Tage-Schnitt)
/// - CTL: Chronic Training Load (Belastung / Fitness, 42-Tage-Schnitt)
/// - TSB: Training Stress Balance (Form / Frische = CTL - ATL)
library;

import '../../domain/training_plan.dart';

enum TssMethod {
  power('Wattbasiert (FTP/LT2)'),
  heartRate('Herzfrequenzbasiert (LTHR)'),
  sufferScore('Strava Relative Effort / Suffer Score'),
  estimate('Schätzung nach Dauer und Intensität');

  const TssMethod(this.label);
  final String label;
}

class SessionTss {
  const SessionTss({
    required this.tss,
    required this.method,
    this.intensityFactor,
    this.durationSeconds = 0,
    this.sourceLabel,
  });

  final double tss;
  final TssMethod method;
  final double? intensityFactor;
  final int durationSeconds;
  final String? sourceLabel;
}

enum FormZone {
  detraining('Formverlust (Pause)', 'TSB > +25'),
  raceReady('Wettkampfbereit (Frische)', '+5 bis +25'),
  neutral('Ausgeglichen', '-10 bis +5'),
  optimalBuild('Optimaler Aufbau', '-30 bis -10'),
  highFatigue('Hohe Ermüdung', 'TSB < -30');

  const FormZone(this.label, this.rangeDescription);
  final String label;
  final String rangeDescription;
}

class DailyTrainingStress {
  const DailyTrainingStress({
    required this.day,
    required this.tss,
    required this.atl,
    required this.ctl,
    required this.tsb,
    this.activityCount = 0,
    this.totalDurationSeconds = 0,
  });

  final CalendarDay day;

  /// Summe des Trainingsstresses (TSS) an diesem Kalendertag.
  final double tss;

  /// Ermüdung (Acute Training Load, 7-Tage EMA).
  final double atl;

  /// Belastung / Fitness (Chronic Training Load, 42-Tage EMA).
  final double ctl;

  /// Form / Frische (Training Stress Balance = CTL - ATL).
  final double tsb;

  final int activityCount;
  final int totalDurationSeconds;

  FormZone get formZone {
    if (tsb > 25) return FormZone.detraining;
    if (tsb >= 5) return FormZone.raceReady;
    if (tsb >= -10) return FormZone.neutral;
    if (tsb >= -30) return FormZone.optimalBuild;
    return FormZone.highFatigue;
  }
}

class AthletePerformanceManagement {
  const AthletePerformanceManagement({
    required this.history,
    required this.currentDay,
    required this.ctl,
    required this.atl,
    required this.tsb,
    required this.rampRateWeekly,
    required this.formZone,
    required this.coachingSummary,
    this.projections = const [],
  });

  /// Chronologischer Verlauf von Belastung, Ermüdung und Form über alle Tage.
  final List<DailyTrainingStress> history;

  final CalendarDay currentDay;

  /// Aktuelle Fitness / Belastung (CTL, 42-Tage).
  final double ctl;

  /// Aktuelle Ermüdung (ATL, 7-Tage).
  final double atl;

  /// Aktuelle Form / Frische (TSB = CTL - ATL).
  final double tsb;

  /// Steigerungsrate von CTL der letzten 7 Tage.
  final double rampRateWeekly;

  final FormZone formZone;

  /// Coach-Bewertung in klaren Worten.
  final String coachingSummary;

  /// Hochrechnung bis zum Renntag (Tapering & Formaufbau).
  final List<DailyTrainingStress> projections;
}
