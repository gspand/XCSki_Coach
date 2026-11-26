/// Wissenschaftlich fundierte Intensitätsvorgabe (Intensity Prescription & Multi-Anchor Target).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Keine erfundenen Wattzahlen:
///   Ein FTP-Wert vom Fahrrad darf NIEMALS auf Langlauf-Skating oder Ercolina
///   übertragen werden!
/// - Wattwerte werden NUR vorgeschrieben, wenn eine valide Diagnostik FÜR DIESE MODALITÄT
///   vorliegt (z. B. Ercolina-Stufentest für Ercolina-Training).
/// - Multi-Anchor Intensity Target:
///   1. Trainingsabsicht (Workout Intent)
///   2. Sprech- und Atemkriterien (Talk Test & Breathing Cues)
///   3. RPE-Zielkorridor (Borg CR10, z. B. RPE 2–3 für lockere Grundlagenausdauer)
///   4. Geländeleitplanken (Terrain Guidance, z. B. Druck an Anstiegen aktiv drosseln)
///   5. Sekundäre Herzfrequenz (als begleitende Beobachtung, nicht als Autopilot)
library;

import '../../domain/xc_modality.dart';
import '../load/stimulus_models.dart';
import '../xc_athlete_state/diagnostics_state.dart';
import '../xc_athlete_state/evidence_model.dart';

/// Art der Intensitätssteuerung.
enum IntensityTargetType {
  multiAnchor('Multi-Anchor Zielsteuerung'),
  powerWatt('Wattbereich'),
  heartRateBpm('Herzfrequenzbereich (bpm)'),
  percentHrMax('% HRmax'),
  rpe('Subjektive Anstrengung (Borg CR10)'),
  qualitativePace('Qualitatives Geländetempo');

  const IntensityTargetType(this.label);
  final String label;
}

/// Strukturierte Intensitätsvorgabe mit mehreren Verankerungspunkten (Multi-Anchor).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - RPE (Borg CR10) ist eine Orientierung für die wahrgenommene Anstrengung
///   (Perceived Effort Guidance) und KEINE physiologische Messgröße oder Zonenwahrheit!
/// - Die physiologische Reizklassifikation (Observed Stimulus Evidence) entsteht
///   erst post-hoc aus der tatsächlich beobachteten Session.
/// - Unbeobachtete Laktataussagen sind unzulässig; Laktat wird nur bei echter Messung bewertet.
class IntensityPrescription {
  const IntensityPrescription({
    required this.modality,
    required this.targetType,
    required this.zoneLabel,
    required this.rationale,
    this.workoutIntent = '',
    this.talkTestBreathingCues = '',
    this.rpeTarget = '',
    String? perceivedEffortGuidance,
    this.terrainGuidance = '',
    this.hrGuidance,
    this.minPowerWatt,
    this.maxPowerWatt,
    this.minHrBpm,
    this.maxHrBpm,
    this.minPercentHrMax,
    this.maxPercentHrMax,
    this.minRpe,
    this.maxRpe,
    this.evidenceSource,
    this.isDiagnosticGrounded = false,
  }) : perceivedEffortGuidance = perceivedEffortGuidance ?? rpeTarget;

  final XcModality modality;
  final IntensityTargetType targetType;
  final String zoneLabel;
  final String rationale;

  /// Trainingsabsicht (z. B. "Ökonomisierung aerobe Basis", "Verschiebung LT2", "VO2max HIT").
  final String workoutIntent;

  /// Sprechtest und Atmungs-Cues (z. B. "Volle Sätze möglich", "Kurze Halbsätze", "Sprechunfähig").
  final String talkTestBreathingCues;

  /// Subjektive Vorgabe der wahrgenommenen Anstrengung (Perceived Effort Guidance, z. B. "RPE 2.0–3.0 (sehr locker bis locker)").
  final String perceivedEffortGuidance;

  /// Rückwärtskompatibler Alias für perceivedEffortGuidance.
  final String rpeTarget;

  /// Geländeanweisung (z. B. "Anstiege aktiv deckeln", "Gleichmäßige Steigung 4%").
  final String terrainGuidance;

  /// Sekundäre Herzfrequenz-Orientierung (nicht als primärer Autopilot).
  final String? hrGuidance;

  final double? minPowerWatt;
  final double? maxPowerWatt;
  final int? minHrBpm;
  final int? maxHrBpm;
  final double? minPercentHrMax;
  final double? maxPercentHrMax;
  final double? minRpe;
  final double? maxRpe;

  /// Rückverweis auf die diagnostische Grundlage (z. B. "Ercolina Stufentest 2026-09-15").
  final String? evidenceSource;

  /// Gibt an, ob die Vorgabe auf einer validen sportspezifischen Labordiagnostik beruht.
  final bool isDiagnosticGrounded;

  /// Menschenlesbare Kurzbeschreibung der Intensitätsvorgabe.
  String get displayInstruction {
    final parts = <String>[zoneLabel];
    if (minPowerWatt != null && maxPowerWatt != null) {
      parts.add('${minPowerWatt!.round()}–${maxPowerWatt!.round()} W');
    }
    if (minHrBpm != null && maxHrBpm != null) {
      parts.add('${minHrBpm}–${maxHrBpm} bpm');
    } else if (minPercentHrMax != null && maxPercentHrMax != null) {
      parts.add(
        '${(minPercentHrMax! * 100).round()}–${(maxPercentHrMax! * 100).round()}% HRmax',
      );
    }
    if (rpeTarget.isNotEmpty) {
      parts.add(rpeTarget);
    } else if (minRpe != null && maxRpe != null) {
      parts.add(
        'RPE ${minRpe!.toStringAsFixed(0)}–${maxRpe!.toStringAsFixed(0)}/10',
      );
    }
    return parts.join(' · ');
  }

  factory IntensityPrescription.fromJson(Map<String, dynamic> j) =>
      IntensityPrescription(
        zoneLabel: j['zoneLabel'] as String,
        rationale: j['rationale'] as String,
        workoutIntent: j['workoutIntent'] as String? ?? '',
        talkTestBreathingCues: j['talkTestBreathingCues'] as String? ?? '',
        rpeTarget: j['rpeTarget'] as String? ?? '',
        terrainGuidance: j['terrainGuidance'] as String? ?? '',
        hrGuidance: j['hrGuidance'] as String?,
        evidenceSource: j['evidenceSource'] as String?,
        perceivedEffortGuidance: j['perceivedEffortGuidance'] as String?,
        minPowerWatt: (j['minPowerWatt'] as num?)?.toDouble(),
        maxPowerWatt: (j['maxPowerWatt'] as num?)?.toDouble(),
        minPercentHrMax: (j['minPercentHrMax'] as num?)?.toDouble(),
        maxPercentHrMax: (j['maxPercentHrMax'] as num?)?.toDouble(),
        minRpe: (j['minRpe'] as num?)?.toDouble(),
        maxRpe: (j['maxRpe'] as num?)?.toDouble(),
        minHrBpm: j['minHrBpm'] as int?,
        maxHrBpm: j['maxHrBpm'] as int?,
        modality: XcModality.values.byName(j['modality'] as String),
        targetType: IntensityTargetType.values.byName(
          j['targetType'] as String,
        ),
        isDiagnosticGrounded: j['isDiagnosticGrounded'] == true,
      );

  Map<String, dynamic> toJson() => {
    'modality': modality.name,
    'targetType': targetType.name,
    'zoneLabel': zoneLabel,
    'rationale': rationale,
    'workoutIntent': workoutIntent,
    'talkTestBreathingCues': talkTestBreathingCues,
    'rpeTarget': rpeTarget,
    'perceivedEffortGuidance': perceivedEffortGuidance,
    'terrainGuidance': terrainGuidance,
    'hrGuidance': hrGuidance,
    'minPowerWatt': minPowerWatt,
    'maxPowerWatt': maxPowerWatt,
    'minHrBpm': minHrBpm,
    'maxHrBpm': maxHrBpm,
    'minPercentHrMax': minPercentHrMax,
    'maxPercentHrMax': maxPercentHrMax,
    'minRpe': minRpe,
    'maxRpe': maxRpe,
    'evidenceSource': evidenceSource,
    'isDiagnosticGrounded': isDiagnosticGrounded,
    'displayInstruction': displayInstruction,
  };
}

/// Löst Intensitätsvorgaben evidenzbasiert aus dem DiagnosticsState auf.
class IntensityResolver {
  const IntensityResolver();

  /// Löst die Arbeitsintensität für einen Reiz und eine Modalität auf.
  IntensityPrescription resolveWorkIntensity({
    required XcModality modality,
    required StimulusType stimulus,
    required DiagnosticsState diagnostics,
  }) {
    // 1. Ercolina Doppelstock
    if (modality == XcModality.ercolinaDoublePoling) {
      final ercolinaDiag = diagnostics.ercolina;
      final hasValidWatt =
          ercolinaDiag != null &&
          ercolinaDiag.lt2Ltp2Watt != null &&
          (ercolinaDiag.freshness == FreshnessLevel.fresh ||
              ercolinaDiag.freshness == FreshnessLevel.maturing);

      if (hasValidWatt) {
        final ltp2 = ercolinaDiag.lt2Ltp2Watt!;
        switch (stimulus) {
          case StimulusType.vo2max:
            return IntensityPrescription(
              modality: modality,
              targetType: IntensityTargetType.powerWatt,
              zoneLabel: 'Z4 VO2max Intervall',
              workoutIntent:
                  'Maximale Sauerstoffaufnahme des Oberkörpers am Zuggerät',
              talkTestBreathingCues:
                  'Sprechunfähig, fordernde ventilatorische Ausbelastung',
              rpeTarget: 'RPE 8.5–9.5 (sehr hart bis maximal)',
              terrainGuidance:
                  'Stationär am Zuggerät; saubere Rumpfbeugung, keine unkontrollierten Ausweichbewegungen im Lendenwirbelbereich',
              minPowerWatt: ltp2 * 1.05,
              maxPowerWatt: ltp2 * 1.20,
              minRpe: 8.5,
              maxRpe: 9.5,
              rationale:
                  'Basierend auf Ercolina-Diagnostik (${ercolinaDiag.protocol}, LTP2: ${ltp2.round()} W).',
              evidenceSource:
                  'Diagnostics: ${ercolinaDiag.protocol} (${ercolinaDiag.date.toIso8601String().split("T").first})',
              isDiagnosticGrounded: true,
            );
          case StimulusType.threshold:
            return IntensityPrescription(
              modality: modality,
              targetType: IntensityTargetType.powerWatt,
              zoneLabel: 'Z3 Schwellenbereich (EB)',
              workoutIntent:
                  'Verschiebung der aeroben Schwelle und Zugausdauer am Zuggerät',
              talkTestBreathingCues:
                  'Kurze Halbsätze möglich, tiefe rhythmische Doppelstock-Atmung',
              rpeTarget: 'RPE 7.0–8.0 (kontrolliert hart)',
              terrainGuidance:
                  'Stationär am Zuggerät; Zugrhythmus gleichmäßig bei 48–56 Zügen/min halten',
              minPowerWatt: ltp2 * 0.92,
              maxPowerWatt: ltp2 * 1.02,
              minRpe: 7.0,
              maxRpe: 8.0,
              rationale:
                  'EB-Bereich 92–102% der Ercolina-LTP2 (${ltp2.round()} W).',
              evidenceSource:
                  'Diagnostics: ${ercolinaDiag.protocol} (${ercolinaDiag.date.toIso8601String().split("T").first})',
              isDiagnosticGrounded: true,
            );
          case StimulusType.doublePolingPower:
            return IntensityPrescription(
              modality: modality,
              targetType: IntensityTargetType.powerWatt,
              zoneLabel: 'Maximaler DP-Schnellkraftstoß',
              workoutIntent:
                  'Neuromuskuläre DP-Spitzenleistung und Explosivität',
              talkTestBreathingCues:
                  'Pressatmung während des Stoßes, volle Erholung zwischen den Wiederholungen',
              rpeTarget: 'RPE 9.5–10 (maximaler Krafteinsatz)',
              terrainGuidance:
                  'Stationär am Zuggerät; volle Hebelwirkung aus dem Latissimus und Rumpf',
              minPowerWatt: ltp2 * 1.30,
              maxPowerWatt: ltp2 * 1.80,
              minRpe: 9.5,
              maxRpe: 10.0,
              rationale: 'Neuromuskuläre DP-Leistung oberhalb LTP2.',
              evidenceSource: 'Diagnostics: ${ercolinaDiag.protocol}',
              isDiagnosticGrounded: true,
            );
          default:
            return IntensityPrescription(
              modality: modality,
              targetType: IntensityTargetType.powerWatt,
              zoneLabel: 'Z1/Z2 DP Grundlage',
              workoutIntent:
                  'Ökonomischer Doppelstock-Dauerzug im aeroben Grundlagenbereich',
              talkTestBreathingCues:
                  'Sprechen in ganzen Sätzen problemlos möglich, ruhige Nasen-/Mundatmung',
              rpeTarget: 'RPE 2.5–3.5 (locker bis moderat)',
              terrainGuidance:
                  'Stationär am Zuggerät; Widerstand moderat wählen, sauberes Einfallen in den Stockeinsatz',
              minPowerWatt: ltp2 * 0.60,
              maxPowerWatt: ltp2 * 0.75,
              minRpe: 2.5,
              maxRpe: 3.5,
              rationale:
                  'Grundlagenbereich 60–75% der Ercolina-LTP2 (${ltp2.round()} W).',
              evidenceSource: 'Diagnostics: ${ercolinaDiag.protocol}',
              isDiagnosticGrounded: true,
            );
        }
      }

      // Fallback für Ercolina ohne valide Wattdiagnostik: Subjektive Steuerung (RPE)
      return _buildRpeFallback(
        modality: modality,
        stimulus: stimulus,
        reason:
            'Keine valide Ercolina-Wattdiagnostik verfügbar. Steuerung nach RPE und Zuggefühl.',
      );
    }

    // 2. Skilanglauf Skating (Schnee)
    if (modality == XcModality.skiSkating ||
        modality == XcModality.skiClassic) {
      final skateDiag = diagnostics.skating;
      final hrMax =
          (skateDiag?.maxHeartRateBpm ??
                  diagnostics.cycling?.maxHeartRateBpm ??
                  diagnostics.running?.maxHeartRateBpm)
              ?.round();

      switch (stimulus) {
        case StimulusType.vo2max:
          return IntensityPrescription(
            modality: modality,
            targetType: hrMax != null
                ? IntensityTargetType.percentHrMax
                : IntensityTargetType.rpe,
            zoneLabel: 'Z4 VO2max Intervalle',
            workoutIntent:
                'Maximierung der kardiovaskulären Kapazität und aeroben Spitzenleistung auf Schnee',
            talkTestBreathingCues:
                'Nur einzelne Worte oder sprechunfähig; fordernde Hechelatmung am Ende jedes Intervalls',
            rpeTarget: 'RPE 8.5–9.5 (sehr hart bis nahezu ausbelastend)',
            terrainGuidance:
                'Gleichmäßiger Anstieg (4–8%) für maximale Sauerstoffaufnahme bei dynamischer Skiführung ohne Überdrehen',
            hrGuidance: hrMax != null
                ? 'Sekundäre Orientierung: 90–95% HRmax (${(hrMax * 0.90).round()}–${(hrMax * 0.95).round()} bpm). Achtung: Puls reagiert mit Verzögerung, Anstiegsbeginn nicht überpacen.'
                : 'Pulsdaten sekundär; Belastung nach RPE und Geländesteigung steuern.',
            minPercentHrMax: hrMax != null ? 0.90 : null,
            maxPercentHrMax: hrMax != null ? 0.95 : null,
            minHrBpm: hrMax != null ? (hrMax * 0.90).round() : null,
            maxHrBpm: hrMax != null ? (hrMax * 0.95).round() : null,
            minRpe: 8.5,
            maxRpe: 9.5,
            rationale:
                'Sehr hohe Belastung. Schnelle, dynamische Gleitphasen an Anstiegen.',
            isDiagnosticGrounded: skateDiag != null,
          );
        case StimulusType.threshold:
          return IntensityPrescription(
            modality: modality,
            targetType: hrMax != null
                ? IntensityTargetType.percentHrMax
                : IntensityTargetType.rpe,
            zoneLabel: 'Z3 Schwellenbereich (EB)',
            workoutIntent:
                'Verschiebung der aeroben Schwellenleistung und Dauerleistungsfähigkeit',
            talkTestBreathingCues:
                'Kurze Phrasen und Halbsätze möglich; tiefe, konzentrierte Atmung',
            rpeTarget: 'RPE 6.5–7.5 (kontrolliert hart, gleichmäßig haltbar)',
            terrainGuidance:
                'Gleichmäßige moderate Steigung (2–4%) oder flacher Rundkurs; Tempo an Steigungen nicht explodieren lassen, sondern Druck konstant halten',
            hrGuidance: hrMax != null
                ? 'Sekundäre Orientierung: 82–88% HRmax (${(hrMax * 0.82).round()}–${(hrMax * 0.88).round()} bpm). Nicht vom Gelände überraschen lassen.'
                : 'Pulsdaten sekundär; Intensität über kontrollierten Druck und Sprechtest stabilisieren.',
            minPercentHrMax: hrMax != null ? 0.82 : null,
            maxPercentHrMax: hrMax != null ? 0.88 : null,
            minHrBpm: hrMax != null ? (hrMax * 0.82).round() : null,
            maxHrBpm: hrMax != null ? (hrMax * 0.88).round() : null,
            minRpe: 7.0,
            maxRpe: 8.0,
            rationale:
                'Kontrolliert zügig, Atmung tief aber gleichmäßig, Belastung stabil halten.',
            isDiagnosticGrounded: skateDiag != null,
          );
        case StimulusType.fatigueResistance:
          return IntensityPrescription(
            modality: modality,
            targetType: hrMax != null
                ? IntensityTargetType.percentHrMax
                : IntensityTargetType.rpe,
            zoneLabel: 'Z2 Langzeitausdauer',
            workoutIntent:
                'Ausbildung von Ermüdungsresistenz, Fettstoffwechsel und technischer Durability',
            talkTestBreathingCues:
                'Sprechen in vollständigen Sätzen jederzeit möglich; gleichmäßige Ruheatmung',
            rpeTarget: 'RPE 2.5–3.5 (locker bis moderat)',
            terrainGuidance:
                'Kupiertes Terrain mit Fokus auf Gleitökonomie; an allen Anstiegen Druck aktiv drosseln, sodass der lockere Charakter der Einheit erhalten bleibt',
            hrGuidance: hrMax != null
                ? 'Sekundäre Orientierung: 65–75% HRmax (${(hrMax * 0.65).round()}–${(hrMax * 0.75).round()} bpm). Kardialer Drift nach 90 min normal.'
                : 'Orientierung nach RPE und lockerer Konversation.',
            minPercentHrMax: hrMax != null ? 0.65 : null,
            maxPercentHrMax: hrMax != null ? 0.75 : null,
            minHrBpm: hrMax != null ? (hrMax * 0.65).round() : null,
            maxHrBpm: hrMax != null ? (hrMax * 0.75).round() : null,
            minRpe: 2.5,
            maxRpe: 3.5,
            rationale:
                'Lange skispezifische Grundlageneinheit. Anstiege strikt dosieren.',
            isDiagnosticGrounded: skateDiag != null,
          );
        default:
          return IntensityPrescription(
            modality: modality,
            targetType: hrMax != null
                ? IntensityTargetType.percentHrMax
                : IntensityTargetType.rpe,
            zoneLabel: 'Z2 Grundlagenausdauer',
            workoutIntent:
                'Ruhiges, ökonomisches Gleiten im rein aeroben Stoffwechselbereich',
            talkTestBreathingCues:
                'Sprechen in ganzen Sätzen problemlos möglich; ruhige Nasen-/Mundatmung',
            rpeTarget: 'RPE 2.0–3.0 (sehr locker bis locker)',
            terrainGuidance:
                'Flaches bis leicht kupiertes Gelände; an Anstiegen bewusst Tempo drosseln und flüssig weitergleiten',
            hrGuidance: hrMax != null
                ? 'Sekundäre Orientierung: 65–75% HRmax (${(hrMax * 0.65).round()}–${(hrMax * 0.75).round()} bpm).'
                : 'Orientierung primär über Sprechfähigkeit.',
            minPercentHrMax: hrMax != null ? 0.65 : null,
            maxPercentHrMax: hrMax != null ? 0.75 : null,
            minHrBpm: hrMax != null ? (hrMax * 0.65).round() : null,
            maxHrBpm: hrMax != null ? (hrMax * 0.75).round() : null,
            minRpe: 2.0,
            maxRpe: 3.5,
            rationale:
                'Ruhiges, ökonomisches Gleiten im aeroben Bereich. Volle Sprechfähigkeit.',
            isDiagnosticGrounded: skateDiag != null,
          );
      }
    }

    // 3. Allgemeiner Fallback für sonstige Sportarten
    return _buildRpeFallback(
      modality: modality,
      stimulus: stimulus,
      reason:
          'Steuerung über subjektive Anstrengung (RPE) und Bewegungsökonomie.',
    );
  }

  /// Löst die Pausen- bzw. Regenerationsintensität auf.
  IntensityPrescription resolveRecoveryIntensity({
    required XcModality modality,
  }) {
    return const IntensityPrescription(
      modality: XcModality.skiSkating,
      targetType: IntensityTargetType.rpe,
      zoneLabel: 'Z1 Aktive Erholung',
      workoutIntent: 'Aktive Durchblutungsförderung und vegetative Entlastung',
      talkTestBreathingCues:
          'Völlig unbeschwertes Sprechen, minimale Atemanstrengung',
      rpeTarget: 'RPE 1.5–2.5 (extrem locker)',
      terrainGuidance: 'Flaches Gelände ohne nennenswerte Steigungen',
      minRpe: 1.5,
      maxRpe: 2.5,
      minPercentHrMax: 0.50,
      maxPercentHrMax: 0.65,
      rationale:
          'Sehr lockere Bewegung zur Förderung der Durchblutung und metabolischen Erholung.',
    );
  }

  IntensityPrescription _buildRpeFallback({
    required XcModality modality,
    required StimulusType stimulus,
    required String reason,
  }) {
    switch (stimulus) {
      case StimulusType.vo2max:
        return IntensityPrescription(
          modality: modality,
          targetType: IntensityTargetType.rpe,
          zoneLabel: 'Z4 VO2max (RPE)',
          workoutIntent: 'Maximale aerobe Ausbelastung',
          talkTestBreathingCues: 'Sprechunfähig, schwere Atmung',
          rpeTarget: 'RPE 8.5–9.5 (sehr hart)',
          terrainGuidance:
              'Anstieg oder ebene freie Strecke für ununterbrochene Intervalle',
          minRpe: 8.5,
          maxRpe: 9.5,
          rationale: reason,
          isDiagnosticGrounded: false,
        );
      case StimulusType.threshold:
        return IntensityPrescription(
          modality: modality,
          targetType: IntensityTargetType.rpe,
          zoneLabel: 'Z3 Schwellenbereich (RPE)',
          workoutIntent: 'Gleichmäßige Schwellenbelastung',
          talkTestBreathingCues: 'Kurze Sätze möglich',
          rpeTarget: 'RPE 6.5–7.5 (kontrolliert zügig)',
          terrainGuidance:
              'Flache bis mäßig ansteigende Strecke ohne Gefälle-Unterbrechung',
          minRpe: 7.0,
          maxRpe: 8.0,
          rationale: reason,
          isDiagnosticGrounded: false,
        );
      default:
        return IntensityPrescription(
          modality: modality,
          targetType: IntensityTargetType.rpe,
          zoneLabel: 'Z2 Grundlagenausdauer (RPE)',
          workoutIntent: 'Aerobe Basisausdauer',
          talkTestBreathingCues: 'Volle Sätze mühelos möglich',
          rpeTarget: 'RPE 2.0–3.0 (sehr locker bis locker)',
          terrainGuidance: 'Flaches bis welliges Gelände, Steigungen drosseln',
          minRpe: 2.0,
          maxRpe: 3.5,
          rationale: reason,
          isDiagnosticGrounded: false,
        );
    }
  }
}
