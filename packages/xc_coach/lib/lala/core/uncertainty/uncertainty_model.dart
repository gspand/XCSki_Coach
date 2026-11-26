import 'package:xc_coach/lala/core/models/threshold_result.dart';
import 'package:xc_coach/lala/core/models/uncertainty_result.dart';
import 'package:xc_coach/lala/core/uncertainty/uncertainty_sources.dart';

class UncertaintyModel {
  const UncertaintyModel();

  UncertaintyResult build({
    required ThresholdResult result,
    required bool hasMissingHeartRate,
  }) {
    final sources = <String>[
      UncertaintySource.stageSpacing.name,
      UncertaintySource.interpolation.name,
      UncertaintySource.lactateDeviceMeasurement.name,
      UncertaintySource.protocolQuality.name,
    ];

    if (hasMissingHeartRate) {
      sources.add(UncertaintySource.missingHeartRate.name);
    }

    if (result.sensitivity != null) {
      sources.add(UncertaintySource.leaveOneOutSensitivity.name);
    }

    final stabilityBand =
        result.sensitivity?.minimumThreshold != null &&
            result.sensitivity?.maximumThreshold != null
        ? '${result.sensitivity!.minimumThreshold!.toStringAsFixed(1)}-${result.sensitivity!.maximumThreshold!.toStringAsFixed(1)}'
        : 'nicht quantifizierbar';

    return UncertaintyResult(
      stabilityBand: stabilityBand,
      modelSpreadDescription:
          'Bandbreite basiert auf Stufenabstand, Interpolation und Sensitivitaetsanalyse; kein 95%-Konfidenzintervall.',
      sensitivityRange: result.sensitivity == null
          ? 'keine Sensitivitaetsanalyse'
          : 'medianer Shift ${result.sensitivity!.medianAbsoluteShift?.toStringAsFixed(1) ?? '-'}; maximale Einpunktwirkung ${result.sensitivity!.maxSinglePointImpact?.toStringAsFixed(1) ?? '-'}',
      sources: sources,
    );
  }
}
