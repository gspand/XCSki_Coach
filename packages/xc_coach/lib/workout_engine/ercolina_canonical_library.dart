// GENERIERT – nicht von Hand ändern.
//
// Quelle: ../workouts/index.csv (und die dort genannten CSV-Dateien), die
// Bibliothek, die die Ercolina-Firmware von der SD-Karte liest. Neu erzeugen
// mit:
//
//     dart run tool/generate_ercolina_library.dart
//
// Warum generiert und nicht gepflegt: E0–E14 sind die Quelle der Wahrheit für
// das Gerät. Eine zweite, handgeschriebene Liste in Dart wäre eine Kopie, die
// irgendwann abweicht — und der Coach würde Einheiten verschreiben, die das
// Gerät nicht kennt.
library;

/// Ein Schritt einer kanonischen Einheit, genau wie er in der CSV steht.
class ErcolinaCanonicalStep {
  const ErcolinaCanonicalStep({
    required this.seconds,
    required this.percentFtp,
    this.hint = '',
  });

  final int seconds;

  /// Zielanteil der Schwellenleistung in Prozent, wie das Gerät ihn liest.
  final int percentFtp;

  /// Der Hinweis aus der CSV: «brisk», «easy recovery», «technique focus».
  final String hint;
}

/// Eine Einheit der kanonischen Ercolina-Bibliothek.
class ErcolinaCanonicalWorkout {
  const ErcolinaCanonicalWorkout({
    required this.id,
    required this.title,
    required this.minutes,
    required this.type,
    required this.level,
    required this.season,
    required this.file,
    required this.notes,
    required this.steps,
  });

  /// Die Kennung, unter der das Gerät sie führt — das Feld `#name=` der CSV:
  /// «E0_TECH_EASY», «E2_EB_5x3». Eindeutig; das Kürzel «E2» ist es nicht.
  final String id;
  final String title;
  final int minutes;

  /// Der Reiztyp, wie die Bibliothek ihn benennt: TECH, BASE, LONG, VO2 …
  final String type;

  /// E (easy), M (moderate), H (hard).
  final String level;
  final String season;
  final String file;

  /// Die Kurzbeschreibung aus dem CSV-Kopf (`#notes=`).
  final String notes;

  /// Der Ablauf. Das ist, was der Athlet tatsächlich macht.
  final List<ErcolinaCanonicalStep> steps;
}

/// Die 18 Einheiten der Gerätebibliothek.
const List<ErcolinaCanonicalWorkout> ercolinaCanonicalLibrary = [
  ErcolinaCanonicalWorkout(
    id: 'E0_TECH_EASY',
    title: 'E0 Prehab/Technik 20min',
    minutes: 20,
    type: 'TECH',
    level: 'E',
    season: 'common',
    file: 'common/E0_TECH_EASY_20m_E_v1.csv',
    notes: 'Very easy, shoulder low, core stable.',
    steps: [
      ErcolinaCanonicalStep(
        seconds: 720,
        percentFtp: 60,
        hint: 'easy and smooth',
      ),
      ErcolinaCanonicalStep(
        seconds: 480,
        percentFtp: 55,
        hint: 'technique focus',
      ),
    ],
  ),
  ErcolinaCanonicalWorkout(
    id: 'E10_VO2_5x5',
    title: 'E10 VO2max I5 5x5',
    minutes: 62,
    type: 'VO2',
    level: 'H',
    season: 'common',
    file: 'common/E10_VO2_5x5_62m_H_v1.csv',
    notes:
        'Fuenf mal 5min mit 3min Pause. Ziel ist die Zeit nahe VO2max nicht die hoechste Einzelleistung.',
    steps: [
      ErcolinaCanonicalStep(
        seconds: 720,
        percentFtp: 60,
        hint: 'locker einfahren Technik sauber',
      ),
      ErcolinaCanonicalStep(
        seconds: 20,
        percentFtp: 112,
        hint: 'kurze Aktivierung',
      ),
      ErcolinaCanonicalStep(
        seconds: 40,
        percentFtp: 60,
        hint: 'locker ausrollen',
      ),
      ErcolinaCanonicalStep(
        seconds: 20,
        percentFtp: 112,
        hint: 'kurze Aktivierung',
      ),
      ErcolinaCanonicalStep(
        seconds: 40,
        percentFtp: 60,
        hint: 'locker ausrollen',
      ),
      ErcolinaCanonicalStep(
        seconds: 20,
        percentFtp: 112,
        hint: 'kurze Aktivierung',
      ),
      ErcolinaCanonicalStep(
        seconds: 40,
        percentFtp: 60,
        hint: 'locker ausrollen',
      ),
      ErcolinaCanonicalStep(seconds: 300, percentFtp: 112, hint: 'VO2max 1/5'),
      ErcolinaCanonicalStep(
        seconds: 180,
        percentFtp: 60,
        hint: 'locker traben',
      ),
      ErcolinaCanonicalStep(seconds: 300, percentFtp: 112, hint: 'VO2max 2/5'),
      ErcolinaCanonicalStep(
        seconds: 180,
        percentFtp: 60,
        hint: 'locker traben',
      ),
      ErcolinaCanonicalStep(seconds: 300, percentFtp: 112, hint: 'VO2max 3/5'),
      ErcolinaCanonicalStep(
        seconds: 180,
        percentFtp: 60,
        hint: 'locker traben',
      ),
      ErcolinaCanonicalStep(seconds: 300, percentFtp: 112, hint: 'VO2max 4/5'),
      ErcolinaCanonicalStep(
        seconds: 180,
        percentFtp: 60,
        hint: 'locker traben',
      ),
      ErcolinaCanonicalStep(seconds: 300, percentFtp: 112, hint: 'VO2max 5/5'),
      ErcolinaCanonicalStep(seconds: 600, percentFtp: 60, hint: 'ausfahren'),
    ],
  ),
  ErcolinaCanonicalWorkout(
    id: 'E11_ANAEROB_2x8x1',
    title: 'E11 Anaerob I6 2x8x1min',
    minutes: 70,
    type: 'ANAEROB',
    level: 'H',
    season: 'common',
    file: 'common/E11_ANAEROB_2x8x1_70m_H_v1.csv',
    notes:
        'Zwei Serien a 8x1min mit 90s Pause und 5min Serienpause. Abbruchkriterium ist die Technik nicht die Uhr.',
    steps: [
      ErcolinaCanonicalStep(
        seconds: 720,
        percentFtp: 60,
        hint: 'locker einfahren Technik sauber',
      ),
      ErcolinaCanonicalStep(
        seconds: 20,
        percentFtp: 112,
        hint: 'kurze Aktivierung',
      ),
      ErcolinaCanonicalStep(
        seconds: 40,
        percentFtp: 60,
        hint: 'locker ausrollen',
      ),
      ErcolinaCanonicalStep(
        seconds: 20,
        percentFtp: 112,
        hint: 'kurze Aktivierung',
      ),
      ErcolinaCanonicalStep(
        seconds: 40,
        percentFtp: 60,
        hint: 'locker ausrollen',
      ),
      ErcolinaCanonicalStep(
        seconds: 20,
        percentFtp: 112,
        hint: 'kurze Aktivierung',
      ),
      ErcolinaCanonicalStep(
        seconds: 40,
        percentFtp: 60,
        hint: 'locker ausrollen',
      ),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 135,
        hint: 'Serie 1 anaerob 1/8',
      ),
      ErcolinaCanonicalStep(seconds: 90, percentFtp: 60, hint: 'locker traben'),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 135,
        hint: 'Serie 1 anaerob 2/8',
      ),
      ErcolinaCanonicalStep(seconds: 90, percentFtp: 60, hint: 'locker traben'),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 135,
        hint: 'Serie 1 anaerob 3/8',
      ),
      ErcolinaCanonicalStep(seconds: 90, percentFtp: 60, hint: 'locker traben'),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 135,
        hint: 'Serie 1 anaerob 4/8',
      ),
      ErcolinaCanonicalStep(seconds: 90, percentFtp: 60, hint: 'locker traben'),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 135,
        hint: 'Serie 1 anaerob 5/8',
      ),
      ErcolinaCanonicalStep(seconds: 90, percentFtp: 60, hint: 'locker traben'),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 135,
        hint: 'Serie 1 anaerob 6/8',
      ),
      ErcolinaCanonicalStep(seconds: 90, percentFtp: 60, hint: 'locker traben'),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 135,
        hint: 'Serie 1 anaerob 7/8',
      ),
      ErcolinaCanonicalStep(seconds: 90, percentFtp: 60, hint: 'locker traben'),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 135,
        hint: 'Serie 1 anaerob 8/8',
      ),
      ErcolinaCanonicalStep(seconds: 90, percentFtp: 60, hint: 'Ende Serie 1'),
      ErcolinaCanonicalStep(
        seconds: 300,
        percentFtp: 60,
        hint: 'Serienpause locker',
      ),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 135,
        hint: 'Serie 2 anaerob 1/8',
      ),
      ErcolinaCanonicalStep(seconds: 90, percentFtp: 60, hint: 'locker traben'),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 135,
        hint: 'Serie 2 anaerob 2/8',
      ),
      ErcolinaCanonicalStep(seconds: 90, percentFtp: 60, hint: 'locker traben'),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 135,
        hint: 'Serie 2 anaerob 3/8',
      ),
      ErcolinaCanonicalStep(seconds: 90, percentFtp: 60, hint: 'locker traben'),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 135,
        hint: 'Serie 2 anaerob 4/8',
      ),
      ErcolinaCanonicalStep(seconds: 90, percentFtp: 60, hint: 'locker traben'),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 135,
        hint: 'Serie 2 anaerob 5/8',
      ),
      ErcolinaCanonicalStep(seconds: 90, percentFtp: 60, hint: 'locker traben'),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 135,
        hint: 'Serie 2 anaerob 6/8',
      ),
      ErcolinaCanonicalStep(seconds: 90, percentFtp: 60, hint: 'locker traben'),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 135,
        hint: 'Serie 2 anaerob 7/8',
      ),
      ErcolinaCanonicalStep(seconds: 90, percentFtp: 60, hint: 'locker traben'),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 135,
        hint: 'Serie 2 anaerob 8/8',
      ),
      ErcolinaCanonicalStep(seconds: 90, percentFtp: 60, hint: 'Ende Serie 2'),
      ErcolinaCanonicalStep(seconds: 600, percentFtp: 60, hint: 'ausfahren'),
    ],
  ),
  ErcolinaCanonicalWorkout(
    id: 'E12_SPRINT_12x10s',
    title: 'E12 Sprint I8 12x10s',
    minutes: 61,
    type: 'SPRINT',
    level: 'H',
    season: 'common',
    file: 'common/E12_SPRINT_12x10s_61m_H_v1.csv',
    notes:
        'Zwoelf Sprints a 10s mit fast drei Minuten Pause. Der Zielwert von 200 Prozent FTP ist nur ein Anzeigeanker - massgeblich ist maximal.',
    steps: [
      ErcolinaCanonicalStep(
        seconds: 720,
        percentFtp: 60,
        hint: 'locker einfahren Technik sauber',
      ),
      ErcolinaCanonicalStep(
        seconds: 20,
        percentFtp: 165,
        hint: 'kurze Aktivierung',
      ),
      ErcolinaCanonicalStep(
        seconds: 40,
        percentFtp: 60,
        hint: 'locker ausrollen',
      ),
      ErcolinaCanonicalStep(
        seconds: 20,
        percentFtp: 165,
        hint: 'kurze Aktivierung',
      ),
      ErcolinaCanonicalStep(
        seconds: 40,
        percentFtp: 60,
        hint: 'locker ausrollen',
      ),
      ErcolinaCanonicalStep(
        seconds: 20,
        percentFtp: 165,
        hint: 'kurze Aktivierung',
      ),
      ErcolinaCanonicalStep(
        seconds: 40,
        percentFtp: 60,
        hint: 'locker ausrollen',
      ),
      ErcolinaCanonicalStep(
        seconds: 10,
        percentFtp: 200,
        hint: 'SPRINT maximal 1/12',
      ),
      ErcolinaCanonicalStep(
        seconds: 170,
        percentFtp: 60,
        hint: 'vollstaendig erholen',
      ),
      ErcolinaCanonicalStep(
        seconds: 10,
        percentFtp: 200,
        hint: 'SPRINT maximal 2/12',
      ),
      ErcolinaCanonicalStep(
        seconds: 170,
        percentFtp: 60,
        hint: 'vollstaendig erholen',
      ),
      ErcolinaCanonicalStep(
        seconds: 10,
        percentFtp: 200,
        hint: 'SPRINT maximal 3/12',
      ),
      ErcolinaCanonicalStep(
        seconds: 170,
        percentFtp: 60,
        hint: 'vollstaendig erholen',
      ),
      ErcolinaCanonicalStep(
        seconds: 10,
        percentFtp: 200,
        hint: 'SPRINT maximal 4/12',
      ),
      ErcolinaCanonicalStep(
        seconds: 170,
        percentFtp: 60,
        hint: 'vollstaendig erholen',
      ),
      ErcolinaCanonicalStep(
        seconds: 10,
        percentFtp: 200,
        hint: 'SPRINT maximal 5/12',
      ),
      ErcolinaCanonicalStep(
        seconds: 170,
        percentFtp: 60,
        hint: 'vollstaendig erholen',
      ),
      ErcolinaCanonicalStep(
        seconds: 10,
        percentFtp: 200,
        hint: 'SPRINT maximal 6/12',
      ),
      ErcolinaCanonicalStep(
        seconds: 170,
        percentFtp: 60,
        hint: 'vollstaendig erholen',
      ),
      ErcolinaCanonicalStep(
        seconds: 10,
        percentFtp: 200,
        hint: 'SPRINT maximal 7/12',
      ),
      ErcolinaCanonicalStep(
        seconds: 170,
        percentFtp: 60,
        hint: 'vollstaendig erholen',
      ),
      ErcolinaCanonicalStep(
        seconds: 10,
        percentFtp: 200,
        hint: 'SPRINT maximal 8/12',
      ),
      ErcolinaCanonicalStep(
        seconds: 170,
        percentFtp: 60,
        hint: 'vollstaendig erholen',
      ),
      ErcolinaCanonicalStep(
        seconds: 10,
        percentFtp: 200,
        hint: 'SPRINT maximal 9/12',
      ),
      ErcolinaCanonicalStep(
        seconds: 170,
        percentFtp: 60,
        hint: 'vollstaendig erholen',
      ),
      ErcolinaCanonicalStep(
        seconds: 10,
        percentFtp: 200,
        hint: 'SPRINT maximal 10/12',
      ),
      ErcolinaCanonicalStep(
        seconds: 170,
        percentFtp: 60,
        hint: 'vollstaendig erholen',
      ),
      ErcolinaCanonicalStep(
        seconds: 10,
        percentFtp: 200,
        hint: 'SPRINT maximal 11/12',
      ),
      ErcolinaCanonicalStep(
        seconds: 170,
        percentFtp: 60,
        hint: 'vollstaendig erholen',
      ),
      ErcolinaCanonicalStep(
        seconds: 10,
        percentFtp: 200,
        hint: 'SPRINT maximal 12/12',
      ),
      ErcolinaCanonicalStep(seconds: 170, percentFtp: 60, hint: 'letzte Pause'),
      ErcolinaCanonicalStep(seconds: 600, percentFtp: 60, hint: 'ausfahren'),
    ],
  ),
  ErcolinaCanonicalWorkout(
    id: 'E13_OVERUNDER_4x9',
    title: 'E13 Over/Under I4-I5 4x9',
    minutes: 73,
    type: 'OVERUNDER',
    level: 'H',
    season: 'common',
    file: 'common/E13_OVERUNDER_4x9_73m_H_v1.csv',
    notes:
        'Vier Bloecke a 3x(2min unter Schwelle + 1min darueber). Der under-Abschnitt ist Teil der Belastung keine Pause.',
    steps: [
      ErcolinaCanonicalStep(
        seconds: 720,
        percentFtp: 60,
        hint: 'locker einfahren Technik sauber',
      ),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 97,
        hint: 'kurze Aktivierung',
      ),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 60,
        hint: 'locker ausrollen',
      ),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 97,
        hint: 'kurze Aktivierung',
      ),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 60,
        hint: 'locker ausrollen',
      ),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 97,
        hint: 'kurze Aktivierung',
      ),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 60,
        hint: 'locker ausrollen',
      ),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 97,
        hint: 'Block 1 under 1/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 112,
        hint: 'Block 1 over 1/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 97,
        hint: 'Block 1 under 2/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 112,
        hint: 'Block 1 over 2/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 97,
        hint: 'Block 1 under 3/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 112,
        hint: 'Block 1 over 3/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 240,
        percentFtp: 60,
        hint: 'locker traben',
      ),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 97,
        hint: 'Block 2 under 1/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 112,
        hint: 'Block 2 over 1/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 97,
        hint: 'Block 2 under 2/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 112,
        hint: 'Block 2 over 2/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 97,
        hint: 'Block 2 under 3/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 112,
        hint: 'Block 2 over 3/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 240,
        percentFtp: 60,
        hint: 'locker traben',
      ),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 97,
        hint: 'Block 3 under 1/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 112,
        hint: 'Block 3 over 1/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 97,
        hint: 'Block 3 under 2/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 112,
        hint: 'Block 3 over 2/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 97,
        hint: 'Block 3 under 3/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 112,
        hint: 'Block 3 over 3/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 240,
        percentFtp: 60,
        hint: 'locker traben',
      ),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 97,
        hint: 'Block 4 under 1/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 112,
        hint: 'Block 4 over 1/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 97,
        hint: 'Block 4 under 2/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 112,
        hint: 'Block 4 over 2/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 97,
        hint: 'Block 4 under 3/3',
      ),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 112,
        hint: 'Block 4 over 3/3',
      ),
      ErcolinaCanonicalStep(seconds: 600, percentFtp: 60, hint: 'ausfahren'),
    ],
  ),
  ErcolinaCanonicalWorkout(
    id: 'E14_PROGRESSIV',
    title: 'E14 Progressiv I1-I5 60min',
    minutes: 60,
    type: 'PROGRESSION',
    level: 'M',
    season: 'common',
    file: 'common/E14_PROGRESSIV_60m_M_v1.csv',
    notes:
        'Eine Stufe pro Block ohne Pause dazwischen. Gute Einheit um die eigenen Zonen zu ueberpruefen.',
    steps: [
      ErcolinaCanonicalStep(
        seconds: 600,
        percentFtp: 60,
        hint: 'Stufe 1 locker',
      ),
      ErcolinaCanonicalStep(
        seconds: 900,
        percentFtp: 78,
        hint: 'Stufe 2 Dauerbereich',
      ),
      ErcolinaCanonicalStep(
        seconds: 900,
        percentFtp: 88,
        hint: 'Stufe 3 zuegig',
      ),
      ErcolinaCanonicalStep(
        seconds: 600,
        percentFtp: 97,
        hint: 'Stufe 4 Schwelle',
      ),
      ErcolinaCanonicalStep(
        seconds: 300,
        percentFtp: 112,
        hint: 'Stufe 5 VO2max',
      ),
      ErcolinaCanonicalStep(seconds: 300, percentFtp: 60, hint: 'ausfahren'),
    ],
  ),
  ErcolinaCanonicalWorkout(
    id: 'E1_TECH_ECON',
    title: 'E1 Technik und Oekonomie 25min',
    minutes: 25,
    type: 'TECH',
    level: 'E',
    season: 'common',
    file: 'common/E1_TECH_ECON_25m_E_v1.csv',
    notes: '10min warmup, 6x(30s brisk/60s easy), 1min easy, 5min cooldown.',
    steps: [
      ErcolinaCanonicalStep(
        seconds: 600,
        percentFtp: 65,
        hint: 'easy and smooth',
      ),
      ErcolinaCanonicalStep(seconds: 30, percentFtp: 110, hint: 'brisk'),
      ErcolinaCanonicalStep(seconds: 60, percentFtp: 60, hint: 'easy recovery'),
      ErcolinaCanonicalStep(seconds: 30, percentFtp: 110, hint: 'brisk'),
      ErcolinaCanonicalStep(seconds: 60, percentFtp: 60, hint: 'easy recovery'),
      ErcolinaCanonicalStep(seconds: 30, percentFtp: 110, hint: 'brisk'),
      ErcolinaCanonicalStep(seconds: 60, percentFtp: 60, hint: 'easy recovery'),
      ErcolinaCanonicalStep(seconds: 30, percentFtp: 110, hint: 'brisk'),
      ErcolinaCanonicalStep(seconds: 60, percentFtp: 60, hint: 'easy recovery'),
      ErcolinaCanonicalStep(seconds: 30, percentFtp: 110, hint: 'brisk'),
      ErcolinaCanonicalStep(seconds: 60, percentFtp: 60, hint: 'easy recovery'),
      ErcolinaCanonicalStep(seconds: 30, percentFtp: 110, hint: 'brisk'),
      ErcolinaCanonicalStep(seconds: 60, percentFtp: 60, hint: 'easy recovery'),
      ErcolinaCanonicalStep(seconds: 60, percentFtp: 60, hint: 'easy recovery'),
      ErcolinaCanonicalStep(
        seconds: 300,
        percentFtp: 60,
        hint: 'easy recovery',
      ),
    ],
  ),
  ErcolinaCanonicalWorkout(
    id: 'E2_EB_5x3',
    title: 'E2 Kraftausdauer EB 40min (5x3)',
    minutes: 40,
    type: 'EB',
    level: 'M',
    season: 'common',
    file: 'common/E2_EB_5x3_40m_M_v1.csv',
    notes: '10min warmup, 5x(3min EB / 2min easy), 5min cooldown.',
    steps: [
      ErcolinaCanonicalStep(
        seconds: 600,
        percentFtp: 65,
        hint: 'easy and smooth',
      ),
      ErcolinaCanonicalStep(seconds: 180, percentFtp: 108, hint: 'EB steady'),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 60,
        hint: 'easy recovery',
      ),
      ErcolinaCanonicalStep(seconds: 180, percentFtp: 108, hint: 'EB steady'),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 60,
        hint: 'easy recovery',
      ),
      ErcolinaCanonicalStep(seconds: 180, percentFtp: 108, hint: 'EB steady'),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 60,
        hint: 'easy recovery',
      ),
      ErcolinaCanonicalStep(seconds: 180, percentFtp: 108, hint: 'EB steady'),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 60,
        hint: 'easy recovery',
      ),
      ErcolinaCanonicalStep(seconds: 180, percentFtp: 108, hint: 'EB steady'),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 60,
        hint: 'easy recovery',
      ),
      ErcolinaCanonicalStep(
        seconds: 300,
        percentFtp: 60,
        hint: 'easy recovery',
      ),
    ],
  ),
  ErcolinaCanonicalWorkout(
    id: 'E2_GA2toEB_3x8',
    title: 'E2 GA2->EB 40min (3x8)',
    minutes: 40,
    type: 'EB',
    level: 'M',
    season: 'common',
    file: 'common/E2_GA2toEB_3x8_40m_M_v1.csv',
    notes: 'Warmup/cooldown trimmed to hit 40min total.',
    steps: [
      ErcolinaCanonicalStep(
        seconds: 300,
        percentFtp: 65,
        hint: 'easy and smooth',
      ),
      ErcolinaCanonicalStep(seconds: 480, percentFtp: 95, hint: 'GA2->EB'),
      ErcolinaCanonicalStep(
        seconds: 240,
        percentFtp: 60,
        hint: 'easy recovery',
      ),
      ErcolinaCanonicalStep(seconds: 480, percentFtp: 95, hint: 'GA2->EB'),
      ErcolinaCanonicalStep(
        seconds: 240,
        percentFtp: 60,
        hint: 'easy recovery',
      ),
      ErcolinaCanonicalStep(seconds: 480, percentFtp: 95, hint: 'GA2->EB'),
      ErcolinaCanonicalStep(
        seconds: 180,
        percentFtp: 60,
        hint: 'easy recovery',
      ),
    ],
  ),
  ErcolinaCanonicalWorkout(
    id: 'E3_SPEED',
    title: 'E3 Speed 20min',
    minutes: 20,
    type: 'SPEED',
    level: 'H',
    season: 'common',
    file: 'common/E3_SPEED_20m_H_v1.csv',
    notes: '5min warmup, 8x(30s fast/60s easy), 3min cooldown.',
    steps: [
      ErcolinaCanonicalStep(
        seconds: 300,
        percentFtp: 65,
        hint: 'easy and smooth',
      ),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 160,
        hint: 'sprint - stay clean',
      ),
      ErcolinaCanonicalStep(seconds: 60, percentFtp: 60, hint: 'easy recovery'),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 160,
        hint: 'sprint - stay clean',
      ),
      ErcolinaCanonicalStep(seconds: 60, percentFtp: 60, hint: 'easy recovery'),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 160,
        hint: 'sprint - stay clean',
      ),
      ErcolinaCanonicalStep(seconds: 60, percentFtp: 60, hint: 'easy recovery'),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 160,
        hint: 'sprint - stay clean',
      ),
      ErcolinaCanonicalStep(seconds: 60, percentFtp: 60, hint: 'easy recovery'),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 160,
        hint: 'sprint - stay clean',
      ),
      ErcolinaCanonicalStep(seconds: 60, percentFtp: 60, hint: 'easy recovery'),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 160,
        hint: 'sprint - stay clean',
      ),
      ErcolinaCanonicalStep(seconds: 60, percentFtp: 60, hint: 'easy recovery'),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 160,
        hint: 'sprint - stay clean',
      ),
      ErcolinaCanonicalStep(seconds: 60, percentFtp: 60, hint: 'easy recovery'),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 160,
        hint: 'sprint - stay clean',
      ),
      ErcolinaCanonicalStep(seconds: 60, percentFtp: 60, hint: 'easy recovery'),
      ErcolinaCanonicalStep(
        seconds: 180,
        percentFtp: 60,
        hint: 'easy recovery',
      ),
    ],
  ),
  ErcolinaCanonicalWorkout(
    id: 'E4_LONG_EASY',
    title: 'E4 Lange locker 55min',
    minutes: 55,
    type: 'LONG',
    level: 'E',
    season: 'common',
    file: 'common/E4_LONG_EASY_55m_E_v1.csv',
    notes: '10min easy, then 3x(10min diagonal + 5min double).',
    steps: [
      ErcolinaCanonicalStep(
        seconds: 600,
        percentFtp: 65,
        hint: 'easy and smooth',
      ),
      ErcolinaCanonicalStep(
        seconds: 600,
        percentFtp: 65,
        hint: 'diagonal easy',
      ),
      ErcolinaCanonicalStep(seconds: 300, percentFtp: 60, hint: 'double easy'),
      ErcolinaCanonicalStep(
        seconds: 600,
        percentFtp: 65,
        hint: 'diagonal easy',
      ),
      ErcolinaCanonicalStep(seconds: 300, percentFtp: 60, hint: 'double easy'),
      ErcolinaCanonicalStep(
        seconds: 600,
        percentFtp: 65,
        hint: 'diagonal easy',
      ),
      ErcolinaCanonicalStep(seconds: 300, percentFtp: 60, hint: 'double easy'),
    ],
  ),
  ErcolinaCanonicalWorkout(
    id: 'E5_VO2_5x3',
    title: 'E5 VO2max 35min (5x3)',
    minutes: 35,
    type: 'VO2',
    level: 'H',
    season: 'common',
    file: 'common/E5_VO2_5x3_35m_H_v1.csv',
    notes: 'Warmup trimmed to fit 35min total.',
    steps: [
      ErcolinaCanonicalStep(
        seconds: 300,
        percentFtp: 65,
        hint: 'easy and smooth',
      ),
      ErcolinaCanonicalStep(seconds: 180, percentFtp: 120, hint: 'VO2 hard'),
      ErcolinaCanonicalStep(
        seconds: 180,
        percentFtp: 60,
        hint: 'easy recovery',
      ),
      ErcolinaCanonicalStep(seconds: 180, percentFtp: 120, hint: 'VO2 hard'),
      ErcolinaCanonicalStep(
        seconds: 180,
        percentFtp: 60,
        hint: 'easy recovery',
      ),
      ErcolinaCanonicalStep(seconds: 180, percentFtp: 120, hint: 'VO2 hard'),
      ErcolinaCanonicalStep(
        seconds: 180,
        percentFtp: 60,
        hint: 'easy recovery',
      ),
      ErcolinaCanonicalStep(seconds: 180, percentFtp: 120, hint: 'VO2 hard'),
      ErcolinaCanonicalStep(
        seconds: 180,
        percentFtp: 60,
        hint: 'easy recovery',
      ),
      ErcolinaCanonicalStep(seconds: 180, percentFtp: 120, hint: 'VO2 hard'),
      ErcolinaCanonicalStep(
        seconds: 180,
        percentFtp: 60,
        hint: 'easy recovery',
      ),
    ],
  ),
  ErcolinaCanonicalWorkout(
    id: 'E6_BASE_I1',
    title: 'E6 Grundlage I1 75min',
    minutes: 75,
    type: 'BASE',
    level: 'E',
    season: 'common',
    file: 'common/E6_BASE_I1_75m_E_v1.csv',
    notes:
        'Reine I1-Einheit. Wenn die Leistung nicht ohne Anstrengung zu halten ist ist der Widerstand zu hoch.',
    steps: [
      ErcolinaCanonicalStep(
        seconds: 600,
        percentFtp: 60,
        hint: 'locker einfahren',
      ),
      ErcolinaCanonicalStep(
        seconds: 1500,
        percentFtp: 60,
        hint: 'ruhig und gleichmaessig',
      ),
      ErcolinaCanonicalStep(
        seconds: 1500,
        percentFtp: 60,
        hint: 'Technik halten Schulter tief',
      ),
      ErcolinaCanonicalStep(
        seconds: 600,
        percentFtp: 60,
        hint: 'gleichmaessig zu Ende',
      ),
      ErcolinaCanonicalStep(seconds: 300, percentFtp: 60, hint: 'ausfahren'),
    ],
  ),
  ErcolinaCanonicalWorkout(
    id: 'E7_LONG_I2',
    title: 'E7 Langer Dauerbereich I2 3x25',
    minutes: 105,
    type: 'LONG',
    level: 'M',
    season: 'common',
    file: 'common/E7_LONG_I2_105m_M_v1.csv',
    notes:
        'Drei Bloecke a 25min I2 mit 5min locker. Bricht der Rhythmus im dritten Block ein war I2 zu hoch angesetzt.',
    steps: [
      ErcolinaCanonicalStep(seconds: 900, percentFtp: 60, hint: 'einfahren'),
      ErcolinaCanonicalStep(
        seconds: 1500,
        percentFtp: 78,
        hint: 'Block 1/3 ruhiger Rhythmus',
      ),
      ErcolinaCanonicalStep(
        seconds: 300,
        percentFtp: 60,
        hint: 'locker traben',
      ),
      ErcolinaCanonicalStep(
        seconds: 1500,
        percentFtp: 78,
        hint: 'Block 2/3 gleicher Rhythmus',
      ),
      ErcolinaCanonicalStep(
        seconds: 300,
        percentFtp: 60,
        hint: 'locker traben',
      ),
      ErcolinaCanonicalStep(
        seconds: 1500,
        percentFtp: 78,
        hint: 'Block 3/3 Technik nicht verlieren',
      ),
      ErcolinaCanonicalStep(seconds: 300, percentFtp: 60, hint: 'ausfahren'),
    ],
  ),
  ErcolinaCanonicalWorkout(
    id: 'E8_TEMPO_I3',
    title: 'E8 Zuegiger Dauerbereich I3 3x15',
    minutes: 80,
    type: 'TEMPO',
    level: 'M',
    season: 'common',
    file: 'common/E8_TEMPO_I3_3x15_80m_M_v1.csv',
    notes:
        'Der klassische Mitteltempo-Bereich. Bewusst unterhalb der Schwelle bleiben sonst wird daraus eine Schwelleneinheit.',
    steps: [
      ErcolinaCanonicalStep(seconds: 900, percentFtp: 60, hint: 'einfahren'),
      ErcolinaCanonicalStep(
        seconds: 900,
        percentFtp: 88,
        hint: 'Block 1/3 zuegig kontrolliert',
      ),
      ErcolinaCanonicalStep(
        seconds: 300,
        percentFtp: 60,
        hint: 'locker traben',
      ),
      ErcolinaCanonicalStep(
        seconds: 900,
        percentFtp: 88,
        hint: 'Block 2/3 gleiche Leistung',
      ),
      ErcolinaCanonicalStep(
        seconds: 300,
        percentFtp: 60,
        hint: 'locker traben',
      ),
      ErcolinaCanonicalStep(
        seconds: 900,
        percentFtp: 88,
        hint: 'Block 3/3 sauber zu Ende',
      ),
      ErcolinaCanonicalStep(seconds: 600, percentFtp: 60, hint: 'ausfahren'),
    ],
  ),
  ErcolinaCanonicalWorkout(
    id: 'E9_SCHWELLE_6x10',
    title: 'E9 Schwelle I4 6x10',
    minutes: 95,
    type: 'THRESHOLD',
    level: 'H',
    season: 'common',
    file: 'common/E9_SCHWELLE_6x10_95m_H_v1.csv',
    notes:
        'Sechs mal 10min an der Schwelle mit 2min locker. Wenn Wiederholung 5 und 6 nicht mehr auf Leistung gehalten werden koennen war der Start zu hoch.',
    steps: [
      ErcolinaCanonicalStep(
        seconds: 720,
        percentFtp: 60,
        hint: 'locker einfahren Technik sauber',
      ),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 88,
        hint: 'kurze Aktivierung',
      ),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 60,
        hint: 'locker ausrollen',
      ),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 88,
        hint: 'kurze Aktivierung',
      ),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 60,
        hint: 'locker ausrollen',
      ),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 88,
        hint: 'kurze Aktivierung',
      ),
      ErcolinaCanonicalStep(
        seconds: 30,
        percentFtp: 60,
        hint: 'locker ausrollen',
      ),
      ErcolinaCanonicalStep(seconds: 600, percentFtp: 97, hint: 'Schwelle 1/6'),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 60,
        hint: 'locker traben',
      ),
      ErcolinaCanonicalStep(seconds: 600, percentFtp: 97, hint: 'Schwelle 2/6'),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 60,
        hint: 'locker traben',
      ),
      ErcolinaCanonicalStep(seconds: 600, percentFtp: 97, hint: 'Schwelle 3/6'),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 60,
        hint: 'locker traben',
      ),
      ErcolinaCanonicalStep(seconds: 600, percentFtp: 97, hint: 'Schwelle 4/6'),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 60,
        hint: 'locker traben',
      ),
      ErcolinaCanonicalStep(seconds: 600, percentFtp: 97, hint: 'Schwelle 5/6'),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 60,
        hint: 'locker traben',
      ),
      ErcolinaCanonicalStep(seconds: 600, percentFtp: 97, hint: 'Schwelle 6/6'),
      ErcolinaCanonicalStep(seconds: 600, percentFtp: 60, hint: 'ausfahren'),
    ],
  ),
  ErcolinaCanonicalWorkout(
    id: 'FTP_TEST_20MIN',
    title: 'FTP Test 20min',
    minutes: 49,
    type: 'TEST',
    level: 'H',
    season: 'common',
    file: 'common/FTP_TEST_20MIN_49m_H_v1.csv',
    notes:
        '8min warmup, 3x(1min brisk/1min easy), 5min easy, 20min TT, 10min cooldown.',
    steps: [
      ErcolinaCanonicalStep(
        seconds: 480,
        percentFtp: 65,
        hint: 'easy and smooth',
      ),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 95,
        hint: 'steady and controlled',
      ),
      ErcolinaCanonicalStep(seconds: 60, percentFtp: 60, hint: 'easy recovery'),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 95,
        hint: 'steady and controlled',
      ),
      ErcolinaCanonicalStep(seconds: 60, percentFtp: 60, hint: 'easy recovery'),
      ErcolinaCanonicalStep(
        seconds: 60,
        percentFtp: 95,
        hint: 'steady and controlled',
      ),
      ErcolinaCanonicalStep(seconds: 60, percentFtp: 60, hint: 'easy recovery'),
      ErcolinaCanonicalStep(
        seconds: 300,
        percentFtp: 60,
        hint: 'easy recovery',
      ),
      ErcolinaCanonicalStep(
        seconds: 1200,
        percentFtp: 105,
        hint: 'TEST 20min TT',
      ),
      ErcolinaCanonicalStep(
        seconds: 600,
        percentFtp: 60,
        hint: 'easy recovery',
      ),
    ],
  ),
  ErcolinaCanonicalWorkout(
    id: 'E15_SKIMARA_3x30',
    title: 'E15 Skimarathon 3x30 spezifisch',
    minutes: 125,
    type: 'RACE',
    level: 'M',
    season: 'winter',
    file: 'winter/E15_SKIMARA_3x30_125m_M_v1.csv',
    notes:
        'Drei Bloecke a 30min die von I2 ueber I3 zurueck auf I2 gehen und mit 2min I4 enden. Simuliert Anstiege am Ende eines langen Rennens.',
    steps: [
      ErcolinaCanonicalStep(seconds: 900, percentFtp: 60, hint: 'einfahren'),
      ErcolinaCanonicalStep(
        seconds: 600,
        percentFtp: 78,
        hint: 'Block 1 Grundtempo',
      ),
      ErcolinaCanonicalStep(
        seconds: 600,
        percentFtp: 88,
        hint: 'Block 1 zuegig',
      ),
      ErcolinaCanonicalStep(
        seconds: 480,
        percentFtp: 78,
        hint: 'Block 1 zurueck ins Grundtempo',
      ),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 97,
        hint: 'Block 1 Schlussanstieg',
      ),
      ErcolinaCanonicalStep(
        seconds: 300,
        percentFtp: 60,
        hint: 'locker traben',
      ),
      ErcolinaCanonicalStep(
        seconds: 600,
        percentFtp: 78,
        hint: 'Block 2 Grundtempo',
      ),
      ErcolinaCanonicalStep(
        seconds: 600,
        percentFtp: 88,
        hint: 'Block 2 zuegig',
      ),
      ErcolinaCanonicalStep(
        seconds: 480,
        percentFtp: 78,
        hint: 'Block 2 zurueck ins Grundtempo',
      ),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 97,
        hint: 'Block 2 Schlussanstieg',
      ),
      ErcolinaCanonicalStep(
        seconds: 300,
        percentFtp: 60,
        hint: 'locker traben',
      ),
      ErcolinaCanonicalStep(
        seconds: 600,
        percentFtp: 78,
        hint: 'Block 3 Grundtempo',
      ),
      ErcolinaCanonicalStep(
        seconds: 600,
        percentFtp: 88,
        hint: 'Block 3 zuegig',
      ),
      ErcolinaCanonicalStep(
        seconds: 480,
        percentFtp: 78,
        hint: 'Block 3 zurueck ins Grundtempo',
      ),
      ErcolinaCanonicalStep(
        seconds: 120,
        percentFtp: 97,
        hint: 'Block 3 Schlussanstieg',
      ),
      ErcolinaCanonicalStep(seconds: 600, percentFtp: 60, hint: 'ausfahren'),
    ],
  ),
];
