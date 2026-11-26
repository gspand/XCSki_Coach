/// Deterministische Berechnungs-Engine für Trainings- und Informationsbedarfe (Schritt 4).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Beantwortet: «Welche Fähigkeiten sollte dieser Athlet als Nächstes entwickeln oder erhalten – und warum?»
/// - Fällt noch KEINE konkrete Workout-Entscheidung (keine Dauer, keine Wattwerte, keine 4x4 min).
/// - Trennt strikt:
///   1. Development Needs (langfristiger Aufbau)
///   2. Maintenance Needs (Erhalt vorhandener Basis)
///   3. Immediate Opportunities (situative Trainingschancen)
///   4. Information Needs / Assessment Needs ("Ich weiß noch nicht genug")
///   5. Safety Constraints (Schutz des Athleten vor Überlastung/Schaden ohne medizinische Diagnose)
library;

import '../../domain/xc_modality.dart';
import '../load/load_models.dart';
import '../load/stimulus_models.dart';
import '../xc_athlete_state/xc_athlete_state.dart';
import 'assessment_need.dart';
import 'goal_demand_model.dart';
import 'need_types.dart';
import 'safety_constraint.dart';
import 'training_need.dart';
import 'training_need_result.dart';
import 'transfer_model.dart';

class TrainingNeedEngine {
  const TrainingNeedEngine({
    this.demandModel = const GoalDemandModel(),
    this.transferEvaluator = const TrainingTransferEvaluator(),
  });

  final GoalDemandModel demandModel;
  final TrainingTransferEvaluator transferEvaluator;

  /// Ermittelt die strukturierten Trainings- und Informationsbedarfe des Athleten.
  TrainingNeedResult evaluate({
    required XCAthleteState state,
  }) {
    final goal = state.goal;
    final asOf = state.asOf;
    final athleteId = state.athleteId;

    final safetyConstraints = <SafetyConstraint>[];
    final informationNeeds = <AssessmentNeed>[];
    final developmentNeeds = <TrainingNeed>[];
    final maintenanceNeeds = <TrainingNeed>[];
    final immediateOpportunities = <TrainingNeed>[];
    final traceMap = <String, String>{};

    // -------------------------------------------------------------------------
    // 1. SAFETY CONSTRAINTS & GESUNDHEITSSCHUTZ (STÄRKER ALS JEDER NEED)
    // -------------------------------------------------------------------------
    final subj = state.subjectiveReadiness;
    if (subj.hasIllnessSymptoms) {
      final constraint = SafetyConstraint(
        id: 'sc_illness_${asOf.millisecondsSinceEpoch}',
        severity: SafetyConstraintSeverity.severe,
        reason: 'Athlet berichtet über Infekt-/Krankheitssymptome (${subj.illnessSymptoms.join(", ")}). Hochintensive Belastungen meiden.',
        evidence: 'Subjektive Erfassung: ${subj.illnessSymptoms.join(", ")}',
        affectedTrainingTypes: const [
          TrainingNeedType.vo2max,
          TrainingNeedType.threshold,
          TrainingNeedType.longEndurance,
          TrainingNeedType.speedNeuromuscular,
          TrainingNeedType.doublePolingPower,
        ],
        recordedAt: subj.recordedAt,
      );
      safetyConstraints.add(constraint);
    }

    if (subj.hasPainSymptoms) {
      final constraint = SafetyConstraint(
        id: 'sc_pain_${asOf.millisecondsSinceEpoch}',
        severity: SafetyConstraintSeverity.moderate,
        reason: 'Athlet berichtet über Schmerzen oder orthopädische Beschwerden (${subj.painSymptoms.join(", ")}). Spezifische Muskelketten schonen.',
        evidence: 'Subjektive Erfassung: ${subj.painSymptoms.join(", ")}',
        affectedTrainingTypes: [
          if (subj.painSymptoms.any((p) => p.toLowerCase().contains('trizeps') || p.toLowerCase().contains('arm') || p.toLowerCase().contains('schulter'))) ...[
            TrainingNeedType.doublePolingPower,
            TrainingNeedType.doublePolingEndurance,
          ],
          if (subj.painSymptoms.any((p) => p.toLowerCase().contains('knie') || p.toLowerCase().contains('bein') || p.toLowerCase().contains('schienbein'))) ...[
            TrainingNeedType.skatingSpecificity,
            TrainingNeedType.longEndurance,
          ],
        ],
        recordedAt: subj.recordedAt,
      );
      safetyConstraints.add(constraint);
    }

    if (subj.unusualFatigue == true) {
      safetyConstraints.add(
        SafetyConstraint(
          id: 'sc_fatigue_${asOf.millisecondsSinceEpoch}',
          severity: SafetyConstraintSeverity.moderate,
          reason: 'Athlet berichtet über ungewöhnliche, unbegründete Erschöpfung.',
          evidence: 'Subjektive Erfassung: unusualFatigue = true',
          affectedTrainingTypes: const [
            TrainingNeedType.vo2max,
            TrainingNeedType.threshold,
          ],
          recordedAt: subj.recordedAt,
        ),
      );
    }

    // -------------------------------------------------------------------------
    // 2. DATA COVERAGE & BASALE KONFIDENZ
    // -------------------------------------------------------------------------
    final coverage = state.dataCoverage;
    final isCoverageSparse = coverage.unknownDays28d > 3 || coverage.overallCoverageRatio < 0.60;
    final defaultConfidence = isCoverageSparse
        ? NeedConfidence.low
        : NeedConfidence.high;

    if (coverage.unknownDays28d > 5) {
      informationNeeds.add(
        AssessmentNeed(
          id: 'info_coverage',
          type: AssessmentNeedType.dataCoverageAssessment,
          priority: NeedPriority.high,
          reasons: [
            'Trainingshistorie der letzten 28 Tage weist ${coverage.unknownDays28d} unbekannte Tage auf.',
            'Bei Lücken im Trainingsbuch ist die Einschätzung des Trainingsbedarfs unsicherer.',
          ],
          confidence: NeedConfidence.high,
          sourceEvidence: coverage.coverageAssessmentText,
        ),
      );
    }

    // -------------------------------------------------------------------------
    // 3. INFORMATION NEEDS (DIAGNOSTIK & ASSESSMENT)
    // -------------------------------------------------------------------------
    // A. Skating-Schwellendiagnostik
    final targetModality = goal?.modality ?? XcModality.skiSkating;
    if (targetModality == XcModality.skiSkating) {
      if (!state.diagnostics.hasCurrentSkatingDiagnostics) {
        final hasCycling = state.diagnostics.cycling != null;
        final hasRunning = state.diagnostics.running != null;
        final reasons = <String>[
          'Aktuelle Skating-Schwellenwerte (LT1/LT2/LTP2) sind UNKNOWN oder veraltet.',
        ];
        if (hasCycling || hasRunning) {
          reasons.add('Vorhandene Rad-/Laufdiagnostik darf physiologisch nicht als Skating-Schwelle herangezogen werden.');
        }
        informationNeeds.add(
          AssessmentNeed(
            id: 'info_skating_lt2',
            type: AssessmentNeedType.skatingThresholdAssessment,
            priority: NeedPriority.high,
            reasons: reasons,
            targetModality: XcModality.skiSkating,
            confidence: NeedConfidence.high,
            sourceEvidence: state.traceEvidenceFor('skating_lt2'),
          ),
        );
        traceMap['skating_threshold'] =
            'InformationNeed: Skating-Schwellendiagnostik (HIGH) -> Gründe: ${reasons.first} -> Evidenz: ${state.traceEvidenceFor("skating_lt2")}';
        traceMap['skating_lt2'] = traceMap['skating_threshold']!;
      }
    }

    // B. Ercolina DP Schwellen-/Kalibrierungs-Assessment
    if (!state.diagnostics.hasCurrentErcolinaDiagnostics) {
      if (state.doublePoling.calibrationConfidence == null || state.doublePoling.calibrationConfidence! < 0.85) {
        final reasons = [
          'Ercolina-Doppelstock-Referenz ist nicht kalibriert oder diagnostisch ungesichert.',
          'Für präzise Watt-basierte DP-Intervalle wird eine valide Kalibrierung oder ein DP-Leistungstest empfohlen.',
        ];
        informationNeeds.add(
          AssessmentNeed(
            id: 'info_ercolina_calib',
            type: AssessmentNeedType.ercolinaDpAssessment,
            priority: NeedPriority.moderate,
            reasons: reasons,
            targetModality: XcModality.ercolinaDoublePoling,
            confidence: NeedConfidence.moderate,
            sourceEvidence: state.traceEvidenceFor('ercolina_dp'),
          ),
        );
        traceMap['ercolina_dp'] =
            'InformationNeed: Ercolina DP Assessment (MODERATE) -> Gründe: ${reasons.first} -> Evidenz: ${state.traceEvidenceFor("ercolina_dp")}';
      }
    }

    // C. Durability Assessment
    if (!state.durability.hasMeasuredObservations) {
      if (goal != null && (goal.targetDistanceKm ?? 0) >= 30.0) {
        final reasons = [
          'Wettkampfdistanz von ${goal.targetDistanceKm?.toStringAsFixed(0)} km erfordert hohe Durability.',
          'Bislang liegen keine standardisierten aeroben Entkopplungs- oder Ermüdungsbeobachtungen vor.',
          'Fehlende Evidenz bedeutet nicht schlechte Durability, erfordert aber Beobachtung bei langen Einheiten.',
        ];
        informationNeeds.add(
          AssessmentNeed(
            id: 'info_durability',
            type: AssessmentNeedType.durabilityAssessment,
            priority: NeedPriority.moderate,
            reasons: reasons,
            targetModality: targetModality,
            confidence: NeedConfidence.moderate,
            sourceEvidence: state.traceEvidenceFor('durability'),
          ),
        );
        traceMap['durability'] =
            'InformationNeed: Durability Assessment (MODERATE) -> Gründe: ${reasons.first} -> Evidenz: ${state.traceEvidenceFor("durability")}';
        traceMap['durability_assessment'] = traceMap['durability']!;
      }
    }

    // D. Readiness Assessment bei fehlenden subjektiven Daten
    if (!subj.hasData) {
      informationNeeds.add(
        AssessmentNeed(
          id: 'info_readiness',
          type: AssessmentNeedType.readinessAssessment,
          priority: NeedPriority.moderate,
          reasons: [
            'Keine aktuellen subjektiven Rückmeldungen (Schlaf, Muskelkater, Erholung) vorhanden.',
            'Fehlende Daten dürfen niemals als "erholt" interpretiert werden.',
          ],
          confidence: NeedConfidence.high,
          sourceEvidence: 'SubjectiveReadinessState.hasData = false',
        ),
      );
    }

    // -------------------------------------------------------------------------
    // 4. RECOVERY NEED (REGENERATION & ENTLASTUNG)
    // -------------------------------------------------------------------------
    // Entsteht aus mehreren Signalen (nicht allein aus EWMA!):
    var recoveryScore = 0;
    final recoveryReasons = <String>[];

    if (subj.perceivedRecovery != null && subj.perceivedRecovery! <= 4.0) {
      recoveryScore += 2;
      recoveryReasons.add('Subjektive Erholung sehr niedrig (${subj.perceivedRecovery!.toStringAsFixed(1)}/10)');
    }
    if (subj.muscleSoreness != null && subj.muscleSoreness! >= 6.0) {
      recoveryScore += 2;
      recoveryReasons.add('Starker Muskelkater berichtet (${subj.muscleSoreness!.toStringAsFixed(1)}/10)');
    }
    if (subj.sleepQuality != null && subj.sleepQuality! <= 4.0) {
      recoveryScore += 1;
      recoveryReasons.add('Schlechte Schlafqualität gemeldet (${subj.sleepQuality!.toStringAsFixed(1)}/10)');
    }
    // Letzte Stimuli: mehrere fordernde Reize in den letzten 72h
    final recentHit = state.stimulusHistory.entries[StimulusType.vo2max];
    final recentThresh = state.stimulusHistory.entries[StimulusType.threshold];
    final nowMs = asOf.millisecondsSinceEpoch;
    var hardStimuliCount72h = 0;
    if (recentHit?.lastObservedAt != null && asOf.difference(recentHit!.lastObservedAt!).inHours <= 72) {
      hardStimuliCount72h++;
    }
    if (recentThresh?.lastObservedAt != null && asOf.difference(recentThresh!.lastObservedAt!).inHours <= 72) {
      hardStimuliCount72h++;
    }
    if (hardStimuliCount72h >= 2) {
      recoveryScore += 2;
      recoveryReasons.add('$hardStimuliCount72h hochintensive Reize (VO2/Schwelle) in den letzten 72 Stunden');
    }

    // Deskriptives EWMA-Signal (nur stützendes Signal, kein alleiniges Gate!)
    final bState = state.trainingLoad.latestBanisterState;
    if (bState != null && bState.loadBalance < -15.0) {
      recoveryScore += 1;
      recoveryReasons.add('Akute Belastung übersteigt chronische Belastung deutlich (LoadBalance ${bState.loadBalance.toStringAsFixed(1)})');
    }

    if (recoveryScore >= 3) {
      final recNeed = TrainingNeed(
        id: 'need_recovery_${asOf.millisecondsSinceEpoch}',
        type: TrainingNeedType.recovery,
        category: NeedCategory.immediateOpportunity,
        priority: recoveryScore >= 5 ? NeedPriority.critical : NeedPriority.high,
        reasons: recoveryReasons,
        confidence: isCoverageSparse ? NeedConfidence.moderate : NeedConfidence.high,
        sourceEvidenceIds: [
          if (subj.recordedAt != null) 'subjective_readiness',
          if (bState != null) 'banister_ewma',
        ],
      );
      immediateOpportunities.add(recNeed);
      traceMap['recovery'] = 'Need: Recovery (${recNeed.priority.label}) -> Gründe: ${recoveryReasons.join("; ")} -> Evidenz: SubjectiveReadiness & StimulusHistory';
    }

    // -------------------------------------------------------------------------
    // 5. GOAL DEMAND VS. ATHLETE STATE -> TRAINING NEEDS
    // -------------------------------------------------------------------------
    if (goal != null) {
      final profile = demandModel.evaluateDemand(goal);
      final daysUntilGoal = goal.daysUntilGoal(asOf: asOf) ?? 120;

      // 5.1 Long Endurance & Ski Specificity
      final longExpHours28d = state.durability.longSessionExposureHours28d;
      final skiHours28d = state.skiExposure.totalSkiSpecificDurationSeconds28d / 3600.0;
      final nonSkiHours28d = state.skiExposure.totalNonSkiDurationSeconds28d / 3600.0;

      if (profile.demandFor(TrainingNeedType.longEndurance) >= NeedPriority.high) {
        if (longExpHours28d < 4.0 || skiHours28d < 6.0) {
          final reasons = <String>[
            'Wettkampfdistanz von ${profile.distanceKm?.toStringAsFixed(0)} km (erwartet ca. ${profile.expectedDurationHours.toStringAsFixed(2)} h) erfordert spezifische Langzeitausdauer.',
          ];
          if (isCoverageSparse) {
            reasons.add('Nur ${longExpHours28d.toStringAsFixed(1)} h lange Einheiten und ${skiHours28d.toStringAsFixed(1)} h skispezifischer Umfang beobachtet; Datenabdeckung unzureichend für eine belastbare Aussage über den tatsächlichen 28-Tage-Umfang.');
          } else {
            reasons.add('In den letzten 28 Tagen nur ${longExpHours28d.toStringAsFixed(1)} h lange Einheiten (>= 90 min) und ${skiHours28d.toStringAsFixed(1)} h skispezifischer Umfang erfasst.');
          }
          if (nonSkiHours28d > 10.0) {
            reasons.add('Hohes unspezifisches Ausdauervolumen (${nonSkiHours28d.toStringAsFixed(1)} h Rad/Lauf) liefert kardiovaskuläre Basis, ersetzt aber nicht die skispezifische Bewegungsökonomie.');
          }

          final need = TrainingNeed(
            id: 'need_long_endurance',
            type: TrainingNeedType.longEndurance,
            category: NeedCategory.development,
            priority: daysUntilGoal < 45 ? NeedPriority.critical : NeedPriority.high,
            reasons: reasons,
            confidence: defaultConfidence,
            targetModality: targetModality,
            relatedNeedTypes: const [
              TrainingNeedType.durability,
              TrainingNeedType.skatingSpecificity,
              TrainingNeedType.raceSpecificity,
            ],
            sourceEvidenceIds: [
              'ski_exposure_28d',
              'durability_exposure_28d',
            ],
          );
          developmentNeeds.add(need);
          traceMap['long_endurance'] =
              'Need: Long Endurance (HIGH) -> Gründe: ${reasons.first} -> Evidenz: SkiExposure ${skiHours28d.toStringAsFixed(1)} h, DurabilityExp ${longExpHours28d.toStringAsFixed(1)} h -> Quelle: NormalizedSessions';
        } else {
          // Ausreichend lange Einheiten absolviert -> Maintenance
          maintenanceNeeds.add(
            TrainingNeed(
              id: 'maint_long_endurance',
              type: TrainingNeedType.longEndurance,
              category: NeedCategory.maintenance,
              priority: NeedPriority.maintenance,
              reasons: [
                'Gute Langzeitausdauer-Exposition in den letzten 28 Tagen (${longExpHours28d.toStringAsFixed(1)} h in Einheiten >= 90 min).',
                'Regelmäßige Reize im Grundlagenbereich (Z1/Z2) zur Sicherung des Niveaus beibehalten.',
              ],
              confidence: defaultConfidence,
              targetModality: targetModality,
            ),
          );
        }
      }

      // 5.2 Durability: Nur echter Leistungsabfall erzeugt Development Need
      if (state.durability.hasMeasuredObservations) {
        final decObs = state.durability.observations.where(
          (o) => o.type == DurabilityObservationType.hrExternalDecoupling ||
                 o.type == DurabilityObservationType.powerPaceDegradation,
        ).toList();

        final severeDecoupling = decObs.any((o) => (o.value ?? 0.0) > 6.0);
        if (severeDecoupling) {
          final reasons = [
            'Gemessene aerobe Entkopplung oder Leistungsabfall unter Dauerbelastung nachgewiesen.',
            'Zur Verhinderung des späten Leistungseinbruchs im Wettkampf ist spezifische Durability-Entwicklung indiziert.',
          ];
          final need = TrainingNeed(
            id: 'need_durability_deficit',
            type: TrainingNeedType.durability,
            category: NeedCategory.development,
            priority: NeedPriority.high,
            reasons: reasons,
            confidence: NeedConfidence.high,
            targetModality: targetModality,
            relatedNeedTypes: const [
              TrainingNeedType.longEndurance,
            ],
            sourceEvidenceIds: decObs.map((o) => o.sessionId).toList(),
          );
          developmentNeeds.add(need);
          traceMap['durability'] =
              'Need: Durability (HIGH) -> Gründe: ${reasons.first} -> Evidenz: Beobachtete Entkopplung ${decObs.first.value}% -> Session: ${decObs.first.sessionId} -> Quelle: ${decObs.first.provenance}';
        }
      }

      // 5.3 Aerobic Base: Development oder Maintenance
      final aeroSec28d = state.aerobic.lowIntensityDurationSeconds28d;
      final aeroHours28d = aeroSec28d / 3600.0;
      if (aeroHours28d >= 12.0) {
        maintenanceNeeds.add(
          TrainingNeed(
            id: 'maint_aerobic_base',
            type: TrainingNeedType.aerobicBase,
            category: NeedCategory.maintenance,
            priority: NeedPriority.maintenance,
            reasons: [
              'Solide aerobe Grundlage vorhanden (${aeroHours28d.toStringAsFixed(1)} h Grundlagenausdauer in den letzten 28 Tagen).',
              'Regelmäßige Zone-1/2-Einheiten zur physiologischen Stabilisierung fortführen.',
            ],
            confidence: defaultConfidence,
            targetModality: targetModality,
            sourceEvidenceIds: ['aerobic_state_28d'],
          ),
        );
        traceMap['aerobic_base'] =
            'Need: Aerobic Base (MAINTENANCE) -> Gründe: Solide aerobe Basis vorhanden -> Evidenz: ${aeroHours28d.toStringAsFixed(1)} h Grundlagenumfang 28d -> Quelle: NormalizedSessions';
      } else if (aeroHours28d < 6.0) {
        final reason = isCoverageSparse
            ? '${aeroHours28d.toStringAsFixed(1)} h aerober Umfang beobachtet; Datenabdeckung unzureichend für eine belastbare Aussage über den tatsächlichen 28-Tage-Umfang.'
            : 'Geringer aerober Grundlagenausdauer-Umfang in den letzten 4 Wochen (${aeroHours28d.toStringAsFixed(1)} h).';
        developmentNeeds.add(
          TrainingNeed(
            id: 'need_aerobic_base',
            type: TrainingNeedType.aerobicBase,
            category: NeedCategory.development,
            priority: isCoverageSparse ? NeedPriority.low : NeedPriority.moderate,
            reasons: [
              reason,
              if (!isCoverageSparse)
                'Fettstoffwechselbasis und aerobe Kapazität sollten systematisch aufgebaut werden.'
              else
                'Fehlende Trainingsdaten dürfen nicht automatisch als Trainingsdefizit interpretiert werden; Datenlücke schließen.',
            ],
            confidence: defaultConfidence,
            targetModality: targetModality,
            sourceEvidenceIds: ['aerobic_state_28d'],
          ),
        );
      }

      // 5.4 Double Poling Endurance & Power
      if (targetModality == XcModality.skiSkating ||
          targetModality == XcModality.skiClassic) {
        final dpWorkKj = state.doublePoling.totalWorkKiloJoule28d ?? 0.0;
        final dpSec28d = state.skiExposure.ercolinaDurationSeconds28d;
        final dpHours28d = dpSec28d / 3600.0;

        if (dpHours28d < 2.0 && dpWorkKj < 800.0) {
          final reasons = [
            'Doppelstockvortrieb ist essenzieller Leistungsbestandteil für Skilanglauf.',
            'In den letzten 28 Tagen nur ${dpHours28d.toStringAsFixed(1)} h DP-Exposition (${dpWorkKj.toStringAsFixed(0)} kJ Ercolina-Arbeit) erfasst.',
          ];
          final need = TrainingNeed(
            id: 'need_dp_endurance',
            type: TrainingNeedType.doublePolingEndurance,
            category: NeedCategory.development,
            priority: NeedPriority.moderate,
            reasons: reasons,
            confidence: defaultConfidence,
            targetModality: XcModality.ercolinaDoublePoling,
            sourceEvidenceIds: ['double_poling_state_28d'],
          );
          developmentNeeds.add(need);
          traceMap['double_poling_endurance'] =
              'Need: DP Endurance (MODERATE) -> Gründe: Geringe DP-Arbeit in 28d -> Evidenz: ${dpWorkKj.toStringAsFixed(0)} kJ Ercolina Arbeit -> Quelle: Ercolina Sessions';
        } else {
          maintenanceNeeds.add(
            TrainingNeed(
              id: 'maint_dp_endurance',
              type: TrainingNeedType.doublePolingEndurance,
              category: NeedCategory.maintenance,
              priority: NeedPriority.maintenance,
              reasons: [
                'Gute kontinuierliche Doppelstock-Arbeit (${dpWorkKj.toStringAsFixed(0)} kJ in 28 Tagen) absolviert.',
              ],
              confidence: defaultConfidence,
              targetModality: XcModality.ercolinaDoublePoling,
            ),
          );
        }
      }

      // 5.5 Schwellenkapazität (Threshold): Nur wenn Skating-Schwelle valide bekannt ist!
      // Wenn unbekannt -> wurde bereits oben als AssessmentNeed deklariert!
      if (state.diagnostics.hasCurrentSkatingDiagnostics) {
        final threshSessions28d = state.threshold.thresholdSessionCount28d;
        if (threshSessions28d < 2 && daysUntilGoal < 90) {
          final reasons = [
            'Wettkampfspezifische Schwellenstabilität für Anstiege erforderlich.',
            'In den letzten 4 Wochen nur $threshSessions28d spezifische Schwelleneinheiten absolviert.',
          ];
          developmentNeeds.add(
            TrainingNeed(
              id: 'need_threshold',
              type: TrainingNeedType.threshold,
              category: NeedCategory.development,
              priority: NeedPriority.high,
              reasons: reasons,
              confidence: NeedConfidence.high,
              targetModality: targetModality,
              sourceEvidenceIds: ['threshold_state_28d', 'diag_lt2_skating'],
            ),
          );
          traceMap['threshold'] =
              'Need: Threshold (HIGH) -> Gründe: Nur $threshSessions28d Schwelleneinheiten in 28d -> Evidenz: Skating LTP2 ${state.diagnostics.skating?.lt2Ltp2Watt} W -> Quelle: Labordiagnostik';
        }
      }

      // 5.6 Skating-Spezifität
      if (targetModality == XcModality.skiSkating) {
        final onSnowSkatingHours = state.skiExposure.exposureOf(XcModality.skiSkating).durationHours28d;
        final rollerSkatingHours = state.skiExposure.exposureOf(XcModality.rollerSkiSkating).durationHours28d;
        final totalSkatingHours = onSnowSkatingHours + rollerSkatingHours;

        if (totalSkatingHours < 4.0 && daysUntilGoal < 60) {
          final reasons = [
            'Wettkampfziel ist Langlauf Skating (${profile.distanceKm?.toStringAsFixed(0)} km).',
            'In den letzten 28 Tagen nur ${totalSkatingHours.toStringAsFixed(1)} h Skating (Schnee + Rollski) absolviert.',
          ];
          developmentNeeds.add(
            TrainingNeed(
              id: 'need_skating_spec',
              type: TrainingNeedType.skatingSpecificity,
              category: NeedCategory.development,
              priority: NeedPriority.high,
              reasons: reasons,
              confidence: defaultConfidence,
              targetModality: XcModality.skiSkating,
              sourceEvidenceIds: ['ski_exposure_state'],
            ),
          );
        }
      }
    }

    // -------------------------------------------------------------------------
    // 6. SORTIERUNG NACH PRIORITÄT (ORDINAL)
    // -------------------------------------------------------------------------
    developmentNeeds.sort((a, b) => b.priority.rank.compareTo(a.priority.rank));
    maintenanceNeeds.sort((a, b) => b.priority.rank.compareTo(a.priority.rank));
    informationNeeds.sort((a, b) => b.priority.rank.compareTo(a.priority.rank));
    immediateOpportunities.sort((a, b) => b.priority.rank.compareTo(a.priority.rank));

    return TrainingNeedResult(
      asOf: asOf,
      athleteId: athleteId,
      goal: goal,
      developmentNeeds: developmentNeeds,
      maintenanceNeeds: maintenanceNeeds,
      immediateOpportunities: immediateOpportunities,
      informationNeeds: informationNeeds,
      safetyConstraints: safetyConstraints,
      traceMap: traceMap,
    );
  }
}
