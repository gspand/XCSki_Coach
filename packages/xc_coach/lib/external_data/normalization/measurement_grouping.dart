/// Aus einzelnen Werten wird eine Messreihe — als **Vorschlag**.
///
/// ## Die Regel, die alles andere bestimmt
///
/// > GIULIA erfindet keinen Test.
///
/// Was hier entsteht, ist eine Vermutung mit ihrer Begründung, und ein Mensch
/// bestätigt sie. Ein Importer, der aus sechs Werten still einen Stufentest
/// anlegt, produziert im ersten Monat Begeisterung und danach einen Bestand,
/// dem niemand mehr traut: Irgendwann sind zwei Ruhewerte und vier
/// Trainingsproben ein «Stufentest», und die Schwelle daraus steht in einem
/// Bericht.
///
/// ## Woran die Zugehörigkeit erkannt wird, in dieser Reihenfolge
///
/// 1. **Das Gerät hat es selbst gesagt.** Der Lactate Scout kann die Werte
///    eines Stufentests zusammenhängend ablegen. Liegt diese Angabe vor, wird
///    nicht gerechnet, sondern gelesen — [GroupOrigin.deviceMarking].
/// 2. **Die Abstände.** Ohne Markierung bleibt die Zeit. Werte, zwischen denen
///    keine grössere Lücke als [maxGap] liegt, gehören zusammen —
///    [GroupOrigin.timing].
///
/// Was die Reihe **ist**, entscheidet diese Datei nicht. Ob sie zu einem
/// Protokoll passt, steht in [ProtocolMatching](protocol_matching.dart); dort
/// kommt die Belastung dazu.
library;

import 'external_data.dart';

/// Warum diese Werte als zusammengehörig gelten.
enum GroupOrigin {
  /// Das Gerät selbst hat sie zusammen abgelegt. Die stärkste Aussage, die es
  /// gibt — hier wird nichts geschätzt.
  deviceMarking,

  /// Aus den Zeitabständen geschlossen. Eine Vermutung, und sie wird als
  /// solche angezeigt.
  timing,
}

/// Eine zusammenhängende Reihe fremder Werte.
class MeasurementGroup {
  MeasurementGroup({
    required this.origin,
    required List<ExternalMeasurement> measurements,
  }) : measurements = List<ExternalMeasurement>.unmodifiable(
         measurements.toList()
           ..sort((a, b) => a.measuredAtUtcUs.compareTo(b.measuredAtUtcUs)),
       ),
       assert(measurements.isNotEmpty, 'Eine leere Reihe ist keine Reihe.');

  final GroupOrigin origin;

  /// Die Werte, zeitlich aufsteigend.
  final List<ExternalMeasurement> measurements;

  int get startedAtUtcUs => measurements.first.measuredAtUtcUs;
  int get endedAtUtcUs => measurements.last.measuredAtUtcUs;
  int get count => measurements.length;

  Duration get span => Duration(microseconds: endedAtUtcUs - startedAtUtcUs);

  /// Die Abstände zwischen aufeinanderfolgenden Werten.
  List<Duration> get intervals => [
    for (var i = 1; i < measurements.length; i++)
      Duration(
        microseconds:
            measurements[i].measuredAtUtcUs -
            measurements[i - 1].measuredAtUtcUs,
      ),
  ];

  /// Der mittlere Abstand — null bei einem einzelnen Wert.
  ///
  /// Der erste Hinweis auf eine Stufendauer, aber nur ein Hinweis: Er wird in
  /// [ProtocolMatching] gegen die tatsächlichen Protokolle geprüft und nie
  /// selbst zu einem Protokoll erhoben.
  Duration? get medianInterval {
    final gaps = intervals;
    if (gaps.isEmpty) return null;
    final sorted = gaps.map((gap) => gap.inMicroseconds).toList()..sort();
    final middle = sorted.length ~/ 2;
    return Duration(
      microseconds: sorted.length.isOdd
          ? sorted[middle]
          : (sorted[middle - 1] + sorted[middle]) ~/ 2,
    );
  }

  /// Ob die Abstände gleichmässig genug für einen Stufentest sind.
  ///
  /// Gleichmässig heisst: Kein Abstand weicht um mehr als [tolerance] vom
  /// mittleren ab. Eine Blutentnahme dauert bei dem einen zwanzig Sekunden
  /// und bei dem nächsten vierzig — deshalb ist die Vorgabe grosszügig.
  bool isRegular({Duration tolerance = const Duration(seconds: 75)}) {
    final median = medianInterval;
    if (median == null) return false;
    return intervals.every((gap) => (gap - median).abs() <= tolerance);
  }
}

/// Schneidet eine Übertragung in Reihen.
class MeasurementGrouping {
  const MeasurementGrouping({
    this.maxGap = const Duration(minutes: 15),
    this.minimumForSeries = 3,
  });

  /// Die grösste Lücke, die eine Reihe noch überbrückt.
  ///
  /// Fünfzehn Minuten: Die längste übliche Stufendauer liegt bei fünf, ein
  /// Erholungswert kommt bis zu zehn Minuten nach der letzten Stufe. Der
  /// Ruhewert vom Morgen liegt Stunden entfernt und fällt nicht darunter.
  final Duration maxGap;

  /// Ab wie vielen Werten eine Reihe überhaupt als Reihe gilt.
  ///
  /// Drei: Aus zwei Werten lässt sich keine Kurve lesen, und ein Vorschlag
  /// «vermutlicher Stufentest» wäre bei zweien eine Behauptung.
  final int minimumForSeries;

  /// Alle Reihen einer Übertragung, zeitlich aufsteigend.
  ///
  /// Werte, die zu keiner Reihe gehören, kommen als Reihe der Länge eins
  /// zurück. Sie verschwinden nicht: Ein einzelner Ruhewert ist eine gültige
  /// Beobachtung und wird später auch als solche gespeichert.
  List<MeasurementGroup> groupsOf(List<ExternalMeasurement> measurements) {
    if (measurements.isEmpty) return const [];

    final marked = <String, List<ExternalMeasurement>>{};
    final loose = <ExternalMeasurement>[];
    for (final measurement in measurements) {
      final marking = measurement.deviceMarking;
      if (marking == null || marking.isEmpty) {
        loose.add(measurement);
      } else {
        marked.putIfAbsent(marking, () => []).add(measurement);
      }
    }

    final groups = <MeasurementGroup>[
      for (final entry in marked.entries)
        MeasurementGroup(
          origin: GroupOrigin.deviceMarking,
          measurements: entry.value,
        ),
    ];

    loose.sort((a, b) => a.measuredAtUtcUs.compareTo(b.measuredAtUtcUs));
    var open = <ExternalMeasurement>[];
    for (final measurement in loose) {
      if (open.isNotEmpty) {
        final gap = Duration(
          microseconds: measurement.measuredAtUtcUs - open.last.measuredAtUtcUs,
        );
        if (gap > maxGap) {
          groups.add(
            MeasurementGroup(origin: GroupOrigin.timing, measurements: open),
          );
          open = <ExternalMeasurement>[];
        }
      }
      open.add(measurement);
    }
    if (open.isNotEmpty) {
      groups.add(
        MeasurementGroup(origin: GroupOrigin.timing, measurements: open),
      );
    }

    return groups..sort((a, b) => a.startedAtUtcUs.compareTo(b.startedAtUtcUs));
  }

  /// Ob diese Reihe überhaupt als Stufentest vorgeschlagen werden darf.
  ///
  /// Eine vom Gerät markierte Reihe darf es immer: Dort steht die Zugehörigkeit
  /// schon fest, und GIULIA hat sie nicht erfunden. Eine aus Zeitabständen
  /// geschlossene Reihe braucht genug Werte **und** gleichmässige Abstände.
  bool mayBeSuggestedAsTest(MeasurementGroup group) =>
      group.origin == GroupOrigin.deviceMarking
      ? group.count >= 2
      : group.count >= minimumForSeries && group.isRegular();
}
