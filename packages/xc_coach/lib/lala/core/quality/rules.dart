import 'dart:math';

import 'package:xc_coach/lala/core/models/analysis_input.dart';
import 'package:xc_coach/lala/core/models/quality_result.dart';
import 'package:xc_coach/lala/core/preprocessing/preprocessing_result.dart';
import 'package:xc_coach/lala/core/quality/quality_rule.dart';

class MinimumValidStagesRule implements QualityRule {
  @override
  String get id => 'quality.min_valid_stages.v1';

  @override
  QualityFinding? evaluate(
    AnalysisInput input,
    PreprocessingResult preprocessing,
  ) {
    if (preprocessing.sortedValidStages.length >= 5) {
      return null;
    }
    return QualityFinding(
      ruleId: id,
      severity: QualitySeverity.warning,
      message: 'Weniger als fuenf gueltige Messstufen.',
      affectedStageNumbers: preprocessing.sortedValidStages
          .map((stage) => stage.stageNumber)
          .toList(growable: false),
      impact: 'Erhoehte Unsicherheit der Schwellenbestimmung.',
      suggestedMitigation:
          'Mehr gueltige Stufen mit gleichmaessiger Progression erfassen.',
    );
  }
}

class ExcludedPointsRule implements QualityRule {
  @override
  String get id => 'quality.excluded_points.v1';

  @override
  QualityFinding? evaluate(
    AnalysisInput input,
    PreprocessingResult preprocessing,
  ) {
    if (preprocessing.excludedStages.isEmpty) {
      return null;
    }
    return QualityFinding(
      ruleId: id,
      severity: QualitySeverity.warning,
      message: 'Ausgeschlossene Messpunkte vorhanden.',
      affectedStageNumbers: preprocessing.excludedStages
          .map((stage) => stage.stageNumber)
          .toList(growable: false),
      impact: 'Ergebnis basiert auf reduzierter Datenbasis.',
      suggestedMitigation:
          'Ausschlussgruende dokumentieren und Messqualitaet pruefen.',
    );
  }
}

class UnevenIncrementRule implements QualityRule {
  @override
  String get id => 'quality.uneven_increment.v1';

  @override
  QualityFinding? evaluate(
    AnalysisInput input,
    PreprocessingResult preprocessing,
  ) {
    final valid = preprocessing.sortedValidStages;
    if (valid.length < 3) {
      return null;
    }

    final increments = <double>[];
    for (var i = 1; i < valid.length; i++) {
      increments.add(valid[i].load - valid[i - 1].load);
    }

    final mean = increments.reduce((a, b) => a + b) / increments.length;
    final hasOutlier = increments.any(
      (inc) => (inc - mean).abs() > max(1.0, mean * 0.35),
    );
    if (!hasOutlier) {
      return null;
    }

    return QualityFinding(
      ruleId: id,
      severity: QualitySeverity.warning,
      message: 'Ungleichmaessige Belastungssteigerung erkannt.',
      affectedStageNumbers: valid
          .map((stage) => stage.stageNumber)
          .toList(growable: false),
      impact: 'Interpolation und Vergleichbarkeit koennen verzerrt sein.',
      suggestedMitigation: 'Konstantere Stufensteigerung verwenden.',
    );
  }
}

class FallingLactateRule implements QualityRule {
  @override
  String get id => 'quality.falling_lactate.v1';

  @override
  QualityFinding? evaluate(
    AnalysisInput input,
    PreprocessingResult preprocessing,
  ) {
    final valid = preprocessing.sortedValidStages;
    for (var i = 1; i < valid.length; i++) {
      if (valid[i].lactate < valid[i - 1].lactate - 0.1) {
        return QualityFinding(
          ruleId: id,
          severity: QualitySeverity.warning,
          message: 'Fallender Laktatwert trotz hoeherer Belastung erkannt.',
          affectedStageNumbers: <int>[
            valid[i - 1].stageNumber,
            valid[i].stageNumber,
          ],
          impact: 'Methoden koennen empfindlich auf diese Inversion reagieren.',
          suggestedMitigation:
              'Messung pruefen und bei Bedarf Wiederholung erwogen.',
        );
      }
    }
    return null;
  }
}

class MissingHeartRateRule implements QualityRule {
  @override
  String get id => 'quality.missing_hr.v1';

  @override
  QualityFinding? evaluate(
    AnalysisInput input,
    PreprocessingResult preprocessing,
  ) {
    final missing = preprocessing.sortedValidStages
        .where((stage) => stage.heartRate == null)
        .toList(growable: false);
    if (missing.isEmpty) {
      return null;
    }
    return QualityFinding(
      ruleId: id,
      severity: QualitySeverity.info,
      message: 'Fehlende Herzfrequenzwerte in gueltigen Stufen.',
      affectedStageNumbers: missing
          .map((stage) => stage.stageNumber)
          .toList(growable: false),
      impact: 'HF-bezogene Schwelleninterpretation eingeschraenkt.',
      suggestedMitigation: 'HF-Erfassung pruefen.',
    );
  }
}
