// LaLa – Lactate Lab: Versionsvertrag des wissenschaftlichen Kerns.
//
// Diese Datei liegt bewusst AUSSERHALB von `lib/lala/core/**`. Der Kern selbst
// bleibt unveraendert gegenueber dem migrierten Original (Phase C1); diese
// Datei beschreibt ihn nur von aussen. Der Core-Purity-Test verbietet, dass der
// Kern sie importiert.
//
// Regeln siehe docs/LALA_SCIENTIFIC_GUARDRAILS.md.

/// Version der wissenschaftlichen LaLa-Engine.
///
/// Diese Version identifiziert das **Rechenverhalten** des gesamten Kerns unter
/// `lib/lala/core/**`, nicht die App-Version von Giulia.
///
/// Sie MUSS erhoeht werden, sobald sich irgendein numerisches oder
/// strukturelles Ergebnis der Engine bewusst aendert. Ein solcher Schritt ist
/// nur zusammen mit einer neuen Baseline, einer fachlichen Begruendung und
/// einem dokumentierten Ergebnis-Diff zulaessig.
///
/// Ab Phase D wird dieser Wert bei jedem persistierten Ergebnis mitgeschrieben
/// (`lala_engine_version`), damit historische Resultate dauerhaft dem exakten
/// Rechenstand zugeordnet bleiben, mit dem sie entstanden sind.
const String lalaEngineVersion = '2.0.0';

/// Herkunft des Kerns: Commit im Ursprungsrepository `Lactate_Test`,
/// aus dem der Verbatim-Move in Phase C1 erfolgt ist.
const String lalaEngineSourceCommit =
    '66b460e4be46f09506023df8be4bd632f53464ae';

/// Bezeichner der eingefrorenen numerischen Baseline, gegen die die Engine
/// getestet wird.
const String lalaBaselineSnapshotId = 'lala_numeric_baseline_v2';

/// Pfad der eingefrorenen Baseline relativ zum Paketwurzelverzeichnis.
const String lalaBaselineSnapshotPath =
    'docs/baseline/lala_numeric_baseline_v2.json';

/// SHA-256 der eingefrorenen Baseline-Datei.
///
/// Doppelte Sicherung: Der Regressionstest vergleicht die erzeugten Werte gegen
/// die Datei UND die Datei gegen diesen Hash. Damit kann eine Abweichung nicht
/// dadurch verschwinden, dass jemand die Baseline anpasst -- dieser Hash muesste
/// dann ebenfalls bewusst geaendert werden, gemeinsam mit
/// [lalaEngineVersion].
const String lalaBaselineSnapshotSha256 =
    '6dcbdb73c8dc114b84331a02e7334055beb70232f63b65fc9719058335ba0641';

/// Anzahl der Referenzfaelle im Snapshot: 4 mitgelieferte Diagnostikberichte,
/// 1 Golden-Vektor, 10 Testfixtures.
const int lalaBaselineCaseCount = 15;

/// Anzahl der registrierten Analysemethoden.
const int lalaMethodCount = 24;

/// Goldenwerte des Hofmann-Graz-Referenzfalls. Sie werden zusaetzlich zum
/// Snapshot-Vergleich einzeln geprueft, damit ein Fehlschlag sofort lesbar ist.
const double lalaHofmannGoldenLt1Load = 132.9824561403509;

/// Siehe [lalaHofmannGoldenLt1Load].
const double lalaHofmannGoldenLt2Load = 231.89672447013496;
