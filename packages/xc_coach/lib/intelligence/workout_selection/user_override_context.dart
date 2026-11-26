/// Benutzerspezifische Eingriffe und Tagespräferenzen (User Override Context).
///
/// Ermöglicht dem Athleten, Tagesentscheidungen zu überschreiben oder
/// zusätzliche subjektive Rahmenbedingungen und geplante Trainingsblöcke anzugeben.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Kein boolescher Sicherheits-Bypass:
///   Aufeinanderfolgende intensive Tage (Consecutive Hard Days) sind grundsätzlich
///   eine reguläre Trainingsstruktur im Skilanglauf (z. B. Blocktraining).
/// - Ein geplanter Trainingsblock ([plannedTrainingBlockContext]) liefert positive
///   Kontextevidenz für die Reizdichte, ist aber kein simpler "Safety Bypass".
library;

import '../../domain/xc_modality.dart';
import '../training_need/need_types.dart';

class UserOverrideContext {
  const UserOverrideContext({
    this.forcedRestDay = false,
    this.preferredModality,
    this.excludedModalities = const [],
    this.maxAvailableMinutes,
    this.heavyLegs = false,
    this.heavyArms = false,
    this.focusNeed,
    this.plannedTrainingBlockContext,
    bool? allowConsecutiveHardDays,
    this.notes,
  }) : _allowConsecutiveHardDays = allowConsecutiveHardDays;

  /// Erzwingt einen vollständigen Ruhetag durch den Athleten.
  final bool forcedRestDay;

  /// Bevorzugte Sportart / Modalität für heute.
  final XcModality? preferredModality;

  /// Vom Athleten für heute explizit ausgeschlossene Modalitäten.
  final List<XcModality> excludedModalities;

  /// Manuell reduziertes Zeitbudget (Minuten).
  final int? maxAvailableMinutes;

  /// Lokale muskuläre Ermüdung: Schwere Beine (z. B. nach Kniebeugen oder Skitour).
  final bool heavyLegs;

  /// Lokale muskuläre Ermüdung: Müde Arme/Schultern (z. B. nach Ercolina-Belastung).
  final bool heavyArms;

  /// Spezifischer Trainingsbedarf, den der Athlet heute fokussieren möchte.
  final TrainingNeedType? focusNeed;

  /// Geplanter Trainingsblock-Kontext (z. B. "Wochenend-Schwellenblock", "HIT-Mikrozyklus").
  /// Liefert positive Kontextevidenz für aufeinanderfolgende intensive Reize.
  final String? plannedTrainingBlockContext;

  final bool? _allowConsecutiveHardDays;

  /// Gibt an, ob ein expliziter Trainingsblock aktiv ist.
  bool get hasPlannedTrainingBlock =>
      (plannedTrainingBlockContext != null && plannedTrainingBlockContext!.isNotEmpty) ||
      (_allowConsecutiveHardDays == true);

  /// Rückwärtskompatibler Getter.
  bool get allowConsecutiveHardDays => hasPlannedTrainingBlock;

  /// Freitext-Notiz des Athleten.
  final String? notes;

  Map<String, dynamic> toJson() => {
    'forcedRestDay': forcedRestDay,
    'preferredModality': preferredModality?.name,
    'excludedModalities': excludedModalities.map((m) => m.name).toList(),
    'maxAvailableMinutes': maxAvailableMinutes,
    'heavyLegs': heavyLegs,
    'heavyArms': heavyArms,
    'focusNeed': focusNeed?.name,
    'plannedTrainingBlockContext': plannedTrainingBlockContext,
    'hasPlannedTrainingBlock': hasPlannedTrainingBlock,
    'notes': notes,
  };
}
