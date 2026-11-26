/// Fremde Werte treffen auf ein bestehendes Protokoll.
///
/// ## Was hier **nicht** passiert
///
/// Es wird kein Protokoll erfunden. Die Protokolle von LaLa
/// ([test_protocol.dart](../../measurement/contracts/test_protocol.dart)) sind
/// die einzige Wahrheit; der Abgleich darf ausschliesslich sagen:
///
/// > Ich habe externe Messungen gefunden, die zu diesem Protokoll passen.
///
/// Der Unterschied ist nicht kosmetisch. Ein Importer, der sich sein Protokoll
/// aus den Messpunkten zurechtlegt, erzeugt für jeden Test ein eigenes — und
/// damit Werte, die sich nie wieder miteinander vergleichen lassen.
///
/// ## Die drei Quellen einer Stufe
///
/// ```text
///   Laktat      ← Lactate Scout          (Zeitpunkt + Wert)
///   Belastung   ← Garmin / Ercolina      (gemessen)  ─┐
///   Belastung   ← Protokoll              (nominell)  ─┴─ das eine oder das andere
///   Herzfrequenz← Garmin / Ercolina      (gemessen)
/// ```
///
/// Wo eine Aktivität vorliegt, wird die Belastung **gelesen**. Wo keine
/// vorliegt, steht die nominelle Belastung des Protokolls da — und sie ist als
/// solche gekennzeichnet ([StageLoadOrigin]). Beides in derselben Spalte
/// anzuzeigen, ohne den Unterschied zu nennen, wäre die Art von Scheinpräzision,
/// die dieses Projekt an keiner Stelle zulässt.
library;

import '../../measurement/contracts/test_protocol.dart';
import 'external_data.dart';
import 'measurement_grouping.dart';

/// Woher die Belastung einer Stufe kommt.
enum StageLoadOrigin {
  /// Aus einer Aktivität gelesen — was tatsächlich getreten wurde.
  measured,

  /// Aus dem Protokoll gerechnet — was vorgesehen **war**.
  nominal,

  /// Vom Trainer aus dem Ergometer-/Laufbanddisplay übernommen.
  manual,

  /// Unbekannt. Dann steht keine Zahl da.
  unknown,
}

/// Eine Stufe, so wie der Abgleich sie sieht.
class StageMatch {
  const StageMatch({
    required this.stageNumber,
    required this.loadOrigin,
    this.measurement,
    this.loadValue,
    this.loadUnit,
    this.heartRateBpm,
  });

  final int stageNumber;

  /// Der Laktatwert dieser Stufe. Null heisst: keine Probe für diese Stufe.
  final ExternalMeasurement? measurement;

  final double? loadValue;
  final String? loadUnit;
  final StageLoadOrigin loadOrigin;
  final int? heartRateBpm;

  bool get hasLactate => measurement != null;
}

/// Das Ergebnis eines Abgleichs — ein Vorschlag, mehr nicht.
class ProtocolMatch {
  ProtocolMatch({
    required this.protocol,
    required List<StageMatch> stages,
    required List<ExternalMeasurement> unassigned,
    this.activity,
  }) : stages = List<StageMatch>.unmodifiable(stages),
       unassigned = List<ExternalMeasurement>.unmodifiable(unassigned);

  final TestProtocol protocol;
  final List<StageMatch> stages;

  /// Werte, die zu keiner Stufe gehören — Ruhe, Aufwärmen, Erholung.
  ///
  /// Sie werden **nicht** weggeworfen. Sie werden als eigenständige
  /// Beobachtungen angelegt, mit ihrem Anlass.
  final List<ExternalMeasurement> unassigned;

  /// Der Belastungsverlauf, wo einer gefunden wurde.
  final ExternalActivity? activity;

  int get assigned => stages.where((stage) => stage.hasLactate).length;

  /// Ob jede Stufe eine Probe hat. Der Satz «Zuordnung 7/7».
  bool get isComplete => stages.isNotEmpty && assigned == stages.length;

  String get assignmentLabel => '$assigned/${stages.length}';
}

/// Gleicht eine Messreihe gegen die vorhandenen Protokolle ab.
class ProtocolMatching {
  const ProtocolMatching({
    this.sampleDelay = const Duration(seconds: 20),
    this.loadWindow = const Duration(seconds: 60),
    this.durationTolerance = const Duration(seconds: 45),
  });

  /// Wie lange nach Stufenende die Probe üblicherweise genommen wird.
  ///
  /// Zwanzig Sekunden: Ohrläppchen desinfizieren, stechen, Streifen füllen.
  /// Die Zahl verschiebt nur das Fenster, aus dem die Belastung gelesen wird —
  /// sie verändert keinen gemessenen Wert.
  final Duration sampleDelay;

  /// Wie lange das Fenster ist, aus dem die Belastung einer Stufe gelesen wird.
  ///
  /// Die letzte Minute der Stufe. Darin wird der **Median** genommen und nicht
  /// der Mittelwert: Liegt das Fenster versehentlich über einem Stufenwechsel,
  /// landet ein Median auf einer der beiden Stufen, ein Mittelwert dagegen
  /// dazwischen — auf einer Belastung, die nie gefahren wurde.
  final Duration loadWindow;

  /// Wie weit der mittlere Probenabstand von der Stufendauer abweichen darf,
  /// damit ein Protokoll überhaupt in Frage kommt.
  final Duration durationTolerance;

  /// Die Uhren zweier Geräte gehen selten gleich.
  ///
  /// Ein Laktatmessgerät, das drei Minuten vorgeht, verschiebt jede Probe um
  /// eine ganze Stufe — und dann steht neben 260 W ein Laktatwert von 240 W.
  /// Deshalb ist der Versatz ein **Griff** und keine stille Annahme: Der
  /// Bildschirm zeigt die Zuordnung, ein Mensch verschiebt sie, und was er
  /// eingestellt hat, wandert als Provenienz mit.
  ///
  /// Verändert wird dabei nichts am Messwert — nur, welche Belastung neben ihm
  /// gelesen wird.

  /// Alle Protokolle, die zu dieser Reihe passen — das beste zuerst.
  ///
  /// Leer, wenn keines passt. Dann sagt der Bildschirm das, statt das am
  /// wenigsten unpassende auszuwählen.
  List<ProtocolMatch> candidatesFor(
    MeasurementGroup group, {
    required List<TestProtocol> protocols,
    ExternalActivity? activity,
    Duration clockOffset = Duration.zero,
  }) {
    final median = group.medianInterval;
    final matches = <(ProtocolMatch, int, int)>[];

    for (final protocol in protocols) {
      if (activity != null && activity.sport != protocol.sport) continue;
      final stageDuration = Duration(seconds: protocol.stageDurationSeconds);
      if (median != null &&
          (median - stageDuration).abs() > durationTolerance) {
        continue;
      }

      final match = _match(group, protocol, activity, clockOffset);
      if (match.assigned == 0) continue;

      final loadAgreements = _loadAgreements(match, protocol);
      final durationMiss = median == null
          ? 0
          : (median - stageDuration).abs().inMilliseconds;
      matches.add((match, loadAgreements, durationMiss));
    }

    matches.sort((a, b) {
      final byAssigned = b.$1.assigned.compareTo(a.$1.assigned);
      if (byAssigned != 0) return byAssigned;
      final byLoad = b.$2.compareTo(a.$2);
      if (byLoad != 0) return byLoad;
      return a.$3.compareTo(b.$3);
    });

    return [for (final entry in matches) entry.$1];
  }

  /// Der Abgleich gegen ein **gewähltes** Protokoll.
  ///
  /// Ohne Vorauswahl und ohne Toleranzprüfung: Wer das Protokoll nennt, weiss,
  /// welches gefahren wurde. Dann prüft GIULIA nicht mehr, ob die Stufendauer
  /// dazu passt, sondern ordnet zu und zeigt, was dabei herauskommt.
  ///
  /// [candidatesFor] ist der umgekehrte Fall: dort sucht GIULIA, und dort darf
  /// es auch nichts finden.
  ProtocolMatch matchFor(
    MeasurementGroup group,
    TestProtocol protocol, {
    ExternalActivity? activity,
    Duration clockOffset = Duration.zero,
  }) => _match(group, protocol, activity, clockOffset);

  /// Ordnet die Werte einer Reihe den Stufen zu.
  ///
  /// Mit Aktivität gilt: Eine Probe gehört zu einer Stufe, wenn zum Zeitpunkt
  /// der Belastung tatsächlich belastet wurde. Ein Ruhewert vor dem Start und
  /// ein Erholungswert danach fallen damit von selbst heraus — sie werden
  /// nicht ausgeschlossen, sie sind einfach keine Stufenwerte.
  ///
  /// Ohne Aktivität ist die Reihenfolge alles, was es gibt: Der n-te Wert ist
  /// die n-te Stufe. Das ist eine Annahme, und sie steht als
  /// [StageLoadOrigin.nominal] auch so im Ergebnis.
  ProtocolMatch _match(
    MeasurementGroup group,
    TestProtocol protocol,
    ExternalActivity? activity,
    Duration clockOffset,
  ) {
    final stages = <StageMatch>[];
    final unassigned = <ExternalMeasurement>[];

    for (final measurement in group.measurements) {
      final at =
          measurement.measuredAtUtcUs +
          clockOffset.inMicroseconds -
          sampleDelay.inMicroseconds;
      if (activity != null && !activity.covers(at)) {
        unassigned.add(measurement);
        continue;
      }

      final stageNumber = stages.length + 1;
      final load = activity == null ? null : _loadAt(activity, at);
      if (activity != null && load == null) {
        unassigned.add(measurement);
        continue;
      }

      stages.add(
        StageMatch(
          stageNumber: stageNumber,
          measurement: measurement,
          loadValue: load?.value ?? protocol.loadOfStage(stageNumber),
          loadUnit: load?.unit ?? protocol.loadUnit,
          loadOrigin: load == null
              ? StageLoadOrigin.nominal
              : StageLoadOrigin.measured,
          heartRateBpm: load?.heartRateBpm ?? measurement.heartRateBpm,
        ),
      );
    }

    return ProtocolMatch(
      protocol: protocol,
      stages: stages,
      unassigned: unassigned,
      activity: activity,
    );
  }

  /// Die Belastung am Ende einer Stufe — Median des letzten Fensters.
  ({double value, String unit, int? heartRateBpm})? _loadAt(
    ExternalActivity activity,
    int atUtcUs,
  ) {
    final from = atUtcUs - loadWindow.inMicroseconds;
    final inside = [
      for (final sample in activity.samples)
        if (sample.atUtcUs >= from && sample.atUtcUs <= atUtcUs) sample,
    ];
    if (inside.isEmpty) return null;

    final loads = [for (final sample in inside) sample.loadValue]..sort();
    final middle = loads.length ~/ 2;
    final median = loads.length.isOdd
        ? loads[middle]
        : (loads[middle - 1] + loads[middle]) / 2;

    // Die Herzfrequenz zu **dieser** Belastung, spätestmöglich im Fenster.
    //
    // Nicht schlicht der letzte Wert: Liegt das Fenster über einem
    // Stufenwechsel, gehört sein letzter Punkt schon zur nächsten Stufe, und
    // dann stünde neben 220 W die Herzfrequenz von 240 W. Der Median hat sich
    // für eine Seite entschieden — die Herzfrequenz folgt ihr.
    final tolerance = median.abs() * 0.05;
    int? heartRate;
    for (final sample in inside) {
      if ((sample.loadValue - median).abs() <= tolerance) {
        heartRate = sample.heartRateBpm ?? heartRate;
      }
    }

    return (value: median, unit: inside.last.loadUnit, heartRateBpm: heartRate);
  }

  /// Wie viele Stufen die Belastung tragen, die das Protokoll vorsieht.
  ///
  /// Nur ein Rangkriterium unter mehreren — eine Abweichung ist kein Fehler.
  /// Wer die dritte Stufe zwanzig Watt zu hoch gefahren hat, hat trotzdem
  /// diesen Test gefahren, und die **gemessene** Belastung bleibt die, die
  /// gilt.
  int _loadAgreements(ProtocolMatch match, TestProtocol protocol) {
    if (match.activity == null) return 0;
    final tolerance = protocol.increment / 2;
    var agreements = 0;
    for (final stage in match.stages) {
      final expected = protocol.loadOfStage(stage.stageNumber);
      final actual = stage.loadValue;
      if (actual != null && (actual - expected).abs() <= tolerance) {
        agreements++;
      }
    }
    return agreements;
  }
}
