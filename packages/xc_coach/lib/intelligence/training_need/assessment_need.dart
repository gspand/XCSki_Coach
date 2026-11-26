/// Informations- und Diagnostikbedarf (Assessment Need / Information Need).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - «Ich weiß noch nicht genug» ist wissenschaftlich hochwertiger als ein erfundener Trainingsbedarf.
/// - Fehlende Skating-Schwelle erzeugt einen [AssessmentNeed], KEINEN künstlichen [TrainingNeed].
/// - Fehlende Durability-Beobachtungen bedeuten Informationsbedarf, nicht schlechte Durability.
/// - Unbekannte Technikqualität erzeugt Informationsbedarf, keinen behaupteten Technikmangel.
library;

import '../../domain/xc_modality.dart';
import 'need_types.dart';

class AssessmentNeed {
  const AssessmentNeed({
    required this.id,
    required this.type,
    required this.priority,
    required this.reasons,
    this.targetModality = XcModality.skiSkating,
    this.confidence = NeedConfidence.high,
    this.sourceEvidence,
  });

  /// Eindeutige Kennung des Informationsbedarfs.
  final String id;

  /// Spezifischer Typ des diagnostischen Bedarfs.
  final AssessmentNeedType type;

  /// Dringlichkeit der Klärung für das Erreichen des Zielprofils.
  final NeedPriority priority;

  /// Nachvollziehbare sportwissenschaftliche Begründungen.
  final List<String> reasons;

  /// Ziel-Sportart/Modality, für welche die Information fehlt.
  final XcModality targetModality;

  /// Verlässlichkeit der Notwendigkeit dieser Diagnostik.
  final NeedConfidence confidence;

  /// Bisherige Datenlage oder fehlender Nachweis.
  final String? sourceEvidence;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.key,
    'priority': priority.nameKey,
    'reasons': reasons,
    'targetModality': targetModality.key,
    'confidence': confidence.name,
    if (sourceEvidence != null) 'sourceEvidence': sourceEvidence,
  };
}
