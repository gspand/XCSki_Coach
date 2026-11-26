/// A load, said the way its sport says it.
///
/// The database stores one number and one unit: `14.0` and `km/h`, or `226`
/// and `W`. Both are correct and neither is what a coach reads.
///
/// - A running coach does not think in km/h. A treadmill stage at 14 km/h is
///   **4:17 min/km**, and a zone from 11,0 to 12,3 km/h is 5:27 to 4:52 —
///   which is the form every training plan, every track session and every
///   race target is written in. Leaving the conversion to the reader means
///   leaving it to a phone calculator, once per zone boundary.
/// - A cycling coach compares **W/kg**, not watts. 226 W says nothing until
///   the athlete's mass is next to it; 226 W at 62 kg is 3,65 W/kg, and that
///   is the number that means the same thing across two athletes.
///
/// So each sport gets a second reading of the same stored value.
///
/// ## Three rules
///
/// 1. **Nothing here changes what is stored.** These are pure functions over a
///    value that stays exactly as it was persisted. The engine keeps working
///    in the unit it was given.
/// 2. **A second reading is never invented.** W/kg without a body mass is not
///    shown at all, rather than shown against a guessed mass. The function
///    returns null and the screen omits the line.
/// 3. **The primary unit stays primary.** Pace is offered beside the speed,
///    not instead of it: a treadmill is set in km/h, and a diagnostician
///    reading a protocol needs the number that was dialled in.
library;

import 'package:xc_coach/domain/diagnostics.dart';

/// Seconds per kilometre for a speed, or null when [unit] is not a speed.
double? paceSecondsPerKilometre(double value, String unit) {
  if (value <= 0) return null;
  return switch (unit) {
    LoadUnits.kilometresPerHour => 3600 / value,
    LoadUnits.metresPerSecond => 1000 / value,
    _ => null,
  };
}

/// A pace as `m:ss`, rounded to the second.
///
/// Rounded, not truncated: 4:16,6 min/km is 4:17, and a systematic downward
/// bias of up to a second per kilometre is a minute over a marathon.
String formatPace(double secondsPerKilometre) {
  final total = secondsPerKilometre.round();
  final minutes = total ~/ 60;
  final seconds = total % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Relative power as `x,xx W/kg`, or null without a usable body mass.
String? formatRelativePower(double watts, double? bodyMassKg) {
  if (bodyMassKg == null || bodyMassKg <= 0) return null;
  return '${(watts / bodyMassKg).toStringAsFixed(2).replaceAll('.', ',')} W/kg';
}

/// The second reading of a single load, or null when the sport has none.
///
/// Speed becomes pace; power becomes W/kg when the athlete's mass is known.
String? secondaryLoad(double? value, String unit, {double? bodyMassKg}) {
  final number = _secondaryNumber(value, unit, bodyMassKg: bodyMassKg);
  final suffix = secondaryLoadUnit(unit, bodyMassKg: bodyMassKg);
  return number == null || suffix == null ? null : '$number $suffix';
}

/// The bare number of a second reading, without its unit.
///
/// Split out so a range can set the unit once at the end instead of twice in
/// the middle — «2,16 W/kg – 3,35 W/kg» is not how a table column is written.
/// A table column needs the same thing: the unit belongs in the heading.
String? secondaryLoadNumber(double? value, String unit, {double? bodyMassKg}) =>
    _secondaryNumber(value, unit, bodyMassKg: bodyMassKg);

String? _secondaryNumber(double? value, String unit, {double? bodyMassKg}) {
  if (value == null) return null;
  if (LoadUnits.isPower(unit)) {
    if (bodyMassKg == null || bodyMassKg <= 0) return null;
    return (value / bodyMassKg).toStringAsFixed(2).replaceAll('.', ',');
  }
  final pace = paceSecondsPerKilometre(value, unit);
  return pace == null ? null : formatPace(pace);
}

/// The unit a second reading is given in, or null when there is none.
String? secondaryLoadUnit(String unit, {double? bodyMassKg}) {
  if (LoadUnits.isPower(unit)) {
    return bodyMassKg == null || bodyMassKg <= 0 ? null : 'W/kg';
  }
  return paceSecondsPerKilometre(1, unit) == null ? null : 'min/km';
}

/// The second reading of a *range*, as a zone table needs it.
///
/// Note the order: a **faster** pace is a **smaller** number, so a zone from
/// 11,0 to 12,3 km/h reads «5:27 – 4:53», descending. Sorting the two numbers
/// would turn every running zone back to front, and it would look right.
String? secondaryLoadRange(
  double? from,
  double? to,
  String unit, {
  double? bodyMassKg,
}) {
  final suffix = secondaryLoadUnit(unit, bodyMassKg: bodyMassKg);
  if (suffix == null) return null;
  final lower = _secondaryNumber(from, unit, bodyMassKg: bodyMassKg);
  final upper = _secondaryNumber(to, unit, bodyMassKg: bodyMassKg);
  if (lower == null && upper == null) return null;
  // «bis» und «ab» statt ≤ und ≥.
  //
  // Zwei Gruende, und der zweite ist der wichtigere. Erstens liest sich eine
  // Trainingsvorgabe in Worten besser als in Relationszeichen. Zweitens
  // enthaelt die Standardschrift eines PDF diese beiden Zeichen nicht, und
  // der Bericht muss dieselbe Zeile setzen wie der Bildschirm — sonst haetten
  // Papier und App zwei Schreibweisen fuer dieselbe Grenze.
  if (lower == null) return 'bis $upper $suffix';
  if (upper == null) return 'ab $lower $suffix';
  return '$lower – $upper $suffix';
}

/// What the second reading is called, for a column heading.
String? secondaryLoadCaption(String unit, {double? bodyMassKg}) {
  if (LoadUnits.isPower(unit)) {
    return bodyMassKg == null || bodyMassKg <= 0 ? null : 'RELATIV';
  }
  return paceSecondsPerKilometre(1, unit) == null ? null : 'TEMPO';
}
