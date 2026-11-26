import 'package:xc_coach/lala/core/models/threshold_result.dart';
import 'package:xc_coach/lala/core/models/method_metadata.dart';

/// Die zwei Leitverfahren der normalen Traineransicht.
/// Weitere Verfahren werden weiterhin berechnet und bleiben in den
/// wissenschaftlichen Details verfuegbar.
const standardLt1MethodId = 'HOFMANN_GRAZ_RECON_V1_LTP1';
const standardLt2MethodId = 'MODDMAX_BISHOP_ALLDATA_V1';

class DisplayThresholdSelection {
  const DisplayThresholdSelection({
    required this.result,
    required this.methodLabel,
    required this.isStandard,
    required this.isExpertOverride,
  });

  final ThresholdResult result;
  final String methodLabel;
  final bool isStandard;
  final bool isExpertOverride;

  String get statusLabel => isStandard
      ? 'Standard'
      : isExpertOverride
      ? 'Expertenauswahl'
      : 'Vorlaeufiger Ersatzwert';
}

String standardMethodId(ThresholdType type) => switch (type) {
  ThresholdType.lt1 => standardLt1MethodId,
  ThresholdType.lt2 => standardLt2MethodId,
};

String standardMethodLabel(ThresholdType type) => switch (type) {
  ThresholdType.lt1 => 'Hofmann/Graz Turnpoint',
  ThresholdType.lt2 => 'Modified DMAX nach Bishop',
};

ThresholdResult? standardThreshold(
  List<ThresholdResult> results,
  ThresholdType type,
) {
  final preferredId = standardMethodId(type);
  for (final result in results) {
    if (result.thresholdType == type &&
        result.methodId == preferredId &&
        result.thresholdLoad != null) {
      return result;
    }
  }
  return null;
}

/// Liefert fuer die Traineransicht immer den methodisch besten vorhandenen
/// Wert. Der Standard wird nie stillschweigend ersetzt: ein Fallback ist als
/// vorlaeufig gekennzeichnet und kann deshalb gezielt nachgetestet werden.
DisplayThresholdSelection? displayThreshold(
  List<ThresholdResult> results,
  ThresholdType type, {
  String? expertMethodId,
}) {
  if (expertMethodId != null) {
    final selected = results
        .where((result) => result.thresholdType == type)
        .where((result) => result.methodId == expertMethodId)
        .where((result) => result.thresholdLoad != null)
        .where((result) => _isProductive(result))
        .firstOrNull;
    if (selected != null) {
      return DisplayThresholdSelection(
        result: selected,
        methodLabel: _fallbackMethodLabel(selected.methodId),
        isStandard: selected.methodId == standardMethodId(type),
        isExpertOverride: selected.methodId != standardMethodId(type),
      );
    }
  }
  final standard = standardThreshold(results, type);
  if (standard != null) {
    return DisplayThresholdSelection(
      result: standard,
      methodLabel: standardMethodLabel(type),
      isStandard: true,
      isExpertOverride: false,
    );
  }

  final productive = results
      .where((result) => result.thresholdType == type)
      .where((result) => result.thresholdLoad != null)
      .where(_isProductive)
      .toList(growable: false);
  if (productive.isEmpty) return null;

  final priorities = type == ThresholdType.lt1
      ? const <String>[
          'LOGLOG_WORKLOAD_TWO_LINE_RSS_V1',
          'lt_lower.baseline_plus_1_0.v1',
          'lt_lower.baseline_plus_0_5.v1',
          'fixed_blood_lactate.generic.v1.2_0mmol',
        ]
      : const <String>[
          'DMAX_CUBIC_WORKLOAD_V1',
          'DICKHUTH_LEMIN_DISCRETE_LINEAR_V1',
          'fixed_blood_lactate.generic.v1.4_0mmol',
          'fixed_blood_lactate.generic.v1.3_0mmol',
        ];
  for (final methodId in priorities) {
    final match = productive
        .where((result) => result.methodId == methodId)
        .firstOrNull;
    if (match != null) {
      return DisplayThresholdSelection(
        result: match,
        methodLabel: _fallbackMethodLabel(methodId),
        isStandard: false,
        isExpertOverride: false,
      );
    }
  }
  final fallback = productive.first;
  return DisplayThresholdSelection(
    result: fallback,
    methodLabel: _fallbackMethodLabel(fallback.methodId),
    isStandard: false,
    isExpertOverride: false,
  );
}

bool _isProductive(ThresholdResult result) =>
    result.implementationStatus == MethodImplementationStatus.implemented ||
    result.implementationStatus ==
        MethodImplementationStatus.internallyVerified ||
    result.implementationStatus ==
        MethodImplementationStatus.externallyValidated;

String _fallbackMethodLabel(String id) {
  if (id == 'LOGLOG_WORKLOAD_TWO_LINE_RSS_V1') return 'Log-Log';
  if (id == 'DMAX_CUBIC_WORKLOAD_V1') return 'Dmax';
  if (id == 'DICKHUTH_LEMIN_DISCRETE_LINEAR_V1') return 'Dickhuth';
  if (id.contains('baseline_plus_1_0')) return 'Basislaktat +1,0';
  if (id.contains('baseline_plus_0_5')) return 'Basislaktat +0,5';
  if (id.contains('2_0mmol')) return '2,0 mmol/l';
  if (id.contains('3_0mmol')) return '3,0 mmol/l';
  if (id.contains('4_0mmol')) return '4,0 mmol/l';
  return id;
}

String? preferredAvailableMethodId(
  Iterable<String> available,
  ThresholdType type,
) {
  final values = available.toList(growable: false);
  final preferred = standardMethodId(type);
  if (values.contains(preferred)) return preferred;
  return values.firstOrNull;
}
