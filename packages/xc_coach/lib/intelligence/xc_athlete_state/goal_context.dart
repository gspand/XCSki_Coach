/// Zielkontext (Goal Context) im XCAthleteState.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Reiner Kontext für den Coach (Wettkampfdistanz, Zieldatum, Priorität).
/// - Fällt noch KEINE Coachingentscheidung und erzwingt keine automatische Trainingspace!
/// - Verändert keine historischen Messdaten.
library;

import '../../domain/xc_modality.dart';

class GoalContext {
  const GoalContext({
    required this.name,
    required this.modality,
    this.targetDistanceMetres,
    this.targetDurationSeconds,
    this.raceDate,
    this.priority = 'A',
    this.weeklyAvailableMinutes = const {},
  });

  /// Name des Ziels (z. B. '50 km Skating').
  final String name;

  /// Wettkampfsportart / Technik (z. B. skiSkating).
  final XcModality modality;

  /// Vorgesehene Wettkampfdistanz in Metern.
  final double? targetDistanceMetres;

  /// Angestrebte Zielzeit in Sekunden (z. B. 8100 s = 2:15:00).
  final int? targetDurationSeconds;

  /// Datum des Hauptwettkampfs.
  final DateTime? raceDate;

  /// Priorität ('A', 'B', 'C').
  final String priority;

  /// Verfügbare Trainingszeit je Wochentag in Minuten.
  final Map<int, int> weeklyAvailableMinutes;

  int? daysUntilGoal({required DateTime asOf}) =>
      raceDate != null ? raceDate!.difference(asOf).inDays : null;

  double? get targetDistanceKm =>
      targetDistanceMetres != null ? targetDistanceMetres! / 1000.0 : null;

  double? get targetDurationHours =>
      targetDurationSeconds != null ? targetDurationSeconds! / 3600.0 : null;

  /// Rechnerische Durchschnittsgeschwindigkeit (km/h) als rein informative Zielgröße.
  /// (Kein Trainingspace-Diktat!)
  double? get targetSpeedKmh {
    if (targetDistanceKm == null || targetDurationHours == null) return null;
    if (targetDurationHours! <= 0) return null;
    return targetDistanceKm! / targetDurationHours!;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'modality': modality.key,
    if (targetDistanceMetres != null)
      'targetDistanceMetres': targetDistanceMetres,
    if (targetDurationSeconds != null)
      'targetDurationSeconds': targetDurationSeconds,
    if (raceDate != null) 'raceDate': raceDate!.toIso8601String().split('T').first,
    'priority': priority,
    if (weeklyAvailableMinutes.isNotEmpty)
      'weeklyAvailableMinutes': weeklyAvailableMinutes.map(
        (k, v) => MapEntry(k.toString(), v),
      ),
  };

  factory GoalContext.fromJson(Map<String, dynamic> json) => GoalContext(
    name: (json['name'] ?? '').toString(),
    modality: XcModality.values.firstWhere(
      (m) => m.key == json['modality'],
      orElse: () => XcModality.skiSkating,
    ),
    targetDistanceMetres:
        (json['targetDistanceMetres'] as num?)?.toDouble(),
    targetDurationSeconds:
        (json['targetDurationSeconds'] as num?)?.toInt(),
    raceDate: json['raceDate'] != null
        ? DateTime.parse(json['raceDate'].toString())
        : null,
    priority: (json['priority'] ?? 'A').toString(),
    weeklyAvailableMinutes:
        (json['weeklyAvailableMinutes'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(int.parse(k), (v as num).toInt()),
            ) ??
            const {},
  );
}
