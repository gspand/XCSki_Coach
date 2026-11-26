/// Reines Presenter-Modell für den ATHLET-Tab (Zustandsebene).
///
/// WICHTIGE ARCHITEKTUR-REGEL:
/// - Presentation entscheidet NICHT.
/// - Formatiert und gruppiert ausschließlich existierende Daten aus [XCAthleteState].
/// - Erfindet keine neuen Schwellen oder Recovery-Formeln.
/// - Fehlende historische Daten bleiben ehrlich unbekannt (keine künstlichen 28-Tage-Kurven).
library;

import '../domain/xc_modality.dart';
import '../intelligence/load/stimulus_models.dart';
import '../intelligence/xc_athlete_state/xc_athlete_state.dart';
import 'canonical_terminology.dart';

class AthleteHeroPresentation {
  const AthleteHeroPresentation({
    required this.athleteName,
    required this.goalTitle,
    required this.daysUntilGoal,
    required this.summarySentence,
  });

  final String athleteName;
  final String goalTitle;
  final int? daysUntilGoal;
  final String summarySentence;
}

class AthleteLoadAndRecoveryPresentation {
  const AthleteLoadAndRecoveryPresentation({
    required this.statusTitle,
    required this.statusDescription,
    required this.acuteLoadValue,
    required this.chronicLoadValue,
    required this.loadBalanceValue,
    required this.checkInStatus,
    required this.recentStimuli,
    required this.dataCoverageText,
    required this.hasUnknownDaysNotice,
  });

  final String statusTitle;
  final String statusDescription;
  final String acuteLoadValue;
  final String chronicLoadValue;
  final String loadBalanceValue;
  final String checkInStatus;
  final List<StimulusPresentationItem> recentStimuli;
  final String dataCoverageText;
  final bool hasUnknownDaysNotice;
}

class StimulusPresentationItem {
  const StimulusPresentationItem({
    required this.title,
    required this.lastSeenText,
    required this.isRecent,
  });

  final String title;
  final String lastSeenText;
  final bool isRecent;
}

class PerformancePresentation {
  const PerformancePresentation({
    required this.aerobicBaseText,
    required this.thresholdText,
    required this.highIntensityText,
    required this.durabilityText,
  });

  final String aerobicBaseText;
  final String thresholdText;
  final String highIntensityText;
  final String durabilityText;
}

class XcSpecificityPresentation {
  const XcSpecificityPresentation({
    required this.snowExposure7d,
    required this.snowExposure28d,
    required this.doublePolingPower,
    required this.techniqueSymmetry,
  });

  final String snowExposure7d;
  final String snowExposure28d;
  final String doublePolingPower;
  final String techniqueSymmetry;
}

class DiagnosticsAndCoveragePresentation {
  const DiagnosticsAndCoveragePresentation({
    required this.diagnosticsStatus,
    required this.confidenceLabel,
    required this.coverageSummary,
    required this.traceDetails,
  });

  final String diagnosticsStatus;
  final String confidenceLabel;
  final String coverageSummary;
  final Map<String, String> traceDetails;
}

class AthletePresentationState {
  const AthletePresentationState({
    required this.hero,
    required this.loadAndRecovery,
    required this.performance,
    required this.xcSpecificity,
    required this.diagnosticsAndCoverage,
  });

  final AthleteHeroPresentation hero;
  final AthleteLoadAndRecoveryPresentation loadAndRecovery;
  final PerformancePresentation performance;
  final XcSpecificityPresentation xcSpecificity;
  final DiagnosticsAndCoveragePresentation diagnosticsAndCoverage;

  factory AthletePresentationState.fromDomain({
    required XCAthleteState state,
    String athleteName = 'Athlet',
  }) {
    // 1. Hero
    final goal = state.goal;
    final int? daysToGoal = goal?.daysUntilGoal(asOf: state.asOf);
    final String goalTitle = goal?.name ?? 'Allgemeine Saisonvorbereitung';

    final trimp = state.trainingLoad.latestBanisterState;
    final cov = state.dataCoverage;
    final subj = state.subjectiveReadiness;

    final String summarySentence;
    if (cov.unknownDays28d > 5 || trimp == null) {
      summarySentence = 'Trainingshistorie teilweise lückenhaft – GIULIA schützt dich mit konservativen Empfehlungen.';
    } else if (subj.hasIllnessSymptoms || subj.hasPainSymptoms) {
      summarySentence = 'Körperliche Beschwerden erfordern heute gezielte Schonung und Regeneration.';
    } else if (trimp.loadBalance < -15.0) {
      summarySentence = 'Hohe akute Belastung vorhanden – regenerative Reize oder Ruhetage priorisieren.';
    } else if (trimp.loadBalance >= 5.0) {
      summarySentence = 'Gute Frische und solide Grundfitness für anspruchsvolle Einheiten vorhanden.';
    } else {
      summarySentence = 'Ausgewogenes Trainingsverhältnis – Belastung und Regeneration im stabilen Fluss.';
    }

    final hero = AthleteHeroPresentation(
      athleteName: athleteName,
      goalTitle: goalTitle,
      daysUntilGoal: daysToGoal,
      summarySentence: summarySentence,
    );

    // 2. Belastung & Erholung (strikte Präsentation bestehender Daten)
    final acuteStr = trimp != null ? trimp.acuteLoad.toStringAsFixed(1) : CanonicalTerminology.unknownValue;
    final chronicStr = trimp != null ? trimp.chronicLoad.toStringAsFixed(1) : CanonicalTerminology.unknownValue;
    final balanceStr = trimp != null
        ? '${trimp.loadBalance >= 0 ? "+" : ""}${trimp.loadBalance.toStringAsFixed(1)}'
        : CanonicalTerminology.unknownValue;

    final String statusTitle;
    final String statusDesc;
    if (cov.unknownDays28d > 5 || trimp == null) {
      statusTitle = 'Datenlage unklar';
      statusDesc = 'Aufgrund fehlender Daten der letzten Tage ist die Belastungseinschätzung eingeschränkt.';
    } else if (subj.hasIllnessSymptoms || subj.hasPainSymptoms) {
      statusTitle = 'Hohe Belastung / Erholung priorisieren';
      statusDesc = 'Körperliche Symptome oder Beschwerden erfordern heute gezielte Entlastung.';
    } else if (trimp.loadBalance < -20.0) {
      statusTitle = 'Hohe Belastung / Erholung priorisieren';
      statusDesc = 'Die akute Trainingslast übersteigt das gewohnte Niveau deutlich.';
    } else if (trimp.loadBalance < -10.0) {
      statusTitle = 'Erhöhte Belastung';
      statusDesc = 'Du befindest dich in einem fordernden Belastungsblock. Reize gezielt dosieren.';
    } else if (trimp.loadBalance >= 5.0) {
      statusTitle = 'Gut erholt';
      statusDesc = 'Ausreichende Anpassungsreserve und gute Frische für fordernde Trainingsreize vorhanden.';
    } else {
      statusTitle = 'Normale Trainingsbelastung';
      statusDesc = 'Ausgewogenes Verhältnis von akuter Beanspruchung und chronischer Belastungsverträglichkeit.';
    }

    final String checkInStr;
    if (!subj.hasData) {
      checkInStr = 'Heute noch kein Check-in erfasst (wird als unvollständig und nicht als erholt gewertet).';
    } else {
      final parts = <String>[];
      if (subj.perceivedRecovery != null) parts.add('Erholung ${subj.perceivedRecovery!.toStringAsFixed(1)}/10');
      if (subj.sleepQuality != null) parts.add('Schlaf ${subj.sleepQuality!.toStringAsFixed(1)}/10');
      if (subj.legSoreness != null) parts.add('Beine ${subj.legSoreness!.toStringAsFixed(1)}/10');
      if (subj.upperBodySoreness != null) parts.add('Oberkörper ${subj.upperBodySoreness!.toStringAsFixed(1)}/10');
      if (subj.hasIllnessSymptoms) parts.add('Symptome: ${subj.illnessSymptoms.join(", ")}');
      if (subj.hasPainSymptoms) parts.add('Schmerzen: ${subj.painSymptoms.join(", ")}');
      checkInStr = parts.join(' · ');
    }

    final stimuli = state.stimulusHistory;
    final recentStimuliItems = <StimulusPresentationItem>[];
    void addStimulus(String title, StimulusType type) {
      final entry = stimuli.entries[type];
      if (entry == null || entry.lastObservedAt == null) {
        recentStimuliItems.add(StimulusPresentationItem(
          title: title,
          lastSeenText: 'Bisher kein Reiz dokumentiert',
          isRecent: false,
        ));
      } else {
        final daysAgo = state.asOf.difference(entry.lastObservedAt!).inDays;
        recentStimuliItems.add(StimulusPresentationItem(
          title: title,
          lastSeenText: daysAgo == 0 ? 'Heute' : 'vor $daysAgo Tagen',
          isRecent: daysAgo <= 4,
        ));
      }
    }
    addStimulus('Hochintensiver Reiz (VO2max / HIT)', StimulusType.vo2max);
    addStimulus('Schwellenreiz (LTP2 / EB)', StimulusType.threshold);
    addStimulus('Langer Ausdauerreiz (Grundlage / Umfang)', StimulusType.aerobicBase);

    final covText = cov.unknownDays28d > 0
        ? '${cov.unknownDays28d} Tage ohne Synchronisation in den letzten 28 Tagen.'
        : 'Lückenlose 28-Tage-Historie (${cov.observedTrainingDays28d} Trainingstage, ${cov.confirmedRestDays28d} bestätigte Ruhetage).';

    final loadAndRecovery = AthleteLoadAndRecoveryPresentation(
      statusTitle: statusTitle,
      statusDescription: statusDesc,
      acuteLoadValue: acuteStr,
      chronicLoadValue: chronicStr,
      loadBalanceValue: balanceStr,
      checkInStatus: checkInStr,
      recentStimuli: recentStimuliItems,
      dataCoverageText: covText,
      hasUnknownDaysNotice: cov.unknownDays28d > 0,
    );

    // 3. Leistungsfähigkeit (Evidence-basiert)
    final diag = state.diagnostics;
    final thresh = state.threshold;
    final vo2 = state.highIntensity;
    final dur = state.durability;

    final thresholdDesc = thresh.hasThresholdData
        ? 'LTP2: ${thresh.observedThresholdPowerWatt?.toStringAsFixed(0) ?? thresh.observedThresholdHrBpm?.toStringAsFixed(0) ?? "Dokumentiert"} (Konfidenz ${(thresh.confidence * 100).toStringAsFixed(0)}%)'
        : CanonicalTerminology.unknownDiagnostic;

    final vo2Desc = vo2.diagnosticVo2maxEvidence != null
        ? 'VO2max: ${vo2.diagnosticVo2maxEvidence!.value.toStringAsFixed(1)} ml/kg/min (Labordiagnostik)'
        : (vo2.accumulatedZ5DurationSeconds28d > 0
            ? '${(vo2.accumulatedZ5Minutes28d).toStringAsFixed(0)} Min. in Zone 5 (28d)'
            : 'Keine aktuellen HIT-Messungen');

    final baseDesc = state.aerobic.lowIntensityDurationSeconds28d > 0
        ? '${state.aerobic.lowIntensityHours28d.toStringAsFixed(1)} Std. Grundlagenausdauer (28d)'
        : 'Bisher keine erfassten Grundlageneinheiten';

    final durDesc = dur.hasMeasuredObservations
        ? '${dur.longSessionCount28d} lange Einheiten · ${dur.longSessionExposureHours28d.toStringAsFixed(1)} Std.'
        : 'Durability wird über Einheiten > 90 Min. ermittelt';

    final performance = PerformancePresentation(
      aerobicBaseText: baseDesc,
      thresholdText: thresholdDesc,
      highIntensityText: vo2Desc,
      durabilityText: durDesc,
    );

    // 4. Langlauf-Spezifität
    final ski = state.skiExposure;
    final dp = state.doublePoling;

    final skatingExp = ski.exposureOf(XcModality.skiSkating);
    final classicExp = ski.exposureOf(XcModality.skiClassic);

    final xcSpecificity = XcSpecificityPresentation(
      snowExposure7d: '${((skatingExp.durationHours7d + classicExp.durationHours7d)).toStringAsFixed(1)} Std. Schnee (7d)',
      snowExposure28d: '${((skatingExp.durationHours28d + classicExp.durationHours28d)).toStringAsFixed(1)} Std. Schnee (28d)',
      doublePolingPower: dp.recentSessionAveragePowerWatt != null
          ? '${dp.recentSessionAveragePowerWatt!.toStringAsFixed(0)} W Ø Ercolina Doppelstock'
          : 'Noch kein Ercolina-Profilwert',
      techniqueSymmetry: dp.leftRightBalancePercent != null
          ? '${dp.leftRightBalancePercent!.toStringAsFixed(0)} % Symmetrie'
          : 'Symmetrie unkalibriert',
    );

    // 5. Diagnostik & Daten
    final diagStatus = diag.references.isNotEmpty
        ? 'Diagnostik vorhanden (Referenzen für ${diag.references.keys.map((k) => k.label).join(", ")})'
        : CanonicalTerminology.unknownDiagnostic;

    final confLabel = cov.overallCoverageRatio >= 0.8
        ? CanonicalTerminology.confidenceHigh
        : (cov.overallCoverageRatio >= 0.5
            ? CanonicalTerminology.confidenceModerate
            : CanonicalTerminology.confidenceLow);

    final diagnosticsAndCoverage = DiagnosticsAndCoveragePresentation(
      diagnosticsStatus: diagStatus,
      confidenceLabel: confLabel,
      coverageSummary: '${cov.observedTrainingDays28d} Trainingstage · ${cov.confirmedRestDays28d} Ruhetage · ${cov.unknownDays28d} unbekannt',
      traceDetails: {
        'Skating LTP2': state.traceEvidenceFor('skating_threshold'),
        'Doppelstock': state.traceEvidenceFor('double_poling'),
      },
    );

    return AthletePresentationState(
      hero: hero,
      loadAndRecovery: loadAndRecovery,
      performance: performance,
      xcSpecificity: xcSpecificity,
      diagnosticsAndCoverage: diagnosticsAndCoverage,
    );
  }
}
