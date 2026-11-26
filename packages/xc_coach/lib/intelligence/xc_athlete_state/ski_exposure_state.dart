/// Skispezifische Exposition im XCAthleteState.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Trennt strikt: skiSkating, skiClassic, rollerSkiSkating, rollerSkiClassic,
///   rollerSkiDoublePoling, ercolinaDoublePoling und skiNordicUnknown.
/// - skiNordicUnknown wird NIEMALS als Skating-Exposition gewertet!
/// - Zeithorizonte: 7 Tage, 28 Tage, 90 Tage.
/// - Ermöglicht es dem Coach, zu erkennen: Hohe Ausdauer, aber fehlende Skispezifik.
library;

import '../../domain/xc_modality.dart';

/// Expositionsdaten für eine einzelne spezifische Bewegungsform.
class SkiModalityExposure {
  const SkiModalityExposure({
    required this.modality,
    this.durationSeconds7d = 0,
    this.sessionCount7d = 0,
    this.distanceMetres7d,
    this.elevationGainMetres7d,
    this.durationSeconds28d = 0,
    this.sessionCount28d = 0,
    this.distanceMetres28d,
    this.elevationGainMetres28d,
    this.durationSeconds90d = 0,
    this.sessionCount90d = 0,
    this.distanceMetres90d,
    this.elevationGainMetres90d,
    this.longestSessionSeconds28d = 0,
    this.longestSessionSeconds90d = 0,
    this.durationsSeconds90d = const [],
    this.daysSinceLastSession,
    this.confidence = 1.0,
  });

  final XcModality modality;

  final int durationSeconds7d;
  final int sessionCount7d;
  final double? distanceMetres7d;
  final double? elevationGainMetres7d;

  final int durationSeconds28d;
  final int sessionCount28d;
  final double? distanceMetres28d;
  final double? elevationGainMetres28d;

  final int durationSeconds90d;
  final int sessionCount90d;
  final double? distanceMetres90d;
  final double? elevationGainMetres90d;

  final int longestSessionSeconds28d;
  final int longestSessionSeconds90d;

  /// Die Dauern aller Einheiten im 90-Tage-Fenster.
  ///
  /// Dosisentscheidungen brauchen die Verteilung, nicht eine Kennzahl: Ein
  /// Maximum allein sagt nicht, ob es wiederholbar war. Siehe
  /// [longSessionCount90d] und [secondLongestMinutes90d].
  final List<int> durationsSeconds90d;

  /// Wie viele Einheiten mindestens drei Viertel der laengsten erreichten.
  ///
  /// Zwei oder mehr heisst: ein Plateau, die Dauer war wiederholbar. Genau
  /// eine heisst: ein einzelner Ausreisser, auch wenn er echt war.
  int get longSessionCount90d {
    if (durationsSeconds90d.isEmpty) return 0;
    final longest = longestSessionSeconds90d;
    if (longest <= 0) return 0;
    return durationsSeconds90d.where((d) => d >= longest * 0.75).length;
  }

  /// Die zweitlaengste Einheit — der Rueckfallwert, wenn die laengste allein
  /// steht.
  int get secondLongestMinutes90d {
    if (durationsSeconds90d.length < 2) return 0;
    final sorted = [...durationsSeconds90d]..sort();
    return (sorted[sorted.length - 2] / 60).round();
  }

  /// Der Median der Dauern — was der Athlet ueblicherweise tut.
  int get medianMinutes90d {
    if (durationsSeconds90d.isEmpty) return 0;
    final sorted = [...durationsSeconds90d]..sort();
    return (sorted[sorted.length ~/ 2] / 60).round();
  }

  final int? daysSinceLastSession;

  final double confidence;

  double get durationHours7d => durationSeconds7d / 3600.0;
  double get durationHours28d => durationSeconds28d / 3600.0;
  double get durationHours90d => durationSeconds90d / 3600.0;

  int get longestMinutes28d => (longestSessionSeconds28d / 60).round();
  int get longestMinutes90d => (longestSessionSeconds90d / 60).round();
  int get typicalMinutes28d => sessionCount28d > 0
      ? (durationSeconds28d / sessionCount28d / 60).round()
      : 0;

  Map<String, dynamic> toJson() => {
    'modality': modality.key,
    'durationSeconds7d': durationSeconds7d,
    'sessionCount7d': sessionCount7d,
    if (distanceMetres7d != null) 'distanceMetres7d': distanceMetres7d,
    if (elevationGainMetres7d != null)
      'elevationGainMetres7d': elevationGainMetres7d,
    'durationSeconds28d': durationSeconds28d,
    'sessionCount28d': sessionCount28d,
    if (distanceMetres28d != null) 'distanceMetres28d': distanceMetres28d,
    if (elevationGainMetres28d != null)
      'elevationGainMetres28d': elevationGainMetres28d,
    'durationSeconds90d': durationSeconds90d,
    'sessionCount90d': sessionCount90d,
    if (distanceMetres90d != null) 'distanceMetres90d': distanceMetres90d,
    if (elevationGainMetres90d != null)
      'elevationGainMetres90d': elevationGainMetres90d,
    'longestSessionSeconds28d': longestSessionSeconds28d,
    'longestSessionSeconds90d': longestSessionSeconds90d,
    if (daysSinceLastSession != null)
      'daysSinceLastSession': daysSinceLastSession,
    'confidence': confidence,
  };

  factory SkiModalityExposure.fromJson(Map<String, dynamic> json) =>
      SkiModalityExposure(
        modality: XcModality.values.firstWhere(
          (m) => m.key == json['modality'],
          orElse: () => XcModality.unknown,
        ),
        durationSeconds7d: (json['durationSeconds7d'] as num?)?.toInt() ?? 0,
        sessionCount7d: (json['sessionCount7d'] as num?)?.toInt() ?? 0,
        distanceMetres7d: (json['distanceMetres7d'] as num?)?.toDouble(),
        elevationGainMetres7d: (json['elevationGainMetres7d'] as num?)
            ?.toDouble(),
        durationSeconds28d: (json['durationSeconds28d'] as num?)?.toInt() ?? 0,
        sessionCount28d: (json['sessionCount28d'] as num?)?.toInt() ?? 0,
        distanceMetres28d: (json['distanceMetres28d'] as num?)?.toDouble(),
        elevationGainMetres28d: (json['elevationGainMetres28d'] as num?)
            ?.toDouble(),
        durationSeconds90d: (json['durationSeconds90d'] as num?)?.toInt() ?? 0,
        sessionCount90d: (json['sessionCount90d'] as num?)?.toInt() ?? 0,
        distanceMetres90d: (json['distanceMetres90d'] as num?)?.toDouble(),
        elevationGainMetres90d: (json['elevationGainMetres90d'] as num?)
            ?.toDouble(),
        longestSessionSeconds28d:
            (json['longestSessionSeconds28d'] as num?)?.toInt() ?? 0,
        longestSessionSeconds90d:
            (json['longestSessionSeconds90d'] as num?)?.toInt() ?? 0,
        daysSinceLastSession: (json['daysSinceLastSession'] as num?)?.toInt(),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      );
}

/// Gesamtzustand der skispezifischen Trainingsreize und Umfänge.
class SkiSpecificExposureState {
  const SkiSpecificExposureState({
    this.byModality = const {},
    this.totalNonSkiDurationSeconds28d = 0,
  });

  /// Aufschlüsselung je Modalität.
  final Map<XcModality, SkiModalityExposure> byModality;

  /// Trainingsumfang in unspezifischen Ausdauersportarten (Laufen, Radfahren, Rudern).
  final int totalNonSkiDurationSeconds28d;

  SkiModalityExposure exposureOf(XcModality modality) =>
      byModality[modality] ?? SkiModalityExposure(modality: modality);

  // Schnee-Exposition
  int get onSnowDurationSeconds28d =>
      (byModality[XcModality.skiSkating]?.durationSeconds28d ?? 0) +
      (byModality[XcModality.skiClassic]?.durationSeconds28d ?? 0) +
      (byModality[XcModality.skiNordicUnknown]?.durationSeconds28d ?? 0);

  // Rollski-Exposition
  int get rollerSkiDurationSeconds28d =>
      (byModality[XcModality.rollerSkiSkating]?.durationSeconds28d ?? 0) +
      (byModality[XcModality.rollerSkiClassic]?.durationSeconds28d ?? 0) +
      (byModality[XcModality.rollerSkiDoublePoling]?.durationSeconds28d ?? 0);

  // Ercolina-Exposition
  int get ercolinaDurationSeconds28d =>
      byModality[XcModality.ercolinaDoublePoling]?.durationSeconds28d ?? 0;

  // Skispezifische Gesamtzeit (Schnee + Rollski + Ercolina)
  int get totalSkiSpecificDurationSeconds28d =>
      onSnowDurationSeconds28d +
      rollerSkiDurationSeconds28d +
      ercolinaDurationSeconds28d;

  /// Spezifitätsquote der letzten 28 Tage (0.0 bis 1.0).
  ///
  /// Verhältnis von skispezifischem Training zum gesamten erfassten Ausdauertraining.
  double get skiSpecificityRatio28d {
    final total =
        totalSkiSpecificDurationSeconds28d + totalNonSkiDurationSeconds28d;
    if (total <= 0) return 0.0;
    return totalSkiSpecificDurationSeconds28d / total;
  }

  Map<String, dynamic> toJson() => {
    'byModality': byModality.map((k, v) => MapEntry(k.key, v.toJson())),
    'totalNonSkiDurationSeconds28d': totalNonSkiDurationSeconds28d,
  };

  factory SkiSpecificExposureState.fromJson(Map<String, dynamic> json) {
    final rawMap = json['byModality'] as Map<String, dynamic>? ?? {};
    final parsed = <XcModality, SkiModalityExposure>{};
    for (final entry in rawMap.entries) {
      final m = XcModality.values.firstWhere(
        (val) => val.key == entry.key,
        orElse: () => XcModality.unknown,
      );
      if (entry.value is Map<String, dynamic>) {
        parsed[m] = SkiModalityExposure.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }
    return SkiSpecificExposureState(
      byModality: parsed,
      totalNonSkiDurationSeconds28d:
          (json['totalNonSkiDurationSeconds28d'] as num?)?.toInt() ?? 0,
    );
  }
}
