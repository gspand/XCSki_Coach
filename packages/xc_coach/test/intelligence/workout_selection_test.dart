import 'package:xc_coach/intelligence/xc_athlete_state/elite_analysis_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/app/coach_plan_service.dart'
    show blueprintById;
import 'package:xc_coach/domain/normalized_session.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:xc_coach/intelligence/load/stimulus_models.dart';
import 'package:xc_coach/intelligence/training_need/need_types.dart';
import 'package:xc_coach/intelligence/training_need/safety_constraint.dart';
import 'package:xc_coach/intelligence/training_need/training_need.dart';
import 'package:xc_coach/intelligence/training_need/training_need_engine.dart';
import 'package:xc_coach/intelligence/training_need/training_need_result.dart';
import 'package:xc_coach/intelligence/workout_selection/availability_context.dart';
import 'package:xc_coach/intelligence/workout_selection/closed_loop_simulator.dart';
import 'package:xc_coach/intelligence/workout_selection/daily_coaching_decision.dart';
import 'package:xc_coach/intelligence/workout_selection/daily_decision_engine.dart';
import 'package:xc_coach/intelligence/workout_selection/intensity_prescription.dart';
import 'package:xc_coach/intelligence/workout_selection/user_override_context.dart';
import 'package:xc_coach/intelligence/workout_selection/workout_candidate.dart';
import 'package:xc_coach/intelligence/workout_selection/workout_family.dart';
import 'package:xc_coach/intelligence/workout_selection/workout_prescription.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/diagnostics_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/evidence_model.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/goal_context.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/subjective_readiness_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/xc_athlete_state_builder.dart';

void main() {
  group('Schritt 5 – Workout Selection & Daily Coaching Decision (30 Kern-Tests)', () {
    const builder = XCAthleteStateBuilder();
    const needEngine = TrainingNeedEngine();
    const decisionEngine = DailyDecisionEngine();
    const simulator = ClosedLoopSimulator();
    const athleteId = 'athlete_step5_test';
    final asOf = DateTime.utc(2026, 10, 3, 10, 0);

    const goal50k = GoalContext(
      name: 'Engadin Skimarathon',
      modality: XcModality.skiSkating,
      targetDistanceMetres: 50000.0,
      targetDurationSeconds: 8100,
      priority: 'A',
    );

    List<NormalizedSession> establishedHistory(DateTime day) => [
      for (final modality in [
        XcModality.skiSkating,
        XcModality.ercolinaDoublePoling,
      ])
        for (var i = 0; i < 6; i++)
          NormalizedSession(
            id: 'history-${modality.name}-$i',
            title: 'Established base',
            athleteId: athleteId,
            source: NormalizedSessionSource.garmin,
            sourceId: 'history-${modality.name}-$i',
            startedAtUtcUs: day
                .subtract(Duration(days: 4 + i * 4))
                .microsecondsSinceEpoch,
            durationSeconds: 5400,
            movingTimeSeconds: 5400,
            modality: modality,
            isIndoor: modality == XcModality.ercolinaDoublePoling,
            internalMetrics: const SessionInternalMetrics(
              timeInHrZonesSeconds: {'z2': 5400},
            ),
          ),
    ];

    // Standardmäßige Verfügbarkeit: 60 Minuten, Schnee und Ercolina vorhanden
    final standardAvailability = DayAvailability(
      date: asOf,
      availableMinutes: 60,
      environment: TrainingEnvironment.outdoorSnow,
      hasSnow: true,
      hasErcolina: true,
      hasRollerSki: true,
      hasBike: true,
      hasRunningShoes: true,
    );

    test(
      '1. Infektsymptome lösen sofort Ruhetag aus (Severe Safety Filter)',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          subjectiveReadiness: SubjectiveReadinessState(
            recordedAt: asOf,
            illnessSymptoms: const ['Fieber', 'Halsschmerzen'],
          ),
        );

        final needResult = needEngine.evaluate(state: state);
        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: standardAvailability,
        );

        expect(decision.actionType, CoachingActionType.restDay);
        expect(decision.coachingReason, contains('Infekt'));
        expect(decision.prescribedWorkout, isNull);
      },
    );

    test('Kritische Einschränkung schützt auch bei guter Tagesform', () {
      final state = builder.buildState(athleteId: athleteId, asOf: asOf, goal: goal50k,
        subjectiveReadiness: SubjectiveReadinessState(perceivedRecovery: 10, recordedAt: asOf));
      final needs = TrainingNeedResult(athleteId: athleteId, asOf: asOf,
        safetyConstraints: const [SafetyConstraint(id:'clinical_hold', severity:SafetyConstraintSeverity.critical,
          reason:'Trainingspause gemeldet',evidence:'Athletenmeldung')]);
      final decision = decisionEngine.decide(state:state,needResult:needs,availability:standardAvailability);
      expect(decision.actionType,CoachingActionType.restDay);
      expect(decision.prescribedWorkout,isNull);
      expect(decision.safetyConstraintsApplied.single.id,'clinical_hold');
    });

    test(
      '2. Severe Safety Constraint aus der Need Engine erzwingt Ruhetag',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
        );

        final severeConstraint = SafetyConstraint(
          id: 'sc_fever',
          severity: SafetyConstraintSeverity.severe,
          reason: 'Ärztlich verordnete Sportpause nach viralem Infekt',
          evidence: 'Klinischer Befund',
          affectedTrainingTypes: const [
            TrainingNeedType.vo2max,
            TrainingNeedType.threshold,
          ],
          recordedAt: asOf,
        );

        final needResult = TrainingNeedResult(
          athleteId: athleteId,
          asOf: asOf,
          safetyConstraints: [severeConstraint],
        );

        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: standardAvailability,
        );

        expect(decision.actionType, CoachingActionType.restDay);
        expect(decision.coachingReason, contains('Sportpause'));
      },
    );

    test(
      '3. Trizeps-Schmerzen blockieren Ercolina und DP-Power (Lokaler Sicherheitsfilter)',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          subjectiveReadiness: SubjectiveReadinessState(
            recordedAt: asOf,
            painSymptoms: const ['Trizepssehnenreizung'],
          ),
        );

        final needResult = needEngine.evaluate(state: state);
        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: standardAvailability,
        );

        // Ercolina DP muss in den abgelehnten Alternativen mit Begründung auftauchen
        final rejectedDp = decision.rejectedAlternatives.where(
          (alt) => alt.modality == XcModality.ercolinaDoublePoling,
        );
        expect(rejectedDp.isNotEmpty, isTrue);
        expect(rejectedDp.first.rejectionStage, RejectionStage.safetyFilter);
        expect(rejectedDp.first.reason, contains('Oberkörper'));
        // Aber Skating auf Schnee darf gewählt werden!
        expect(decision.prescribedWorkout?.modality, XcModality.skiSkating);
      },
    );

    test(
      '4. Kniebeschwerden blockieren Skating und Laufen (Lokaler Sicherheitsfilter)',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          subjectiveReadiness: SubjectiveReadinessState(
            recordedAt: asOf,
            painSymptoms: const ['Knieschmerzen'],
          ),
        );

        final needResult = needEngine.evaluate(state: state);
        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: standardAvailability,
        );

        // Skating muss abgelehnt worden sein:
        final rejectedSkate = decision.rejectedAlternatives.where(
          (alt) => alt.modality == XcModality.skiSkating,
        );
        expect(rejectedSkate.isNotEmpty, isTrue);
        expect(rejectedSkate.first.rejectionStage, RejectionStage.safetyFilter);
        expect(rejectedSkate.first.reason, contains('unteren Extremität'));
      },
    );

    test(
      '5. Akute Erschöpfung / extrem niedrige Erholung löst aktive Erholung oder Ruhetag aus',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          subjectiveReadiness: SubjectiveReadinessState(
            recordedAt: asOf,
            perceivedRecovery: 2.0, // sehr niedrig
            unusualFatigue: true,
          ),
        );

        final needResult = needEngine.evaluate(state: state);
        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: standardAvailability,
        );

        expect(
          decision.actionType == CoachingActionType.activeRecovery ||
              decision.actionType == CoachingActionType.restDay,
          isTrue,
        );
        expect(decision.coachingReason, contains('Erholung'));
      },
    );

    test(
      '6. Zeitbudget schließt zu lange Einheiten aus (Feasibility Filter)',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
        );

        final needResult = needEngine.evaluate(state: state);

        // Nur 35 Minuten heute verfügbar
        final shortAvailability = DayAvailability(
          date: DateTime.utc(2026, 10, 3),
          availableMinutes: 35,
          environment: TrainingEnvironment.outdoorSnow,
          hasSnow: true,
        );

        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: shortAvailability,
        );

        // Die gewählte Einheit darf maximal 35 Minuten dauern
        expect(
          decision.prescribedWorkout!.totalDurationMinutes,
          lessThanOrEqualTo(35),
        );

        // Einheiten > 35 min müssen im feasibilityFilter abgelehnt worden sein
        final rejectedLong = decision.rejectedAlternatives.where(
          (a) =>
              a.rejectionStage == RejectionStage.feasibilityFilter &&
              a.reason.contains('35 min'),
        );
        expect(rejectedLong.isNotEmpty, isTrue);
      },
    );

    test(
      '7. Look-Ahead Scheduling verschiebt Long Endurance auf das Wochenende',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
        );

        final needResult = needEngine.evaluate(state: state);
        // Long Endurance ist ein Entwicklungsbedarf
        expect(
          needResult.developmentNeeds.any(
            (n) => n.type == TrainingNeedType.longEndurance,
          ),
          isTrue,
        );

        // Heute nur 45 min verfügbar:
        final todayShort = DayAvailability(
          date: DateTime.utc(2026, 10, 3),
          availableMinutes: 45,
          environment: TrainingEnvironment.outdoorSnow,
          hasSnow: true,
        );

        // Aber am Samstag 180 min Zeitfenster vorhanden:
        final lookAhead = DayLookAheadContext(
          upcomingDays: [
            DayAvailability(
              date: DateTime.utc(2026, 10, 4),
              availableMinutes: 45,
            ),
            DayAvailability(
              date: DateTime.utc(2026, 10, 5),
              availableMinutes: 180, // Samstag
              environment: TrainingEnvironment.outdoorSnow,
              hasSnow: true,
            ),
          ],
        );

        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: todayShort,
          lookAhead: lookAhead,
        );

        // Long Endurance darf heute NICHT gewählt werden
        expect(
          decision.prescribedWorkout?.family,
          isNot(WorkoutFamilyType.longEndurance),
        );

        // Long Endurance muss mit lookAheadDeferred begründet sein!
        final deferredLong = decision.rejectedAlternatives.where(
          (a) => a.rejectionStage == RejectionStage.lookAheadDeferred,
        );
        expect(deferredLong.isNotEmpty, isTrue);
        expect(deferredLong.first.reason, contains('verschoben'));
      },
    );

    test(
      '8. Look-Ahead Scheduling verschiebt nicht, wenn kein langes Fenster folgt',
      () {
        final lookAheadEmpty = DayLookAheadContext(
          upcomingDays: [
            DayAvailability(
              date: DateTime.utc(2026, 10, 4),
              availableMinutes: 45,
            ),
            DayAvailability(
              date: DateTime.utc(2026, 10, 5),
              availableMinutes: 50,
            ),
          ],
        );

        expect(lookAheadEmpty.hasUpcomingLongWindow(120), isFalse);
        expect(lookAheadEmpty.findNextLongWindow(120), isNull);
      },
    );

    test(
      '9. Fehlender Schnee verhindert Outdoor Skating (Feasibility Filter)',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
        );

        final needResult = needEngine.evaluate(state: state);

        // Kein Schnee heute, nur Ercolina oder Laufen
        final noSnowAvailability = DayAvailability(
          date: DateTime.utc(2026, 10, 3),
          availableMinutes: 60,
          environment: TrainingEnvironment.indoorErcolina,
          hasSnow: false,
          hasErcolina: true,
        );

        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: noSnowAvailability,
        );

        expect(
          decision.prescribedWorkout?.modality,
          isNot(XcModality.skiSkating),
        );
        final rejectedSkate = decision.rejectedAlternatives.where(
          (a) =>
              a.modality == XcModality.skiSkating &&
              a.rejectionStage == RejectionStage.feasibilityFilter,
        );
        expect(rejectedSkate.isNotEmpty, isTrue);
        expect(rejectedSkate.first.reason, contains('nicht machbar'));
      },
    );

    test(
      '10. Fehlende Ercolina verhindert Ercolina-Doppelstock Prescription',
      () {
        final noErcolinaAvailability = DayAvailability(
          date: DateTime.utc(2026, 10, 3),
          availableMinutes: 60,
          environment: TrainingEnvironment.outdoorSnow,
          hasSnow: true,
          hasErcolina: false,
        );

        expect(
          noErcolinaAvailability.isModalityFeasible(
            XcModality.ercolinaDoublePoling,
          ),
          isFalse,
        );
      },
    );

    test(
      '11. Kürzlicher VO2max-Reiz (< 48h) blockiert erneuten VO2max-Reiz (Recovery Spacing)',
      () {
        // Vor 24 Stunden fand ein VO2max-Training statt
        final vo2Session = NormalizedSession(
          id: 'sess_vo2_yesterday',
          athleteId: athleteId,
          source: NormalizedSessionSource.ercolina,
          sourceId: 'src_vo2',
          startedAtUtcUs: asOf
              .subtract(const Duration(hours: 24))
              .microsecondsSinceEpoch,
          durationSeconds: 2400,
          movingTimeSeconds: 2400,
          modality: XcModality.ercolinaDoublePoling,
          technique: XcTechnique.classicDoublePoling,
          isIndoor: true,
          title: 'Ercolina VO2max HIT',
          externalMetrics: const SessionExternalMetrics(
            sessionAveragePowerWatt: 190.0,
            intervalAveragePowerWatt: 230.0,
          ),
          internalMetrics: const SessionInternalMetrics(
            averageHeartRateBpm: 168.0,
            peakHeartRateBpm: 185,
            rpe: 9.0,
            timeInHrZonesSeconds: {'z5': 420},
          ),
        );

        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          sessions: [vo2Session],
        );

        final needResult = needEngine.evaluate(state: state);
        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: standardAvailability,
        );

        // Heute darf kein VO2max vorgeschrieben werden
        expect(
          decision.prescribedWorkout?.intendedStimuli.contains(
            StimulusType.vo2max,
          ),
          isFalse,
        );

        final rejectedVo2 = decision.rejectedAlternatives.where(
          (a) =>
              a.intendedStimulus == StimulusType.vo2max &&
              a.rejectionStage == RejectionStage.recoveryContext,
        );
        expect(rejectedVo2.isNotEmpty, isTrue);
        expect(rejectedVo2.first.reason, contains('Superkompensation'));
      },
    );

    test(
      '12. Kürzlicher Schwellenreiz (< 24h) blockiert erneuten Schwellenreiz',
      () {
        final threshSession = NormalizedSession(
          id: 'sess_thresh_yesterday',
          athleteId: athleteId,
          source: NormalizedSessionSource.garmin,
          sourceId: 'src_th',
          startedAtUtcUs: asOf
              .subtract(const Duration(hours: 18))
              .microsecondsSinceEpoch,
          durationSeconds: 3600,
          movingTimeSeconds: 3600,
          modality: XcModality.skiSkating,
          technique: XcTechnique.skatingG3,
          isIndoor: false,
          title: 'Skating EB Schwellenintervalle',
          externalMetrics: const SessionExternalMetrics(
            sessionAveragePowerWatt: 210.0,
            intervalAveragePowerWatt: 245.0,
          ),
          internalMetrics: const SessionInternalMetrics(
            averageHeartRateBpm: 168.0,
            peakHeartRateBpm: 178,
            rpe: 8.0,
            timeInHrZonesSeconds: {'z4': 1500},
          ),
        );

        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          // Classification requires an individual HR reference.
          physiology: const AthletePhysiologyState(maxHeartRateBpm: 190),
          sessions: [...establishedHistory(asOf), threshSession],
        );

        expect(
          state.stimulusHistory.entries[StimulusType.threshold]!.sourceModality,
          XcModality.skiSkating,
        );
        // Isolate the spacing filter; an earlier global recovery decision
        // legitimately returns before candidate rejection diagnostics exist.
        final needResult = TrainingNeedResult(asOf: asOf, athleteId: athleteId);
        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: standardAvailability,
        );

        expect(
          decision.prescribedWorkout?.intendedStimuli.contains(
            StimulusType.threshold,
          ),
          isFalse,
        );
        final rejectedThresh = decision.rejectedAlternatives.where(
          (a) =>
              a.intendedStimulus == StimulusType.threshold &&
              a.rejectionStage == RejectionStage.recoveryContext,
        );
        expect(rejectedThresh.isNotEmpty, isTrue);
      },
    );

    test(
      '13. Multi-Objective Scoring priorisiert Primary Development Need vor Maintenance',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
        );

        final needResult = needEngine.evaluate(state: state);

        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: standardAvailability,
        );

        expect(decision.prescribedWorkout, isNotNull);
        expect(decision.primaryNeed, isNotNull);
        expect(decision.primaryNeed?.category, NeedCategory.development);
      },
    );

    test(
      '14. Spezifitätsbonus bevorzugt Ski/Ercolina vor Rad/Lauf bei Skating-Wettkampfziel',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
        );

        final needResult = needEngine.evaluate(state: state);
        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: standardAvailability,
        );

        // Bei vorhandenem Schnee und Skating-Ziel muss Skilanglauf oder Ercolina vor Rad/Lauf gewählt werden
        expect(
          decision.prescribedWorkout?.modality == XcModality.skiSkating ||
              decision.prescribedWorkout?.modality ==
                  XcModality.ercolinaDoublePoling,
          isTrue,
        );
      },
    );

    test(
      '15. Vorliebe des Athleten (Preferred Modality) erhält Scoring-Bonus',
      () {
        final prefAvailability = DayAvailability(
          date: asOf,
          availableMinutes: 50,
          environment: TrainingEnvironment.outdoorSnow,
          hasSnow: true,
          hasErcolina: true,
          preferredModality: XcModality.ercolinaDoublePoling,
        );

        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
        );

        final needResult = needEngine.evaluate(state: state);
        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: prefAvailability,
        );

        final withoutPreference = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: DayAvailability(
            date: asOf,
            availableMinutes: 50,
            environment: TrainingEnvironment.outdoorSnow,
            hasSnow: true,
            hasErcolina: true,
          ),
        );
        final preferredAlternative = decision.rejectedAlternatives.firstWhere(
          (a) =>
              a.modality == XcModality.ercolinaDoublePoling &&
              a.intendedStimulus == StimulusType.technique,
        );
        final sameAlternative = withoutPreference.rejectedAlternatives
            .firstWhere(
              (a) => a.workoutTitle == preferredAlternative.workoutTitle,
            );
        expect(
          preferredAlternative.originalScore! - sameAlternative.originalScore!,
          15.0,
        );
      },
    );

    test(
      '16. Ercolina schreibt exakte Watt vor, wenn valide Ercolina-Diagnostik vorliegt',
      () {
        final ercolinaDiag = DiagnosticReference(
          modality: XcModality.ercolinaDoublePoling,
          date: asOf.subtract(const Duration(days: 10)),
          protocol: 'Ercolina 5x3min Stufentest',
          lt2Ltp2Watt: 200.0,
          source: 'ercolina_machine',
          freshness: FreshnessLevel.fresh,
        );

        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          diagnostics: [ercolinaDiag],
        );

        const resolver = IntensityResolver();
        final pres = resolver.resolveWorkIntensity(
          modality: XcModality.ercolinaDoublePoling,
          stimulus: StimulusType.threshold,
          diagnostics: state.diagnostics,
        );

        expect(pres.targetType, IntensityTargetType.powerWatt);
        expect(pres.isDiagnosticGrounded, isTrue);
        expect(pres.minPowerWatt, closeTo(184.0, 1.0)); // 92% von 200 W
        expect(pres.maxPowerWatt, closeTo(204.0, 1.0)); // 102% von 200 W
        expect(pres.displayInstruction, contains('W'));
      },
    );

    test(
      '17. Ercolina fällt auf RPE zurück, wenn Ercolina-Diagnostik fehlt (keine erfundenen Watt)',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          // Keine Diagnostik
        );

        const resolver = IntensityResolver();
        final pres = resolver.resolveWorkIntensity(
          modality: XcModality.ercolinaDoublePoling,
          stimulus: StimulusType.threshold,
          diagnostics: state.diagnostics,
        );

        expect(pres.targetType, IntensityTargetType.rpe);
        expect(pres.minPowerWatt, isNull);
        expect(pres.isDiagnosticGrounded, isFalse);
        expect(
          pres.rationale,
          contains('Keine valide Ercolina-Wattdiagnostik'),
        );
      },
    );

    test(
      '18. Skating erbt NIEMALS Rad-FTP als Wattwerte (Sportwissenschaftliche Leitplanke)',
      () {
        final cyclingDiag = DiagnosticReference(
          modality: XcModality.cycling,
          date: asOf.subtract(const Duration(days: 5)),
          protocol: 'FTP Test Ergometer',
          lt2Ltp2Watt: 320.0,
          source: 'smart_trainer',
          freshness: FreshnessLevel.fresh,
        );

        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          diagnostics: [cyclingDiag],
        );

        const resolver = IntensityResolver();
        final pres = resolver.resolveWorkIntensity(
          modality: XcModality.skiSkating,
          stimulus: StimulusType.threshold,
          diagnostics: state.diagnostics,
        );

        // Rad-320 Watt dürfen NICHT im Skating auftauchen!
        expect(pres.minPowerWatt, isNull);
        expect(pres.maxPowerWatt, isNull);
        expect(pres.targetType, isNot(IntensityTargetType.powerWatt));
      },
    );

    test(
      '19. Skating mit bekannter HRmax liefert Herzfrequenz- und RPE-Zielkorridore',
      () {
        final skateDiag = DiagnosticReference(
          modality: XcModality.skiSkating,
          date: asOf.subtract(const Duration(days: 10)),
          protocol: 'Feldstufentest Schnee',
          maxHeartRateBpm: 190.0,
          lt2Ltp2Bpm: 168.0,
          source: 'field_test',
          freshness: FreshnessLevel.fresh,
        );

        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          diagnostics: [skateDiag],
        );

        const resolver = IntensityResolver();
        final pres = resolver.resolveWorkIntensity(
          modality: XcModality.skiSkating,
          stimulus: StimulusType.threshold,
          diagnostics: state.diagnostics,
        );

        expect(pres.targetType, IntensityTargetType.percentHrMax);
        expect(pres.minHrBpm, closeTo(156, 1)); // 82% von 190
        expect(pres.maxHrBpm, closeTo(167, 1)); // 88% von 190
        expect(pres.displayInstruction, contains('bpm'));
      },
    );

    test(
      '20. Ablehnungsgründe und Stufen werden für verworfene Alternativen protokolliert',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
        );

        final needResult = needEngine.evaluate(state: state);
        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: standardAvailability,
        );

        expect(decision.rejectedAlternatives.isNotEmpty, isTrue);
        for (final alt in decision.rejectedAlternatives) {
          expect(alt.reason.isNotEmpty, isTrue);
          expect(alt.workoutTitle.isNotEmpty, isTrue);
        }
      },
    );

    test(
      '21. Heute-Karte Text enthält Titel, Dauer, Struktur und Intensitätsinstruktion',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
        );

        final needResult = needEngine.evaluate(state: state);
        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: standardAvailability,
        );

        final cardText = decision.toHeuteCardText();

        expect(cardText, contains('HEUTE-KARTE'));
        expect(cardText, contains('EMPFOHLENE EINHEIT:'));
        expect(cardText, contains('DAUER:'));
        expect(cardText, contains('STRUKTUR:'));
        expect(cardText, contains('WARUM HEUTE:'));
      },
    );

    test(
      '22. Heute-Karte enthält verworfene Alternativen und Sicherheitshinweise',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          subjectiveReadiness: SubjectiveReadinessState(
            recordedAt: asOf,
            painSymptoms: const ['Leichte Schulterüberlastung'],
          ),
        );

        final needResult = needEngine.evaluate(state: state);
        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: standardAvailability,
        );

        final cardText = decision.toHeuteCardText();
        expect(cardText, contains('VERWORFENE ALTERNATIVEN:'));
      },
    );

    test(
      '23. Entscheidung ist lückenlos bis zur State-Evidenz rückverfolgbar',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
        );

        final needResult = needEngine.evaluate(state: state);
        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: standardAvailability,
        );

        expect(decision.backwardTrace.containsKey('decision'), isTrue);
        expect(decision.backwardTrace.containsKey('need'), isTrue);
      },
    );

    test(
      '24. Schlechte Datenabdeckung senkt Decision Confidence und erzeugt Hinweistext',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          sessions: [], // Keine synchronisierten Sessions in 28 Tagen
        );

        final needResult = needEngine.evaluate(state: state);
        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: standardAvailability,
        );

        expect(decision.confidence, NeedConfidence.moderate);
        expect(
          decision.dataLimitations.any((l) => l.contains('Datenabdeckung')),
          isTrue,
        );
      },
    );

    test('25. Mehrere Kandidaten werden deterministisch bewertet', () {
      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        goal: goal50k,
      );

      final needResult = needEngine.evaluate(state: state);
      final decision1 = decisionEngine.decide(
        state: state,
        needResult: needResult,
        availability: standardAvailability,
      );
      final decision2 = decisionEngine.decide(
        state: state,
        needResult: needResult,
        availability: standardAvailability,
      );

      expect(decision1.prescribedWorkout?.id, decision2.prescribedWorkout?.id);
      expect(decision1.coachingReason, decision2.coachingReason);
    });

    test(
      '26. Intervallverschreibungen deklarieren Progressions- und Regressionsvarianten',
      () {
        final family = WorkoutFamily.standardFamilies.firstWhere(
          (f) => f.type == WorkoutFamilyType.thresholdIntervals,
        );

        final p = family.buildPrescription(
          availableMinutes: 75,
          diagnostics: const DiagnosticsState(),
        );

        expect(p.progressionVariant, isNotNull);
        expect(p.regressionVariant, isNotNull);
        expect(p.progressionVariant, contains('min'));
      },
    );

    test(
      '27. Warmup, Belastung und Cooldown sind zeitlich sauber aufgeteilt',
      () {
        final family = WorkoutFamily.standardFamilies.firstWhere(
          (f) => f.type == WorkoutFamilyType.thresholdIntervals,
        );

        final p = family.buildPrescription(
          availableMinutes: 60,
          diagnostics: const DiagnosticsState(),
        );

        expect(p.warmupMinutes, greaterThanOrEqualTo(10));
        expect(p.workMinutes, greaterThanOrEqualTo(20));
        expect(p.cooldownMinutes, greaterThanOrEqualTo(5));
        expect(p.totalDurationMinutes, lessThanOrEqualTo(65));
      },
    );

    test('28. Extrem lange Einheit weist RecoveryCost.extreme aus', () {
      final family = WorkoutFamily.standardFamilies.firstWhere(
        (f) => f.type == WorkoutFamilyType.longEndurance,
      );

      final p = family.buildPrescription(
        availableMinutes: 180,
        diagnostics: const DiagnosticsState(),
      );

      expect(p.recoveryCost, RecoveryCost.extreme);
      expect(p.recoveryCost.requiredRestHours, 72);
    });

    test('29. Unsichere Schneelage weicht auf Cross-Training aus', () {
      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        goal: goal50k,
      );

      final needResult = needEngine.evaluate(state: state);

      final crossAvailability = DayAvailability(
        date: DateTime.utc(2026, 10, 3),
        availableMinutes: 60,
        environment: TrainingEnvironment.outdoorTrailOrRoad,
        hasSnow: false,
        hasErcolina: false,
        hasRollerSki: false,
        hasBike: true,
        hasRunningShoes: true,
      );

      final decision = decisionEngine.decide(
        state: state,
        needResult: needResult,
        availability: crossAvailability,
      );

      expect(
        decision.prescribedWorkout?.modality == XcModality.running ||
            decision.prescribedWorkout?.modality == XcModality.cycling,
        isTrue,
      );
    });

    test(
      '30. End-to-End Closed-Loop Test: Empfehlung Tag 1 -> Ausführung -> State Update -> Anpassung Tag 2',
      () {
        // -----------------------------------------------------------------------
        // SCHRITT A: TAG 1 (Samstag)
        // -----------------------------------------------------------------------
        final day1Date = DateTime.utc(2026, 10, 3, 9, 0);

        // Athlet hat VO2max-Diagnostik auf Ercolina
        final ercolinaDiag = DiagnosticReference(
          modality: XcModality.ercolinaDoublePoling,
          date: day1Date.subtract(const Duration(days: 7)),
          protocol: 'Ercolina Stufentest',
          lt2Ltp2Watt: 210.0,
          source: 'ercolina_machine',
          freshness: FreshnessLevel.fresh,
        );

        final day1State = builder.buildState(
          athleteId: athleteId,
          asOf: day1Date,
          goal: goal50k,
          diagnostics: [ercolinaDiag],
          sessions: establishedHistory(day1Date),
        );

        const vo2Need = TrainingNeed(
          id: 'need_vo2_prioritized',
          type: TrainingNeedType.vo2max,
          category: NeedCategory.development,
          priority: NeedPriority.critical,
          reasons: ['Zielspezifische VO2max-Ausprägung für Wettkampfantritte'],
          confidence: NeedConfidence.high,
        );
        final day1Needs = TrainingNeedResult(
          asOf: day1Date,
          athleteId: athleteId,
          developmentNeeds: const [vo2Need],
        );

        final day1Availability = DayAvailability(
          date: DateTime.utc(2026, 10, 3),
          availableMinutes: 60,
          environment: TrainingEnvironment.outdoorSnow,
          hasSnow: true,
          hasErcolina: true,
          hasRollerSki: true,
        );

        final day1Decision = decisionEngine.decide(
          state: day1State,
          needResult: day1Needs,
          availability: day1Availability,
        );

        expect(day1Decision.actionType, CoachingActionType.prescribedWorkout);
        expect(
          day1Decision.prescribedWorkout?.intendedStimuli.contains(
            StimulusType.vo2max,
          ),
          isTrue,
        );
        final prescribedWorkoutDay1 = day1Decision.prescribedWorkout!;

        // -----------------------------------------------------------------------
        // SCHRITT B: AUSFÜHRUNG SIMULATION
        // -----------------------------------------------------------------------
        // Athlet absolviert die vorgeschriebene Einheit um 10:00 Uhr
        final executedSession = simulator.simulateCompletedSession(
          prescription: prescribedWorkoutDay1,
          athleteId: athleteId,
          performedAt: day1Date.add(const Duration(hours: 1)),
          perceivedRpe: 8.5,
          averageHrBpm: 165.0,
          maxHrBpm: 184.0,
        );

        expect(
          executedSession.durationSeconds,
          prescribedWorkoutDay1.totalDurationMinutes * 60,
        );
        expect(executedSession.externalMetrics.workJoule, isNotNull);

        // -----------------------------------------------------------------------
        // SCHRITT C: TAG 2 (Sonntag, 24 Stunden später)
        // -----------------------------------------------------------------------
        final day2Date = day1Date.add(const Duration(hours: 24));

        // Neuer State mit der absolvierten Einheit von gestern
        final day2State = builder.buildState(
          athleteId: athleteId,
          asOf: day2Date,
          goal: goal50k,
          diagnostics: [ercolinaDiag],
          sessions: [...establishedHistory(day1Date), executedSession],
          subjectiveReadiness: SubjectiveReadinessState(
            recordedAt: day2Date,
            perceivedRecovery: 5.5,
            muscleSoreness: 5.0,
          ),
        );

        // State muss den Reiz von gestern kennen!
        final recordedYesterdayStimulus =
            prescribedWorkoutDay1.intendedStimuli.first;
        expect(
          day2State.stimulusHistory.entries.containsKey(
            recordedYesterdayStimulus,
          ),
          isTrue,
        );

        final day2Needs = needEngine.evaluate(state: day2State);

        final day2Availability = DayAvailability(
          date: DateTime.utc(2026, 10, 4),
          availableMinutes: 60,
          environment: TrainingEnvironment.outdoorSnow,
          hasSnow: true,
          hasErcolina: true,
        );

        final day2Decision = decisionEngine.decide(
          state: day2State,
          needResult: day2Needs,
          availability: day2Availability,
        );

        // BEWEIS DES CLOSED LOOP:
        // Der Coach darf an Tag 2 NICHT denselben harten Reiz noch einmal setzen,
        // wenn es ein HIT- oder Schwellenreiz war!
        if (recordedYesterdayStimulus == StimulusType.vo2max) {
          expect(
            day2Decision.prescribedWorkout?.intendedStimuli.contains(
              StimulusType.vo2max,
            ),
            isFalse,
          );
          final rejectedVo2 = day2Decision.rejectedAlternatives.where(
            (a) =>
                a.intendedStimulus == StimulusType.vo2max &&
                a.rejectionStage == RejectionStage.recoveryContext,
          );
          expect(rejectedVo2.isNotEmpty, isTrue);
        } else if (recordedYesterdayStimulus == StimulusType.threshold) {
          expect(
            day2Decision.prescribedWorkout?.intendedStimuli.contains(
              StimulusType.threshold,
            ),
            isFalse,
          );
        }

        // Tag 2 Entscheidung muss sich nachweisbar an die Belastung von Tag 1 angepasst haben
        expect(
          day2Decision.prescribedWorkout?.id,
          isNot(prescribedWorkoutDay1.id),
        );
      },
    );

    test(
      '31. Contextual Stimulus Spacing: Zwei intensive Tage hintereinander bei Blocktraining erlaubt',
      () {
        final yesterdayVo2 = NormalizedSession(
          id: 'sess_vo2_block',
          athleteId: athleteId,
          source: NormalizedSessionSource.ercolina,
          sourceId: 'src_v',
          startedAtUtcUs: asOf
              .subtract(const Duration(hours: 20))
              .microsecondsSinceEpoch,
          durationSeconds: 2400,
          movingTimeSeconds: 2400,
          modality: XcModality.ercolinaDoublePoling,
          technique: XcTechnique.classicDoublePoling,
          isIndoor: true,
          title: 'Ercolina VO2max',
          externalMetrics: const SessionExternalMetrics(
            sessionAveragePowerWatt: 195.0,
          ),
          internalMetrics: const SessionInternalMetrics(
            averageHeartRateBpm: 165.0,
            peakHeartRateBpm: 184,
            rpe: 8.5,
            timeInHrZonesSeconds: {'z5': 360},
          ),
        );

        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          sessions: [...establishedHistory(asOf), yesterdayVo2],
          subjectiveReadiness: SubjectiveReadinessState(
            recordedAt: asOf,
            perceivedRecovery: 7.5,
          ),
        );

        final needResult = needEngine.evaluate(state: state);

        // Mit allowConsecutiveHardDays = true darf der Schwellenreiz stattfinden
        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: standardAvailability,
          userOverride: const UserOverrideContext(
            allowConsecutiveHardDays: true,
            focusNeed: TrainingNeedType.threshold,
          ),
        );

        expect(decision.actionType, CoachingActionType.prescribedWorkout);
        expect(
          decision.prescribedWorkout?.intendedStimuli.contains(
            StimulusType.threshold,
          ),
          isTrue,
        );
      },
    );

    test(
      '32. User Override: forcedRestDay = true erzwingt Ruhetag unabhängig vom Trainingsbedarf',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
        );

        final needResult = needEngine.evaluate(state: state);
        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: standardAvailability,
          userOverride: const UserOverrideContext(forcedRestDay: true),
        );

        expect(decision.actionType, CoachingActionType.restDay);
        expect(decision.coachingReason, contains('erbetener Ruhetag'));
        expect(decision.prescribedWorkout, isNull);
      },
    );

    test(
      '33. User Override: heavyArms = true schließt Ercolina-Training deterministisch aus',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
        );

        final needResult = needEngine.evaluate(state: state);
        final decision = decisionEngine.decide(
          state: state,
          needResult: needResult,
          availability: standardAvailability,
          userOverride: const UserOverrideContext(heavyArms: true),
        );

        expect(
          decision.prescribedWorkout?.modality,
          isNot(XcModality.ercolinaDoublePoling),
        );
        final rejectedErcolina = decision.rejectedAlternatives.where(
          (a) =>
              a.modality == XcModality.ercolinaDoublePoling &&
              a.reason.contains('Oberkörper'),
        );
        expect(rejectedErcolina.isNotEmpty, isTrue);
      },
    );

    test(
      '34. Qualitativer Erholungsbedarf weist betroffene Körpersysteme aus',
      () {
        final skateLongFam = WorkoutFamily.standardFamilies.firstWhere(
          (f) => f.type == WorkoutFamilyType.longEndurance,
        );
        final p = skateLongFam.buildPrescription(
          availableMinutes: 180,
          diagnostics: const DiagnosticsState(),
        );

        final recDemand = p.effectiveRecoveryDemand;
        expect(recDemand.cost, RecoveryCost.extreme);
        expect(
          recDemand.affectedSystems.contains(TrainedSystem.systemic),
          isTrue,
        );
        expect(
          recDemand.affectedSystems.contains(TrainedSystem.lowerBody),
          isTrue,
        );
        expect(recDemand.qualitativeDescription, contains('Erholungsbedarf'));
      },
    );

    test(
      '35. E0–E14 Canonical Mapping: Ercolina-Verschreibungen verweisen auf kanonische IDs',
      () {
        final ercolinaFam = WorkoutFamily.standardFamilies.firstWhere(
          (f) => f.id == 'fam_ercolina_dp_power',
        );
        final p = ercolinaFam.buildPrescription(
          availableMinutes: 45,
          diagnostics: const DiagnosticsState(),
        );

        // Der Name dieses Tests verlangt kanonische IDs — und genau die
        // stehen jetzt da. Vorher stand hier `expect(p.templateId, 'speed')`
        // und `expect(p.blueprintId, 'power-10x15')`: IDs aus dem
        // Planungskatalog bzw. der handgeschriebenen Bibliothek. 'speed'
        // kannte `blueprintById` gar nicht, und 'power-10x15' war eine
        // andere Einheit als die verschriebene — 33 statt 40 Minuten, andere
        // Struktur. Die Verschreibung verweist nun auf die Einheit selbst,
        // die das Geraet fuehrt.
        expect(p.blueprintId, 'E2_EB_5x3');
        expect(p.templateId, p.blueprintId);

        // Und sie muss startbar sein: Beide Startpfade der App loesen
        // `templateId` ueber `blueprintById` auf.
        expect(
          blueprintById(p.templateId),
          isNotNull,
          reason:
              'templateId ${p.templateId} ist der ausfuehrbaren Bibliothek '
              'unbekannt: Der Start faellt auf freies Training zurueck.',
        );
        for (final fam in WorkoutFamily.standardFamilies.where(
          (f) => f.modality == XcModality.ercolinaDoublePoling,
        )) {
          for (final v in fam.allowedVariants) {
            if (v.templateId == null) continue;
            expect(
              blueprintById(v.templateId),
              isNotNull,
              reason: '${fam.id}/${v.id}: ${v.templateId} startet nicht.',
            );
          }
        }
      },
    );

    test(
      '36. Multi-Anchor Intensitätssteuerung umfasst Intent, Talk-Test, RPE und Gelände',
      () {
        final skateThreshFam = WorkoutFamily.standardFamilies.firstWhere(
          (f) => f.type == WorkoutFamilyType.thresholdIntervals,
        );
        final p = skateThreshFam.buildPrescription(
          availableMinutes: 60,
          diagnostics: const DiagnosticsState(),
        );

        final intensity = p.workIntensity;
        expect(intensity.workoutIntent.isNotEmpty, isTrue);
        expect(intensity.talkTestBreathingCues.isNotEmpty, isTrue);
        expect(intensity.rpeTarget.isNotEmpty, isTrue);
        expect(intensity.terrainGuidance.isNotEmpty, isTrue);
      },
    );
  });
}
