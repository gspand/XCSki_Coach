/// Need, Modalität und Dosis sind drei Fragen.
///
/// Ein Athlet kann einen großen Bedarf an langer aerober Arbeit haben und
/// trotzdem keine plausible Drei-Stunden-Laufdosis besitzen. Diese Datei hält
/// fest, dass GIULIA die dritte Frage aus den Daten beantwortet und nicht aus
/// dem Kalender.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/domain/normalized_session.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:xc_coach/intelligence/training_need/need_types.dart';
import 'package:xc_coach/intelligence/training_need/training_need_engine.dart';
import 'package:xc_coach/intelligence/workout_selection/availability_context.dart';
import 'package:xc_coach/intelligence/workout_selection/daily_coaching_decision.dart';
import 'package:xc_coach/intelligence/workout_selection/daily_decision_engine.dart';
import 'package:xc_coach/intelligence/workout_selection/modality_dose.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/data_coverage_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/goal_context.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/xc_athlete_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/xc_athlete_state_builder.dart';

const _athleteId = 'jan';
final _asOf = DateTime.utc(2026, 10, 5, 9);
const _model = ModalityDoseModel();

const _skatingGoal = GoalContext(
  name: 'Engadin 50k',
  modality: XcModality.skiSkating,
  targetDistanceMetres: 50000,
  targetDurationSeconds: 8100,
  priority: 'A',
);

/// Einheiten einer Modalität mit den angegebenen Dauern, absteigend in die
/// Vergangenheit verteilt.
List<NormalizedSession> sessionsOf(
  XcModality modality,
  List<int> minutes, {
  int spacingDays = 3,
}) => [
  for (final (index, m) in minutes.indexed)
    NormalizedSession(
      id: '${modality.key}_$index',
      athleteId: _athleteId,
      source: NormalizedSessionSource.garmin,
      sourceId: '${modality.key}_$index',
      startedAtUtcUs: _asOf
          .subtract(Duration(days: 2 + index * spacingDays))
          .microsecondsSinceEpoch,
      durationSeconds: m * 60,
      movingTimeSeconds: m * 60,
      modality: modality,
      technique: XcTechnique.unknown,
      isIndoor: modality == XcModality.ercolinaDoublePoling,
      title: modality.label,
    ),
];

XCAthleteState stateWith(
  List<NormalizedSession> sessions, {
  DataCoverageState? coverage,
}) {
  final built = const XCAthleteStateBuilder().buildState(
    athleteId: _athleteId,
    asOf: _asOf,
    goal: _skatingGoal,
    sessions: sessions,
  );
  return coverage == null ? built : built.copyWith(dataCoverage: coverage);
}

PlausibleDose doseOf(XCAthleteState state, XcModality modality) =>
    _model.doseFor(
      modality: modality,
      exposure: state.skiExposure.exposureOf(modality),
      coverage: state.dataCoverage,
    );

DailyCoachingDecision decide(XCAthleteState state, int availableMinutes) =>
    const DailyDecisionEngine().decide(
      state: state,
      needResult: const TrainingNeedEngine().evaluate(state: state),
      availability: DayAvailability(
        date: _asOf,
        availableMinutes: availableMinutes,
        environment: TrainingEnvironment.outdoorTrailOrRoad,
        hasSnow: false,
        hasErcolina: true,
        hasBike: true,
        hasRunningShoes: true,
      ),
    );

void main() {
  group('1. Keine aktuellen Läufe', () {
    test('viel Zeit macht aus null Läufen keine lange Laufdosis', () {
      // Gute Datenlage, viel Radausdauer, aber kein Lauf seit 90 Tagen.
      final state = stateWith(
        sessionsOf(XcModality.cycling, [180, 170, 165, 150, 160]),
        coverage: const DataCoverageState(unknownDays28d: 0),
      );

      final run = doseOf(state, XcModality.running);
      expect(run.evidence, ExposureEvidence.none);
      expect(
        run.ceilingMinutes,
        ModalityDoseModel.entryMinutesFor(XcModality.running),
      );

      final decision = decide(state, 240);
      final workout = decision.prescribedWorkout!;
      if (workout.modality == XcModality.running) {
        expect(
          workout.totalDurationMinutes,
          lessThanOrEqualTo(run.ceilingMinutes),
          reason: 'Ohne Laufhistorie nur die Einstiegsdosis.',
        );
      }
      expect(workout.totalDurationMinutes, lessThan(240));
    });
  });

  group('2. Regelmässiges Running', () {
    test('wiederholte lange Läufe tragen eine längere Dosis', () {
      final gelegentlich = doseOf(
        stateWith(sessionsOf(XcModality.running, [40, 35])),
        XcModality.running,
      );
      final regelmaessig = doseOf(
        stateWith(sessionsOf(XcModality.running, [75, 70, 72, 45, 50, 40])),
        XcModality.running,
      );

      expect(regelmaessig.evidence, ExposureEvidence.established);
      expect(regelmaessig.confidence, NeedConfidence.high);
      expect(
        regelmaessig.ceilingMinutes,
        greaterThan(gelegentlich.ceilingMinutes),
      );
      expect(regelmaessig.ceilingMinutes, greaterThanOrEqualTo(75));
    });
  });

  group('3. Running unbekannt', () {
    test('Datenlücken sind nicht null und senken die Zuversicht', () {
      final unbekannt = doseOf(
        stateWith(
          const [],
          coverage: const DataCoverageState(unknownDays28d: 25),
        ),
        XcModality.running,
      );
      final bekanntNull = doseOf(
        stateWith(
          sessionsOf(XcModality.cycling, [60, 55]),
          coverage: const DataCoverageState(unknownDays28d: 0),
        ),
        XcModality.running,
      );

      expect(unbekannt.evidence, ExposureEvidence.unknown);
      expect(unbekannt.confidence, NeedConfidence.unknown);
      // Der entscheidende Punkt: Unkenntnis ist nicht grosszuegiger.
      expect(
        unbekannt.ceilingMinutes,
        lessThanOrEqualTo(bekanntNull.ceilingMinutes),
      );
      expect(bekanntNull.confidence, NeedConfidence.high);
    });
  });

  group('4. Cycling gut etabliert', () {
    test('wiederholte lange Etappen tragen eine lange Dosis', () {
      // Die echte Lage aus den iPad-Daten: viele Einheiten, mehrere lange,
      // 368 und 364 min nebeneinander.
      final dose = doseOf(
        stateWith(
          sessionsOf(XcModality.cycling, [
            368,
            364,
            332,
            307,
            260,
            142,
            120,
            95,
          ], spacingDays: 7),
        ),
        XcModality.cycling,
      );

      expect(dose.evidence, ExposureEvidence.established);
      expect(dose.ceilingMinutes, greaterThanOrEqualTo(330));
      expect(dose.reason, contains('wiederholt belegt'));
    });
  });

  group('5. Ercolina-Testhistorie', () {
    test('Häufigkeit allein legitimiert keine lange Dosis', () {
      // 73 Einheiten, aber fast alle sehr kurz: Entwicklungsbetrieb.
      final dose = doseOf(
        stateWith(
          sessionsOf(XcModality.ercolinaDoublePoling, [
            for (var i = 0; i < 70; i++) 3,
            20,
            18,
            15,
          ], spacingDays: 0),
        ),
        XcModality.ercolinaDoublePoling,
      );

      expect(
        dose.ceilingMinutes,
        lessThan(60),
        reason: '73 Einheiten à drei Minuten sind keine Stunde Belastbarkeit.',
      );
      expect(dose.ceilingMinutes, lessThan(120));
    });
  });

  group('6. Verfügbarkeit ist eine Obergrenze', () {
    test('240 Minuten Zeit werden nicht zu 240 Minuten Training', () {
      final state = stateWith(
        sessionsOf(XcModality.cycling, [90, 85, 88, 60]),
        coverage: const DataCoverageState(unknownDays28d: 0),
      );

      final decision = decide(state, 240);
      final workout = decision.prescribedWorkout!;

      expect(workout.totalDurationMinutes, lessThan(240));
      expect(
        decision.coachingReason,
        isNot(contains('Zeitfenster optimal aus')),
        reason: 'Zeit zu füllen ist kein Trainingsziel.',
      );
    });
  });

  group('7. Zielspezifität', () {
    test('Transfer trennt Modalitäten, ohne Cross-Training zu verbieten', () {
      // Gleiche Exposition in Skating und Rad; das Ziel ist Skating.
      final state = stateWith([
        ...sessionsOf(XcModality.skiSkating, [90, 85, 88, 80], spacingDays: 5),
        ...sessionsOf(XcModality.cycling, [90, 85, 88, 80], spacingDays: 6),
      ]);

      final decision = decide(state, 120);
      final workout = decision.prescribedWorkout!;

      // Rad bleibt ein zulaessiger Kandidat — es gewinnt nur nicht gegen
      // gleich gut belegte Zielmodalitaet.
      expect(
        workout.modality,
        isNot(XcModality.running),
        reason: 'Laufen ist hier weder belegt noch spezifisch.',
      );
      expect(decision.coachingReason, isNotEmpty);
    });
  });

  group('8. Plan fordert zu hohe Dosis', () {
    test('die Entscheidung passt an und benennt die Abweichung', () {
      // Der Referenzfall: Der Plan will drei Stunden Laufen, der Athlet ist
      // seit 90 Tagen nicht gelaufen.
      final state = stateWith(
        sessionsOf(XcModality.cycling, [120, 110, 115, 100]),
        coverage: const DataCoverageState(unknownDays28d: 0),
      );
      final planned = PlannedWorkout(
        id: 'plan-1',
        organizationId: 'org',
        athleteId: _athleteId,
        day: CalendarDay.ofUtcUs(_asOf.microsecondsSinceEpoch),
        sport: 'running',
        goal: '3 h Lauf',
        durationSeconds: 3 * 3600,
        createdAtUtcUs: 1000,
        updatedAtUtcUs: 1000,
      );

      final decision = const DailyDecisionEngine().decide(
        state: state,
        needResult: const TrainingNeedEngine().evaluate(state: state),
        availability: DayAvailability(
          date: _asOf,
          availableMinutes: 240,
          environment: TrainingEnvironment.outdoorTrailOrRoad,
          hasSnow: false,
          hasErcolina: true,
          hasBike: true,
          hasRunningShoes: true,
        ),
        plannedWorkout: planned,
      );

      final workout = decision.prescribedWorkout!;
      expect(
        workout.totalDurationMinutes,
        lessThan(180),
        reason: 'Der Plan darf die Dosis nicht diktieren.',
      );
      if (workout.modality == XcModality.running) {
        final dose = doseOf(state, XcModality.running);
        expect(
          workout.totalDurationMinutes,
          lessThanOrEqualTo(dose.ceilingMinutes),
        );
      }
      // Und die Abweichung ist benannt, nicht stillschweigend.
      expect(decision.coachingReason, isNotEmpty);
    });
  });

  group('9. Gleicher Bedarf, andere Exposition', () {
    test('dieselbe Zeit, andere Historie, andere Dosis', () {
      final ohneLauf = stateWith(
        sessionsOf(XcModality.cycling, [120, 110, 115, 100]),
        coverage: const DataCoverageState(unknownDays28d: 0),
      );
      final mitLauf = stateWith(
        sessionsOf(XcModality.running, [80, 75, 78, 60, 55]),
        coverage: const DataCoverageState(unknownDays28d: 0),
      );

      final doseA = doseOf(ohneLauf, XcModality.running);
      final doseB = doseOf(mitLauf, XcModality.running);

      expect(doseA.ceilingMinutes, lessThan(doseB.ceilingMinutes));
      expect(doseA.evidence, ExposureEvidence.none);
      expect(doseB.evidence, ExposureEvidence.established);
    });
  });

  group('10. Mehr Zeit ändert die Verschreibung nicht von selbst', () {
    test('120 und 240 Minuten ergeben dieselbe Einheit', () {
      final state = stateWith(
        sessionsOf(XcModality.ercolinaDoublePoling, [60, 55, 58, 45, 50]),
        coverage: const DataCoverageState(unknownDays28d: 0),
      );

      final kurz = decide(state, 120).prescribedWorkout!;
      final lang = decide(state, 240).prescribedWorkout!;

      expect(
        lang.totalDurationMinutes,
        kurz.totalDurationMinutes,
        reason: 'Die Dosis kommt aus der Exposition, nicht aus dem Kalender.',
      );
      expect(lang.modality, kurz.modality);
    });
  });

  group('Die Regel selbst', () {
    test('Fortschritt ist eine Stufe des Katalogs, kein Faktor', () {
      // Die Stufen stehen in der Bibliothek, nicht in einer Formel. Skating
      // bietet 45, 50, 60, 65, 75, 80, 120, 150 und 180 Minuten.
      expect(ModalityDoseModel.nextVariantAbove(XcModality.skiSkating, 45), 50);
      expect(
        ModalityDoseModel.nextVariantAbove(XcModality.skiSkating, 80),
        120,
      );
      // Die Ercolina-Stufen kommen jetzt aus der Geraetebibliothek: nach 45
      // folgt E4 mit 55 Minuten, nicht eine handgeschriebene 60.
      expect(
        ModalityDoseModel.nextVariantAbove(XcModality.ercolinaDoublePoling, 45),
        55,
      );
      // Oberhalb der letzten Stufe gibt es keine — dann bleibt es beim
      // Belegten, statt eine Zahl zu erfinden.
      expect(
        ModalityDoseModel.nextVariantAbove(XcModality.skiSkating, 180),
        isNull,
      );
    });

    test('wo der Katalog keine zweite Stufe hat, steigert nichts', () {
      // Ein Produktbefund, kein Fehler des Modells: Fuer Laufen bietet die
      // Bibliothek genau eine Variante (45 min), fuer Rad genau eine
      // (60 min). Ein gut trainierter Laeufer kann deshalb nicht mehr als
      // 45 Minuten verschrieben bekommen — nicht weil die Dosis es verbietet,
      // sondern weil es nichts Laengeres gibt.
      //
      // Das Modell erfindet dafuer keine Dauer. Festgehalten, damit die
      // Luecke sichtbar bleibt und nicht als Dosisentscheidung missverstanden
      // wird.
      expect(
        ModalityDoseModel.nextVariantAbove(XcModality.running, 45),
        isNull,
      );
      expect(
        ModalityDoseModel.nextVariantAbove(XcModality.cycling, 60),
        isNull,
      );

      final guterLaeufer = doseOf(
        stateWith(sessionsOf(XcModality.running, [75, 70, 72, 45, 50, 40])),
        XcModality.running,
      );
      // Die Dosis erlaubt mehr als die Bibliothek anbietet …
      expect(guterLaeufer.ceilingMinutes, greaterThanOrEqualTo(75));
      // … verschrieben werden kann aber nur die eine Variante.
      final state = stateWith(
        sessionsOf(XcModality.running, [75, 70, 72, 45, 50, 40]),
        coverage: const DataCoverageState(unknownDays28d: 0),
      );
      final workout = decide(state, 240).prescribedWorkout!;
      if (workout.modality == XcModality.running) {
        expect(workout.totalDurationMinutes, 45);
      }
    });

    // Die Einstiegsdosis ist eine benannte Konstante der Belastungsart. Der
    // Katalog darf sie nicht verschieben — aber er muss sie treffen koennen,
    // sonst ist sie unerreichbar.
    test('die Einstiegsdosis ist als konkrete Einheit erreichbar', () {
      for (final modality in [
        XcModality.running,
        XcModality.cycling,
        XcModality.ercolinaDoublePoling,
        XcModality.skiSkating,
      ]) {
        final entry = ModalityDoseModel.entryMinutesFor(modality);
        expect(entry, greaterThan(0), reason: '${modality.name} ohne Familie?');
        expect(
          ModalityDoseModel.nextVariantAbove(modality, entry - 1),
          entry,
          reason: 'Die Einstiegsdosis ist die kleinste angebotene Stufe.',
        );
      }
    });

    test('die Regel ist versioniert', () {
      expect(modalityDoseModelVersion, 'giulia-modality-dose-v1');
    });
  });
}
