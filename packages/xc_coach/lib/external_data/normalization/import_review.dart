/// Was ein Mensch am Vorschlag noch ändern darf, bevor daraus ein Test wird.
///
/// ## Die Regel, die dieses Modul trägt
///
/// > Der Originalwert wird nie überschrieben.
///
/// Eine Korrektur ist ein **zweiter** Wert neben dem ersten, mit Begründung und
/// Urheber. Das ist keine Umständlichkeit: Ein Laktatwert von 8,7, der zu 6,7
/// korrigiert wurde, ist eine andere Tatsache als ein gemessener 6,7. Wer in
/// zwei Jahren über tausend Tests hinweg auswertet, muss beide auseinander
/// halten können — sonst wird aus jeder Korrektur eine Messung.
///
/// Dieselbe Haltung steckt schon in
/// [correctStageData](../../database/diagnostics_repository.dart): Die Korrektur
/// ist dort eine eigene Zeile, und die Auswertung liest
/// `COALESCE(korrigiert, original)`. Dieses Modul ist die Vorstufe davon — der
/// Zustand, den der Bildschirm hält, bevor irgendetwas gespeichert wird.
///
/// ## «Löschen» gibt es nicht
///
/// Ein Wert, den jemand für unbrauchbar hält, wird **ausgeschlossen**. Er bleibt
/// erhalten, geht in keine Auswertung ein und trägt den Grund. Ein gelöschter
/// Messwert dagegen ist eine Messung, die stattgefunden hat und über die
/// niemand mehr etwas sagen kann.
library;

import '../../domain/diagnostics.dart';
import '../../measurement/contracts/test_protocol.dart';
import 'external_data.dart';
import 'protocol_matching.dart';

/// Was mit einem Wert geschehen soll.
enum ReviewDecision {
  /// So übernehmen, wie das Gerät ihn geliefert hat.
  accept,

  /// Übernehmen, aber mit einem anderen Zahlwert — und einer Begründung.
  correct,

  /// Nicht auswerten. Der Wert bleibt erhalten und trägt den Grund.
  exclude,
}

/// Warum ein Wert korrigiert oder ausgeschlossen wurde.
///
/// Eine Aufzählung und kein Freitext, weil sich das später auswerten lassen
/// soll: Wie oft ein Teststreifen versagt, ist eine Frage, die ein Bestand
/// beantworten kann — wenn der Grund einen Namen hat. Der Freitext kommt
/// zusätzlich dazu, nicht statt dessen.
enum ReviewReason {
  /// Der Streifen, die Probe oder die Entnahme war fehlerhaft.
  measurementError('Messfehler'),

  /// Beim Abtippen verrutscht.
  transcriptionError('Übertragungsfehler'),

  /// Der Wert gehört zu einer anderen Stufe.
  wrongStage('Falsche Stufe zugeordnet'),

  /// Der Wert gehört gar nicht zu diesem Test.
  notPartOfTest('Gehört nicht zum Test'),

  /// Etwas anderes — dann trägt der Freitext die Erklärung.
  other('Anderer Grund');

  const ReviewReason(this.label);
  final String label;
}

/// Eine Stufe im Prüfbildschirm.
class ReviewedStage {
  const ReviewedStage({
    required this.stageNumber,
    required this.loadOrigin,
    this.measurement,
    this.loadValue,
    this.loadUnit,
    this.heartRateBpm,
    this.rpe,
    this.decision = ReviewDecision.accept,
    this.correctedValue,
    this.reason,
    this.note,
  });

  ReviewedStage.of(StageMatch match)
    : stageNumber = match.stageNumber,
      loadOrigin = match.loadOrigin,
      measurement = match.measurement,
      loadValue = match.loadValue,
      loadUnit = match.loadUnit,
      heartRateBpm = match.heartRateBpm,
      rpe = null,
      decision = ReviewDecision.accept,
      correctedValue = null,
      reason = null,
      note = null;

  final int stageNumber;
  final ExternalMeasurement? measurement;
  final double? loadValue;
  final String? loadUnit;
  final StageLoadOrigin loadOrigin;
  final int? heartRateBpm;
  final int? rpe;

  final ReviewDecision decision;

  /// Der Wert, den ein Mensch statt des gemessenen gelten lassen will.
  final double? correctedValue;

  final ReviewReason? reason;

  /// Was darüber hinaus zu sagen war.
  final String? note;

  /// Was das Gerät geliefert hat. Bleibt unverändert, immer.
  double? get originalValue => measurement?.value;

  /// Der Wert, der in die Auswertung geht. Null, wo ausgeschlossen wurde.
  double? get acceptedValue => switch (decision) {
    ReviewDecision.exclude => null,
    ReviewDecision.correct => correctedValue,
    ReviewDecision.accept => originalValue,
  };

  bool get isCorrected =>
      decision == ReviewDecision.correct && correctedValue != originalValue;

  bool get countsForAnalysis => acceptedValue != null;

  /// Dieselbe Stufe unter neuer Nummer.
  ///
  /// Eine **gemessene** Belastung bleibt unverändert: Sie ist gefahren worden,
  /// egal welche Nummer die Stufe trägt. Eine nominelle wird neu gerechnet,
  /// weil sie aus der Nummer stammt.
  ReviewedStage _renumbered(int stageNumber, TestProtocol protocol) =>
      ReviewedStage(
        stageNumber: stageNumber,
        loadOrigin: loadOrigin,
        measurement: measurement,
        loadValue: loadOrigin == StageLoadOrigin.nominal
            ? protocol.loadOfStage(stageNumber)
            : loadValue,
        loadUnit: loadUnit,
        heartRateBpm: heartRateBpm,
        rpe: rpe,
        decision: decision,
        correctedValue: correctedValue,
        reason: reason,
        note: note,
      );

  ReviewedStage _with({
    ReviewDecision? decision,
    double? correctedValue,
    ReviewReason? reason,
    String? note,
    ExternalMeasurement? measurement,
    bool clearMeasurement = false,
  }) => ReviewedStage(
    stageNumber: stageNumber,
    loadOrigin: loadOrigin,
    measurement: clearMeasurement ? null : (measurement ?? this.measurement),
    loadValue: loadValue,
    loadUnit: loadUnit,
    heartRateBpm: heartRateBpm,
    rpe: rpe,
    decision: decision ?? this.decision,
    correctedValue: decision == ReviewDecision.accept
        ? null
        : (correctedValue ?? this.correctedValue),
    reason: decision == ReviewDecision.accept ? null : (reason ?? this.reason),
    note: decision == ReviewDecision.accept ? null : (note ?? this.note),
  );
}

/// Der Zustand des Prüfbildschirms.
///
/// Unveränderlich: Jeder Griff gibt einen neuen Zustand zurück. Damit lässt
/// sich der ganze Ablauf ohne Oberfläche prüfen — und die Oberfläche kann
/// zurücknehmen, ohne etwas rückgängig rechnen zu müssen.
class ImportReview {
  ImportReview({
    required this.protocol,
    required List<ReviewedStage> stages,
    required List<ExternalMeasurement> separate,
    this.activity,
    this.clockOffset = Duration.zero,
    this.sampleSite = LactateSampleSite.unknown,
  }) : stages = List<ReviewedStage>.unmodifiable(stages),
       separate = List<ExternalMeasurement>.unmodifiable(separate);

  /// Der Vorschlag als Ausgangszustand.
  factory ImportReview.of(
    ProtocolMatch match, {
    Duration clockOffset = Duration.zero,
    LactateSampleSite sampleSite = LactateSampleSite.unknown,
  }) => ImportReview(
    protocol: match.protocol,
    stages: [for (final stage in match.stages) ReviewedStage.of(stage)],
    separate: match.unassigned,
    activity: match.activity,
    clockOffset: clockOffset,
    sampleSite: sampleSite,
  );

  final TestProtocol protocol;
  final List<ReviewedStage> stages;

  /// Werte, die zu keiner Stufe gehören. Sie werden als eigenständige
  /// Beobachtungen angelegt — Ruhe, Aufwärmen, Erholung.
  final List<ExternalMeasurement> separate;

  final ExternalActivity? activity;

  /// Der eingestellte Uhrenversatz zwischen den beiden Geräten.
  final Duration clockOffset;
  final LactateSampleSite sampleSite;

  /// Wie viele Stufen einen auswertbaren Wert tragen.
  int get evaluableStages =>
      stages.where((stage) => stage.countsForAnalysis).length;

  /// Ob daraus ein Test werden darf.
  ///
  /// Drei auswertbare Stufen: Unter drei Punkten ist jede Schwellenbestimmung
  /// eine Linie durch zwei Punkte, und die trägt keine Aussage. Dieselbe
  /// Untergrenze wie im gemessenen Stufentest.
  bool get mayBeEvaluated => evaluableStages >= 3;

  ImportReview _replace(int stageNumber, ReviewedStage replacement) =>
      ImportReview(
        protocol: protocol,
        stages: [
          for (final stage in stages)
            if (stage.stageNumber == stageNumber) replacement else stage,
        ],
        separate: separate,
        activity: activity,
        clockOffset: clockOffset,
        sampleSite: sampleSite,
      );

  ReviewedStage? stage(int stageNumber) {
    for (final stage in stages) {
      if (stage.stageNumber == stageNumber) return stage;
    }
    return null;
  }

  /// Einen Wert durch einen anderen ersetzen — der ursprüngliche bleibt.
  ImportReview correct(
    int stageNumber, {
    required double value,
    required ReviewReason reason,
    String? note,
  }) {
    final target = stage(stageNumber);
    if (target == null) return this;
    return _replace(
      stageNumber,
      target._with(
        decision: ReviewDecision.correct,
        correctedValue: value,
        reason: reason,
        note: note,
      ),
    );
  }

  /// Einen Wert aus der Auswertung nehmen. Gelöscht wird er nicht.
  ImportReview exclude(
    int stageNumber, {
    required ReviewReason reason,
    String? note,
  }) {
    final target = stage(stageNumber);
    if (target == null) return this;
    return _replace(
      stageNumber,
      target._with(
        decision: ReviewDecision.exclude,
        reason: reason,
        note: note,
      ),
    );
  }

  /// Eine Entscheidung zurücknehmen.
  ImportReview accept(int stageNumber) {
    final target = stage(stageNumber);
    if (target == null) return this;
    return _replace(stageNumber, target._with(decision: ReviewDecision.accept));
  }

  /// Ergänzt das, was der Scout nicht wissen kann: tatsächlich gefahrene
  /// Last, manuell abgelesene Herzfrequenz und subjektive Belastung.
  ImportReview updateStageFacts(
    int stageNumber, {
    required double loadValue,
    required int? heartRateBpm,
    required int? rpe,
  }) {
    final target = stage(stageNumber);
    if (target == null) return this;
    return _replace(
      stageNumber,
      ReviewedStage(
        stageNumber: target.stageNumber,
        loadOrigin: StageLoadOrigin.manual,
        measurement: target.measurement,
        loadValue: loadValue,
        loadUnit: target.loadUnit,
        heartRateBpm: heartRateBpm,
        rpe: rpe,
        decision: target.decision,
        correctedValue: target.correctedValue,
        reason: target.reason,
        note: target.note,
      ),
    );
  }

  ImportReview withSampleSite(LactateSampleSite site) => ImportReview(
    protocol: protocol,
    stages: stages,
    separate: separate,
    activity: activity,
    clockOffset: clockOffset,
    sampleSite: site,
  );

  /// Einen Wert aus dem Test herausnehmen — er ist gar keine Stufe.
  ///
  /// Der Fall, den nur ein Mensch entscheiden kann: Ohne gemessene Aktivität
  /// hat GIULIA nichts, woran es einen Ruhewert von einem Stufenwert
  /// unterscheiden könnte. Der Scout liefert Uhrzeit und Laktat, sonst nichts;
  /// die Reihenfolge ist alles, was bleibt, und die erste Probe ist eben nicht
  /// immer die erste Stufe.
  ///
  /// Deshalb werden die übrigen Stufen **neu durchnummeriert**. Bliebe der
  /// Ruhewert Stufe 1, stünde der ganze Test um eine Stufe verschoben da — und
  /// die Schwelle läge bei der falschen Belastung. Gemessene Belastungen
  /// bleiben dabei, was sie sind; nur die nominellen folgen der neuen Nummer,
  /// weil sie aus ihr stammen.
  ImportReview notPartOfTest(int stageNumber) {
    final target = stage(stageNumber);
    final measurement = target?.measurement;
    if (target == null || measurement == null) return this;

    final remaining = [
      for (final stage in stages)
        if (stage.stageNumber != stageNumber) stage,
    ];

    return ImportReview(
      protocol: protocol,
      stages: [
        for (final (index, stage) in remaining.indexed)
          stage._renumbered(index + 1, protocol),
      ],
      separate: [...separate, measurement]
        ..sort((a, b) => a.measuredAtUtcUs.compareTo(b.measuredAtUtcUs)),
      activity: activity,
      clockOffset: clockOffset,
      sampleSite: sampleSite,
    );
  }

  /// Einen Wert einer anderen Stufe zuordnen.
  ///
  /// Der häufigste echte Fehler beim Import: Eine Probe wurde eine Stufe zu
  /// spät genommen und liegt deshalb im falschen Fenster. Beide Stufen ändern
  /// sich dabei — die eine verliert ihren Wert, die andere bekommt ihn — und
  /// beide tragen danach den Grund.
  ///
  /// Die Zielstufe muss frei sein. Zwei Laktatwerte auf einer Stufe wären eine
  /// Aussage, die das Protokoll nicht kennt.
  ImportReview moveToStage(int from, int to, {String? note}) {
    final source = stage(from);
    final target = stage(to);
    if (source == null || target == null) return this;
    if (source.measurement == null || target.measurement != null) return this;

    return ImportReview(
      protocol: protocol,
      stages: [
        for (final stage in stages)
          if (stage.stageNumber == from)
            stage._with(
              clearMeasurement: true,
              decision: ReviewDecision.exclude,
              reason: ReviewReason.wrongStage,
              note: note ?? 'Wert zu Stufe $to verschoben.',
            )
          else if (stage.stageNumber == to)
            stage._with(
              measurement: source.measurement,
              decision: ReviewDecision.correct,
              correctedValue: source.acceptedValue,
              reason: ReviewReason.wrongStage,
              note: note ?? 'Wert von Stufe $from übernommen.',
            )
          else
            stage,
      ],
      separate: separate,
      activity: activity,
      clockOffset: clockOffset,
      sampleSite: sampleSite,
    );
  }
}
