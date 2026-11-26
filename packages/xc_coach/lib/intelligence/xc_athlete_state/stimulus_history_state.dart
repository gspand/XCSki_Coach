/// Historie aller gesetzten, geplanten und verifizierten Trainingsreize (Stimulus History State).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Unterscheidet strikt zwischen:
///   * lastObserved: Tatsächlich in einer Einheit beobachtet.
///   * lastPlanned: Vom Coach oder Plan als Vorgabe gesetzt.
///   * lastVerified: Geplant UND durch Messdaten erfolgreich nachgewiesen.
/// - Deckt alle 14 XC-Reizarten ab.
library;

import '../../domain/xc_modality.dart';
import '../load/stimulus_models.dart';

/// Historischer Datensatz für einen einzelnen Trainingsreiztyp.
class StimulusHistoryEntry {
  const StimulusHistoryEntry({
    required this.type,
    this.lastObservedAt,
    this.lastPlannedAt,
    this.lastVerifiedAt,
    this.sourceModality,
    this.frequency28d = 0,
    this.accumulatedExposureMinutes28d = 0.0,
    this.recentSessionIds = const [],
    this.confidence = 0.8,
  });

  final StimulusType type;
  final DateTime? lastObservedAt;
  final DateTime? lastPlannedAt;
  final DateTime? lastVerifiedAt;
  final XcModality? sourceModality;

  /// Anzahl beobachteter Reize in den letzten 28 Tagen.
  final int frequency28d;

  /// Akkumulierte Reizzeit in Minuten.
  final double accumulatedExposureMinutes28d;

  final List<String> recentSessionIds;
  final double confidence;

  int? daysSinceLastObserved({required DateTime asOf}) =>
      lastObservedAt != null ? asOf.difference(lastObservedAt!).inDays : null;

  int? daysSinceLastVerified({required DateTime asOf}) =>
      lastVerifiedAt != null ? asOf.difference(lastVerifiedAt!).inDays : null;

  Map<String, dynamic> toJson() => {
    'type': type.key,
    if (lastObservedAt != null)
      'lastObservedAt': lastObservedAt!.toIso8601String(),
    if (lastPlannedAt != null) 'lastPlannedAt': lastPlannedAt!.toIso8601String(),
    if (lastVerifiedAt != null)
      'lastVerifiedAt': lastVerifiedAt!.toIso8601String(),
    if (sourceModality != null) 'sourceModality': sourceModality!.key,
    'frequency28d': frequency28d,
    'accumulatedExposureMinutes28d': accumulatedExposureMinutes28d,
    'recentSessionIds': recentSessionIds,
    'confidence': confidence,
  };

  factory StimulusHistoryEntry.fromJson(Map<String, dynamic> json) =>
      StimulusHistoryEntry(
        type: StimulusType.values.firstWhere(
          (t) => t.key == json['type'],
          orElse: () => StimulusType.aerobicBase,
        ),
        lastObservedAt: json['lastObservedAt'] != null
            ? DateTime.parse(json['lastObservedAt'].toString())
            : null,
        lastPlannedAt: json['lastPlannedAt'] != null
            ? DateTime.parse(json['lastPlannedAt'].toString())
            : null,
        lastVerifiedAt: json['lastVerifiedAt'] != null
            ? DateTime.parse(json['lastVerifiedAt'].toString())
            : null,
        sourceModality: json['sourceModality'] != null
            ? XcModality.values.firstWhere(
                (m) => m.key == json['sourceModality'],
                orElse: () => XcModality.rollerSkiDoublePoling,
              )
            : null,
        frequency28d: (json['frequency28d'] as num?)?.toInt() ?? 0,
        accumulatedExposureMinutes28d:
            (json['accumulatedExposureMinutes28d'] as num?)?.toDouble() ?? 0.0,
        recentSessionIds: (json['recentSessionIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.8,
      );
}

/// Gesamtzustand aller Reiz-Historien im Athletengedächtnis.
class StimulusHistoryState {
  const StimulusHistoryState({
    this.entries = const {},
  });

  final Map<StimulusType, StimulusHistoryEntry> entries;

  StimulusHistoryEntry entryFor(StimulusType type) =>
      entries[type] ?? StimulusHistoryEntry(type: type);

  Map<String, dynamic> toJson() => {
    'entries': entries.map((k, v) => MapEntry(k.key, v.toJson())),
  };

  factory StimulusHistoryState.fromJson(Map<String, dynamic> json) {
    final raw = json['entries'] as Map<String, dynamic>? ?? {};
    final parsed = <StimulusType, StimulusHistoryEntry>{};
    for (final entry in raw.entries) {
      final t = StimulusType.values.firstWhere(
        (st) => st.key == entry.key,
        orElse: () => StimulusType.aerobicBase,
      );
      if (entry.value is Map<String, dynamic>) {
        parsed[t] = StimulusHistoryEntry.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }
    return StimulusHistoryState(entries: parsed);
  }
}
