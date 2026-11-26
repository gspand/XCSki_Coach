/// Dienst für den Abgleich zwischen einer Coach-Vorgabe ([WorkoutPrescription])
/// und einer tatsächlich beobachteten [NormalizedSession] aus einer zugelassenen Quelle.
///
/// Folgt den Vorgaben:
/// - Striktes Matching (Datum, Zeitfenster, Sportart, Dauer)
/// - Ercolina-Workouts werden über die explizite Workout-ID gematcht
/// - Unsichere Treffer werden als 'possibleMatch' markiert, nie blind behauptet
library;

import '../../domain/normalized_session.dart';
import '../../domain/xc_modality.dart';
import 'workout_prescription.dart';

enum MatchConfidence {
  exactMatch,
  possibleMatch,
  noMatch,
}

class SessionMatchResult {
  const SessionMatchResult({
    required this.prescription,
    required this.observedSession,
    required this.confidence,
    required this.reasons,
  });

  final WorkoutPrescription prescription;
  final NormalizedSession observedSession;
  final MatchConfidence confidence;
  final List<String> reasons;

  bool get isMatched => confidence != MatchConfidence.noMatch;
}

class SessionMatchingService {
  const SessionMatchingService();

  /// Überprüft, ob eine beobachtete Einheit zu einer Vorgabe passt.
  SessionMatchResult evaluateMatch({
    required WorkoutPrescription prescription,
    required NormalizedSession session,
  }) {
    if (!session.eligibleForCoach) {
      throw UnsupportedError('Die Datenquelle ist für den XC Ski Coach gesperrt.');
    }
    final reasons = <String>[];

    // 1. Expliziter Ercolina Template / Workout Match
    final templateOrBlueprint = prescription.templateId ?? prescription.blueprintId;
    if (templateOrBlueprint != null &&
        (session.sourceId == templateOrBlueprint ||
         session.rawMetadata['blueprintId'] == templateOrBlueprint ||
         session.rawMetadata['templateId'] == templateOrBlueprint)) {
      reasons.add('Exakte Ercolina Workout-ID stimmt überein ($templateOrBlueprint).');
      return SessionMatchResult(
        prescription: prescription,
        observedSession: session,
        confidence: MatchConfidence.exactMatch,
        reasons: reasons,
      );
    }

    // 2. Datum / Zeitfenster prüfen (am selben Kalendertag)
    final prescriptionDate = DateTime.now(); // lokales Tagesfenster
    final sessionDate = session.startedAtLocal;

    final isSameDay = prescriptionDate.year == sessionDate.year &&
        prescriptionDate.month == sessionDate.month &&
        prescriptionDate.day == sessionDate.day;

    if (!isSameDay) {
      return SessionMatchResult(
        prescription: prescription,
        observedSession: session,
        confidence: MatchConfidence.noMatch,
        reasons: ['Aktivität fand an einem anderen Datum statt.'],
      );
    }
    reasons.add('Gleicher Trainingstag (${sessionDate.year}-${sessionDate.month}-${sessionDate.day}).');

    // 3. Modalität / Sportart prüfen
    final modalityMatches = _isModalityCompatible(prescription.modality, session.modality);
    if (!modalityMatches) {
      return SessionMatchResult(
        prescription: prescription,
        observedSession: session,
        confidence: MatchConfidence.noMatch,
        reasons: ['Sportart/Modalität passt nicht: Vorgabe war ${prescription.modality.label}, absolviert wurde ${session.modality.label}.'],
      );
    }
    reasons.add('Sportart ist kompatibel (${prescription.modality.label}).');

    // 4. Dauer prüfen (Toleranz: +/- 30 Minuten oder 35 %)
    final plannedMin = prescription.totalDurationMinutes;
    final actualMin = session.durationMinutes;
    final durationDiff = (actualMin - plannedMin).abs();
    final durationRatio = plannedMin > 0 ? actualMin / plannedMin : 1.0;

    final durationOk = durationDiff <= 30 || (durationRatio >= 0.65 && durationRatio <= 1.45);
    if (!durationOk) {
      reasons.add('Dauer weicht stark ab (geplant $plannedMin min, absolviert ${actualMin.round()} min).');
      return SessionMatchResult(
        prescription: prescription,
        observedSession: session,
        confidence: MatchConfidence.possibleMatch,
        reasons: reasons,
      );
    }
    reasons.add('Dauer liegt im plausiblen Bereich (${actualMin.round()} min von geplant $plannedMin min).');

    return SessionMatchResult(
      prescription: prescription,
      observedSession: session,
      confidence: MatchConfidence.exactMatch,
      reasons: reasons,
    );
  }

  bool _isModalityCompatible(XcModality prescribed, XcModality observed) {
    if (prescribed == observed) return true;

    // Ercolina-Varianten
    if (prescribed.isErcolina && observed.isErcolina) return true;

    // Ski-Varianten
    if (prescribed.isSnowSkiing && observed.isSnowSkiing) {
      // Wenn Skating vorgeschrieben war, aber generisches Langlauf geloggt wurde
      if (prescribed == XcModality.skiSkating && observed == XcModality.skiNordicUnknown) return true;
      if (prescribed == XcModality.skiClassic && observed == XcModality.skiNordicUnknown) return true;
      return false;
    }

    // Rollski
    if (prescribed.isRollerSkiing && observed.isRollerSkiing) return true;

    // Radsport
    if (prescribed == XcModality.cycling && observed == XcModality.cycling) return true;

    // Laufen
    if (prescribed == XcModality.running && observed == XcModality.running) return true;

    return false;
  }
}
