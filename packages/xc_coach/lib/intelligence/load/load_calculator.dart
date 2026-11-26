/// Sportwissenschaftliche Berechnung von External Load, Internal Load und Stimuli in GIULIA.
///
/// Wissenschaftliche Fundierung:
/// 1. Banister TRIMP:
///    Banister EW (1991): «Modeling Elite Athletic Performance». In: Physiological Testing
///    of Elite Athletes. Human Kinetics, Champaign, IL, pp 403-424.
/// 2. Edwards Zonal TRIMP:
///    Edwards S (1993): «The Heart Rate Monitor Book». Fleet Feet Press, Roseville.
/// 3. Session RPE (sRPE):
///    Foster C et al. (2001): «A new approach to monitoring exercise training».
///    J Strength Cond Res 15(1): 109-115.
///
/// Wichtige Prinzipien:
/// - Keine erfundene Skating-LTHR aus historischen Rad- oder Laufwerten.
/// - Fehlende Sensoren erzeugen null, niemals Schätzwerte.
/// - External und Internal Load bleiben unabhängig.
library;

import 'dart:math' as math;

import '../../domain/normalized_session.dart';
import '../../domain/xc_modality.dart';
import 'load_models.dart';
import 'stimulus_models.dart';

/// Physiologische Referenzdaten des Athleten.
class AthletePhysiology {
  const AthletePhysiology({
    this.maxHeartRateBpm = 190.0,
    this.restingHeartRateBpm = 50.0,
    this.isFemale = false,
    this.sportSpecificLthrBpm = const {},
    this.sportSpecificThresholdPowerWatt = const {},
    this.banisterFactorB = 0.64,
    double? banisterGenderFactorY,
    this.banisterModelVersion = 'banister_1991',
  }) : banisterGenderFactorY =
           banisterGenderFactorY ?? (isFemale ? 1.67 : 1.92);

  final double maxHeartRateBpm;
  final double restingHeartRateBpm;
  final bool isFemale;

  /// Echte, sportartspezifisch gemessene Laktatschwellen-Herzfrequenz (LTHR).
  /// Darf NIEMALS ungeprüft zwischen Sportarten übertragen werden (z. B. Rad-LTHR + 5 bpm = Skating-LTHR).
  final Map<XcModality, double> sportSpecificLthrBpm;

  /// Sportartspezifische Schwellenleistung (z. B. Ercolina Critical Power oder Rad FTP).
  final Map<XcModality, double> sportSpecificThresholdPowerWatt;

  /// Banister TRIMP Modellparameter: b-Faktor (Standard: 0.64).
  final double banisterFactorB;

  /// Banister TRIMP Modellparameter: y-Faktor (Standard: 1.92 für Männer, 1.67 für Frauen).
  /// WICHTIG: Keine biologische Naturkonstante, sondern empirisch parametrisierbarer Modellwert!
  final double banisterGenderFactorY;

  /// Modellversion / Provenienz der Banister-Berechnung.
  final String banisterModelVersion;

  bool hasSpecificLthr(XcModality modality) =>
      sportSpecificLthrBpm.containsKey(modality) &&
      sportSpecificLthrBpm[modality]! > 0;

  bool hasSpecificThresholdPower(XcModality modality) =>
      sportSpecificThresholdPowerWatt.containsKey(modality) &&
      sportSpecificThresholdPowerWatt[modality]! > 0;
}

class LoadCalculator {
  const LoadCalculator();

  /// Berechnet die vollständige Belastung ([SessionLoad]) einer kanonischen Trainingseinheit.
  SessionLoad calculateLoad(
    NormalizedSession session, {
    AthletePhysiology physiology = const AthletePhysiology(),
    bool allowGenericHeartRateReference = true,
  }) {
    if (!session.eligibleForCoach) {
      throw UnsupportedError('Die Datenquelle ist für den XC Ski Coach gesperrt.');
    }
    final external = _calculateExternalLoad(session);
    final internal = _calculateInternalLoad(
      session,
      physiology,
      allowGenericHeartRateReference: allowGenericHeartRateReference,
    );
    final perceived = _calculatePerceivedLoad(session);

    // Gesamtkonfidenz der Belastungsberechnung:
    // Ergibt sich aus der Datenqualität der Einheit und der Verfügbarkeit von Primärsignalen.
    var calcConfidence = session.dataQuality.confidence;
    if (session.dataQuality.warnings.isNotEmpty) {
      calcConfidence = (calcConfidence * 0.9).clamp(0.1, 1.0);
    }

    return SessionLoad(
      sessionId: session.id,
      athleteId: session.athleteId,
      modality: session.modality,
      technique: session.technique,
      startedAtUtcUs: session.startedAtUtcUs,
      durationSeconds: session.durationSeconds,
      external: external,
      internal: internal,
      perceived: perceived,
      confidence: calcConfidence,
      provenance: session.source.key,
    );
  }

  /// Berechnet alle in dieser Einheit gesetzten Reize ([StimulusLedger]).
  ///
  /// Unterstützt den Abgleich zwischen geplanten Reizen ([plannedStimulusType], [plannedStimuli])
  /// und tatsächlich nachgewiesenen physiologischen Ist-Reizen.
  StimulusLedger calculateStimuli(
    NormalizedSession session, {
    AthletePhysiology physiology = const AthletePhysiology(),
    bool allowGenericHeartRateReference = true,
    StimulusType? plannedStimulusType,
    List<TrainingStimulus>? plannedStimuli,
  }) {
    if (!session.eligibleForCoach) {
      throw UnsupportedError('Die Datenquelle ist für den XC Ski Coach gesperrt.');
    }
    final stimuli = <TrainingStimulus>[];
    final durationMin = session.movingTimeSeconds / 60.0;
    final modality = session.modality;
    final hrMean = session.internalMetrics.averageHeartRateBpm;
    final rpe = session.internalMetrics.rpe;
    final sessionWatt =
        session.externalMetrics.sessionAveragePowerWatt ??
        session.externalMetrics.averagePowerWatt;
    final intervalWatt = session.externalMetrics.intervalAveragePowerWatt;
    final effectiveWatt = intervalWatt ?? sessionWatt;
    final zones = session.internalMetrics.timeInHrZonesSeconds;
    final classifiedZoneSeconds = zones.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    final lowZoneSeconds = (zones['z1'] ?? 0) + (zones['z2'] ?? 0);
    final hasLowZoneDominance =
        classifiedZoneSeconds > 0 &&
        lowZoneSeconds / classifiedZoneSeconds >= 0.75;

    // 1. Grundlagenausdauer (Aerobic Base)
    if (durationMin >= 40 &&
        (((allowGenericHeartRateReference && hrMean != null) &&
                hrMean <= physiology.maxHeartRateBpm * 0.78) ||
            (rpe != null && rpe <= 5.0) ||
            hasLowZoneDominance ||
            (allowGenericHeartRateReference &&
                hrMean == null &&
                rpe == null))) {
      stimuli.add(
        TrainingStimulus(
          type: StimulusType.aerobicBase,
          modality: modality,
          technique: session.technique,
          evidence:
              'Dauer ${durationMin.toStringAsFixed(0)} min im Grundbereich (Fettstoffwechsel & Kapillarisierung)',
          confidence: hrMean != null ? 0.90 : 0.75,
          primaryEnergySystem: 'aerobic_lipolytic',
          origin: plannedStimulusType == StimulusType.aerobicBase
              ? StimulusOrigin.verified
              : StimulusOrigin.observed,
          plannedType: plannedStimulusType,
          complianceRate: 1.0,
        ),
      );
    }

    // 2. Langer Skiumfang (Long Endurance) - Reine Exposition
    if (durationMin >= 90 && modality.isSkiing) {
      stimuli.add(
        TrainingStimulus(
          type: StimulusType.longEndurance,
          modality: modality,
          technique: session.technique,
          evidence:
              'Spezifischer Skilanglauf-Dauerumfang (${durationMin.toStringAsFixed(0)} min Expositionszeit)',
          confidence: 0.95,
          primaryEnergySystem: 'aerobic_glycogen_lipolytic',
          origin: plannedStimulusType == StimulusType.longEndurance
              ? StimulusOrigin.verified
              : StimulusOrigin.observed,
          plannedType: plannedStimulusType,
          complianceRate: 1.0,
        ),
      );
    }

    // 3. Ermüdungswiderstand (Fatigue Resistance / Durability als Anpassungsziel)
    // Wichtig: Dies ist ein Stimulus/Adaptationsreiz durch überlange Glykogenverarmung,
    // KEINE automatisch gemessene DurabilityObservation!
    if (durationMin >= 150 && modality.isSkiing) {
      stimuli.add(
        TrainingStimulus(
          type: StimulusType.fatigueResistance,
          modality: modality,
          technique: session.technique,
          evidence:
              'Überlange skispezifische Belastung (> 2,5 h) induziert subzelluläre Ermüdungsresistenz (Expositionsreiz, keine gemessene Durability-Degradation)',
          confidence: 0.85,
          primaryEnergySystem: 'durability_glycogen_depleted',
          origin: plannedStimulusType == StimulusType.fatigueResistance
              ? StimulusOrigin.verified
              : StimulusOrigin.observed,
          plannedType: plannedStimulusType,
          complianceRate: 1.0,
        ),
      );
    }

    // 4. Ercolina / Doppelstock Spezifik
    if (modality == XcModality.ercolinaDoublePoling ||
        modality == XcModality.doublePoling ||
        modality == XcModality.rollerSkiDoublePoling) {
      final thresholdWatt =
          physiology.sportSpecificThresholdPowerWatt[modality];

      // Wissenschaftliche Leitplanke: Absolute Watt niemals allein als Power-Reiz hardcoden!
      // Nur wenn ein relativer Schwellenwert vorliegt oder geplante HIT-Intervalle absolviert wurden:
      if (thresholdWatt != null && thresholdWatt > 0 && effectiveWatt != null) {
        final relPower = effectiveWatt / thresholdWatt;
        if (relPower >= 1.05) {
          stimuli.add(
            TrainingStimulus(
              type: StimulusType.doublePolingPower,
              modality: modality,
              technique: session.technique,
              evidence:
                  'Hohe mechanische Doppelstock-Leistung (${effectiveWatt.toStringAsFixed(0)} W = ${(relPower * 100).toStringAsFixed(0)}% der individuellen DP-Schwelle von ${thresholdWatt.toStringAsFixed(0)} W)',
              confidence: 0.95,
              primaryEnergySystem: 'upper_body_neuromuscular',
              origin: plannedStimulusType == StimulusType.doublePolingPower
                  ? StimulusOrigin.verified
                  : StimulusOrigin.observed,
              plannedType: plannedStimulusType,
              complianceRate: 1.0,
            ),
          );
        }
      } else if (plannedStimulusType == StimulusType.doublePolingPower &&
          effectiveWatt != null &&
          effectiveWatt > 0) {
        // Geplanter Power-Reiz absolviert, aber ohne hinterlegte Schwelle
        stimuli.add(
          TrainingStimulus(
            type: StimulusType.doublePolingPower,
            modality: modality,
            technique: session.technique,
            evidence:
                'Geplante Doppelstock-Power Einheit absolviert (${effectiveWatt.toStringAsFixed(0)} W; individuelle Schwelle nicht hinterlegt)',
            confidence: 0.80,
            primaryEnergySystem: 'upper_body_neuromuscular',
            origin: StimulusOrigin.verified,
            plannedType: plannedStimulusType,
            complianceRate: 0.9,
          ),
        );
      }

      // Kraftausdauer über Dauer
      if (durationMin >= 20) {
        stimuli.add(
          TrainingStimulus(
            type: StimulusType.muscularEndurance,
            modality: modality,
            technique: session.technique,
            evidence:
                'Oberkörper- und Rumpfkraftausdauer über ${durationMin.toStringAsFixed(0)} min Doppelstockbelastung',
            confidence: 0.90,
            primaryEnergySystem: 'upper_body_glycolytic',
            origin: plannedStimulusType == StimulusType.muscularEndurance
                ? StimulusOrigin.verified
                : StimulusOrigin.observed,
            plannedType: plannedStimulusType,
            complianceRate: 1.0,
          ),
        );
      }
    }

    // 5. VO2max Reiz vs. Schwellenreiz
    // WICHTIG: sessionAverageHR >= 88% HRmax ist KEIN Beweis für einen VO2max-Reiz!
    // Erforderlich: Hohe Zeit in Z5 (>90% HRmax) ODER geplante HIT-Intervalle ODER RPE >= 9 mit hoher Intensität.
    final z5Seconds = zones['z5'] ?? 0;
    final hasZ5Accumulation = z5Seconds >= 300; // >= 5 min in Z5
    final isPlannedVo2Hit = plannedStimulusType == StimulusType.vo2max;
    final isMaximalIntervalRpe =
        (rpe != null && rpe >= 8.5) &&
        (intervalWatt != null ||
            session.title.toLowerCase().contains('hit') ||
            session.title.toLowerCase().contains('intervall'));

    if (hasZ5Accumulation ||
        (isPlannedVo2Hit && (hrMean != null || rpe != null)) ||
        isMaximalIntervalRpe) {
      stimuli.add(
        TrainingStimulus(
          type: StimulusType.vo2max,
          modality: modality,
          technique: session.technique,
          evidence: hasZ5Accumulation
              ? 'Akkumulierte Verweildauer in VO2max-Zone Z5 (${(z5Seconds / 60).toStringAsFixed(1)} min > 90% HRmax)'
              : (isPlannedVo2Hit
                    ? 'Geplante VO2max-Intervalleinheit nach Workout Prescription absolviert'
                    : 'Sehr hohe subjektive und mechanische Intervall-Auslastung (RPE $rpe)'),
          confidence: hasZ5Accumulation ? 0.95 : 0.85,
          primaryEnergySystem: 'aerobic_vo2max',
          origin: isPlannedVo2Hit
              ? StimulusOrigin.verified
              : StimulusOrigin.observed,
          plannedType: plannedStimulusType,
          complianceRate: 1.0,
        ),
      );
    } else if (allowGenericHeartRateReference &&
        hrMean != null &&
        hrMean >= physiology.maxHeartRateBpm * 0.85) {
      // Hohe mittlere HF ohne Z5-Akkumulation = Schwellenbelastung / Tempodauer, kein VO2max!
      stimuli.add(
        TrainingStimulus(
          type: StimulusType.threshold,
          modality: modality,
          technique: session.technique,
          evidence:
              'Hohe mittlere HF (Ø ${hrMean.toStringAsFixed(0)} bpm / ${(hrMean / physiology.maxHeartRateBpm * 100).toStringAsFixed(0)}% HRmax) ohne Z5-Intervallnachweis indiziert Schwellen-/Tempobelastung',
          confidence: 0.85,
          primaryEnergySystem: 'aerobic_glycolytic_threshold',
          origin: plannedStimulusType == StimulusType.threshold
              ? StimulusOrigin.verified
              : StimulusOrigin.observed,
          plannedType: plannedStimulusType,
          complianceRate: 1.0,
        ),
      );
    }

    // 6. Aktive Erholung (Recovery)
    if (durationMin <= 45 &&
        ((rpe != null && rpe <= 3.0) ||
            (allowGenericHeartRateReference &&
                hrMean != null &&
                hrMean <= physiology.maxHeartRateBpm * 0.65))) {
      stimuli.add(
        TrainingStimulus(
          type: StimulusType.recovery,
          modality: modality,
          technique: session.technique,
          evidence:
              'Kurze, regenerative Einheit (${durationMin.toStringAsFixed(0)} min) ohne Glykogen-Erschöpfung',
          confidence: 0.90,
          primaryEnergySystem: 'active_recovery',
          origin: plannedStimulusType == StimulusType.recovery
              ? StimulusOrigin.verified
              : StimulusOrigin.observed,
          plannedType: plannedStimulusType,
          complianceRate: 1.0,
        ),
      );
    }

    // Falls ein plannedStimulus vorlag, der nicht erfüllt wurde, als Soll-Reiz festhalten:
    if (plannedStimulusType != null &&
        !stimuli.any((s) => s.type == plannedStimulusType)) {
      stimuli.add(
        TrainingStimulus(
          type: plannedStimulusType,
          modality: modality,
          technique: session.technique,
          evidence:
              'Geplanter Reiz ($plannedStimulusType) wurde in den Messdaten nicht nachgewiesen',
          confidence: 0.50,
          origin: StimulusOrigin.planned,
          plannedType: plannedStimulusType,
          complianceRate: 0.0,
        ),
      );
    }

    return StimulusLedger(
      sessionId: session.id,
      athleteId: session.athleteId,
      startedAtUtcUs: session.startedAtUtcUs,
      stimuli: stimuli,
    );
  }

  ExternalLoad _calculateExternalLoad(NormalizedSession session) {
    final sessionWatt =
        session.externalMetrics.sessionAveragePowerWatt ??
        session.externalMetrics.averagePowerWatt;

    return ExternalLoad(
      durationSeconds: session.durationSeconds,
      workJoule: session.externalMetrics.workJoule,
      sessionAveragePowerWatt: sessionWatt,
      intervalAveragePowerWatt:
          session.externalMetrics.intervalAveragePowerWatt,
      workPhaseAveragePowerWatt:
          session.externalMetrics.workPhaseAveragePowerWatt,
      peakPowerWatt: session.externalMetrics.peakPowerWatt,
      normalizedPowerWatt: session.externalMetrics.normalizedPowerWatt,
      distanceMetres: session.distanceMetres,
      elevationGainMetres: session.elevationGainMetres,
      strokeCount: session.externalMetrics.strokeCount,
      strokeRatePerMinute: session.externalMetrics.strokeOrCadenceRate,
      leftRightSymmetryPercent:
          session.externalMetrics.leftRightSymmetryPercent,
      confidence:
          session.dataQuality.externalConfidence ??
          (session.externalMetrics.hasPower
              ? session.dataQuality.confidence
              : (session.distanceMetres != null ? 0.90 : null)),
      provenance: session.source.key,
    );
  }

  InternalLoad _calculateInternalLoad(
    NormalizedSession session,
    AthletePhysiology physiology, {
    required bool allowGenericHeartRateReference,
  }) {
    final hrMean = session.internalMetrics.averageHeartRateBpm;
    if (hrMean == null || hrMean <= 0) {
      // Keine erfundenen Werte bei fehlender HF!
      return InternalLoad(
        confidence: null,
        provenance: 'no_heart_rate_recorded',
      );
    }

    final durationMin = session.movingTimeSeconds / 60.0;
    final maxHr = physiology.maxHeartRateBpm;
    final restHr = physiology.restingHeartRateBpm;

    // 1. Banister TRIMP Berechnung (Schätzung / Proxy, keine biologische Naturkonstante)
    double? banisterTrimp;
    if (allowGenericHeartRateReference && maxHr > restHr && hrMean >= restHr) {
      final deltaHr = ((hrMean - restHr) / (maxHr - restHr)).clamp(0.0, 1.0);
      final y = physiology.banisterGenderFactorY;
      final b = physiology.banisterFactorB;
      banisterTrimp = durationMin * deltaHr * b * math.exp(y * deltaHr);
    }

    // 2. Edwards Zonal TRIMP (Grober Zonen-Stufenproxy)
    double? edwardsTrimp;
    final zones = session.internalMetrics.timeInHrZonesSeconds;
    if (zones.isNotEmpty) {
      var weightedSum = 0.0;
      final z1 = (zones['z1'] ?? 0) / 60.0;
      final z2 = (zones['z2'] ?? 0) / 60.0;
      final z3 = (zones['z3'] ?? 0) / 60.0;
      final z4 = (zones['z4'] ?? 0) / 60.0;
      final z5 = (zones['z5'] ?? 0) / 60.0;
      weightedSum =
          (z1 * 1.0) + (z2 * 2.0) + (z3 * 3.0) + (z4 * 4.0) + (z5 * 5.0);
      if (weightedSum > 0) {
        edwardsTrimp = weightedSum;
      }
    } else if (allowGenericHeartRateReference) {
      // Annäherung nach Edwards Zonen anhand der mittleren HF
      final hrRatio = hrMean / maxHr;
      final zoneWeight = hrRatio >= 0.90
          ? 5.0
          : (hrRatio >= 0.80
                ? 4.0
                : (hrRatio >= 0.70 ? 3.0 : (hrRatio >= 0.60 ? 2.0 : 1.0)));
      edwardsTrimp = durationMin * zoneWeight;
    }

    var hrConfidence = session.dataQuality.internalConfidence ?? 0.90;
    if (session.dataQuality.warnings.any(
      (w) => w.toLowerCase().contains('hr') || w.toLowerCase().contains('herz'),
    )) {
      hrConfidence = (hrConfidence * 0.8).clamp(0.1, 1.0);
    }

    return InternalLoad(
      trimpBanister: banisterTrimp,
      trimpEdwards: edwardsTrimp,
      averageHeartRateBpm: hrMean,
      peakHeartRateBpm: session.internalMetrics.peakHeartRateBpm,
      timeInHrZonesSeconds: zones,
      confidence: hrConfidence,
      provenance: allowGenericHeartRateReference
          ? 'heart_rate_estimated_proxy_${physiology.banisterModelVersion}'
          : 'heart_rate_without_individual_reference',
    );
  }

  PerceivedLoad _calculatePerceivedLoad(NormalizedSession session) {
    final rpe = session.internalMetrics.rpe;
    if (rpe == null || rpe <= 0) {
      return const PerceivedLoad();
    }

    final durationMin = session.movingTimeSeconds / 60.0;
    final srpe = rpe * durationMin;

    return PerceivedLoad(
      rpe: rpe,
      durationMinutes: durationMin,
      srpeLoad: srpe,
      confidence: 0.95, // Direkte subjektive Angabe des Athleten
    );
  }
}
