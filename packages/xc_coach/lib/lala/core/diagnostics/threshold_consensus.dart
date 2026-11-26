import 'dart:math' as math;

import 'package:xc_coach/lala/core/models/method_metadata.dart';
import 'package:xc_coach/lala/core/models/threshold_result.dart';
import 'package:xc_coach/lala/core/registry/method_registry.dart';

/// Gemeinsame Registrierung fuer Namen und Kategorien der Verfahren.
final MethodRegistry sharedMethodRegistry = MethodRegistry();

/// Fachliche Gruppierung der Schwellenverfahren.
///
/// Die Gruppe entscheidet, ob ein Verfahren den Schwellenbereich bestimmt oder
/// nur als Vergleichsmarke dient.
enum ThresholdMethodFamily {
  /// Individuelle Kurvenverfahren wie Dmax, Modified Dmax, Log-Log, Dickhuth.
  curveBreakpoint,

  /// Anstieg um einen festen Betrag ueber das Ruhelaktat.
  baselineRise,

  /// Feste Laktatkonzentration. Bevoelkerungsbezogen, nicht individuell.
  fixedConcentration,

  other,
}

extension ThresholdMethodFamilyX on ThresholdMethodFamily {
  String get label => switch (this) {
    ThresholdMethodFamily.curveBreakpoint => 'Individuelles Kurvenverfahren',
    ThresholdMethodFamily.baselineRise => 'Anstieg ueber Ruhelaktat',
    ThresholdMethodFamily.fixedConcentration => 'Fester Laktatwert',
    ThresholdMethodFamily.other => 'Sonstiges Verfahren',
  };

  String get shortLabel => switch (this) {
    ThresholdMethodFamily.curveBreakpoint => 'Kurvenverfahren',
    ThresholdMethodFamily.baselineRise => 'Ruhelaktat + Anstieg',
    ThresholdMethodFamily.fixedConcentration => 'Fester Wert',
    ThresholdMethodFamily.other => 'Sonstiges',
  };

  /// Nur individuelle Verfahren bestimmen den Schwellenbereich.
  bool get isIndividual => this != ThresholdMethodFamily.fixedConcentration;
}

ThresholdMethodFamily familyOfMethod(String methodId) {
  final metadata = sharedMethodRegistry.findById(methodId)?.metadata;
  return switch (metadata?.category) {
    ThresholdMethodCategory.fixedBloodLactate =>
      ThresholdMethodFamily.fixedConcentration,
    ThresholdMethodCategory.breakpointModel =>
      ThresholdMethodFamily.curveBreakpoint,
    ThresholdMethodCategory.lowerTransition ||
    ThresholdMethodCategory.upperTransition =>
      ThresholdMethodFamily.baselineRise,
    _ =>
      methodId.startsWith('fixed_blood_lactate')
          ? ThresholdMethodFamily.fixedConcentration
          : ThresholdMethodFamily.other,
  };
}

String methodShortName(String methodId) =>
    sharedMethodRegistry.findById(methodId)?.metadata.shortName ?? methodId;

String methodFullName(String methodId) =>
    sharedMethodRegistry.findById(methodId)?.metadata.fullName ?? methodId;

/// Rangfolge fuer die Wahl des Leitverfahrens. Hoeher bedeutet aussagekraeftiger.
int methodEvidenceRank(String methodId) => switch (methodId) {
  'MODDMAX_BISHOP_ALLDATA_V1' => 100,
  'LOGLOG_WORKLOAD_TWO_LINE_RSS_V1' => 95,
  'DMAX_CUBIC_WORKLOAD_V1' => 90,
  'DICKHUTH_LEMIN_DISCRETE_LINEAR_V1' => 80,
  'lt_lower.baseline_plus_1_0.v1' => 70,
  'lt_lower.baseline_plus_0_5.v1' => 60,
  _ =>
    familyOfMethod(methodId) == ThresholdMethodFamily.fixedConcentration
        ? 30
        : 50,
};

/// Uebereinstimmung der beitragenden Verfahren.
enum ThresholdAgreement {
  uniform,
  mostlyUniform,
  divergent,
  singleMethod,
  none,
}

extension ThresholdAgreementX on ThresholdAgreement {
  String get label => switch (this) {
    ThresholdAgreement.uniform => 'einheitlich',
    ThresholdAgreement.mostlyUniform => 'weitgehend einheitlich',
    ThresholdAgreement.divergent => 'uneinheitlich',
    ThresholdAgreement.singleMethod => 'nur ein Verfahren',
    ThresholdAgreement.none => 'kein Ergebnis',
  };
}

/// Wie ein einzelnes Verfahren in den Schwellenbereich eingegangen ist.
enum MethodContribution {
  /// Bestimmt den Bereich mit.
  leading,

  /// Individuelles Verfahren innerhalb der Streuung.
  included,

  /// Individuelles Verfahren, das als Ausreisser ausgeschlossen wurde.
  excludedOutlier,

  /// Fester Laktatwert. Dient nur dem Vergleich.
  reference,
}

extension MethodContributionX on MethodContribution {
  String get label => switch (this) {
    MethodContribution.leading => 'Leitverfahren',
    MethodContribution.included => 'fliesst ein',
    MethodContribution.excludedOutlier => 'als Ausreisser ausgeschlossen',
    MethodContribution.reference => 'nur Vergleichswert',
  };
}

class MethodContributionEntry {
  const MethodContributionEntry({
    required this.methodId,
    required this.shortName,
    required this.family,
    required this.contribution,
    required this.load,
    this.heartRate,
    this.lactate,
  });

  final String methodId;
  final String shortName;
  final ThresholdMethodFamily family;
  final MethodContribution contribution;
  final double load;
  final double? heartRate;
  final double? lactate;
}

/// Robuste Zusammenfuehrung mehrerer Schwellenverfahren zu einem Bereich.
///
/// Feste Laktatkonzentrationen sind bevoelkerungsbezogene Vergleichsmarken und
/// gehen deshalb nicht in den Bereich ein, solange individuelle Verfahren
/// vorliegen. Der Bereich entsteht aus Median und mittlerer absoluter Abweichung
/// statt aus dem Kleinst- und Groesstwert, damit ein einzelnes abweichendes
/// Verfahren den Bereich nicht aufblaeht.
class ThresholdConsensusBuilder {
  const ThresholdConsensusBuilder({
    this.outlierTolerance = 0.12,
    this.uniformBandRatio = 0.05,
    this.acceptableBandRatio = 0.10,
  });

  /// Zulaessige relative Abweichung vom Median, bevor ein Verfahren als
  /// Ausreisser gilt.
  final double outlierTolerance;
  final double uniformBandRatio;
  final double acceptableBandRatio;

  ThresholdConsensusData build({
    required ThresholdType thresholdType,
    required Iterable<ThresholdResult> results,
  }) {
    final usable = results
        .where((result) => result.thresholdType == thresholdType)
        .where((result) => result.thresholdLoad != null)
        .where(
          (result) =>
              result.status == ThresholdComputationStatus.success ||
              result.status == ThresholdComputationStatus.successWithWarnings,
        )
        .where(
          (result) =>
              result.implementationStatus == null ||
              result.implementationStatus ==
                  MethodImplementationStatus.implemented ||
              result.implementationStatus ==
                  MethodImplementationStatus.internallyVerified ||
              result.implementationStatus ==
                  MethodImplementationStatus.externallyValidated,
        )
        .toList(growable: false);

    if (usable.isEmpty) {
      return ThresholdConsensusData(
        thresholdType: thresholdType,
        agreement: ThresholdAgreement.none,
        contributions: const <MethodContributionEntry>[],
        basedOnFixedValuesOnly: false,
        explanation:
            'Keine geeignete Methode lieferte einen Wert. Es wird keine '
            'Schwelle behauptet.',
      );
    }

    final individual = usable
        .where((result) => familyOfMethod(result.methodId).isIndividual)
        .toList(growable: false);
    final fixedValues = usable
        .where((result) => !familyOfMethod(result.methodId).isIndividual)
        .toList(growable: false);

    final basedOnFixedOnly = individual.isEmpty;
    final base = basedOnFixedOnly ? fixedValues : individual;

    final loads = base.map((result) => result.thresholdLoad!).toList()..sort();
    final firstMedian = _median(loads);

    var retained = base;
    var excluded = const <ThresholdResult>[];
    if (base.length >= 3 && firstMedian > 0) {
      final kept = base
          .where(
            (result) =>
                (result.thresholdLoad! - firstMedian).abs() / firstMedian <=
                outlierTolerance,
          )
          .toList(growable: false);
      if (kept.length >= 2) {
        retained = kept;
        excluded = base
            .where((result) => !kept.contains(result))
            .toList(growable: false);
      }
    }

    final retainedLoads =
        retained.map((result) => result.thresholdLoad!).toList()..sort();
    final central = _median(retainedLoads);
    final deviations =
        retainedLoads.map((load) => (load - central).abs()).toList()..sort();
    final mad = _median(deviations);
    final halfBand = math.max(mad, central.abs() * 0.005);

    final minLoad = retainedLoads.first;
    final maxLoad = retainedLoads.last;
    final lower = (central - halfBand).clamp(minLoad, central);
    final upper = (central + halfBand).clamp(central, maxLoad);

    final leading = retained.reduce(
      (best, candidate) =>
          methodEvidenceRank(candidate.methodId) >
              methodEvidenceRank(best.methodId)
          ? candidate
          : best,
    );

    final bandRatio = central == 0 ? 0.0 : (upper - lower) / central.abs();
    final agreement = retained.length == 1
        ? ThresholdAgreement.singleMethod
        : bandRatio <= uniformBandRatio
        ? ThresholdAgreement.uniform
        : bandRatio <= acceptableBandRatio
        ? ThresholdAgreement.mostlyUniform
        : ThresholdAgreement.divergent;

    final contributions = <MethodContributionEntry>[
      for (final result in retained)
        _entry(
          result,
          result.methodId == leading.methodId
              ? MethodContribution.leading
              : MethodContribution.included,
        ),
      for (final result in excluded)
        _entry(result, MethodContribution.excludedOutlier),
      if (!basedOnFixedOnly)
        for (final result in fixedValues)
          _entry(result, MethodContribution.reference),
    ]..sort((first, second) => first.load.compareTo(second.load));

    return ThresholdConsensusData(
      thresholdType: thresholdType,
      lowerLoad: lower,
      upperLoad: upper,
      centralLoad: central,
      leadingMethodId: leading.methodId,
      leadingLoad: leading.thresholdLoad,
      leadingHeartRate: leading.interpolatedHeartRate,
      centralHeartRate: _medianOrNull(
        retained
            .map((result) => result.interpolatedHeartRate)
            .whereType<double>()
            .toList()
          ..sort(),
      ),
      agreement: agreement,
      contributions: contributions,
      basedOnFixedValuesOnly: basedOnFixedOnly,
      explanation: _explain(
        thresholdType: thresholdType,
        retainedCount: retained.length,
        excludedCount: excluded.length,
        leadingId: leading.methodId,
        agreement: agreement,
        basedOnFixedOnly: basedOnFixedOnly,
        referenceCount: basedOnFixedOnly ? 0 : fixedValues.length,
      ),
    );
  }

  MethodContributionEntry _entry(
    ThresholdResult result,
    MethodContribution contribution,
  ) => MethodContributionEntry(
    methodId: result.methodId,
    shortName: methodShortName(result.methodId),
    family: familyOfMethod(result.methodId),
    contribution: contribution,
    load: result.thresholdLoad!,
    heartRate: result.interpolatedHeartRate,
    lactate: result.interpolatedLactate,
  );

  String _explain({
    required ThresholdType thresholdType,
    required int retainedCount,
    required int excludedCount,
    required String leadingId,
    required ThresholdAgreement agreement,
    required bool basedOnFixedOnly,
    required int referenceCount,
  }) {
    final name = thresholdType == ThresholdType.lt1 ? 'LT1' : 'LT2';
    final parts = <String>[];
    if (basedOnFixedOnly) {
      parts.add(
        'Kein individuelles Kurvenverfahren lieferte ein Ergebnis. Der '
        '$name-Bereich stuetzt sich deshalb nur auf feste Laktatwerte und ist '
        'lediglich ein Vergleichsmass.',
      );
    } else {
      parts.add(
        'Der $name-Bereich stammt aus $retainedCount individuellen Verfahren, '
        'Leitverfahren ist ${methodShortName(leadingId)}.',
      );
    }
    if (excludedCount > 0) {
      parts.add(
        '$excludedCount Verfahren wich deutlich ab und wurde nicht in den '
        'Bereich uebernommen.',
      );
    }
    if (referenceCount > 0) {
      parts.add(
        'Feste Laktatwerte werden getrennt ausgewiesen, weil sie '
        'bevoelkerungsbezogen und nicht individuell sind.',
      );
    }
    parts.add(switch (agreement) {
      ThresholdAgreement.uniform => 'Die Verfahren stimmen eng ueberein.',
      ThresholdAgreement.mostlyUniform =>
        'Die Verfahren stimmen weitgehend ueberein.',
      ThresholdAgreement.divergent =>
        'Die Verfahren weichen deutlich voneinander ab. Eine Bestaetigung '
            'durch einen Dauertest ist hier besonders sinnvoll.',
      ThresholdAgreement.singleMethod =>
        'Nur ein Verfahren lieferte ein Ergebnis, eine Bestaetigung ist '
            'erforderlich.',
      ThresholdAgreement.none => '',
    });
    return parts.where((part) => part.isNotEmpty).join(' ');
  }

  static double _median(List<double> sorted) {
    if (sorted.isEmpty) return 0;
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  static double? _medianOrNull(List<double> sorted) =>
      sorted.isEmpty ? null : _median(sorted);
}

class ThresholdConsensusData {
  const ThresholdConsensusData({
    required this.thresholdType,
    required this.agreement,
    required this.contributions,
    required this.basedOnFixedValuesOnly,
    required this.explanation,
    this.lowerLoad,
    this.upperLoad,
    this.centralLoad,
    this.leadingMethodId,
    this.leadingLoad,
    this.leadingHeartRate,
    this.centralHeartRate,
  });

  final ThresholdType thresholdType;
  final double? lowerLoad;
  final double? upperLoad;
  final double? centralLoad;
  final String? leadingMethodId;
  final double? leadingLoad;
  final double? leadingHeartRate;
  final double? centralHeartRate;
  final ThresholdAgreement agreement;
  final List<MethodContributionEntry> contributions;
  final bool basedOnFixedValuesOnly;
  final String explanation;

  bool get isDetermined => centralLoad != null;

  List<MethodContributionEntry> get contributingMethods => contributions
      .where(
        (entry) =>
            entry.contribution == MethodContribution.leading ||
            entry.contribution == MethodContribution.included,
      )
      .toList(growable: false);

  List<MethodContributionEntry> get referenceMethods => contributions
      .where((entry) => entry.contribution == MethodContribution.reference)
      .toList(growable: false);

  List<MethodContributionEntry> get excludedMethods => contributions
      .where(
        (entry) => entry.contribution == MethodContribution.excludedOutlier,
      )
      .toList(growable: false);

  String get leadingMethodName =>
      leadingMethodId == null ? '-' : methodShortName(leadingMethodId!);

  /// Breite des Bereichs bezogen auf den Mittelwert.
  double? get bandRatio {
    final central = centralLoad;
    final lower = lowerLoad;
    final upper = upperLoad;
    if (central == null || lower == null || upper == null || central == 0) {
      return null;
    }
    return (upper - lower) / central.abs();
  }
}
