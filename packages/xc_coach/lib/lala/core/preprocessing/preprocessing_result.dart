import 'package:xc_coach/lala/core/models/test_stage.dart';

class PreprocessingResult {
  const PreprocessingResult({
    required this.rawStages,
    required this.validStages,
    required this.sortedValidStages,
    required this.excludedStages,
    required this.validationErrors,
    required this.validationWarnings,
  });

  final List<TestStage> rawStages;
  final List<TestStage> validStages;
  final List<TestStage> sortedValidStages;
  final List<TestStage> excludedStages;
  final List<String> validationErrors;
  final List<String> validationWarnings;

  bool get hasErrors => validationErrors.isNotEmpty;
}
