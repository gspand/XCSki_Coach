/// Was ein Workout vorgibt — und wie daraus eine Zahl für **diesen** Menschen
/// an **diesem** Tag wird.
///
/// ## Die Rangfolge
///
/// ```text
///   1. gültiges sportartspezifisches Zonenmodell   → 190–208 W
///   2. gültige sportartspezifische Schwelle        → 213–224 W
///   3. keine belastbare Grundlage                  → keine Zahl
/// ```
///
/// **Zonen zuerst**, weil ein Workout fachlich nicht sagt «fahre 92 % von
/// LTP2», sondern «fahre im oberen GA2». Wenn LaLa für diese Sportart bereits
/// ein Zonenmodell gerechnet hat, ist das die reichere Aussage: Es kennt die
/// Grenzen, ihre Herleitung und ihre Unsicherheit.
///
/// **Die dritte Stufe ist die wichtigste.** Liegt weder Zone noch Schwelle
/// vor, entsteht **keine** Zahl. Es wird nichts aus einem alten Wert
/// abgeleitet, nichts aus einer anderen Sportart übertragen, nichts geschätzt.
/// Die Einheit bleibt fahrbar, sie schreibt nur nichts vor — dieselbe Regel
/// wie in der Trainingsbibliothek und aus demselben Grund: Eine erfundene
/// Wattzahl ist schlimmer als keine, weil man ihr folgt.
///
/// ## Warum jede Auflösung ihre Herkunft mitträgt
///
/// Weil ein Trainer in einem halben Jahr fragt: «Warum standen bei Anna am
/// 12. Oktober 238–250 W?» — und die Antwort lauten muss: «Aus dem
/// Rad-Zonenmodell vom 28.09.2026, LaLa 2.1». Kommt im November eine neue
/// Schwelle, bleiben die alten Einheiten historisch richtig, weil in ihnen
/// steht, worauf sie beruhten.
library;

import '../domain/platform.dart';

/// Wo innerhalb einer Zone gearbeitet wird.
///
/// Die Aufteilung ist eine Festlegung, keine Messung: die untere und obere
/// Hälfte, das mittlere Drittel. Sie steht hier an einer Stelle, damit «oberes
/// GA2» überall dasselbe heisst.
enum ZonePosition {
  whole,
  lower,
  middle,
  upper;

  /// Der Ausschnitt aus [lower]…[upper].
  (double, double) narrow(double lower, double upper) {
    final span = upper - lower;
    return switch (this) {
      ZonePosition.whole => (lower, upper),
      ZonePosition.lower => (lower, lower + span / 2),
      ZonePosition.upper => (lower + span / 2, upper),
      ZonePosition.middle => (lower + span / 3, upper - span / 3),
    };
  }
}

/// Die Vorgabe eines Workoutschritts.
sealed class TrainingTarget {
  const TrainingTarget();
}

/// «Oberes GA2 im Fünfzonenmodell» — der fachlich richtige Weg.
class ZoneTarget extends TrainingTarget {
  const ZoneTarget(
    this.zoneCode, {
    required this.modelId,
    this.position = ZonePosition.whole,
    this.fallback,
  });

  /// Die Kennung der Zone, etwa `GA2` oder `Z3`.
  final String zoneCode;

  /// In welchem Zonenmodell.
  ///
  /// **Pflicht, und das ist die wichtigste Festlegung dieser Datei.** LaLa
  /// rechnet zu einem Test mehrere Modelle nebeneinander — dreizonig,
  /// fünfzonig, siebenzonig, schwellenverankert. `Z1` bedeutet in jedem davon
  /// etwas anderes. Ein Workout, das nur «Z1» sagt, ist nicht ungenau, es ist
  /// unbestimmt; und die Software darf sich nicht eines aussuchen.
  final String modelId;

  final ZonePosition position;

  /// Was gilt, wenn für diesen Athleten und diese Sportart kein Zonenmodell
  /// vorliegt.
  ///
  /// Optional, und bewusst vom Autor des Workouts zu entscheiden: Ein
  /// Prozentband ist Trainingslehre, kein Messwert. Wer keines angibt, bekommt
  /// lieber keine Vorgabe als eine hergeleitete.
  final RelativeThresholdTarget? fallback;
}

/// «95–100 % der zweiten Schwelle» — die Rückfallebene.
class RelativeThresholdTarget extends TrainingTarget {
  const RelativeThresholdTarget({
    required this.threshold,
    required this.minPercent,
    required this.maxPercent,
  }) : assert(minPercent <= maxPercent);

  final ThresholdType threshold;

  /// Anteile, nicht Prozentzahlen: 0,95 und 1,05.
  final double minPercent;
  final double maxPercent;
}

// ------------------------------------------------------------- die Fakten

/// Eine Zone, wie sie gespeichert ist.
class ZoneFact {
  const ZoneFact({
    required this.code,
    required this.name,
    this.lowerLoad,
    this.upperLoad,
    this.lowerHeartRateBpm,
    this.upperHeartRateBpm,
    this.provisional = false,
  });

  final String code;
  final String name;
  final double? lowerLoad;
  final double? upperLoad;
  final int? lowerHeartRateBpm;
  final int? upperHeartRateBpm;

  /// Ob eine Grenze dieser Zone geschätzt und nicht gemessen ist.
  final bool provisional;
}

/// Ein Zonenmodell für eine Sportart, gültig ab einem Zeitpunkt.
class ZoneSetFact {
  const ZoneSetFact({
    required this.id,
    required this.modelId,
    required this.sport,
    required this.effectiveFromUtcUs,
    required this.loadUnit,
    required this.zones,
    this.modelName,
    this.engineVersion,
    this.quality,
  });

  final String id;

  /// Welches Zonenmodell — `standard-five-zone`, `domain-three-zone`, …
  final String modelId;
  final String? modelName;

  final String sport;
  final int effectiveFromUtcUs;
  final String loadUnit;
  final List<ZoneFact> zones;
  final String? engineVersion;

  /// Der Qualitätsvermerk der Auswertung, unverändert übernommen.
  final String? quality;

  ZoneFact? zone(String code) {
    for (final zone in zones) {
      if (zone.code.toUpperCase() == code.toUpperCase()) return zone;
    }
    return null;
  }
}

/// Eine Schwelle für eine Sportart, gültig ab einem Zeitpunkt.
class ThresholdFact {
  const ThresholdFact({
    required this.id,
    required this.type,
    required this.sport,
    required this.loadValue,
    required this.loadUnit,
    required this.effectiveAtUtcUs,
    this.engineVersion,
    this.isSelectedStandard = false,
  });

  final String id;
  final ThresholdType type;
  final String sport;
  final double loadValue;
  final String loadUnit;
  final int effectiveAtUtcUs;
  final String? engineVersion;

  /// Ob es die vom Verfahren als Standard gewählte Bestimmung ist.
  final bool isSelectedStandard;
}

// ---------------------------------------------------------- das Ergebnis

/// Woher die Zahlen kommen.
enum TargetSource {
  zoneSet,
  threshold,

  /// Von Hand gesetzt — kommt aus einem Workout mit absoluter Vorgabe.
  manual,

  /// Keine belastbare Grundlage. Kein Fehler, ein Zustand.
  none,
}

enum TargetQuality {
  /// Beruht auf gemessenen Grenzen.
  measured,

  /// Mindestens eine benutzte Grenze ist geschätzt.
  provisional,

  /// Bewusst vom Trainer in Watt festgelegt, keine Diagnostik.
  userDefined,

  /// Es gibt keine Vorgabe.
  unavailable,
}

/// Eine aufgelöste Vorgabe, mit ihrer Herkunft.
class ResolvedTrainingTarget {
  const ResolvedTrainingTarget({
    required this.source,
    required this.quality,
    required this.validAtUtcUs,
    this.sourceId,
    this.algorithmVersion,
    this.resolvedMin,
    this.resolvedMax,
    this.unit,
    this.heartRateMin,
    this.heartRateMax,
    this.reason,
  });

  /// Der Zustand «keine Grundlage», mit dem Grund im Klartext.
  const ResolvedTrainingTarget.unavailable({
    required this.validAtUtcUs,
    required this.reason,
  }) : source = TargetSource.none,
       quality = TargetQuality.unavailable,
       sourceId = null,
       algorithmVersion = null,
       resolvedMin = null,
       resolvedMax = null,
       unit = null,
       heartRateMin = null,
       heartRateMax = null;

  final TargetSource source;
  final TargetQuality quality;

  /// Der Zeitpunkt, für den aufgelöst wurde — nicht der der Grundlage.
  final int validAtUtcUs;

  /// Das Zonenmodell oder die Schwelle, auf der das beruht.
  final String? sourceId;
  final String? algorithmVersion;

  final double? resolvedMin;
  final double? resolvedMax;
  final String? unit;

  final int? heartRateMin;
  final int? heartRateMax;

  /// Warum keine Zahl entstand. Nur bei [TargetSource.none] gesetzt.
  final String? reason;

  bool get hasRange => resolvedMin != null && resolvedMax != null;
  bool get hasHeartRateRange => heartRateMin != null && heartRateMax != null;
}

// -------------------------------------------------------- die Auflösung

/// Löst eine Vorgabe für einen Athleten, eine Sportart und einen Zeitpunkt auf.
///
/// Deterministisch: Bei gleicher Eingabe dasselbe Ergebnis. Wo mehrere
/// Grundlagen infrage kommen, entscheidet der Gültigkeitszeitpunkt und bei
/// Gleichstand die Kennung — nie die Reihenfolge, in der jemand die Zeilen
/// gelesen hat.
ResolvedTrainingTarget resolveTrainingTarget({
  required TrainingTarget target,
  required String sport,
  required int atUtcUs,
  Iterable<ZoneSetFact> zoneSets = const [],
  Iterable<ThresholdFact> thresholds = const [],
}) {
  switch (target) {
    case ZoneTarget():
      final resolved = _fromZone(target, sport, atUtcUs, zoneSets);
      if (resolved != null) return resolved;
      final fallback = target.fallback;
      if (fallback == null) {
        return ResolvedTrainingTarget.unavailable(
          validAtUtcUs: atUtcUs,
          reason:
              'Für $sport liegt kein Zonenmodell «${target.modelId}» mit der '
              'Zone ${target.zoneCode} vor.',
        );
      }
      return _fromThreshold(fallback, sport, atUtcUs, thresholds);

    case RelativeThresholdTarget():
      return _fromThreshold(target, sport, atUtcUs, thresholds);
  }
}

ResolvedTrainingTarget? _fromZone(
  ZoneTarget target,
  String sport,
  int atUtcUs,
  Iterable<ZoneSetFact> zoneSets,
) {
  final set = _newest<ZoneSetFact>(
    zoneSets.where(
      (candidate) =>
          candidate.modelId == target.modelId &&
          _sameSport(candidate.sport, sport) &&
          candidate.effectiveFromUtcUs <= atUtcUs &&
          candidate.zone(target.zoneCode) != null,
    ),
    at: (candidate) => candidate.effectiveFromUtcUs,
    id: (candidate) => candidate.id,
  );
  if (set == null) return null;

  final zone = set.zone(target.zoneCode)!;
  final lower = zone.lowerLoad;
  final upper = zone.upperLoad;
  if (lower == null || upper == null) return null;

  final (min, max) = target.position.narrow(lower, upper);
  final (hrMin, hrMax) = _heartRate(zone, target.position);

  return ResolvedTrainingTarget(
    source: TargetSource.zoneSet,
    quality: zone.provisional
        ? TargetQuality.provisional
        : TargetQuality.measured,
    validAtUtcUs: atUtcUs,
    sourceId: set.id,
    algorithmVersion: set.engineVersion,
    resolvedMin: min,
    resolvedMax: max,
    unit: set.loadUnit,
    heartRateMin: hrMin,
    heartRateMax: hrMax,
  );
}

(int?, int?) _heartRate(ZoneFact zone, ZonePosition position) {
  final lower = zone.lowerHeartRateBpm;
  final upper = zone.upperHeartRateBpm;
  if (lower == null || upper == null) return (null, null);
  final (min, max) = position.narrow(lower.toDouble(), upper.toDouble());
  return (min.round(), max.round());
}

ResolvedTrainingTarget _fromThreshold(
  RelativeThresholdTarget target,
  String sport,
  int atUtcUs,
  Iterable<ThresholdFact> thresholds,
) {
  final candidates = thresholds.where(
    (candidate) =>
        candidate.type == target.threshold &&
        _sameSport(candidate.sport, sport) &&
        candidate.effectiveAtUtcUs <= atUtcUs,
  );
  // Die vom Verfahren als Standard gewählte Bestimmung geht vor — sonst
  // entschiede der Zufall zwischen zwei Methoden desselben Tests.
  final standard = candidates.where(
    (candidate) => candidate.isSelectedStandard,
  );
  final threshold = _newest<ThresholdFact>(
    standard.isEmpty ? candidates : standard,
    at: (candidate) => candidate.effectiveAtUtcUs,
    id: (candidate) => candidate.id,
  );

  if (threshold == null) {
    return ResolvedTrainingTarget.unavailable(
      validAtUtcUs: atUtcUs,
      reason:
          'Für $sport liegt keine ${target.threshold.name.toUpperCase()} vor.',
    );
  }

  return ResolvedTrainingTarget(
    source: TargetSource.threshold,
    quality: TargetQuality.measured,
    validAtUtcUs: atUtcUs,
    sourceId: threshold.id,
    algorithmVersion: threshold.engineVersion,
    resolvedMin: threshold.loadValue * target.minPercent,
    resolvedMax: threshold.loadValue * target.maxPercent,
    unit: threshold.loadUnit,
  );
}

/// Sportarten werden nie ineinander übersetzt.
///
/// Eine Radschwelle sagt über das Laufen nichts, und der Versuch, sie
/// umzurechnen, ist der klassische Weg zu einer Zahl, die niemand mehr
/// hinterfragt.
bool _sameSport(String a, String b) => a.toLowerCase() == b.toLowerCase();

T? _newest<T>(
  Iterable<T> candidates, {
  required int Function(T) at,
  required String Function(T) id,
}) {
  T? best;
  for (final candidate in candidates) {
    if (best == null ||
        at(candidate) > at(best) ||
        (at(candidate) == at(best) && id(candidate).compareTo(id(best)) > 0)) {
      best = candidate;
    }
  }
  return best;
}
