/// Was von aussen kommt — bevor GIULIA es deutet.
///
/// ## Warum es diese Schicht gibt
///
/// Ein Lactate Scout liefert Laktatwerte mit Zeitstempeln. Eine Garmin-Uhr
/// liefert eine Aktivität mit Leistung und Herzfrequenz. Ein Wahoo-Trainer
/// liefert dasselbe auf einem anderen Weg. Keines der drei darf als solches in
/// den LaLa-Kern gelangen: Sonst hängt die Auswertung eines Stufentests
/// irgendwann daran, welches Gerät sie geliefert hat, und der Satz «dieselbe
/// Messung ergibt dasselbe Ergebnis» stimmt nicht mehr.
///
/// ```text
///   Lactate Scout ─┐
///   Garmin ────────┼─▶ external_data ─▶ Normalisierung ─▶ Observation
///   Wahoo ─────────┘                                    └─▶ MeasurementSession
///                                                             │
///                                                             ▼
///                                                          LaLa
/// ```
///
/// Deshalb ist diese Datei reines Dart: kein Funk, keine Datenbank, keine
/// Oberfläche. Sie beschreibt nur, was ein fremdes System behauptet, und
/// trennt das sichtbar von dem, was GIULIA daraus macht.
///
/// ## Was hier bewusst fehlt
///
/// Ein Ergebnis. Kein Anbieter darf eine berechnete Schwelle als GIULIA-Wert
/// einliefern — dieselbe Regel wie beim
/// [Berichtsimport](../../importing/reference_report_importer.dart). Von aussen
/// kommen Messwerte, nie Deutungen.
library;

import '../../observation/observation.dart';

/// Woher ein fremder Wert stammt.
///
/// Als Zeichenkette und nicht als Aufzählung: Die Liste der Anbieter wächst,
/// und jeder neue Anbieter soll ein Adapter sein, keine Änderung an einem
/// Kerntyp. Was hier steht, wandert unverändert in die Provenienz.
extension type const ExternalProvider(String id) {
  static const ExternalProvider lactateScout = ExternalProvider(
    'lactate_scout',
  );
  static const ExternalProvider garmin = ExternalProvider('garmin');
  static const ExternalProvider strava = ExternalProvider('strava');
  bool get isStrava => id.trim().toLowerCase() == strava.id;
  static const ExternalProvider wahoo = ExternalProvider('wahoo');

  /// Von Hand aus einem Ausdruck oder Display abgetippt.
  static const ExternalProvider transcribed = ExternalProvider('transcribed');
}

/// Ein einzelner Wert, den ein fremdes Gerät gespeichert hat.
///
/// Der Zeitpunkt ist das Wichtigste daran: Er ist das einzige, worüber sich
/// dieser Wert später mit einer Belastung zusammenbringen lässt.
class ExternalMeasurement {
  const ExternalMeasurement({
    required this.provider,
    required this.sourceId,
    required this.measuredAtUtcUs,
    required this.type,
    required this.value,
    required this.unit,
    this.deviceMarking,
    this.sequenceNumber,
    this.heartRateBpm,
    this.temperatureCelsius,
    this.rawPayloadHex,
  });

  final ExternalProvider provider;

  /// Die Kennung beim Ursprungssystem — beim Scout der Speicherplatz.
  ///
  /// Nur dafür da, denselben Wert bei einem zweiten Übertragen wiederzuerkennen
  /// und nicht doppelt anzulegen.
  final String sourceId;

  /// Wann gemessen wurde, nach der Uhr des fremden Geräts.
  ///
  /// Die Uhren zweier Geräte gehen selten gleich. Was daraus folgt, steht bei
  /// [MeasurementGrouping] — hier wird nichts zurechtgerückt.
  final int measuredAtUtcUs;

  final ObservationType type;
  final double value;
  final String unit;

  /// Was das Gerät selbst über die Zugehörigkeit sagt.
  ///
  /// Der Lactate Scout kann die Werte eines Stufentests zusammenhängend
  /// ablegen. Wo diese Angabe vorliegt, ist sie die belastbarste, die es gibt:
  /// Dann muss GIULIA nicht aus Zeitabständen **raten**, sondern liest ab.
  final String? deviceMarking;

  /// Die Position innerhalb der Markierung, wo das Gerät sie mitliefert.
  final int? sequenceNumber;

  /// Die Herzfrequenz, wo das Messgerät selbst eine mitgespeichert hat.
  ///
  /// Ein Laktatmessgerät ist keine Uhr — aber wenn es die Frequenz beim
  /// Stechen festhält, ist das die einzige, die es ohne fremde Aktivität gibt.
  /// Eine gemessene Aktivität hat Vorrang: Sie kennt den Verlauf und nicht nur
  /// den Augenblick.
  final int? heartRateBpm;

  /// Die vom Messgerät gespeicherte Probentemperatur, sofern vorhanden.
  ///
  /// Sie ist kein Eingang der Schwellenberechnung, gehört aber in die
  /// Qualitätskontrolle eines Trainers: Ein auffälliger Wert kann erklären,
  /// warum eine einzelne Probe nicht zur übrigen Kurve passt.
  final double? temperatureCelsius;

  /// Die unveränderten Bytes des Ursprungsrecords, wo es solche gibt.
  ///
  /// Hex als Text ist absichtlich unspektakulär: Es bleibt über Datenbank,
  /// Export und spätere Decoder-Versionen exakt dasselbe und behauptet keine
  /// Bedeutung für Bytes, die heute noch unbekannt sind.
  final String? rawPayloadHex;
}

/// Ein Belastungsverlauf aus einem fremden System.
///
/// Die zweite Hälfte eines Stufentests: Der Scout weiss, wie hoch das Laktat
/// war, aber nicht, wobei. Das steht hier.
enum FitFileOrigin { recordingDevice, garminConnect }

class ExternalActivity {
  const ExternalActivity({
    required this.provider,
    required this.sourceId,
    required this.sport,
    required this.startedAtUtcUs,
    required this.endedAtUtcUs,
    required this.samples,
    this.fitFileOrigin,
  });

  final FitFileOrigin? fitFileOrigin;
  bool get eligibleForCoach => !provider.isStrava &&
      (!sourceId.startsWith('fit:') || fitFileOrigin != null);
  final ExternalProvider provider;
  final String sourceId;
  final String sport;
  final int startedAtUtcUs;
  final int endedAtUtcUs;

  /// Der Verlauf, zeitlich aufsteigend.
  final List<ExternalLoadSample> samples;

  bool covers(int atUtcUs) =>
      atUtcUs >= startedAtUtcUs && atUtcUs <= endedAtUtcUs;
}

/// Ein Punkt im Belastungsverlauf.
class ExternalLoadSample {
  const ExternalLoadSample({
    required this.atUtcUs,
    required this.loadValue,
    required this.loadUnit,
    this.heartRateBpm,
    this.cadencePerMinute,
  });

  final int atUtcUs;
  final double loadValue;
  final String loadUnit;
  final int? heartRateBpm;
  final int? cadencePerMinute;
}
