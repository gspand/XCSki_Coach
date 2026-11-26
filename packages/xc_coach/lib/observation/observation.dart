/// Eine Beobachtung — ein Wert, den jemand an einem bestimmten Punkt
/// festgehalten hat.
///
/// ```text
///   Training ──▶  Observation  ◀── LaLa
/// ```
///
/// ## Warum ein eigenes Modul
///
/// Weil dieselbe Beobachtung in drei Zusammenhängen entsteht und bisher drei
/// verschiedene Speicherwege hatte: Laktat im Stufentest hing an
/// `performance_test`, RPE an `test_stage`, und für eine normale
/// Trainingseinheit gab es überhaupt keinen Ort. Wer während einer
/// Schwelleneinheit zwei Werte nimmt, konnte sie nicht festhalten.
///
/// Die Regel des Projekts bleibt dieselbe wie bei den Messverträgen:
///
/// > Observation beschreibt eine konkrete Beobachtung im Kontext.
/// > LaLa interpretiert sie.
///
/// Deshalb ist dieses Modul reines Dart und kennt weder Gerät noch Diagnostik.
/// Es liegt **neben** `measurement/contracts/` und nicht darin: Messverträge
/// halten fest, was die Messkette erfasst hat; eine Beobachtung entsteht,
/// weil ein Mensch ein Ohrläppchen sticht oder eine Zahl auf einer Skala
/// nennt.
///
/// ## Was hier nicht steht
///
/// Kein freier Merkmalsbeutel. Was eine Beobachtung trägt, hat einen Namen und
/// einen Typ — sonst landet dort innerhalb eines Jahres alles, was gerade
/// keinen Platz hatte, und niemand kann mehr auswerten, was drinsteht. Kommt
/// ein Merkmal dazu, bekommt es ein Feld.
library;

/// Woran eine Beobachtung hängt.
///
/// Alle Bezüge sind einzeln optional, weil sie unabhängig voneinander
/// auftreten: Laktat in einer freien Einheit hat nur eine Sitzung; Laktat in
/// einem Stufentest hat Test und Stufe; ein Wert nach dem dritten Intervall
/// hat Sitzung und Intervall. Ein Wert ganz ohne Bezug ist erlaubt — die
/// Ruhemessung am Morgen gehört zu niemandem als zum Athleten selbst.
class ObservationContext {
  const ObservationContext({
    this.sessionId,
    this.intervalRecordId,
    this.testId,
    this.testStageId,
  });

  /// Die Trainingseinheit.
  final String? sessionId;

  /// Der Abschnitt darin — ein Intervall eines Workouts.
  final String? intervalRecordId;

  /// Der Leistungstest.
  final String? testId;

  /// Die Stufe darin.
  final String? testStageId;

  bool get isEmpty =>
      sessionId == null &&
      intervalRecordId == null &&
      testId == null &&
      testStageId == null;

  /// Ob diese Beobachtung zu einem Stufentest gehört.
  bool get belongsToTest => testId != null;
}

/// Was beobachtet wurde.
enum ObservationType {
  /// Blutlaktat in mmol/l.
  lactate,

  /// Subjektives Belastungsempfinden.
  rpe,

  /// Eine Bemerkung ohne Zahl.
  note;

  /// Die Einheit, in der dieser Typ gemessen wird. Leer, wo es keine gibt.
  String get canonicalUnit => switch (this) {
    lactate => 'mmol/l',
    rpe => '',
    note => '',
  };

  bool get hasValue => this != note;
}

/// Woher der Wert kommt.
enum ObservationSource {
  /// Ein Mensch hat ihn eingetragen.
  manual,

  /// Ein Gerät hat ihn geliefert.
  device,

  /// Aus einem fremden Bericht oder System übernommen.
  imported,
}

/// Wie belastbar er ist.
enum ObservationQuality {
  /// Regulär erfasst.
  recorded,

  /// Mit Vorbehalt — die Umstände waren nicht sauber.
  doubtful,

  /// Nachträglich als unbrauchbar markiert. Bleibt erhalten, geht nicht in
  /// Auswertungen ein.
  rejected;

  bool get usable => this != rejected;
}

/// Eine Beobachtung.
class Observation {
  const Observation({
    required this.id,
    required this.athleteId,
    required this.observedAtUtcUs,
    required this.type,
    required this.context,
    this.value,
    this.text,
    this.unit,
    this.source = ObservationSource.manual,
    this.quality = ObservationQuality.recorded,
    this.recordedByUserId,
    this.timeSinceLoadEndSeconds,
    this.occasion,
    this.sampleSite,
  });

  final String id;
  final String athleteId;

  /// Wann beobachtet wurde — nicht, wann jemand es eingetippt hat.
  final int observedAtUtcUs;

  final ObservationType type;
  final ObservationContext context;

  /// Der Zahlwert, wo es einen gibt.
  final double? value;

  /// Der Text, wo es einen gibt.
  final String? text;

  /// Die Einheit. Null bedeutet: die übliche des Typs.
  final String? unit;

  final ObservationSource source;
  final ObservationQuality quality;
  final String? recordedByUserId;

  /// Sekunden zwischen Belastungsende und Entnahme.
  ///
  /// Für Laktat der wichtigste Zusatzwert überhaupt: 3,8 mmol/l eine Minute
  /// nach Belastungsende und 3,8 mmol/l nach fünf Minuten sind zwei
  /// verschiedene Aussagen über denselben Menschen. Ohne diesen Bezug werden
  /// Vergleiche über Wochen irreführend, ohne dass es auffällt.
  final int? timeSinceLoadEndSeconds;

  /// Der Anlass der Entnahme — Ruhe, Aufwärmen, Stufe, nach Belastung,
  /// Erholung, Stichprobe.
  ///
  /// Nicht dasselbe wie [context]: Der eine sagt, **woran** die Beobachtung
  /// hängt, der andere, **warum** sie genommen wurde. Für die Auswertung ist
  /// der Unterschied wesentlich — ein Ruhewert und ein Stufenwert stehen
  /// nebeneinander in derselben Messung und bedeuten Verschiedenes.
  ///
  /// Als Zeichenkette, weil die Liste je Verfahren abweicht.
  final String? occasion;

  /// Entnahmestelle, wo eine gestochen wurde. Als Zeichenkette, weil die Liste
  /// je Labor abweicht und eine Aufzählung hier nur festschriebe, was das
  /// Projekt gerade kennt.
  final String? sampleSite;

  /// Die Einheit, in der dieser Wert steht.
  String get effectiveUnit => unit ?? type.canonicalUnit;

  /// Ob dieser Wert in eine Auswertung eingehen darf.
  bool get countsForAnalysis =>
      quality.usable && (value != null || text != null);
}
