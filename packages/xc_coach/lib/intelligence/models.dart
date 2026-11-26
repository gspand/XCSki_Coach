/// Typed, serialisable facts passed from deterministic GIULIA analysis to the
/// coach language layer.
///
/// These objects deliberately contain no database rows and no widgets. They
/// are the structured boundary an eventual remote or on-device language model
/// may receive. A model can explain these facts; it cannot replace or mutate
/// the calculations that produced them.
library;

import '../domain/diagnostic_catalogue.dart';
import '../domain/diagnostic_comparability.dart';

enum IntelligenceConfidence {
  high('hoch'),
  moderate('mittel'),
  low('niedrig'),
  insufficient('nicht ausreichend');

  const IntelligenceConfidence(this.label);
  final String label;
}

enum IntelligenceSource {
  measurement,
  lalaEngine,
  deterministicAnalysis,
  subjective,
  academy,
}

class IntelligenceEvidence {
  const IntelligenceEvidence({
    required this.label,
    required this.value,
    required this.source,
    this.unit,
    this.sourceId,
    this.observedAtUtcUs,
    this.caveat,
  });

  final String label;
  final num value;
  final String? unit;
  final IntelligenceSource source;
  final String? sourceId;
  final int? observedAtUtcUs;
  final String? caveat;

  Map<String, Object?> toJson() => {
    'label': label,
    'value': value,
    if (unit != null) 'unit': unit,
    'source': source.name,
    if (sourceId != null) 'sourceId': sourceId,
    if (observedAtUtcUs != null) 'observedAtUtcUs': observedAtUtcUs,
    if (caveat != null) 'caveat': caveat,
  };
}

class IntelligenceAthlete {
  const IntelligenceAthlete({
    required this.id,
    required this.name,
    this.birthYear,
    this.sex,
    this.bodyMassKg,
    this.maxHeartRateBpm,
    this.restingHeartRateBpm,
  });

  final String id;
  final String name;
  final int? birthYear;
  final String? sex;
  final double? bodyMassKg;
  final int? maxHeartRateBpm;
  final int? restingHeartRateBpm;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (birthYear != null) 'birthYear': birthYear,
    if (sex != null) 'sex': sex,
    if (bodyMassKg != null) 'bodyMassKg': bodyMassKg,
    if (maxHeartRateBpm != null) 'maxHeartRateBpm': maxHeartRateBpm,
    if (restingHeartRateBpm != null) 'restingHeartRateBpm': restingHeartRateBpm,
  };
}

enum IntelligenceObservationType { lactate, rpe, note }

class IntelligenceObservation {
  const IntelligenceObservation({
    required this.type,
    required this.observedAtUtcUs,
    this.value,
    this.text,
    this.unit,
    this.sessionId,
    this.testId,
    this.quality = 'recorded',
  });

  final IntelligenceObservationType type;
  final int observedAtUtcUs;
  final double? value;
  final String? text;
  final String? unit;
  final String? sessionId;
  final String? testId;
  final String quality;

  bool get usable => quality != 'rejected';

  Map<String, Object?> toJson() => {
    'type': type.name,
    'observedAtUtcUs': observedAtUtcUs,
    if (value != null) 'value': value,
    if (text != null) 'text': text,
    if (unit != null) 'unit': unit,
    if (sessionId != null) 'sessionId': sessionId,
    if (testId != null) 'testId': testId,
    'quality': quality,
  };
}

class IntelligenceInterval {
  const IntelligenceInterval({
    required this.ordinal,
    required this.durationSeconds,
    required this.kind,
    this.averagePowerWatt,
    this.peakPowerWatt,
    this.averageSpeedKmh,
    this.peakSpeedKmh,
    this.leftPowerWatt,
    this.rightPowerWatt,
    this.targetMinWatt,
    this.targetMaxWatt,
  });

  final int ordinal;
  final int durationSeconds;
  final String kind;
  final double? averagePowerWatt;
  final double? peakPowerWatt;
  final double? averageSpeedKmh;
  final double? peakSpeedKmh;
  final double? leftPowerWatt;
  final double? rightPowerWatt;
  final double? targetMinWatt;
  final double? targetMaxWatt;

  double? get symmetryPercent {
    final left = leftPowerWatt;
    final right = rightPowerWatt;
    if (left == null || right == null || left + right <= 0) return null;
    return 100 * (1 - (left - right).abs() / (left + right));
  }

  Map<String, Object?> toJson() => {
    'ordinal': ordinal,
    'durationSeconds': durationSeconds,
    'kind': kind,
    if (averagePowerWatt != null) 'averagePowerWatt': averagePowerWatt,
    if (peakPowerWatt != null) 'peakPowerWatt': peakPowerWatt,
    if (averageSpeedKmh != null) 'averageSpeedKmh': averageSpeedKmh,
    if (peakSpeedKmh != null) 'peakSpeedKmh': peakSpeedKmh,
    if (leftPowerWatt != null) 'leftPowerWatt': leftPowerWatt,
    if (rightPowerWatt != null) 'rightPowerWatt': rightPowerWatt,
    if (targetMinWatt != null) 'targetMinWatt': targetMinWatt,
    if (targetMaxWatt != null) 'targetMaxWatt': targetMaxWatt,
  };
}

class IntelligenceSession {
  const IntelligenceSession({
    required this.id,
    required this.startedAtUtcUs,
    required this.durationSeconds,
    required this.sport,
    required this.completed,
    this.providerId,
    this.averagePowerWatt,
    this.peakPowerWatt,
    this.averageSpeedKmh,
    this.peakSpeedKmh,
    this.distanceMetres,
    this.workJoule,
    this.averageHeartRateBpm,
    this.peakHeartRateBpm,
    this.rpe,
    this.strokeCount,
    this.strokeRatePerMinute,
    this.workPerStrokeJoule,
    this.leftPowerWatt,
    this.rightPowerWatt,
    this.symmetryPercent,
    this.fatiguePercent,
    this.powerVariationPercent,
    this.intervals = const [],
  });

  final String id;
  final int startedAtUtcUs;
  final int durationSeconds;
  final String sport;
  final bool completed;
  final String? providerId;
  final double? averagePowerWatt;
  final double? peakPowerWatt;
  final double? averageSpeedKmh;
  final double? peakSpeedKmh;
  final double? distanceMetres;
  final double? workJoule;
  final int? averageHeartRateBpm;
  final int? peakHeartRateBpm;
  final double? rpe;
  final int? strokeCount;
  final double? strokeRatePerMinute;
  final double? workPerStrokeJoule;
  final double? leftPowerWatt;
  final double? rightPowerWatt;
  final double? symmetryPercent;
  final double? fatiguePercent;
  final double? powerVariationPercent;
  final List<IntelligenceInterval> intervals;

  bool get hasErcolinaMetrics =>
      strokeCount != null && strokeCount! > 0 && averagePowerWatt != null;

  Map<String, Object?> toJson() => {
    'id': id,
    'startedAtUtcUs': startedAtUtcUs,
    'durationSeconds': durationSeconds,
    'sport': sport,
    'completed': completed,
    if (providerId != null) 'providerId': providerId,
    if (averagePowerWatt != null) 'averagePowerWatt': averagePowerWatt,
    if (peakPowerWatt != null) 'peakPowerWatt': peakPowerWatt,
    if (averageSpeedKmh != null) 'averageSpeedKmh': averageSpeedKmh,
    if (peakSpeedKmh != null) 'peakSpeedKmh': peakSpeedKmh,
    if (distanceMetres != null) 'distanceMetres': distanceMetres,
    if (workJoule != null) 'workJoule': workJoule,
    if (averageHeartRateBpm != null) 'averageHeartRateBpm': averageHeartRateBpm,
    if (peakHeartRateBpm != null) 'peakHeartRateBpm': peakHeartRateBpm,
    if (rpe != null) 'rpe': rpe,
    if (strokeCount != null) 'strokeCount': strokeCount,
    if (strokeRatePerMinute != null) 'strokeRatePerMinute': strokeRatePerMinute,
    if (workPerStrokeJoule != null) 'workPerStrokeJoule': workPerStrokeJoule,
    if (leftPowerWatt != null) 'leftPowerWatt': leftPowerWatt,
    if (rightPowerWatt != null) 'rightPowerWatt': rightPowerWatt,
    if (symmetryPercent != null) 'symmetryPercent': symmetryPercent,
    if (fatiguePercent != null) 'fatiguePercent': fatiguePercent,
    if (powerVariationPercent != null)
      'powerVariationPercent': powerVariationPercent,
    'intervals': [for (final interval in intervals) interval.toJson()],
  };
}

class IntelligenceCurvePoint {
  const IntelligenceCurvePoint({
    required this.stageNumber,
    required this.load,
    required this.lactateMmolPerLitre,
    required this.excluded,
    this.heartRateBpm,
    this.rpe,
    this.partial = false,
  });

  final int stageNumber;
  final double load;
  final double lactateMmolPerLitre;
  final int? heartRateBpm;
  final double? rpe;
  final bool excluded;
  final bool partial;

  Map<String, Object?> toJson() => {
    'stageNumber': stageNumber,
    'load': load,
    'lactateMmolPerLitre': lactateMmolPerLitre,
    if (heartRateBpm != null) 'heartRateBpm': heartRateBpm,
    if (rpe != null) 'rpe': rpe,
    'excluded': excluded,
    'partial': partial,
  };
}

class IntelligenceThreshold {
  const IntelligenceThreshold({
    required this.type,
    required this.methodId,
    required this.methodVersion,
    required this.engineVersion,
    required this.status,
    required this.loadUnit,
    required this.selected,
    this.load,
    this.heartRateBpm,
    this.lactateMmolPerLitre,
    this.interpretation,
  });

  final String type;
  final String methodId;
  final String methodVersion;
  final String engineVersion;
  final String status;
  final double? load;
  final String loadUnit;
  final int? heartRateBpm;
  final double? lactateMmolPerLitre;
  final bool selected;
  final String? interpretation;

  Map<String, Object?> toJson() => {
    'type': type,
    'methodId': methodId,
    'methodVersion': methodVersion,
    'engineVersion': engineVersion,
    'status': status,
    if (load != null) 'load': load,
    'loadUnit': loadUnit,
    if (heartRateBpm != null) 'heartRateBpm': heartRateBpm,
    if (lactateMmolPerLitre != null) 'lactateMmolPerLitre': lactateMmolPerLitre,
    'selected': selected,
    if (interpretation != null) 'interpretation': interpretation,
  };
}

class IntelligenceZone {
  const IntelligenceZone({
    required this.modelId,
    required this.modelName,
    required this.modelVersion,
    required this.engineVersion,
    required this.quality,
    required this.name,
    required this.code,
    required this.loadUnit,
    required this.provisional,
    this.lowerLoad,
    this.upperLoad,
    this.lowerHeartRateBpm,
    this.upperHeartRateBpm,
    this.rationale,
  });

  final String modelId;
  final String modelName;
  final String modelVersion;
  final String engineVersion;
  final String quality;
  final String name;
  final String code;
  final String loadUnit;
  final double? lowerLoad;
  final double? upperLoad;
  final int? lowerHeartRateBpm;
  final int? upperHeartRateBpm;
  final bool provisional;
  final String? rationale;

  Map<String, Object?> toJson() => {
    'modelId': modelId,
    'modelName': modelName,
    'modelVersion': modelVersion,
    'engineVersion': engineVersion,
    'quality': quality,
    'name': name,
    'code': code,
    'loadUnit': loadUnit,
    if (lowerLoad != null) 'lowerLoad': lowerLoad,
    if (upperLoad != null) 'upperLoad': upperLoad,
    if (lowerHeartRateBpm != null) 'lowerHeartRateBpm': lowerHeartRateBpm,
    if (upperHeartRateBpm != null) 'upperHeartRateBpm': upperHeartRateBpm,
    'provisional': provisional,
    if (rationale != null) 'rationale': rationale,
  };
}

class IntelligenceTest {
  const IntelligenceTest({
    required this.id,
    required this.startedAtUtcUs,
    required this.sport,
    required this.loadUnit,
    required this.loadSemantics,
    required this.protocol,
    required this.status,
    required this.curve,
    required this.thresholds,
    required this.zones,
    required this.structure,
    required this.engineVersion,
    required this.qualityNotes,
  });

  final String id;
  final int startedAtUtcUs;
  final String sport;
  final String loadUnit;
  final String loadSemantics;
  final String protocol;
  final String status;
  final List<IntelligenceCurvePoint> curve;
  final List<IntelligenceThreshold> thresholds;
  final List<IntelligenceZone> zones;
  final DiagnosticStepStructure? structure;
  final String? engineVersion;
  final List<String> qualityNotes;

  IntelligenceThreshold? threshold(String type) {
    for (final item in thresholds) {
      if (item.type == type && item.selected && item.load != null) return item;
    }
    return null;
  }

  /// Sport under which this test's values may be used; legacy Ercolina tests
  /// stored as `generic` count as Ercolina.
  String get sportKey =>
      diagnosticComparisonSport(sport: sport, protocol: protocol);

  double? get maximumLoad {
    final values = curve
        .where((point) => !point.excluded)
        .map((point) => point.load);
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a > b ? a : b);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'startedAtUtcUs': startedAtUtcUs,
    'sport': sport,
    'loadUnit': loadUnit,
    'loadSemantics': loadSemantics,
    'protocol': protocol,
    'status': status,
    'curve': [for (final point in curve) point.toJson()],
    'thresholds': [for (final threshold in thresholds) threshold.toJson()],
    'zones': [for (final zone in zones) zone.toJson()],
    if (structure != null)
      'structure': {
        'increment': structure!.increment,
        'stageSeconds': structure!.stageSeconds,
      },
    if (engineVersion != null) 'engineVersion': engineVersion,
    'qualityNotes': qualityNotes,
  };
}

abstract interface class IntelligenceDataSource {
  IntelligenceAthlete? getAthleteProfile(String athleteId);

  List<IntelligenceSession> getRecentTraining(
    String athleteId, {
    int? fromUtcUs,
    int limit = 40,
  });

  List<IntelligenceTest> getTests(String athleteId, {int limit = 10});

  List<IntelligenceObservation> getObservations(
    String athleteId, {
    int? fromUtcUs,
  });
}

class TrainingLoadContext {
  const TrainingLoadContext({
    required this.sessions7Days,
    required this.duration7Days,
    required this.work7DaysJoule,
    required this.sessionsPrevious21Days,
    required this.durationPrevious21Days,
    required this.highIntensitySeconds7Days,
    required this.intensityClassifiedSeconds7Days,
    required this.missing,
  });

  final int sessions7Days;
  final int duration7Days;
  final double work7DaysJoule;
  final int sessionsPrevious21Days;
  final int durationPrevious21Days;
  final int highIntensitySeconds7Days;
  final int intensityClassifiedSeconds7Days;
  final List<String> missing;

  /// Seven days compared with the weekly mean of the preceding three weeks.
  double? get durationChangePercent {
    if (durationPrevious21Days <= 0) return null;
    final weeklyReference = durationPrevious21Days / 3;
    return (duration7Days - weeklyReference) / weeklyReference * 100;
  }

  Map<String, Object?> toJson() => {
    'sessions7Days': sessions7Days,
    'duration7Days': duration7Days,
    'work7DaysJoule': work7DaysJoule,
    'sessionsPrevious21Days': sessionsPrevious21Days,
    'durationPrevious21Days': durationPrevious21Days,
    'highIntensitySeconds7Days': highIntensitySeconds7Days,
    'intensityClassifiedSeconds7Days': intensityClassifiedSeconds7Days,
    if (durationChangePercent != null)
      'durationChangePercent': durationChangePercent,
    'missing': missing,
  };
}

enum TrendDirection { improving, stable, declining, mixed, unavailable }

class IntelligenceTrend {
  const IntelligenceTrend({
    required this.parameter,
    required this.direction,
    required this.summary,
    required this.confidence,
    required this.evidence,
    this.delta,
    this.deltaPercent,
    this.unit,
    this.caveat,
  });

  final String parameter;
  final TrendDirection direction;
  final String summary;
  final IntelligenceConfidence confidence;
  final double? delta;
  final double? deltaPercent;
  final String? unit;
  final List<IntelligenceEvidence> evidence;
  final String? caveat;

  Map<String, Object?> toJson() => {
    'parameter': parameter,
    'direction': direction.name,
    'summary': summary,
    'confidence': confidence.name,
    if (delta != null) 'delta': delta,
    if (deltaPercent != null) 'deltaPercent': deltaPercent,
    if (unit != null) 'unit': unit,
    'evidence': [for (final item in evidence) item.toJson()],
    if (caveat != null) 'caveat': caveat,
  };
}

class TestComparisonContext {
  const TestComparisonContext({
    required this.earlier,
    required this.later,
    required this.comparable,
    required this.trends,
    required this.caveats,
    required this.confidence,
  });

  final IntelligenceTest earlier;
  final IntelligenceTest later;
  final bool comparable;
  final List<IntelligenceTrend> trends;
  final List<String> caveats;
  final IntelligenceConfidence confidence;

  Map<String, Object?> toJson() => {
    'earlierTestId': earlier.id,
    'laterTestId': later.id,
    'comparable': comparable,
    'trends': [for (final trend in trends) trend.toJson()],
    'caveats': caveats,
    'confidence': confidence.name,
  };
}

enum ReadinessRecommendation {
  insufficient,
  recovery,
  easy,
  endurance,
  quality,
  technique,
}

class ReadinessContext {
  const ReadinessContext({
    required this.recommendation,
    required this.headline,
    required this.reasons,
    required this.evidence,
    required this.missing,
    required this.confidence,
  });

  final ReadinessRecommendation recommendation;
  final String headline;
  final List<String> reasons;
  final List<IntelligenceEvidence> evidence;
  final List<String> missing;
  final IntelligenceConfidence confidence;

  Map<String, Object?> toJson() => {
    'recommendation': recommendation.name,
    'headline': headline,
    'reasons': reasons,
    'evidence': [for (final item in evidence) item.toJson()],
    'missing': missing,
    'confidence': confidence.name,
  };
}

class ErcolinaFinding {
  const ErcolinaFinding({
    required this.parameter,
    required this.summary,
    required this.confidence,
    required this.evidence,
  });

  final String parameter;
  final String summary;
  final IntelligenceConfidence confidence;
  final List<IntelligenceEvidence> evidence;

  Map<String, Object?> toJson() => {
    'parameter': parameter,
    'summary': summary,
    'confidence': confidence.name,
    'evidence': [for (final item in evidence) item.toJson()],
  };
}

class ErcolinaContext {
  const ErcolinaContext({
    required this.session,
    required this.findings,
    required this.missing,
  });

  final IntelligenceSession? session;
  final List<ErcolinaFinding> findings;
  final List<String> missing;

  Map<String, Object?> toJson() => {
    if (session != null) 'session': session!.toJson(),
    'findings': [for (final finding in findings) finding.toJson()],
    'missing': missing,
  };
}

class AcademyKnowledge {
  const AcademyKnowledge({
    required this.articleId,
    required this.title,
    required this.summary,
    required this.evidenceLabel,
  });

  final String articleId;
  final String title;
  final String summary;
  final String evidenceLabel;

  Map<String, Object?> toJson() => {
    'articleId': articleId,
    'title': title,
    'summary': summary,
    'evidenceLabel': evidenceLabel,
  };
}

class IntelligenceToolCall {
  const IntelligenceToolCall({
    required this.name,
    required this.arguments,
    required this.output,
    this.missing = const [],
  });

  final String name;
  final Map<String, Object?> arguments;
  final Object? output;
  final List<String> missing;

  Map<String, Object?> toJson() => {
    'name': name,
    'arguments': arguments,
    'output': output,
    'missing': missing,
  };
}

class StructuredCoachContext {
  const StructuredCoachContext({
    required this.question,
    required this.athleteId,
    required this.calls,
  });

  final String question;
  final String athleteId;
  final List<IntelligenceToolCall> calls;

  Map<String, Object?> toJson() => {
    'question': question,
    'athleteId': athleteId,
    'tools': [for (final call in calls) call.toJson()],
  };
}

enum CoachAnswerKind { recommendation, explanation, comparison, limitation }

class CoachAnswer {
  const CoachAnswer({
    required this.kind,
    required this.title,
    required this.recommendation,
    required this.reasoning,
    required this.evidence,
    required this.uncertainty,
    required this.confidence,
    required this.knowledge,
    required this.context,
  });

  final CoachAnswerKind kind;
  final String title;
  final String recommendation;
  final List<String> reasoning;
  final List<IntelligenceEvidence> evidence;
  final List<String> uncertainty;
  final IntelligenceConfidence confidence;
  final List<AcademyKnowledge> knowledge;
  final StructuredCoachContext context;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'title': title,
    'recommendation': recommendation,
    'reasoning': reasoning,
    'evidence': [for (final item in evidence) item.toJson()],
    'uncertainty': uncertainty,
    'confidence': confidence.name,
    'knowledge': [for (final item in knowledge) item.toJson()],
    'context': context.toJson(),
  };
}
