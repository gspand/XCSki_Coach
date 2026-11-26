/// Correct German spelling for text that comes out of the frozen core.
///
/// ## Why this exists at all
///
/// `lib/lala/core/**` is frozen: gate C4 requires its output to stay
/// byte-identical to a recorded baseline, and that baseline contains strings
/// like «Schaetzung» and «gueltig» 264 times. Correcting them in the core is
/// not a spelling fix — it is a deliberate re-freeze of the scientific record,
/// and that is a decision with its own procedure.
///
/// Meanwhile those sentences appear on screen next to text that spells
/// «ausschließlich» and «müssen» correctly, and — since the report exists —
/// on a document that leaves the building with a federation's name near it.
///
/// So the spelling is corrected where it is *displayed*, not where it is
/// stored. The engine keeps emitting exactly what the baseline recorded; the
/// screen and the report set it in the orthography a German reader expects.
/// This is the same move [sportLabel] makes for `cycling`: the stored form is
/// a key, the shown form is language.
///
/// ## Why a word list and not a rule
///
/// A rule over `ae|oe|ue` would hit «value», «neue», «Dauer» and «zuerst». The
/// map below is explicit, and a word that is not in it passes through
/// untouched — a gap here looks like a gap, never like a corruption.
library;

/// Transliterated spellings and the words they stand for.
const Map<String, String> _spellings = <String, String>{
  'Aenderung': 'Änderung',
  'aendern': 'ändern',
  'geaendert': 'geändert',
  'abhaengig': 'abhängig',
  'unabhaengig': 'unabhängig',
  'Aktivitaet': 'Aktivität',
  'Kapazitaet': 'Kapazität',
  'Intensitaet': 'Intensität',
  'Intensitaeten': 'Intensitäten',
  'Intensitaetsdomaene': 'Intensitätsdomäne',
  'Intensitaetsdomaenen': 'Intensitätsdomänen',
  'Plausibilitaet': 'Plausibilität',
  'Qualitaet': 'Qualität',
  'Realitaet': 'Realität',
  'Zielgroesse': 'Zielgröße',
  'Kontrollgroesse': 'Kontrollgröße',
  'Groesse': 'Größe',
  'Schaetzung': 'Schätzung',
  'geschaetzt': 'geschätzt',
  'geschaetzter': 'geschätzter',
  'geschaetzte': 'geschätzte',
  'Ermuedung': 'Ermüdung',
  'Hoehe': 'Höhe',
  'hoehere': 'höhere',
  'erhoeht': 'erhöht',
  'erhoehtes': 'erhöhtes',
  'gueltig': 'gültig',
  'ungueltig': 'ungültig',
  'benoetigen': 'benötigen',
  'benoetigt': 'benötigt',
  'laengere': 'längere',
  'laenger': 'länger',
  'ueber': 'über',
  'Uebergang': 'Übergang',
  'ueberhaupt': 'überhaupt',
  'Fuer': 'Für',
  'fuer': 'für',
  'muessen': 'müssen',
  'muss': 'muss',
  'koennen': 'können',
  'moeglich': 'möglich',
  'zusaetzlich': 'zusätzlich',
  'zusaetzliche': 'zusätzliche',
  'ausschliesslich': 'ausschließlich',
  'einschliesslich': 'einschließlich',
  'aelteren': 'älteren',
  'aeltere': 'ältere',
  'Verhaeltnis': 'Verhältnis',
  'verhaeltnismaessig': 'verhältnismäßig',
  'regelmaessig': 'regelmäßig',
  'gleichmaessig': 'gleichmäßig',
  'vereinfachten': 'vereinfachten',
  'genauere': 'genauere',
  'Maximaltests': 'Maximaltests',
  'stabilisierbares': 'stabilisierbares',
  'unveraendert': 'unverändert',
  'unveraenderlich': 'unveränderlich',
  'vollstaendig': 'vollständig',
  'naechste': 'nächste',
  'Uebung': 'Übung',
  'ueblich': 'üblich',
  'zurueck': 'zurück',
};

final RegExp _word = RegExp(r'[A-Za-zÄÖÜäöüß]+');

/// Text from the frozen core, spelled the way it is read.
///
/// Idempotent, and safe on text that is already correct: a word that is not a
/// known transliteration is returned unchanged.
String germanSpelling(String text) =>
    text.replaceAllMapped(_word, (m) => _spellings[m.group(0)] ?? m.group(0)!);

/// [germanSpelling] for a value that may be absent.
String? germanSpellingOrNull(String? text) =>
    text == null ? null : germanSpelling(text);

/// Decimal points between digits, written as the comma German uses.
///
/// The core labels a method «2.0 mmol/l» because that is how a Dart double
/// prints. On a German report it has to read «2,0 mmol/l» — and it has to do
/// so in the same line as the value column, which already uses a comma.
///
/// Only *between digits*: the pattern leaves «Dmax (Bishop, All Data)», file
/// names and version numbers such as «v1.2.0» alone, because those never have
/// a digit on both sides of a single dot in a label — and where they do, the
/// label is a key and does not belong on a report anyway.
final RegExp _decimalPoint = RegExp(r'(?<=\d)\.(?=\d)');

String germanNumbers(String text) => text.replaceAll(_decimalPoint, ',');

/// A display string that comes out of the core: spelling and numbers both.
String germanLabel(String text) => germanNumbers(germanSpelling(text));
