import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:xc_coach/intelligence/training_need/training_need_engine.dart';
import 'package:xc_coach/intelligence/workout_selection/availability_context.dart';
import 'package:xc_coach/intelligence/workout_selection/daily_coaching_decision.dart';
import 'package:xc_coach/intelligence/workout_selection/daily_decision_engine.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/data_coverage_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/goal_context.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/ski_exposure_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/xc_athlete_state.dart';

void main() {
  group('Modality Exposure & Load Tolerance Gate Tests (Gold-Tests A–F)', () {
    const needEngine = TrainingNeedEngine();
    const decisionEngine = DailyDecisionEngine();
    const athleteId = 'athlete_modality_exposure_test';
    final asOf = DateTime.utc(2026, 10, 4, 10, 0);

    const goal50k = GoalContext(
      name: 'Engadin Skimarathon (50km)',
      modality: XcModality.skiSkating,
      targetDistanceMetres: 50000.0,
      targetDurationSeconds: 8100,
      priority: 'A',
    );

    test('Gold-Test A: Hohe aerobe Fitness, 0 Läufe in 90d, 180 min Zeitfenster -> Laufen strikt <= 45 min, Rad/Ski bevorzugt', () {
      // Athlet mit hoher aerober Fitness aus Radsport/Ercolina
      final state = XCAthleteState(
        athleteId: athleteId,
        asOf: asOf,
        goal: goal50k,
        skiExposure: const SkiSpecificExposureState(
          byModality: {
            XcModality.cycling: SkiModalityExposure(
              modality: XcModality.cycling,
              sessionCount90d: 40,
              durationSeconds90d: 144000,
              longestSessionSeconds90d: 14400, // 4h Radfahrt
            ),
            XcModality.running: SkiModalityExposure(
              modality: XcModality.running,
              sessionCount90d: 0,
              durationSeconds90d: 0,
              longestSessionSeconds90d: 0,
            ),
          },
        ),
      );

      final needResult = needEngine.evaluate(state: state);

      // Athlet hat heute 180 min Zeit, Laufen und Rad verfügbar (kein Schnee)
      final availability = DayAvailability(
        date: asOf,
        availableMinutes: 180,
        environment: TrainingEnvironment.outdoorTrailOrRoad,
        hasSnow: false,
        hasErcolina: true,
        hasRollerSki: false,
        hasBike: true,
        hasRunningShoes: true,
      );

      final decision = decisionEngine.decide(
        state: state,
        needResult: needResult,
        availability: availability,
      );

      // Verbotene Handlung: Niemals 3 Stunden oder > 45 min Laufen verschreiben!
      if (decision.prescribedWorkout != null && decision.prescribedWorkout!.modality == XcModality.running) {
        expect(decision.prescribedWorkout!.totalDurationMinutes, lessThanOrEqualTo(45));
      }

      // Bei 180 min verfügbar und Rad/Ercolina vorhanden wird für lange aerobe Basis Rad oder Ercolina gewählt
      expect(decision.actionType, CoachingActionType.prescribedWorkout);
      expect(decision.prescribedWorkout!.modality, isNot(XcModality.running));
      expect(decision.prescribedWorkout!.totalDurationMinutes, greaterThan(45));

      // Rejection Check: Lauf-Kandidaten, die 45 min überschreiten, wurden wegen Belastungstoleranz abgewiesen
      expect(
        decision.dataLimitations.any((lim) => lim.contains('Keine Laufhistorie in den letzten 90 Tagen')),
        isTrue,
      );
    });

    test('Gold-Test B: Geringe Laufexposition (3 Läufe in 90d, längster 40 min), 180 min Zeitfenster -> Laufen <= 50 min gedeckelt mit transparenter Begründung', () {
      final state = XCAthleteState(
        athleteId: athleteId,
        asOf: asOf,
        goal: goal50k,
        skiExposure: const SkiSpecificExposureState(
          byModality: {
            XcModality.running: SkiModalityExposure(
              modality: XcModality.running,
              sessionCount90d: 3,
              durationSeconds90d: 6000,
              longestSessionSeconds90d: 2400, // 40 min längster Lauf
            ),
          },
        ),
      );

      // Berechne die sichere Dosis direkt
      final maxSafe = decisionEngine.computeMaxSafeModalityMinutes(
        XcModality.running,
        state.skiExposure.exposureOf(XcModality.running),
        state.dataCoverage,
      );

      // Hier stand `expect(maxSafe, equals(50))` — 40 min mal dem Faktor
      // 1,25. Der Faktor war erfunden: Es gab keinen Grund fuer 1,25 statt
      // 1,2 oder 1,3, und er stand nur fuer Laufen im Code.
      //
      // [ModalityDoseModel] steigert nicht mit Faktoren, sondern in Stufen,
      // die die Bibliothek anbietet — und bei nur drei Einheiten in 90 Tagen
      // gar nicht: Dann gilt, was belegt ist. Weil die kuerzeste Laufeinheit
      // des Katalogs 45 min dauert, ist das hier die kleinste
      // verschreibbare Dosis.
      //
      // Die fachliche Zusage des Tests bleibt bestehen und wird hier
      // geprueft: deutlich unter dem Zeitfenster, in der Naehe des Belegten.
      expect(maxSafe, lessThanOrEqualTo(50));
      expect(maxSafe, greaterThanOrEqualTo(40));
      expect(maxSafe, lessThan(180), reason: 'Nicht das Zeitfenster.');

      // Nur Laufschuhe verfügbar, 180 min Zeitfenster
      final runOnlyAvailability = DayAvailability(
        date: asOf,
        availableMinutes: 180,
        environment: TrainingEnvironment.outdoorTrailOrRoad,
        hasSnow: false,
        hasErcolina: false,
        hasRollerSki: false,
        hasBike: false,
        hasRunningShoes: true,
      );

      final needResult = needEngine.evaluate(state: state);
      final decision = decisionEngine.decide(
        state: state,
        needResult: needResult,
        availability: runOnlyAvailability,
      );

      expect(decision.actionType, CoachingActionType.prescribedWorkout);
      final workout = decision.prescribedWorkout!;
      expect(workout.modality, XcModality.running);
      expect(workout.totalDurationMinutes, lessThanOrEqualTo(50));
      expect(
        decision.dataLimitations.any((lim) => lim.contains('Sehr geringe Laufexposition')),
        isTrue,
      );
    });

    test('Gold-Test C: Etablierter Läufer mit 120-min-Historie in 28d -> Längerer Lauf zulässig bis progressive Decke', () {
      final state = XCAthleteState(
        athleteId: athleteId,
        asOf: asOf,
        goal: goal50k,
        skiExposure: const SkiSpecificExposureState(
          byModality: {
            XcModality.running: SkiModalityExposure(
              modality: XcModality.running,
              sessionCount90d: 24,
              sessionCount28d: 8,
              durationSeconds90d: 72000,
              durationSeconds28d: 28800,
              longestSessionSeconds90d: 7200, // 120 min
              longestSessionSeconds28d: 7200, // 120 min
            ),
          },
        ),
      );

      final maxSafe = decisionEngine.computeMaxSafeModalityMinutes(
        XcModality.running,
        state.skiExposure.exposureOf(XcModality.running),
        state.dataCoverage,
      );

      // Etablierter Läufer: 120 min * 1.4 clamp(30, 120) = 120 min Decke
      expect(maxSafe, greaterThanOrEqualTo(90));
    });

    test('Gold-Test D: Datenabdeckung unvollständig (Unknown Days) -> Konservative Dosis und transparente Begrenzung in dataLimitations', () {
      final state = XCAthleteState(
        athleteId: athleteId,
        asOf: asOf,
        goal: goal50k,
        dataCoverage: const DataCoverageState(
          unknownDays28d: 6,
        ),
        skiExposure: const SkiSpecificExposureState(
          byModality: {
            XcModality.running: SkiModalityExposure(
              modality: XcModality.running,
              sessionCount90d: 0,
            ),
          },
        ),
      );

      final needResult = needEngine.evaluate(state: state);
      final availability = DayAvailability(
        date: asOf,
        availableMinutes: 120,
        environment: TrainingEnvironment.outdoorTrailOrRoad,
        hasSnow: false,
        hasErcolina: true,
        hasRollerSki: false,
        hasBike: false,
        hasRunningShoes: true,
      );

      final decision = decisionEngine.decide(
        state: state,
        needResult: needResult,
        availability: availability,
      );

      expect(
        decision.dataLimitations.any((l) => l.contains('Datenabdeckung der letzten 28 Tage unvollständig')),
        isTrue,
      );
      expect(
        decision.dataLimitations.any((l) => l.contains('Keine Laufhistorie in den letzten 90 Tagen vorhanden')),
        isTrue,
      );
    });

    test('Gold-Test E: 50k-Skating-Ziel + Schnee/Rollerski verfügbar -> Bevorzugt ski/rollerski/ercolina für lange Ausdauer vor Laufen', () {
      final state = XCAthleteState(
        athleteId: athleteId,
        asOf: asOf,
        goal: goal50k,
        skiExposure: const SkiSpecificExposureState(
          byModality: {
            XcModality.skiSkating: SkiModalityExposure(
              modality: XcModality.skiSkating,
              sessionCount90d: 15,
              durationSeconds90d: 54000,
              longestSessionSeconds90d: 7200,
            ),
            XcModality.running: SkiModalityExposure(
              modality: XcModality.running,
              sessionCount90d: 2,
              durationSeconds90d: 3600,
              longestSessionSeconds90d: 1800,
            ),
          },
        ),
      );

      final needResult = needEngine.evaluate(state: state);
      final availability = DayAvailability(
        date: asOf,
        availableMinutes: 150,
        environment: TrainingEnvironment.outdoorSnow,
        hasSnow: true,
        hasErcolina: true,
        hasRollerSki: true,
        hasBike: true,
        hasRunningShoes: true,
      );

      final decision = decisionEngine.decide(
        state: state,
        needResult: needResult,
        availability: availability,
      );

      expect(decision.actionType, CoachingActionType.prescribedWorkout);
      expect(decision.prescribedWorkout!.modality, equals(XcModality.skiSkating));
      expect(decision.prescribedWorkout!.totalDurationMinutes, greaterThanOrEqualTo(120));
    });

    test('Gold-Test F: 180 min Zeitfenster, sichere Laufdosis ist 45 min -> Prescribes 45 min, NICHT 180 min', () {
      // Nur Laufschuhe verfügbar, aber unbegrenzt Zeit
      final state = XCAthleteState(
        athleteId: athleteId,
        asOf: asOf,
        goal: goal50k,
        skiExposure: const SkiSpecificExposureState(
          byModality: {
            XcModality.running: SkiModalityExposure(
              modality: XcModality.running,
              sessionCount90d: 0, // Unaccustomed runner
            ),
          },
        ),
      );

      final needResult = needEngine.evaluate(state: state);
      final availability = DayAvailability(
        date: asOf,
        availableMinutes: 180,
        environment: TrainingEnvironment.outdoorTrailOrRoad,
        hasSnow: false,
        hasErcolina: false,
        hasRollerSki: false,
        hasBike: false,
        hasRunningShoes: true,
      );

      final decision = decisionEngine.decide(
        state: state,
        needResult: needResult,
        availability: availability,
      );

      expect(decision.actionType, CoachingActionType.prescribedWorkout);
      final workout = decision.prescribedWorkout!;
      expect(workout.modality, XcModality.running);
      expect(workout.totalDurationMinutes, equals(45));
      expect(workout.totalDurationMinutes, isNot(equals(180)));
    });
  });
}
