/// Deskriptive Berechnung von akuter und chronischer Belastung (EWMA) in GIULIA.
///
/// Wissenschaftliche Fundierung:
/// - Banister EW et al. (1975): Systems model of training for athletic performance.
///   Aust J Sports Med 7: 57-61.
/// - Morton RH (1997): Modeling training and overtraining. J Sports Sci 15(3): 335-340.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// 1. Kein biologischer Naturkonstanten-Anspruch für 7 und 42 Tage. Die Zeitkonstanten
///    sind parametrisierbar und deskriptiv.
/// 2. LoadBalance = ChronicLoad - AcuteLoad darf NICHT isoliert als «fit», «müde»,
///    «verletzt» oder «optimal trainiert» interpretiert werden.
/// 3. KEIN ACWR (Acute:Chronic Workload Ratio) als Safety-, Verletzungs- oder Coach-Gate.
///    Wissenschaftliche Meta-Analysen (z. B. Impellizzeri et al. 2020) zeigen, dass
///    ACWR-Schwellenwerte (wie 1.5) artefaktbehaftet und nicht kausal prädiktiv sind.
///    Ein ACWR wird hier, falls abgefragt, ausschliesslich rein deskriptiv ausgewiesen.
/// 4. Fehlende Trainingstage bedeuten exaktes mathematisches Abklingen (Decay),
///    niemals Datenverlust oder Aussetzen der Kurve.
library;

import 'dart:math' as math;

import 'load_models.dart';

/// Eingabedatum für einen Tag im rollierenden Belastungstracking.
class EwmaDailyInput {
  const EwmaDailyInput({
    required this.date,
    this.load = 0.0,
    this.classification = DayClassification.observedTrainingDay,
  });

  final DateTime date;
  final double load;
  final DayClassification classification;
}

/// Tageszustand der rollierenden Belastung.
class EwmaDailyState {
  const EwmaDailyState({
    required this.date,
    required this.dailyLoad,
    required this.acuteLoad,
    required this.chronicLoad,
    required this.loadBalance,
    this.experimentalAcwr,
    this.classification = DayClassification.observedTrainingDay,
    this.confidence = 1.0,
  });

  final DateTime date;

  /// Am Tag erbrachte Gesamtbelastung (z. B. Banister TRIMP, sRPE Load oder Work kJ).
  final double dailyLoad;

  /// Akute Belastung (typisch 7-Tage-Zeithorizont).
  final double acuteLoad;

  /// Chronische Belastung (typisch 42-Tage-Zeithorizont).
  final double chronicLoad;

  /// Differenz aus chronischer und akuter Last (Chronic - Acute).
  ///
  /// Wichtig: Rein deskriptive Kennzahl! Keine voreilige Diagnose wie «überlastet» oder «Formpeak».
  final double loadBalance;

  /// Experimentelles, rein deskriptives Verhältnis (Acute / Chronic).
  ///
  /// WICHTIG: Kein Sicherheits- oder Verletzungsfilter!
  final double? experimentalAcwr;

  /// Semantische Klassifikation des Tages (bestätigter Ruhetag, Trainingstag, unbekannter Tag).
  final DayClassification classification;

  /// Datenkonfidenz dieses Tageszustands (sinkt bei unbekannten Tagen).
  final double confidence;

  bool get isUnknownDay => classification == DayClassification.unknownDay;
  bool get isConfirmedRestDay =>
      classification == DayClassification.confirmedRestDay;
  bool get isObservedTrainingDay =>
      classification == DayClassification.observedTrainingDay;

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String().split('T').first,
    'dailyLoad': dailyLoad,
    'acuteLoad': acuteLoad,
    'chronicLoad': chronicLoad,
    'loadBalance': loadBalance,
    if (experimentalAcwr != null) 'experimentalAcwr': experimentalAcwr,
    'classification': classification.key,
    'confidence': confidence,
  };

  factory EwmaDailyState.fromJson(Map<String, dynamic> json) => EwmaDailyState(
    date: DateTime.parse((json['date'] ?? '2026-01-01').toString()),
    dailyLoad: (json['dailyLoad'] as num?)?.toDouble() ?? 0.0,
    acuteLoad: (json['acuteLoad'] as num?)?.toDouble() ?? 0.0,
    chronicLoad: (json['chronicLoad'] as num?)?.toDouble() ?? 0.0,
    loadBalance: (json['loadBalance'] as num?)?.toDouble() ?? 0.0,
    experimentalAcwr: (json['experimentalAcwr'] as num?)?.toDouble(),
    classification: DayClassification.values.firstWhere(
      (c) => c.key == json['classification'],
      orElse: () => DayClassification.observedTrainingDay,
    ),
    confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
  );
}

/// Eine homogene Zeitreihe rollierender Belastung mit strikter Methoden-Provenienz.
///
/// Verhindert die unzulässige Vermischung von Banister TRIMP, sRPE und Work kJ in einer Kurve.
class EwmaSeries {
  const EwmaSeries({
    required this.seriesId,
    required this.athleteId,
    required this.method,
    required this.unit,
    required this.version,
    this.parameters = const {},
    required this.states,
    this.confidence = 1.0,
  });

  final String seriesId;
  final String athleteId;

  /// Berechnungsmethode: z. B. 'banister_trimp', 'srpe_load', 'work_kj'.
  final String method;

  /// Einheit der Werte: z. B. 'trimp_points', 'srpe_points', 'kj'.
  final String unit;

  /// Version der Modellimplementierung.
  final String version;

  /// Verwendete Zeitkonstanten und Koeffizienten (z. B. tau_acute: 7.0, tau_chronic: 42.0).
  final Map<String, dynamic> parameters;

  /// Zeitliche Abfolge der Tageszustände.
  final List<EwmaDailyState> states;

  /// Konfidenz der Gesamtreihe.
  final double confidence;

  Map<String, dynamic> toJson() => {
    'seriesId': seriesId,
    'athleteId': athleteId,
    'method': method,
    'unit': unit,
    'version': version,
    'parameters': parameters,
    'states': states.map((s) => s.toJson()).toList(),
    'confidence': confidence,
  };

  factory EwmaSeries.fromJson(Map<String, dynamic> json) => EwmaSeries(
    seriesId: (json['seriesId'] ?? '').toString(),
    athleteId: (json['athleteId'] ?? '').toString(),
    method: (json['method'] ?? '').toString(),
    unit: (json['unit'] ?? '').toString(),
    version: (json['version'] ?? '1.0').toString(),
    parameters: (json['parameters'] as Map<String, dynamic>?) ?? const {},
    states: (json['states'] as List<dynamic>?)
            ?.map((e) => EwmaDailyState.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
    confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
  );
}

/// Konfiguration für den exponentiell gewichteten gleitenden Durchschnitt (EWMA).
class EwmaConfig {
  const EwmaConfig({
    this.timeConstantAcuteDays = 7.0,
    this.timeConstantChronicDays = 42.0,
  }) : assert(timeConstantAcuteDays > 0, 'Acute time constant must be positive'),
       assert(timeConstantChronicDays > 0, 'Chronic time constant must be positive');

  /// Zeitkonstante für akute Last in Tagen (Standard: 7 Tage).
  final double timeConstantAcuteDays;

  /// Zeitkonstante für chronische Last in Tagen (Standard: 42 Tage).
  final double timeConstantChronicDays;

  /// Glättungsfaktor alpha für diskrete Tagesschritte: alpha = 1 - e^(-1 / tau).
  double get alphaAcute => 1.0 - math.exp(-1.0 / timeConstantAcuteDays);
  double get alphaChronic => 1.0 - math.exp(-1.0 / timeConstantChronicDays);
}

/// Tracker für rollierende Belastungshistorien.
class EwmaLoadTracker {
  const EwmaLoadTracker({
    this.config = const EwmaConfig(),
  });

  final EwmaConfig config;

  /// Berechnet einen einzelnen Tagesschritt ausgehend vom vorherigen Zustand.
  ///
  /// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKE:
  /// - Ein [confirmedRestDay] führt zu mathematisch exaktem exponentiellem Abklingen:
  ///   `newAcute = previousAcute * (1 - alpha)`.
  /// - Ein [unknownDay] (Datenlücke / fehlender Sync) darf die Kurve NICHT einfach
  ///   als 0-Belastung abklingen lassen, da dies fälschlicherweise Regeneration unterstellt!
  ///   Stattdessen wird der bisherige Zustand eingefroren und die Konfidenz abgesenkt.
  EwmaDailyState step({
    required DateTime date,
    required double dailyLoad,
    required double previousAcute,
    required double previousChronic,
    DayClassification classification = DayClassification.observedTrainingDay,
    double previousConfidence = 1.0,
  }) {
    final alphaA = config.alphaAcute;
    final alphaC = config.alphaChronic;

    double newAcute;
    double newChronic;
    double stateConfidence;

    if (classification == DayClassification.unknownDay) {
      // WICHTIG: Kein stillschweigendes Abklingen an unbekannten Tagen!
      // Der Zustand wird gehalten und die Konfidenz der Historie degradiert.
      newAcute = previousAcute;
      newChronic = previousChronic;
      stateConfidence = (previousConfidence * 0.85).clamp(0.1, 1.0);
    } else if (classification == DayClassification.confirmedRestDay || (classification != DayClassification.observedTrainingDay && dailyLoad <= 0.0)) {
      // Bestätigter Ruhetag: exakter exponentieller Decay
      newAcute = previousAcute * (1.0 - alphaA);
      newChronic = previousChronic * (1.0 - alphaC);
      stateConfidence = previousConfidence;
    } else if (dailyLoad <= 0.0) {
      // Unbekannter Tag oder Nullbelastung ohne Ruhetagsbestätigung: Zustand halten, kein künstlicher Decay
      newAcute = previousAcute;
      newChronic = previousChronic;
      stateConfidence = (previousConfidence * 0.90).clamp(0.1, 1.0);
    } else {
      // Beobachteter Trainingstag: klassischer EWMA-Schritt
      newAcute = previousAcute + alphaA * (dailyLoad - previousAcute);
      newChronic = previousChronic + alphaC * (dailyLoad - previousChronic);
      stateConfidence = previousConfidence;
    }

    final balance = newChronic - newAcute;
    final acwr = newChronic > 0.001 ? newAcute / newChronic : null;

    return EwmaDailyState(
      date: DateTime.utc(date.year, date.month, date.day),
      dailyLoad: classification == DayClassification.unknownDay ? 0.0 : dailyLoad,
      acuteLoad: newAcute,
      chronicLoad: newChronic,
      loadBalance: balance,
      experimentalAcwr: acwr,
      classification: classification,
      confidence: stateConfidence,
    );
  }

  /// Berechnet den vollständigen Belastungsverlauf über eine Folge strukturierter Tageseingaben.
  List<EwmaDailyState> computeTrajectoryWithInputs({
    required List<EwmaDailyInput> inputs,
    double initialAcute = 0.0,
    double initialChronic = 0.0,
    double initialConfidence = 1.0,
  }) {
    final result = <EwmaDailyState>[];
    var currentAcute = initialAcute;
    var currentChronic = initialChronic;
    var currentConfidence = initialConfidence;

    for (final input in inputs) {
      final state = step(
        date: input.date,
        dailyLoad: input.load,
        previousAcute: currentAcute,
        previousChronic: currentChronic,
        classification: input.classification,
        previousConfidence: currentConfidence,
      );

      result.add(state);
      currentAcute = state.acuteLoad;
      currentChronic = state.chronicLoad;
      currentConfidence = state.confidence;
    }

    return result;
  }

  /// Erstellt eine vollständige, methodenreine [EwmaSeries] mit lückenloser Provenienz.
  EwmaSeries computeSeries({
    required String seriesId,
    required String athleteId,
    required String method,
    required String unit,
    required String version,
    required List<EwmaDailyInput> inputs,
    double initialAcute = 0.0,
    double initialChronic = 0.0,
    Map<String, dynamic> parameters = const {},
  }) {
    final states = computeTrajectoryWithInputs(
      inputs: inputs,
      initialAcute: initialAcute,
      initialChronic: initialChronic,
    );

    final finalConfidence = states.isEmpty ? 1.0 : states.last.confidence;

    final fullParams = {
      'timeConstantAcuteDays': config.timeConstantAcuteDays,
      'timeConstantChronicDays': config.timeConstantChronicDays,
      ...parameters,
    };

    return EwmaSeries(
      seriesId: seriesId,
      athleteId: athleteId,
      method: method,
      unit: unit,
      version: version,
      parameters: fullParams,
      states: states,
      confidence: finalConfidence,
    );
  }

  /// Berechnet den Verlauf über eine Liste von Tageslasten (Rückwärtskompatibilität).
  ///
  /// Werte von 0.0 werden standardmäßig als [confirmedRestDay] behandelt.
  List<EwmaDailyState> computeTrajectory({
    required DateTime startDate,
    required List<double> dailyLoads,
    double initialAcute = 0.0,
    double initialChronic = 0.0,
  }) {
    final inputs = <EwmaDailyInput>[];
    for (var i = 0; i < dailyLoads.length; i++) {
      final date = startDate.add(Duration(days: i));
      final load = dailyLoads[i];
      inputs.add(
        EwmaDailyInput(
          date: date,
          load: load,
          classification: load > 0.0
              ? DayClassification.observedTrainingDay
              : DayClassification.confirmedRestDay,
        ),
      );
    }

    return computeTrajectoryWithInputs(
      inputs: inputs,
      initialAcute: initialAcute,
      initialChronic: initialChronic,
    );
  }
}
