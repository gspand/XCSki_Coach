/// Ermüdungswiderstand und physiologische Entkopplung (Durability State).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Durability ist ein Evidenz-Gebiet und KEIN einzelner zusammengefasster Phantasiescore!
/// - Strikte Unterscheidung:
///   * «3 Stunden trainiert» = reine EXPOSITION (Umfang).
///   * «Leistung/EF blieb nach 3 Stunden stabil» = DURABILITY EVIDENZ.
/// - Jede Beobachtung hält Messbedingungen, Quelle und Konfidenz fest.
library;

import '../load/load_models.dart';

class DurabilityState {
  const DurabilityState({
    this.longSessionExposureHours28d = 0.0,
    this.longSessionCount28d = 0,
    this.observations = const [],
    this.confidence = 0.5,
  });

  /// Reine Exposition: Akkumulierte Dauer in Einheiten >= 90 Minuten (letzte 28 Tage).
  final double longSessionExposureHours28d;

  /// Anzahl absolvierter langer Einheiten (>= 90 min) in den letzten 28 Tagen.
  final int longSessionCount28d;

  /// Echte, gemessene Einzelbeobachtungen zu Ermüdungsresistenz und Entkopplung.
  final List<DurabilityObservation> observations;

  /// Gesamtkonfidenz der Durability-Aussage (nur hoch, wenn tatsächliche Messungen vorliegen).
  final double confidence;

  /// Liegen tatsächlich gemessene Entkopplungs- oder Degradationsbeobachtungen vor?
  bool get hasMeasuredObservations => observations.isNotEmpty;

  /// Beobachtungen zur aeroben Entkopplung (PW:HR Drift / EF Drift).
  List<DurabilityObservation> get decouplingObservations => observations
      .where((o) => o.type == DurabilityObservationType.hrExternalDecoupling)
      .toList(growable: false);

  /// Beobachtungen zum Leistungserhalt spät vs. früh.
  List<DurabilityObservation> get powerRetentionObservations => observations
      .where(
        (o) =>
            o.type == DurabilityObservationType.powerPaceDegradation ||
            o.type == DurabilityObservationType.ercolinaPowerRetention,
      )
      .toList(growable: false);

  Map<String, dynamic> toJson() => {
    'longSessionExposureHours28d': longSessionExposureHours28d,
    'longSessionCount28d': longSessionCount28d,
    'observations': observations.map((o) => o.toJson()).toList(),
    'confidence': confidence,
  };

  factory DurabilityState.fromJson(Map<String, dynamic> json) =>
      DurabilityState(
        longSessionExposureHours28d:
            (json['longSessionExposureHours28d'] as num?)?.toDouble() ?? 0.0,
        longSessionCount28d:
            (json['longSessionCount28d'] as num?)?.toInt() ?? 0,
        observations: (json['observations'] as List<dynamic>?)
                ?.map((e) =>
                    DurabilityObservation.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      );
}
