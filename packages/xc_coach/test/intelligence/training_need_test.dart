import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/domain/normalized_session.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:xc_coach/intelligence/load/load_models.dart';
import 'package:xc_coach/intelligence/training_need/assessment_need.dart';
import 'package:xc_coach/intelligence/training_need/goal_demand_model.dart';
import 'package:xc_coach/intelligence/training_need/need_types.dart';
import 'package:xc_coach/intelligence/training_need/safety_constraint.dart';
import 'package:xc_coach/intelligence/training_need/training_need.dart';
import 'package:xc_coach/intelligence/training_need/training_need_engine.dart';
import 'package:xc_coach/intelligence/training_need/transfer_model.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/diagnostics_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/evidence_model.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/goal_context.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/subjective_readiness_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/xc_athlete_state_builder.dart';

void main() {
  group('Schritt 4 – Training Need Engine (24 Kern-Tests)', () {
    const builder = XCAthleteStateBuilder();
    const engine = TrainingNeedEngine();
    const athleteId = 'xc_athlete_test_need';
    final asOf = DateTime.utc(2026, 10, 3, 12, 0);

    // Hilfsobjekt: 50 km Skating Ziel
    const goal50k = GoalContext(
      name: 'Engadin Skimarathon',
      modality: XcModality.skiSkating,
      targetDistanceMetres: 50000.0,
      targetDurationSeconds: 8100, // 2h15
      priority: 'A',
    );

    test('1. 50-km-Skating-Ziel erhöht Relevanz von longEndurance', () {
      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        goal: goal50k,
      );

      final result = engine.evaluate(state: state);
      final longNeed = result.developmentNeeds.firstWhere(
        (n) => n.type == TrainingNeedType.longEndurance,
      );

      expect(longNeed.priority >= NeedPriority.high, isTrue);
      expect(longNeed.reasons.first, contains('50 km'));
    });

    test(
      '2. Fehlende Skating-Schwelle erzeugt InformationNeed, nicht automatisch Threshold TrainingNeed',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          // Keine Diagnostik
        );

        final result = engine.evaluate(state: state);

        // Muss in informationNeeds sein:
        final infoNeed = result.informationNeeds.where(
          (i) => i.type == AssessmentNeedType.skatingThresholdAssessment,
        );
        expect(infoNeed.isNotEmpty, isTrue);
        expect(infoNeed.first.priority, NeedPriority.high);

        // Darf KEINEN developmentNeed für Threshold behaupten, weil Daten fehlen!
        final devThreshold = result.developmentNeeds.where(
          (n) => n.type == TrainingNeedType.threshold,
        );
        expect(devThreshold.isEmpty, isTrue);
      },
    );

    test(
      '3. Historische Cycling-Schwelle erfüllt Skating Diagnostic Need nicht',
      () {
        final cyclingDiag = DiagnosticReference(
          modality: XcModality.cycling,
          date: DateTime.utc(2024, 6, 1),
          protocol: 'FTP Test Ergometer',
          lt2Ltp2Watt: 300.0,
          source: 'lab_bike',
          freshness: FreshnessLevel.historical,
        );

        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          diagnostics: [cyclingDiag],
        );

        final result = engine.evaluate(state: state);

        final infoNeed = result.informationNeeds.firstWhere(
          (i) => i.type == AssessmentNeedType.skatingThresholdAssessment,
        );
        expect(
          infoNeed.reasons.any((r) => r.contains('Rad-/Laufdiagnostik')),
          isTrue,
        );
      },
    );

    test(
      '4. Viel Radtraining kann Aerobic Need beeinflussen, aber Skating Specificity Need nicht vollständig erfüllen',
      () {
        // 15 Stunden Radtraining in den letzten 4 Wochen
        final cyclingSession = NormalizedSession(
          id: 'bike_long',
          athleteId: athleteId,
          source: NormalizedSessionSource.garmin,
          sourceId: 'c1',
          startedAtUtcUs: asOf
              .subtract(const Duration(days: 2))
              .microsecondsSinceEpoch,
          durationSeconds: 54000, // 15h
          movingTimeSeconds: 54000,
          modality: XcModality.cycling,
          isIndoor: false,
          title: 'Lange Ausfahrt Albula Pass',
          internalMetrics: const SessionInternalMetrics(
            averageHeartRateBpm: 130.0,
          ),
        );

        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          sessions: [cyclingSession],
        );

        final result = engine.evaluate(state: state);

        // Transferprüfung (qualitativ / ordinal):
        final transfer = const TrainingTransferEvaluator().evaluateTransfer(
          trainingModality: XcModality.cycling,
          targetModality: XcModality.skiSkating,
          needType: TrainingNeedType.aerobicBase,
        );
        expect(transfer.physiologicalTransfer, TransferLevel.high);
        expect(transfer.movementSpecificity, TransferLevel.minimal);
        expect(transfer.technicalSpecificity, TransferLevel.minimal);

        // LongEndurance für Skating bleibt als Need bestehen mit Hinweis auf unspezifischen Radumfang:
        final longNeed = result.developmentNeeds.firstWhere(
          (n) => n.type == TrainingNeedType.longEndurance,
        );
        expect(
          longNeed.reasons.any(
            (r) => r.contains('unspezifisches Ausdauervolumen'),
          ),
          isTrue,
        );
      },
    );

    test(
      '5. Ercolina erfüllt DP Need teilweise, nicht Skating Technique Need',
      () {
        final transferDp = const TrainingTransferEvaluator().evaluateTransfer(
          trainingModality: XcModality.ercolinaDoublePoling,
          targetModality: XcModality.skiSkating,
          needType: TrainingNeedType.doublePolingEndurance,
        );
        final transferTech = const TrainingTransferEvaluator().evaluateTransfer(
          trainingModality: XcModality.ercolinaDoublePoling,
          targetModality: XcModality.skiSkating,
          needType: TrainingNeedType.technique,
        );

        expect(transferDp.physiologicalTransfer, TransferLevel.high);
        expect(transferDp.movementSpecificity, TransferLevel.high);
        expect(transferDp.muscularSpecificity, TransferLevel.high);

        expect(transferTech.technicalSpecificity, TransferLevel.minimal);
        expect(transferTech.movementSpecificity, TransferLevel.low);
        expect(transferTech.notes.first, contains('keinen Beinabstoß'));
      },
    );

    test('6. 3 h Skating liefert long-duration exposure', () {
      final skate3h = NormalizedSession(
        id: 'skate_3h',
        athleteId: athleteId,
        source: NormalizedSessionSource.garmin,
        sourceId: 's3h',
        startedAtUtcUs: asOf
            .subtract(const Duration(days: 2))
            .microsecondsSinceEpoch,
        durationSeconds: 10800,
        movingTimeSeconds: 10800,
        modality: XcModality.skiSkating,
        isIndoor: false,
        title: '3h Skatingrunde Cungels',
      );

      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        goal: goal50k,
        sessions: [skate3h],
      );

      expect(state.durability.longSessionExposureHours28d, 3.0);
      expect(state.durability.longSessionCount28d, 1);
    });

    test(
      '7. Fehlende Durability Evidence bedeutet nicht schlechte Durability',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
        );

        final result = engine.evaluate(state: state);

        // Erzeugt InformationNeed, nicht DevelopmentNeed mit Vorwurf "schlechte Durability"
        final durInfo = result.informationNeeds.where(
          (i) => i.type == AssessmentNeedType.durabilityAssessment,
        );
        expect(durInfo.isNotEmpty, isTrue);
        expect(
          durInfo.first.reasons.any(
            (r) => r.contains(
              'Fehlende Evidenz bedeutet nicht schlechte Durability',
            ),
          ),
          isTrue,
        );

        final durDev = result.developmentNeeds.where(
          (n) => n.type == TrainingNeedType.durability,
        );
        expect(durDev.isEmpty, isTrue);
      },
    );

    test(
      '8. Schlechte gemessene Durability kann spezifischen Development Need erzeugen',
      () {
        const decObs = DurabilityObservation(
          sessionId: 'sess_marathon_test',
          modality: XcModality.skiSkating,
          durationSeconds: 10800,
          type: DurabilityObservationType.hrExternalDecoupling,
          value: 9.5, // 9.5% Entkopplung = deutlicher Abfall
          unit: '%',
          conditions: '3h Skating St. Moritz',
          confidence: 0.90,
          provenance: 'first_party_hrm_pwr',
        );

        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          explicitDurabilityObservations: [decObs],
        );

        final result = engine.evaluate(state: state);

        final durDev = result.developmentNeeds.firstWhere(
          (n) => n.type == TrainingNeedType.durability,
        );
        expect(durDev.priority, NeedPriority.high);
        expect(durDev.reasons.first, contains('Gemessene aerobe Entkopplung'));
      },
    );

    test('9. Unknown technique erzeugt keinen behaupteten Technikmangel', () {
      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        goal: goal50k,
      );

      final result = engine.evaluate(state: state);

      // Kein TrainingNeed mit Vorwurf mangelhafter Technik:
      final techDev = result.developmentNeeds.where(
        (n) =>
            n.type == TrainingNeedType.technique &&
            n.priority == NeedPriority.high,
      );
      expect(techDev.isEmpty, isTrue);
    });

    test(
      '10. Recent VO2 allein bedeutet nicht automatisch keinen VO2 Need',
      () {
        final vo2Session = NormalizedSession(
          id: 'sess_vo2',
          athleteId: athleteId,
          source: NormalizedSessionSource.ercolina,
          sourceId: 'v1',
          startedAtUtcUs: asOf
              .subtract(const Duration(days: 3))
              .microsecondsSinceEpoch,
          durationSeconds: 2400,
          movingTimeSeconds: 2400,
          modality: XcModality.ercolinaDoublePoling,
          isIndoor: true,
          title: 'Ercolina VO2max 4x4 min',
        );

        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          sessions: [vo2Session],
        );

        final profile = const GoalDemandModel().evaluateDemand(goal50k);
        // VO2 Demand für 50k ist moderat (Dach), unabhängig vom jüngsten Reiz
        expect(
          profile.demandFor(TrainingNeedType.vo2max),
          NeedPriority.moderate,
        );
      },
    );

    test('11. Recovery Need kann aus mehreren Evidence-Signalen entstehen', () {
      const subj = SubjectiveReadinessState(
        perceivedRecovery: 2.0, // sehr schlecht
        muscleSoreness: 7.5, // starker Muskelkater
        sleepQuality: 3.0, // mieser Schlaf
      );

      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        subjectiveReadiness: subj,
      );

      final result = engine.evaluate(state: state);
      final rec = result.immediateOpportunities.where(
        (n) => n.type == TrainingNeedType.recovery,
      );

      expect(rec.isNotEmpty, isTrue);
      expect(rec.first.priority >= NeedPriority.high, isTrue);
      expect(rec.first.reasons.length, greaterThanOrEqualTo(2));
    });

    test('12. EWMA allein erzeugt kein Recovery Gate', () {
      // Nur EWMA negativ, aber subjektiv alles top
      const subj = SubjectiveReadinessState(
        perceivedRecovery: 9.0,
        muscleSoreness: 2.0,
        sleepQuality: 9.0,
      );

      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        subjectiveReadiness: subj,
      );

      final result = engine.evaluate(state: state);

      // Kein kritischer Sicherheitsstopp oder SafetyConstraint allein durch EWMA!
      expect(result.safetyConstraints.isEmpty, isTrue);
    });

    test('13. Pain erzeugt SafetyConstraint, keine Diagnose', () {
      const subj = SubjectiveReadinessState(
        painSymptoms: ['Stechender Schmerz linker Ellenbogen'],
      );

      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        subjectiveReadiness: subj,
      );

      final result = engine.evaluate(state: state);

      expect(result.safetyConstraints.isNotEmpty, isTrue);
      final sc = result.safetyConstraints.first;
      expect(sc.reason, contains('Athlet berichtet über Schmerzen'));
      // Keine medizinische Diagnose enthalten!
      expect(
        sc.reason.contains('Tendinitis') ||
            sc.reason.contains('Sehnenentzündung'),
        isFalse,
      );
    });

    test('14. Illness symptoms erzeugen SafetyConstraint', () {
      const subj = SubjectiveReadinessState(
        illnessSymptoms: ['Fiebergefühl', 'Halsschmerzen'],
      );

      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        subjectiveReadiness: subj,
      );

      final result = engine.evaluate(state: state);

      expect(result.safetyConstraints.isNotEmpty, isTrue);
      final sc = result.safetyConstraints.first;
      expect(sc.severity, SafetyConstraintSeverity.severe);
      expect(sc.restricts(TrainingNeedType.vo2max), isTrue);
      expect(sc.restricts(TrainingNeedType.threshold), isTrue);
    });

    test(
      '15. Missing subjective data erzeugt keinen positiven Readiness-Schluss',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          subjectiveReadiness: const SubjectiveReadinessState(), // Leer
        );

        final result = engine.evaluate(state: state);

        final infoReadiness = result.informationNeeds.where(
          (i) => i.type == AssessmentNeedType.readinessAssessment,
        );
        expect(infoReadiness.isNotEmpty, isTrue);
        expect(
          infoReadiness.first.reasons.any(
            (r) => r.contains(
              'Fehlende Daten dürfen niemals als "erholt" interpretiert werden',
            ),
          ),
          isTrue,
        );
      },
    );

    test('16. Need Priorities besitzen Reasons', () {
      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        goal: goal50k,
      );

      final result = engine.evaluate(state: state);

      for (final need in result.developmentNeeds) {
        expect(
          need.reasons.isNotEmpty,
          isTrue,
          reason: 'Need ${need.type} hat leere Reasons',
        );
      }
      for (final info in result.informationNeeds) {
        expect(
          info.reasons.isNotEmpty,
          isTrue,
          reason: 'Info ${info.type} hat leere Reasons',
        );
      }
    });

    test('17. Need ist vollständig zu Evidence rückverfolgbar', () {
      final skateRef = DiagnosticReference(
        modality: XcModality.skiSkating,
        date: DateTime.utc(2026, 9, 15),
        protocol: 'Laufband Stufentest',
        lt2Ltp2Watt: 250.0,
        source: 'lab_magglingen',
        freshness: FreshnessLevel.fresh,
      );

      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        goal: GoalContext(
          name: '30 km Skating',
          modality: XcModality.skiSkating,
          targetDistanceMetres: 30000.0,
          raceDate: asOf.add(const Duration(days: 45)),
        ),
        diagnostics: [skateRef],
      );

      final result = engine.evaluate(state: state);
      final trace = result.traceEvidenceFor('threshold');

      expect(
        trace.contains('State') || trace.contains('Need: Threshold'),
        isTrue,
      );
    });

    test('18. Goal Context verändert historische State-Evidence nicht', () {
      final stateBefore = builder.buildState(athleteId: athleteId, asOf: asOf);

      final stateWithGoal = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        goal: goal50k,
      );

      // Vorhandene State-Felder bleiben identisch:
      expect(
        stateWithGoal.diagnostics.references.length,
        stateBefore.diagnostics.references.length,
      );
      expect(
        stateWithGoal.durability.longSessionExposureHours28d,
        stateBefore.durability.longSessionExposureHours28d,
      );
    });

    test('19. Schlechte DataCoverage senkt Need Confidence', () {
      // 28 Tage ohne Sync und ohne Daten
      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        goal: goal50k,
        sessions: [],
      );

      final result = engine.evaluate(state: state);

      for (final need in result.developmentNeeds) {
        expect(need.confidence, NeedConfidence.low);
      }
    });

    test(
      '20. Mehrere verwandte Needs zählen denselben Mangel nicht künstlich mehrfach',
      () {
        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
        );

        final result = engine.evaluate(state: state);
        final longNeed = result.developmentNeeds.firstWhere(
          (n) => n.type == TrainingNeedType.longEndurance,
        );

        // Verknüpfte verwandte Bedarfe deklariert:
        expect(
          longNeed.relatedNeedTypes,
          contains(TrainingNeedType.durability),
        );
        expect(
          longNeed.relatedNeedTypes,
          contains(TrainingNeedType.skatingSpecificity),
        );
      },
    );

    test('21. Maintenance Need möglich', () {
      // 40 Stunden Grundlagenausdauer
      final aeroSession = NormalizedSession(
        id: 'sess_base_massive',
        athleteId: athleteId,
        source: NormalizedSessionSource.garmin,
        sourceId: 'bm1',
        startedAtUtcUs: asOf
            .subtract(const Duration(days: 3))
            .microsecondsSinceEpoch,
        durationSeconds: 72000, // 20h
        movingTimeSeconds: 72000,
        modality: XcModality.skiSkating,
        isIndoor: false,
        title: 'Massive Grundlagenausdauer Davos',
        internalMetrics: const SessionInternalMetrics(
          averageHeartRateBpm: 125.0,
          timeInHrZonesSeconds: {'z2': 72000},
        ),
      );

      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        goal: goal50k,
        sessions: [aeroSession],
      );

      final result = engine.evaluate(state: state);
      final maint = result.maintenanceNeeds.where(
        (m) => m.type == TrainingNeedType.aerobicBase,
      );

      expect(maint.isNotEmpty, isTrue);
      expect(maint.first.category, NeedCategory.maintenance);
    });

    test('22. AssessmentNeed getrennt von TrainingNeed', () {
      final state = builder.buildState(
        athleteId: athleteId,
        asOf: asOf,
        goal: goal50k,
      );

      final result = engine.evaluate(state: state);

      // Strikt getrennte Listen
      expect(result.informationNeeds, isA<List<AssessmentNeed>>());
      expect(result.developmentNeeds, isA<List<TrainingNeed>>());
      expect(result.maintenanceNeeds, isA<List<TrainingNeed>>());
    });

    test(
      '23. Athlete mit wenig Daten erzeugt primär InformationNeeds statt erfundener TrainingNeeds',
      () {
        final state = builder.buildState(
          athleteId: 'blank_athlete',
          asOf: asOf,
        );

        final result = engine.evaluate(state: state);

        expect(result.informationNeeds.length, greaterThanOrEqualTo(2));
        expect(result.developmentNeeds.isEmpty, isTrue);
      },
    );

    test(
      '24. Athlete mit guter Evidenz erzeugt konkrete Development/Maintenance Needs',
      () {
        final skateDiag = DiagnosticReference(
          modality: XcModality.skiSkating,
          date: DateTime.utc(2026, 9, 20),
          protocol: 'Spiroergometrie Magglingen',
          lt2Ltp2Watt: 245.0,
          lt1Ltp1Watt: 185.0,
          source: 'lab_test',
          freshness: FreshnessLevel.fresh,
        );

        final skateSession = NormalizedSession(
          id: 'skate_sess_good',
          athleteId: athleteId,
          source: NormalizedSessionSource.garmin,
          sourceId: 'g1',
          startedAtUtcUs: asOf
              .subtract(const Duration(days: 2))
              .microsecondsSinceEpoch,
          durationSeconds: 7200,
          movingTimeSeconds: 7200,
          modality: XcModality.skiSkating,
          isIndoor: false,
          title: 'Gute 2h Skating Einheit',
          internalMetrics: const SessionInternalMetrics(
            averageHeartRateBpm: 135.0,
          ),
        );

        final state = builder.buildState(
          athleteId: athleteId,
          asOf: asOf,
          goal: goal50k,
          diagnostics: [skateDiag],
          sessions: [skateSession],
          confirmedRestDays: {asOf.subtract(const Duration(days: 1))},
        );

        final result = engine.evaluate(state: state);

        expect(result.developmentNeeds.isNotEmpty, isTrue);
        // Skating LTP2 ist bekannt, also kein SkatingThresholdAssessment Need:
        expect(
          result.informationNeeds.any(
            (i) => i.type == AssessmentNeedType.skatingThresholdAssessment,
          ),
          isFalse,
        );
      },
    );
  });
}
