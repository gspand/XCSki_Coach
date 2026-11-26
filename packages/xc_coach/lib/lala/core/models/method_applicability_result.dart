import 'package:xc_coach/lala/core/models/method_metadata.dart';

class MethodApplicabilityResult {
  const MethodApplicabilityResult({
    required this.status,
    required this.satisfiedRequirements,
    required this.violatedRequirements,
    required this.warnings,
  });

  final MethodApplicabilityStatus status;
  final List<String> satisfiedRequirements;
  final List<String> violatedRequirements;
  final List<String> warnings;
}
