/// Reines Presenter-Modell für ANALYSE (Ergebnisebene).
///
/// WICHTIGE ARCHITEKTUR-REGEL:
/// - Presentation entscheidet NICHT.
/// - Bereitet eine [NormalizedSession] für die kanonische 3-Block-Darstellung auf:
///   1. Das Training (Modality, Duration, Work kJ, Power W, Tritt/Zugfrequenz, Distanz)
///   2. Deine Reaktion (Heart Rate, HR Zones, RPE, Laktat)
///   3. Was GIULIA gelernt hat (Erkannter Reiz, Erholungsbedarf, Auswirkung auf Zustand)
library;

import '../domain/normalized_session.dart';
import '../domain/xc_modality.dart';
import 'canonical_terminology.dart';

class SessionBlockTraining {
  const SessionBlockTraining({
    required this.title,
    required this.sourceLabel,
    required this.modalityLabel,
    required this.modality,
    required this.durationMinutes,
    required this.workKiloJoule,
    required this.averagePowerWatt,
    this.averageStrokePowerWatt,
    required this.strokeOrCadenceRate,
    required this.distanceKm,
    required this.symmetryText,
  });

  final String title;
  final String sourceLabel;
  final String modalityLabel;
  final XcModality modality;
  final int durationMinutes;
  final String? workKiloJoule;
  final String? averagePowerWatt;
  final String? averageStrokePowerWatt;
  final String? strokeOrCadenceRate;
  final String? distanceKm;
  final String? symmetryText;
}

class SessionBlockReaction {
  const SessionBlockReaction({
    required this.averageHeartRateBpm,
    required this.peakHeartRateBpm,
    required this.rpeText,
    required this.lactateText,
    required this.hrZonesBreakdown,
  });

  final String? averageHeartRateBpm;
  final String? peakHeartRateBpm;
  final String? rpeText;
  final String? lactateText;
  final List<String> hrZonesBreakdown;
}

class SessionBlockLearnings {
  const SessionBlockLearnings({
    required this.detectedStimulusText,
    required this.loadImpactText,
    required this.dataConfidenceText,
    required this.stateUpdateSummary,
  });

  final String detectedStimulusText;
  final String loadImpactText;
  final String dataConfidenceText;
  final String stateUpdateSummary;
}

class SessionPresentationModel {
  const SessionPresentationModel({
    required this.sessionId,
    required this.dateFormatted,
    required this.training,
    required this.reaction,
    required this.learnings,
  });

  final String sessionId;
  final String dateFormatted;
  final SessionBlockTraining training;
  final SessionBlockReaction reaction;
  final SessionBlockLearnings learnings;

  factory SessionPresentationModel.fromDomain({
    required NormalizedSession session,
  }) {
    final localDate = DateTime.fromMicrosecondsSinceEpoch(
      session.startedAtUtcUs,
      isUtc: true,
    ).toLocal();

    String two(int v) => v.toString().padLeft(2, '0');
    final dateStr = '${two(localDate.day)}.${two(localDate.month)}.${localDate.year} · ${two(localDate.hour)}:${two(localDate.minute)}';

    // 1. Das Training
    final ext = session.externalMetrics;
    final workKj = ext.workJoule != null
        ? '${(ext.workJoule! / 1000).toStringAsFixed(0)} kJ'
        : null;
    final pwr = ext.sessionAveragePowerWatt != null
        ? '${ext.sessionAveragePowerWatt!.toStringAsFixed(0)} W'
        : null;
    final strokePwr = ext.workPhaseAveragePowerWatt != null
        ? '${ext.workPhaseAveragePowerWatt!.toStringAsFixed(0)} W'
        : null;
    final cadence = ext.strokeOrCadenceRate != null
        ? '${ext.strokeOrCadenceRate!.toStringAsFixed(0)} ${CanonicalTerminology.unitStrokesPerMin}'
        : null;
    final dist = session.distanceKm != null
        ? '${session.distanceKm!.toStringAsFixed(1)} km'
        : null;

    final String? symText;
    if (ext.leftRightSymmetryPercent != null) {
      symText = '${ext.leftRightSymmetryPercent!.toStringAsFixed(0)}% L/R Symmetrie';
    } else if (ext.classicLeftWorkPercent != null) {
      symText = '${ext.classicLeftWorkPercent!.toStringAsFixed(0)}% Linksanteil';
    } else {
      symText = null;
    }

    final blockTraining = SessionBlockTraining(
      title: session.title,
      sourceLabel: session.source.label,
      modalityLabel: session.modality.label,
      modality: session.modality,
      durationMinutes: session.durationSeconds ~/ 60,
      workKiloJoule: workKj,
      averagePowerWatt: pwr,
      averageStrokePowerWatt: strokePwr,
      strokeOrCadenceRate: cadence,
      distanceKm: dist,
      symmetryText: symText,
    );

    // 2. Deine Reaktion
    final intl = session.internalMetrics;
    final avgHr = intl.averageHeartRateBpm != null
        ? '${intl.averageHeartRateBpm!.toStringAsFixed(0)} bpm'
        : null;
    final peakHr = intl.peakHeartRateBpm != null
        ? '${intl.peakHeartRateBpm} bpm'
        : null;
    final rpe = intl.rpe != null
        ? 'RPE ${intl.rpe!.toStringAsFixed(1)} / 10'
        : null;
    final lac = intl.peakLactateMmolPerLitre != null
        ? '${intl.peakLactateMmolPerLitre!.toStringAsFixed(1)} mmol/l'
        : null;

    final zones = <String>[];
    for (final e in intl.timeInHrZonesSeconds.entries) {
      final mins = e.value ~/ 60;
      if (mins > 0) {
        zones.add('${e.key}: ${mins}m');
      }
    }

    final blockReaction = SessionBlockReaction(
      averageHeartRateBpm: avgHr,
      peakHeartRateBpm: peakHr,
      rpeText: rpe,
      lactateText: lac,
      hrZonesBreakdown: zones,
    );

    // 3. Was GIULIA gelernt hat
    final qual = session.dataQuality;
    final confStr = qual.confidence >= 0.8
        ? CanonicalTerminology.confidenceHigh
        : (qual.confidence >= 0.5
            ? CanonicalTerminology.confidenceModerate
            : CanonicalTerminology.confidenceLow);

    final String stimulusDesc;
    if (session.isIndoor && session.modality == XcModality.ercolinaDoublePoling) {
      stimulusDesc = 'Ercolina Oberkörper-Reiz erfasst';
    } else {
      stimulusDesc = 'Ausdauerbelastung dokumentiert';
    }

    final blockLearnings = SessionBlockLearnings(
      detectedStimulusText: stimulusDesc,
      loadImpactText: 'Einfluss auf akute & chronische Belastung verbucht',
      dataConfidenceText: confStr,
      stateUpdateSummary: 'Fließt in die nächste tägliche Coaching-Entscheidung ein.',
    );

    return SessionPresentationModel(
      sessionId: session.id,
      dateFormatted: dateStr,
      training: blockTraining,
      reaction: blockReaction,
      learnings: blockLearnings,
    );
  }
}
