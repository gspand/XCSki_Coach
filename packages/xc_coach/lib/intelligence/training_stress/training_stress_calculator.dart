/// Berechnet die Trainingsbelastung, Ermüdung und Form (TrainingPeaks-Standard).
///
/// Führt Ercolina-Einheiten (aus der GIULIA-App) und direkt importierte Outdoor-Einheiten
/// zusammen und berechnet täglich TSS, ATL (7 Tage), CTL (42 Tage) und TSB.
library;

import 'dart:math' as math;

import '../../domain/training_plan.dart';
import '../planning/planning_models.dart';
import 'training_stress_models.dart';

class TrainingStressActivity {
  const TrainingStressActivity({
    required this.id,
    required this.title,
    required this.day,
    required this.durationSeconds,
    this.averageWatts,
    this.averageHeartRateBpm,
    this.isErcolina = false,
    this.explicitTss,
  });

  final String id;
  final String title;
  final CalendarDay day;
  final int durationSeconds;
  final double? averageWatts;
  final double? averageHeartRateBpm;
  final bool isErcolina;
  final double? explicitTss;


}

class TrainingStressCalculator {
  const TrainingStressCalculator({
    this.defaultThresholdWatt = 220.0,
    this.defaultThresholdHeartRate = 168.0,
  });

  /// Schwellenleistung (FTP / LT2) in Watt.
  final double defaultThresholdWatt;

  /// Schwellenherzfrequenz (LTHR / LT2) in bpm.
  final double defaultThresholdHeartRate;

  /// Berechnet den TSS (Training Stress Score) einer einzelnen Einheit.
  SessionTss calculateSessionTss(
    TrainingStressActivity activity, {
    double? athleteThresholdWatt,
    double? athleteThresholdHeartRate,
  }) {
    if (activity.explicitTss != null) {
      return SessionTss(
        tss: activity.explicitTss!,
        method: TssMethod.estimate,
        durationSeconds: activity.durationSeconds,
        sourceLabel: activity.title,
      );
    }

    final durationHours = activity.durationSeconds / 3600.0;
    if (durationHours <= 0) {
      return SessionTss(
        tss: 0.0,
        method: TssMethod.estimate,
        durationSeconds: 0,
        sourceLabel: activity.title,
      );
    }

    // 1. Wattbasierter TSS (Ercolina oder Rad/Ski-Powermeter)
    final ftp = athleteThresholdWatt ?? defaultThresholdWatt;
    if (activity.averageWatts != null && activity.averageWatts! > 0 && ftp > 0) {
      final intensityFactor = activity.averageWatts! / ftp;
      // Coggan TSS Formel: (sec * NP * IF) / (FTP * 3600) * 100
      final tss = durationHours * math.pow(intensityFactor, 2) * 100.0;
      return SessionTss(
        tss: double.parse(tss.toStringAsFixed(1)),
        method: TssMethod.power,
        intensityFactor: double.parse(intensityFactor.toStringAsFixed(2)),
        durationSeconds: activity.durationSeconds,
        sourceLabel: activity.title,
      );
    }

    // 2. Herzfrequenzbasierter hrTSS (der Standard beim Langlauf Skating!)
    final lthr = athleteThresholdHeartRate ?? defaultThresholdHeartRate;
    if (activity.averageHeartRateBpm != null &&
        activity.averageHeartRateBpm! > 0 &&
        lthr > 0) {
      final hrRatio = activity.averageHeartRateBpm! / lthr;
      // hrTSS approximiert die metabolische Belastung über das Verhältnis zur Schwelle:
      final tss = durationHours * math.pow(hrRatio, 2.1) * 100.0;
      return SessionTss(
        tss: double.parse(tss.toStringAsFixed(1)),
        method: TssMethod.heartRate,
        intensityFactor: double.parse(hrRatio.toStringAsFixed(2)),
        durationSeconds: activity.durationSeconds,
        sourceLabel: activity.title,
      );
    }

    // 4. Schätzung nach Dauer (mittlere GA1-Intensität ca. 55 TSS/Stunde)
    final estimatedTss = durationHours * 55.0;
    return SessionTss(
      tss: double.parse(estimatedTss.toStringAsFixed(1)),
      method: TssMethod.estimate,
      durationSeconds: activity.durationSeconds,
      sourceLabel: activity.title,
    );
  }

  /// Berechnet das vollständige Performance Management (ATL, CTL, TSB) über die Zeit.
  AthletePerformanceManagement calculate({
    required List<TrainingStressActivity> activities,
    required CalendarDay today,
    TrainingGoal? targetGoal,
    double? athleteThresholdWatt,
    double? athleteThresholdHeartRate,
    int lookbackDays = 60,
  }) {
    // 1. Tägliche TSS summieren
    final dailyTss = <CalendarDay, double>{};
    final dailyDuration = <CalendarDay, int>{};
    final dailyCount = <CalendarDay, int>{};

    for (final activity in activities) {
      final tss = calculateSessionTss(
        activity,
        athleteThresholdWatt: athleteThresholdWatt,
        athleteThresholdHeartRate: athleteThresholdHeartRate,
      ).tss;
      dailyTss.update(activity.day, (v) => v + tss, ifAbsent: () => tss);
      dailyDuration.update(
        activity.day,
        (v) => v + activity.durationSeconds,
        ifAbsent: () => activity.durationSeconds,
      );
      dailyCount.update(activity.day, (v) => v + 1, ifAbsent: () => 1);
    }

    // Frühester Tag bestimmen
    var startDay = today.addDays(-lookbackDays);
    if (activities.isNotEmpty) {
      for (final a in activities) {
        if (a.day.isBefore(startDay)) {
          startDay = a.day;
        }
      }
    }

    // 2. Exponential Moving Average für ATL (7d) und CTL (42d)
    final kAtl = 1.0 - math.exp(-1.0 / 7.0);
    final kCtl = 1.0 - math.exp(-1.0 / 42.0);

    var currentAtl = 0.0;
    var currentCtl = 0.0;

    final history = <DailyTrainingStress>[];
    var cursor = startDay;

    while (cursor.compareTo(today) <= 0) {
      final tss = dailyTss[cursor] ?? 0.0;
      final duration = dailyDuration[cursor] ?? 0;
      final count = dailyCount[cursor] ?? 0;

      currentAtl = currentAtl + (tss - currentAtl) * kAtl;
      currentCtl = currentCtl + (tss - currentCtl) * kCtl;
      final tsb = currentCtl - currentAtl;

      history.add(
        DailyTrainingStress(
          day: cursor,
          tss: double.parse(tss.toStringAsFixed(1)),
          atl: double.parse(currentAtl.toStringAsFixed(1)),
          ctl: double.parse(currentCtl.toStringAsFixed(1)),
          tsb: double.parse(tsb.toStringAsFixed(1)),
          activityCount: count,
          totalDurationSeconds: duration,
        ),
      );

      cursor = cursor.addDays(1);
    }

    // Ramp Rate: Steigerung von CTL über die letzten 7 Tage
    final sevenDaysAgo = today.addDays(-7);
    final pastCtl = history
        .where((h) => h.day == sevenDaysAgo)
        .firstOrNull
        ?.ctl ?? 0.0;
    final rampRateWeekly = double.parse((currentCtl - pastCtl).toStringAsFixed(1));

    // Aktuelle Formzone
    final latestTsb = currentCtl - currentAtl;
    final currentRecord = history.lastOrNull ??
        DailyTrainingStress(
          day: today,
          tss: 0,
          atl: currentAtl,
          ctl: currentCtl,
          tsb: latestTsb,
        );
    final formZone = currentRecord.formZone;

    // 3. Hochrechnung / Tapering bis zum Wettkampfziel (z. B. 50 km Skating)
    final projections = <DailyTrainingStress>[];
    if (targetGoal?.day case final goalDay? when goalDay.compareTo(today) > 0) {
      var projCursor = today.addDays(1);
      var pAtl = currentAtl;
      var pCtl = currentCtl;

      while (projCursor.compareTo(goalDay) <= 0) {
        final daysLeft = projCursor.daysUntil(goalDay);
        // Modelliert Tapering: In den letzten 10 Tagen sinkt das Volumen um 40-60%,
        // damit TSB am Renntag auf +10 bis +20 steigt!
        final taperFactor = daysLeft <= 10 ? (0.4 + (daysLeft / 10.0) * 0.4) : 1.0;
        final targetDailyTss = currentCtl * taperFactor;

        pAtl = pAtl + (targetDailyTss - pAtl) * kAtl;
        pCtl = pCtl + (targetDailyTss - pCtl) * kCtl;
        final pTsb = pCtl - pAtl;

        projections.add(
          DailyTrainingStress(
            day: projCursor,
            tss: double.parse(targetDailyTss.toStringAsFixed(1)),
            atl: double.parse(pAtl.toStringAsFixed(1)),
            ctl: double.parse(pCtl.toStringAsFixed(1)),
            tsb: double.parse(pTsb.toStringAsFixed(1)),
          ),
        );
        projCursor = projCursor.addDays(1);
      }
    }

    final summary = _generateCoachingSummary(
      ctl: currentCtl,
      atl: currentAtl,
      tsb: latestTsb,
      rampRate: rampRateWeekly,
      zone: formZone,
      goal: targetGoal,
      today: today,
    );

    return AthletePerformanceManagement(
      history: history,
      currentDay: today,
      ctl: double.parse(currentCtl.toStringAsFixed(1)),
      atl: double.parse(currentAtl.toStringAsFixed(1)),
      tsb: double.parse(latestTsb.toStringAsFixed(1)),
      rampRateWeekly: rampRateWeekly,
      formZone: formZone,
      coachingSummary: summary,
      projections: projections,
    );
  }

  static String _generateCoachingSummary({
    required double ctl,
    required double atl,
    required double tsb,
    required double rampRate,
    required FormZone zone,
    required TrainingGoal? goal,
    required CalendarDay today,
  }) {
    final parts = <String>[];

    switch (zone) {
      case FormZone.highFatigue:
        parts.add(
          'Hohe akute Ermüdung (TSB ${tsb.round()}). Die letzten Tage waren sehr fordernd. '
          'Heute steht aktive Erholung oder lockere Technik im Vordergrund.',
        );
      case FormZone.optimalBuild:
        parts.add(
          'Optimaler Trainingsaufbau (TSB ${tsb.round()}). Belastung und Ermüdung greifen '
          'ideal ineinander.',
        );
      case FormZone.neutral:
        parts.add(
          'Ausgeglichener Zustand (TSB ${tsb.round()}). Basis ist stabil, Raum für neue Reize '
          'ist vorhanden.',
        );
      case FormZone.raceReady:
        parts.add(
          'Hervorragende Frische und Wettkampfform (TSB +${tsb.round()}). Die Beine sind bereit '
          'für maximale Leistung.',
        );
      case FormZone.detraining:
        parts.add(
          'Hohe Frische bei sinkender Reizdichte (TSB +${tsb.round()}). Zeit für den nächsten '
          'gezielten Trainingsblock.',
        );
    }

    if (rampRate > 8.0) {
      parts.add('Achtung: Belastungsanstieg (+${rampRate.round()} TSS/Woche) ist sehr steil.');
    } else if (rampRate > 2.0) {
      parts.add('Der Aufbau verläuft mit +${rampRate.round()} TSS/Woche gleichmäßig.');
    }

    if (goal != null && goal.day != null) {
      final days = today.daysUntil(goal.day!);
      if (days > 0) {
        parts.add('Noch $days Tage bis ${goal.name}.');
      } else if (days == 0) {
        parts.add('Heute ist Renntag: ${goal.name}!');
      }
    }

    return parts.join(' ');
  }
}
