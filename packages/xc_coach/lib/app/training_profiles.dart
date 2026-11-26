/// Trainingsprofile: wer trainiert, was er während der Einheit sieht und
/// woran sich die Wattziele seiner Einheiten messen.
///
/// Ein Profil ist ein Athlet dieses Arbeitsbereichs. Seine Einheiten gehören
/// ihm, seine Ansicht und seine Schwelle liegen unter seiner Id im
/// Anwendungszustand.
///
/// ## Wie sich die Einheiten anpassen
///
/// Nach jeder Einheit wird aus den Zügen der letzten sechs Wochen die beste
/// Dauerleistung bestimmt: 95 % der besten 20 Minuten oder 90 % der besten
/// 8 Minuten, je nachdem, was höher ist. Liegt sie über der eingetragenen
/// oder diagnostizierten Schwelle, rechnen die Einheiten ab dann damit.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../core/models.dart';
import '../database/platform_repository.dart';
import '../database/session_repository.dart';
import '../domain/platform.dart';

/// Welches Profil gerade trainiert.
const String activeProfileStateKey = 'training.active_athlete';

String profileLayoutStateKey(String athleteId) =>
    'profile.$athleteId.live_layout';

String profileReferenceStateKey(String athleteId) =>
    'profile.$athleteId.reference_w';

String profileEstimateStateKey(String athleteId) =>
    'profile.$athleteId.estimate';

/// Ab hier rechnet die Firmware mit gemessenem Trägheitsmoment und
/// Rückholseil (0.22.29). Frühere Watt sind rund 2,7-mal zu hoch und nicht
/// vergleichbar. Ändert sich das Leistungsmodell wieder, wandert diese Grenze.
const int comparablePowerSinceUtcUs = 1790784000000000; // 2026-09-30 16:00 UTC

/// Die beste Dauerleistung einer Einheit und was daraus als Schwelle folgt.
class PerformanceEstimate {
  const PerformanceEstimate({
    required this.watt,
    required this.bestWatt,
    required this.window,
    required this.sessionId,
    required this.sessionStartedAtUtcUs,
  });

  /// Die daraus abgeleitete Schwelle.
  final double watt;

  /// Die gemessene mittlere Leistung im besten Fenster.
  final double bestWatt;
  final Duration window;
  final String sessionId;
  final int sessionStartedAtUtcUs;

  String get label => 'beste ${window.inMinutes} min: ${bestWatt.round()} W';

  String encode() => jsonEncode(<String, Object?>{
    'watt': watt,
    'best_w': bestWatt,
    'window_s': window.inSeconds,
    'session': sessionId,
    'started_us': sessionStartedAtUtcUs,
  });

  static PerformanceEstimate? decode(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    try {
      final json = jsonDecode(stored) as Map<String, Object?>;
      return PerformanceEstimate(
        watt: (json['watt']! as num).toDouble(),
        bestWatt: (json['best_w']! as num).toDouble(),
        window: Duration(seconds: (json['window_s']! as num).toInt()),
        sessionId: json['session']! as String,
        sessionStartedAtUtcUs: (json['started_us']! as num).toInt(),
      );
    } on Object {
      return null;
    }
  }
}

/// Fenster und Anteil, der davon als Schwelle gilt.
const List<(Duration, double)> estimateWindows = [
  (Duration(minutes: 20), 0.95),
  (Duration(minutes: 8), 0.90),
];

/// Die höchste mittlere Leistung über [window], aus der Arbeit der Züge.
///
/// Null, wenn die Einheit kürzer ist als das Fenster. Pausen im Fenster zählen
/// mit, dadurch wird der Wert eher zu niedrig als zu hoch.
double? bestMeanPower(List<Stroke> strokes, Duration window) {
  if (strokes.isEmpty) return null;
  final sorted = [
    for (final stroke in strokes)
      if (stroke.workJoule.isFinite && stroke.workJoule >= 0) stroke,
  ]..sort((a, b) => a.startUs.compareTo(b.startUs));
  if (sorted.isEmpty) return null;
  final windowUs = window.inMicroseconds;
  final lastEndUs = sorted.map((s) => s.endUs).reduce(math.max);
  double? best;
  var end = 0;
  var work = 0.0;
  for (var start = 0; start < sorted.length; start++) {
    final windowEndUs = sorted[start].startUs + windowUs;
    if (windowEndUs > lastEndUs) break;
    while (end < sorted.length && sorted[end].startUs < windowEndUs) {
      work += sorted[end].workJoule;
      end++;
    }
    final power = work / (windowUs / Duration.microsecondsPerSecond);
    if (best == null || power > best) best = power;
    work -= sorted[start].workJoule;
  }
  return best;
}

/// Die Schwelle, die eine einzelne Einheit belegt.
PerformanceEstimate? estimateFromSession({
  required String sessionId,
  required int startedAtUtcUs,
  required List<Stroke> strokes,
}) {
  PerformanceEstimate? best;
  for (final (window, share) in estimateWindows) {
    final power = bestMeanPower(strokes, window);
    if (power == null || power <= 0) continue;
    final watt = power * share;
    if (best == null || watt > best.watt) {
      best = PerformanceEstimate(
        watt: watt,
        bestWatt: power,
        window: window,
        sessionId: sessionId,
        sessionStartedAtUtcUs: startedAtUtcUs,
      );
    }
  }
  return best;
}

/// Liest und schreibt alles, was an einem Profil hängt.
class TrainingProfiles {
  const TrainingProfiles({required this.platform, required this.sessions});

  final PlatformRepository platform;
  final SessionRepository sessions;

  /// Wie weit zurück Einheiten die Schwelle belegen.
  static const Duration lookback = Duration(days: 42);

  /// Das aktive Profil. Ohne gültige Wahl das erste sichtbare.
  String? activeId(List<AthleteSummary> athletes) {
    final stored = platform.appState(activeProfileStateKey);
    for (final athlete in athletes) {
      if (athlete.id == stored) return athlete.id;
    }
    return athletes.isEmpty ? null : athletes.first.id;
  }

  void activate(String athleteId, {required int nowUtcUs}) =>
      platform.setAppState(
        key: activeProfileStateKey,
        value: athleteId,
        nowUtcUs: nowUtcUs,
      );

  /// Übernimmt Ansicht und Schwelle, die vor den Profilen für die ganze
  /// Installation galten, einmal in das Profil [athleteId].
  void adoptInstallationSettings({
    required String athleteId,
    required String layoutKey,
    required String referenceKey,
    required int nowUtcUs,
  }) {
    for (final (global, own) in [
      (layoutKey, profileLayoutStateKey(athleteId)),
      (referenceKey, profileReferenceStateKey(athleteId)),
    ]) {
      final value = platform.appState(global);
      if (value == null) continue;
      if (platform.appState(own) == null) {
        platform.setAppState(key: own, value: value, nowUtcUs: nowUtcUs);
      }
      platform.clearAppState(global);
    }
  }

  String? layoutOf(String athleteId) =>
      platform.appState(profileLayoutStateKey(athleteId));

  void saveLayout(String athleteId, String encoded, {required int nowUtcUs}) =>
      platform.setAppState(
        key: profileLayoutStateKey(athleteId),
        value: encoded,
        nowUtcUs: nowUtcUs,
      );

  double? referenceOf(String athleteId) {
    final value = double.tryParse(
      platform.appState(profileReferenceStateKey(athleteId)) ?? '',
    );
    return value != null && value > 0 ? value : null;
  }

  void setReference(String athleteId, double? watt, {required int nowUtcUs}) {
    if (watt == null || watt <= 0) {
      platform.clearAppState(profileReferenceStateKey(athleteId));
      return;
    }
    platform.setAppState(
      key: profileReferenceStateKey(athleteId),
      value: watt.round().toString(),
      nowUtcUs: nowUtcUs,
    );
  }

  PerformanceEstimate? estimateOf(String athleteId) =>
      PerformanceEstimate.decode(
        platform.appState(profileEstimateStateKey(athleteId)),
      );

  /// Bestimmt die Schwelle aus den Einheiten neu und legt sie ab.
  PerformanceEstimate? refreshEstimate(
    String athleteId, {
    required int nowUtcUs,
  }) {
    final since = math.max(
      comparablePowerSinceUtcUs,
      nowUtcUs - lookback.inMicroseconds,
    );
    PerformanceEstimate? best;
    for (final session in sessions.sessionsOfAthlete(athleteId)) {
      if (session.startedAtUtcUs < since) continue;
      final estimate = estimateFromSession(
        sessionId: session.id,
        startedAtUtcUs: session.startedAtUtcUs,
        strokes: sessions.loadStrokes(session.id),
      );
      if (estimate != null && (best == null || estimate.watt > best.watt)) {
        best = estimate;
      }
    }
    final key = profileEstimateStateKey(athleteId);
    if (best == null) {
      platform.clearAppState(key);
    } else {
      platform.setAppState(key: key, value: best.encode(), nowUtcUs: nowUtcUs);
    }
    return best;
  }

  /// Legt ein neues Profil an und gibt seine Id zurück.
  String create({
    required String organizationId,
    required String name,
    required int nowUtcUs,
    double? bodyMassKg,
    int? maxHeartRateBpm,
    int? restingHeartRateBpm,
    String? recordedByUserId,
  }) {
    final id = 'athlete-$nowUtcUs';
    platform.createAthlete(
      id: id,
      organizationId: organizationId,
      name: name.trim(),
      nowUtcUs: nowUtcUs,
    );
    if (bodyMassKg != null) {
      setBodyMass(
        id,
        bodyMassKg,
        nowUtcUs: nowUtcUs,
        recordedByUserId: recordedByUserId,
      );
    }
    if (maxHeartRateBpm != null) {
      setMaxHeartRate(
        id,
        maxHeartRateBpm,
        nowUtcUs: nowUtcUs,
        recordedByUserId: recordedByUserId,
      );
    }
    if (restingHeartRateBpm != null) {
      setRestingHeartRate(
        id,
        restingHeartRateBpm,
        nowUtcUs: nowUtcUs,
        recordedByUserId: recordedByUserId,
      );
    }
    return id;
  }

  double? bodyMassOf(String athleteId, {required int nowUtcUs}) =>
      platform.attributeAt(
        athleteId: athleteId,
        attribute: AthleteAttribute.bodyMassKg,
        asOfUtcUs: nowUtcUs,
      );

  void setBodyMass(
    String athleteId,
    double kilograms, {
    required int nowUtcUs,
    String? recordedByUserId,
  }) => platform.recordAttribute(
    id: '$athleteId-mass-$nowUtcUs',
    athleteId: athleteId,
    attribute: AthleteAttribute.bodyMassKg,
    value: kilograms,
    unit: 'kg',
    effectiveFromUtcUs: nowUtcUs,
    recordedAtUtcUs: nowUtcUs,
    recordedByUserId: recordedByUserId,
  );

  int? maxHeartRateOf(String athleteId, {required int nowUtcUs}) => platform
      .attributeAt(
        athleteId: athleteId,
        attribute: AthleteAttribute.maxHeartRateBpm,
        asOfUtcUs: nowUtcUs,
      )
      ?.round();

  void setMaxHeartRate(
    String athleteId,
    int beatsPerMinute, {
    required int nowUtcUs,
    String? recordedByUserId,
  }) => platform.recordAttribute(
    id: '$athleteId-max-hr-$nowUtcUs',
    athleteId: athleteId,
    attribute: AthleteAttribute.maxHeartRateBpm,
    value: beatsPerMinute.toDouble(),
    unit: 'bpm',
    effectiveFromUtcUs: nowUtcUs,
    recordedAtUtcUs: nowUtcUs,
    recordedByUserId: recordedByUserId,
  );

  int? restingHeartRateOf(String athleteId, {required int nowUtcUs}) => platform
      .attributeAt(
        athleteId: athleteId,
        attribute: AthleteAttribute.restingHeartRateBpm,
        asOfUtcUs: nowUtcUs,
      )
      ?.round();

  void setRestingHeartRate(
    String athleteId,
    int beatsPerMinute, {
    required int nowUtcUs,
    String? recordedByUserId,
  }) => platform.recordAttribute(
    id: '$athleteId-resting-hr-$nowUtcUs',
    athleteId: athleteId,
    attribute: AthleteAttribute.restingHeartRateBpm,
    value: beatsPerMinute.toDouble(),
    unit: 'bpm',
    effectiveFromUtcUs: nowUtcUs,
    recordedAtUtcUs: nowUtcUs,
    recordedByUserId: recordedByUserId,
  );
}
