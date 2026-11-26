/// Zustand der Datenabdeckung und Lücken-Transparenz (Data Coverage State).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - «Der Coach muss wissen, was er NICHT weiß.»
/// - Wenn fünf Tage keine Daten synchronisiert wurden:
///   NICHT: «Athlet hatte fünf Ruhetage.»
///   SONDERN: «Trainingshistorie der letzten fünf Tage unvollständig / 5 unbekannte Tage.»
library;

class DataCoverageState {
  const DataCoverageState({
    this.lastStravaSync,
    this.lastGarminSync,
    this.lastErcolinaSession,
    this.externalActivityCoverage = 1.0,
    this.ercolinaCoverage = 1.0,
    this.hrCoverage = 1.0,
    this.powerCoverage = 1.0,
    this.subjectiveCoverage = 0.5,
    this.diagnosticsCoverage = 0.5,
    this.unknownDays28d = 0,
    this.confirmedRestDays28d = 0,
    this.observedTrainingDays28d = 0,
  });

  final DateTime? lastStravaSync;
  final DateTime? lastGarminSync;
  final DateTime? lastErcolinaSession;

  /// Anteil erfasster externer Aktivitäten (0.0 bis 1.0).
  final double externalActivityCoverage;

  /// Anteil erfasster Ercolina-Einheiten (0.0 bis 1.0).
  final double ercolinaCoverage;

  /// Anteil der Einheiten mit Herzfrequenz-Signal (0.0 bis 1.0).
  final double hrCoverage;

  /// Anteil der Einheiten mit mechanischer Leistungsmessung (0.0 bis 1.0).
  final double powerCoverage;

  /// Anteil der Einheiten mit subjektiver RPE-Rückmeldung (0.0 bis 1.0).
  final double subjectiveCoverage;

  /// Abdeckungsgrad sportartspezifischer Leistungsdiagnostik (0.0 bis 1.0).
  final double diagnosticsCoverage;

  /// Anzahl unbekannter Kalendertage in den letzten 28 Tagen (weder Einheit noch Ruhetag belegt).
  final int unknownDays28d;

  /// Anzahl explizit bestätigter Ruhetage in den letzten 28 Tagen.
  final int confirmedRestDays28d;

  /// Anzahl beobachteter Trainingstage in den letzten 28 Tagen.
  final int observedTrainingDays28d;

  /// Gesamt-Datenzuverlässigkeit (sinkt maßgeblich mit jedem unknownDay).
  double get overallCoverageRatio {
    final daysFactor = (28 - unknownDays28d).clamp(0, 28) / 28.0;
    if (daysFactor == 0) return 0.0;
    final signalQuality = 0.5 + (hrCoverage * 0.25) + (powerCoverage * 0.25);
    return daysFactor * signalQuality;
  }

  String get coverageAssessmentText {
    if (unknownDays28d > 3) {
      return 'Trainingshistorie unvollständig: $unknownDays28d unbekannte Tage in den letzten 4 Wochen (keine Datenlücke als Ruhetag werten!)';
    }
    if (unknownDays28d > 0) {
      return 'Gute Datenabdeckung mit $unknownDays28d ungeklärten Tagen';
    }
    return 'Lückenlose Datenabdeckung der letzten 28 Tage ($observedTrainingDays28d Trainingstage, $confirmedRestDays28d bestätigte Ruhetage)';
  }

  Map<String, dynamic> toJson() => {
    if (lastStravaSync != null)
      'lastStravaSync': lastStravaSync!.toIso8601String(),
    if (lastGarminSync != null)
      'lastGarminSync': lastGarminSync!.toIso8601String(),
    if (lastErcolinaSession != null)
      'lastErcolinaSession': lastErcolinaSession!.toIso8601String(),
    'externalActivityCoverage': externalActivityCoverage,
    'ercolinaCoverage': ercolinaCoverage,
    'hrCoverage': hrCoverage,
    'powerCoverage': powerCoverage,
    'subjectiveCoverage': subjectiveCoverage,
    'diagnosticsCoverage': diagnosticsCoverage,
    'unknownDays28d': unknownDays28d,
    'confirmedRestDays28d': confirmedRestDays28d,
    'observedTrainingDays28d': observedTrainingDays28d,
  };

  factory DataCoverageState.fromJson(Map<String, dynamic> json) =>
      DataCoverageState(
        lastStravaSync: json['lastStravaSync'] != null
            ? DateTime.parse(json['lastStravaSync'].toString())
            : null,
        lastGarminSync: json['lastGarminSync'] != null
            ? DateTime.parse(json['lastGarminSync'].toString())
            : null,
        lastErcolinaSession: json['lastErcolinaSession'] != null
            ? DateTime.parse(json['lastErcolinaSession'].toString())
            : null,
        externalActivityCoverage:
            (json['externalActivityCoverage'] as num?)?.toDouble() ?? 1.0,
        ercolinaCoverage:
            (json['ercolinaCoverage'] as num?)?.toDouble() ?? 1.0,
        hrCoverage: (json['hrCoverage'] as num?)?.toDouble() ?? 1.0,
        powerCoverage: (json['powerCoverage'] as num?)?.toDouble() ?? 1.0,
        subjectiveCoverage:
            (json['subjectiveCoverage'] as num?)?.toDouble() ?? 0.5,
        diagnosticsCoverage:
            (json['diagnosticsCoverage'] as num?)?.toDouble() ?? 0.5,
        unknownDays28d: (json['unknownDays28d'] as num?)?.toInt() ?? 0,
        confirmedRestDays28d:
            (json['confirmedRestDays28d'] as num?)?.toInt() ?? 0,
        observedTrainingDays28d:
            (json['observedTrainingDays28d'] as num?)?.toInt() ?? 0,
      );
}
