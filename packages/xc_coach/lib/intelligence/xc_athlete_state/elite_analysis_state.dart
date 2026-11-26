/// Longitudinale, evidenzgebundene Vollauswertung eines Langlauf-Athleten.
///
/// Der Zustand enthält bewusst keinen globalen Fitness- oder Readiness-Score.
/// Jede Zahl bleibt in ihrer physikalischen Einheit, in ihrem Zeitfenster und
/// bei ihrer Quelle. Fehlende Hochleistungsdaten werden als Lücke ausgewiesen.
library;

import '../../domain/xc_modality.dart';

class AthletePhysiologyState {
  const AthletePhysiologyState({
    this.bodyMassKg,
    this.maxHeartRateBpm,
    this.restingHeartRateBpm,
    this.sex,
  });

  final double? bodyMassKg;
  final int? maxHeartRateBpm;
  final int? restingHeartRateBpm;
  final String? sex;

  bool get hasHeartRateReserve =>
      maxHeartRateBpm != null &&
      restingHeartRateBpm != null &&
      maxHeartRateBpm! > restingHeartRateBpm!;

  bool get isFemale {
    final normalized = sex?.trim().toLowerCase();
    return normalized == 'w' ||
        normalized == 'f' ||
        normalized == 'female' ||
        normalized == 'weiblich';
  }

  List<String> get missing => [
    if (bodyMassKg == null) 'aktuelles Körpergewicht',
    if (maxHeartRateBpm == null) 'individuelle maximale Herzfrequenz',
    if (restingHeartRateBpm == null) 'individuelle Ruheherzfrequenz',
  ];

  Map<String, dynamic> toJson() => {
    if (bodyMassKg != null) 'bodyMassKg': bodyMassKg,
    if (maxHeartRateBpm != null) 'maxHeartRateBpm': maxHeartRateBpm,
    if (restingHeartRateBpm != null) 'restingHeartRateBpm': restingHeartRateBpm,
    if (sex != null) 'sex': sex,
  };

  factory AthletePhysiologyState.fromJson(Map<String, dynamic> json) =>
      AthletePhysiologyState(
        bodyMassKg: (json['bodyMassKg'] as num?)?.toDouble(),
        maxHeartRateBpm: (json['maxHeartRateBpm'] as num?)?.round(),
        restingHeartRateBpm: (json['restingHeartRateBpm'] as num?)?.round(),
        sex: json['sex']?.toString(),
      );
}

class TrainingWindowAnalysis {
  const TrainingWindowAnalysis({
    required this.key,
    required this.label,
    required this.periodDays,
    required this.sessionCount,
    required this.activeDays,
    required this.activeWeeks,
    required this.durationSeconds,
    required this.distanceMetres,
    required this.elevationGainMetres,
    required this.workJoule,
    required this.modalityDurationSeconds,
    required this.hrZoneSeconds,
    required this.sessionsWithHeartRate,
    required this.sessionsWithHeartRateZones,
    required this.sessionsWithDerivedHeartRateZones,
    required this.sessionsWithPower,
    required this.sessionsWithRpe,
    required this.longestGapDays,
  });

  final String key;
  final String label;
  final int periodDays;
  final int sessionCount;
  final int activeDays;
  final int activeWeeks;
  final int durationSeconds;
  final double distanceMetres;
  final double elevationGainMetres;
  final double workJoule;
  final Map<XcModality, int> modalityDurationSeconds;
  final Map<String, int> hrZoneSeconds;
  final int sessionsWithHeartRate;
  final int sessionsWithHeartRateZones;

  /// Anzahl Einheiten, deren Zonen aus einem zeitaufgelösten HF-Stream und
  /// der individuellen HFmax berechnet wurden. Quell-Zonen werden bevorzugt.
  final int sessionsWithDerivedHeartRateZones;
  final int sessionsWithPower;
  final int sessionsWithRpe;
  final double longestGapDays;

  double get durationHours => durationSeconds / 3600.0;
  double get distanceKm => distanceMetres / 1000.0;
  double get workKiloJoule => workJoule / 1000.0;
  int get classifiedHrZoneSeconds =>
      hrZoneSeconds.values.fold<int>(0, (sum, value) => sum + value);
  double get hrZoneCoverage => durationSeconds <= 0
      ? 0
      : (classifiedHrZoneSeconds / durationSeconds).clamp(0.0, 1.0);
  double get heartRateSessionCoverage =>
      sessionCount == 0 ? 0 : sessionsWithHeartRate / sessionCount;
  double get powerSessionCoverage =>
      sessionCount == 0 ? 0 : sessionsWithPower / sessionCount;
  double get rpeSessionCoverage =>
      sessionCount == 0 ? 0 : sessionsWithRpe / sessionCount;

  int durationFor(XcModality modality) =>
      modalityDurationSeconds[modality] ?? 0;

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'periodDays': periodDays,
    'sessionCount': sessionCount,
    'activeDays': activeDays,
    'activeWeeks': activeWeeks,
    'durationSeconds': durationSeconds,
    'distanceMetres': distanceMetres,
    'elevationGainMetres': elevationGainMetres,
    'workJoule': workJoule,
    'modalityDurationSeconds': modalityDurationSeconds.map(
      (key, value) => MapEntry(key.key, value),
    ),
    'hrZoneSeconds': hrZoneSeconds,
    'sessionsWithHeartRate': sessionsWithHeartRate,
    'sessionsWithHeartRateZones': sessionsWithHeartRateZones,
    'sessionsWithDerivedHeartRateZones': sessionsWithDerivedHeartRateZones,
    'sessionsWithPower': sessionsWithPower,
    'sessionsWithRpe': sessionsWithRpe,
    'longestGapDays': longestGapDays,
  };

  factory TrainingWindowAnalysis.fromJson(Map<String, dynamic> json) =>
      TrainingWindowAnalysis(
        key: (json['key'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
        periodDays: (json['periodDays'] as num?)?.round() ?? 0,
        sessionCount: (json['sessionCount'] as num?)?.round() ?? 0,
        activeDays: (json['activeDays'] as num?)?.round() ?? 0,
        activeWeeks: (json['activeWeeks'] as num?)?.round() ?? 0,
        durationSeconds: (json['durationSeconds'] as num?)?.round() ?? 0,
        distanceMetres: (json['distanceMetres'] as num?)?.toDouble() ?? 0,
        elevationGainMetres:
            (json['elevationGainMetres'] as num?)?.toDouble() ?? 0,
        workJoule: (json['workJoule'] as num?)?.toDouble() ?? 0,
        modalityDurationSeconds:
            (json['modalityDurationSeconds'] as Map<String, dynamic>?)?.map(
              (key, value) => MapEntry(
                XcModality.values.firstWhere(
                  (modality) => modality.key == key,
                  orElse: () => XcModality.unknown,
                ),
                (value as num).round(),
              ),
            ) ??
            const {},
        hrZoneSeconds:
            (json['hrZoneSeconds'] as Map<String, dynamic>?)?.map(
              (key, value) => MapEntry(key, (value as num).round()),
            ) ??
            const {},
        sessionsWithHeartRate:
            (json['sessionsWithHeartRate'] as num?)?.round() ?? 0,
        sessionsWithHeartRateZones:
            (json['sessionsWithHeartRateZones'] as num?)?.round() ?? 0,
        sessionsWithDerivedHeartRateZones:
            (json['sessionsWithDerivedHeartRateZones'] as num?)?.round() ?? 0,
        sessionsWithPower: (json['sessionsWithPower'] as num?)?.round() ?? 0,
        sessionsWithRpe: (json['sessionsWithRpe'] as num?)?.round() ?? 0,
        longestGapDays: (json['longestGapDays'] as num?)?.toDouble() ?? 0,
      );
}

class MonthlyTrainingSummary {
  const MonthlyTrainingSummary({
    required this.year,
    required this.month,
    required this.sessionCount,
    required this.durationSeconds,
    required this.distanceMetres,
    required this.elevationGainMetres,
    required this.skiSpecificDurationSeconds,
  });

  final int year;
  final int month;
  final int sessionCount;
  final int durationSeconds;
  final double distanceMetres;
  final double elevationGainMetres;
  final int skiSpecificDurationSeconds;

  DateTime get date => DateTime.utc(year, month);
  double get durationHours => durationSeconds / 3600.0;
  double get skiSpecificHours => skiSpecificDurationSeconds / 3600.0;

  Map<String, dynamic> toJson() => {
    'year': year,
    'month': month,
    'sessionCount': sessionCount,
    'durationSeconds': durationSeconds,
    'distanceMetres': distanceMetres,
    'elevationGainMetres': elevationGainMetres,
    'skiSpecificDurationSeconds': skiSpecificDurationSeconds,
  };

  factory MonthlyTrainingSummary.fromJson(Map<String, dynamic> json) =>
      MonthlyTrainingSummary(
        year: (json['year'] as num).round(),
        month: (json['month'] as num).round(),
        sessionCount: (json['sessionCount'] as num?)?.round() ?? 0,
        durationSeconds: (json['durationSeconds'] as num?)?.round() ?? 0,
        distanceMetres: (json['distanceMetres'] as num?)?.toDouble() ?? 0,
        elevationGainMetres:
            (json['elevationGainMetres'] as num?)?.toDouble() ?? 0,
        skiSpecificDurationSeconds:
            (json['skiSpecificDurationSeconds'] as num?)?.round() ?? 0,
      );
}

class AthleteBestEvidence {
  const AthleteBestEvidence({
    required this.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.achievedAt,
    required this.modality,
    required this.sessionId,
    required this.source,
    this.caveat,
  });

  final String key;
  final String label;
  final double value;
  final String unit;
  final DateTime achievedAt;
  final XcModality modality;
  final String sessionId;
  final String source;
  final String? caveat;

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'value': value,
    'unit': unit,
    'achievedAt': achievedAt.toIso8601String(),
    'modality': modality.key,
    'sessionId': sessionId,
    'source': source,
    if (caveat != null) 'caveat': caveat,
  };

  factory AthleteBestEvidence.fromJson(Map<String, dynamic> json) =>
      AthleteBestEvidence(
        key: (json['key'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
        value: (json['value'] as num).toDouble(),
        unit: (json['unit'] ?? '').toString(),
        achievedAt: DateTime.parse(json['achievedAt'].toString()),
        modality: XcModality.values.firstWhere(
          (modality) => modality.key == json['modality'],
          orElse: () => XcModality.unknown,
        ),
        sessionId: (json['sessionId'] ?? '').toString(),
        source: (json['source'] ?? '').toString(),
        caveat: json['caveat']?.toString(),
      );
}

class EliteAnalysisState {
  const EliteAnalysisState({
    this.physiology = const AthletePhysiologyState(),
    this.historyStart,
    this.historyEnd,
    this.latestGarminSessionId,
    this.windows = const [],
    this.months = const [],
    this.personalBests = const [],
    this.volumeChange28dPercent,
    this.volumeChange90dPercent,
    this.missingEvidence = const [],
  });

  final AthletePhysiologyState physiology;
  final DateTime? historyStart;
  final DateTime? historyEnd;
  final String? latestGarminSessionId;
  final List<TrainingWindowAnalysis> windows;
  final List<MonthlyTrainingSummary> months;
  final List<AthleteBestEvidence> personalBests;
  final double? volumeChange28dPercent;
  final double? volumeChange90dPercent;
  final List<String> missingEvidence;

  TrainingWindowAnalysis? window(String key) =>
      windows.where((window) => window.key == key).firstOrNull;

  TrainingWindowAnalysis? get allTime => window('all');
  bool get hasHistory => (allTime?.sessionCount ?? 0) > 0;

  Map<String, dynamic> toJson() => {
    'physiology': physiology.toJson(),
    if (historyStart != null) 'historyStart': historyStart!.toIso8601String(),
    if (latestGarminSessionId != null) 'latestGarminSessionId': latestGarminSessionId,
    if (historyEnd != null) 'historyEnd': historyEnd!.toIso8601String(),
    'windows': windows.map((window) => window.toJson()).toList(),
    'months': months.map((month) => month.toJson()).toList(),
    'personalBests': personalBests.map((best) => best.toJson()).toList(),
    if (volumeChange28dPercent != null)
      'volumeChange28dPercent': volumeChange28dPercent,
    if (volumeChange90dPercent != null)
      'volumeChange90dPercent': volumeChange90dPercent,
    'missingEvidence': missingEvidence,
  };

  factory EliteAnalysisState.fromJson(
    Map<String, dynamic> json,
  ) => EliteAnalysisState(
    physiology: json['physiology'] == null
        ? const AthletePhysiologyState()
        : AthletePhysiologyState.fromJson(
            json['physiology'] as Map<String, dynamic>,
          ),
    historyStart: json['historyStart'] == null
        ? null
        : DateTime.parse(json['historyStart'].toString()),
    latestGarminSessionId: json['latestGarminSessionId'] as String?,
    historyEnd: json['historyEnd'] == null
        ? null
        : DateTime.parse(json['historyEnd'].toString()),
    windows:
        (json['windows'] as List<dynamic>?)
            ?.map(
              (window) => TrainingWindowAnalysis.fromJson(
                window as Map<String, dynamic>,
              ),
            )
            .toList() ??
        const [],
    months:
        (json['months'] as List<dynamic>?)
            ?.map(
              (month) => MonthlyTrainingSummary.fromJson(
                month as Map<String, dynamic>,
              ),
            )
            .toList() ??
        const [],
    personalBests:
        (json['personalBests'] as List<dynamic>?)
            ?.map(
              (best) =>
                  AthleteBestEvidence.fromJson(best as Map<String, dynamic>),
            )
            .toList() ??
        const [],
    volumeChange28dPercent: (json['volumeChange28dPercent'] as num?)
        ?.toDouble(),
    volumeChange90dPercent: (json['volumeChange90dPercent'] as num?)
        ?.toDouble(),
    missingEvidence:
        (json['missingEvidence'] as List<dynamic>?)
            ?.map((value) => value.toString())
            .toList() ??
        const [],
  );
}
