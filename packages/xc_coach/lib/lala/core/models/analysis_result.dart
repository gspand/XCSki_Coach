import 'package:xc_coach/lala/core/audit/analysis_audit_record.dart';
import 'package:xc_coach/lala/core/analysis/heart_rate_curve_analysis.dart';
import 'package:xc_coach/lala/core/models/quality_result.dart';
import 'package:xc_coach/lala/core/models/threshold_result.dart';

class AnalysisResult {
  const AnalysisResult({
    required this.validationErrors,
    required this.validationWarnings,
    required this.qualityResult,
    required this.thresholdResults,
    required this.heartRateCurveAnalysis,
    required this.auditRecord,
  });

  final List<String> validationErrors;
  final List<String> validationWarnings;
  final QualityResult qualityResult;
  final List<ThresholdResult> thresholdResults;
  final HeartRateCurveAnalysis heartRateCurveAnalysis;
  final AnalysisAuditRecord auditRecord;
}
