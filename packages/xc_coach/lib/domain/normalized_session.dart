/// Kanonisches Aktivitätsmodell für GIULIA.
///
/// Vereinheitlicht Ercolina (First-Party), Strava, Garmin und manuelle Einheiten.
/// Hält mechanische Arbeit (External Load) und physiologische Reaktion (Internal Load)
/// streng getrennt und behält Herkunft, Datenqualität und Konfidenz bei.
library;

import 'xc_modality.dart';

enum NormalizedSessionSource {
  ercolina('ercolina', 'Ercolina Gerät'),
  strava('strava', 'Strava Sync'),
  garmin('garmin', 'Garmin Connect / FIT'),
  manual('manual', 'Manuelle Erfassung');

  const NormalizedSessionSource(this.key, this.label);
  final String key;
  final String label;
}

class SessionDataQuality {
  const SessionDataQuality({
    required this.confidence,
    this.externalConfidence,
    this.internalConfidence,
    this.calibrationConfidence,
    this.hasHeartRate = false,
    this.hasPower = false,
    this.hasCadenceOrStroke = false,
    this.hasGps = false,
    this.hasDropouts = false,
    this.warnings = const [],
  });

  /// Gesamt-Konfidenzwert der Session von 0.0 (sehr unsicher / Schätzung) bis 1.0 (direkt gemessen).
  final double confidence;

  /// Differenzierte Konfidenzen auf Metrik-/Gruppenebene:
  final double? externalConfidence;
  final double? internalConfidence;
  final double? calibrationConfidence;

  final bool hasHeartRate;
  final bool hasPower;
  final bool hasCadenceOrStroke;
  final bool hasGps;
  final bool hasDropouts;
  final List<String> warnings;

  Map<String, dynamic> toJson() => {
    'confidence': confidence,
    if (externalConfidence != null) 'externalConfidence': externalConfidence,
    if (internalConfidence != null) 'internalConfidence': internalConfidence,
    if (calibrationConfidence != null) 'calibrationConfidence': calibrationConfidence,
    'hasHeartRate': hasHeartRate,
    'hasPower': hasPower,
    'hasCadenceOrStroke': hasCadenceOrStroke,
    'hasGps': hasGps,
    'hasDropouts': hasDropouts,
    'warnings': warnings,
  };

  factory SessionDataQuality.fromJson(Map<String, dynamic> json) =>
      SessionDataQuality(
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.8,
        externalConfidence: (json['externalConfidence'] as num?)?.toDouble(),
        internalConfidence: (json['internalConfidence'] as num?)?.toDouble(),
        calibrationConfidence: (json['calibrationConfidence'] as num?)?.toDouble(),
        hasHeartRate: json['hasHeartRate'] as bool? ?? false,
        hasPower: json['hasPower'] as bool? ?? false,
        hasCadenceOrStroke: json['hasCadenceOrStroke'] as bool? ?? false,
        hasGps: json['hasGps'] as bool? ?? false,
        hasDropouts: json['hasDropouts'] as bool? ?? false,
        warnings: (json['warnings'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}


/// Mechanisch erbrachte Leistung (External Load).
///
/// Differenziert zwischen Einheiten-Mittelwert, Intervall-Mittelwert und Arbeitsphasen-Mittelwert.
/// Total Work (Joule/kJ) muss immer aus Zügen/Samples integriert sein, niemals
/// aus Intervall-Power über die Gesamtzeit hochgerechnet.
class SessionExternalMetrics {
  const SessionExternalMetrics({
    double? sessionAveragePowerWatt,
    double? averagePowerWatt,
    this.intervalAveragePowerWatt,
    this.workPhaseAveragePowerWatt,
    this.peakPowerWatt,
    this.normalizedPowerWatt,
    this.workJoule,
    this.strokeOrCadenceRate,
    this.strokeCount,
    this.leftRightSymmetryPercent,
    this.classicLeftWorkPercent,
  }) : sessionAveragePowerWatt = sessionAveragePowerWatt ?? averagePowerWatt;

  /// Mittlere mechanische Leistung über die gesamte Trainingszeit (inkl. Pausen/Ausrollen).
  final double? sessionAveragePowerWatt;

  /// Mittlere Leistung während spezifischer Intervallabschnitte.
  final double? intervalAveragePowerWatt;

  /// Mittlere Leistung während reiner Arbeitsphasen (ohne Serienpausen).
  final double? workPhaseAveragePowerWatt;

  final double? peakPowerWatt;
  final double? normalizedPowerWatt;
  final double? workJoule;

  /// Alias für Rückwärtskompatibilität: liefert sessionAveragePowerWatt.
  double? get averagePowerWatt => sessionAveragePowerWatt;

  /// Kadenz (Rad/Lauf) oder Zugfrequenz (Ercolina/Ski in Züge/min).
  final double? strokeOrCadenceRate;
  final int? strokeCount;

  /// Symmetrie links/rechts (z. B. auf der Ercolina in Prozent).
  final double? leftRightSymmetryPercent;
  final double? classicLeftWorkPercent;

  bool get hasPower => sessionAveragePowerWatt != null && sessionAveragePowerWatt! > 0;
  bool get hasWork => workJoule != null && workJoule! > 0;

  Map<String, dynamic> toJson() => {
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
    if (workJoule != null) 'workJoule': workJoule,
    if (strokeOrCadenceRate != null) 'strokeOrCadenceRate': strokeOrCadenceRate,
    if (strokeCount != null) 'strokeCount': strokeCount,
    if (leftRightSymmetryPercent != null)
      'leftRightSymmetryPercent': leftRightSymmetryPercent,
    if (classicLeftWorkPercent != null)
      'classicLeftWorkPercent': classicLeftWorkPercent,
  };

  factory SessionExternalMetrics.fromJson(Map<String, dynamic> json) =>
      SessionExternalMetrics(
        sessionAveragePowerWatt:
            (json['sessionAveragePowerWatt'] as num?)?.toDouble() ??
            (json['averagePowerWatt'] as num?)?.toDouble(),
        intervalAveragePowerWatt:
            (json['intervalAveragePowerWatt'] as num?)?.toDouble(),
        workPhaseAveragePowerWatt:
            (json['workPhaseAveragePowerWatt'] as num?)?.toDouble(),
        peakPowerWatt: (json['peakPowerWatt'] as num?)?.toDouble(),
        normalizedPowerWatt: (json['normalizedPowerWatt'] as num?)?.toDouble(),
        workJoule: (json['workJoule'] as num?)?.toDouble(),
        strokeOrCadenceRate: (json['strokeOrCadenceRate'] as num?)?.toDouble(),
        strokeCount: (json['strokeCount'] as num?)?.toInt(),
        leftRightSymmetryPercent:
            (json['leftRightSymmetryPercent'] as num?)?.toDouble(),
        classicLeftWorkPercent:
            (json['classicLeftWorkPercent'] as num?)?.toDouble(),
      );
}

/// Physiologische Reaktion des Athleten (Internal Load).
class SessionInternalMetrics {
  const SessionInternalMetrics({
    this.averageHeartRateBpm,
    this.peakHeartRateBpm,
    this.rpe,
    this.peakLactateMmolPerLitre,
    this.timeInHrZonesSeconds = const {},
  });

  final double? averageHeartRateBpm;
  final int? peakHeartRateBpm;

  /// Subjektives Belastungsempfinden (Borg 6-20 oder 1-10 Skala).
  final double? rpe;

  /// Höchster gemessener Laktatwert während oder nach der Belastung.
  final double? peakLactateMmolPerLitre;

  /// Verweildauer in den Herzfrequenzzonen (Sekunden).
  final Map<String, int> timeInHrZonesSeconds;

  bool get hasHeartRate =>
      averageHeartRateBpm != null && averageHeartRateBpm! > 0;
  bool get hasLactate =>
      peakLactateMmolPerLitre != null && peakLactateMmolPerLitre! > 0;

  SessionInternalMetrics copyWith({
    double? averageHeartRateBpm,
    int? peakHeartRateBpm,
    double? rpe,
    double? peakLactateMmolPerLitre,
    Map<String, int>? timeInHrZonesSeconds,
  }) => SessionInternalMetrics(
    averageHeartRateBpm: averageHeartRateBpm ?? this.averageHeartRateBpm,
    peakHeartRateBpm: peakHeartRateBpm ?? this.peakHeartRateBpm,
    rpe: rpe ?? this.rpe,
    peakLactateMmolPerLitre: peakLactateMmolPerLitre ?? this.peakLactateMmolPerLitre,
    timeInHrZonesSeconds: timeInHrZonesSeconds ?? this.timeInHrZonesSeconds,
  );

  Map<String, dynamic> toJson() => {
    if (averageHeartRateBpm != null) 'averageHeartRateBpm': averageHeartRateBpm,
    if (peakHeartRateBpm != null) 'peakHeartRateBpm': peakHeartRateBpm,
    if (rpe != null) 'rpe': rpe,
    if (peakLactateMmolPerLitre != null)
      'peakLactateMmolPerLitre': peakLactateMmolPerLitre,
    if (timeInHrZonesSeconds.isNotEmpty)
      'timeInHrZonesSeconds': timeInHrZonesSeconds,
  };

  factory SessionInternalMetrics.fromJson(Map<String, dynamic> json) =>
      SessionInternalMetrics(
        averageHeartRateBpm: (json['averageHeartRateBpm'] as num?)?.toDouble(),
        peakHeartRateBpm: (json['peakHeartRateBpm'] as num?)?.toInt(),
        rpe: (json['rpe'] as num?)?.toDouble(),
        peakLactateMmolPerLitre:
            (json['peakLactateMmolPerLitre'] as num?)?.toDouble(),
        timeInHrZonesSeconds:
            (json['timeInHrZonesSeconds'] as Map<String, dynamic>?)?.map(
                  (k, v) => MapEntry(k, (v as num).toInt()),
                ) ??
                const {},
      );
}

/// Die kanonische, quellenunabhängige Repräsentation einer Trainingseinheit.
class NormalizedSession {
  const NormalizedSession({
    required this.id,
    required this.athleteId,
    required this.source,
    required this.sourceId,
    required this.startedAtUtcUs,
    required this.durationSeconds,
    required this.movingTimeSeconds,
    required this.modality,
    this.technique = XcTechnique.unknown,
    this.classificationProvenance = ClassificationProvenance.unknown,
    required this.isIndoor,
    required this.title,
    this.distanceMetres,
    this.elevationGainMetres,
    this.elevationLossMetres,
    this.externalMetrics = const SessionExternalMetrics(),
    this.internalMetrics = const SessionInternalMetrics(),
    this.dataQuality = const SessionDataQuality(confidence: 0.8),
    this.rawMetadata = const {},
  });

  final String id;
  final String athleteId;
  final NormalizedSessionSource source;
  final String sourceId;
  final int startedAtUtcUs;
  final int durationSeconds;
  final int movingTimeSeconds;
  final XcModality modality;
  final XcTechnique technique;
  final ClassificationProvenance classificationProvenance;
  final bool isIndoor;
  final String title;

  final double? distanceMetres;
  final double? elevationGainMetres;
  final double? elevationLossMetres;

  final SessionExternalMetrics externalMetrics;
  final SessionInternalMetrics internalMetrics;
  final SessionDataQuality dataQuality;
  final Map<String, dynamic> rawMetadata;

  /// Preserved archive markers still disqualify an accidentally relabelled row.
  bool get eligibleForCoach => source != NormalizedSessionSource.strava &&
      !id.startsWith('strava_') && !rawMetadata.containsKey('sufferScore') &&
      rawMetadata['originalProvider'] != 'strava';


  double? get distanceKm =>
      distanceMetres == null ? null : distanceMetres! / 1000.0;
  double get durationMinutes => durationSeconds / 60.0;
  double get movingMinutes => movingTimeSeconds / 60.0;

  DateTime get startedAtUtc =>
      DateTime.fromMicrosecondsSinceEpoch(startedAtUtcUs, isUtc: true);
  DateTime get startedAt => startedAtUtc;

  DateTime get startedAtLocal =>
      DateTime.fromMicrosecondsSinceEpoch(startedAtUtcUs, isUtc: true).toLocal();

  double? get averagePowerWatt => externalMetrics.averagePowerWatt;
  double? get rpe => internalMetrics.rpe;

  NormalizedSession copyWith({
    String? id,
    String? athleteId,
    NormalizedSessionSource? source,
    String? sourceId,
    int? startedAtUtcUs,
    int? durationSeconds,
    int? movingTimeSeconds,
    XcModality? modality,
    XcTechnique? technique,
    ClassificationProvenance? classificationProvenance,
    bool? isIndoor,
    String? title,
    double? distanceMetres,
    double? elevationGainMetres,
    double? elevationLossMetres,
    SessionExternalMetrics? externalMetrics,
    SessionInternalMetrics? internalMetrics,
    SessionDataQuality? dataQuality,
    Map<String, dynamic>? rawMetadata,
    String? athleteNotes,
  }) => NormalizedSession(
    id: id ?? this.id,
    athleteId: athleteId ?? this.athleteId,
    source: source ?? this.source,
    sourceId: sourceId ?? this.sourceId,
    startedAtUtcUs: startedAtUtcUs ?? this.startedAtUtcUs,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    movingTimeSeconds: movingTimeSeconds ?? this.movingTimeSeconds,
    modality: modality ?? this.modality,
    technique: technique ?? this.technique,
    classificationProvenance: classificationProvenance ?? this.classificationProvenance,
    isIndoor: isIndoor ?? this.isIndoor,
    title: title ?? this.title,
    distanceMetres: distanceMetres ?? this.distanceMetres,
    elevationGainMetres: elevationGainMetres ?? this.elevationGainMetres,
    elevationLossMetres: elevationLossMetres ?? this.elevationLossMetres,
    externalMetrics: externalMetrics ?? this.externalMetrics,
    internalMetrics: internalMetrics ?? this.internalMetrics,
    dataQuality: dataQuality ?? this.dataQuality,
    rawMetadata: rawMetadata != null || athleteNotes != null || !eligibleForCoach
        ? {
            ...this.rawMetadata,
            if (rawMetadata != null) ...rawMetadata,
            if (athleteNotes != null) 'athleteNotes': athleteNotes,
            if (!eligibleForCoach) 'originalProvider': 'strava',
          }
        : this.rawMetadata,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'athleteId': athleteId,
    'source': source.key,
    'sourceId': sourceId,
    'startedAtUtcUs': startedAtUtcUs,
    'durationSeconds': durationSeconds,
    'movingTimeSeconds': movingTimeSeconds,
    'modality': modality.key,
    'technique': technique.key,
    'classificationProvenance': classificationProvenance.key,
    'isIndoor': isIndoor,
    'title': title,
    if (distanceMetres != null) 'distanceMetres': distanceMetres,
    if (elevationGainMetres != null) 'elevationGainMetres': elevationGainMetres,
    if (elevationLossMetres != null) 'elevationLossMetres': elevationLossMetres,
    'externalMetrics': externalMetrics.toJson(),
    'internalMetrics': internalMetrics.toJson(),
    'dataQuality': dataQuality.toJson(),
    if (rawMetadata.isNotEmpty) 'rawMetadata': rawMetadata,
  };

  factory NormalizedSession.fromJson(Map<String, dynamic> json) =>
      NormalizedSession(
        id: (json['id'] ?? '').toString(),
        athleteId: (json['athleteId'] ?? '').toString(),
        source: NormalizedSessionSource.values.firstWhere(
          (s) => s.key == json['source'],
          orElse: () => NormalizedSessionSource.manual,
        ),
        sourceId: (json['sourceId'] ?? '').toString(),
        startedAtUtcUs: (json['startedAtUtcUs'] as num?)?.toInt() ?? 0,
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
        movingTimeSeconds: (json['movingTimeSeconds'] as num?)?.toInt() ?? 0,
        modality: XcModality.values.firstWhere(
          (m) => m.key == json['modality'],
          orElse: () => XcModality.unknown,
        ),
        technique: XcTechnique.values.firstWhere(
          (t) => t.key == json['technique'],
          orElse: () => XcTechnique.unknown,
        ),
        classificationProvenance: ClassificationProvenance.values.firstWhere(
          (p) => p.key == json['classificationProvenance'],
          orElse: () => ClassificationProvenance.unknown,
        ),
        isIndoor: json['isIndoor'] as bool? ?? false,

        title: (json['title'] ?? 'Trainingseinheit').toString(),
        distanceMetres: (json['distanceMetres'] as num?)?.toDouble(),
        elevationGainMetres: (json['elevationGainMetres'] as num?)?.toDouble(),
        elevationLossMetres: (json['elevationLossMetres'] as num?)?.toDouble(),
        externalMetrics: json['externalMetrics'] != null
            ? SessionExternalMetrics.fromJson(
                json['externalMetrics'] as Map<String, dynamic>,
              )
            : const SessionExternalMetrics(),
        internalMetrics: json['internalMetrics'] != null
            ? SessionInternalMetrics.fromJson(
                json['internalMetrics'] as Map<String, dynamic>,
              )
            : const SessionInternalMetrics(),
        dataQuality: json['dataQuality'] != null
            ? SessionDataQuality.fromJson(
                json['dataQuality'] as Map<String, dynamic>,
              )
            : const SessionDataQuality(confidence: 0.8),
        rawMetadata: (json['rawMetadata'] as Map<String, dynamic>?) ?? const {},
      );
}

