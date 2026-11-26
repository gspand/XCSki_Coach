import 'package:xc_coach/lala/core/models/analysis_input.dart';
import 'package:xc_coach/lala/core/models/quality_result.dart';
import 'package:xc_coach/lala/core/preprocessing/preprocessing_result.dart';
import 'package:xc_coach/lala/core/quality/quality_rule.dart';

class QualityAssessor {
  const QualityAssessor({required this.rules});

  final List<QualityRule> rules;

  QualityResult assess(AnalysisInput input, PreprocessingResult preprocessing) {
    final findings = <QualityFinding>[];

    for (final rule in rules) {
      final finding = rule.evaluate(input, preprocessing);
      if (finding != null) {
        findings.add(finding);
      }
    }

    final errorCount = findings
        .where((finding) => finding.severity == QualitySeverity.error)
        .length;
    final warningCount = findings
        .where((finding) => finding.severity == QualitySeverity.warning)
        .length;

    final overall = switch ((errorCount, warningCount)) {
      (>= 2, _) => QualityOverallLevel.limited,
      (_, >= 4) => QualityOverallLevel.limited,
      (1, _) => QualityOverallLevel.medium,
      (_, >= 1) => QualityOverallLevel.medium,
      _ => QualityOverallLevel.high,
    };

    return QualityResult(overallLevel: overall, findings: findings);
  }
}
