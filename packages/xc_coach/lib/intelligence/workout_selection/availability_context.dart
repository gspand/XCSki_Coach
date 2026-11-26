/// Verfügbarkeits- und Umgebungskontext für die tägliche Trainingsentscheidung (Schritt 5).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Kein Athlet hat jeden Tag unbegrenzt Zeit und Zugriff auf Schnee.
/// - Der Coach muss wissen:
///   1. Zeitbudget heute (Minuten)
///   2. Zugang zu Trainingsumgebungen (Schnee, Rollskibahn, Ercolina, Kraftraum, Strasse)
///   3. Vorausschauende Verfügbarkeit (Look-Ahead): Wenn heute nur 45 min frei sind,
///      aber am Samstag 180 min, wird eine Langzeitausdauer auf den Samstag verschoben,
///      statt sie heute unvollständig abzubrechen.
library;

import '../../domain/xc_modality.dart';

/// Verfügbare Trainingsumgebung für den heutigen Tag.
enum TrainingEnvironment {
  outdoorSnow('Schnee / Loipe'),
  rollerSkiRoad('Rollskibahn / Asphalt'),
  indoorErcolina('Ercolina Zuggerät / Indoortrainer'),
  outdoorTrailOrRoad('Outdoor Laufen / Trail'),
  indoorBike('Fahrradergometer / Rolle'),
  gym('Kraftraum / Gym'),
  restOnly('Nur Regeneration möglich');

  const TrainingEnvironment(this.label);
  final String label;
}

/// Verfügbarkeitskontext für einen konkreten Tag.
class DayAvailability {
  const DayAvailability({
    required this.date,
    required this.availableMinutes,
    this.assumption,
    this.allowedModalities = const {
      XcModality.skiSkating,
      XcModality.skiClassic,
      XcModality.ercolinaDoublePoling,
      XcModality.rollerSkiSkating,
      XcModality.running,
      XcModality.cycling,
    },
    this.environment = TrainingEnvironment.indoorErcolina,
    this.hasErcolina = true,
    this.hasSnow = false,
    this.hasRollerSki = false,
    this.hasBike = true,
    this.hasRunningShoes = true,
    this.preferredModality,
  });

  final DateTime date;

  /// Heute verfügbare Netto-Trainingszeit in Minuten.
  final int availableMinutes;
  final String? assumption;

  /// Vom Athleten für heute zugelassene Modalitäten.
  final Set<XcModality> allowedModalities;

  /// Primäre Trainingsumgebung heute.
  final TrainingEnvironment environment;

  final bool hasErcolina;
  final bool hasSnow;
  final bool hasRollerSki;
  final bool hasBike;
  final bool hasRunningShoes;

  /// Explizite Präferenz des Athleten (falls vorhanden).
  final XcModality? preferredModality;

  /// Prüft, ob eine bestimmte Modalität mit dem heutigen Equipment und Umfeld machbar ist.
  bool isModalityFeasible(XcModality modality) {
    if (!allowedModalities.contains(modality)) return false;

    switch (modality) {
      case XcModality.skiSkating:
      case XcModality.skiClassic:
        return hasSnow && environment == TrainingEnvironment.outdoorSnow;
      case XcModality.rollerSkiSkating:
      case XcModality.rollerSkiClassic:
        return hasRollerSki && (environment == TrainingEnvironment.rollerSkiRoad || environment == TrainingEnvironment.outdoorTrailOrRoad);
      case XcModality.ercolinaDoublePoling:
        return hasErcolina;
      case XcModality.cycling:
        return hasBike;
      case XcModality.running:
        return hasRunningShoes;
      default:
        return true;
    }
  }

  DayAvailability copyWith({
    DateTime? date,
    int? availableMinutes,
    Set<XcModality>? allowedModalities,
    TrainingEnvironment? environment,
    bool? hasErcolina,
    bool? hasSnow,
    bool? hasRollerSki,
    bool? hasBike,
    bool? hasRunningShoes,
    XcModality? preferredModality,
  }) {
    return DayAvailability(
      date: date ?? this.date,
      availableMinutes: availableMinutes ?? this.availableMinutes,
      assumption: assumption,
      allowedModalities: allowedModalities ?? this.allowedModalities,
      environment: environment ?? this.environment,
      hasErcolina: hasErcolina ?? this.hasErcolina,
      hasSnow: hasSnow ?? this.hasSnow,
      hasRollerSki: hasRollerSki ?? this.hasRollerSki,
      hasBike: hasBike ?? this.hasBike,
      hasRunningShoes: hasRunningShoes ?? this.hasRunningShoes,
      preferredModality: preferredModality ?? this.preferredModality,
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'availableMinutes': availableMinutes,
    if (assumption != null) 'assumption': assumption,
    'allowedModalities': allowedModalities.map((m) => m.name).toList(),
    'environment': environment.name,
    'hasErcolina': hasErcolina,
    'hasSnow': hasSnow,
    'hasRollerSki': hasRollerSki,
    'hasBike': hasBike,
    'hasRunningShoes': hasRunningShoes,
    'preferredModality': preferredModality?.name,
  };
}

/// Vorausschauende Verfügbarkeit über die kommenden Tage (Look-Ahead Scheduling).
class DayLookAheadContext {
  const DayLookAheadContext({
    required this.upcomingDays,
  });

  /// Chronologisch geordnete Verfügbarkeiten der kommenden Tage (z. B. morgen bis Sonntag).
  final List<DayAvailability> upcomingDays;

  /// Prüft, ob in den nächsten Tagen ein langes Zeitfenster (z. B. >= minMinutes) vorhanden ist.
  bool hasUpcomingLongWindow(int minMinutes) {
    return upcomingDays.any((d) => d.availableMinutes >= minMinutes);
  }

  /// Liefert den ersten kommenden Tag mit ausreichend Zeit für eine lange Einheit.
  DayAvailability? findNextLongWindow(int minMinutes) {
    for (final day in upcomingDays) {
      if (day.availableMinutes >= minMinutes) return day;
    }
    return null;
  }
}
