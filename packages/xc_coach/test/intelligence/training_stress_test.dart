import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'package:xc_coach/intelligence/planning/planning_models.dart';
import 'package:xc_coach/intelligence/training_stress/training_stress_calculator.dart';
import 'package:xc_coach/intelligence/training_stress/training_stress_models.dart';

void main() {
  group('TrainingStressCalculator & TSS', () {
    const calc = TrainingStressCalculator(
      defaultThresholdWatt: 200,
      defaultThresholdHeartRate: 170,
    );

    test('berechnet Watt-TSS exakt nach Coggan-Formel', () {
      // 1 Stunde an der Schwelle (200 W bei 200 W FTP) ergibt genau 100 TSS!
      final activity = TrainingStressActivity(
        id: 'ercolina-1',
        title: 'Ercolina Schwellentraining',
        day: const CalendarDay(2026, 10, 1),
        durationSeconds: 3600,
        averageWatts: 200,
        isErcolina: true,
      );

      final result = calc.calculateSessionTss(activity);
      expect(result.method, TssMethod.power);
      expect(result.tss, closeTo(100.0, 0.5));
      expect(result.intensityFactor, closeTo(1.0, 0.05));
    });

    test('berechnet die Herzfrequenzlast für eine gemessene Skatingeinheit', () {
      const activity = TrainingStressActivity(id: 'measured', title: 'Skating',
          day: CalendarDay(2026, 10, 2), durationSeconds: 7200, averageHeartRateBpm: 145);
      final result = calc.calculateSessionTss(activity);

      expect(result.method, TssMethod.heartRate);
      // hrTSS ca. 2h * (145/170)^2.1 * 100 ≈ 140 TSS
      expect(result.tss, greaterThan(120));
      expect(result.tss, lessThan(160));
    });

    test('berechnet ATL, CTL, TSB und Formzone über die Zeit', () {
      const today = CalendarDay(2026, 10, 15);
      final goal = const TrainingGoal(
        name: '50 km Skating',
        day: CalendarDay(2026, 11, 20),
        modality: TrainingModality.skiSkating,
        distanceKm: 50,
        targetSeconds: 2 * 3600 + 15 * 60,
      );

      // Simulation von 14 Tagen regelmäßigem Training
      final activities = <TrainingStressActivity>[];
      for (var i = 14; i >= 1; i--) {
        final day = today.addDays(-i);
        activities.add(
          TrainingStressActivity(
            id: 'act-$i',
            title: 'Training Tag $i',
            day: day,
            durationSeconds: 3600,
            averageWatts: 180, // ca. 81 TSS
          ),
        );
      }

      final pmc = calc.calculate(
        activities: activities,
        today: today,
        targetGoal: goal,
      );

      expect(pmc.ctl, greaterThan(15));
      expect(pmc.atl, greaterThan(pmc.ctl)); // Nach 14 Tagen harter Reize ist ATL > CTL
      expect(pmc.tsb, lessThan(0)); // TSB negativ = akute Ermüdung
      expect(pmc.projections, isNotEmpty);
      expect(pmc.projections.last.day, goal.day);
      // Durch Tapering in den Projektionen steigt TSB zum Renntag an
      expect(pmc.projections.last.tsb, greaterThan(pmc.tsb));
    });
  });
}
