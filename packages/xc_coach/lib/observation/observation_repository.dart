/// Der Zugang zu Beobachtungen — als Vertrag.
///
/// Aus demselben Grund wie bei der Coaching-Domain: Die Regeln müssen prüfbar
/// bleiben, ohne dass eine Datei geöffnet wird, und ein Server später eine
/// zweite Fassung bekommen können.
library;

import 'observation.dart';

abstract interface class ObservationRepository {
  /// Legt eine Beobachtung an.
  void record(Observation observation);

  /// Alle Beobachtungen zu einem Test, nach Beobachtungszeitpunkt geordnet,
  /// bei Gleichstand nach Kennung — dieselbe Ordnung wie im Altbestand, damit
  /// ein Vergleich überhaupt möglich ist.
  List<Observation> ofTest(String testId);

  /// Alle Beobachtungen zu einer Trainingseinheit.
  List<Observation> ofSession(String sessionId);

  /// Beobachtungen eines Athleten in einem Zeitraum, unabhängig vom Kontext.
  List<Observation> ofAthlete(
    String athleteId, {
    int? fromUtcUs,
    int? toUtcUs,
    ObservationType? type,
  });
}
