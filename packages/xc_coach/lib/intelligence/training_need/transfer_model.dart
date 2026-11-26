/// Transfermodell (Training Transfer Model) zwischen Trainingsmodalität und Zielwettkampf.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - 3 Stunden Radfahren ist physiologisch wertvoll, aber NICHT gleichwertig mit 3 Stunden Skating.
/// - Keine pseudopräzisen Transferkoeffizienten (wie 0.82 oder 0.90) ohne empirische Begründung.
/// - Modellierung erfolgt ordinal/qualitativ in 4 getrennten Dimensionen:
///   1. physiologicalTransfer: Kardiovaskuläre und metabolische Systembeanspruchung
///   2. movementSpecificity: Kinematische Verwandtschaft des Bewegungsablaufs
///   3. technicalSpecificity: Gleitphase, Balance, Kantenwechsel, Stockeinsatzwinkel
///   4. muscularSpecificity: Beanspruchung der wettkampfspezifischen Muskelketten
/// - Ercolina: Hoher DP- und Oberkörper-Transfer, aber kein vollständiger Skating-Ersatz
///   (kein Beinabstoß, keine Gleitphase, kein Geländeübergang).
library;

import '../../domain/xc_modality.dart';
import 'need_types.dart';

/// Ordinales Transfer-Niveau ohne scheinwissenschaftliche Scheingenauigkeit.
enum TransferLevel {
  high,
  moderate,
  low,
  minimal,
  unknown;

  String get label {
    switch (this) {
      case TransferLevel.high:
        return 'hoch';
      case TransferLevel.moderate:
        return 'moderat';
      case TransferLevel.low:
        return 'gering';
      case TransferLevel.minimal:
        return 'minimal';
      case TransferLevel.unknown:
        return 'unbekannt';
    }
  }

  bool get isSubstantial =>
      this == TransferLevel.high || this == TransferLevel.moderate;
}

class TrainingTransfer {
  const TrainingTransfer({
    required this.physiologicalTransfer,
    required this.movementSpecificity,
    required this.technicalSpecificity,
    required this.muscularSpecificity,
    this.loadToleranceTransfer = TransferLevel.moderate,
    this.notes = const [],
  });

  /// Kardiovaskulärer und metabolischer Übertrag (ordinal).
  final TransferLevel physiologicalTransfer;

  /// Kinematische Verwandtschaft des Bewegungsablaufs.
  final TransferLevel movementSpecificity;

  /// Spezifische Anforderung an Balance, Gleiten, Kanten und Timing.
  final TransferLevel technicalSpecificity;

  /// Beanspruchung der zielsportartspezifischen Muskelketten.
  final TransferLevel muscularSpecificity;

  /// Orthopädischer / mechanischer Belastungstoleranz-Übertrag.
  /// Kardiovaskuläre Fitness überträgt sich schnell, muskuloskelettale/orthopädische
  /// Toleranz (z. B. Sehnen, Schienbeine, Gelenke bei Laufstößen) ist strikt modalitätsspezifisch.
  final TransferLevel loadToleranceTransfer;

  final List<String> notes;

  Map<String, dynamic> toJson() => {
    'physiologicalTransfer': physiologicalTransfer.name,
    'movementSpecificity': movementSpecificity.name,
    'technicalSpecificity': technicalSpecificity.name,
    'muscularSpecificity': muscularSpecificity.name,
    'loadToleranceTransfer': loadToleranceTransfer.name,
    'notes': notes,
  };
}

/// # TRANSFER_MODEL_CLASSIC_GAP
///
/// Der Klassik-Zweig dieses Evaluators ist schwächer ausgebaut als der
/// Skating-Zweig, und das fiel nie auf, weil der Evaluator bis zum
/// 05.10.2026 **keinen einzigen Aufrufer** hatte.
///
/// Gemessen für ein `skiClassic`-Ziel und den Bedarf `aerobicBase`:
///
/// | Modalität            | physiologisch | muskulär |
/// |----------------------|---------------|----------|
/// | running              | **high**      | moderate |
/// | skiSkating           | moderate      | low      |
/// | rollerSkiSkating     | moderate      | low      |
/// | ercolinaDoublePoling | moderate      | low      |
///
/// Allein auf diese Zahlen gestellt gewann ein Lauf gegen Skiroller — bei
/// einem Langlaufziel. Für `skiSkating` als Ziel sind die Werte dagegen
/// sauber (rollerSkiSkating: high/high).
///
/// **Vorläufiger Schutz**, nicht die Lösung: Der Auswahlpfad legt eine
/// strukturelle Untergrenze aus [XcModality.sportGroup] darunter — die
/// Zielmodalität ist per Definition maximal spezifisch, eine Modalität
/// derselben Sportgruppe ist dem Ziel näher als eine fremde. Siehe
/// `_sportGroupFloor` in `daily_decision_engine.dart`.
///
/// **Was offen ist:** Die Klassik-Werte gehören mit Fachinput und Literatur
/// gesetzt, nicht nebenbei geraten. Bis dahin bleibt die Untergrenze aktiv
/// und dieser Hinweis stehen.
class TrainingTransferEvaluator {
  const TrainingTransferEvaluator();

  /// Berechnet den Transfer einer ausgeführten oder geplanten Trainingsmodalität
  /// bezogen auf die Zielmodalität und den spezifischen Trainingsbedarf.
  TrainingTransfer evaluateTransfer({
    required XcModality trainingModality,
    required XcModality targetModality,
    required TrainingNeedType needType,
  }) {
    // 1. Identische Sportart: Maximaler physiologischer und spezifischer Transfer
    if (trainingModality == targetModality) {
      return const TrainingTransfer(
        physiologicalTransfer: TransferLevel.high,
        movementSpecificity: TransferLevel.high,
        technicalSpecificity: TransferLevel.high,
        muscularSpecificity: TransferLevel.high,
        loadToleranceTransfer: TransferLevel.high,
        notes: [
          'Direkte Zielmodalität: Vollständiger physiologischer und biomechanischer Übertrag',
        ],
      );
    }

    // 2. Ercolina Doppelstock auf Skilanglauf Skating
    if (trainingModality == XcModality.ercolinaDoublePoling &&
        targetModality == XcModality.skiSkating) {
      switch (needType) {
        case TrainingNeedType.doublePolingPower:
        case TrainingNeedType.doublePolingEndurance:
          return const TrainingTransfer(
            physiologicalTransfer: TransferLevel.high,
            movementSpecificity: TransferLevel.high,
            technicalSpecificity: TransferLevel.moderate,
            muscularSpecificity: TransferLevel.high,
            loadToleranceTransfer: TransferLevel.high,
            notes: [
              'Ercolina bildet Oberkörper- und Rumpfvortrieb des Doppelstocks exzellent ab',
            ],
          );
        case TrainingNeedType.aerobicBase:
        case TrainingNeedType.threshold:
          return const TrainingTransfer(
            physiologicalTransfer: TransferLevel.high,
            movementSpecificity: TransferLevel.moderate,
            technicalSpecificity: TransferLevel.low,
            muscularSpecificity: TransferLevel.moderate,
            loadToleranceTransfer: TransferLevel.moderate,
            notes: [
              'Hohe Oberkörper-Herz-Kreislauf-Belastung, beansprucht aber nur Teilmuskulatur',
            ],
          );
        case TrainingNeedType.skatingSpecificity:
        case TrainingNeedType.technique:
          return const TrainingTransfer(
            physiologicalTransfer: TransferLevel.moderate,
            movementSpecificity: TransferLevel.low,
            technicalSpecificity: TransferLevel.minimal,
            muscularSpecificity: TransferLevel.low,
            loadToleranceTransfer: TransferLevel.low,
            notes: [
              'Ercolina trainiert keinen Beinabstoß, keine Gleitbalance und keine Kurventechnik',
            ],
          );
        default:
          return const TrainingTransfer(
            physiologicalTransfer: TransferLevel.moderate,
            movementSpecificity: TransferLevel.low,
            technicalSpecificity: TransferLevel.minimal,
            muscularSpecificity: TransferLevel.moderate,
            loadToleranceTransfer: TransferLevel.moderate,
            notes: ['Partieller Doppelstock-Transfer'],
          );
      }
    }

    // 3. Rollski Skating auf Schnee Skating
    if (trainingModality == XcModality.rollerSkiSkating &&
        targetModality == XcModality.skiSkating) {
      return const TrainingTransfer(
        physiologicalTransfer: TransferLevel.high,
        movementSpecificity: TransferLevel.high,
        technicalSpecificity: TransferLevel.high,
        muscularSpecificity: TransferLevel.high,
        loadToleranceTransfer: TransferLevel.high,
        notes: [
          'Rollski Skating bietet sehr hohe Bewegungsverwandtschaft zum Schneelauf',
        ],
      );
    }

    // 4. Radfahren auf Skilanglauf Skating
    if (trainingModality == XcModality.cycling) {
      switch (needType) {
        case TrainingNeedType.aerobicBase:
        case TrainingNeedType.threshold:
        case TrainingNeedType.vo2max:
          return const TrainingTransfer(
            physiologicalTransfer: TransferLevel.high,
            movementSpecificity: TransferLevel.minimal,
            technicalSpecificity: TransferLevel.minimal,
            muscularSpecificity: TransferLevel.low,
            loadToleranceTransfer: TransferLevel.low,
            notes: [
              'Exzellenter aerober/kardiovaskulärer Transfer, aber geringe skispezifische Muskelkoordination',
            ],
          );
        case TrainingNeedType.longEndurance:
          return const TrainingTransfer(
            physiologicalTransfer: TransferLevel.high,
            movementSpecificity: TransferLevel.minimal,
            technicalSpecificity: TransferLevel.minimal,
            muscularSpecificity: TransferLevel.low,
            loadToleranceTransfer: TransferLevel.low,
            notes: [
              'Umfangstransfer für zentrales Herz-Kreislauf-System hoch, aber keine Skilanglauf-Ganzkörperbelastung',
            ],
          );
        case TrainingNeedType.skatingSpecificity:
        case TrainingNeedType.doublePolingEndurance:
        case TrainingNeedType.technique:
          return const TrainingTransfer(
            physiologicalTransfer: TransferLevel.low,
            movementSpecificity: TransferLevel.minimal,
            technicalSpecificity: TransferLevel.minimal,
            muscularSpecificity: TransferLevel.minimal,
            loadToleranceTransfer: TransferLevel.minimal,
            notes: [
              'Kein nennenswerter spezifischer Transfer für Oberkörper- und Skilanglauftechnik',
            ],
          );
        default:
          return const TrainingTransfer(
            physiologicalTransfer: TransferLevel.moderate,
            movementSpecificity: TransferLevel.minimal,
            technicalSpecificity: TransferLevel.minimal,
            muscularSpecificity: TransferLevel.low,
            loadToleranceTransfer: TransferLevel.low,
            notes: ['Allgemeines Ausdauertraining'],
          );
      }
    }

    // 5. Laufen / Berglauf auf Skilanglauf Skating
    if (trainingModality == XcModality.running) {
      switch (needType) {
        case TrainingNeedType.aerobicBase:
        case TrainingNeedType.vo2max:
          return const TrainingTransfer(
            physiologicalTransfer: TransferLevel.high,
            movementSpecificity: TransferLevel.low,
            technicalSpecificity: TransferLevel.minimal,
            muscularSpecificity: TransferLevel.moderate,
            loadToleranceTransfer: TransferLevel.low,
            notes: [
              'Hohe VO2max- und Herz-Kreislauf-Stimulation durch große beanspruchte Muskelmasse',
            ],
          );
        case TrainingNeedType.skatingSpecificity:
        case TrainingNeedType.doublePolingEndurance:
          return const TrainingTransfer(
            physiologicalTransfer: TransferLevel.moderate,
            movementSpecificity: TransferLevel.minimal,
            technicalSpecificity: TransferLevel.minimal,
            muscularSpecificity: TransferLevel.low,
            loadToleranceTransfer: TransferLevel.minimal,
            notes: [
              'Fehlende Oberkörper-Vortriebsbeanspruchung im Vergleich zum Skilanglauf',
            ],
          );
        default:
          return const TrainingTransfer(
            physiologicalTransfer: TransferLevel.high,
            movementSpecificity: TransferLevel.low,
            technicalSpecificity: TransferLevel.minimal,
            muscularSpecificity: TransferLevel.moderate,
            loadToleranceTransfer: TransferLevel.low,
            notes: [
              'Allgemeines aerobes Ausdauertraining; hohe mechanische Aufprallbelastung',
            ],
          );
      }
    }

    // Standard-Fallback für sonstige Modalities
    return const TrainingTransfer(
      physiologicalTransfer: TransferLevel.moderate,
      movementSpecificity: TransferLevel.low,
      technicalSpecificity: TransferLevel.minimal,
      muscularSpecificity: TransferLevel.low,
      loadToleranceTransfer: TransferLevel.low,
      notes: ['Allgemeiner Transfer unspezifischer Belastung'],
    );
  }
}
