/// Sportwissenschaftliche Machbarkeitsprüfung von Athletenzielen (Goal Feasibility Engine).
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Beurteilt, ob ein eingegebenes Leistungsziel (Distanz in km und Zielzeit)
///   in Relation zur physiologischen Leistungsdiagnostik und biologischen Grenzen realistisch ist.
/// - Verhindert unrealistische Zielsetzungen (z. B. Marathon in 2:15:00 = 3:12 min/km bzw. 18,75 km/h,
///   was Weltklasse-Niveau mit VO2max > 75–80 ml/kg/min und LT2 > 19 km/h entspricht).
/// - Differenziert nach Sportart/Modalität:
///   * Laufen (Running)
///   * Skilanglauf Skating / Klassisch
///   * Radfahren (Cycling)
///   * Ercolina / Doppelstock
/// - Keine falschen Hoffnungen: Klare, respektvolle, aber unmissverständliche physiologische Rückmeldung.
library;

import '../../intelligence/planning/planning_models.dart';
import '../xc_athlete_state/diagnostics_state.dart';

enum FeasibilityStatus {
  realistic('Realistisch'),
  ambitious('Ambitioniert · Hohe Trainingsdisziplin erforderlich'),
  unrealistic('Sehr unrealistisch · Hohes Überlastungsrisiko'),
  infeasible('Physiologisch nicht erreichbar');

  const FeasibilityStatus(this.label);
  final String label;

  bool get isIssue => this == FeasibilityStatus.unrealistic || this == FeasibilityStatus.infeasible;
}

class GoalFeasibilityVerdict {
  const GoalFeasibilityVerdict({
    required this.status,
    required this.targetSpeedKmh,
    this.targetPaceMinPerKm,
    this.thresholdSpeedKmh,
    this.thresholdPaceMinPerKm,
    this.thresholdWatt,
    required this.headline,
    required this.reasoning,
    required this.isEliteRequirement,
  });

  final FeasibilityStatus status;
  final double targetSpeedKmh;
  final String? targetPaceMinPerKm;
  final double? thresholdSpeedKmh;
  final String? thresholdPaceMinPerKm;
  final double? thresholdWatt;
  final String headline;
  final String reasoning;
  final bool isEliteRequirement;

  bool get isAchievable => status == FeasibilityStatus.realistic || status == FeasibilityStatus.ambitious;
  bool get isIssue => status.isIssue;
}

class GoalFeasibilityEngine {
  const GoalFeasibilityEngine();

  GoalFeasibilityVerdict evaluateGoal({
    required TrainingGoal goal,
    DiagnosticsState? diagnostics,
    DateTime? now,
  }) {
    if (goal.distanceKm == null || goal.targetSeconds == null) {
      return const GoalFeasibilityVerdict(
        status: FeasibilityStatus.realistic,
        targetSpeedKmh: 0,
        headline: 'Ziel erfasst',
        reasoning: 'Gültige Distanz und Zeit erforderlich.',
        isEliteRequirement: false,
      );
    }
    return evaluate(
      modality: goal.modality,
      distanceKm: goal.distanceKm!,
      targetSeconds: goal.targetSeconds!,
      diagnostics: diagnostics,
    );
  }

  GoalFeasibilityVerdict evaluate({
    required TrainingModality modality,
    required double distanceKm,
    required int targetSeconds,
    DiagnosticsState? diagnostics,
  }) {
    if (distanceKm <= 0 || targetSeconds <= 0) {
      return const GoalFeasibilityVerdict(
        status: FeasibilityStatus.realistic,
        targetSpeedKmh: 0,
        headline: 'Ziel erfasst',
        reasoning: 'Gültige Distanz und Zeit erforderlich.',
        isEliteRequirement: false,
      );
    }

    final durationHours = targetSeconds / 3600.0;
    final speedKmh = distanceKm / durationHours;
    final paceSecPerKm = targetSeconds / distanceKm;
    final paceMinStr = _formatPace(paceSecPerKm);

    switch (modality) {
      case TrainingModality.running:
        return _evaluateRunning(
          distanceKm: distanceKm,
          targetSeconds: targetSeconds,
          speedKmh: speedKmh,
          paceSecPerKm: paceSecPerKm,
          paceMinStr: paceMinStr,
          diagnostics: diagnostics,
        );

      case TrainingModality.skiSkating:
      case TrainingModality.skiClassic:
        return _evaluateSkiing(
          distanceKm: distanceKm,
          targetSeconds: targetSeconds,
          speedKmh: speedKmh,
          modality: modality,
          diagnostics: diagnostics,
        );

      case TrainingModality.bikeIndoor:
      case TrainingModality.bikeOutdoor:
        return _evaluateCycling(
          distanceKm: distanceKm,
          targetSeconds: targetSeconds,
          speedKmh: speedKmh,
          diagnostics: diagnostics,
        );

      case TrainingModality.ercolina:
        return _evaluateErcolina(
          distanceKm: distanceKm,
          targetSeconds: targetSeconds,
          speedKmh: speedKmh,
          diagnostics: diagnostics,
        );
    }
  }

  // --- LAUFEN EVALUATION ---
  GoalFeasibilityVerdict _evaluateRunning({
    required double distanceKm,
    required int targetSeconds,
    required double speedKmh,
    required double paceSecPerKm,
    required String paceMinStr,
    DiagnosticsState? diagnostics,
  }) {
    // 1. Absolute Weltklasse-/Elite-Grenzen (z. B. Marathon < 2:20 h oder 10 km < 31 min)
    // 2:15 Marathon = 18.75 km/h = 3:12 min/km
    final isWorldClassMarathon = distanceKm >= 40.0 && targetSeconds <= (2 * 3600 + 20 * 60); // < 2:20:00
    final isWorldClassHalf = distanceKm >= 20.0 && distanceKm < 40.0 && targetSeconds <= (66 * 60); // < 1:06:00
    final isWorldClass10k = distanceKm >= 9.0 && distanceKm < 15.0 && targetSeconds <= (31 * 60); // < 31:00

    // Diagnostische Referenz suchen
    final runRef = diagnostics?.running;
    final lt2PaceSec = runRef?.lt2Ltp2PaceSecPerKm;
    final lt2Watt = runRef?.lt2Ltp2Watt;

    // Wenn diagnostische LT2-Pace vorliegt:
    if (lt2PaceSec != null && lt2PaceSec > 0) {
      final lt2SpeedKmh = 3600.0 / lt2PaceSec;
      final lt2PaceStr = _formatPace(lt2PaceSec);

      // Marathon kann physiologisch maximal bei ca. 88-90% der LT2 gelaufen werden.
      // Erforderliche LT2-Geschwindigkeit für diese Zielzeit:
      final marathonFactor = distanceKm >= 40.0 ? 0.90 : (distanceKm >= 20.0 ? 0.94 : 1.0);
      final maxSustainableSpeed = lt2SpeedKmh * marathonFactor;

      if (speedKmh > lt2SpeedKmh * 1.05) {
        // Zielpace liegt DEUTLICH über der anaeroben Schwelle
        return GoalFeasibilityVerdict(
          status: FeasibilityStatus.infeasible,
          targetSpeedKmh: speedKmh,
          targetPaceMinPerKm: paceMinStr,
          thresholdSpeedKmh: lt2SpeedKmh,
          thresholdPaceMinPerKm: lt2PaceStr,
          isEliteRequirement: speedKmh >= 18.0,
          headline: 'Physiologisch nicht erreichbar',
          reasoning: 'Zielzeit erfordert ein Durchschnittstempo von $paceMinStr min/km (${speedKmh.toStringAsFixed(1)} km/h). '
              'Deine gemessene anaerobe Schwelle (LTP2) liegt bei $lt2PaceStr min/km (${lt2SpeedKmh.toStringAsFixed(1)} km/h). '
              'Über ${distanceKm.toStringAsFixed(0)} km ist ein Tempo oberhalb deiner anaeroben Schwelle biologisch unmöglich.',
        );
      } else if (speedKmh > maxSustainableSpeed) {
        return GoalFeasibilityVerdict(
          status: FeasibilityStatus.unrealistic,
          targetSpeedKmh: speedKmh,
          targetPaceMinPerKm: paceMinStr,
          thresholdSpeedKmh: lt2SpeedKmh,
          thresholdPaceMinPerKm: lt2PaceStr,
          isEliteRequirement: speedKmh >= 18.0,
          headline: 'Sehr unrealistisch für aktuellen Trainingsstand',
          reasoning: 'Zielzeit verlangt $paceMinStr min/km (${speedKmh.toStringAsFixed(1)} km/h). '
              'Mit deiner aktuellen LTP2 von $lt2PaceStr min/km liegt diese Renngeschwindigkeit über der maximal haltbaren Dauerleistung für diese Distanz.',
        );
      } else if (speedKmh > maxSustainableSpeed * 0.95) {
        return GoalFeasibilityVerdict(
          status: FeasibilityStatus.ambitious,
          targetSpeedKmh: speedKmh,
          targetPaceMinPerKm: paceMinStr,
          thresholdSpeedKmh: lt2SpeedKmh,
          thresholdPaceMinPerKm: lt2PaceStr,
          isEliteRequirement: false,
          headline: 'Ambitioniertes Ziel',
          reasoning: 'Zielpace $paceMinStr min/km liegt nah an deiner anaeroben Schwelle ($lt2PaceStr min/km). '
              'Erfordert fokussierten Schwellenaufbau und hohe Durability.',
        );
      } else {
        return GoalFeasibilityVerdict(
          status: FeasibilityStatus.realistic,
          targetSpeedKmh: speedKmh,
          targetPaceMinPerKm: paceMinStr,
          thresholdSpeedKmh: lt2SpeedKmh,
          thresholdPaceMinPerKm: lt2PaceStr,
          isEliteRequirement: false,
          headline: 'Realistisches Leistungsziel',
          reasoning: 'Zielpace $paceMinStr min/km liegt im physiologisch gut trainierbaren Dauerleistungsbereich relativ zu deiner Schwelle ($lt2PaceStr min/km).',
        );
      }
    }

    // Wenn KEINE Laufdiagnostik vorliegt -> Prüfung gegen physiologische Maximalwerte
    if (isWorldClassMarathon || isWorldClassHalf || isWorldClass10k || speedKmh >= 18.5) {
      return GoalFeasibilityVerdict(
        status: FeasibilityStatus.infeasible,
        targetSpeedKmh: speedKmh,
        targetPaceMinPerKm: paceMinStr,
        isEliteRequirement: true,
        headline: 'Physiologisch nicht erreichbar (Elite-Anforderung)',
        reasoning: 'Ein Marathon in ${_clock(targetSeconds)} erfordert ein Dauertempo von $paceMinStr min/km (${speedKmh.toStringAsFixed(1)} km/h). '
            'Dies entspricht internationalem Spitzen- und Profilaufniveau (VO2max > 78 ml/kg/min). '
            'Ohne nachgewiesenes Kader-/Elite-Leistungsniveau ist dieses Ziel physiologisch nicht realisierbar.',
      );
    } else if (speedKmh >= 16.5) { // 3:38 min/km
      return GoalFeasibilityVerdict(
        status: FeasibilityStatus.unrealistic,
        targetSpeedKmh: speedKmh,
        targetPaceMinPerKm: paceMinStr,
        isEliteRequirement: true,
        headline: 'Extrem ambitioniert / Sub-Elite Niveau',
        reasoning: 'Tempo von $paceMinStr min/km (${speedKmh.toStringAsFixed(1)} km/h) verlangt Sub-Elite-Leistungsfähigkeit. '
            'Ohne spezifische Leistungsdiagnostik kann GIULIA dieses Ziel nicht als realistisch einstufen.',
      );
    }

    return GoalFeasibilityVerdict(
      status: FeasibilityStatus.realistic,
      targetSpeedKmh: speedKmh,
      targetPaceMinPerKm: paceMinStr,
      isEliteRequirement: false,
      headline: 'Ziel erfasst',
      reasoning: 'Zielpace von $paceMinStr min/km (${speedKmh.toStringAsFixed(1)} km/h). '
          'Absolviere einen Diagnostik-Test, um deine Schwellen und Renntaktik exakt abzugleichen.',
    );
  }

  // --- SKILANGLAUF EVALUATION ---
  GoalFeasibilityVerdict _evaluateSkiing({
    required double distanceKm,
    required int targetSeconds,
    required double speedKmh,
    required TrainingModality modality,
    DiagnosticsState? diagnostics,
  }) {
    // 50 km Skating in < 1:50 h = > 27.2 km/h (Weltcup-/Engadin-Spitze bei schnellem Schnee)
    // 42 km Skating in < 1:30 h = 28 km/h
    final isWorldClassSki = (distanceKm >= 40.0 && speedKmh >= 28.0) || speedKmh >= 31.0;

    if (isWorldClassSki) {
      return GoalFeasibilityVerdict(
        status: FeasibilityStatus.infeasible,
        targetSpeedKmh: speedKmh,
        isEliteRequirement: true,
        headline: 'Physiologisch nicht erreichbar',
        reasoning: 'Eine Durchschnittsgeschwindigkeit von ${speedKmh.toStringAsFixed(1)} km/h über ${distanceKm.toStringAsFixed(0)} km '
            'entspricht Weltcup-Siegerzeiten bei schnellsten Eis-/Schneeverhältnissen. '
            'Für Breitensportler und Altersklassen-Athleten ist dies physiologisch ausgeschlossen.',
      );
    } else if (speedKmh >= 25.0 && distanceKm >= 30.0) {
      return GoalFeasibilityVerdict(
        status: FeasibilityStatus.unrealistic,
        targetSpeedKmh: speedKmh,
        isEliteRequirement: true,
        headline: 'Sehr unrealistisch / Spitzenkader-Niveau',
        reasoning: 'Ein Skimarathon-Schnitt von ${speedKmh.toStringAsFixed(1)} km/h verlangt exzellente Gleitbedingungen und Worldloppet-Elitegruppe.',
      );
    }

    return GoalFeasibilityVerdict(
      status: FeasibilityStatus.realistic,
      targetSpeedKmh: speedKmh,
      isEliteRequirement: false,
      headline: 'Realistisches Skilanglauf-Ziel',
      reasoning: 'Geplante Geschwindigkeit von ${speedKmh.toStringAsFixed(1)} km/h (${_clock(targetSeconds)} für ${distanceKm.toStringAsFixed(0)} km).',
    );
  }

  // --- RADFAHREN EVALUATION ---
  GoalFeasibilityVerdict _evaluateCycling({
    required double distanceKm,
    required int targetSeconds,
    required double speedKmh,
    DiagnosticsState? diagnostics,
  }) {
    if (speedKmh >= 46.0) {
      return GoalFeasibilityVerdict(
        status: FeasibilityStatus.infeasible,
        targetSpeedKmh: speedKmh,
        isEliteRequirement: true,
        headline: 'Physiologisch nicht erreichbar',
        reasoning: 'Ein Schnitt von ${speedKmh.toStringAsFixed(1)} km/h über ${distanceKm.toStringAsFixed(0)} km entspricht professionellem Zeitfahr-Weltklasseniveau.',
      );
    } else if (speedKmh >= 40.0 && distanceKm >= 60.0) {
      return GoalFeasibilityVerdict(
        status: FeasibilityStatus.unrealistic,
        targetSpeedKmh: speedKmh,
        isEliteRequirement: true,
        headline: 'Sehr unrealistisch ohne Profi-Peloton',
        reasoning: 'Ein Alleinfahrt-Schnitt von ${speedKmh.toStringAsFixed(1)} km/h erfordert über 350–400 Watt Dauerleistung.',
      );
    }

    return GoalFeasibilityVerdict(
      status: FeasibilityStatus.realistic,
      targetSpeedKmh: speedKmh,
      isEliteRequirement: false,
      headline: 'Realisierbares Rad-Ziel',
      reasoning: 'Zielgeschwindigkeit: ${speedKmh.toStringAsFixed(1)} km/h.',
    );
  }

  // --- ERCOLINA EVALUATION ---
  GoalFeasibilityVerdict _evaluateErcolina({
    required double distanceKm,
    required int targetSeconds,
    required double speedKmh,
    DiagnosticsState? diagnostics,
  }) {
    // Ercolina-Schwelle
    final ercoRef = diagnostics?.ercolina;
    final ercoWatt = ercoRef?.lt2Ltp2Watt;

    if (speedKmh >= 24.0) {
      return GoalFeasibilityVerdict(
        status: FeasibilityStatus.infeasible,
        targetSpeedKmh: speedKmh,
        thresholdWatt: ercoWatt,
        isEliteRequirement: true,
        headline: 'Physiologisch nicht erreichbar',
        reasoning: 'Ercolina-Geschwindigkeit von ${speedKmh.toStringAsFixed(1)} km/h erfordert kontinuierliche Zugleistungen jenseits von 280–320 W Oberkörperarbeit.',
      );
    }

    return GoalFeasibilityVerdict(
      status: FeasibilityStatus.realistic,
      targetSpeedKmh: speedKmh,
      thresholdWatt: ercoWatt,
      isEliteRequirement: false,
      headline: 'Ercolina-Ziel erfasst',
      reasoning: 'Geplante Geschwindigkeit: ${speedKmh.toStringAsFixed(1)} km/h.',
    );
  }

  static String _formatPace(double secPerKm) {
    final m = secPerKm ~/ 60;
    final s = (secPerKm % 60).round();
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static String _clock(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
