import 'package:xc_coach/lala/core/models/analysis_input.dart';
import 'package:xc_coach/lala/core/models/method_applicability_result.dart';
import 'package:xc_coach/lala/core/models/method_metadata.dart';
import 'package:xc_coach/lala/core/models/test_protocol_metadata.dart';
import 'package:xc_coach/lala/core/thresholds/method_applicability_evaluator.dart';

class DefaultApplicabilityEvaluator implements MethodApplicabilityEvaluator {
  const DefaultApplicabilityEvaluator({required this.metadata});

  final MethodMetadata metadata;

  @override
  MethodApplicabilityResult evaluate(
    AnalysisInput input,
    TestProtocolMetadata protocol,
  ) {
    final satisfied = <String>[];
    final violated = <String>[];
    final warnings = <String>[];

    final validStages = input.validStages;
    if (validStages.length >=
        metadata.protocolRequirements.minimumValidStages) {
      satisfied.add('Mindestanzahl gueltiger Stufen erfuellt.');
    } else {
      violated.add('Zu wenige gueltige Stufen fuer diese Methode.');
    }

    final stageDuration = protocol.stageDurationSeconds;
    final minDuration =
        metadata.protocolRequirements.minimumStageDurationSeconds;
    final maxDuration =
        metadata.protocolRequirements.maximumStageDurationSeconds;
    if (stageDuration != null &&
        minDuration != null &&
        stageDuration < minDuration) {
      warnings.add('Stufendauer liegt unter methodischer Empfehlung.');
    }
    if (stageDuration != null &&
        maxDuration != null &&
        stageDuration > maxDuration) {
      warnings.add('Stufendauer liegt ueber methodischer Empfehlung.');
    }

    if (metadata.protocolRequirements.requiresRecoverySamples) {
      if (protocol.recoveryLactateSamples.isEmpty) {
        violated.add('Erforderliche Erholungsmessungen fehlen.');
      } else {
        satisfied.add('Erholungsmessungen vorhanden.');
      }
    }

    if (metadata.protocolRequirements.supportedSports.isNotEmpty) {
      final sport = protocol.sportType;
      if (sport == null ||
          !metadata.protocolRequirements.supportedSports.contains(sport)) {
        warnings.add(
          'Sportartspezifische Evidenz fuer dieses Protokoll ist eingeschraenkt.',
        );
      } else {
        satisfied.add('Sportart innerhalb dokumentierter Evidenz.');
      }
    }

    final status = violated.isNotEmpty
        ? (violated.any((entry) => entry.contains('Erholungsmessungen'))
              ? MethodApplicabilityStatus.unsupportedProtocol
              : MethodApplicabilityStatus.insufficientData)
        : (warnings.isNotEmpty
              ? MethodApplicabilityStatus.applicableWithWarnings
              : MethodApplicabilityStatus.applicable);

    return MethodApplicabilityResult(
      status: status,
      satisfiedRequirements: satisfied,
      violatedRequirements: violated,
      warnings: warnings,
    );
  }
}
