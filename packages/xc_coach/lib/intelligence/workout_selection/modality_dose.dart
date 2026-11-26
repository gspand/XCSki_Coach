/// Welche Dauer einer Modalität für diesen Athleten **heute** plausibel ist.
///
/// ## Warum das eine eigene Stelle ist
///
/// Der Bedarf und die Dosis sind zwei Fragen. Ein Athlet kann einen großen
/// Bedarf an langer aerober Arbeit haben und trotzdem keine plausible
/// Drei-Stunden-Laufdosis besitzen. Vorher war die Antwort auf die zweite
/// Frage über den Core verteilt: eine Lauf-Sonderlogik mit Faktoren 1,25 /
/// 1,4, ein Steigerungsdeckel in der Planung mit Faktor 1,5, und ein
/// Punktebonus dafür, das verfügbare Zeitfenster „optimal auszunutzen". Für
/// alle Modalitäten außer Laufen lag die Grenze bei 360 Minuten.
///
/// Diese Datei ist die einzige Stelle, die eine plausible Dosis ableitet.
///
/// ## Die Regel, in einem Satz
///
/// **Plausibel ist, was belegt ist — und ein Schritt darüber, wenn der Beleg
/// sich wiederholt hat.**
///
/// Daraus folgt alles Weitere, und es kommt ohne erfundene Prozentsätze aus:
///
/// * Die Obergrenze ist eine **tatsächlich gefahrene** Dauer, nicht eine
///   gerechnete. Keine Zehn-Prozent-Regel, kein Steigerungsfaktor.
/// * Ein Fortschritt ist der **nächste Schritt, den die Bibliothek anbietet**
///   — eine diskrete Stufe aus [WorkoutFamily.allowedVariants], nicht eine
///   Multiplikation. Er wird nur erlaubt, wenn die bisherige Dauer
///   wiederholbar war.
/// * Die Einstiegsdosis ist die **kleinste Einheit, die das Produkt für
///   diese Modalität kennt**. Auch sie ist damit keine erfundene Zahl.
///
/// ## Wiederholbar heißt: mehr als ein Beleg
///
/// Die echten Daten zeigen beide Richtungen. Beim Rad lagen 368 und 364
/// Minuten nebeneinander — ein Plateau, die Dauer war wiederholbar. Beim
/// Laufen standen 229 Minuten neben einem Median von 57 — ein Ausreißer, und
/// obendrein eine Wanderung. Darum entscheidet nicht das Maximum und nicht
/// der Median, sondern [SkiModalityExposure.longSessionCount90d]: Wie viele
/// Einheiten haben die längste Dauer annähernd erreicht?
///
/// ## UNKNOWN ist nicht NULL
///
/// Fehlende Daten dürfen nicht großzügiger machen als bekannte, geringe
/// Exposition. Vorher war es umgekehrt: `stepUpMinutes(null)` gab keinen
/// Deckel zurück, und wer eine Modalität nie trainiert hatte, bekam deshalb
/// *mehr* erlaubt als jemand mit einer kurzen Einheit. Hier gilt:
///
///     unbekannt  ≤  nicht beobachtet  ≤  gering  ≤  belastbar
///
/// Bei Unkenntnis fällt zusätzlich die Zuversicht — ohne dass eine erfundene
/// Sicherheitsgrenze eingeführt wird.
library;

import '../../domain/xc_modality.dart';
import '../training_need/need_types.dart';
import '../xc_athlete_state/data_coverage_state.dart';
import '../xc_athlete_state/ski_exposure_state.dart';
import 'workout_family.dart';

/// Version dieser Ableitung.
///
/// Eine gespeicherte Entscheidung bleibt nur erklärbar, wenn man weiß, nach
/// welcher Regel sie entstand. Ändert sich die Regel, ändert sich diese Zahl.
const String modalityDoseModelVersion = 'giulia-modality-dose-v1';

/// Wie gut die Exposition dieser Modalität belegt ist.
enum ExposureEvidence {
  /// Mehrere Einheiten im Fenster, die Dauer ist wiederholbar.
  established('belastbar'),

  /// Einzelne Einheiten — ein Anfang, kein Plateau.
  limited('gering'),

  /// Bei guter Datenlage keine Einheit beobachtet. Eine Aussage, nicht eine
  /// Lücke: Der Athlet macht das derzeit nicht.
  none('nicht beobachtet'),

  /// Die Datenlage trägt die Frage nicht. Keine Aussage.
  unknown('unbekannt');

  const ExposureEvidence(this.label);
  final String label;
}

/// Die plausible Dosis einer Modalität, samt Begründung.
class PlausibleDose {
  const PlausibleDose({
    required this.modality,
    required this.ceilingMinutes,
    required this.evidence,
    required this.confidence,
    required this.reason,
    this.signals = const [],
  });

  final XcModality modality;

  /// Die obere plausible Dauer in Minuten. Eine Obergrenze, kein Ziel.
  final int ceilingMinutes;

  final ExposureEvidence evidence;
  final NeedConfidence confidence;

  /// Ein Satz, der die Zahl aus den Daten erklärt.
  final String reason;

  /// Die Signale, die zur Zahl geführt haben — für Replay und Debug.
  final List<String> signals;

  Map<String, dynamic> toJson() => {
    'modelVersion': modalityDoseModelVersion,
    'modality': modality.key,
    'ceilingMinutes': ceilingMinutes,
    'evidence': evidence.name,
    'confidence': confidence.name,
    'reason': reason,
    'signals': signals,
  };

  @override
  String toString() =>
      '${modality.name}: ≤$ceilingMinutes min (${evidence.label}, '
      '${confidence.name})';
}

/// Leitet die plausible Dosis je Modalität ab. Zustandslos.
class ModalityDoseModel {
  const ModalityDoseModel();

  /// Ab wie vielen Tagen ohne Synchronisation die Frage nicht mehr beantwortbar
  /// ist.
  ///
  /// Nicht als Sicherheitsgrenze gedacht, sondern als Aussage über die Daten:
  /// Wer von achtundzwanzig Tagen die Hälfte nicht kennt, kann über die
  /// Exposition der letzten Wochen nichts sagen.
  static const int _unknownDaysThreshold = 14;

  /// Ab wie vielen Einheiten im Neunzig-Tage-Fenster von Belastbarkeit die
  /// Rede sein kann.
  static const int _establishedSessionCount = 4;

  /// Die kleinste Einheit, die das Produkt für diese Modalität kennt.
  ///
  /// Keine erfundene Einstiegszahl: Was die Bibliothek als kürzeste Variante
  /// anbietet, ist die kleinste Dosis, die das Produkt für sinnvoll hält.
  /// Die Einstiegsdosis einer Modalität: Was zumutbar ist, wenn über diese
  /// Bewegungsform nichts bekannt ist.
  ///
  /// Dieser Wert ist ausdrücklich eine Konstante und **nicht** die kürzeste
  /// Einheit des Katalogs. Der Unterschied ist nicht akademisch: Als der
  /// Katalog um eine zwanzigminütige Technikeinheit erweitert wurde, sank die
  /// zulässige Ercolina-Dosis von dreißig auf zwanzig Minuten — ein reicherer
  /// Katalog machte die Modalität scheinbar weniger belastbar. Das ist eine
  /// Eigenschaft der Dateiablage, keine des Athleten.
  ///
  /// Die Werte sind nach Belastungsart gestaffelt, nicht nach Sportart im
  /// Einzelnen: Gelenkbelastung und Umfangsgewöhnung unterscheiden sich
  /// zwischen Laufen, Rollski, Schnee, Zuggerät und Rad.
  static int entryMinutesFor(XcModality modality) => switch (modality) {
    // Oberkörperdominantes Zuggerät: kein Aufprall, aber eine lokale
    // Muskelgruppe, die als Erstes ermüdet.
    XcModality.ercolinaDoublePoling => 30,
    // Schnee und Rollski: Technik begrenzt den Umfang, nicht das Herz.
    XcModality.skiSkating ||
    XcModality.skiClassic ||
    XcModality.skiNordicUnknown ||
    XcModality.doublePoling ||
    XcModality.rollerSkiSkating ||
    XcModality.rollerSkiClassic ||
    XcModality.rollerSkiDoublePoling ||
    XcModality.rollerSkiUnknown => 45,
    // Laufen: die höchste Gelenkbelastung pro Minute.
    XcModality.running => 45,
    // Rad: die niedrigste.
    XcModality.cycling => 60,
    // Für diese Modalitäten verschreibt der Coach nichts. Dann gibt es auch
    // keine Dosis zu raten.
    XcModality.strength || XcModality.other || XcModality.unknown => 0,
  };

  /// Die nächste Stufe, die die Bibliothek über [minutes] anbietet.
  ///
  /// Fortschritt in diskreten Schritten des eigenen Katalogs statt in
  /// Prozenten: «Du hast wiederholt fünfundvierzig Minuten gefahren, die
  /// nächste Einheit, die es dafür gibt, dauert sechzig.»
  static int? nextVariantAbove(XcModality modality, int minutes) {
    final above = <int>[
      for (final family in WorkoutFamily.standardFamilies)
        if (family.modality == modality)
          for (final variant in family.allowedVariants)
            if (variant.totalDurationMinutes > minutes)
              variant.totalDurationMinutes,
    ];
    if (above.isEmpty) return null;
    return above.reduce((a, b) => a < b ? a : b);
  }

  /// Die plausible Dosis für [modality].
  PlausibleDose doseFor({
    required XcModality modality,
    required SkiModalityExposure exposure,
    required DataCoverageState coverage,
  }) {
    final entry = entryMinutesFor(modality);
    final signals = <String>[
      'n28=${exposure.sessionCount28d}',
      'n90=${exposure.sessionCount90d}',
      'laengste90=${exposure.longestMinutes90d}',
      'laengste28=${exposure.longestMinutes28d}',
      'median90=${exposure.medianMinutes90d}',
      'plateau=${exposure.longSessionCount90d}',
      'seitTagen=${exposure.daysSinceLastSession ?? "-"}',
      'unbekannteTage28=${coverage.unknownDays28d}',
    ];

    // 1. Trägt die Datenlage die Frage überhaupt?
    //
    // Ohne beobachtete Einheit **und** mit Datenlücken ist beides möglich:
    // Der Athlet macht es nicht, oder wir sehen es nur nicht. Das darf nicht
    // großzügiger ausfallen als bekannte geringe Exposition.
    if (exposure.sessionCount90d == 0 &&
        coverage.unknownDays28d >= _unknownDaysThreshold) {
      return PlausibleDose(
        modality: modality,
        ceilingMinutes: entry,
        evidence: ExposureEvidence.unknown,
        confidence: NeedConfidence.unknown,
        reason:
            'Keine beobachtete ${modality.label}-Einheit, und '
            '${coverage.unknownDays28d} der letzten 28 Tage sind nicht '
            'synchronisiert: Die Belastbarkeit ist unbekannt, nicht null. '
            'Es gilt die Einstiegsdosis.',
        signals: signals,
      );
    }

    // 2. Gute Datenlage, keine Einheit: eine Aussage, keine Lücke.
    if (exposure.sessionCount90d == 0) {
      return PlausibleDose(
        modality: modality,
        ceilingMinutes: entry,
        evidence: ExposureEvidence.none,
        confidence: NeedConfidence.high,
        reason:
            'Keine ${modality.label}-Einheit in 90 Tagen bei vollständiger '
            'Datenlage. Es gilt die Einstiegsdosis.',
        signals: signals,
      );
    }

    final demonstrated = exposure.longestMinutes90d;

    // Liegt die Verteilung nicht vor, ist die **Wiederholbarkeit** unbekannt
    // — nicht die Exposition. Dann gilt die belegte Dauer, aber ohne den
    // Schritt darüber. Ein Rückfall auf die Einstiegsdosis wäre hier falsch:
    // Er würde eine gefahrene Stunde behandeln wie eine nie gefahrene.
    if (exposure.durationsSeconds90d.isEmpty) {
      final ceiling = demonstrated > entry ? demonstrated : entry;
      return PlausibleDose(
        modality: modality,
        ceilingMinutes: ceiling,
        evidence: exposure.sessionCount90d >= _establishedSessionCount
            ? ExposureEvidence.established
            : ExposureEvidence.limited,
        confidence: NeedConfidence.moderate,
        reason:
            'Belegt sind $ceiling min ${modality.label}. Ob die Dauer '
            'wiederholbar war, lässt sich ohne die Verteilung der Einheiten '
            'nicht sagen — deshalb kein Schritt darüber.',
        signals: [...signals, 'verteilung=fehlt'],
      );
    }

    final repeatable = exposure.longSessionCount90d >= 2;

    // 3. Einzelne Einheiten: der Beleg gilt, ein Schritt darüber nicht.
    if (exposure.sessionCount90d < _establishedSessionCount) {
      final ceiling = demonstrated > entry ? demonstrated : entry;
      return PlausibleDose(
        modality: modality,
        ceilingMinutes: ceiling,
        evidence: ExposureEvidence.limited,
        confidence: NeedConfidence.moderate,
        reason:
            'Nur ${exposure.sessionCount90d} ${modality.label}-Einheit(en) in '
            '90 Tagen. Plausibel ist, was dabei belegt wurde: '
            '$ceiling min — ohne Steigerung.',
        signals: signals,
      );
    }

    // 4. Belastbar, aber die längste Einheit steht allein.
    if (!repeatable) {
      final fallback = <int>[
        exposure.secondLongestMinutes90d,
        exposure.medianMinutes90d,
        entry,
      ].reduce((a, b) => a > b ? a : b);
      return PlausibleDose(
        modality: modality,
        ceilingMinutes: fallback,
        evidence: ExposureEvidence.established,
        confidence: NeedConfidence.moderate,
        reason:
            'Die längste ${modality.label}-Einheit ($demonstrated min) steht '
            'allein; wiederholt wurden $fallback min. Ein einzelner '
            'Ausreißer trägt keine Dosis — auch wenn er echt war.',
        signals: signals,
      );
    }

    // 5. Belastbar und wiederholt: ein Schritt des Katalogs darüber.
    final next = nextVariantAbove(modality, demonstrated);
    final ceiling = next ?? demonstrated;
    return PlausibleDose(
      modality: modality,
      ceilingMinutes: ceiling,
      evidence: ExposureEvidence.established,
      confidence: NeedConfidence.high,
      reason: next == null
          ? '${exposure.longSessionCount90d} Einheiten erreichten '
                '$demonstrated min: wiederholt belegt. Die Bibliothek bietet '
                'darüber keine Stufe an.'
          : '${exposure.longSessionCount90d} Einheiten erreichten '
                '$demonstrated min: wiederholt belegt. Die nächste Stufe der '
                'Bibliothek ist $ceiling min.',
      signals: signals,
    );
  }
}
