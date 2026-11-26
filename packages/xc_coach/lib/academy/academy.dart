/// Die Wissensschicht von GIULIA.
///
/// ## Warum das kein Blog ist
///
/// Ein Blog beantwortet «was ist Laktat». Diese Schicht beantwortet «warum
/// steht heute diese Einheit in meinem Plan, was passiert dabei in mir, und
/// woran werde ich in acht Wochen sehen, ob es gewirkt hat». Der Unterschied
/// ist nicht der Ton, sondern die Verbindung: Ein Artikel hängt an
/// Trainingsformen, physiologischen Grössen und Diagnostikparametern, die das
/// System selbst berechnet.
///
/// ```text
///   Diagnostik → Interpretation → Trainingsentscheidung
///        ↑                              ↓
///   nachgewiesene Anpassung ← Analyse ← Training
///                    ↑
///              Academy erklärt jeden Pfeil
/// ```
///
/// ## Drei Regeln, die diese Datei durchsetzt
///
/// 1. **Jeder Inhalt hat eine Evidenzstufe.** Trainingswissenschaft ist nicht
///    eindeutig, und eine Anwendung, die so tut, verliert genau die Leser, auf
///    die es ankommt.
/// 2. **Keine erfundenen Quellen.** [AcademySource] trägt Autor, Jahr, Titel
///    und Journal. Eine Kennung (DOI, PubMed) steht nur dort, wo sie geprüft
///    ist — [AcademySource.verified] sagt, ob das geschehen ist. Ein Test
///    verhindert, dass eine ungeprüfte Kennung ins Produkt gerät.
/// 3. **Drei Tiefen, dieselbe Aussage.** Kurz, ausführlich, wissenschaftlich —
///    nie widersprüchlich, nur unterschiedlich weit.
library;

/// Wie tief jemand einsteigen will.
enum ArticleDepth {
  /// Zwanzig bis dreissig Sekunden: warum das für mich zählt.
  brief('Kurz erklärt'),

  /// Die physiologische Erklärung für ambitionierte Sportler.
  detailed('Im Detail'),

  /// Mechanismen, Studienlage, Grenzen.
  science('Wissenschaft');

  const ArticleDepth(this.label);
  final String label;
}

/// Wie gut eine Aussage belegt ist.
///
/// Die Stufen sind absichtlich grob: Eine feinere Skala täuscht eine Präzision
/// vor, die eine Einordnung nicht hat.
enum EvidenceLevel {
  strong(
    'Sehr gut belegt',
    'Mehrere hochwertige systematische Übersichten, Metaanalysen oder '
        'Konsenspapiere mit übereinstimmendem Befund.',
  ),
  good(
    'Gut belegt',
    'Mehrere brauchbare Studien mit weitgehend übereinstimmenden Ergebnissen.',
  ),
  contextual(
    'Kontextabhängig',
    'Die Ergebnisse hängen deutlich von Sportart, Trainingszustand, '
        'Geschlecht, Alter, Trainingsphase oder Studiendesign ab.',
  ),
  limited(
    'Begrenzte Evidenz',
    'Nur kleine Studien oder widersprüchliche Ergebnisse.',
  ),
  practice(
    'Praxiswissen',
    'In Training und Betreuung verbreitet, wissenschaftlich aber nicht '
        'ausreichend abgesichert.',
  );

  const EvidenceLevel(this.label, this.description);
  final String label;
  final String description;
}

/// Eine wissenschaftliche Quelle.
///
/// [verified] ist der Kern dieser Klasse. Eine Literaturangabe aus dem
/// Gedächtnis kann im Jahr, im Journal oder in der Kennung danebenliegen, und
/// eine falsche Kennung ist schlimmer als keine: Sie führt jemanden zu einer
/// Arbeit, die es so nicht gibt, und beschädigt das Vertrauen in alles
/// Übrige. Deshalb wird eine Kennung erst gezeigt, wenn sie jemand geprüft
/// hat.
class AcademySource {
  const AcademySource({
    required this.authors,
    required this.year,
    required this.title,
    required this.journal,
    this.doi,
    this.pubmedId,
    this.verified = false,
  }) : assert(
         verified || (doi == null && pubmedId == null),
         'Eine ungeprüfte Quelle darf keine Kennung tragen.',
       );

  final String authors;
  final int year;
  final String title;
  final String journal;

  /// Nur gesetzt, wenn [verified].
  final String? doi;
  final String? pubmedId;

  /// Ob Angabe und Kennung gegen die Originalquelle geprüft wurden.
  final bool verified;

  String get citation => '$authors ($year). $title. $journal.';
}

/// Die grossen Themenbereiche.
enum AcademyCategory {
  physiology('Trainingsphysiologie', 'Was im Körper passiert.'),
  intensities('Intensitäten & Schwellen', 'Wo die Grenzen liegen und warum.'),
  planning('Trainingsplanung', 'Warum dein Plan so aussieht.'),
  diagnostics('Leistungsdiagnostik', 'Was gemessen wird und was es bedeutet.'),
  progress('Fortschritt erkennen', 'Woran Anpassung sichtbar wird.'),
  strength('Kraft', 'Kraft für Ausdauersportler.'),
  recovery('Regeneration', 'Warum Erholung Teil des Trainings ist.'),
  nutrition('Ernährung', 'Was der Stoffwechsel dafür braucht.'),
  sportSpecific('Sportarten', 'Was sich nicht übertragen lässt.');

  const AcademyCategory(this.label, this.description);
  final String label;
  final String description;
}

/// Für welche Sportart ein Inhalt gilt.
///
/// [AcademySport.any] heisst nicht «egal», sondern: Die Aussage ist über
/// Sportarten hinweg belegt. Wo das nicht so ist, steht die Sportart dran —
/// eine Radstudie sagt über das Laufen nichts, und die stillschweigende
/// Übertragung ist der häufigste Fehler in Trainingsratgebern.
enum AcademySport {
  any('Sportartübergreifend'),
  cycling('Radfahren'),
  running('Laufen'),
  crossCountrySkiing('Langlauf'),
  swimming('Schwimmen'),
  ercolina('Oberkörperausdauer');

  const AcademySport(this.label);
  final String label;
}

/// Ein häufiges Missverständnis und seine Richtigstellung.
class Misconception {
  const Misconception({required this.claim, required this.correction});

  /// Was oft gesagt wird.
  final String claim;

  /// Was daran nicht stimmt.
  final String correction;
}

/// Ein Artikel.
class AcademyArticle {
  const AcademyArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.category,
    required this.evidence,
    required this.brief,
    required this.detailed,
    required this.science,
    this.sport = AcademySport.any,
    this.tags = const [],
    this.sources = const [],
    this.misconceptions = const [],
    this.related = const [],
    this.relatedParameters = const [],
    this.practicalExample,
    this.progressMarkers = const [],
  });

  final String id;
  final String title;

  /// Ein Satz für die Übersicht.
  final String summary;

  final AcademyCategory category;
  final AcademySport sport;
  final EvidenceLevel evidence;

  /// Die drei Tiefen. Jede ist für sich lesbar; keine widerspricht einer
  /// anderen.
  final List<String> brief;
  final List<String> detailed;
  final List<String> science;

  final List<String> tags;
  final List<AcademySource> sources;
  final List<Misconception> misconceptions;

  /// Kennungen verwandter Artikel.
  final List<String> related;

  /// Grössen, die GIULIA selbst berechnet und die zu diesem Artikel gehören —
  /// `lt1`, `lt2`, `vo2max`, `symmetry`. Darüber entsteht später die
  /// persönliche Ergänzung: «Dein LT1 liegt bei 198 W.»
  final List<String> relatedParameters;

  /// Wie eine Einheit dazu aussehen könnte.
  final String? practicalExample;

  /// Woran Fortschritt erkennbar wäre.
  final List<String> progressMarkers;

  List<String> textFor(ArticleDepth depth) => switch (depth) {
    ArticleDepth.brief => brief,
    ArticleDepth.detailed => detailed,
    ArticleDepth.science => science,
  };
}
