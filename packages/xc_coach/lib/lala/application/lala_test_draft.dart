/// Draft of a manually recorded step test.
///
/// This is the state of the entry form before anything is written down. It is
/// pure Dart and holds no opinion about physiology: it checks that the person
/// entering the data has entered enough of it to *store* a test, nothing more.
///
/// Whether the data is scientifically sufficient for a given method is the
/// engine's decision, made later, during the calculation run. The form must
/// not pre-empt that — a protocol that is too short for Hofmann is still a
/// legitimate test with a legitimate Log-Log result.
library;

import 'package:xc_coach/measurement/contracts/test_protocol.dart';

/// One step as it is being typed in.
class LalaStageDraft {
  const LalaStageDraft({
    required this.stageNumber,
    this.load,
    this.durationSeconds,
    this.heartRateBpm,
    this.rpe,
    this.lactateMmolPerLitre,
    this.excluded = false,
    this.exclusionReason,
  });

  final int stageNumber;
  final double? load;
  final int? durationSeconds;
  final int? heartRateBpm;
  final int? rpe;
  final double? lactateMmolPerLitre;
  final bool excluded;
  final String? exclusionReason;

  /// A step is analysable once it carries both a load and a lactate value.
  bool get isComplete => load != null && lactateMmolPerLitre != null;

  /// Partially filled, e.g. a load but no lactate yet.
  bool get isStarted =>
      load != null ||
      lactateMmolPerLitre != null ||
      heartRateBpm != null ||
      rpe != null;

  LalaStageDraft copyWith({
    double? load,
    int? durationSeconds,
    int? heartRateBpm,
    int? rpe,
    double? lactateMmolPerLitre,
    bool? excluded,
    String? exclusionReason,
    bool clearLoad = false,
    bool clearLactate = false,
    bool clearHeartRate = false,
    bool clearRpe = false,
  }) => LalaStageDraft(
    stageNumber: stageNumber,
    load: clearLoad ? null : (load ?? this.load),
    durationSeconds: durationSeconds ?? this.durationSeconds,
    heartRateBpm: clearHeartRate ? null : (heartRateBpm ?? this.heartRateBpm),
    rpe: clearRpe ? null : (rpe ?? this.rpe),
    lactateMmolPerLitre: clearLactate
        ? null
        : (lactateMmolPerLitre ?? this.lactateMmolPerLitre),
    excluded: excluded ?? this.excluded,
    exclusionReason: exclusionReason ?? this.exclusionReason,
  );
}

/// The complete entry state of a new manual test.
class LalaTestDraft {
  LalaTestDraft({
    required this.athleteId,
    required this.preset,
    required this.startedAtUtcUs,
    List<LalaStageDraft>? stages,
    this.notes,
  }) : stages =
           stages ??
           List<LalaStageDraft>.generate(
             _initialStageCount,
             (index) => LalaStageDraft(
               stageNumber: index + 1,
               load: preset.loadOfStage(index + 1),
               durationSeconds: preset.stageDurationSeconds,
             ),
           );

  static const int _initialStageCount = 6;

  final String athleteId;
  final TestProtocol preset;
  final int startedAtUtcUs;
  final List<LalaStageDraft> stages;
  final String? notes;

  String get sport => preset.sport;
  String get loadUnit => preset.loadUnit;

  /// Steps that can actually be analysed.
  List<LalaStageDraft> get completeStages =>
      stages.where((stage) => stage.isComplete).toList(growable: false);

  /// A test can be stored as soon as one step carries load and lactate.
  ///
  /// One step is of course not a diagnostic — but refusing to *save* it would
  /// throw away entered measurements. The engine, not the form, decides what
  /// can be computed from it.
  bool get canSave => completeStages.isNotEmpty;

  /// Human-readable reason why saving is not yet possible.
  String? get blockingReason => canSave
      ? null
      : 'Mindestens eine Stufe braucht sowohl eine Belastung als auch einen '
            'Laktatwert.';

  /// Appends the next step, pre-filled from the protocol.
  LalaTestDraft withAdditionalStage() {
    final next = stages.length + 1;
    return copyWith(
      stages: <LalaStageDraft>[
        ...stages,
        LalaStageDraft(
          stageNumber: next,
          load: preset.loadOfStage(next),
          durationSeconds: preset.stageDurationSeconds,
        ),
      ],
    );
  }

  /// Removes the last step, as long as one remains.
  LalaTestDraft withoutLastStage() => stages.length <= 1
      ? this
      : copyWith(stages: stages.sublist(0, stages.length - 1));

  LalaTestDraft withStage(int stageNumber, LalaStageDraft stage) => copyWith(
    stages: <LalaStageDraft>[
      for (final existing in stages)
        if (existing.stageNumber == stageNumber) stage else existing,
    ],
  );

  /// Switches the protocol and re-fills loads of untouched steps.
  ///
  /// Steps that already carry entered measurements keep their values: changing
  /// a dropdown must never silently discard a measured number.
  LalaTestDraft withPreset(TestProtocol next) => LalaTestDraft(
    athleteId: athleteId,
    preset: next,
    startedAtUtcUs: startedAtUtcUs,
    notes: notes,
    stages: <LalaStageDraft>[
      for (final stage in stages)
        stage.lactateMmolPerLitre != null || stage.heartRateBpm != null
            ? stage
            : LalaStageDraft(
                stageNumber: stage.stageNumber,
                load: next.loadOfStage(stage.stageNumber),
                durationSeconds: next.stageDurationSeconds,
              ),
    ],
  );

  /// Changes the planning values for an own protocol. Existing measurements
  /// remain the source of truth and are never overwritten by form settings.
  LalaTestDraft withCustomProtocol({
    required String name,
    required String sport,
    required String loadUnit,
    required double startLoad,
    required double increment,
    required int stageDurationSeconds,
  }) => withPreset(
    TestProtocol.custom(
      name: name,
      sport: sport,
      loadUnit: loadUnit,
      startLoad: startLoad,
      increment: increment,
      stageDurationSeconds: stageDurationSeconds,
    ),
  );

  LalaTestDraft copyWith({
    String? athleteId,
    TestProtocol? preset,
    int? startedAtUtcUs,
    List<LalaStageDraft>? stages,
    String? notes,
  }) => LalaTestDraft(
    athleteId: athleteId ?? this.athleteId,
    preset: preset ?? this.preset,
    startedAtUtcUs: startedAtUtcUs ?? this.startedAtUtcUs,
    stages: stages ?? this.stages,
    notes: notes ?? this.notes,
  );
}
