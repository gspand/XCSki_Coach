/// Die ersten Inhalte der Wissensschicht.
///
/// ## Wie diese Texte entstanden sind — und was das für sie bedeutet
///
/// Sie stammen aus dem gesicherten Bestand der Trainingsphysiologie und sind
/// bewusst dort angesetzt, wo GIULIA selbst rechnet: Laktat, LT1, LT2,
/// Schwellenmodelle, Trainingsbereiche. Was das System misst, soll es auch
/// erklären können.
///
/// Literaturangaben tragen nur dann DOI und PubMed-Kennung, wenn beide gegen
/// den Originaleintrag geprüft wurden. Ältere Einträge ohne diese Prüfung
/// bleiben bewusst ohne Kennung und mit [AcademySource.verified] = false. Das
/// ist die Umsetzung der Regel: Eine Kennung, die auf eine andere Arbeit
/// zeigt, ist schlimmer als gar keine. Ein Test verhindert, dass eine
/// ungeprüfte Kennung in die Oberfläche gelangt.
library;

import 'academy.dart';

// --------------------------------------------------------------- Quellen

const _faude2009 = AcademySource(
  authors: 'Faude O, Kindermann W, Meyer T',
  year: 2009,
  title: 'Lactate threshold concepts: how valid are they?',
  journal: 'Sports Medicine',
);

const _beneke2011 = AcademySource(
  authors: 'Beneke R, Leithäuser RM, Ochentel O',
  year: 2011,
  title: 'Blood lactate diagnostics in exercise testing and training',
  journal: 'International Journal of Sports Physiology and Performance',
);

const _brooks2018 = AcademySource(
  authors: 'Brooks GA',
  year: 2018,
  title: 'The science and translation of lactate shuttle theory',
  journal: 'Cell Metabolism',
);

const _jamnick2020 = AcademySource(
  authors: 'Jamnick NA, Pettitt RW, Granata C, Pyne DB, Bishop DJ',
  year: 2020,
  title:
      'An examination and critique of current methods to determine exercise '
      'intensity',
  journal: 'Sports Medicine',
);

const _seiler2010 = AcademySource(
  authors: 'Seiler S',
  year: 2010,
  title:
      'What is best practice for training intensity and duration distribution '
      'in endurance athletes?',
  journal: 'International Journal of Sports Physiology and Performance',
);

const _buchheit2013 = AcademySource(
  authors: 'Buchheit M, Laursen PB',
  year: 2013,
  title:
      'High-intensity interval training, solutions to the programming puzzle',
  journal: 'Sports Medicine',
);

const _bassett2000 = AcademySource(
  authors: 'Bassett DR, Howley ET',
  year: 2000,
  title:
      'Limiting factors for maximum oxygen uptake and determinants of '
      'endurance performance',
  journal: 'Medicine & Science in Sports & Exercise',
);

const _bishop2014 = AcademySource(
  authors: 'Bishop DJ, Granata C, Eynon N',
  year: 2014,
  title:
      'Can we optimise the exercise training prescription to maximise '
      'improvements in mitochondria function and content?',
  journal: 'Biochimica et Biophysica Acta',
);

const _meeusen2013 = AcademySource(
  authors: 'Meeusen R, Duclos M, Foster C et al.',
  year: 2013,
  title:
      'Prevention, diagnosis and treatment of the overtraining syndrome: '
      'joint consensus statement of ECSS and ACSM',
  journal: 'Medicine & Science in Sports & Exercise',
);

const _halson2014 = AcademySource(
  authors: 'Halson SL',
  year: 2014,
  title: 'Monitoring training load to understand fatigue in athletes',
  journal: 'Sports Medicine',
);

const _ronnestad2014 = AcademySource(
  authors: 'Rønnestad BR, Mujika I',
  year: 2014,
  title:
      'Optimizing strength training for running and cycling endurance '
      'performance: a review',
  journal: 'Scandinavian Journal of Medicine & Science in Sports',
  doi: '10.1111/sms.12104',
  pubmedId: '23914932',
  verified: true,
);

const _sandbakk2017 = AcademySource(
  authors: 'Sandbakk Ø, Holmberg HC',
  year: 2017,
  title:
      'Physiological capacity and training routines of elite cross-country '
      'skiers: approaching the upper limits of human endurance',
  journal: 'International Journal of Sports Physiology and Performance',
  doi: '10.1123/ijspp.2016-0749',
  pubmedId: '28095083',
  verified: true,
);

const _hegge2016 = AcademySource(
  authors: 'Hegge AM, Bucher E, Ettema G, Faude O, Holmberg HC, Sandbakk Ø',
  year: 2016,
  title:
      'Gender differences in power production, energetic capacity and '
      'efficiency of elite cross-country skiers during whole-body, '
      'upper-body, and arm poling',
  journal: 'European Journal of Applied Physiology',
  doi: '10.1007/s00421-015-3281-y',
  pubmedId: '26476546',
  verified: true,
);

const _thomas2016 = AcademySource(
  authors: 'Thomas DT, Erdman KA, Burke LM',
  year: 2016,
  title:
      'Position of the Academy of Nutrition and Dietetics, Dietitians of '
      'Canada, and the American College of Sports Medicine: Nutrition and '
      'Athletic Performance',
  journal: 'Journal of the Academy of Nutrition and Dietetics',
  doi: '10.1016/j.jand.2015.12.006',
  pubmedId: '26920240',
  verified: true,
);

// -------------------------------------------------------------- Artikel

/// Was ohne weiteres Zutun zur Verfügung steht.
const List<AcademyArticle> academyLibrary = [
  AcademyArticle(
    id: 'laktat',
    title: 'Was ist Laktat?',
    summary:
        'Kein Abfallprodukt und keine Ursache von Muskelkater, sondern ein '
        'Brennstoff und ein Messfenster in den Stoffwechsel.',
    category: AcademyCategory.physiology,
    evidence: EvidenceLevel.strong,
    tags: ['lactate', 'metabolism'],
    relatedParameters: ['lactate'],
    brief: [
      'Laktat entsteht laufend im Muskel — auch in Ruhe. Es ist kein Zeichen '
          'dafür, dass etwas schiefläuft, sondern ein Zwischenprodukt des '
          'Kohlenhydratabbaus, das andere Zellen als Brennstoff nutzen.',
      'Gemessen wird es, weil sein Verlauf über die Belastung etwas verrät, '
          'was man von aussen nicht sieht: ab wann die Bildung schneller '
          'steigt als die Verwertung.',
    ],
    detailed: [
      'Beim Abbau von Kohlenhydraten entsteht Pyruvat. Ein Teil davon wird in '
          'den Mitochondrien weiter oxidiert, ein Teil zu Laktat umgewandelt. '
          'Beides passiert immer und nebeneinander — die Frage ist nur, in '
          'welchem Verhältnis.',
      'Das gebildete Laktat bleibt nicht liegen. Es wird in derselben '
          'Muskelfaser, in benachbarten Fasern, im Herzmuskel, in der Leber '
          'und in der Niere weiterverwendet. Was im Blut ankommt, ist deshalb '
          'immer die Differenz aus Bildung und Verwertung, nie die Bildung '
          'allein.',
      'Genau darin liegt der diagnostische Wert: Solange die Verwertung '
          'mithält, bleibt die Blutkonzentration niedrig, obwohl die Bildung '
          'längst gestiegen ist. Erst wenn sie nicht mehr mithält, steigt die '
          'Kurve deutlich — und dieser Punkt lässt sich messen.',
      'Der lange geglaubte Zusammenhang zwischen Laktat und Muskelkater ist '
          'widerlegt. Laktat ist nach einer Belastung binnen Minuten bis '
          'wenige Stunden abgebaut; Muskelkater entsteht Stunden später und '
          'hat andere Ursachen.',
    ],
    science: [
      'Die Vorstellung von Laktat als Endprodukt eines «anaeroben» '
          'Stoffwechsels ist überholt. Das Laktat-Shuttle-Konzept beschreibt '
          'Laktat als Transportform von Kohlenhydratenergie zwischen Zellen '
          'und Geweben; die Oxidation überwiegt gegenüber der Ausscheidung '
          'deutlich.',
      'Die Blutkonzentration ist eine Nettogrösse und hängt ausser von der '
          'Belastung auch vom Glykogenstatus, von vorangegangenen Einheiten, '
          'von der Kohlenhydratzufuhr, von der Umgebungstemperatur und vom '
          'Entnahmeort ab. Das macht Einzelwerte zwischen Tagen nur '
          'eingeschränkt vergleichbar — Verläufe innerhalb eines Tests '
          'dagegen sehr wohl.',
      'Für die Diagnostik folgt daraus: Ein Laktatwert ohne Protokoll, ohne '
          'Stufendauer und ohne Angabe des Vorzustands ist keine Aussage, '
          'sondern eine Zahl.',
    ],
    misconceptions: [
      Misconception(
        claim: 'Laktat verursacht Muskelkater.',
        correction:
            'Laktat ist Stunden vor dem Auftreten von Muskelkater bereits '
            'abgebaut. Muskelkater geht auf mechanische Beanspruchung und '
            'nachfolgende Entzündungsvorgänge zurück, insbesondere nach '
            'bremsenden Belastungen.',
      ),
      Misconception(
        claim: 'Laktat ist ein Abfallprodukt.',
        correction:
            'Es ist ein Brennstoff. Herzmuskel und langsam zuckende Fasern '
            'oxidieren Laktat bevorzugt; die Leber baut daraus wieder Glukose '
            'auf.',
      ),
      Misconception(
        claim: 'Hohes Laktat bedeutet, dass kein Sauerstoff da war.',
        correction:
            'Laktat entsteht auch bei ausreichender Sauerstoffversorgung. Die '
            'Bildungsrate hängt vom Tempo der Glykolyse ab, nicht allein von '
            'der Sauerstoffverfügbarkeit.',
      ),
    ],
    related: ['lt1', 'lt2', 'stufentest'],
    sources: [_brooks2018, _beneke2011, _faude2009],
  ),

  AcademyArticle(
    id: 'lt1',
    title: 'Was ist LT1?',
    summary:
        'Der erste deutliche Anstieg der Laktatkurve über den Ruhebereich — '
        'die obere Grenze dessen, was sich sehr lange durchhalten lässt.',
    category: AcademyCategory.intensities,
    evidence: EvidenceLevel.good,
    tags: ['lt1', 'lactate', 'base_training'],
    relatedParameters: ['lt1'],
    brief: [
      'LT1 ist die Belastung, ab der die Laktatkonzentration im Blut zum '
          'ersten Mal erkennbar über den Ruhebereich steigt.',
      'Unterhalb davon lässt sich sehr lange arbeiten, weil Bildung und '
          'Verwertung nahe beieinander bleiben. Für die Trainingsplanung ist '
          'das die wichtigste untere Marke.',
    ],
    detailed: [
      'Unterhalb von LT1 bleibt die Blutkonzentration über die Zeit nahezu '
          'stabil. Die Belastung ist damit über Stunden möglich, und die '
          'Ermüdung, die entsteht, ist überwiegend mechanisch und nicht '
          'metabolisch.',
      'Der Punkt selbst ist kein Schalter. Die Stoffwechsellage ändert sich '
          'stetig; LT1 markiert die Stelle, an der diese Änderung im Blut '
          'erstmals sichtbar wird. Verschiedene Bestimmungsverfahren legen '
          'ihn deshalb geringfügig unterschiedlich fest.',
      'Trainingspraktisch ist LT1 die Grenze, unterhalb derer sich grosse '
          'Trainingsumfänge ansammeln lassen, ohne dass die Erholungszeit '
          'unverhältnismässig wächst. Das ist der eigentliche Grund für seine '
          'Bedeutung — nicht ein besonderer «Fettstoffwechselbereich».',
      'Eine Verschiebung von LT1 zu höherer Leistung bei gleicher '
          'Laktatkonzentration gehört zu den brauchbarsten Zeichen dafür, '
          'dass Grundlagenarbeit gewirkt hat.',
    ],
    science: [
      'LT1 wird in der Literatur unterschiedlich benannt — aerobe Schwelle, '
          'erster Laktatanstieg, LTP1 — und unterschiedlich bestimmt: als '
          'erster Anstieg über einen Basiswert, über feste Zuschläge oder '
          'über Kurvenanpassungen. Die Werte derselben Messung können je nach '
          'Verfahren um relevante Beträge auseinanderliegen.',
      'Die Zuordnung zu Ventilationsschwellen ist gut, aber nicht perfekt; '
          'beide beschreiben verwandte, nicht identische Phänomene.',
      'Für die Anwendung heisst das: Der Zahlenwert ist nur innerhalb '
          'desselben Verfahrens und desselben Protokolls über die Zeit '
          'vergleichbar. Ein Verfahrenswechsel erzeugt einen Sprung, der '
          'nichts mit dem Athleten zu tun hat.',
    ],
    misconceptions: [
      Misconception(
        claim: 'Unterhalb von LT1 trainiert man den Fettstoffwechsel.',
        correction:
            'Der Anteil der Fettoxidation ist dort hoch, aber die wesentlichen '
            'Anpassungen betreffen die Muskelzelle als Ganzes — '
            'mitochondriale Dichte und Funktion, Kapillarisierung, '
            'Enzymausstattung. «Fettstoffwechseltraining» beschreibt eine '
            'Begleiterscheinung, nicht das Trainingsziel.',
      ),
      Misconception(
        claim: 'LT1 ist ein fester Prozentsatz der maximalen Herzfrequenz.',
        correction:
            'Die Streuung zwischen Menschen ist zu gross, als dass eine '
            'Faustformel den individuellen Wert ersetzen könnte. Genau '
            'deshalb wird gemessen.',
      ),
    ],
    practicalExample:
        'Sechzig bis hundertachtzig Minuten gleichmässig knapp unterhalb von '
        'LT1, ohne Anstiege in höhere Bereiche. Die Einheit soll am Ende '
        'gleichmässig aussehen, nicht am Anfang stark.',
    progressMarkers: [
      'Höhere Leistung bei gleicher Laktatkonzentration',
      'Niedrigere Herzfrequenz bei gleicher Leistung unter vergleichbaren '
          'Bedingungen',
      'Längere gleichmässige Einheiten bei gleicher subjektiver Belastung',
    ],
    related: ['lt2', 'lt1-vs-lt2', 'training-unter-lt1', 'laktat'],
    sources: [_faude2009, _jamnick2020, _beneke2011],
  ),

  AcademyArticle(
    id: 'lt2',
    title: 'Was ist LT2?',
    summary:
        'Die höchste Belastung, bei der Laktatbildung und -verwertung noch '
        'ins Gleichgewicht kommen.',
    category: AcademyCategory.intensities,
    evidence: EvidenceLevel.good,
    tags: ['lt2', 'lactate', 'threshold_training'],
    relatedParameters: ['lt2'],
    brief: [
      'LT2 markiert den Übergang, oberhalb dessen die Laktatkonzentration '
          'nicht mehr stabil bleibt, sondern über die Zeit weiter steigt.',
      'Diese Leistung lässt sich typischerweise dreissig bis sechzig Minuten '
          'halten. Sie ist der wichtigste Einzelwert für die Steuerung '
          'intensiverer Einheiten.',
    ],
    detailed: [
      'Unterhalb von LT2 stellt sich bei gleichbleibender Belastung nach '
          'einigen Minuten ein stabiler Laktatwert ein. Oberhalb davon nicht: '
          'Dort steigt die Konzentration weiter, und die Belastung endet '
          'absehbar.',
      'Der zugrunde liegende Begriff ist das maximale Laktat-Steady-State — '
          'die höchste Leistung mit noch stabiler Konzentration. Es direkt zu '
          'bestimmen verlangt mehrere Dauerbelastungen an verschiedenen '
          'Tagen. Ein Stufentest schätzt es; verschiedene Verfahren tun das '
          'unterschiedlich gut.',
      'Trainingspraktisch ist LT2 der Bezugspunkt für Schwellenintervalle und '
          'zugleich die Obergrenze für das, was sich in grossem Umfang '
          'wiederholen lässt, ohne die Erholung zu überfordern.',
    ],
    science: [
      'Die Bestimmungsverfahren zerfallen in zwei Gruppen: feste '
          'Konzentrationen — etwa 4 mmol/l — und individuelle Verfahren wie '
          'Dmax, modifiziertes Dmax oder Anstiege über einen Basiswert. Feste '
          'Werte sind einfach und über Personen hinweg schlecht vergleichbar; '
          'individuelle Verfahren treffen das Steady State im Mittel besser, '
          'streuen aber ebenfalls.',
      'Übersichtsarbeiten zeigen, dass die Übereinstimmung zwischen '
          'Verfahren und direkt bestimmtem Steady State je nach Sportart, '
          'Protokoll und Trainingszustand deutlich schwankt. Es gibt kein '
          'Verfahren, das in allen Konstellationen überlegen wäre.',
      'Deshalb gilt: Das Verfahren gehört zum Wert. Zwei Tests desselben '
          'Athleten sind nur dann vergleichbar, wenn Protokoll, Stufendauer '
          'und Auswerteverfahren übereinstimmen.',
    ],
    misconceptions: [
      Misconception(
        claim: 'LT2 ist die Leistung, die man eine Stunde halten kann.',
        correction:
            'Als grobe Orientierung brauchbar, als Definition nicht. Die '
            'tatsächlich haltbare Dauer schwankt zwischen Athleten erheblich '
            'und hängt vom Trainingszustand ab.',
      ),
    ],
    practicalExample:
        'Vier bis sechs Wiederholungen von sechs bis zehn Minuten knapp '
        'unterhalb bis an LT2, mit kurzen Pausen. Die letzte Wiederholung '
        'soll noch dieselbe Leistung tragen wie die erste.',
    progressMarkers: [
      'Höhere Leistung bei LT2 im nächsten Test',
      'Rechtsverschiebung der gesamten Laktatkurve',
      'Gleiche Leistung bei niedrigerem Laktat',
    ],
    related: ['lt1', 'lt1-vs-lt2', 'vier-mmol', 'stufentest'],
    sources: [_faude2009, _jamnick2020, _beneke2011],
  ),

  AcademyArticle(
    id: 'lt1-vs-lt2',
    title: 'LT1 und LT2 — zwei Grenzen, zwei Aufgaben',
    summary:
        'Zwischen den beiden Schwellen liegt der Bereich, der am häufigsten '
        'falsch eingesetzt wird.',
    category: AcademyCategory.intensities,
    evidence: EvidenceLevel.contextual,
    tags: ['lt1', 'lt2', 'intensity_distribution'],
    relatedParameters: ['lt1', 'lt2'],
    brief: [
      'LT1 trennt das sehr lange Haltbare vom mittelschweren Bereich. LT2 '
          'trennt das noch Stabilisierbare vom absehbar Endenden.',
      'Dazwischen liegt ein Bereich, der anstrengend genug ist, um Erholung '
          'zu kosten, aber selten anstrengend genug, um die stärksten Reize '
          'zu setzen.',
    ],
    detailed: [
      'Unterhalb von LT1: viel Umfang möglich, geringe metabolische '
          'Ermüdung, Anpassungen überwiegend peripher.',
      'Zwischen LT1 und LT2: steigender Kohlenhydratanteil, zunehmende '
          'metabolische und muskuläre Ermüdung. Der Bereich ist nicht '
          'schädlich — er ist teuer. Wer viel Zeit dort verbringt, sammelt '
          'Ermüdung, ohne die Vorteile der Ränder voll auszuschöpfen.',
      'An und über LT2: hohe aerobe Beanspruchung, deutliche Reize auf '
          'zentrale und periphere Systeme, entsprechend hoher Erholungsbedarf '
          'und begrenzte Wiederholbarkeit.',
      'Es gibt bewusste Gründe, im mittleren Bereich zu arbeiten — '
          'wettkampfspezifische Vorbereitung, begrenzte Trainingszeit, '
          'bestimmte Sportarten und Geländeprofile. Die Frage ist nicht, ob '
          'er vorkommt, sondern ob er absichtlich vorkommt.',
    ],
    science: [
      'Beobachtungsstudien an gut trainierten Ausdauerathleten zeigen '
          'wiederholt eine Verteilung mit hohem Anteil niedriger Intensität '
          'und einem kleineren Anteil hoher Intensität. Daraus wurde die '
          'Empfehlung einer polarisierten Verteilung abgeleitet.',
      'Interventionsstudien fallen weniger einheitlich aus. Vergleiche '
          'zwischen polarisierten, pyramidalen und schwellenbetonten '
          'Verteilungen zeigen je nach Sportart, Leistungsniveau, '
          'Trainingsphase und Studiendauer unterschiedliche Ergebnisse.',
      'Die belastbare Aussage lautet daher: Ein hoher Anteil niedriger '
          'Intensität in Verbindung mit gezielten intensiven Reizen ist gut '
          'begründet. Eine feste Zahlenformel für alle ist es nicht.',
    ],
    misconceptions: [
      Misconception(
        claim: '80/20 ist die richtige Verteilung.',
        correction:
            'Die Zahl stammt aus Beobachtungen an gut trainierten Athleten in '
            'bestimmten Sportarten und Phasen. Sie ist eine gute '
            'Orientierung, kein Naturgesetz — und sie beantwortet nicht, ob '
            '80 % der Zeit oder 80 % der Einheiten gemeint sind.',
      ),
      Misconception(
        claim: 'Der Bereich zwischen den Schwellen ist verbotenes Gebiet.',
        correction:
            'Er ist teuer, nicht verboten. Wettkampfspezifisches Training '
            'findet für viele Sportarten genau dort statt.',
      ),
    ],
    related: ['lt1', 'lt2', 'training-unter-lt1', 'vo2max'],
    sources: [_seiler2010, _jamnick2020, _faude2009],
  ),

  AcademyArticle(
    id: 'training-unter-lt1',
    title: 'Warum trainieren wir unter LT1?',
    summary:
        'Weil dort das beste Verhältnis aus Trainingsreiz und Erholungskosten '
        'liegt — nicht wegen des Fettstoffwechsels.',
    category: AcademyCategory.planning,
    evidence: EvidenceLevel.good,
    tags: ['lt1', 'base_training', 'volume'],
    relatedParameters: ['lt1'],
    brief: [
      'Unterhalb von LT1 lässt sich viel Zeit ansammeln, ohne dass die '
          'Erholung überproportional wächst.',
      'Genau darin liegt der Wert: Nicht die einzelne Einheit ist besonders '
          'wirksam, sondern die Summe vieler Einheiten, die sich '
          'nebeneinander vertragen.',
    ],
    detailed: [
      'Ein Trainingsreiz kostet Erholung. Bei niedriger Intensität steigt '
          'der Reiz mit der Dauer, die Erholungskosten steigen aber deutlich '
          'langsamer als bei hoher Intensität. Deshalb lässt sich in diesem '
          'Bereich Woche für Woche Umfang wiederholen.',
      'Die Anpassungen betreffen vor allem die Arbeitsmuskulatur: mehr und '
          'leistungsfähigere Mitochondrien, dichtere Kapillarisierung, '
          'bessere Substratverwertung. Dazu kommen zentrale Anpassungen wie '
          'ein grösseres Schlagvolumen.',
      'Diese Anpassungen brauchen Zeit — Wochen bis Monate. Sie sind der '
          'Grund, warum Grundlagenarbeit langweilig aussieht und trotzdem '
          'entscheidend ist.',
      'Ein zweiter, unterschätzter Punkt: Nur wer die Grundlage ohne '
          'Restermüdung fährt, kann die intensiven Einheiten in der Qualität '
          'fahren, für die sie gedacht sind. Zu schnelle Grundlage macht '
          'nicht die Grundlage besser, sondern die Intervalle schlechter.',
    ],
    science: [
      'Mitochondriale Anpassungen entstehen sowohl über Umfang bei niedriger '
          'als auch über Reize bei hoher Intensität; die auslösenden '
          'Signalwege überschneiden sich teilweise. Die Literatur legt nahe, '
          'dass beide Wege ihren Beitrag leisten und sich nicht ersetzen.',
      'Die Übertragbarkeit zwischen Sportarten ist begrenzt. Beim Laufen '
          'begrenzt die mechanische Beanspruchung den möglichen Umfang '
          'deutlich stärker als beim Radfahren; im Langlauf verteilt sich die '
          'Belastung zusätzlich auf Ober- und Unterkörper.',
      'Belastbar ist die Aussage über das Verhältnis von Reiz zu Ermüdung. '
          'Nicht belastbar sind feste Vorgaben, wie viele Stunden ein '
          'bestimmter Athlet in diesem Bereich verbringen sollte.',
    ],
    misconceptions: [
      Misconception(
        claim: 'Langsames Training macht langsam.',
        correction:
            'Es macht die intensiven Einheiten möglich. Wer jede Einheit '
            'mittelhart fährt, ermüdet gleichmässig und setzt nirgends einen '
            'klaren Reiz.',
      ),
      Misconception(
        claim: 'Nur Training unter LT1 baut die Grundlagenausdauer auf.',
        correction:
            'Auch intensive Einheiten tragen zu peripheren Anpassungen bei. '
            'Der Umfang bei niedriger Intensität ist der verträglichste Weg '
            'dorthin, nicht der einzige.',
      ),
    ],
    practicalExample:
        'Zwei bis vier Einheiten je Woche über sechzig bis hundertachtzig '
        'Minuten unterhalb von LT1 — gleichmässig, ohne Anstiege, und lang '
        'genug, dass die Dauer selbst der Reiz ist.',
    progressMarkers: [
      'Mehr Leistung bei LT1 im nächsten Test',
      'Gleiche Einheit bei geringerer Herzfrequenz und geringerem '
          'Belastungsempfinden',
      'Mehr Wochenumfang bei gleichbleibender Erholung',
    ],
    related: ['lt1', 'lt1-vs-lt2', 'entlastung'],
    sources: [_seiler2010, _bishop2014, _bassett2000],
  ),

  AcademyArticle(
    id: 'vier-mmol',
    title: 'Warum 4 mmol/l nicht automatisch deine Schwelle ist',
    summary:
        'Ein fester Zahlenwert für alle Menschen kann eine individuelle '
        'Grenze nicht treffen.',
    category: AcademyCategory.diagnostics,
    evidence: EvidenceLevel.strong,
    tags: ['lt2', 'lactate', 'threshold_models'],
    relatedParameters: ['lt2'],
    brief: [
      'Die 4-mmol-Marke ist ein historisch verbreitetes Rechenverfahren, '
          'keine physiologische Konstante.',
      'Bei manchen Menschen liegt die tatsächliche obere Schwelle darunter, '
          'bei anderen deutlich darüber. Wer die Marke ungeprüft übernimmt, '
          'trainiert einen Teil der Athleten zu hart und einen anderen zu '
          'weich.',
    ],
    detailed: [
      'Das Verfahren entstand, weil es einfach ist: eine Zahl, ein '
          'Schnittpunkt, ein Ergebnis. Für Gruppenvergleiche ist das '
          'brauchbar. Für die Steuerung eines einzelnen Menschen ist es zu '
          'grob.',
      'Die individuell bestimmte obere Schwelle streut über Personen '
          'erheblich. Zusätzlich verschiebt sich die gesamte Kurve mit dem '
          'Glykogenstatus: Wer entleert antritt, zeigt bei gleicher Leistung '
          'niedrigere Werte — und bekäme nach fester Marke eine zu hohe '
          'Schwelle zugewiesen.',
      'GIULIA rechnet deshalb mehrere Verfahren nebeneinander und weist '
          'dasjenige als Standard aus, das für die Fragestellung geeignet '
          'ist. Der benutzte Weg steht an jedem Ergebnis.',
    ],
    science: [
      'Übersichtsarbeiten zu Schwellenkonzepten zeigen, dass feste '
          'Konzentrationsmarken das maximale Laktat-Steady-State im Mittel '
          'systematisch verfehlen und die Streuung gross ist.',
      'Individuelle Verfahren schneiden im Mittel besser ab, ohne fehlerfrei '
          'zu sein. Ausserdem hängt jedes Ergebnis vom Protokoll ab: '
          'Stufendauer, Steigerung und Entnahmezeitpunkt verschieben die '
          'Kurve.',
      'Die praktische Folgerung ist unabhängig vom bevorzugten Verfahren: '
          'Vergleichbar sind nur Tests mit gleichem Protokoll und gleichem '
          'Auswerteweg.',
    ],
    misconceptions: [
      Misconception(
        claim: 'Die anaerobe Schwelle liegt bei 4 mmol/l.',
        correction:
            'Bei manchen Menschen ungefähr, bei vielen nicht. Der Wert ist '
            'eine Konvention, keine Messung.',
      ),
      Misconception(
        claim: 'Wenn mein Laktat niedriger ist, bin ich fitter.',
        correction:
            'Nicht ohne Kontext. Ein entleerter Kohlenhydratspeicher senkt '
            'die Werte, ohne dass sich die Leistungsfähigkeit verbessert hat.',
      ),
    ],
    related: ['lt2', 'stufentest', 'laktat'],
    sources: [_faude2009, _jamnick2020, _beneke2011],
  ),

  AcademyArticle(
    id: 'vo2max',
    title: 'Was ist VO2max — und was sagt sie nicht?',
    summary:
        'Die maximale Sauerstoffaufnahme ist eine Obergrenze, keine '
        'Vorhersage der Wettkampfleistung.',
    category: AcademyCategory.physiology,
    evidence: EvidenceLevel.strong,
    tags: ['vo2max', 'aerobic_capacity'],
    relatedParameters: ['vo2max'],
    brief: [
      'VO2max beschreibt, wie viel Sauerstoff der Körper bei maximaler '
          'Belastung höchstens aufnehmen und verwerten kann.',
      'Sie ist eine wichtige Grösse — aber unter Athleten mit ähnlicher '
          'VO2max entscheiden Schwellenleistung und Bewegungsökonomie über '
          'das Rennen.',
    ],
    detailed: [
      'Begrenzend ist bei den meisten gesunden Menschen vor allem der '
          'Sauerstofftransport: Herzzeitvolumen und Sauerstofftransport im '
          'Blut. Die Muskulatur könnte in der Regel mehr verwerten, als '
          'geliefert wird.',
      'Für die Ausdauerleistung zählen drei Grössen zusammen: die '
          'Obergrenze (VO2max), der Anteil davon, der über die '
          'Wettkampfdauer haltbar ist (Schwellenleistung), und wie viel '
          'Sauerstoff eine gegebene Geschwindigkeit kostet (Ökonomie).',
      'Bei trainierten Athleten verändert sich die Obergrenze langsamer und '
          'weniger als die beiden anderen Grössen. Deshalb ist ein '
          'Trainingsplan, der ausschliesslich auf VO2max zielt, für sie '
          'selten der beste.',
    ],
    science: [
      'Das Zusammenspiel von maximaler Sauerstoffaufnahme, Schwellenanteil '
          'und Ökonomie als Determinanten der Ausdauerleistung ist gut '
          'belegt und über Sportarten hinweg reproduziert.',
      'Intervallformen, die eine lange Zeit nahe der maximalen '
          'Sauerstoffaufnahme erzeugen, gelten als wirksam für diese Grösse; '
          'die optimale Gestaltung von Dauer, Anzahl und Pause ist jedoch '
          'nicht abschliessend geklärt und hängt vom Trainingszustand ab.',
      'Absolute Zahlenvergleiche zwischen Sportarten sind nur eingeschränkt '
          'sinnvoll: Die gemessene VO2max hängt von der eingesetzten '
          'Muskelmasse und der Bewegungsform ab.',
    ],
    misconceptions: [
      Misconception(
        claim: 'Wer die höhere VO2max hat, gewinnt.',
        correction:
            'In homogenen Leistungsgruppen sagt sie das Rennergebnis kaum '
            'voraus. Dort entscheiden Schwellenleistung und Ökonomie.',
      ),
    ],
    practicalExample:
        'Vier bis sechs Wiederholungen von drei bis fünf Minuten deutlich '
        'oberhalb von LT2, mit Pausen, die die nächste Wiederholung in '
        'gleicher Qualität erlauben.',
    related: ['lt2', 'lt1-vs-lt2', 'entlastung'],
    sources: [_bassett2000, _buchheit2013, _jamnick2020],
  ),

  AcademyArticle(
    id: 'entlastung',
    title: 'Warum es Entlastungswochen gibt',
    summary:
        'Die Anpassung entsteht nicht im Training, sondern in der Erholung '
        'danach.',
    category: AcademyCategory.recovery,
    evidence: EvidenceLevel.contextual,
    tags: ['recovery', 'periodisation', 'load'],
    brief: [
      'Training setzt einen Reiz und erzeugt Ermüdung. Die Leistungsfähigkeit '
          'steigt erst, wenn die Ermüdung abgebaut ist und die Anpassung '
          'bleibt.',
      'Eine Entlastungswoche macht die vorangegangene Arbeit sichtbar. Ohne '
          'sie summiert sich Ermüdung, und die Form bleibt unter dem, was '
          'möglich wäre.',
    ],
    detailed: [
      'Über mehrere Belastungswochen sammelt sich Ermüdung schneller an, als '
          'sie zwischen einzelnen Einheiten abgebaut wird. Das ist gewollt: '
          'Der aufgeschobene Abbau ist Teil des Reizes.',
      'Wird die Belastung dann reduziert, fällt die Ermüdung schneller als '
          'die aufgebaute Anpassung. In dieser Phase steigt die messbare '
          'Leistungsfähigkeit — nicht, weil in der Entlastungswoche etwas '
          'aufgebaut würde, sondern weil sichtbar wird, was vorher entstanden '
          'ist.',
      'Wie stark und wie oft entlastet werden muss, hängt vom '
          'Trainingszustand, vom Alter, vom Umfang und vom Rest des Lebens '
          'ab. Feste Rhythmen wie «drei zu eins» sind Ausgangspunkte, keine '
          'Vorschriften.',
    ],
    science: [
      'Die Grundvorstellung von Belastung, Erholung und Anpassung ist gut '
          'etabliert; die quantitative Modellierung ist es nicht. Modelle '
          'zur Trainingswirkung beschreiben Verläufe brauchbar, taugen aber '
          'nicht als individuelle Vorhersage.',
      'Zur Erkennung von Überlastung existieren Konsenspapiere. Sie betonen '
          'übereinstimmend, dass kein einzelner Messwert — weder Ruhepuls '
          'noch Herzratenvariabilität noch ein Bereitschaftswert eines '
          'Geräts — für sich genommen ausreicht.',
      'Belastbar ist die Kombination: Trainingsdaten, subjektives '
          'Belastungsempfinden, Leistung in Standardeinheiten und Schlaf im '
          'Verlauf — nicht als Tageswert, sondern als Muster über Wochen.',
    ],
    misconceptions: [
      Misconception(
        claim:
            'Mein Bereitschaftswert war heute niedrig, also ist die '
            'Einheit sinnlos.',
        correction:
            'Ein einzelner abgeleiteter Wert eines Geräts ist ein Hinweis, '
            'keine Diagnose. Entscheidend ist das Muster über Wochen im '
            'Zusammenspiel mit Trainingsdaten und Empfinden.',
      ),
      Misconception(
        claim: 'Wer sich gut fühlt, braucht keine Entlastung.',
        correction:
            'Ermüdung kumuliert, bevor sie sich meldet. Entlastungswochen '
            'werden geplant, nicht abgewartet.',
      ),
    ],
    related: ['training-unter-lt1', 'lt1-vs-lt2'],
    sources: [_meeusen2013, _halson2014, _seiler2010],
  ),

  AcademyArticle(
    id: 'stufentest',
    title: 'Was ist ein Laktatstufentest?',
    summary:
        'Eine Folge ansteigender Belastungsstufen mit Blutentnahme am Ende '
        'jeder Stufe — und ein Protokoll, das zum Ergebnis gehört.',
    category: AcademyCategory.diagnostics,
    evidence: EvidenceLevel.strong,
    tags: ['lactate', 'testing', 'protocol'],
    relatedParameters: ['lt1', 'lt2', 'lactate'],
    brief: [
      'Die Belastung wird stufenweise gesteigert; am Ende jeder Stufe werden '
          'Laktat und Herzfrequenz festgehalten.',
      'Aus dem Verlauf über die Stufen entsteht die Laktatleistungskurve und '
          'daraus die Schwellen.',
    ],
    detailed: [
      'Entscheidend ist die Gleichmässigkeit: gleiche Stufendauer, gleiche '
          'Steigerung, gleicher Entnahmezeitpunkt. Ändert sich davon etwas, '
          'ändert sich die Kurve — auch wenn sich am Athleten nichts geändert '
          'hat.',
      'Kürzere Stufen führen bei gleicher Leistung zu niedrigeren '
          'Laktatwerten, weil sich die Konzentration noch nicht eingestellt '
          'hat. Längere Stufen erlauben stabilere Werte, verlängern aber den '
          'Test und erhöhen die Ermüdung.',
      'Zum Ergebnis gehören deshalb immer: Protokoll, Stufendauer, '
          'Steigerung, Sportart, Gerät und der Zustand vor dem Test.',
    ],
    science: [
      'Die Protokollabhängigkeit von Schwellenwerten ist gut dokumentiert. '
          'Vergleiche zwischen Tests mit unterschiedlicher Stufendauer sind '
          'ohne Umrechnung nicht zulässig — und die Umrechnung ist ihrerseits '
          'unsicher.',
      'Messfehler des Analysegeräts, Entnahmeort und Vorbelastung tragen '
          'zusätzlich zur Streuung bei. Eine Verschiebung von wenigen Watt '
          'zwischen zwei Tests liegt möglicherweise im Rauschen.',
      'Aussagekräftig werden Verläufe über mehrere Tests unter gleichen '
          'Bedingungen — nicht der Vergleich zweier Einzelmessungen.',
    ],
    misconceptions: [
      Misconception(
        claim: 'Zwei Tests lassen sich immer vergleichen.',
        correction:
            'Nur bei gleichem Protokoll, gleicher Sportart und gleichem '
            'Auswerteverfahren. Sonst vergleicht man Verfahren, nicht '
            'Athleten.',
      ),
    ],
    related: ['laktat', 'lt1', 'lt2', 'vier-mmol'],
    sources: [_beneke2011, _faude2009, _jamnick2020],
  ),

  AcademyArticle(
    id: 'schwellentraining',
    title: 'Schwellentraining gezielt einsetzen',
    summary:
        'Arbeit an LTP2 ist präzise dosiert: genug Zeit nahe der Schwelle, '
        'ohne jede Wiederholung zum Test zu machen.',
    category: AcademyCategory.planning,
    evidence: EvidenceLevel.good,
    tags: ['threshold_training', 'lt2', 'intervals'],
    relatedParameters: ['lt2'],
    brief: [
      'Schwellenintervalle sammeln kontrollierte Zeit knapp unter bis an '
          'LTP2. Ziel ist eine stabile Leistung über alle Wiederholungen.',
      'Wenn Leistung, Technik oder RPE früh entgleisen, war die Vorgabe für '
          'diesen Tag wahrscheinlich zu hoch.',
    ],
    detailed: [
      'Pausen machen die Belastung wiederholbar; sie verwandeln die Einheit '
          'nicht in Sprinttraining. Die gesamte Qualitätszeit ist wichtiger '
          'als eine besonders harte erste Wiederholung.',
      'Die passende Dosis hängt von Sportart, Trainingszustand und Phase ab. '
          'GIULIA bezieht die Vorgabe deshalb auf eine gemessene, '
          'methodentransparente Schwelle statt auf einen universellen Puls.',
    ],
    science: [
      'LTP2 aus einem Stufentest ist eine Schätzung des höchsten noch '
          'stabilisierbaren Bereichs. Protokoll und Schwellenmethode '
          'begrenzen die Genauigkeit der Trainingsvorgabe.',
      'Intervallstudien stützen mehrere wirksame Gestaltungen; eine für alle '
          'Athleten überlegene Kombination aus Dauer und Pause ist nicht '
          'belegt.',
    ],
    practicalExample:
        'Viermal acht Minuten knapp unter bis an LTP2, mit drei Minuten '
        'lockerer Pause und gleichmässiger Leistung.',
    progressMarkers: [
      'Mehr stabile Qualitätszeit bei gleichem RPE',
      'Höhere Leistung an derselben Schwellenmethode',
    ],
    related: ['lt2', 'intervalle', 'entlastung'],
    sources: [_buchheit2013, _faude2009, _jamnick2020],
  ),

  AcademyArticle(
    id: 'intervalle',
    title: 'Intervalle für VO2max und hohe aerobe Leistung',
    summary:
        'Gute Intervalle maximieren nicht den Schmerz, sondern die '
        'wiederholbare Zeit mit hoher aerober Beanspruchung.',
    category: AcademyCategory.planning,
    evidence: EvidenceLevel.good,
    tags: ['intervals', 'vo2max', 'high_intensity'],
    relatedParameters: ['vo2max', 'lt2'],
    brief: [
      'Drei- bis fünfminütige Intervalle oberhalb von LTP2 können viel Zeit '
          'bei hoher Sauerstoffaufnahme erzeugen.',
      'Die Pause soll die nächste Wiederholung ermöglichen. Ein kompletter '
          'Einbruch ist kein Qualitätsmerkmal.',
    ],
    detailed: [
      'Leistung, Dauer, Anzahl und Pause greifen ineinander. Kürzere Pausen '
          'halten die Beanspruchung hoch, können aber die folgende Leistung '
          'senken.',
      'Eine harte Einheit wird erst durch die Verteilung über die Woche '
          'sinnvoll. Readiness ist deshalb eine begründete Entscheidung aus '
          'Verlauf und Empfinden, keine Tageszahl.',
    ],
    science: [
      'Hohe aerobe Intervalle sind für die Entwicklung maximaler aerober '
          'Leistung gut gestützt. Die Reaktion streut individuell deutlich.',
      'Zeit nahe VO2max ist ein plausibler Mechanismus, aber kein alleiniger '
          'Beweis für die langfristige Wirksamkeit einer Einheit.',
    ],
    practicalExample:
        'Fünfmal vier Minuten deutlich oberhalb von LTP2; die letzte '
        'Wiederholung bleibt technisch und leistungsmässig kontrolliert.',
    related: ['vo2max', 'schwellentraining', 'belastungssteuerung'],
    sources: [_buchheit2013, _bishop2014, _bassett2000],
  ),

  AcademyArticle(
    id: 'belastungssteuerung',
    title: 'Belastung steuern ohne falsche Readiness-Präzision',
    summary:
        'Eine Trainingsentscheidung braucht Verlauf, letzte harte Belastung '
        'und subjektives Empfinden — kein erfundenes Tagesprozent.',
    category: AcademyCategory.recovery,
    evidence: EvidenceLevel.contextual,
    tags: ['load', 'readiness', 'rpe', 'recovery'],
    brief: [
      'Ein einzelner Wert entscheidet nicht über die Einheit. Erst mehrere '
          'Hinweise im Verlauf machen eine Anpassung plausibel.',
      'Fehlen Schlaf- oder Erholungsangaben, muss diese Lücke sichtbar '
          'bleiben.',
    ],
    detailed: [
      'Trainingsdauer und Intensität beschreiben die äussere Belastung; RPE '
          'und Reaktion beschreiben, wie sie ankam. Beide Seiten gehören '
          'zusammen.',
      'Ein ungewöhnliches Muster ist ein Anlass zum Nachfragen, nicht zum '
          'Diagnostizieren. Anhaltende Beschwerden gehören in fachkundige '
          'medizinische Abklärung.',
    ],
    science: [
      'Monitoring-Literatur empfiehlt die Kombination mehrerer belastbarer '
          'Signale. Kein einzelner Marker erkennt Ermüdung oder Überlastung '
          'hinreichend sicher.',
      'Akut-chronische Quotienten und abgeleitete Scores können beschreiben, '
          'dürfen aber ohne individuelle Validierung keine Kausalität '
          'beanspruchen.',
    ],
    related: ['entlastung', 'intervalle', 'fortschritt-interpretieren'],
    sources: [_halson2014, _meeusen2013],
  ),

  AcademyArticle(
    id: 'testvorbereitung',
    title: 'Einen Stufentest vergleichbar vorbereiten',
    summary:
        'Ein guter Vergleich beginnt vor der ersten Stufe: Vorbelastung, '
        'Ernährung, Zeitpunkt und Protokoll möglichst konstant halten.',
    category: AcademyCategory.diagnostics,
    evidence: EvidenceLevel.good,
    tags: ['testing', 'protocol', 'preparation', 'quality'],
    relatedParameters: ['lactate', 'lt1', 'lt2'],
    brief: [
      'Teste möglichst zur gleichen Tageszeit, mit ähnlicher Vorbelastung '
          'und einem dokumentierten Ernährungszustand.',
      'Sportart, Gerät, Stufendauer und Steigerung müssen für einen direkten '
          'Verlauf gleich bleiben.',
    ],
    detailed: [
      'Eine intensive Einheit am Vortag, veränderte Kohlenhydratzufuhr oder '
          'ein anderer Entnahmezeitpunkt können die Laktatkurve verschieben.',
      'GIULIA trennt deshalb Messwert, Protokoll und Interpretation. Ein '
          'formal schöner Kurvenvergleich ersetzt keine Vergleichbarkeit.',
    ],
    science: [
      'Blutlaktat ist eine Nettogrösse aus Produktion und Verwertung und '
          'reagiert auf mehrere präanalytische Einflüsse.',
      'Standardisierung reduziert Streuung, beseitigt Messfehler aber nicht. '
          'Kleine Veränderungen bleiben entsprechend unsicher.',
    ],
    related: ['stufentest', 'laktat', 'fortschritt-interpretieren'],
    sources: [_beneke2011, _faude2009],
  ),

  AcademyArticle(
    id: 'radfahren',
    title: 'Leistung beim Radfahren einordnen',
    summary:
        'Watt ist beim Radfahren direkt messbar; aussagekräftig wird es erst '
        'mit Dauer, Körpermasse, Position und Testprotokoll.',
    category: AcademyCategory.sportSpecific,
    sport: AcademySport.cycling,
    evidence: EvidenceLevel.good,
    tags: ['cycling', 'power', 'economy', 'sport_specific'],
    relatedParameters: ['lt1', 'lt2'],
    brief: [
      'Radschwellen werden in Watt beschrieben und nur mit Radtests '
          'verglichen. Eine Laufschwelle ist keine alternative Wattmessung.',
      'Für den Verlauf zählt dieselbe Ergometer- und Protokollkonfiguration.',
    ],
    detailed: [
      'Absolute Watt und Watt pro Kilogramm beantworten unterschiedliche '
          'Fragen. Auf flacher Strecke zählt Aerodynamik anders als am Berg.',
      'Sitzposition und Tritttechnik können die gemessene Leistung und '
          'Ökonomie verändern, ohne dass daraus direkt eine physiologische '
          'Ursache folgt.',
    ],
    science: [
      'VO2max, Schwellenleistung und Ökonomie tragen gemeinsam zur '
          'Ausdauerleistung bei; ihre Gewichtung ist disziplinspezifisch.',
      'Ergometerwerte sind bewegungsformspezifisch. Eine Übertragung auf '
          'Laufen oder Oberkörperarbeit ist fachlich nicht zulässig.',
    ],
    related: ['lt1', 'lt2', 'kraft-stabilisation'],
    sources: [_bassett2000, _ronnestad2014],
  ),

  AcademyArticle(
    id: 'laufen',
    title: 'Pace, Geschwindigkeit und Laufökonomie',
    summary:
        'Beim Laufen beschreibt Pace das Ergebnis; Ökonomie beschreibt, wie '
        'viel Energie diese Geschwindigkeit kostet.',
    category: AcademyCategory.sportSpecific,
    sport: AcademySport.running,
    evidence: EvidenceLevel.good,
    tags: ['running', 'pace', 'speed', 'economy', 'sport_specific'],
    relatedParameters: ['lt1', 'lt2'],
    brief: [
      'Pace und Geschwindigkeit sind zwei Darstellungen derselben '
          'Belastungsvariable. Vergleiche müssen dieselbe Einheit verwenden.',
      'Untergrund, Steigung und Wind verändern die Kosten einer Pace.',
    ],
    detailed: [
      'Eine höhere Geschwindigkeit bei gleicher physiologischer '
          'Beanspruchung kann aus besserer aerober Leistung, besserer '
          'Laufökonomie oder beidem entstehen.',
      'Darum beschreibt GIULIA die beobachtete Veränderung, behauptet aber '
          'ohne zusätzliche Messung nicht deren Ursache.',
    ],
    science: [
      'VO2max, der haltbare Anteil davon und Laufökonomie sind etablierte '
          'Determinanten. Stufentests erfassen sie nicht alle direkt.',
      'Krafttraining kann die Laufökonomie verbessern; Effekte und optimale '
          'Dosis unterscheiden sich zwischen Populationen.',
    ],
    related: ['vo2max', 'kraft-stabilisation', 'testvorbereitung'],
    sources: [_bassett2000, _ronnestad2014],
  ),

  AcademyArticle(
    id: 'langlauf',
    title: 'Langlauf ist eine wechselnde Ganzkörperbelastung',
    summary:
        'Gelände und Technik verändern im Langlauf fortlaufend, welche '
        'Muskelgruppen die Leistung erzeugen.',
    category: AcademyCategory.sportSpecific,
    sport: AcademySport.crossCountrySkiing,
    evidence: EvidenceLevel.good,
    tags: ['cross_country', 'skiing', 'technique', 'sport_specific'],
    relatedParameters: ['lt1', 'lt2'],
    brief: [
      'Eine Schwelle gehört zur getesteten Technik und Bewegungsform. '
          'Doppelstock, Skating und Laufen sind nicht direkt austauschbar.',
      'Technikwechsel und Gelände machen Geschwindigkeit allein als '
          'Belastungsmass unzuverlässig.',
    ],
    detailed: [
      'Langlauf kombiniert hohe aerobe Anforderungen mit wechselnder '
          'Ober- und Unterkörperbeteiligung. Das macht sportartspezifische '
          'Tests und technische Kontextdaten besonders wichtig.',
      'Für den Verlauf sollten Technik, Ergometer oder Strecke und Protokoll '
          'konstant dokumentiert werden.',
    ],
    science: [
      'Elite-Langlauf erfordert hohe aerobe Kapazität, Ökonomie sowie Kraft '
          'und Geschwindigkeit; die Anforderungen variieren nach Disziplin.',
      'Ergebnisse aus einer Teilkörper-Belastungsform dürfen nicht wie '
          'Ganzkörperwerte interpretiert werden.',
    ],
    related: ['ercolina-technik', 'vo2max', 'kraft-stabilisation'],
    sources: [_sandbakk2017, _hegge2016],
  ),

  AcademyArticle(
    id: 'ercolina-technik',
    title: 'Ercolina: Wie entsteht die Leistung?',
    summary:
        'Gesamtleistung entsteht aus Arbeit je Zug, Zugfrequenz, Seitigkeit '
        'und deren Stabilität — Watt allein erklärt die Technik nicht.',
    category: AcademyCategory.sportSpecific,
    sport: AcademySport.ercolina,
    evidence: EvidenceLevel.contextual,
    tags: ['ercolina', 'ski_erg', 'poling', 'symmetry', 'technique'],
    relatedParameters: ['symmetry'],
    brief: [
      'Dieselben Watt können mit kräftigeren Einzelzügen oder höherer '
          'Frequenz entstehen. Beides stellt andere technische Anforderungen.',
      'Links-rechts-Abweichung und Ermüdung werden im Verlauf beurteilt, '
          'nicht aus einem einzelnen Zug diagnostiziert.',
    ],
    detailed: [
      'Arbeit je Zug und Frequenz erklären zusammen die mittlere Leistung. '
          'Intervalle zeigen, ob dieses Muster bei Ermüdung stabil bleibt.',
      'Fehlen Zuglänge, Zugzeit oder Force-Curve, darf GIULIA daraus keine '
          'verdeckte Koordinationsmetrik erfinden.',
    ],
    science: [
      'Oberkörper-, Arm- und Ganzkörper-Doppelstockarbeit unterscheiden '
          'sich in einbezogener Muskelmasse und erreichbarer Leistung.',
      'Asymmetrie ist zunächst eine Beschreibung. Ihre Ursache oder '
          'medizinische Bedeutung erfordert weitere Untersuchung.',
    ],
    related: ['langlauf', 'kraft-stabilisation', 'belastungssteuerung'],
    sources: [_hegge2016, _sandbakk2017],
  ),

  AcademyArticle(
    id: 'kraft-stabilisation',
    title: 'Kraft und Stabilisation für Ausdauerleistung',
    summary:
        'Krafttraining ergänzt Ausdauertraining vor allem über '
        'neuromuskuläre Leistung und Bewegungsökonomie.',
    category: AcademyCategory.strength,
    evidence: EvidenceLevel.good,
    tags: ['strength', 'stability', 'economy', 'injury_prevention'],
    brief: [
      'Schweres oder explosives Krafttraining kann die Ökonomie verbessern, '
          'ohne dass VO2max steigen muss.',
      'Die Übungsauswahl soll zur Sportart und Trainingsphase passen.',
    ],
    detailed: [
      'Für Ausdauersportler geht es nicht nur um Muskelmasse. '
          'Kraftentwicklung, Sehnensteifigkeit und neuromuskuläre Effizienz '
          'können die Bewegungskosten beeinflussen.',
      'Kraft- und Ausdauerreize benötigen gemeinsam geplante Erholung. Mehr '
          'ist nicht automatisch besser.',
    ],
    science: [
      'Reviews zeigen Vorteile kombinierten Kraft- und Ausdauertrainings für '
          'Lauf- und Radökonomie; Schwellen- und VO2max-Effekte sind weniger '
          'einheitlich.',
      'Eine allgemeine Verletzungsdiagnose oder individuelle '
          'Rehabilitation lässt sich daraus nicht ableiten.',
    ],
    related: ['laufen', 'radfahren', 'ercolina-technik'],
    sources: [_ronnestad2014],
  ),

  AcademyArticle(
    id: 'sporternaehrung',
    title: 'Ernährung unterstützt Belastung und Erholung',
    summary:
        'Energie- und Kohlenhydratverfügbarkeit beeinflussen Leistung und '
        'Laktatkontext; Ernährung ersetzt weder Training noch Diagnostik.',
    category: AcademyCategory.nutrition,
    evidence: EvidenceLevel.strong,
    tags: ['nutrition', 'carbohydrate', 'recovery', 'hydration'],
    brief: [
      'Harte oder lange Einheiten brauchen passende Energie- und '
          'Kohlenhydratverfügbarkeit. Danach unterstützt Ernährung die '
          'Erholung.',
      'Ein Test mit deutlich anderem Ernährungszustand ist schlechter mit '
          'früheren Tests vergleichbar.',
    ],
    detailed: [
      'Bedarf und Timing hängen von Dauer, Intensität, Gesamtumfang und '
          'individueller Verträglichkeit ab. Eine starre Vorgabe passt nicht '
          'zu jeder Einheit.',
      'GIULIA darf Ernährungsstatus als möglichen Kontext nennen, aber aus '
          'einer Laktatkurve keine Unterversorgung diagnostizieren.',
    ],
    science: [
      'Konsenspapiere stützen periodisierte, an Trainingsanforderungen '
          'angepasste Energie-, Flüssigkeits- und Makronährstoffzufuhr.',
      'Individuelle klinische Fragen und anhaltende Beschwerden gehören zu '
          'qualifizierter Ernährungs- oder medizinischer Betreuung.',
    ],
    related: ['testvorbereitung', 'belastungssteuerung', 'entlastung'],
    sources: [_thomas2016],
  ),

  AcademyArticle(
    id: 'fortschritt-interpretieren',
    title: 'Fortschritt, Plateau und Messrauschen unterscheiden',
    summary:
        'Eine Veränderung wird belastbar, wenn sie unter vergleichbaren '
        'Bedingungen wiederkehrt und mehrere passende Signale zusammenpassen.',
    category: AcademyCategory.progress,
    evidence: EvidenceLevel.good,
    tags: ['trend', 'plateau', 'comparison', 'uncertainty'],
    relatedParameters: ['lt1', 'lt2', 'lactate'],
    brief: [
      'Ein einzelner Sprung kann Trainingseffekt, Tagesform oder Messstreuung '
          'sein. Mehrere vergleichbare Tests zeigen den Trend besser.',
      'Ein Plateau ist zunächst eine Beschreibung, keine Erklärung.',
    ],
    detailed: [
      'Aussagekräftige Muster sind beispielsweise höhere Leistung an '
          'derselben Schwellenmethode oder niedrigeres Laktat an einer exakt '
          'gemeinsamen Belastungsstufe.',
      'Ändern sich Sportart, Protokoll, Einheit oder Methode, blockiert '
          'GIULIA den numerischen Vergleich statt eine Scheinpräzision zu '
          'erzeugen.',
    ],
    science: [
      'Messfehler, biologische Variation und Modellunsicherheit wirken '
          'gleichzeitig. Wiederholte standardisierte Messungen erhöhen die '
          'Aussagekraft.',
      'Eine zeitliche Korrelation zwischen Training und Testveränderung '
          'belegt für sich keine Ursache.',
    ],
    related: ['stufentest', 'testvorbereitung', 'belastungssteuerung'],
    sources: [_beneke2011, _faude2009, _halson2014],
  ),
];
