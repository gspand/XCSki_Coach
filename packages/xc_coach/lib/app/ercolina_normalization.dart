/// Jede gefahrene Ercolina-Einheit erreicht den Coach — über genau einen Weg.
///
/// ## Was vorher fehlte
///
/// Der Coach liest seinen Zustand aus `normalized_session_record`. In diesem
/// Bestand lagen am 05.10.2026 **nur Strava-Aktivitäten** (1355), während
/// 114 lokale Ercolina-Einheiten der vorangegangenen drei Wochen fehlten:
/// das tatsächliche aktuelle Training des Athleten. `XCAthleteState` meldete
/// folgerichtig `unknownDays28d = 25` — fünfundzwanzig von achtundzwanzig
/// Tagen ohne Daten — und leitete daraus einen Doppelstock-Bedarf ab, der
/// zum Teil ein Datenloch war.
///
/// Die Ursache war keine fehlende Abbildung: [ErcolinaRecapAdapter] gab es
/// längst. Sie war nur an *einen* Bildschirm gekoppelt
/// (`athlete_surface.onSessionCompleted`). Wer über das Geräteprodukt oder
/// den Entwicklungsstand trainierte, erzeugte keine normalisierte Einheit —
/// die Persistenz hing am Einstiegsweg.
///
/// ## Warum hier und nicht im Bildschirm
///
/// Diese Datei kennt keine Oberfläche. Sie wird vom Abschluss der Einheit
/// gerufen — von [ErcolinaTrainingScope], der beide Produkte umhüllt — und
/// vom Backfill. Beide nehmen denselben fachlichen Weg; es gibt keine
/// Sonderdaten für historische Einheiten.
///
/// ## Genau einmal
///
/// [ErcolinaRecapAdapter] bildet `sourceId` deterministisch auf die
/// Sitzungskennung ab, und `saveNormalizedSession` schreibt mit
/// `ON CONFLICT(athlete_id, source, source_id) DO UPDATE`. Mehrfaches
/// Normalisieren derselben Einheit — Neustart, Wiederholung, Backfill über
/// bereits normalisierte Einheiten — aktualisiert denselben Satz und legt
/// keinen zweiten an.
library;

import '../database/coach_storage_repository.dart';
import '../database/session_repository.dart';
import '../domain/normalized_session.dart';
import '../domain/normalized_session_adapters.dart';
import 'session_recap.dart';

/// Normalisiert eine abgeschlossene Ercolina-Einheit.
///
/// Gibt die geschriebene Einheit zurück, oder null, wenn aus der Sitzung
/// keine Einheit wird — ohne Züge war es keine.
NormalizedSession? normalizeErcolinaSession({
  required SessionRepository sessions,
  required SqliteCoachStorageRepository storage,
  required String athleteId,
  required String sessionId,
  required int nowUtcUs,
}) {
  final summary = sessions.sessionById(sessionId);
  if (summary == null) return null;
  final recap = SessionRecapReader(sessions).of(summary);
  if (recap == null) return null;
  final normalized = ErcolinaRecapAdapter.toNormalized(
    recap,
    athleteId: athleteId,
  );
  storage.saveNormalizedSession(normalized, nowUtcUs: nowUtcUs);
  return normalized;
}

/// Was ein Backfill bewegt hat.
class ErcolinaBackfillReport {
  const ErcolinaBackfillReport({
    required this.considered,
    required this.normalized,
    required this.withoutStrokes,
    this.alreadyPresent = 0,
  });

  /// Gespeicherte Ercolina-Sitzungen dieses Athleten.
  final int considered;

  /// Davon als Einheit normalisiert (neu oder aktualisiert).
  final int normalized;

  /// Ohne Züge — keine Einheit, bewusst übersprungen.
  final int withoutStrokes;

  /// Lag schon im Coach-Bestand. Beim zweiten Lauf ist das der Normalfall.
  final int alreadyPresent;

  @override
  String toString() =>
      'betrachtet $considered, normalisiert $normalized, '
      'schon vorhanden $alreadyPresent, ohne Züge $withoutStrokes';
}

/// Holt bereits gespeicherte Ercolina-Einheiten in den Coach-Bestand nach.
///
/// Wiederholbar: Dieselbe Einheit landet auf demselben Satz. Wird beim Start
/// gerufen, damit kein Mensch daran denken muss.
ErcolinaBackfillReport backfillErcolinaSessions({
  required SessionRepository sessions,
  required SqliteCoachStorageRepository storage,
  required String athleteId,
  required int nowUtcUs,
}) {
  var normalized = 0;
  var withoutStrokes = 0;
  var alreadyPresent = 0;
  final summaries = sessions.sessionsOfAthlete(athleteId);
  for (final summary in summaries) {
    // Billig bleiben: Wer schon im Bestand liegt, braucht kein erneutes
    // Lesen aller Zuege. Das Ergebnis waere dasselbe.
    if (storage.hasNormalizedSession(
      athleteId: athleteId,
      source: NormalizedSessionSource.ercolina,
      sourceId: summary.id,
    )) {
      alreadyPresent++;
      continue;
    }
    final written = normalizeErcolinaSession(
      sessions: sessions,
      storage: storage,
      athleteId: athleteId,
      sessionId: summary.id,
      nowUtcUs: nowUtcUs,
    );
    if (written == null) {
      withoutStrokes++;
    } else {
      normalized++;
    }
  }
  return ErcolinaBackfillReport(
    considered: summaries.length,
    normalized: normalized,
    withoutStrokes: withoutStrokes,
    alreadyPresent: alreadyPresent,
  );
}
