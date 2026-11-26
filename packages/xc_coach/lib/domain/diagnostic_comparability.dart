/// The one platform-wide answer to whether two diagnostic results may be
/// compared numerically.
///
/// Thresholds are still determined exclusively by LaLa. This rule operates
/// one level later: it protects every consumer of persisted results from
/// subtracting different sports, load definitions or step protocols. LaLa's
/// views and GIULIA Intelligence both delegate here so a permissive shadow
/// comparison cannot emerge beside the diagnostic product.
library;

/// The protocol properties that materially shape a step-test curve.
class DiagnosticStepStructure {
  const DiagnosticStepStructure({
    required this.increment,
    required this.stageSeconds,
  });

  /// Builds a structure from already filtered, ordered stages.
  ///
  /// Excluded stages must be removed by the caller: exclusion is a diagnostic
  /// decision and must not alter the description of the protocol that remains
  /// eligible for comparison.
  static DiagnosticStepStructure? fromStages(
    Iterable<({double load, int durationSeconds})> stages,
  ) {
    final used = stages.toList(growable: false);
    if (used.length < 2) return null;

    final seconds = used.first.durationSeconds;
    final increment = used[1].load - used[0].load;
    if (increment <= 0 || seconds <= 0) return null;

    for (var index = 1; index < used.length; index++) {
      final step = used[index].load - used[index - 1].load;
      if ((step - increment).abs() > 1e-6) return null;
      if (used[index].durationSeconds != seconds) return null;
    }
    return DiagnosticStepStructure(increment: increment, stageSeconds: seconds);
  }

  final double increment;
  final int stageSeconds;

  String get label =>
      '${_number(increment)} je ${(stageSeconds / 60).toStringAsFixed(0)} min';

  static String _number(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1).replaceAll('.', ',');

  @override
  bool operator ==(Object other) =>
      other is DiagnosticStepStructure &&
      (other.increment - increment).abs() < 1e-6 &&
      other.stageSeconds == stageSeconds;

  @override
  int get hashCode => Object.hash((increment * 1e6).round(), stageSeconds);
}

/// Why [earlier] and [later] must not be subtracted, or `null` when they may.
String? diagnosticIncomparability({
  String? earlierSport,
  String? laterSport,
  required String earlierLoadUnit,
  required String laterLoadUnit,
  required DiagnosticStepStructure? earlierStructure,
  required DiagnosticStepStructure? laterStructure,
  String earlierLoadSemantics = 'load.protocol_target',
  String laterLoadSemantics = 'load.protocol_target',
}) {
  if (earlierSport != null &&
      laterSport != null &&
      earlierSport != laterSport) {
    return 'Die Tests gehören zu unterschiedlichen Sportarten '
        '($earlierSport und $laterSport). Ein Zahlenvergleich ist nicht zulässig.';
  }
  if (earlierLoadUnit != laterLoadUnit) {
    return 'Die Tests verwenden unterschiedliche Belastungseinheiten '
        '($earlierLoadUnit und $laterLoadUnit). '
        'Ein Zahlenvergleich wäre irreführend.';
  }
  if (earlierLoadSemantics != laterLoadSemantics) {
    return 'Die Belastungsachsen der beiden Tests bedeuten Unterschiedliches '
        '(${diagnosticLoadSemanticsLabel(earlierLoadSemantics)} und '
        '${diagnosticLoadSemanticsLabel(laterLoadSemantics)}). '
        'Ein Zahlenvergleich wäre ein Vergleich zweier Definitionen.';
  }
  if (earlierStructure == null || laterStructure == null) {
    return 'Die Stufenstruktur mindestens eines Tests ist nicht eindeutig '
        '(weniger als zwei gültige Stufen, uneinheitlicher Sprung oder '
        'uneinheitliche Stufendauer). Ein Zahlenvergleich wäre nicht '
        'eindeutig dem Athleten zuzuordnen.';
  }
  if (earlierStructure != laterStructure) {
    return 'Die Stufenstruktur unterscheidet sich '
        '(${earlierStructure.label} und ${laterStructure.label}). '
        'Ein Zahlenvergleich wäre nicht eindeutig dem Athleten zuzuordnen.';
  }
  return null;
}

String diagnosticLoadSemanticsLabel(String id) => switch (id) {
  'load.protocol_target' => 'Sollleistung des Protokolls',
  'load.measured_mean.v1' => 'gemessene mittlere Leistung',
  'load.measured_steady_end.v1' => 'gemessene Leistung der Endphase',
  _ => id,
};
