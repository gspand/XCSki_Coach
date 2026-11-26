/// Stored identifiers, said in the language of the people reading them.
///
/// The database keeps `cycling`, `manual` and `cycling_step_120w_20w_3min`
/// because those are stable keys: they survive a translation, a rename and a
/// migration. A screen that prints them raw hands the reader the key instead
/// of the fact — and a coach reading «cycling_step_120w_20w_3min…», cut off by
/// the column width, learns nothing at all.
///
/// This file is the one place where a key becomes a word. Two rules keep it
/// honest:
///
/// 1. **An unknown key is never swallowed.** It is shown, tidied but intact,
///    so an unmapped value looks like a gap in this table rather than like a
///    fact about the test.
/// 2. **Nothing here changes what is stored.** These functions are read-only
///    presentation; the key stays the key.
library;

import '../measurement/contracts/test_protocol.dart';
import 'package:xc_coach/domain/diagnostics.dart';

/// The sport of a test, as it is spoken.
String sportLabel(String sport) => switch (sport) {
  'cycling' => 'Radfahren',
  'running' => 'Laufen',
  'rowing' => 'Rudern',
  'langlauf' => 'Skilanglauf',
  'swimming' => 'Schwimmen',
  // A test recorded without a sport is not a sport called "generic".
  'generic' => 'Ohne Sportartbindung',
  _ => _humanise(sport),
};

/// Where the numbers came from.
///
/// This is a provenance statement, not a technical detail: whether a value was
/// typed in or measured by a device changes how much weight it carries.
String measurementSourceLabel(MeasurementSource source) => switch (source) {
  MeasurementSource.manual => 'Manuell eingegeben',
  MeasurementSource.ercolina => 'Mit Ercolina gemessen',
  MeasurementSource.imported => 'Importiert',
  MeasurementSource.externalDevice => 'Fremdgerät',
};

/// The protocol under its own name, taken from the preset that defines it.
///
/// The presets are the single source for protocol names ([testProtocols]),
/// so a renamed protocol is renamed here too, without a second table to forget.
String protocolLabel(String protocolId) {
  for (final preset in testProtocols) {
    if (preset.id == protocolId) return preset.name;
  }
  return _humanise(protocolId);
}

/// A stored key made readable without pretending to know what it means.
///
/// `cycling_step_20w_2min` becomes «Cycling step 20w 2min»: still visibly a
/// key, but no longer a wall of underscores.
String _humanise(String key) {
  if (key.isEmpty) return key;
  final words = key.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  return words.isEmpty ? key : words[0].toUpperCase() + words.substring(1);
}
