/// Subjektive Rückmeldungen und Bereitschaftsevidenz (Subjective Readiness State).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Noch KEIN binäres Freigabe-Gate (Ready / Not Ready).
/// - Missing = UNKNOWN. Fehlende Daten dürfen NIEMALS als «gut» oder «erholt» interpretiert werden!
/// - Erfasst Symptome (Schmerz, Infekt, ungewöhnliche Erschöpfung) als strukturierte Evidenz.
library;

class SubjectiveReadinessState {
  const SubjectiveReadinessState({
    this.perceivedRecovery,
    this.muscleSoreness,
    this.upperBodySoreness,
    this.legSoreness,
    this.sleepQuality,
    this.motivation,
    this.illnessSymptoms = const [],
    this.painSymptoms = const [],
    this.unusualFatigue,
    this.recordedAt,
    this.confidence = 0.5,
  });

  /// Subjektive Erholung (1 = erschöpft, 10 = voll erholt).
  final double? perceivedRecovery;

  /// Allgemeine Muskelschmerzen / DOMS (1 = schmerzfrei, 10 = extrem stark).
  final double? muscleSoreness;

  /// Spezifischer Muskelkater im Oberkörper / Rumpf (Doppelstock-relevant).
  final double? upperBodySoreness;

  /// Spezifischer Muskelkater in den Beinen (Skating/Klassisch-relevant).
  final double? legSoreness;

  /// Schlafqualität (1 = miserabel, 10 = exzellent).
  final double? sleepQuality;

  /// Trainingsmotivation (1 = völlig lustlos, 10 = hochmotiviert).
  final double? motivation;

  /// Symptome eines Infekts oder Krankheitsgefühls (z. B. ['Halskratzen', 'Kopfschmerzen']).
  final List<String> illnessSymptoms;

  /// Akute Schmerzen / orthopädische Beschwerden (z. B. ['Ellenbogensehne rechts']).
  final List<String> painSymptoms;

  /// Ungewöhnliche, unbegründete Erschöpfung.
  final bool? unusualFatigue;

  /// Zeitstempel der jüngsten subjektiven Erfassung.
  final DateTime? recordedAt;

  final double confidence;

  bool get hasData =>
      perceivedRecovery != null ||
      muscleSoreness != null ||
      upperBodySoreness != null ||
      legSoreness != null ||
      sleepQuality != null ||
      motivation != null ||
      illnessSymptoms.isNotEmpty ||
      painSymptoms.isNotEmpty ||
      unusualFatigue != null;

  bool get hasIllnessSymptoms => illnessSymptoms.isNotEmpty;
  bool get hasPainSymptoms => painSymptoms.isNotEmpty;

  Map<String, dynamic> toJson() => {
    if (perceivedRecovery != null) 'perceivedRecovery': perceivedRecovery,
    if (muscleSoreness != null) 'muscleSoreness': muscleSoreness,
    if (upperBodySoreness != null) 'upperBodySoreness': upperBodySoreness,
    if (legSoreness != null) 'legSoreness': legSoreness,
    if (sleepQuality != null) 'sleepQuality': sleepQuality,
    if (motivation != null) 'motivation': motivation,
    if (illnessSymptoms.isNotEmpty) 'illnessSymptoms': illnessSymptoms,
    if (painSymptoms.isNotEmpty) 'painSymptoms': painSymptoms,
    if (unusualFatigue != null) 'unusualFatigue': unusualFatigue,
    if (recordedAt != null) 'recordedAt': recordedAt!.toIso8601String(),
    'confidence': confidence,
  };

  factory SubjectiveReadinessState.fromJson(Map<String, dynamic> json) =>
      SubjectiveReadinessState(
        perceivedRecovery: (json['perceivedRecovery'] as num?)?.toDouble(),
        muscleSoreness: (json['muscleSoreness'] as num?)?.toDouble(),
        upperBodySoreness: (json['upperBodySoreness'] as num?)?.toDouble(),
        legSoreness: (json['legSoreness'] as num?)?.toDouble(),
        sleepQuality: (json['sleepQuality'] as num?)?.toDouble(),
        motivation: (json['motivation'] as num?)?.toDouble(),
        illnessSymptoms: (json['illnessSymptoms'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        painSymptoms: (json['painSymptoms'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        unusualFatigue: json['unusualFatigue'] as bool?,
        recordedAt: json['recordedAt'] != null
            ? DateTime.parse(json['recordedAt'].toString())
            : null,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      );
}
