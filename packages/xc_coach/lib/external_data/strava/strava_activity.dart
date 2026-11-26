/// Strava-Aktivitätenmodell für GIULIA.
///
/// Bildet eine absolvierte Outdoor-Aktivität (z. B. Langlauf Skating, Skiroller,
/// Rad, Laufen) ab, wie sie von Strava bereitgestellt wird.
library;

import '../../intelligence/planning/planning_models.dart';

class StravaActivity {
  const StravaActivity({
    required this.id,
    required this.name,
    required this.sportType,
    required this.startDateLocal,
    required this.movingTimeSeconds,
    required this.elapsedTimeSeconds,
    required this.distanceMetres,
    this.totalElevationGainMetres,
    this.averageHeartRateBpm,
    this.maxHeartRateBpm,
    this.averageWatts,
    this.weightedAverageWatts,
    this.sufferScore,
  });

  final String id;
  final String name;
  final String sportType;
  final DateTime startDateLocal;
  final int movingTimeSeconds;
  final int elapsedTimeSeconds;
  final double distanceMetres;
  final double? totalElevationGainMetres;
  final double? averageHeartRateBpm;
  final int? maxHeartRateBpm;
  final double? averageWatts;
  final double? weightedAverageWatts;
  final int? sufferScore;

  double get distanceKm => distanceMetres / 1000.0;
  double get durationMinutes => movingTimeSeconds / 60.0;
  double get durationHours => movingTimeSeconds / 3600.0;

  /// Durchschnittsgeschwindigkeit in km/h.
  double get averageSpeedKmh => durationHours > 0 ? distanceKm / durationHours : 0.0;

  /// Zuordnung zur internen [TrainingModality] von GIULIA.
  TrainingModality get modality {
    final lower = sportType.toLowerCase();
    if (lower.contains('nordicski') || lower.contains('crosscountryski') || lower.contains('langlauf')) {
      return TrainingModality.skiSkating;
    }
    if (lower.contains('rollerski')) {
      return TrainingModality.skiSkating;
    }
    if (lower.contains('ride') || lower.contains('cycle') || lower.contains('biking')) {
      return lower.contains('virtual') || lower.contains('indoor')
          ? TrainingModality.bikeIndoor
          : TrainingModality.bikeOutdoor;
    }
    if (lower.contains('run') || lower.contains('trail')) {
      return TrainingModality.running;
    }
    // Ercolina oder allgemeines Kraft-/Techniktraining
    return TrainingModality.ercolina;
  }

  factory StravaActivity.fromJson(Map<String, dynamic> json) {
    final rawDate = json['start_date'] ?? json['start_date_local'];
    final parsedDate = rawDate is String ? DateTime.tryParse(rawDate) : null;
    if (parsedDate == null || (json['id'] ?? '').toString().isEmpty) {
      throw const FormatException('Strava-Aktivität ohne gültigen Beginn oder Kennung.');
    }

    final movingTime = (json['moving_time'] as num?)?.toInt() ??
        (json['elapsed_time'] as num?)?.toInt() ??
        0;

    return StravaActivity(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Strava Aktivität').toString(),
      sportType: (json['sport_type'] ?? json['type'] ?? 'Workout').toString(),
      startDateLocal: parsedDate,
      movingTimeSeconds: movingTime,
      elapsedTimeSeconds: (json['elapsed_time'] as num?)?.toInt() ?? movingTime,
      distanceMetres: (json['distance'] as num?)?.toDouble() ?? 0.0,
      totalElevationGainMetres: (json['total_elevation_gain'] as num?)?.toDouble(),
      averageHeartRateBpm: (json['average_heartrate'] as num?)?.toDouble(),
      maxHeartRateBpm: (json['max_heartrate'] as num?)?.toInt(),
      averageWatts: (json['average_watts'] as num?)?.toDouble(),
      weightedAverageWatts: (json['weighted_average_watts'] as num?)?.toDouble(),
      sufferScore: (json['suffer_score'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sport_type': sportType,
    'start_date_local': startDateLocal.toIso8601String(),
    'moving_time': movingTimeSeconds,
    'elapsed_time': elapsedTimeSeconds,
    'distance': distanceMetres,
    if (totalElevationGainMetres != null) 'total_elevation_gain': totalElevationGainMetres,
    if (averageHeartRateBpm != null) 'average_heartrate': averageHeartRateBpm,
    if (maxHeartRateBpm != null) 'max_heartrate': maxHeartRateBpm,
    if (averageWatts != null) 'average_watts': averageWatts,
    if (weightedAverageWatts != null) 'weighted_average_watts': weightedAverageWatts,
    if (sufferScore != null) 'suffer_score': sufferScore,
  };
}
