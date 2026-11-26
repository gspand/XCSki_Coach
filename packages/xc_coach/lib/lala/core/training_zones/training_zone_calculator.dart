import 'package:xc_coach/lala/core/models/training_zone.dart';
import 'package:xc_coach/lala/core/training_zones/training_zone_model.dart';
import 'package:xc_coach/lala/core/training_zones/zone_definitions.dart';

/// Erzeugt Trainingszonen aus einem gemeinsamen physiologischen Ankersatz.
///
/// Der Dienst berechnet nie Schwellen. Ein Modellwechsel veraendert
/// ausschliesslich die Unterteilung und Benennung der Intensitaetsachse.
class TrainingZoneService {
  const TrainingZoneService();

  List<ZoneQualityIssue> validate(
    PhysiologicalAnchorSet anchors, {
    TrainingZoneModel model = thresholdAnchoredModel,
  }) {
    final issues = <ZoneQualityIssue>[];
    final lt1 = anchors.lt1;
    final upper = anchors.upper;
    final needsLt1 = _usesAnchor(model, ZoneAnchorRef.lt1);

    if (lt1 == null && needsLt1) {
      issues.add(
        const ZoneQualityIssue(
          severity: ZoneIssueSeverity.blocking,
          message: 'LTP1 konnte nicht stabil bestimmt werden.',
          consequence:
              'Ohne LTP1 lassen sich die unteren Bereiche dieses Modells '
              'nicht verankern.',
        ),
      );
    }
    if (upper == null) {
      issues.add(
        const ZoneQualityIssue(
          severity: ZoneIssueSeverity.blocking,
          message:
              'Es liegt weder ein bestaetigtes MLSS noch ein verwertbarer '
              'LTP2-Schaetzwert vor.',
          consequence: 'Die obere Zonengrenze kann nicht bestimmt werden.',
        ),
      );
    }
    if (lt1 != null && upper != null && lt1.load >= upper.load) {
      issues.add(
        ZoneQualityIssue(
          severity: ZoneIssueSeverity.blocking,
          message:
              'LTP1 (${_number(lt1.load, anchors)}) liegt nicht unterhalb der '
              'oberen Schwelle (${_number(upper.load, anchors)}).',
          consequence:
              'Die Reihenfolge der Schwellen ist nicht plausibel. Die '
              'Trainingsbereiche werden nicht erstellt.',
        ),
      );
    }
    if (needsLt1 && lt1?.heartRate == null) {
      issues.add(
        const ZoneQualityIssue(
          severity: ZoneIssueSeverity.warning,
          message: 'Zu LTP1 liegt keine Herzfrequenz vor.',
          consequence:
              'Die Herzfrequenzbereiche koennen nicht an LTP1 verankert '
              'werden. Steuern Sie ueber Leistung beziehungsweise Pace.',
        ),
      );
    }
    if (upper?.heartRate == null) {
      issues.add(
        const ZoneQualityIssue(
          severity: ZoneIssueSeverity.warning,
          message: 'Zur oberen Schwelle liegt keine Herzfrequenz vor.',
          consequence:
              'Die oberen Herzfrequenzbereiche koennen nicht bestimmt werden.',
        ),
      );
    }
    if (lt1?.heartRate != null &&
        upper?.heartRate != null &&
        lt1!.heartRate! >= upper!.heartRate!) {
      issues.add(
        ZoneQualityIssue(
          severity: ZoneIssueSeverity.warning,
          message:
              'Die Herzfrequenz an LTP1 (${lt1.heartRate} bpm) liegt nicht '
              'unter der Herzfrequenz an der oberen Schwelle '
              '(${upper.heartRate} bpm).',
          consequence:
              'Die Herzfrequenzbereiche werden nur eingeschraenkt erstellt, '
              'die Leistungsbereiche bleiben gueltig.',
        ),
      );
    }
    if (_needsExtendedAnchors(model) && !anchors.hasExtendedAnchors) {
      issues.add(
        const ZoneQualityIssue(
          severity: ZoneIssueSeverity.info,
          message: extendedAnchorNote,
          consequence:
              'Die betroffenen Zonen werden als vorlaeufig gekennzeichnet.',
        ),
      );
    }
    if (anchors.maximalPower == null) {
      issues.add(
        const ZoneQualityIssue(
          severity: ZoneIssueSeverity.info,
          message: 'Es liegt keine valide Maximalleistung vor.',
          consequence: 'Die oberste Zone wird nach oben offen dargestellt.',
        ),
      );
    }
    if (!anchors.upperConfirmed) {
      issues.add(
        ZoneQualityIssue(
          severity: ZoneIssueSeverity.info,
          message:
              'Die obere Schwelle beruht auf einer Schaetzung '
              '(${thresholdSourceLabels[anchors.upperSource]}).',
          consequence:
              'Die oberen Trainingsbereiche sind vorlaeufig. Ein '
              'MLSS-Bestaetigungstest kann die Zonengrenzen weiter '
              'praezisieren.',
        ),
      );
    }
    return issues;
  }

  GeneratedTrainingZoneSet generate({
    required PhysiologicalAnchorSet anchors,
    TrainingZoneModel model = thresholdAnchoredModel,
    DateTime? generatedAt,
    int revision = 1,
  }) {
    final issues = validate(anchors, model: model);
    final blocked = issues.any(
      (issue) => issue.severity == ZoneIssueSeverity.blocking,
    );
    final zones = blocked
        ? const <TrainingZone>[]
        : _buildZones(anchors, model);

    return GeneratedTrainingZoneSet(
      modelId: model.id,
      modelName: model.displayName,
      modelVersion: model.version,
      sportType: anchors.sportType,
      loadUnit: anchors.loadUnit,
      anchors: anchors,
      zones: zones,
      issues: issues,
      generatedAt: generatedAt ?? DateTime.now(),
      quality: _quality(anchors, issues, blocked),
      modelNotice: model.notice,
      revision: revision,
    );
  }

  /// Uebersetzt eine Belastung gleichzeitig in mehrere Modelle.
  Map<String, TrainingZone?> translate({
    required PhysiologicalAnchorSet anchors,
    required double load,
    required List<TrainingZoneModel> models,
  }) {
    final result = <String, TrainingZone?>{};
    for (final model in models) {
      final set = generate(anchors: anchors, model: model);
      result[model.id] = set.isUsable ? set.zoneForLoad(load) : null;
    }
    return result;
  }

  ZoneSetQuality _quality(
    PhysiologicalAnchorSet anchors,
    List<ZoneQualityIssue> issues,
    bool blocked,
  ) {
    if (blocked) {
      return ZoneSetQuality.notCalculable;
    }
    if (issues.any((issue) => issue.severity == ZoneIssueSeverity.warning)) {
      return ZoneSetQuality.limited;
    }
    if (anchors.upperConfirmed) {
      return ZoneSetQuality.confirmed;
    }
    return anchors.upperSource == ThresholdSource.estimatedLtp2
        ? ZoneSetQuality.plausible
        : ZoneSetQuality.provisional;
  }

  bool _usesAnchor(TrainingZoneModel model, ZoneAnchorRef ref) =>
      model.zones.any(
        (zone) =>
            zone.upperLoadRule?.anchor == ref ||
            zone.upperLoadRule?.blendTo == ref,
      );

  bool _needsExtendedAnchors(TrainingZoneModel model) => model.zones.any(
    (zone) => zone.upperLoadRule?.requiresExtendedAnchors ?? false,
  );

  List<TrainingZone> _buildZones(
    PhysiologicalAnchorSet anchors,
    TrainingZoneModel model,
  ) {
    final step = anchors.isSpeedBased ? 0.1 : 1.0;
    final zones = <TrainingZone>[];

    double? previousLoadExact;
    double? previousLoadDisplay;
    double? previousHrExact;
    int? previousHrDisplay;

    for (final definition in model.zones) {
      var upperExact = _resolveLoad(definition.upperLoadRule, anchors);
      if (upperExact != null &&
          previousLoadExact != null &&
          upperExact <= previousLoadExact) {
        // Enge Schwellenlagen duerfen die Reihenfolge nicht umkehren.
        upperExact = previousLoadExact + step;
      }
      final upperDisplay = upperExact == null
          ? null
          : _roundLoad(upperExact, anchors.isSpeedBased);
      final lowerDisplay = previousLoadDisplay == null
          ? 0.0
          : _roundLoad(previousLoadDisplay + step, anchors.isSpeedBased);

      var upperHrExact = _resolveHeartRate(
        definition.upperHeartRateRule,
        anchors,
      );
      if (upperHrExact != null &&
          previousHrExact != null &&
          upperHrExact <= previousHrExact) {
        upperHrExact = null;
      }
      final upperHrDisplay = upperHrExact?.round();
      final lowerHrDisplay = previousHrDisplay == null
          ? (upperHrExact == null ? null : 0)
          : previousHrDisplay + 1;

      final provisionalBoundary =
          (definition.upperLoadRule?.requiresExtendedAnchors ?? false) &&
          !anchors.hasExtendedAnchors;

      zones.add(
        TrainingZone(
          code: definition.code,
          displayName: definition.displayName,
          shortMeaning: definition.shortMeaning,
          physiologicalDomain: definition.domain,
          purpose: definition.purpose,
          preferredTrainingMethods: definition.typicalTrainingMethods,
          preferredControlMetrics: _controlMetricsFor(definition, anchors),
          boundaryRationale: _rationale(definition, upperExact, anchors),
          lowerLoadExact: previousLoadExact ?? 0,
          upperLoadExact: upperExact,
          lowerLoadDisplay: lowerDisplay,
          upperLoadDisplay: upperDisplay,
          lowerHeartRateExact: previousHrExact,
          upperHeartRateExact: upperHrExact,
          lowerHeartRateDisplay: lowerHrDisplay,
          upperHeartRateDisplay: upperHrDisplay,
          lowerPaceSeconds: anchors.isSpeedBased
              ? _paceSeconds(lowerDisplay)
              : null,
          upperPaceSeconds: anchors.isSpeedBased
              ? _paceSeconds(upperDisplay)
              : null,
          typicalDuration: definition.typicalDuration,
          typicalIntervalLength: definition.typicalIntervalLength,
          typicalLactate: definition.typicalLactate,
          typicalRpe: definition.typicalRpe,
          provisionalBoundary: provisionalBoundary,
        ),
      );

      previousLoadExact = upperExact;
      previousLoadDisplay = upperDisplay;
      previousHrExact = upperHrExact;
      previousHrDisplay = upperHrDisplay;
    }
    return List.unmodifiable(zones);
  }

  /// Bei Geschwindigkeitssportarten tritt Pace an die Stelle der Leistung.
  List<ControlMetric> _controlMetricsFor(
    ZoneDefinition definition,
    PhysiologicalAnchorSet anchors,
  ) {
    if (!anchors.isSpeedBased) {
      return definition.preferredControlMetrics;
    }
    return definition.preferredControlMetrics
        .map(
          (metric) =>
              metric == ControlMetric.power ? ControlMetric.pace : metric,
        )
        .toList(growable: false);
  }

  double? _resolveLoad(BoundaryRule? rule, PhysiologicalAnchorSet anchors) {
    if (rule == null) {
      return null;
    }
    final base = anchors.resolveLoadAnchor(rule.anchor);
    if (base == null) {
      return null;
    }
    final blendTo = rule.blendTo;
    if (blendTo != null) {
      final target = anchors.resolveLoadAnchor(blendTo);
      if (target == null) {
        return null;
      }
      return base + (target - base) * rule.blendFactor;
    }
    return base * rule.factor;
  }

  double? _resolveHeartRate(
    BoundaryRule? rule,
    PhysiologicalAnchorSet anchors,
  ) {
    if (rule == null) {
      return null;
    }
    final base = anchors.resolveHeartRateAnchor(rule.anchor);
    if (base == null) {
      return null;
    }
    final blendTo = rule.blendTo;
    if (blendTo != null) {
      final target = anchors.resolveHeartRateAnchor(blendTo);
      if (target == null) {
        return null;
      }
      return base + (target - base) * rule.blendFactor;
    }
    return base * rule.factor;
  }

  String _rationale(
    ZoneDefinition definition,
    double? upperExact,
    PhysiologicalAnchorSet anchors,
  ) {
    final rule = definition.upperLoadRule;
    if (rule == null) {
      return 'Die Zone ist nach oben offen und beginnt direkt oberhalb der '
          'darunterliegenden Grenze.';
    }
    final base = rule.rationale;
    if (upperExact == null) {
      return '$base Der Wert konnte mit den vorhandenen Daten nicht '
          'berechnet werden.';
    }
    return '$base Obergrenze: ${_number(upperExact, anchors)}.';
  }

  double _roundLoad(double value, bool isSpeedBased) =>
      isSpeedBased ? (value * 10).roundToDouble() / 10 : value.roundToDouble();

  int? _paceSeconds(double? speedKmH) =>
      speedKmH == null || speedKmH <= 0 ? null : (3600 / speedKmH).round();

  String _number(double value, PhysiologicalAnchorSet anchors) =>
      anchors.isSpeedBased
      ? '${value.toStringAsFixed(1)} ${anchors.loadUnit}'
      : '${value.round()} ${anchors.loadUnit}';
}
