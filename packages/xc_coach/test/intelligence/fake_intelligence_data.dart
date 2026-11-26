import 'package:xc_coach/domain/diagnostic_comparability.dart';
import 'package:xc_coach/intelligence/models.dart';

class FakeIntelligenceData implements IntelligenceDataSource {
  FakeIntelligenceData({
    this.profile = const IntelligenceAthlete(id: 'anna', name: 'Anna'),
    this.sessions = const [],
    this.tests = const [],
    this.observations = const [],
  });

  IntelligenceAthlete? profile;
  List<IntelligenceSession> sessions;
  List<IntelligenceTest> tests;
  List<IntelligenceObservation> observations;

  @override
  IntelligenceAthlete? getAthleteProfile(String athleteId) => profile;

  @override
  List<IntelligenceObservation> getObservations(
    String athleteId, {
    int? fromUtcUs,
  }) => observations
      .where((item) => fromUtcUs == null || item.observedAtUtcUs >= fromUtcUs)
      .toList();

  @override
  List<IntelligenceSession> getRecentTraining(
    String athleteId, {
    int? fromUtcUs,
    int limit = 40,
  }) => sessions
      .where((item) => fromUtcUs == null || item.startedAtUtcUs >= fromUtcUs)
      .take(limit)
      .toList();

  @override
  List<IntelligenceTest> getTests(String athleteId, {int limit = 10}) =>
      tests.take(limit).toList();
}

IntelligenceTest intelligenceTest({
  required String id,
  required int at,
  double lt1 = 180,
  double lt2 = 240,
  double maximum = 300,
  String sport = 'cycling',
  String unit = 'W',
  String semantics = 'load.protocol_target',
  String lt1Method = 'lt1-method',
  String lt2Method = 'lt2-method',
  List<double> lactate = const [1.2, 1.5, 2.2, 4.0, 7.0],
}) {
  final step = maximum / 5;
  return IntelligenceTest(
    id: id,
    startedAtUtcUs: at,
    sport: sport,
    loadUnit: unit,
    loadSemantics: semantics,
    protocol: 'test',
    status: 'completed',
    curve: [
      for (var index = 0; index < lactate.length; index++)
        IntelligenceCurvePoint(
          stageNumber: index + 1,
          load: step * (index + 1),
          lactateMmolPerLitre: lactate[index],
          heartRateBpm: 110 + index * 15,
          excluded: false,
        ),
    ],
    thresholds: [
      IntelligenceThreshold(
        type: 'lt1',
        methodId: lt1Method,
        methodVersion: '1',
        engineVersion: '1.0.0',
        status: 'success',
        loadUnit: unit,
        selected: true,
        load: lt1,
        heartRateBpm: 145,
      ),
      IntelligenceThreshold(
        type: 'lt2',
        methodId: lt2Method,
        methodVersion: '1',
        engineVersion: '1.0.0',
        status: 'success',
        loadUnit: unit,
        selected: true,
        load: lt2,
        heartRateBpm: 170,
      ),
    ],
    zones: const [],
    structure: DiagnosticStepStructure(increment: 60, stageSeconds: 180),
    engineVersion: '1.0.0',
    qualityNotes: const [],
  );
}

IntelligenceSession intelligenceSession({
  String id = 'session',
  required int at,
  int durationSeconds = 3600,
  double power = 180,
  double? rpe,
  double symmetry = 98,
  double fatigue = -3,
  List<IntelligenceInterval> intervals = const [],
}) => IntelligenceSession(
  id: id,
  startedAtUtcUs: at,
  durationSeconds: durationSeconds,
  sport: 'ercolina',
  completed: true,
  averagePowerWatt: power,
  peakPowerWatt: power * 1.8,
  workJoule: power * durationSeconds,
  rpe: rpe,
  strokeCount: 1800,
  strokeRatePerMinute: 50,
  workPerStrokeJoule: power * durationSeconds / 1800,
  leftPowerWatt: power * .51,
  rightPowerWatt: power * .49,
  symmetryPercent: symmetry,
  fatiguePercent: fatigue,
  powerVariationPercent: 5,
  intervals: intervals,
);
