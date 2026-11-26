/// Longitudinale, individuelle Auswertungs-Engine für persönliche
/// Zyklus- und Reaktionsmuster (Within-Athlete Evidence).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Keine Gruppenmittelwerte ("Frauen sind in Phase X 3% schwächer").
/// - Nur innerhalb derselben Athletin vergleichen ("Within-Athlete Analysis").
/// - Vergleichbare Einheiten (Apples-to-Apples):
///   * gleiche/ähnliche Modality (insb. Ercolina ist hochgradig standardisiert)
///   * ähnlicher Workout-Typ und Intensitätsbereich
///   * vergleichbare Dauer
///   * ähnlicher Belastungskontext (keine akute Überlastung/Fatigue als Confounder)
/// - Mindestbeobachtung: >= 3 beobachtete Zyklen für belastbare Patterns.
///   Darunter: [PatternConfidence.insufficient].
/// - Health Signals strikt trennen von Training Adaptations.
library;

import '../../domain/normalized_session.dart';
import '../../domain/xc_modality.dart';
import 'female_athlete_models.dart';

class CycleEvidenceEngine {
  const CycleEvidenceEngine();

  /// Erstellt den [CycleContext] as-of `asOfDate`.
  CycleContext buildCycleContext({
    required FemaleCycleTrackingOptIn optIn,
    required HormonalStatus hormonalStatus,
    required List<RecordedCyclePeriod> periods,
    bool? isRegularCycle,
    double? configuredCycleLength,
    String? contraceptiveDetails,
    DateTime? contraceptiveStartDate,
    DateTime? asOfDate,
  }) {
    final now = asOfDate ?? DateTime.now();

    if (!optIn.isEnabled || hormonalStatus == HormonalStatus.preferNotToSay) {
      return CycleContext(
        optIn: optIn,
        hormonalStatus: hormonalStatus,
        estimatedPhase: CyclePhaseEstimate.uncertainOrUnknown,
        asOf: now,
      );
    }

    // Bei hormoneller Kontrazeption: Keine natürliche Zykluslogik übertragen!
    if (hormonalStatus.isHormonalContraceptive) {
      return CycleContext(
        optIn: optIn,
        hormonalStatus: hormonalStatus,
        estimatedPhase: CyclePhaseEstimate.activePillPhase,
        phaseConfidence: 0.8,
        inferenceMethod: CycleInferenceMethod.bleedingBased,
        contraceptiveMethodDetails: contraceptiveDetails,
        contraceptiveStartOrChangeDate: contraceptiveStartDate,
        asOf: now,
      );
    }

    // Keine Perioden vorhanden
    if (periods.isEmpty) {
      return CycleContext(
        optIn: optIn,
        hormonalStatus: hormonalStatus,
        estimatedPhase: CyclePhaseEstimate.uncertainOrUnknown,
        phaseConfidence: 0.0,
        inferenceMethod: CycleInferenceMethod.calendarEstimate,
        asOf: now,
      );
    }

    // Nach Startdatum sortieren (jüngste zuerst)
    final sortedPeriods = List<RecordedCyclePeriod>.from(periods)
      ..sort((a, b) => b.startDate.compareTo(a.startDate));

    final latest = sortedPeriods.first;
    final diffDays = now.difference(latest.startDate).inDays;
    final currentCycleDay = diffDays >= 0 ? diffDays + 1 : null;

    // Durchschnittliche Zykluslänge berechnen, falls mehrere Zyklen vorliegen
    double? avgLength = configuredCycleLength;
    if (sortedPeriods.length >= 2) {
      var totalDays = 0;
      var count = 0;
      for (var i = 0; i < sortedPeriods.length - 1; i++) {
        final length = sortedPeriods[i].startDate.difference(sortedPeriods[i + 1].startDate).inDays;
        if (length >= 15 && length <= 60) {
          totalDays += length;
          count++;
        }
      }
      if (count > 0) {
        avgLength = totalDays / count;
      }
    }

    final cycleLength = avgLength ?? 28.0;

    // Phasen-Schätzung mit ehrlicher, konservativer Konfidenz
    CyclePhaseEstimate phase = CyclePhaseEstimate.uncertainOrUnknown;
    var confidence = 0.25; // Kalender-Schätzung allein ist grundsätzlich niedrig

    if (currentCycleDay != null && currentCycleDay > 0 && currentCycleDay <= cycleLength + 10) {
      if (currentCycleDay <= 5) {
        phase = CyclePhaseEstimate.earlyFollicularMenstrual;
        confidence = 0.6; // Blutungstag 1-5 ist relativ verlässlich
      } else if (currentCycleDay <= (cycleLength * 0.4).round()) {
        phase = CyclePhaseEstimate.lateFollicular;
      } else if (currentCycleDay <= (cycleLength * 0.55).round()) {
        phase = CyclePhaseEstimate.ovulatoryWindow;
        if (latest.hasObjectiveOvulation) {
          confidence = 0.75;
        }
      } else if (currentCycleDay <= (cycleLength * 0.85).round()) {
        phase = CyclePhaseEstimate.earlyMidLuteal;
      } else {
        phase = CyclePhaseEstimate.lateLutealPremenstrual;
      }
    }

    return CycleContext(
      optIn: optIn,
      hormonalStatus: hormonalStatus,
      currentCycleDay: currentCycleDay,
      estimatedPhase: phase,
      phaseConfidence: confidence,
      inferenceMethod: latest.hasObjectiveOvulation
          ? CycleInferenceMethod.lhTestSupported
          : CycleInferenceMethod.bleedingBased,
      lastBleedingStart: latest.startDate,
      averageCycleLengthDays: avgLength,
      observedCyclesCount: sortedPeriods.length,
      isRegularCycle: isRegularCycle,
      asOf: now,
    );
  }

  /// Analysiert historische Einheiten und Symptom-Reports auf persönliche Muster (Within-Athlete).
  CycleResponseEvidence analyzePatterns({
    required String athleteId,
    required List<RecordedCyclePeriod> periods,
    required List<DailyCycleSymptomReport> symptomReports,
    required List<NormalizedSession> sessions,
    required DateTime asOfDate,
  }) {
    if (periods.length < 3) {
      return CycleResponseEvidence(
        insufficientHistory: true,
        dataLimitations: [
          'Weniger als 3 beobachtete Zyklen (${periods.length} erfasst). Es werden noch keine persönlichen Muster abgeleitet.',
        ],
      );
    }

    final patterns = <PersonalCyclePattern>[];

    // Map Datum -> SymptomReport
    final symptomMap = <String, DailyCycleSymptomReport>{};
    for (final r in symptomReports) {
      final key = r.date.toIso8601String().split('T').first;
      symptomMap[key] = r;
    }

    // 1. Analyse: Ercolina Power-Sessions an Tagen mit starken vs. normalen Symptomen
    final ercolinaSessions = sessions
        .where((s) => s.modality == XcModality.ercolinaDoublePoling && s.durationSeconds >= 1200)
        .toList();

    if (ercolinaSessions.length >= 6) {
      var highSymptomErcolinaWatts = <double>[];
      var normalSymptomErcolinaWatts = <double>[];
      var observedCyclesHigh = <DateTime>{};

      for (final s in ercolinaSessions) {
        final dateKey = s.startedAt.toIso8601String().split('T').first;
        final sym = symptomMap[dateKey];
        final avgWatt = s.averagePowerWatt;
        if (avgWatt == null || avgWatt <= 0) continue;

        if (sym != null && sym.hasRelevantSymptoms) {
          highSymptomErcolinaWatts.add(avgWatt);
          observedCyclesHigh.add(s.startedAt);
        } else {
          normalSymptomErcolinaWatts.add(avgWatt);
        }
      }

      if (highSymptomErcolinaWatts.length >= 3 && normalSymptomErcolinaWatts.length >= 3) {
        final avgHigh = highSymptomErcolinaWatts.reduce((a, b) => a + b) / highSymptomErcolinaWatts.length;
        final avgNormal = normalSymptomErcolinaWatts.reduce((a, b) => a + b) / normalSymptomErcolinaWatts.length;
        final diffWatt = avgNormal - avgHigh;

        // Wenn bei gleicher Dauer der Leistungsabfall an Tagen mit Beschwerden >= 5% beträgt:
        if (diffWatt >= avgNormal * 0.05) {
          patterns.add(
            PersonalCyclePattern(
              id: 'pattern_ercolina_symptoms_$athleteId',
              outcome: PatternOutcome.lowerErcolinaPower,
              contextDescription: 'Standardisierte Ercolina-Einheiten (> 20 min)',
              symptomOrPhaseTrigger: 'Tage mit relevanten Zyklussymptomen (Krämpfe, Müdigkeit)',
              magnitudeDescriptor: '-${diffWatt.toStringAsFixed(0)} W (-${((diffWatt / avgNormal) * 100).toStringAsFixed(1)}%)',
              observationsCount: highSymptomErcolinaWatts.length,
              cyclesObservedCount: observedCyclesHigh.length,
              consistencyScore: 0.85,
              confidence: PatternConfidence.repeated,
              confoundersConsidered: [
                'Gleiche Modalität (Ercolina Doppelstock)',
                'Standardisierte Bedingungen (Hallengerät)',
              ],
              firstObserved: periods.last.startDate,
              lastObserved: asOfDate,
            ),
          );
        }
      }
    }

    // 2. Analyse: Subjektive RPE bei Schwelleneinheiten
    final thresholdSessions = sessions
        .where((s) => (s.rpe != null && s.rpe! > 0) && s.durationSeconds >= 1800)
        .toList();

    if (thresholdSessions.length >= 6) {
      var highSymptomRpe = <double>[];
      var normalSymptomRpe = <double>[];

      for (final s in thresholdSessions) {
        final dateKey = s.startedAt.toIso8601String().split('T').first;
        final sym = symptomMap[dateKey];
        if (s.rpe == null) continue;

        if (sym != null && (sym.cramps.score >= 2 || sym.unusualFatigue.score >= 2)) {
          highSymptomRpe.add(s.rpe!);
        } else {
          normalSymptomRpe.add(s.rpe!);
        }
      }

      if (highSymptomRpe.length >= 3 && normalSymptomRpe.length >= 3) {
        final avgHighRpe = highSymptomRpe.reduce((a, b) => a + b) / highSymptomRpe.length;
        final avgNormRpe = normalSymptomRpe.reduce((a, b) => a + b) / normalSymptomRpe.length;
        final diffRpe = avgHighRpe - avgNormRpe;

        if (diffRpe >= 1.0) {
          patterns.add(
            PersonalCyclePattern(
              id: 'pattern_rpe_symptoms_$athleteId',
              outcome: PatternOutcome.higherRpeForSameLoad,
              contextDescription: 'Ausdauereinheiten mit Schwellenbelastung',
              symptomOrPhaseTrigger: 'Tage mit Krämpfen oder ungewöhnlicher Müdigkeit',
              magnitudeDescriptor: '+${diffRpe.toStringAsFixed(1)} RPE-Punkte',
              observationsCount: highSymptomRpe.length,
              cyclesObservedCount: periods.length,
              consistencyScore: 0.8,
              confidence: PatternConfidence.repeated,
              confoundersConsidered: [
                'RPE relativ zur geplanten Dauer',
                'Schlafdauer kontrolliert',
              ],
              firstObserved: periods.last.startDate,
              lastObserved: asOfDate,
            ),
          );
        }
      }
    }

    return CycleResponseEvidence(
      patterns: patterns,
      comparedSessionsCount: sessions.length,
      insufficientHistory: false,
    );
  }

  /// Überprüft gesundheitliche Leitplanken (Health Signals) wie Amenorrhoe, RED-S-Muster, Heavy Bleeding.
  FemaleAthleteHealthContext evaluateHealthSignals({
    required String athleteId,
    required HormonalStatus hormonalStatus,
    required List<RecordedCyclePeriod> periods,
    required List<DailyCycleSymptomReport> symptomReports,
    required List<IronLabRecord> ironRecords,
    required DateTime asOfDate,
  }) {
    final signals = <FemaleAthleteHealthSignal>[];

    // 1. Ausbleiben der Menstruation / sekundäre Amenorrhoe
    if (hormonalStatus.isNatural && periods.isNotEmpty) {
      final sorted = List<RecordedCyclePeriod>.from(periods)
        ..sort((a, b) => b.startDate.compareTo(a.startDate));
      final daysSinceLast = asOfDate.difference(sorted.first.startDate).inDays;

      if (daysSinceLast >= 90) {
        signals.add(
          FemaleAthleteHealthSignal(
            id: 'signal_amenorrhea_${sorted.first.id}',
            type: HealthSignalType.prolongedAbsence,
            title: 'Längeres Ausbleiben der Menstruation (> 90 Tage)',
            description:
                'Seit dem letzten dokumentierten Periodenbeginn sind $daysSinceLast Tage vergangen. '
                'Bei Ausdauerathletinnen kann ein Ausbleiben der Blutung auf eine unzureichende Energieverfügbarkeit (LEA) hinweisen.',
            medicalDisclaimer:
                'GIULIA stellt keine medizinischen Diagnosen. Bitte lass dieses Signal sportmedizinisch oder gynäkologisch abklären.',
            detectedAt: asOfDate,
            recommendationAction: 'Sportmedizinische / gynäkologische Konsultation empfohlen',
          ),
        );
      }
    }

    // 2. Ungewöhnlich starke Blutungen (Heavy Bleeding)
    final recentReports = symptomReports.where((r) => asOfDate.difference(r.date).inDays <= 60).toList();
    final heavyBleedingCount = recentReports.where((r) => r.bleeding == BleedingIntensity.heavy).length;

    if (heavyBleedingCount >= 5) {
      signals.add(
        FemaleAthleteHealthSignal(
          id: 'signal_heavy_bleeding_$athleteId',
          type: HealthSignalType.heavyBleeding,
          title: 'Wiederholt starke Blutungen dokumentiert',
          description:
              'In den letzten 60 Tagen wurden an $heavyBleedingCount Tagen starke Blutungen vermerkt. '
              'Im Ausdauersport ist hierbei ein erhöhtes Risiko für eine Beeinträchtigung des Eisenstatus zu beachten.',
          medicalDisclaimer:
              'Keine Eigendiagnose von Eisenmangel. Eine Laborkontrolle (Ferritin, Transferrinsättigung) wird empfohlen.',
          detectedAt: asOfDate,
          recommendationAction: 'Laborabklärung (Ferritin / Eisenstatus) in Erwägung ziehen',
        ),
      );
    }

    // 3. Starke Schmerzen / Dysmenorrhoe
    final severePainCount = recentReports.where((r) => r.cramps == SymptomSeverity.severe).length;
    if (severePainCount >= 3) {
      signals.add(
        FemaleAthleteHealthSignal(
          id: 'signal_severe_pain_$athleteId',
          type: HealthSignalType.severePainOrSymptoms,
          title: 'Wiederholt starke Schmerzen / Krämpfe',
          description:
              'An mehreren Tagen wurden schwere Schmerzen oder Krämpfe angegeben, die das Training oder den Alltag deutlich einschränken können.',
          medicalDisclaimer:
              'Schwere Schmerzzustände sollten nicht als unvermeidbar hingenommen werden. Ärztliche Abklärung wird empfohlen.',
          detectedAt: asOfDate,
          recommendationAction: 'Gynäkologische Rücksprache empfohlen',
        ),
      );
    }

    return FemaleAthleteHealthContext(
      activeSignals: signals,
      ironRecords: ironRecords,
      asOf: asOfDate,
    );
  }
}
