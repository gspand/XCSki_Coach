import 'package:xc_coach/lala/core/knowledge/analysis_defaults.dart';
import 'package:xc_coach/lala/core/diagnostics/diagnostic_planning.dart';
import 'package:xc_coach/lala/core/models/analysis_result.dart';
import 'package:xc_coach/lala/core/models/method_metadata.dart';
import 'package:xc_coach/lala/core/models/threshold_result.dart';
import 'package:xc_coach/lala/core/models/training_zone.dart';
import 'package:xc_coach/lala/core/training_zones/zone_definitions.dart';

/// Bestimmt die Schwellenanker fuer das Zonenmodell.
/// Die Schwellenbestimmung selbst bleibt unveraendert; hier wird nur
/// entschieden, welche vorhandene Schwelle als Anker verwendet wird.
class ZoneAnchorBuilder {
  const ZoneAnchorBuilder();

  PhysiologicalAnchorSet build({
    required AnalysisResult analysis,
    required String sportType,
    required String loadUnit,
    double? confirmedLt1,
    double? confirmedMlss,
    double? criticalPower,
    double? wPrime,
    double? maximalAerobicPower,
    double? peakLoad,
    int? peakHeartRate,
    double? Function(double load)? heartRateAtLoad,
    String? selectedLt1MethodId,
    String? selectedLt2MethodId,
  }) {
    const planner = DiagnosticPlanningService();
    final lt1Consensus = planner.buildConsensus(
      thresholdType: ThresholdType.lt1,
      results: analysis.thresholdResults,
    );
    final lt2Consensus = planner.buildConsensus(
      thresholdType: ThresholdType.lt2,
      results: analysis.thresholdResults,
    );

    // Die Trainingssteuerung muss dieselben aktiven Werte verwenden wie die
    // Traineransicht im Testergebnis. Der wissenschaftliche Konsens bleibt
    // als Vergleich sichtbar, darf aber keine abweichenden Zonen erzeugen.
    final displayedLt1 = displayThreshold(
      analysis.thresholdResults,
      ThresholdType.lt1,
      expertMethodId: selectedLt1MethodId,
    );
    final displayedLt2 = displayThreshold(
      analysis.thresholdResults,
      ThresholdType.lt2,
      expertMethodId: selectedLt2MethodId,
    );
    final lt1Results = displayedLt1 == null
        ? _contributing(analysis, lt1Consensus)
        : <ThresholdResult>[displayedLt1.result];
    final lt2Results = displayedLt2 == null
        ? _contributing(analysis, lt2Consensus)
        : <ThresholdResult>[displayedLt2.result];

    final lt1Load =
        confirmedLt1 ??
        displayedLt1?.result.thresholdLoad ??
        lt1Consensus.centralLoad;
    final lt1 = lt1Load == null
        ? null
        : ThresholdAnchor(
            load: lt1Load,
            heartRate:
                _averageHeartRate(lt1Results) ??
                heartRateAtLoad?.call(lt1Load)?.round(),
            lactate: _averageLactate(lt1Results),
          );

    final ThresholdSource source;
    final double? upperLoad;
    if (confirmedMlss != null) {
      source = ThresholdSource.confirmedMlss;
      upperLoad = confirmedMlss;
    } else if (displayedLt2?.result.thresholdLoad != null) {
      source = ThresholdSource.estimatedLtp2;
      upperLoad = displayedLt2!.result.thresholdLoad;
    } else if (lt2Consensus.status == DiagnosticStatus.estimated) {
      source = ThresholdSource.estimatedLtp2;
      upperLoad = lt2Consensus.centralLoad;
    } else {
      source = ThresholdSource.provisionalConsensus;
      upperLoad = lt2Consensus.centralLoad;
    }

    final upper = upperLoad == null
        ? null
        : ThresholdAnchor(
            load: upperLoad,
            heartRate:
                _averageHeartRate(lt2Results) ??
                heartRateAtLoad?.call(upperLoad)?.round(),
            lactate: _averageLactate(lt2Results),
          );

    return PhysiologicalAnchorSet(
      sportType: sportType,
      loadUnit: loadUnit,
      upperSource: source,
      lt1: lt1,
      upper: upper,
      criticalPower: criticalPower,
      wPrime: wPrime,
      maximalAerobicPower: maximalAerobicPower,
      maximalPower:
          peakLoad != null && upperLoad != null && peakLoad > upperLoad
          ? peakLoad
          : null,
      maximalHeartRate: peakHeartRate,
    );
  }

  List<ThresholdResult> _contributing(
    AnalysisResult analysis,
    ThresholdConsensus consensus,
  ) => analysis.thresholdResults
      .where(
        (result) => consensus.contributingMethodIds.contains(result.methodId),
      )
      .toList(growable: false);

  int? _averageHeartRate(List<ThresholdResult> results) {
    final values = results
        .map((result) => result.interpolatedHeartRate)
        .whereType<double>()
        .toList(growable: false);
    if (values.isEmpty) {
      return null;
    }
    return (values.reduce((sum, value) => sum + value) / values.length).round();
  }

  double? _averageLactate(List<ThresholdResult> results) {
    final values = results
        .map((result) => result.interpolatedLactate)
        .whereType<double>()
        .toList(growable: false);
    if (values.isEmpty) {
      return null;
    }
    return values.reduce((sum, value) => sum + value) / values.length;
  }
}

String formatZoneLoad(double? value, String unit) {
  if (value == null) {
    return '-';
  }
  return unit.toLowerCase() == 'w'
      ? '${value.round()} $unit'
      : '${value.toStringAsFixed(1)} $unit';
}

String formatPace(int? seconds) {
  if (seconds == null) {
    return '-';
  }
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')} min/km';
}

String zoneRangeText(TrainingZone zone, String unit) {
  final lower = zone.lowerLoadDisplay;
  final upper = zone.upperLoadDisplay;
  if (upper == null) {
    return 'ab ${formatZoneLoad(lower, unit)}';
  }
  if (lower == null || lower <= 0) {
    return 'bis ${formatZoneLoad(upper, unit)}';
  }
  return '${formatZoneLoad(lower, unit)} bis ${formatZoneLoad(upper, unit)}';
}

String zoneHeartRateText(TrainingZone zone) {
  final lower = zone.lowerHeartRateDisplay;
  final upper = zone.upperHeartRateDisplay;
  if (upper == null) {
    return lower == null ? '-' : 'ab $lower bpm';
  }
  if (lower == null || lower <= 0) {
    return 'bis $upper bpm';
  }
  return '$lower bis $upper bpm';
}

/// Pace steigt in der Intensitaet, sinkt aber im Zahlenwert. Die Darstellung
/// laeuft deshalb vom langsameren zum schnelleren Wert.
String zonePaceText(TrainingZone zone) {
  final slower = zone.lowerPaceSeconds;
  final faster = zone.upperPaceSeconds;
  if (faster == null) {
    return slower == null ? '-' : 'schneller als ${formatPace(slower)}';
  }
  if (slower == null) {
    return 'bis ${formatPace(faster)}';
  }
  return '${formatPace(slower)} bis ${formatPace(faster)}';
}
