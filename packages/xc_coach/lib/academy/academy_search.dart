/// Suchen, was jemand meint — nicht, was er tippt.
///
/// Ein Athlet sucht «Zone 2» und meint das, was hier LT1 heisst. Er sucht
/// «anaerobe Schwelle» und meint LT2. Er sucht «Fettverbrennung» und landet
/// bei einem Missverständnis, das ein Artikel richtigstellt. Eine Suche, die
/// nur Titel vergleicht, findet in allen drei Fällen nichts — und der Leser
/// schliesst daraus, dass es dazu nichts gibt.
library;

import 'academy.dart';

/// Was Menschen sagen, und worauf es zeigt.
///
/// Bewusst als Liste und nicht als Rechenverfahren: Trainingsbegriffe sind
/// historisch gewachsen und uneinheitlich; das lässt sich nicht ableiten,
/// sondern nur aufschreiben.
const Map<String, List<String>> academySynonyms = {
  'zone 2': ['lt1', 'base_training'],
  'zone2': ['lt1', 'base_training'],
  'z2': ['lt1', 'base_training'],
  'grundlage': ['lt1', 'base_training'],
  'grundlagenausdauer': ['lt1', 'base_training'],
  'ga1': ['lt1', 'base_training'],
  'ga2': ['lt2', 'threshold_training'],
  'aerobe schwelle': ['lt1'],
  'anaerobe schwelle': ['lt2', 'threshold_models'],
  'schwelle': ['lt2', 'threshold_training'],
  'ftp': ['lt2', 'threshold_training'],
  'fettverbrennung': ['lt1', 'metabolism'],
  'fettstoffwechsel': ['lt1', 'metabolism'],
  'intervalle': ['vo2max', 'threshold_training'],
  'vo2max intervalle': ['vo2max', 'intervals', 'high_intensity'],
  'spitzenleistung': ['vo2max'],
  'erholung': ['recovery'],
  'readiness': ['readiness', 'load', 'recovery'],
  'trainingsbelastung': ['load', 'readiness'],
  'pause': ['recovery'],
  'übertraining': ['recovery', 'load'],
  'laktattest': ['testing', 'lactate'],
  'stufentest': ['testing', 'protocol'],
  '4 mmol': ['threshold_models', 'lt2'],
  'rad': ['cycling', 'power'],
  'radfahren': ['cycling', 'power'],
  'laufen': ['running', 'pace', 'economy'],
  'laufökonomie': ['running', 'economy'],
  'langlauf': ['cross_country', 'skiing'],
  'ercolina': ['ercolina', 'ski_erg', 'poling'],
  'skierg': ['ercolina', 'ski_erg', 'poling'],
  'symmetrie': ['symmetry', 'technique'],
  'kraft': ['strength', 'stability'],
  'stabilisation': ['strength', 'stability'],
  'ernährung': ['nutrition', 'carbohydrate'],
  'kohlenhydrate': ['nutrition', 'carbohydrate'],
  'plateau': ['trend', 'plateau', 'uncertainty'],
  'testvorbereitung': ['testing', 'preparation', 'quality'],
};

/// Findet Artikel zu einer Eingabe.
///
/// Die Reihenfolge ist die Antwort: Titeltreffer vor Zusammenfassung vor
/// Schlagwort vor Fliesstext. Wer «LT2» sucht, will den Artikel über LT2 und
/// nicht den, der ihn nebenbei erwähnt.
List<AcademyArticle> searchAcademy(
  String query, {
  List<AcademyArticle> library = const [],
  AcademySport? sport,
}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];

  final tags = <String>{
    ...?academySynonyms[needle],
    for (final entry in academySynonyms.entries)
      if (needle.contains(entry.key)) ...entry.value,
  };

  final scored = <(int, AcademyArticle)>[];
  for (final article in library) {
    if (sport != null &&
        article.sport != AcademySport.any &&
        article.sport != sport) {
      continue;
    }
    var score = 0;
    if (article.title.toLowerCase().contains(needle)) score += 100;
    if (article.id.contains(needle.replaceAll(' ', '-'))) score += 90;
    if (article.summary.toLowerCase().contains(needle)) score += 50;
    for (final tag in article.tags) {
      if (tags.contains(tag)) score += 40;
      if (tag.contains(needle)) score += 30;
    }
    for (final depth in ArticleDepth.values) {
      for (final paragraph in article.textFor(depth)) {
        if (paragraph.toLowerCase().contains(needle)) {
          score += 10;
          break;
        }
      }
    }
    // Ein Missverständnis ist oft genau das, wonach jemand sucht.
    for (final item in article.misconceptions) {
      if (item.claim.toLowerCase().contains(needle)) score += 35;
    }
    if (score > 0) scored.add((score, article));
  }

  scored.sort((a, b) {
    final byScore = b.$1.compareTo(a.$1);
    return byScore != 0 ? byScore : a.$2.title.compareTo(b.$2.title);
  });
  return [for (final entry in scored) entry.$2];
}

/// Die Artikel einer Kategorie.
List<AcademyArticle> articlesOf(
  AcademyCategory category, {
  List<AcademyArticle> library = const [],
}) => [
  for (final article in library)
    if (article.category == category) article,
];

/// Ein Artikel über seine Kennung.
AcademyArticle? articleById(
  String id, {
  List<AcademyArticle> library = const [],
}) {
  for (final article in library) {
    if (article.id == id) return article;
  }
  return null;
}

/// Artikel zu einer Grösse, die das System selbst berechnet.
///
/// Der Weg von einer Zahl auf dem Bildschirm zu ihrer Erklärung: Wer im
/// Testergebnis auf LT2 tippt, soll dort landen, wo LT2 erklärt wird.
List<AcademyArticle> articlesForParameter(
  String parameter, {
  List<AcademyArticle> library = const [],
}) => [
  for (final article in library)
    if (article.relatedParameters.contains(parameter)) article,
];
