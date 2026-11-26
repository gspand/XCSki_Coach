/// Ziel-Anforderungsprofil (Goal Demand Model) der GIULIA Training Need Engine.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - 50 km bei 2:15 h (Elite/Sub-Elite) stellt andere metabolische und neuromuskuläre
///   Anforderungen als 50 km bei 4:30 h (Freizeitsportler mit extremer Glykogen-/Ermüdungsdauer).
/// - Durchschnittsgeschwindigkeit aus Zieldistanz/Zielzeit darf NIEMALS als Trainingspace verwendet werden!
/// - Das Profil leitet sich aus sportwissenschaftlicher Erkenntnis ab:
///   Für einen 50-km-Skatingmarathon sind aerobe Kapazität, Durability, Schwellenstabilität
///   und Skatingspezifität entscheidender als reine 1-Minuten-Sprintpower.
library;

import '../../domain/xc_modality.dart';
import '../xc_athlete_state/goal_context.dart';
import 'need_types.dart';

class GoalDemandProfile {
  const GoalDemandProfile({
    required this.goalName,
    required this.targetModality,
    required this.demands,
    required this.expectedDurationHours,
    this.distanceKm,
    this.demandRationales = const {},
  });

  final String goalName;
  final XcModality targetModality;

  /// Relevanz/Dringlichkeit der Fähigkeiten für diesen Zielwettkampf.
  final Map<TrainingNeedType, NeedPriority> demands;

  /// Erwartete Renndauer in Stunden (bestimmt Durability- und Fueling-Anforderungen).
  final double expectedDurationHours;

  /// Vorgesehene Wettkampfdistanz in km.
  final double? distanceKm;

  /// Sportwissenschaftliche Erklärungen für jede Fähigkeit.
  final Map<TrainingNeedType, String> demandRationales;

  NeedPriority demandFor(TrainingNeedType type) =>
      demands[type] ?? NeedPriority.low;

  String? rationaleFor(TrainingNeedType type) => demandRationales[type];
}

class GoalDemandModel {
  const GoalDemandModel();

  /// Erstellt das sportwissenschaftlich fundierte Anforderungsprofil aus dem GoalContext.
  GoalDemandProfile evaluateDemand(GoalContext goal) {
    final distKm = goal.targetDistanceKm ?? 42.0; // Fallback auf Marathon-Standard wenn unbestimmt
    final durationHours = goal.targetDurationHours ?? (distKm / 18.0); // Plausibler Richtwert ~18 km/h

    final demands = <TrainingNeedType, NeedPriority>{};
    final rationales = <TrainingNeedType, String>{};

    // 1. Langdistanz-Ausdauer & Durability (stark gekoppelt an erwartete Dauer)
    if (distKm >= 30.0 || durationHours >= 1.75) {
      demands[TrainingNeedType.longEndurance] = NeedPriority.high;
      rationales[TrainingNeedType.longEndurance] =
          'Wettkampfdistanz von ${distKm.toStringAsFixed(1)} km (erwartet ca. ${durationHours.toStringAsFixed(2)} h) erfordert wiederholte lange Dauerbelastungen zur Substrat- und Sehnenadaption.';

      demands[TrainingNeedType.durability] = NeedPriority.high;
      rationales[TrainingNeedType.durability] =
          'Über ${durationHours.toStringAsFixed(2)} h Belastungszeit ist die physiologische und mechanische Durability (Verhinderung vorzeitiger Entkopplung) leistungslimitierend.';

      demands[TrainingNeedType.aerobicBase] = NeedPriority.high;
      rationales[TrainingNeedType.aerobicBase] =
          'Hohe aerobe Fettstoffwechselbasis (Zone 1/2) ist die unabdingbare Voraussetzung für Glykogeneinsparung bei langen Skimarathons.';

      demands[TrainingNeedType.threshold] = NeedPriority.high;
      rationales[TrainingNeedType.threshold] =
          'Schwellenkapazität bestimmt das maximal fahrbare Tempo an langen Anstiegen ohne vorzeitige metabolische Azidose.';

      demands[TrainingNeedType.muscularEndurance] = NeedPriority.high;
      rationales[TrainingNeedType.muscularEndurance] =
          'Wiederholte Vortriebsstöße über tausende Zyklen erfordern hohe lokale Kraftausdauer der Rumpf- und Beinmuskulatur.';

      // VO2max ist wichtig als "aerobes Dach", aber für 50 km nicht isolierte Top-Priorität
      demands[TrainingNeedType.vo2max] = NeedPriority.moderate;
      rationales[TrainingNeedType.vo2max] =
          'VO2max bildet das physiologische Leistungsdach, ist aber auf 50 km weniger differenzierend als Durability und Schwellenstabilität.';

      demands[TrainingNeedType.speedNeuromuscular] = NeedPriority.low;
      rationales[TrainingNeedType.speedNeuromuscular] =
          'Reine Maximalschnelligkeit ist primär für Zielsprints relevant, entscheidet aber selten über die Gesamtzeit eines langen Skimarathons.';
    } else {
      // Kürzere Distanzen (z. B. 10 km bis 15 km)
      demands[TrainingNeedType.threshold] = NeedPriority.critical;
      demands[TrainingNeedType.vo2max] = NeedPriority.high;
      demands[TrainingNeedType.aerobicBase] = NeedPriority.high;
      demands[TrainingNeedType.longEndurance] = NeedPriority.moderate;
      demands[TrainingNeedType.durability] = NeedPriority.moderate;
      demands[TrainingNeedType.speedNeuromuscular] = NeedPriority.moderate;
    }

    // 2. Modality-Spezifität
    if (goal.modality == XcModality.skiSkating ||
        goal.modality == XcModality.rollerSkiSkating) {
      demands[TrainingNeedType.skatingSpecificity] = NeedPriority.high;
      rationales[TrainingNeedType.skatingSpecificity] =
          'Spezifische Gleitphase, 1-1 / 2-1 Eintaktung und lateraler Beinabstoß erfordern skispezifische Reize.';

      demands[TrainingNeedType.doublePolingEndurance] = NeedPriority.moderate;
      rationales[TrainingNeedType.doublePolingEndurance] =
          'Doppelstock bildet den oberen Vortriebsanteil im Skating (insbesondere 1-1 und 2-1 Führung) und erfordert belastbare Oberkörper-Ausdauer.';

      demands[TrainingNeedType.technique] = NeedPriority.moderate;
      rationales[TrainingNeedType.technique] =
          'Ökonomische Skatingtechnik spart über die Distanz substanziell mechanische und metabolische Energie.';
    } else if (goal.modality == XcModality.skiClassic ||
        goal.modality == XcModality.rollerSkiClassic ||
        goal.modality == XcModality.rollerSkiDoublePoling) {
      demands[TrainingNeedType.classicSpecificity] = NeedPriority.high;
      demands[TrainingNeedType.doublePolingEndurance] = NeedPriority.high;
      demands[TrainingNeedType.doublePolingPower] = NeedPriority.high;
    }

    return GoalDemandProfile(
      goalName: goal.name,
      targetModality: goal.modality,
      demands: demands,
      expectedDurationHours: durationHours,
      distanceKm: distKm,
      demandRationales: rationales,
    );
  }
}
