import 'package:xc_coach/lala/core/models/analysis_input.dart';
import 'package:xc_coach/lala/core/models/quality_result.dart';
import 'package:xc_coach/lala/core/preprocessing/preprocessing_result.dart';

abstract interface class QualityRule {
  String get id;

  QualityFinding? evaluate(
    AnalysisInput input,
    PreprocessingResult preprocessing,
  );
}
