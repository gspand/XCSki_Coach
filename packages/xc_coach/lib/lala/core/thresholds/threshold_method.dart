import 'package:xc_coach/lala/core/models/analysis_input.dart';
import 'package:xc_coach/lala/core/models/method_metadata.dart';
import 'package:xc_coach/lala/core/models/threshold_result.dart';
import 'package:xc_coach/lala/core/preprocessing/preprocessing_result.dart';

abstract interface class ThresholdMethod {
  MethodMetadata get metadata;

  ThresholdResult calculate(
    AnalysisInput input,
    PreprocessingResult preprocessing,
  );
}
