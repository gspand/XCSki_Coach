/// Trainingsfamilien für Skilanglauf und Cross-Training (Workout Family System).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Statt kontinuierlicher freier Mathematik werden konkrete, sportwissenschaftlich
///   geprüfte Einheiten-Varianten (AllowedWorkoutVariants) hinterlegt.
/// - Jede Familie deklariert diskrete Varianten mit definierten Wiederholungszahlen,
///   Belastungs- und Pausenzeiten.
/// - Ercolina-Einheiten sind KEINE parallele Schattenbibliothek, sondern referenzieren
///   als Source of Truth direkt die kanonischen IDs aus workoutCatalogue und workoutLibrary
///   (z. B. reg, eb6, eb10, vo2-3, vo2-30-30, speed, base-45, tech-doublepole).
library;

import '../../domain/xc_modality.dart';
import '../../workout_engine/ercolina_canonical_library.dart';
import '../load/stimulus_models.dart';
import '../training_need/need_types.dart';
import '../xc_athlete_state/diagnostics_state.dart';
import 'intensity_prescription.dart';
import 'workout_prescription.dart';

/// Diskrete, sportwissenschaftlich definierte Ausführungsvariante innerhalb einer Familie.
class WorkoutVariant {
  const WorkoutVariant({
    required this.id,
    required this.name,
    required this.totalDurationMinutes,
    required this.warmupMinutes,
    required this.workMinutes,
    required this.cooldownMinutes,
    required this.structureDescription,
    this.templateId,
    this.blueprintId,
    this.progressionVariant,
    this.regressionVariant,
    this.terrainGuidance,
  });

  final String id;
  final String name;
  final int totalDurationMinutes;
  final int warmupMinutes;
  final int workMinutes;
  final int cooldownMinutes;
  final String structureDescription;
  final String? templateId;
  final String? blueprintId;
  final String? progressionVariant;
  final String? regressionVariant;
  final String? terrainGuidance;
}

/// Definition einer parametrisierten Trainingsfamilie.
class WorkoutFamily {
  const WorkoutFamily({
    required this.id,
    required this.name,
    required this.type,
    required this.modality,
    required this.primaryStimulus,
    required this.primaryNeed,
    required this.minDurationMinutes,
    required this.maxDurationMinutes,
    required this.recoveryCost,
    this.affectedSystems = const {TrainedSystem.systemic},
    this.allowedVariants = const [],
    this.secondaryStimuli = const [],
    this.isUpperBodyDominant = false,
    this.isLowerBodyDominant = false,
    this.isAssessmentWorkout = false,
    this.description = '',
  });

  final String id;
  final String name;
  final WorkoutFamilyType type;
  final XcModality modality;
  final StimulusType primaryStimulus;
  final TrainingNeedType primaryNeed;
  final int minDurationMinutes;
  final int maxDurationMinutes;
  final RecoveryCost recoveryCost;
  final Set<TrainedSystem> affectedSystems;
  final List<WorkoutVariant> allowedVariants;
  final List<StimulusType> secondaryStimuli;
  final bool isUpperBodyDominant;
  final bool isLowerBodyDominant;
  final bool isAssessmentWorkout;
  final String description;

  /// Die Varianten einer Ercolina-Familie — aus der kanonischen Bibliothek.
  ///
  /// E0 bis E14 sind die Quelle der Wahrheit: Die Firmware liest sie von der
  /// SD-Karte, und der Coach darf nur verschreiben, was das Gerät kennt. Hier
  /// steht deshalb keine zweite Liste von Dauern, sondern eine Auswahl nach
  /// Reiztyp aus [ercolinaCanonicalLibrary].
  ///
  /// Die Familie beschreibt den **Zweck**, die Bibliothek die **Einheit**.
  /// Ihr Aufbau — Intervalle, Zonen, Hinweise — steht in der CSV und wird
  /// hier nicht nachgebaut; die Beschreibung verweist darauf.
  static List<WorkoutVariant> ercolinaVariantsOfTypes(Set<String> types) {
    final matching =
        ercolinaCanonicalLibrary
            .where((w) => types.contains(w.type))
            // Winter-spezifische Einheiten nur, wenn ausdruecklich gewuenscht.
            .where((w) => w.season == 'common')
            .toList()
          ..sort((a, b) => a.minutes.compareTo(b.minutes));
    return [
      for (final w in matching)
        WorkoutVariant(
          id: w.id,
          name: w.title,
          totalDurationMinutes: w.minutes,
          // Die Aufteilung steht in der CSV. Hier wird sie nicht erfunden:
          // Die Gesamtdauer ist, was der Coach fuer die Dosis braucht.
          warmupMinutes: 0,
          workMinutes: w.minutes,
          cooldownMinutes: 0,
          structureDescription:
              '${w.title} — kanonische Gerätebibliothek (${w.file}).',
          // Die ausfuehrbare Einheit ist die Einheit selbst.
          //
          // Hier stand eine Zuordnung von Reiztyp zu einer handgeschriebenen
          // Einheit: TECH fuehrte auf `technique-doublepoling`. Der Coach
          // verschrieb dann «E1, 25 min» und startete dreiunddreissig
          // Minuten mit anderer Struktur. `blueprintById` loest kanonische
          // IDs jetzt direkt auf, also genuegt die ID.
          templateId: w.id,
          blueprintId: w.id,
        ),
    ];
  }

  /// Erzeugt eine Prescription innerhalb des Zeitfensters und der plausiblen
  /// Dosis.
  ///
  /// [availableMinutes] ist eine **Obergrenze**, kein Ziel: Wer vier Stunden
  /// Zeit hat, soll nicht vier Stunden verschrieben bekommen. Die zweite
  /// Obergrenze ist [doseCeilingMinutes] — was diese Modalität fuer diesen
  /// Athleten derzeit hergibt. Gewaehlt wird die laengste Variante, die unter
  /// **beiden** bleibt; der Rest der Zeit bleibt frei.
  WorkoutPrescription buildPrescription({
    required int availableMinutes,
    required DiagnosticsState diagnostics,
    IntensityResolver intensityResolver = const IntensityResolver(),
    int? doseCeilingMinutes,
  }) {
    final workIntensity = intensityResolver.resolveWorkIntensity(
      modality: modality,
      stimulus: primaryStimulus,
      diagnostics: diagnostics,
    );
    final recoveryIntensity = intensityResolver.resolveRecoveryIntensity(
      modality: modality,
    );

    // 1. Suche nach der am besten passenden diskreten Variante
    //
    // Die Grenze ist das Kleinere von Zeitfenster und plausibler Dosis. Ohne
    // die zweite Grenze wuerde hier die laengste Einheit gewaehlt, die ins
    // Budget passt — und damit die Verfuegbarkeit zur Verschreibung.
    final limit = doseCeilingMinutes == null
        ? availableMinutes
        : (doseCeilingMinutes < availableMinutes
              ? doseCeilingMinutes
              : availableMinutes);
    WorkoutVariant? selectedVariant;
    if (allowedVariants.isNotEmpty) {
      final fittingVariants = allowedVariants
          .where((v) => v.totalDurationMinutes <= limit)
          .toList();
      if (fittingVariants.isNotEmpty) {
        fittingVariants.sort(
          (a, b) => b.totalDurationMinutes.compareTo(a.totalDurationMinutes),
        );
        selectedVariant = fittingVariants.first;
      } else {
        // Falls keine hineinpasst, nimm die kürzeste erlaubte Variante (wird im Feasibility-Filter gefiltert)
        final sorted = List<WorkoutVariant>.from(allowedVariants)
          ..sort(
            (a, b) => a.totalDurationMinutes.compareTo(b.totalDurationMinutes),
          );
        selectedVariant = sorted.first;
      }
    }

    if (selectedVariant != null) {
      return WorkoutPrescription(
        id: '${id}_${selectedVariant.id}',
        title: selectedVariant.name,
        modality: modality,
        family: type,
        totalDurationMinutes: selectedVariant.totalDurationMinutes,
        warmupMinutes: selectedVariant.warmupMinutes,
        workMinutes: selectedVariant.workMinutes,
        cooldownMinutes: selectedVariant.cooldownMinutes,
        structureDescription: selectedVariant.structureDescription,
        workIntensity: workIntensity,
        recoveryIntensity: recoveryIntensity,
        intendedStimuli: [primaryStimulus, ...secondaryStimuli],
        primaryNeedAddressed: primaryNeed,
        recoveryCost: recoveryCost,
        recoveryDemand: RecoveryDemand(
          cost: recoveryCost,
          affectedSystems: affectedSystems,
          qualitativeDescription: 'Erholungsbedarf: ${recoveryCost.label}',
        ),
        terrainGuidance:
            selectedVariant.terrainGuidance ?? workIntensity.terrainGuidance,
        templateId: selectedVariant.templateId,
        blueprintId: selectedVariant.blueprintId,
        progressionVariant: selectedVariant.progressionVariant,
        regressionVariant: selectedVariant.regressionVariant,
        isAssessmentWorkout: isAssessmentWorkout,
      );
    }

    // Fallback falls keine Variantenliste deklariert ist
    final effectiveDuration = availableMinutes.clamp(
      minDurationMinutes,
      maxDurationMinutes,
    );
    final warmup = 10;
    final cooldown = 10;
    final work = effectiveDuration - warmup - cooldown;

    return WorkoutPrescription(
      id: '${id}_${effectiveDuration}m',
      title: '$name ($effectiveDuration min)',
      modality: modality,
      family: type,
      totalDurationMinutes: effectiveDuration,
      warmupMinutes: warmup,
      workMinutes: work,
      cooldownMinutes: cooldown,
      structureDescription:
          '$warmup min Einlaufen, $work min Hauptteil, $cooldown min Auslaufen.',
      workIntensity: workIntensity,
      recoveryIntensity: recoveryIntensity,
      intendedStimuli: [primaryStimulus, ...secondaryStimuli],
      primaryNeedAddressed: primaryNeed,
      recoveryCost: recoveryCost,
      recoveryDemand: RecoveryDemand(
        cost: recoveryCost,
        affectedSystems: affectedSystems,
        qualitativeDescription: 'Erholungsbedarf: ${recoveryCost.label}',
      ),
      terrainGuidance: workIntensity.terrainGuidance,
      isAssessmentWorkout: isAssessmentWorkout,
    );
  }

  /// Vordefinierte Standardfamilien für den Langlauf-Coach mit kanonischen Varianten.
  /// Die Familien des Produkts.
  ///
  /// Nicht mehr `const`: Die Ercolina-Familien holen ihre Varianten aus
  /// [ercolinaCanonicalLibrary], damit der Coach nur verschreibt, was das
  /// Gerät kennt. Eine konstante Liste könnte das nicht — und eine
  /// handgeschriebene Kopie der Dauern wäre eine zweite Wahrheit.
  static final List<WorkoutFamily> standardFamilies = [
    // -------------------------------------------------------------------------
    // SKATING AUF SCHNEE
    // -------------------------------------------------------------------------
    WorkoutFamily(
      id: 'fam_skate_thresh',
      name: 'Skating Schwellenintervalle (EB)',
      type: WorkoutFamilyType.thresholdIntervals,
      modality: XcModality.skiSkating,
      primaryStimulus: StimulusType.threshold,
      primaryNeed: TrainingNeedType.threshold,
      minDurationMinutes: 50,
      maxDurationMinutes: 90,
      recoveryCost: RecoveryCost.high,
      affectedSystems: {TrainedSystem.systemic, TrainedSystem.lowerBody},
      secondaryStimuli: [StimulusType.technique, StimulusType.aerobicBase],
      isLowerBodyDominant: true,
      description:
          'Strukturierte Schwellenintervalle zur Verschiebung der aeroben Schwelle auf Schnee.',
      allowedVariants: [
        WorkoutVariant(
          id: '3x8',
          name: 'Skating Schwellenintervalle (3 × 8 min)',
          totalDurationMinutes: 60,
          warmupMinutes: 15,
          workMinutes: 24,
          cooldownMinutes: 15,
          structureDescription:
              '15 min Einlaufen Z1/Z2, 3 × 8 min EB (Z3) mit je 3 min Trabpause, 15 min Auslaufen Z1.',
          progressionVariant: '4 × 8 min',
          regressionVariant: '3 × 6 min',
          terrainGuidance:
              'Gleichmäßige moderate Steigung (2–4%) oder flacher Rundkurs; Druck über Kuppen konstant halten.',
        ),
        WorkoutVariant(
          id: '4x8',
          name: 'Skating Schwellenintervalle (4 × 8 min)',
          totalDurationMinutes: 75,
          warmupMinutes: 15,
          workMinutes: 32,
          cooldownMinutes: 19,
          structureDescription:
              '15 min Einlaufen Z1/Z2, 4 × 8 min EB (Z3) mit je 3 min Trabpause, 19 min Auslaufen Z1.',
          progressionVariant: '5 × 8 min',
          regressionVariant: '3 × 8 min',
          terrainGuidance:
              'Gleichmäßige moderate Steigung (2–4%) oder flacher Rundkurs.',
        ),
        WorkoutVariant(
          id: '3x10',
          name: 'Skating Schwellenintervalle (3 × 10 min)',
          totalDurationMinutes: 80,
          warmupMinutes: 15,
          workMinutes: 30,
          cooldownMinutes: 29,
          structureDescription:
              '15 min Einlaufen Z1/Z2, 3 × 10 min EB (Z3) mit je 3 min Trabpause, 29 min Auslaufen Z1.',
          progressionVariant: '4 × 10 min',
          regressionVariant: '4 × 8 min',
          terrainGuidance:
              'Längere Anstiegsabschnitte mit kontrollierter Rhythmusführung.',
        ),
      ],
    ),
    WorkoutFamily(
      id: 'fam_skate_vo2',
      name: 'Skating VO2max HIT',
      type: WorkoutFamilyType.vo2maxIntervals,
      modality: XcModality.skiSkating,
      primaryStimulus: StimulusType.vo2max,
      primaryNeed: TrainingNeedType.vo2max,
      minDurationMinutes: 45,
      maxDurationMinutes: 75,
      recoveryCost: RecoveryCost.high,
      affectedSystems: {TrainedSystem.systemic, TrainedSystem.lowerBody},
      secondaryStimuli: [StimulusType.technique],
      isLowerBodyDominant: true,
      description:
          'Hochintensive Intervalle zur Vergrößerung der maximalen Sauerstoffaufnahme.',
      allowedVariants: [
        WorkoutVariant(
          id: '4x4',
          name: 'Skating VO2max HIT (4 × 4 min HIT)',
          totalDurationMinutes: 50,
          warmupMinutes: 15,
          workMinutes: 16,
          cooldownMinutes: 10,
          structureDescription:
              '15 min Einlaufen inklusive 3 dynamischer Steigerungen, 4 × 4 min Z4 (VO2max) mit je 3 min aktiver Pause, 10 min lockeres Auslaufen.',
          progressionVariant: '5 × 4 min',
          regressionVariant: '4 × 3 min',
          terrainGuidance:
              'Gleichmäßiger Anstieg (4–8%) für maximale Sauerstoffaufnahme bei dynamischer Skiführung.',
        ),
        WorkoutVariant(
          id: '5x4',
          name: 'Skating VO2max HIT (5 × 4 min HIT)',
          totalDurationMinutes: 65,
          warmupMinutes: 15,
          workMinutes: 20,
          cooldownMinutes: 18,
          structureDescription:
              '15 min Einlaufen inklusive 3 dynamischer Steigerungen, 5 × 4 min Z4 (VO2max) mit je 3 min aktiver Pause, 18 min lockeres Auslaufen.',
          progressionVariant: '6 × 4 min',
          regressionVariant: '4 × 4 min',
          terrainGuidance: 'Gleichmäßiger Anstieg (4–8%) mit freier Spur.',
        ),
      ],
    ),
    WorkoutFamily(
      id: 'fam_skate_long',
      name: 'Skating Langzeitausdauer',
      type: WorkoutFamilyType.longEndurance,
      modality: XcModality.skiSkating,
      primaryStimulus: StimulusType.fatigueResistance,
      primaryNeed: TrainingNeedType.longEndurance,
      minDurationMinutes: 90,
      maxDurationMinutes: 240,
      recoveryCost: RecoveryCost.extreme,
      affectedSystems: {TrainedSystem.systemic, TrainedSystem.lowerBody},
      secondaryStimuli: [StimulusType.aerobicBase, StimulusType.technique],
      isLowerBodyDominant: true,
      description:
          'Lange skispezifische Grundlageneinheit zur Ausbildung von Ermüdungsresistenz und Durability.',
      allowedVariants: [
        WorkoutVariant(
          id: '120m',
          name: 'Skating Langzeitausdauer (2.0 h)',
          totalDurationMinutes: 120,
          warmupMinutes: 10,
          workMinutes: 100,
          cooldownMinutes: 10,
          structureDescription:
              '10 min ruhiges Einlaufen, 100 min gleichmäßiges Gleiten in Zone 2 mit Fokus auf konstante Ökonomie und regelmäßige Verpflegung, 10 min lockeres Ausgleiten.',
          progressionVariant: '150 min Z2',
          regressionVariant: '90 min Z2',
          terrainGuidance:
              'Kupiertes Terrain; an allen Anstiegen bewusst kontrollieren, sodass der lockere Charakter der Einheit erhalten bleibt.',
        ),
        WorkoutVariant(
          id: '150m',
          name: 'Skating Langzeitausdauer (2.5 h)',
          totalDurationMinutes: 150,
          warmupMinutes: 10,
          workMinutes: 130,
          cooldownMinutes: 10,
          structureDescription:
              '10 min ruhiges Einlaufen, 130 min gleichmäßiges Gleiten in Zone 2 mit Fokus auf Durability und Verpflegungsstrategie, 10 min lockeres Ausgleiten.',
          progressionVariant: '180 min Z2',
          regressionVariant: '120 min Z2',
          terrainGuidance: 'Kupiertes Terrain mit striktem Bergauf-Pacing.',
        ),
        WorkoutVariant(
          id: '180m',
          name: 'Skating Langzeitausdauer (3.0 h)',
          totalDurationMinutes: 180,
          warmupMinutes: 10,
          workMinutes: 160,
          cooldownMinutes: 10,
          structureDescription:
              '10 min ruhiges Einlaufen, 160 min gleichmäßiges Gleiten in Zone 2 zur maximalen Ermüdungsresistenz, 10 min lockeres Ausgleiten.',
          regressionVariant: '150 min Z2',
          terrainGuidance: 'Kupiertes Terrain; Verpflegung alle 20–30 min.',
        ),
      ],
    ),
    WorkoutFamily(
      id: 'fam_skate_base',
      name: 'Skating Grundlagenausdauer',
      type: WorkoutFamilyType.easyBase,
      modality: XcModality.skiSkating,
      primaryStimulus: StimulusType.aerobicBase,
      primaryNeed: TrainingNeedType.aerobicBase,
      minDurationMinutes: 40,
      maxDurationMinutes: 90,
      recoveryCost: RecoveryCost.moderate,
      affectedSystems: {TrainedSystem.systemic, TrainedSystem.lowerBody},
      secondaryStimuli: [StimulusType.technique],
      description:
          'Ruhige Grundlageneinheit mit Gleitgefühl und technischer Ökonomie.',
      allowedVariants: [
        WorkoutVariant(
          id: '45m',
          name: 'Skating Grundlagenausdauer (45 min)',
          totalDurationMinutes: 45,
          warmupMinutes: 10,
          workMinutes: 25,
          cooldownMinutes: 10,
          structureDescription:
              '10 min Einlaufen, 25 min aerobes Grundlagentraining Z2 mit sauberer Bewegungstechnik, 10 min Auslaufen.',
          terrainGuidance:
              'Flaches bis leicht kupiertes Gelände; Anstiege mit hoher Frequenz locker nehmen.',
        ),
        WorkoutVariant(
          id: '60m',
          name: 'Skating Grundlagenausdauer (60 min)',
          totalDurationMinutes: 60,
          warmupMinutes: 10,
          workMinutes: 40,
          cooldownMinutes: 10,
          structureDescription:
              '10 min Einlaufen, 40 min aerobes Grundlagentraining Z2 mit sauberer Bewegungstechnik, 10 min Auslaufen.',
          terrainGuidance:
              'Flaches bis leicht kupiertes Gelände; Anstiege drosseln.',
        ),
      ],
    ),
    WorkoutFamily(
      id: 'fam_skate_tech',
      name: 'Skating Technik & Koordination',
      type: WorkoutFamilyType.techniqueFocus,
      modality: XcModality.skiSkating,
      primaryStimulus: StimulusType.technique,
      primaryNeed: TrainingNeedType.technique,
      minDurationMinutes: 35,
      maxDurationMinutes: 60,
      recoveryCost: RecoveryCost.low,
      affectedSystems: {TrainedSystem.neuromuscular},
      description:
          'Schwerpunkt auf Einbeingleiten, Führungsarmarbeit und Geländeübergänge.',
      allowedVariants: [
        WorkoutVariant(
          id: '45m',
          name: 'Skating Technik & Koordination (45 min)',
          totalDurationMinutes: 45,
          warmupMinutes: 10,
          workMinutes: 25,
          cooldownMinutes: 10,
          structureDescription:
              '10 min Einlaufen, 25 min Technikübungen (Gleiten ohne Stöcke, 1:1 am leichten Anstieg), 10 min Auslaufen.',
          templateId: 'tech-ski',
          terrainGuidance:
              'Flaches, bestens präpariertes Terrain für saubere Kantenkontrolle.',
        ),
      ],
    ),

    // -------------------------------------------------------------------------
    // ERCOLINA DOPPELSTOCK (SOURCE OF TRUTH: workoutCatalogue & workoutLibrary)
    // -------------------------------------------------------------------------
    WorkoutFamily(
      id: 'fam_ercolina_dp_power',
      name: 'Ercolina DP Kraftausdauer & Power',
      type: WorkoutFamilyType.doublePolingSpecific,
      modality: XcModality.ercolinaDoublePoling,
      primaryStimulus: StimulusType.doublePolingPower,
      primaryNeed: TrainingNeedType.doublePolingPower,
      minDurationMinutes: 25,
      maxDurationMinutes: 60,
      recoveryCost: RecoveryCost.high,
      affectedSystems: {TrainedSystem.upperBody, TrainedSystem.neuromuscular},
      isUpperBodyDominant: true,
      description:
          'Maximale DP-Kraftübertragung und Ermüdungstoleranz für den Oberkörper.',
      allowedVariants: WorkoutFamily.ercolinaVariantsOfTypes(const {'EB'}),
    ),
    WorkoutFamily(
      id: 'fam_ercolina_dp_endurance',
      name: 'Ercolina DP Grundlagenausdauer',
      type: WorkoutFamilyType.doublePolingSpecific,
      modality: XcModality.ercolinaDoublePoling,
      primaryStimulus: StimulusType.doublePolingEndurance,
      primaryNeed: TrainingNeedType.doublePolingEndurance,
      minDurationMinutes: 30,
      maxDurationMinutes: 75,
      recoveryCost: RecoveryCost.moderate,
      affectedSystems: {TrainedSystem.upperBody, TrainedSystem.systemic},
      isUpperBodyDominant: true,
      description:
          'Kontinuierliche Doppelstock-Ökonomie und Rumpfstabilität am Zuggerät.',
      // PROGRESSION (E14) gehoert hier NICHT hinein: die Einheit laeuft von
      // I1 bis I5 hoch. Als Grundlagenvariante waere sie eine versteckte
      // Intensitaetseinheit an einem ruhigen Tag. Sie steht in
      // fam_ercolina_threshold.
      allowedVariants: WorkoutFamily.ercolinaVariantsOfTypes(const {
        'BASE',
        'LONG',
      }),
    ),
    // Technik am Zuggeraet: Der Zweck ist derselbe wie beim Skating-Pendant
    // (fam_skate_tech), die Einheiten kommen aus der kanonischen Bibliothek.
    //
    // Diese Familie fehlte, obwohl E0 und E1 seit Langem auf der SD-Karte
    // liegen: zwanzig und fuenfundzwanzig Minuten Technik und Oekonomie. Ohne
    // sie war die kuerzeste erreichbare Ercolina-Einheit fuenfunddreissig
    // Minuten — und ein Athlet mit einer plausiblen Dosis von dreissig
    // Minuten bekam gar keine Ercolina-Einheit, obwohl das Geraet zwei
    // passende kennt.
    WorkoutFamily(
      id: 'fam_ercolina_tech',
      name: 'Doppelstock Technik & Oekonomie',
      type: WorkoutFamilyType.techniqueFocus,
      modality: XcModality.ercolinaDoublePoling,
      primaryStimulus: StimulusType.technique,
      primaryNeed: TrainingNeedType.technique,
      minDurationMinutes: 20,
      maxDurationMinutes: 25,
      recoveryCost: RecoveryCost.low,
      affectedSystems: {TrainedSystem.neuromuscular, TrainedSystem.upperBody},
      description:
          'Schwerpunkt auf Rumpfstabilitaet, tiefer Schulter und oekonomischem '
          'Zugweg am Doppelstockergometer.',
      allowedVariants: WorkoutFamily.ercolinaVariantsOfTypes({'TECH'}),
    ),
    // Schwelle und Z3 am Zuggeraet. Die Einheiten lagen vollstaendig auf der
    // SD-Karte und waren aus der App nicht erreichbar, weil keine Familie
    // ihren Reiztyp genannt hat: E8 (I3, 80 min), E9 (I4, 95 min),
    // E13 (Over/Under I4-I5, 73 min), E14 (progressiv bis I5, 60 min).
    WorkoutFamily(
      id: 'fam_ercolina_threshold',
      name: 'Doppelstock Schwelle & Z3',
      type: WorkoutFamilyType.thresholdIntervals,
      modality: XcModality.ercolinaDoublePoling,
      primaryStimulus: StimulusType.threshold,
      primaryNeed: TrainingNeedType.threshold,
      minDurationMinutes: 60,
      maxDurationMinutes: 95,
      recoveryCost: RecoveryCost.high,
      affectedSystems: {TrainedSystem.upperBody, TrainedSystem.systemic},
      isUpperBodyDominant: true,
      description:
          'Laktat-Gleichgewicht im Doppelstock: zuegiger Dauerbereich, '
          'Schwellenintervalle und Over/Under am Zuggeraet.',
      allowedVariants: WorkoutFamily.ercolinaVariantsOfTypes(const {
        'TEMPO',
        'THRESHOLD',
        'OVERUNDER',
        'PROGRESSION',
      }),
    ),
    // Schnelligkeit am Zuggeraet: E3 (Speed, 20 min) und E12 (Sprint 12x10s,
    // 61 min). Auch diese waren vorhanden und unerreichbar.
    WorkoutFamily(
      id: 'fam_ercolina_speed',
      name: 'Doppelstock Schnelligkeit',
      type: WorkoutFamilyType.speedNeuromuscular,
      modality: XcModality.ercolinaDoublePoling,
      primaryStimulus: StimulusType.speedNeuromuscular,
      primaryNeed: TrainingNeedType.speedNeuromuscular,
      minDurationMinutes: 20,
      maxDurationMinutes: 61,
      recoveryCost: RecoveryCost.moderate,
      affectedSystems: {TrainedSystem.neuromuscular, TrainedSystem.upperBody},
      isUpperBodyDominant: true,
      description:
          'Maximale Zugfrequenz ueber kurze Antritte mit vollstaendiger '
          'Erholung; neuromuskulaere Ansteuerung ohne Ermuedungsaufbau.',
      allowedVariants: WorkoutFamily.ercolinaVariantsOfTypes(const {
        'SPEED',
        'SPRINT',
      }),
    ),
    WorkoutFamily(
      id: 'fam_ercolina_vo2',
      name: 'Ercolina VO2max Intervalle',
      type: WorkoutFamilyType.vo2maxIntervals,
      modality: XcModality.ercolinaDoublePoling,
      primaryStimulus: StimulusType.vo2max,
      primaryNeed: TrainingNeedType.vo2max,
      minDurationMinutes: 30,
      maxDurationMinutes: 50,
      recoveryCost: RecoveryCost.high,
      affectedSystems: {TrainedSystem.upperBody, TrainedSystem.systemic},
      isUpperBodyDominant: true,
      description:
          'Kurze, intensive DP-Intervalle am Ercolina-Zuggerät (z. B. 30/30 oder 4x3 min).',
      allowedVariants: WorkoutFamily.ercolinaVariantsOfTypes(const {'VO2'}),
    ),

    // -------------------------------------------------------------------------
    // CROSS-TRAINING & REGENERATION
    // -------------------------------------------------------------------------
    WorkoutFamily(
      id: 'fam_run_base',
      name: 'Lauf Grundlagenausdauer',
      type: WorkoutFamilyType.easyBase,
      modality: XcModality.running,
      primaryStimulus: StimulusType.aerobicBase,
      primaryNeed: TrainingNeedType.aerobicBase,
      minDurationMinutes: 30,
      maxDurationMinutes: 75,
      recoveryCost: RecoveryCost.moderate,
      affectedSystems: {TrainedSystem.lowerBody, TrainedSystem.systemic},
      description: 'Kardiovaskuläres Grundlagenausdauertraining zu Fuß.',
      allowedVariants: [
        WorkoutVariant(
          id: '45m',
          name: 'Lauf Grundlagenausdauer (45 min)',
          totalDurationMinutes: 45,
          warmupMinutes: 5,
          workMinutes: 35,
          cooldownMinutes: 5,
          structureDescription:
              '45 min ruhiger Dauerlauf im Z2-Bereich auf weichem Untergrund.',
          terrainGuidance:
              'Flacher bis leicht welliger Wald- oder Naturweg; Anstiege bewusst verlangsamen.',
        ),
      ],
    ),
    WorkoutFamily(
      id: 'fam_bike_base',
      name: 'Rad Grundlagenausdauer',
      type: WorkoutFamilyType.easyBase,
      modality: XcModality.cycling,
      primaryStimulus: StimulusType.aerobicBase,
      primaryNeed: TrainingNeedType.aerobicBase,
      minDurationMinutes: 45,
      maxDurationMinutes: 120,
      recoveryCost: RecoveryCost.low,
      affectedSystems: {TrainedSystem.lowerBody, TrainedSystem.systemic},
      description: 'Gelenkschonendes kardiovaskuläres Basistraining.',
      allowedVariants: [
        WorkoutVariant(
          id: '60m',
          name: 'Rad Grundlagenausdauer (60 min)',
          totalDurationMinutes: 60,
          warmupMinutes: 10,
          workMinutes: 45,
          cooldownMinutes: 5,
          structureDescription:
              '60 min lockeres Kurbeln im Z2-Bereich bei 85–95 U/min.',
          terrainGuidance:
              'Flache Strecke; gleichmäßiger Krafteinsatz ohne lange Tretpausen.',
        ),
      ],
    ),
    WorkoutFamily(
      id: 'fam_active_rec',
      name: 'Aktive Erholung',
      type: WorkoutFamilyType.activeRecovery,
      modality: XcModality.ercolinaDoublePoling,
      primaryStimulus: StimulusType.recovery,
      primaryNeed: TrainingNeedType.recovery,
      minDurationMinutes: 20,
      maxDurationMinutes: 40,
      recoveryCost: RecoveryCost.low,
      affectedSystems: {TrainedSystem.systemic},
      description:
          'Ganz lockere Durchblutungsförderung zur Unterstützung der Erholung.',
      allowedVariants: [
        WorkoutVariant(
          id: '30m',
          name: 'Aktive Erholung (30 min)',
          totalDurationMinutes: 30,
          warmupMinutes: 5,
          workMinutes: 20,
          cooldownMinutes: 5,
          structureDescription:
              '30 min sehr lockere Bewegung rein in Zone 1 (RPE <= 2.5), Fokus auf Entlastung und Durchblutung.',
          // Hier stand `templateId: 'reg'`. 'reg' ist eine ID des
          // Planungskatalogs und der ausfuehrbaren Bibliothek unbekannt:
          // `blueprintById('reg')` gab null, und der Start fiel still auf
          // freies Training zurueck. Fuer aktive Erholung ist freies
          // Training das Richtige — eine vorgeschriebene Struktur waere es
          // nicht. Deshalb steht hier jetzt ausdruecklich nichts, statt
          // eines Verweises, der ins Leere zeigt.
          // CONTENT_GAP_RECOVERY_BLUEPRINT: Eine ausfuehrbare Z1-Einheit
          // gibt es in workoutLibrary nicht.
          terrainGuidance: 'Flach und widerstandsarm.',
        ),
      ],
    ),
  ];
}
