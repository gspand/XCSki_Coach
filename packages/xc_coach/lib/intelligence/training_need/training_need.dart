/// Strukturierter Trainingsbedarf (Training Need).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Jeder Need besitzt nachvollziehbare sportwissenschaftliche Begründungen ([reasons]).
/// - Ordinales Prioritätsmodell ([priority]) ohne gefälschte Nachkommastellen.
/// - Verwandte Bedarfe werden über [relatedNeedTypes] verknüpft, um zu verhindern,
///   dass derselbe Mangel (z. B. lange Einheiten für Durability, LongEndurance und RaceSpecificity)
///   dreifach aufgebläht gezählt wird.
library;

import '../../domain/xc_modality.dart';
import 'need_types.dart';

class TrainingNeed {
  const TrainingNeed({
    required this.id,
    required this.type,
    required this.category,
    required this.priority,
    required this.reasons,
    required this.confidence,
    this.targetModality = XcModality.skiSkating,
    this.relatedNeedTypes = const [],
    this.physiologicalTransfer,
    this.specificityTransfer,
    this.sourceEvidenceIds = const [],
  });

  /// Eindeutige Kennung des Bedarfs.
  final String id;

  /// Typ der zu entwickelnden oder zu erhaltenden Fähigkeit.
  final TrainingNeedType type;

  /// Kategorie (Development, Maintenance, ImmediateOpportunity).
  final NeedCategory category;

  /// Ordinale Priorität (Critical, High, Moderate, Low, Maintenance).
  final NeedPriority priority;

  /// Liste konkreter, nachvollziehbarer Gründe für diesen Bedarf.
  final List<String> reasons;

  /// Konfidenz der Evidenzbasis.
  final NeedConfidence confidence;

  /// Relevante Ziel-Sportart / Modalität.
  final XcModality targetModality;

  /// Verwandte Bedarfe zur Vermeidung von Doppelbewertungen (z. B. Durability & LongEndurance).
  final List<TrainingNeedType> relatedNeedTypes;

  /// Kardiovaskulärer / metabolischer Übertrag (falls modalitätsspezifisch berechnet).
  final double? physiologicalTransfer;

  /// Spezifischer biomechanischer / technischer Übertrag.
  final double? specificityTransfer;

  /// IDs der zugrundeliegenden Evidenzobjekte (Sessions, Diagnostik, State-Felder).
  final List<String> sourceEvidenceIds;

  factory TrainingNeed.fromJson(Map<String, dynamic> j) => TrainingNeed(
    id: j['id'] as String,
    type: TrainingNeedType.values.firstWhere((t) => t.key == j['type']),
    category: NeedCategory.values.firstWhere((t) => t.key == j['category']),
    priority: NeedPriority.values.firstWhere((t) => t.nameKey == j['priority']),
    reasons: (j['reasons'] as List? ?? const []).cast<String>(),
    confidence: NeedConfidence.values.byName(j['confidence'] as String),
    targetModality: XcModality.values.firstWhere(
      (t) => t.key == j['targetModality'],
    ),
    relatedNeedTypes: (j['relatedNeedTypes'] as List? ?? const [])
        .cast<String>()
        .map((k) => TrainingNeedType.values.firstWhere((t) => t.key == k))
        .toList(),
    physiologicalTransfer: (j['physiologicalTransfer'] as num?)?.toDouble(),
    specificityTransfer: (j['specificityTransfer'] as num?)?.toDouble(),
    sourceEvidenceIds: (j['sourceEvidenceIds'] as List? ?? const [])
        .cast<String>(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.key,
    'category': category.key,
    'priority': priority.nameKey,
    'reasons': reasons,
    'confidence': confidence.name,
    'targetModality': targetModality.key,
    'relatedNeedTypes': relatedNeedTypes.map((t) => t.key).toList(),
    if (physiologicalTransfer != null)
      'physiologicalTransfer': physiologicalTransfer,
    if (specificityTransfer != null) 'specificityTransfer': specificityTransfer,
    'sourceEvidenceIds': sourceEvidenceIds,
  };
}
