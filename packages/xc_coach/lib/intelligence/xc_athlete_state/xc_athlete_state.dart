/// Das zentrale sportwissenschaftliche Gedächtnis des Coaches: XCAthleteState.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Beantwortet: «Was wissen wir aktuell über diesen Langläufer, wodurch wissen wir es,
///   wie aktuell ist dieses Wissen und wie sicher ist es?»
/// - Keine Coachingentscheidungen, keine Trainingsfreigaben, keine Phantasie-Scores.
/// - Unbekannte Werte bleiben strikt UNKNOWN (keine Durchschnittswerte als Füllung).
/// - Lückenlose Rückverfolgbarkeit: State -> Evidence -> Session/Diagnostic -> Source.
library;

import '../../domain/xc_modality.dart';
import 'aerobic_threshold_hit_states.dart';
import 'data_coverage_state.dart';
import 'diagnostics_state.dart';
import 'double_poling_state.dart';
import 'durability_state.dart';
import 'elite_analysis_state.dart';
import 'goal_context.dart';
import 'performance_trend_state.dart';
import 'ski_exposure_state.dart';
import 'stimulus_history_state.dart';
import 'subjective_readiness_state.dart';
import 'training_load_state.dart';

class XCAthleteState {
  const XCAthleteState({
    required this.athleteId,
    required this.asOf,
    this.diagnostics = const DiagnosticsState(),
    this.aerobic = const AerobicState(),
    this.threshold = const ThresholdState(),
    this.highIntensity = const HighIntensityState(),
    this.skiExposure = const SkiSpecificExposureState(),
    this.doublePoling = const DoublePolingState(),
    this.durability = const DurabilityState(),
    this.trainingLoad = const TrainingLoadState(),
    this.stimulusHistory = const StimulusHistoryState(),
    this.subjectiveReadiness = const SubjectiveReadinessState(),
    this.performanceTrends = const PerformanceTrendState(),
    this.dataCoverage = const DataCoverageState(),
    this.eliteAnalysis = const EliteAnalysisState(),
    this.goal,
  });

  final String athleteId;
  final DateTime asOf;

  /// Diagnostische Schwellen nach Sportarten getrennt.
  final DiagnosticsState diagnostics;

  /// Evidenz zur aeroben Grundlagenausdauer.
  final AerobicState aerobic;

  /// Evidenz zur Schwellenkapazität (LTP2).
  final ThresholdState threshold;

  /// Evidenz zu hochintensiven Fähigkeiten (VO2max / HIT).
  final HighIntensityState highIntensity;

  /// Skispezifische Umfänge und Expositionen (7/28/90 Tage).
  final SkiSpecificExposureState skiExposure;

  /// Ercolina- und Oberkörper-Doppelstock-Zustand.
  final DoublePolingState doublePoling;

  /// Strukturierte Durability-Evidenz (PW:HR Entkopplung, Leistungserhalt).
  final DurabilityState durability;

  /// Rollierende Belastungszeitreihen (Banister TRIMP, sRPE, Work kJ).
  final TrainingLoadState trainingLoad;

  /// Historie aller 14 Trainingsreize (geplant vs. beobachtet vs. verifiziert).
  final StimulusHistoryState stimulusHistory;

  /// Subjektive Bereitschaftsevidenz (DOMS, Schlaf, Symptome).
  final SubjectiveReadinessEvidence subjectiveReadiness;

  /// Apples-to-Apples Leistungsvergleiche vergleichbarer Sessions.
  final PerformanceTrendState performanceTrends;

  /// Transparenz über Datenlücken und Sensorqualität.
  final DataCoverageState dataCoverage;

  /// Vollständige Langzeit-, Periodisierungs- und Bestwertanalyse.
  /// Enthält nur beobachtete Fakten und explizite Evidenzlücken.
  final EliteAnalysisState eliteAnalysis;

  /// Aktuelles Hauptziel des Athleten.
  final GoalContext? goal;

  XCAthleteState copyWith({
    String? athleteId,
    DateTime? asOf,
    DiagnosticsState? diagnostics,
    AerobicState? aerobic,
    ThresholdState? threshold,
    HighIntensityState? highIntensity,
    SkiSpecificExposureState? skiExposure,
    DoublePolingState? doublePoling,
    DurabilityState? durability,
    TrainingLoadState? trainingLoad,
    StimulusHistoryState? stimulusHistory,
    SubjectiveReadinessState? subjectiveReadiness,
    PerformanceTrendState? performanceTrends,
    DataCoverageState? dataCoverage,
    EliteAnalysisState? eliteAnalysis,
    GoalContext? goal,
  }) {
    return XCAthleteState(
      athleteId: athleteId ?? this.athleteId,
      asOf: asOf ?? this.asOf,
      diagnostics: diagnostics ?? this.diagnostics,
      aerobic: aerobic ?? this.aerobic,
      threshold: threshold ?? this.threshold,
      highIntensity: highIntensity ?? this.highIntensity,
      skiExposure: skiExposure ?? this.skiExposure,
      doublePoling: doublePoling ?? this.doublePoling,
      durability: durability ?? this.durability,
      trainingLoad: trainingLoad ?? this.trainingLoad,
      stimulusHistory: stimulusHistory ?? this.stimulusHistory,
      subjectiveReadiness: subjectiveReadiness ?? this.subjectiveReadiness,
      performanceTrends: performanceTrends ?? this.performanceTrends,
      dataCoverage: dataCoverage ?? this.dataCoverage,
      eliteAnalysis: eliteAnalysis ?? this.eliteAnalysis,
      goal: goal ?? this.goal,
    );
  }

  /// Liefert die lückenlose Rückverfolgbarkeitskette für eine gegebene Domäne.
  String traceEvidenceFor(String domain) {
    switch (domain.toLowerCase()) {
      case 'skating_threshold':
      case 'skating_lt2':
        final ref = diagnostics.skating;
        if (ref == null) {
          return 'Skating LT2: UNKNOWN (keine Diagnostik vorhanden)';
        }
        return 'State: Skating LTP2 ${ref.lt2Ltp2Watt ?? ref.lt2Ltp2Bpm} '
            '-> Evidenz: ${ref.protocol} (${ref.date.toIso8601String().split('T').first}) '
            '-> Quelle: ${ref.source} (Test-ID: ${ref.sourceId ?? "keine"}) '
            '-> Frische: ${ref.freshness.label}, Konfidenz: ${(ref.confidence * 100).toStringAsFixed(0)}%';

      case 'ercolina_dp':
      case 'double_poling':
        final calibStr = doublePoling.calibrationConfidence != null
            ? '${(doublePoling.calibrationConfidence! * 100).toStringAsFixed(0)}%'
            : 'unkalibriert';
        return 'State: DP Power ${(doublePoling.recentSessionAveragePowerWatt ?? 0).toStringAsFixed(0)} W '
            '-> Evidenz: Kalibrierungsgüte $calibStr, '
            'Arbeitsphasen-Power ${(doublePoling.workPhaseAveragePowerWatt ?? 0).toStringAsFixed(0)} W '
            '-> Sessions: ${doublePoling.recentSessionIds.join(", ")} '
            '-> Quelle: Ercolina First-Party Sensor V2';

      case 'durability':
        if (!durability.hasMeasuredObservations) {
          return 'State: Durability: Reine Exposition (${durability.longSessionExposureHours28d.toStringAsFixed(1)} h in Einheiten >= 90 min) '
              '-> Gemessene Entkopplungs-Evidenz: KEINE VORHANDEN';
        }
        final obs = durability.observations.first;
        return 'State: Durability Entkopplung ${obs.value}${obs.unit != null ? " ${obs.unit}" : ""} '
            '-> Evidenz: ${obs.type.label} (${obs.conditions ?? "Standard"}) '
            '-> Session: ${obs.sessionId} -> Quelle: ${obs.provenance} '
            '-> Konfidenz: ${(obs.confidence * 100).toStringAsFixed(0)}%';

      case 'ski_exposure':
        return 'State: Skispezifischer 28d-Umfang ${(skiExposure.totalSkiSpecificDurationSeconds28d / 3600).toStringAsFixed(1)} h '
            '(Schnee: ${(skiExposure.onSnowDurationSeconds28d / 3600).toStringAsFixed(1)} h, '
            'Ercolina: ${(skiExposure.ercolinaDurationSeconds28d / 3600).toStringAsFixed(1)} h, '
            'Rollski: ${(skiExposure.rollerSkiDurationSeconds28d / 3600).toStringAsFixed(1)} h) '
            '-> Spezifitätsquote: ${(skiExposure.skiSpecificityRatio28d * 100).toStringAsFixed(0)}% '
            '-> Quelle: Kanonische NormalizedSessions';

      case 'cycling_threshold':
      case 'cycling_lt2':
        final ref = diagnostics.cycling;
        if (ref == null) {
          return 'Cycling LT2: UNKNOWN (keine Rad-Diagnostik vorhanden)';
        }
        return 'State: Cycling LTP2 ${ref.lt2Ltp2Watt ?? ref.lt2Ltp2Bpm} W '
            '-> Evidenz: ${ref.protocol} (${ref.date.toIso8601String().split('T').first}) '
            '-> Quelle: ${ref.source} (Test-ID: ${ref.sourceId ?? "keine"}) '
            '-> Frische: ${ref.freshness.label}, Konfidenz: ${(ref.confidence * 100).toStringAsFixed(0)}% [DARF NICHT AUF SKATING ÜBERTRAGEN WERDEN]';

      case 'running_threshold':
      case 'running_lt2':
        final ref = diagnostics.running;
        if (ref == null) {
          return 'Running LT2: UNKNOWN (keine Lauf-Diagnostik vorhanden)';
        }
        return 'State: Running LTP2 ${ref.lt2Ltp2Watt ?? ref.lt2Ltp2Bpm} '
            '-> Evidenz: ${ref.protocol} (${ref.date.toIso8601String().split('T').first}) '
            '-> Quelle: ${ref.source} '
            '-> Frische: ${ref.freshness.label}, Konfidenz: ${(ref.confidence * 100).toStringAsFixed(0)}% [DARF NICHT AUF SKATING ÜBERTRAGEN WERDEN]';

      case 'readiness':
      case 'subjective_readiness':
        if (!subjectiveReadiness.hasData) {
          return 'State: Subjektive Readiness: UNKNOWN (keine aktuellen Athleten-Einträge)';
        }
        return 'State: Erholung ${subjectiveReadiness.perceivedRecovery ?? "UNKNOWN"}/10, '
            'Oberkörper-DOMS ${subjectiveReadiness.upperBodySoreness ?? "UNKNOWN"}/10, '
            'Symptome: ${subjectiveReadiness.hasIllnessSymptoms ? subjectiveReadiness.illnessSymptoms.join(", ") : "keine"} '
            '-> Quelle: Direkte Athleteneingabe (${subjectiveReadiness.recordedAt?.toIso8601String().split('T').first ?? "unbekannt"}) '
            '-> Konfidenz: ${(subjectiveReadiness.confidence * 100).toStringAsFixed(0)}%';

      case 'training_load':
        return 'State: Banister EWMA (Akut: ${trainingLoad.latestBanisterState?.acuteLoad.toStringAsFixed(1) ?? "UNKNOWN"}, '
            'Chronisch: ${trainingLoad.latestBanisterState?.chronicLoad.toStringAsFixed(1) ?? "UNKNOWN"}), '
            'sRPE EWMA (Akut: ${trainingLoad.latestSrpeState?.acuteLoad.toStringAsFixed(1) ?? "UNKNOWN"}, '
            'Chronisch: ${trainingLoad.latestSrpeState?.chronicLoad.toStringAsFixed(1) ?? "UNKNOWN"}) '
            '-> Quelle: Getrennte EWMA-Zeitreihen ohne universellen TSS-Ersatz';

      default:
        return 'Domäne "$domain": Keine spezifische Evidenzkette registriert';
    }
  }

  /// Erstellt das ehrliche, transparente Fact Sheet des Athleten.
  /// UNKNOWN-Werte werden explizit und ungeschönt ausgewiesen.
  String toFactSheetText() {
    final buffer = StringBuffer();
    buffer.writeln('=== GIULIA XC ATHLETE STATE FACT SHEET ===');
    buffer.writeln(
      'Stichtag: ${asOf.toIso8601String().split('T').first} | Athlet: $athleteId',
    );
    buffer.writeln();

    // 1. Zielkontext
    buffer.writeln('1. ZIELKONTEXT:');
    if (goal != null) {
      final days = goal!.daysUntilGoal(asOf: asOf);
      buffer.writeln('  Ziel: ${goal!.name} (${goal!.modality.label})');
      buffer.writeln(
        '  Zieldatum: ${goal!.raceDate?.toIso8601String().split('T').first ?? "unbekannt"} (${days != null ? "$days Tage verbleibend" : "offen"})',
      );
      buffer.writeln(
        '  Distanz: ${goal!.targetDistanceKm?.toStringAsFixed(1) ?? "offen"} km | Zielzeit: ${goal!.targetDurationHours?.toStringAsFixed(2) ?? "offen"} h',
      );
    } else {
      buffer.writeln('  Aktuell kein Wettkampfziel hinterlegt.');
    }
    buffer.writeln();

    // 2. Leistungsdiagnostik
    buffer.writeln('2. PHYSIOLOGISCHE DIAGNOSTIK (getrennt nach Sportart):');
    final skRef = diagnostics.skating;
    if (skRef != null) {
      buffer.writeln(
        '  Skating LTP2: ${skRef.lt2Ltp2Watt?.toStringAsFixed(0) ?? "UNKNOWN"} W / ${skRef.lt2Ltp2Bpm?.toStringAsFixed(0) ?? "UNKNOWN"} bpm [${skRef.freshness.label}]',
      );
      buffer.writeln(
        '  Skating VO2max: ${skRef.vo2maxMlPerKgMin?.toStringAsFixed(1) ?? "UNKNOWN"} ml/kg/min',
      );
    } else {
      buffer.writeln('  Skating LT1 / LTP1: UNKNOWN');
      buffer.writeln('  Skating LT2 / LTP2: UNKNOWN');
      buffer.writeln('  Skating VO2max: UNKNOWN');
    }

    final erRef = diagnostics.ercolina;
    if (erRef != null) {
      buffer.writeln(
        '  Ercolina DP Critical Power: ${erRef.lt2Ltp2Watt?.toStringAsFixed(0) ?? "UNKNOWN"} W [${erRef.freshness.label}]',
      );
    } else {
      buffer.writeln('  Ercolina DP Schwellendiagnostik: UNKNOWN');
    }

    final runRef = diagnostics.running;
    if (runRef != null) {
      buffer.writeln(
        '  Laufen (historisch/fremdsportlich): LT2 ${runRef.lt2Ltp2Bpm?.toStringAsFixed(0) ?? "UNKNOWN"} bpm [${runRef.freshness.label}] (darf nicht auf Skating übertragen werden!)',
      );
    }

    final cycRef = diagnostics.cycling;
    if (cycRef != null) {
      buffer.writeln(
        '  Radfahren (historisch/fremdsportlich): FTP ${cycRef.lt2Ltp2Watt?.toStringAsFixed(0) ?? "UNKNOWN"} W [${cycRef.freshness.label}] (darf nicht auf Skating übertragen werden!)',
      );
    }
    buffer.writeln();

    // 3. Skispezifische Exposition
    buffer.writeln('3. SKISPEZIFISCHE EXPOSITION:');
    final coverageNotice = dataCoverage.unknownDays28d > 3
        ? ' (bezogen auf erfasste Trainingszeit; Historie lückenhaft: ${dataCoverage.unknownDays28d} Tage unbekannt)'
        : ' (bezogen auf erfasste Trainingszeit)';
    buffer.writeln(
      '  Letzte 28 Tage: ${(skiExposure.totalSkiSpecificDurationSeconds28d / 3600).toStringAsFixed(1)} h skispezifisch (Quote der beobachteten Trainingszeit: ${(skiExposure.skiSpecificityRatio28d * 100).toStringAsFixed(0)}%$coverageNotice)',
    );
    buffer.writeln(
      '  - Schnee Skating: ${(skiExposure.exposureOf(XcModality.skiSkating).durationSeconds28d / 3600).toStringAsFixed(1)} h (${skiExposure.exposureOf(XcModality.skiSkating).sessionCount28d} Sessions)',
    );
    buffer.writeln(
      '  - Schnee Klassisch: ${(skiExposure.exposureOf(XcModality.skiClassic).durationSeconds28d / 3600).toStringAsFixed(1)} h',
    );
    buffer.writeln(
      '  - Ercolina Doppelstock: ${(skiExposure.exposureOf(XcModality.ercolinaDoublePoling).durationSeconds28d / 3600).toStringAsFixed(1)} h (${skiExposure.exposureOf(XcModality.ercolinaDoublePoling).sessionCount28d} Sessions)',
    );
    buffer.writeln(
      '  - Rollski: ${(skiExposure.rollerSkiDurationSeconds28d / 3600).toStringAsFixed(1)} h',
    );
    buffer.writeln(
      '  - Unbekannter Skilanglauf: ${(skiExposure.exposureOf(XcModality.skiNordicUnknown).durationSeconds28d / 3600).toStringAsFixed(1)} h',
    );
    buffer.writeln(
      '  - Unspezifische Ausdauer (Rad/Lauf): ${(skiExposure.totalNonSkiDurationSeconds28d / 3600).toStringAsFixed(1)} h',
    );
    buffer.writeln();

    // 4. Doppelstock / Oberkörper
    buffer.writeln('4. ERCOLINA & DOPPELSTOCK:');
    buffer.writeln(
      '  Jüngste Einheiten-Leistung: ${doublePoling.recentSessionAveragePowerWatt?.toStringAsFixed(0) ?? "UNKNOWN"} W Ø',
    );
    buffer.writeln(
      '  Arbeitsphasen-Leistung: ${doublePoling.workPhaseAveragePowerWatt?.toStringAsFixed(0) ?? "UNKNOWN"} W',
    );
    final calibStr = doublePoling.calibrationConfidence != null
        ? '${(doublePoling.calibrationConfidence! * 100).toStringAsFixed(0)}%'
        : 'keine spezifische Kalibrierung hinterlegt';
    buffer.writeln(
      '  Kalibrierungs-Güte: $calibStr (Diagnostische Konfidenz: ${(doublePoling.diagnosticConfidence * 100).toStringAsFixed(0)}%)',
    );
    buffer.writeln(
      '  Akkumulierte DP-Arbeit (28d): ${doublePoling.totalWorkKiloJoule28d?.toStringAsFixed(0) ?? "UNKNOWN"} kJ',
    );
    buffer.writeln();

    // 5. Durability & Ermüdungswiderstand
    buffer.writeln('5. DURABILITY & ENTKOPPLUNG:');
    buffer.writeln(
      '  Langer Dauerumfang (>= 90 min, 28d): ${durability.longSessionExposureHours28d.toStringAsFixed(1)} h (${durability.longSessionCount28d} Einheiten) [REINE EXPOSITION]',
    );
    if (durability.hasMeasuredObservations) {
      buffer.writeln(
        '  Gemessene Durability-Beobachtungen: ${durability.observations.length}',
      );
      for (final obs in durability.observations) {
        buffer.writeln(
          '    - ${obs.type.label}: ${obs.value}${obs.unit != null ? " ${obs.unit}" : ""} (Konfidenz ${(obs.confidence * 100).toStringAsFixed(0)}%)',
        );
      }
    } else {
      buffer.writeln(
        '  Gemessene aerobe Entkopplung / Durability-Evidenz: KEINE VORHANDEN',
      );
    }
    buffer.writeln();

    // 6. Belastungsverlauf
    buffer.writeln('6. BELASTUNGSHISTORIE (EWMA):');
    buffer.writeln('  ${trainingLoad.descriptiveSummary}');
    buffer.writeln();

    // 7. Subjektive Bereitschaft
    buffer.writeln('7. SUBJEKTIVE RÜCKMELDUNG:');
    if (subjectiveReadiness.hasData) {
      buffer.writeln(
        '  Erholung: ${subjectiveReadiness.perceivedRecovery?.toStringAsFixed(1) ?? "UNKNOWN"} / 10',
      );
      buffer.writeln(
        '  Muskelkater Oberkörper: ${subjectiveReadiness.upperBodySoreness?.toStringAsFixed(1) ?? "UNKNOWN"} / 10',
      );
      buffer.writeln(
        '  Muskelkater Beine: ${subjectiveReadiness.legSoreness?.toStringAsFixed(1) ?? "UNKNOWN"} / 10',
      );
      buffer.writeln(
        '  Symptome Infekt: ${subjectiveReadiness.hasIllnessSymptoms ? subjectiveReadiness.illnessSymptoms.join(", ") : "keine"}',
      );
      buffer.writeln(
        '  Symptome Schmerz: ${subjectiveReadiness.hasPainSymptoms ? subjectiveReadiness.painSymptoms.join(", ") : "keine"}',
      );
    } else {
      buffer.writeln(
        '  Subjektive Rückmeldungen: UNKNOWN (keine aktuellen Athleten-Eingaben vorhanden)',
      );
    }
    buffer.writeln();

    // 8. Datenabdeckung
    buffer.writeln('8. DATENABDECKUNG & SICHERHEIT:');
    buffer.writeln('  ${dataCoverage.coverageAssessmentText}');
    buffer.writeln(
      '  Herzfrequenz-Abdeckung: ${(dataCoverage.hrCoverage * 100).toStringAsFixed(0)}% | Watt-Abdeckung: ${(dataCoverage.powerCoverage * 100).toStringAsFixed(0)}%',
    );
    buffer.writeln('===========================================');

    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
    'athleteId': athleteId,
    'asOf': asOf.toIso8601String(),
    'diagnostics': diagnostics.toJson(),
    'aerobic': aerobic.toJson(),
    'threshold': threshold.toJson(),
    'highIntensity': highIntensity.toJson(),
    'skiExposure': skiExposure.toJson(),
    'doublePoling': doublePoling.toJson(),
    'durability': durability.toJson(),
    'trainingLoad': trainingLoad.toJson(),
    'stimulusHistory': stimulusHistory.toJson(),
    'subjectiveReadiness': subjectiveReadiness.toJson(),
    'performanceTrends': performanceTrends.toJson(),
    'dataCoverage': dataCoverage.toJson(),
    'eliteAnalysis': eliteAnalysis.toJson(),
    if (goal != null) 'goal': goal!.toJson(),
  };

  factory XCAthleteState.fromJson(Map<String, dynamic> json) => XCAthleteState(
    athleteId: (json['athleteId'] ?? '').toString(),
    asOf: DateTime.parse((json['asOf'] ?? '2026-01-01').toString()),
    diagnostics: json['diagnostics'] != null
        ? DiagnosticsState.fromJson(json['diagnostics'] as Map<String, dynamic>)
        : const DiagnosticsState(),
    aerobic: json['aerobic'] != null
        ? AerobicState.fromJson(json['aerobic'] as Map<String, dynamic>)
        : const AerobicState(),
    threshold: json['threshold'] != null
        ? ThresholdState.fromJson(json['threshold'] as Map<String, dynamic>)
        : const ThresholdState(),
    highIntensity: json['highIntensity'] != null
        ? HighIntensityState.fromJson(
            json['highIntensity'] as Map<String, dynamic>,
          )
        : const HighIntensityState(),
    skiExposure: json['skiExposure'] != null
        ? SkiSpecificExposureState.fromJson(
            json['skiExposure'] as Map<String, dynamic>,
          )
        : const SkiSpecificExposureState(),
    doublePoling: json['doublePoling'] != null
        ? DoublePolingState.fromJson(
            json['doublePoling'] as Map<String, dynamic>,
          )
        : const DoublePolingState(),
    durability: json['durability'] != null
        ? DurabilityState.fromJson(json['durability'] as Map<String, dynamic>)
        : const DurabilityState(),
    trainingLoad: json['trainingLoad'] != null
        ? TrainingLoadState.fromJson(
            json['trainingLoad'] as Map<String, dynamic>,
          )
        : const TrainingLoadState(),
    stimulusHistory: json['stimulusHistory'] != null
        ? StimulusHistoryState.fromJson(
            json['stimulusHistory'] as Map<String, dynamic>,
          )
        : const StimulusHistoryState(),
    subjectiveReadiness: json['subjectiveReadiness'] != null
        ? SubjectiveReadinessState.fromJson(
            json['subjectiveReadiness'] as Map<String, dynamic>,
          )
        : const SubjectiveReadinessState(),
    performanceTrends: json['performanceTrends'] != null
        ? PerformanceTrendState.fromJson(
            json['performanceTrends'] as Map<String, dynamic>,
          )
        : const PerformanceTrendState(),
    dataCoverage: json['dataCoverage'] != null
        ? DataCoverageState.fromJson(
            json['dataCoverage'] as Map<String, dynamic>,
          )
        : const DataCoverageState(),
    eliteAnalysis: json['eliteAnalysis'] != null
        ? EliteAnalysisState.fromJson(
            json['eliteAnalysis'] as Map<String, dynamic>,
          )
        : const EliteAnalysisState(),
    goal: json['goal'] != null
        ? GoalContext.fromJson(json['goal'] as Map<String, dynamic>)
        : null,
  );
}

typedef SubjectiveReadinessEvidence = SubjectiveReadinessState;
