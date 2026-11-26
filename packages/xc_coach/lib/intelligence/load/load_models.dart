/// Datenmodelle für External Load, Internal Load und Perceived Load in GIULIA.
///
/// Hält mechanische Leistung und physiologische Reaktion strikt getrennt.
/// Kein universeller GIULIA-TSS, sondern parallele Lastachsen mit eigener
/// Konfidenz und Provenienz.
library;

import '../../domain/xc_modality.dart';

/// Semantische Klassifikation eines Kalendertags im Belastungstracking.
enum DayClassification {
  /// Bestätigter Ruhetag (geplant oder vom Athleten bestätigt).
  /// Bewirkt mathematisch sauberes exponentielles Abklingen (Decay).
  confirmedRestDay('confirmed_rest_day', 'Bestätigter Ruhetag'),

  /// Tag mit mindestens einer beobachteten und erfassten Trainingseinheit.
  observedTrainingDay('observed_training_day', 'Beobachteter Trainingstag'),

  /// Tag ohne Daten und ohne Bestätigung (z. B. fehlender Sync / Tracker vergessen).
  /// WICHTIG: Darf die Belastungskurve NICHT stillschweigend als 0-Belastung abklingen lassen!
  unknownDay('unknown_day', 'Unbekannter Tag / Datenlücke');

  const DayClassification(this.key, this.label);
  final String key;
  final String label;
}

/// Mechanische äußere Belastung (External Load).
///
/// Beschreibt, was der Athlet physikalisch erbracht hat (Arbeit, Leistung, Distanz, Höhenmeter).
/// Wichtig: Die Geschwindigkeit im Outdoor-Langlauf ist massiv von Schnee, Temperatur, Wachs,
/// Glide, Wind und Gelände abhängig und darf nicht als direktes Fitness- oder Lastmaß interpretiert werden.
///
/// Differenziert strikt zwischen:
/// - sessionAveragePowerWatt (Mittelwert über gesamte Einheit inklusive Pausen)
/// - intervalAveragePowerWatt (Mittelwert während Intervall-Phasen)
/// - workPhaseAveragePowerWatt (Mittelwert während reiner Arbeitsphasen)
/// - workJoule (echte integrierte mechanische Arbeit aus Zügen/Samples, niemals aus Intervallpower extrapoliert!)
class ExternalLoad {
  const ExternalLoad({
    required this.durationSeconds,
    this.workJoule,
    double? sessionAveragePowerWatt,
    double? averagePowerWatt,
    this.intervalAveragePowerWatt,
    this.workPhaseAveragePowerWatt,
    this.peakPowerWatt,
    this.normalizedPowerWatt,
    this.distanceMetres,
    this.elevationGainMetres,
    this.strokeCount,
    this.strokeRatePerMinute,
    this.leftRightSymmetryPercent,
    this.confidence,
    this.provenance = 'unspecified',
  }) : sessionAveragePowerWatt = sessionAveragePowerWatt ?? averagePowerWatt;

  final int durationSeconds;

  /// Echte integrierte physikalische Arbeit in Joule (aus Zügen/Sensorsamples).
  /// Niemals durch Hochrechnung einer Intervall-Leistung über die Gesamtdauer schätzen!
  final double? workJoule;

  /// Mittlere Leistung über die gesamte Trainingsdauer.
  final double? sessionAveragePowerWatt;

  /// Mittlere Leistung während spezifischer Intervallphasen.
  final double? intervalAveragePowerWatt;

  /// Mittlere Leistung während reiner Arbeitsphasen.
  final double? workPhaseAveragePowerWatt;

  final double? peakPowerWatt;
  final double? normalizedPowerWatt;
  final double? distanceMetres;
  final double? elevationGainMetres;
  final int? strokeCount;
  final double? strokeRatePerMinute;
  final double? leftRightSymmetryPercent;
  final double? confidence;
  final String provenance;

  /// Alias für Rückwärtskompatibilität: liefert sessionAveragePowerWatt.
  double? get averagePowerWatt => sessionAveragePowerWatt;

  bool get hasPower =>
      sessionAveragePowerWatt != null && sessionAveragePowerWatt! > 0;
  bool get hasWork => workJoule != null && workJoule! > 0;
  bool get hasDistance => distanceMetres != null && distanceMetres! > 0;
  double get durationMinutes => durationSeconds / 60.0;
  double? get distanceKm =>
      distanceMetres != null ? distanceMetres! / 1000.0 : null;
  double? get workKiloJoule => workJoule != null ? workJoule! / 1000.0 : null;

  Map<String, dynamic> toJson() => {
    'durationSeconds': durationSeconds,
    if (workJoule != null) 'workJoule': workJoule,
    if (sessionAveragePowerWatt != null)
      'sessionAveragePowerWatt': sessionAveragePowerWatt,
    if (sessionAveragePowerWatt != null)
      'averagePowerWatt': sessionAveragePowerWatt,
    if (intervalAveragePowerWatt != null)
      'intervalAveragePowerWatt': intervalAveragePowerWatt,
    if (workPhaseAveragePowerWatt != null)
      'workPhaseAveragePowerWatt': workPhaseAveragePowerWatt,
    if (peakPowerWatt != null) 'peakPowerWatt': peakPowerWatt,
    if (normalizedPowerWatt != null) 'normalizedPowerWatt': normalizedPowerWatt,
    if (distanceMetres != null) 'distanceMetres': distanceMetres,
    if (elevationGainMetres != null) 'elevationGainMetres': elevationGainMetres,
    if (strokeCount != null) 'strokeCount': strokeCount,
    if (strokeRatePerMinute != null) 'strokeRatePerMinute': strokeRatePerMinute,
    if (leftRightSymmetryPercent != null)
      'leftRightSymmetryPercent': leftRightSymmetryPercent,
    if (confidence != null) 'confidence': confidence,
    'provenance': provenance,
  };

  factory ExternalLoad.fromJson(Map<String, dynamic> json) => ExternalLoad(
    durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
    workJoule: (json['workJoule'] as num?)?.toDouble(),
    sessionAveragePowerWatt:
        (json['sessionAveragePowerWatt'] as num?)?.toDouble() ??
        (json['averagePowerWatt'] as num?)?.toDouble(),
    intervalAveragePowerWatt:
        (json['intervalAveragePowerWatt'] as num?)?.toDouble(),
    workPhaseAveragePowerWatt:
        (json['workPhaseAveragePowerWatt'] as num?)?.toDouble(),
    peakPowerWatt: (json['peakPowerWatt'] as num?)?.toDouble(),
    normalizedPowerWatt: (json['normalizedPowerWatt'] as num?)?.toDouble(),
    distanceMetres: (json['distanceMetres'] as num?)?.toDouble(),
    elevationGainMetres: (json['elevationGainMetres'] as num?)?.toDouble(),
    strokeCount: (json['strokeCount'] as num?)?.toInt(),
    strokeRatePerMinute: (json['strokeRatePerMinute'] as num?)?.toDouble(),
    leftRightSymmetryPercent:
        (json['leftRightSymmetryPercent'] as num?)?.toDouble(),
    confidence: (json['confidence'] as num?)?.toDouble(),
    provenance: (json['provenance'] ?? 'unspecified').toString(),
  );
}

/// Physiologische innere Beanspruchung (Internal Load).
///
/// Beschreibt, wie das kardiovaskuläre und metabolische System auf die Belastung
/// reagiert hat.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE EINORDNUNG:
/// - Banister TRIMP ist ein geschätzter Proxy (estimatedInternalLoad), keine direkte
///   kardiovaskuläre Messung.
/// - Edwards Zonal TRIMP ist ein noch gröberer Zonen-Proxy (diskrete Zonengewichte 1-5).
/// - Lucia Zonal TRIMP stützt sich auf VT1/VT2.
/// - Beide Verfahren stellen mathematische Modell-Schätzungen dar und keine biologischen Absoluten.
class InternalLoad {
  const InternalLoad({
    double? trimpBanister,
    double? estimatedTrimpBanister,
    double? trimpEdwards,
    double? estimatedTrimpEdwards,
    double? trimpLucia,
    double? estimatedTrimpLucia,
    this.averageHeartRateBpm,
    this.peakHeartRateBpm,
    this.timeInHrZonesSeconds = const {},
    this.confidence,
    this.provenance = 'unspecified',
  })  : trimpBanister = estimatedTrimpBanister ?? trimpBanister,
        trimpEdwards = estimatedTrimpEdwards ?? trimpEdwards,
        trimpLucia = estimatedTrimpLucia ?? trimpLucia;

  /// Geschätzter Banister TRIMP (Banister 1991, exponentiell nach HR-Reserve gewichtet).
  /// Rechnerischer Proxy, keine direkte physiologische Messgröße!
  final double? trimpBanister;

  /// Geschätzter Edwards Zonal TRIMP (Edwards 1993, 5 Zonen mit Gewichten 1 bis 5).
  /// Grober Stufenproxy für akkumulierte Zonenzeit.
  final double? trimpEdwards;

  /// Geschätzter Lucia Zonal TRIMP (Lucia et al. 2000, 3 Zonen um VT1/VT2).
  final double? trimpLucia;

  final double? averageHeartRateBpm;
  final int? peakHeartRateBpm;
  final Map<String, int> timeInHrZonesSeconds;
  final double? confidence;
  final String provenance;

  bool get hasHeartRate => averageHeartRateBpm != null && averageHeartRateBpm! > 0;
  bool get hasTrimp => trimpBanister != null || trimpEdwards != null;

  Map<String, dynamic> toJson() => {
    if (trimpBanister != null) 'trimpBanister': trimpBanister,
    if (trimpEdwards != null) 'trimpEdwards': trimpEdwards,
    if (trimpLucia != null) 'trimpLucia': trimpLucia,
    if (averageHeartRateBpm != null) 'averageHeartRateBpm': averageHeartRateBpm,
    if (peakHeartRateBpm != null) 'peakHeartRateBpm': peakHeartRateBpm,
    if (timeInHrZonesSeconds.isNotEmpty)
      'timeInHrZonesSeconds': timeInHrZonesSeconds,
    if (confidence != null) 'confidence': confidence,
    'provenance': provenance,
  };

  factory InternalLoad.fromJson(Map<String, dynamic> json) => InternalLoad(
    trimpBanister: (json['trimpBanister'] as num?)?.toDouble(),
    trimpEdwards: (json['trimpEdwards'] as num?)?.toDouble(),
    trimpLucia: (json['trimpLucia'] as num?)?.toDouble(),
    averageHeartRateBpm: (json['averageHeartRateBpm'] as num?)?.toDouble(),
    peakHeartRateBpm: (json['peakHeartRateBpm'] as num?)?.toInt(),
    timeInHrZonesSeconds:
        (json['timeInHrZonesSeconds'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, (v as num).toInt()),
            ) ??
            const {},
    confidence: (json['confidence'] as num?)?.toDouble(),
    provenance: (json['provenance'] ?? 'unspecified').toString(),
  );
}

/// Subjektiv empfundene Belastung (Perceived Load).
///
/// session-RPE Methode (Foster et al. 2001): sRPE = RPE (Borg CR-10) * Dauer (Minuten).
class PerceivedLoad {
  const PerceivedLoad({
    this.rpe,
    this.durationMinutes,
    this.srpeLoad,
    this.confidence,
  });

  /// Borg CR-10 RPE Skala (1-10).
  final double? rpe;
  final double? durationMinutes;

  /// session-RPE Load = RPE * Dauer in Minuten.
  final double? srpeLoad;
  final double? confidence;

  bool get hasSrpe => srpeLoad != null && srpeLoad! > 0;

  Map<String, dynamic> toJson() => {
    if (rpe != null) 'rpe': rpe,
    if (durationMinutes != null) 'durationMinutes': durationMinutes,
    if (srpeLoad != null) 'srpeLoad': srpeLoad,
    if (confidence != null) 'confidence': confidence,
  };

  factory PerceivedLoad.fromJson(Map<String, dynamic> json) => PerceivedLoad(
    rpe: (json['rpe'] as num?)?.toDouble(),
    durationMinutes: (json['durationMinutes'] as num?)?.toDouble(),
    srpeLoad: (json['srpeLoad'] as num?)?.toDouble(),
    confidence: (json['confidence'] as num?)?.toDouble(),
  );
}

/// Die ganzheitliche, mehrdimensionale Belastungsbeschreibung einer Einheit.
class SessionLoad {
  const SessionLoad({
    required this.sessionId,
    required this.athleteId,
    required this.modality,
    required this.technique,
    required this.startedAtUtcUs,
    required this.durationSeconds,
    required this.external,
    required this.internal,
    required this.perceived,
    required this.confidence,
    required this.provenance,
  });

  final String sessionId;
  final String athleteId;
  final XcModality modality;
  final XcTechnique technique;
  final int startedAtUtcUs;
  final int durationSeconds;

  final ExternalLoad external;
  final InternalLoad internal;
  final PerceivedLoad perceived;

  final double confidence;
  final String provenance;

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'athleteId': athleteId,
    'modality': modality.key,
    'technique': technique.key,
    'startedAtUtcUs': startedAtUtcUs,
    'durationSeconds': durationSeconds,
    'external': external.toJson(),
    'internal': internal.toJson(),
    'perceived': perceived.toJson(),
    'confidence': confidence,
    'provenance': provenance,
  };

  factory SessionLoad.fromJson(Map<String, dynamic> json) => SessionLoad(
    sessionId: (json['sessionId'] ?? '').toString(),
    athleteId: (json['athleteId'] ?? '').toString(),
    modality: XcModality.values.firstWhere(
      (m) => m.key == json['modality'],
      orElse: () => XcModality.unknown,
    ),
    technique: XcTechnique.values.firstWhere(
      (t) => t.key == json['technique'],
      orElse: () => XcTechnique.unknown,
    ),
    startedAtUtcUs: (json['startedAtUtcUs'] as num?)?.toInt() ?? 0,
    durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
    external: json['external'] != null
        ? ExternalLoad.fromJson(json['external'] as Map<String, dynamic>)
        : const ExternalLoad(durationSeconds: 0),
    internal: json['internal'] != null
        ? InternalLoad.fromJson(json['internal'] as Map<String, dynamic>)
        : const InternalLoad(),
    perceived: json['perceived'] != null
        ? PerceivedLoad.fromJson(json['perceived'] as Map<String, dynamic>)
        : const PerceivedLoad(),
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0.8,
    provenance: (json['provenance'] ?? 'unspecified').toString(),
  );
}

/// Typ einer beobachtbaren Evidenz für Ermüdungswiderstand / Durability.
enum DurabilityObservationType {
  hrExternalDecoupling('hr_external_decoupling', 'Physiologische Entkopplung (EF / PW:HR Drift)'),
  powerPaceDegradation('power_pace_degradation', 'Leistungsabfall bei gleicher Geschwindigkeit/Pace'),
  ercolinaPowerRetention('ercolina_power_retention', 'Ercolina Leistungserhalt vor/nach Vorbelastung'),
  strokeDegradation('stroke_degradation', 'Veränderung der Zugmechanik / Frequenz'),
  subjectiveFatigueDrift('subjective_fatigue_drift', 'Überproportionaler RPE-Anstieg');

  const DurabilityObservationType(this.key, this.label);
  final String key;
  final String label;
}

/// Strukturierte Einzelbeobachtung zu Fatigue Resistance / Durability.
///
/// Hält Messbedingungen und Konfidenz fest, ohne voreilig einen aggregierten Einheitswert zu erzwingen.
class DurabilityObservation {
  const DurabilityObservation({
    required this.sessionId,
    required this.modality,
    required this.durationSeconds,
    required this.type,
    this.value,
    this.unit,
    this.conditions,
    required this.confidence,
    required this.provenance,
  });

  final String sessionId;
  final XcModality modality;
  final int durationSeconds;
  final DurabilityObservationType type;
  final double? value;
  final String? unit;
  final String? conditions;
  final double confidence;
  final String provenance;

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'modality': modality.key,
    'durationSeconds': durationSeconds,
    'type': type.key,
    if (value != null) 'value': value,
    if (unit != null) 'unit': unit,
    if (conditions != null) 'conditions': conditions,
    'confidence': confidence,
    'provenance': provenance,
  };

  factory DurabilityObservation.fromJson(Map<String, dynamic> json) =>
      DurabilityObservation(
        sessionId: (json['sessionId'] ?? '').toString(),
        modality: XcModality.values.firstWhere(
          (m) => m.key == json['modality'],
          orElse: () => XcModality.unknown,
        ),
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
        type: DurabilityObservationType.values.firstWhere(
          (t) => t.key == json['type'],
          orElse: () => DurabilityObservationType.hrExternalDecoupling,
        ),
        value: (json['value'] as num?)?.toDouble(),
        unit: json['unit']?.toString(),
        conditions: json['conditions']?.toString(),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
        provenance: (json['provenance'] ?? 'unspecified').toString(),
      );
}
