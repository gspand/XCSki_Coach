/// Oberkörper- und Doppelstock-Zustand (Double Poling State) im XCAthleteState.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Ercolina liefert First-Party-Messdaten höchster Auflösung.
/// - Absolute Power wird erst dann als diagnostische Leistung interpretiert,
///   wenn Kalibrierung (Drop-Test / Machine Model V2) und Messbedingungen valide sind.
/// - Ohne valide Kalibrierung bleibt [diagnosticConfidence] niedrig oder moderat.
/// - Unabhängig von absoluten Wattwerten sind intraindividuelle Vergleiche
///   bei identischen Messbedingungen möglich.
library;

class DoublePolingState {
  const DoublePolingState({
    this.recentSessionAveragePowerWatt,
    this.workPhaseAveragePowerWatt,
    this.peakPowerWatt,
    this.totalWorkJoule28d,
    this.recentStrokeRate,
    this.recentWorkPerStrokeJoule,
    this.leftRightBalancePercent,
    this.intervalRepeatabilityScore,
    this.powerDegradationPercent,
    this.strokeDegradationPercent,
    this.calibrationConfidence,
    this.diagnosticConfidence = 0.5,
    this.intraIndividualTrend,
    this.lastSessionAt,
    this.recentSessionIds = const [],
  });

  /// Mittlere Leistung über die gesamte Trainingszeit der jüngsten Einheit(en).
  final double? recentSessionAveragePowerWatt;

  /// Mittlere Leistung während der reinen Arbeitsphasen (ohne Pausen).
  final double? workPhaseAveragePowerWatt;

  /// Spitzenleistung (höchster Zug oder 5-Sekunden-Peak).
  final double? peakPowerWatt;

  /// Akkumulierte mechanische Doppelstockarbeit der letzten 28 Tage (in Joule).
  final double? totalWorkJoule28d;

  /// Mittlere Zugfrequenz (Züge/min).
  final double? recentStrokeRate;

  /// Arbeit pro Einzelzug in Joule (Work per Stroke).
  final double? recentWorkPerStrokeJoule;

  /// Bilaterale Symmetrie links/rechts in Prozent (z. B. 50.0 = perfekt balanciert).
  final double? leftRightBalancePercent;

  /// Wiederholbarkeit von Intervall-Leistungen (0.0 = starker Einbruch, 1.0 = pacingkonstant).
  final double? intervalRepeatabilityScore;

  /// Prozentualer Leistungsabfall zwischen erster und zweiter Hälfte einer Session.
  final double? powerDegradationPercent;

  /// Veränderung der Zugmechanik / Zugfrequenz bei Ermüdung.
  final double? strokeDegradationPercent;

  /// Kalibrierungs-Güte (Drop-Test / Bremsskalibrierung; null wenn nicht explizit kalibriert).
  final double? calibrationConfidence;

  /// Diagnostische Konfidenz für absolute Watt-Aussagen.
  /// Nur hoch (> 0.85), wenn Kalibrierung aktuell und valide ist!
  final double diagnosticConfidence;

  /// Intraindividueller Trend bei vergleichbaren Bedingungen (z. B. '+6 W bei gleichem Setup').
  final String? intraIndividualTrend;

  final DateTime? lastSessionAt;
  final List<String> recentSessionIds;

  bool get hasValidCalibration => (calibrationConfidence ?? 0.0) >= 0.85;
  double? get totalWorkKiloJoule28d =>
      totalWorkJoule28d != null ? totalWorkJoule28d! / 1000.0 : null;

  Map<String, dynamic> toJson() => {
    if (recentSessionAveragePowerWatt != null)
      'recentSessionAveragePowerWatt': recentSessionAveragePowerWatt,
    if (workPhaseAveragePowerWatt != null)
      'workPhaseAveragePowerWatt': workPhaseAveragePowerWatt,
    if (peakPowerWatt != null) 'peakPowerWatt': peakPowerWatt,
    if (totalWorkJoule28d != null) 'totalWorkJoule28d': totalWorkJoule28d,
    if (recentStrokeRate != null) 'recentStrokeRate': recentStrokeRate,
    if (recentWorkPerStrokeJoule != null)
      'recentWorkPerStrokeJoule': recentWorkPerStrokeJoule,
    if (leftRightBalancePercent != null)
      'leftRightBalancePercent': leftRightBalancePercent,
    if (intervalRepeatabilityScore != null)
      'intervalRepeatabilityScore': intervalRepeatabilityScore,
    if (powerDegradationPercent != null)
      'powerDegradationPercent': powerDegradationPercent,
    if (strokeDegradationPercent != null)
      'strokeDegradationPercent': strokeDegradationPercent,
    if (calibrationConfidence != null)
      'calibrationConfidence': calibrationConfidence,
    'diagnosticConfidence': diagnosticConfidence,
    if (intraIndividualTrend != null)
      'intraIndividualTrend': intraIndividualTrend,
    if (lastSessionAt != null)
      'lastSessionAt': lastSessionAt!.toIso8601String(),
    'recentSessionIds': recentSessionIds,
  };

  factory DoublePolingState.fromJson(Map<String, dynamic> json) =>
      DoublePolingState(
        recentSessionAveragePowerWatt:
            (json['recentSessionAveragePowerWatt'] as num?)?.toDouble(),
        workPhaseAveragePowerWatt: (json['workPhaseAveragePowerWatt'] as num?)
            ?.toDouble(),
        peakPowerWatt: (json['peakPowerWatt'] as num?)?.toDouble(),
        totalWorkJoule28d: (json['totalWorkJoule28d'] as num?)?.toDouble(),
        recentStrokeRate: (json['recentStrokeRate'] as num?)?.toDouble(),
        recentWorkPerStrokeJoule: (json['recentWorkPerStrokeJoule'] as num?)
            ?.toDouble(),
        leftRightBalancePercent: (json['leftRightBalancePercent'] as num?)
            ?.toDouble(),
        intervalRepeatabilityScore: (json['intervalRepeatabilityScore'] as num?)
            ?.toDouble(),
        powerDegradationPercent: (json['powerDegradationPercent'] as num?)
            ?.toDouble(),
        strokeDegradationPercent: (json['strokeDegradationPercent'] as num?)
            ?.toDouble(),
        calibrationConfidence: (json['calibrationConfidence'] as num?)
            ?.toDouble(),
        diagnosticConfidence:
            (json['diagnosticConfidence'] as num?)?.toDouble() ?? 0.5,
        intraIndividualTrend: json['intraIndividualTrend']?.toString(),
        lastSessionAt: json['lastSessionAt'] != null
            ? DateTime.parse(json['lastSessionAt'].toString())
            : null,
        recentSessionIds:
            (json['recentSessionIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}
