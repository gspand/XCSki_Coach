import 'package:xc_coach/lala/core/models/analysis_input.dart';
import 'package:xc_coach/lala/core/models/method_applicability_result.dart';
import 'package:xc_coach/lala/core/models/test_protocol_metadata.dart';

abstract interface class MethodApplicabilityEvaluator {
  MethodApplicabilityResult evaluate(
    AnalysisInput input,
    TestProtocolMetadata protocol,
  );
}
