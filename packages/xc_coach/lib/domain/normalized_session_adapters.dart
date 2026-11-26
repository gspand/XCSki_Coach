/// Adapter zur Konvertierung von Rohdatenquellen in kanonische [NormalizedSession]s.
///
/// Unterstützt:
/// - First-Party Ercolina Einheiten ([SessionRecap])
/// - Strava API Aktivitäten ([StravaActivity])
/// - Garmin FIT / Externe Aktivitäten ([ExternalActivityImport])
///
/// Folgt strengen sportwissenschaftlichen und datenethischen Prinzipien:
/// 1. Keine automatische Klassifizierung von generischem NordicSki als Skating.
/// 2. Keine Erfindung von fehlenden Metriken (HR, Watt).
/// 3. Erhalt der Provenienz, Original-IDs und Messkonfidenz.
library;

import '../app/session_recap.dart';
import '../external_data/activity_import.dart';
import '../external_data/normalization/external_data.dart';
import '../external_data/strava/strava_activity.dart';
import 'normalized_session.dart';
import 'xc_modality.dart';

/// Evidenzbasierte Klassifikation von Sportart und Technik.
///
/// Verlässt sich ausschliesslich auf explizite Metadaten und Titel/Tags der Aktivität.
/// Das Trainingsziel (z. B. 50 km Skating) darf niemals Beobachtungsdaten umetikettieren.
class EvidenceBasedModalityClassifier {
  const EvidenceBasedModalityClassifier._();

  static ({
    XcModality modality,
    XcTechnique technique,
    ClassificationProvenance provenance,
  })
  classify({required String sport, required String title}) {
    final s = sport.trim().toLowerCase();
    final t = ' ${title.trim().toLowerCase()} ';

    // 1. Radsport
    if (s == 'ride' ||
        s == 'virtualride' ||
        s == 'gravelride' ||
        s == 'mountainbikeride' ||
        s == 'ebikeride' ||
        s.contains('cycl') ||
        s.contains('bike') ||
        s.contains('rad')) {
      return (
        modality: XcModality.cycling,
        technique: XcTechnique.unknown,
        provenance: ClassificationProvenance.explicitSourceMetadata,
      );
    }

    // 2. Laufen / Gehen
    if (s == 'run' ||
        s == 'trailrun' ||
        s.contains('running') ||
        (s.contains('lauf') && !s.contains('langlauf')) ||
        s == 'walk' ||
        s == 'hike') {
      return (
        modality: XcModality.running,
        technique: XcTechnique.unknown,
        provenance: ClassificationProvenance.explicitSourceMetadata,
      );
    }

    // 3. Krafttraining
    if (s == 'weighttraining' ||
        s == 'workout' ||
        s.contains('strength') ||
        s.contains('kraft')) {
      return (
        modality: XcModality.strength,
        technique: XcTechnique.unknown,
        provenance: ClassificationProvenance.explicitSourceMetadata,
      );
    }

    // 4. Langlauf / Skiroller / Ercolina
    final isRoller =
        s.contains('roller') ||
        t.contains('roller') ||
        t.contains('skiroller') ||
        t.contains('rollski');

    final isSnowSki =
        s == 'skate_skiing' || s == 'classic_cross_country_skiing' ||
        s.contains('nordicski') ||
        s.contains('crosscountryski') || s == 'langlauf' || s == 'cross_country_skiing' ||
        t.contains('langlauf') ||
        t.contains('loipe') ||
        t.contains('skating') ||
        t.contains('classic') ||
        t.contains('doppelstock');

    if (isRoller || isSnowSki) {
      // Technik-Evidenz aus Titel und Tags prüfen
      final hasDp =
          t.contains('doppelstock') ||
          t.contains('double pole') ||
          t.contains('doublepole') ||
          t.contains('doublepoling') ||
          RegExp(r'[\s_\-\.\/]dp[\s_\-\.\/]').hasMatch(t);

      final hasClassic =
          s == 'classic_cross_country_skiing' || t.contains('classic') ||
          t.contains('klassisch') ||
          t.contains('diagonal') ||
          t.contains('diagonalschritt');

      final hasSkating =
          s == 'skate_skiing' || s == 'nordicskiskating' || t.contains('skating') ||
          t.contains('skate') ||
          t.contains('skaten') ||
          t.contains('freie technik') ||
          t.contains('freistil') ||
          RegExp(r'[\s_\-\.\/](v1|v2|g2|g3|g4|g5)[\s_\-\.\/]').hasMatch(t);

      final technique = _resolveTechnique(
        titleText: t,
        hasDp: hasDp,
        hasClassic: hasClassic,
        hasSkating: hasSkating,
      );

      final provenance = s != 'skate_skiing' && s != 'classic_cross_country_skiing' && s != 'nordicskiskating' && (hasDp || hasClassic || hasSkating)
          ? ClassificationProvenance.titleInferred
          : ClassificationProvenance.explicitSourceMetadata;

      if (isRoller) {
        if (hasDp) {
          return (
            modality: XcModality.rollerSkiDoublePoling,
            technique: technique == XcTechnique.unknown
                ? XcTechnique.doublePoling
                : technique,
            provenance: provenance,
          );
        }
        if (hasSkating) {
          return (
            modality: XcModality.rollerSkiSkating,
            technique: technique,
            provenance: provenance,
          );
        }
        if (hasClassic) {
          return (
            modality: XcModality.rollerSkiClassic,
            technique: technique,
            provenance: provenance,
          );
        }
        return (
          modality: XcModality.rollerSkiUnknown,
          technique: XcTechnique.unknown,
          provenance: ClassificationProvenance.explicitSourceMetadata,
        );
      } else {
        if (hasDp) {
          return (
            modality: XcModality.doublePoling,
            technique: technique == XcTechnique.unknown
                ? XcTechnique.doublePoling
                : technique,
            provenance: provenance,
          );
        }
        if (hasSkating) {
          return (
            modality: XcModality.skiSkating,
            technique: technique,
            provenance: provenance,
          );
        }
        if (hasClassic) {
          return (
            modality: XcModality.skiClassic,
            technique: technique,
            provenance: provenance,
          );
        }
        // WICHTIG: Kein Raten! Ohne Beleg bleibt es skiNordicUnknown + unknown
        return (
          modality: XcModality.skiNordicUnknown,
          technique: XcTechnique.unknown,
          provenance: ClassificationProvenance.explicitSourceMetadata,
        );
      }
    }

    // 5. Unbekannte oder sonstige Sportart
    return (
      modality: XcModality.unknown,
      technique: XcTechnique.unknown,
      provenance: ClassificationProvenance.unknown,
    );
  }

  static XcTechnique _resolveTechnique({
    required String titleText,
    required bool hasDp,
    required bool hasClassic,
    required bool hasSkating,
  }) {
    if (hasDp) return XcTechnique.doublePoling;

    if (hasSkating) {
      if (RegExp(r'[\s_\-\.\/](g2|v1)[\s_\-\.\/]').hasMatch(titleText) ||
          titleText.contains('führarm') ||
          titleText.contains('berggang')) {
        return XcTechnique.skatingG2;
      }
      if (RegExp(r'[\s_\-\.\/](g3|v2)[\s_\-\.\/]').hasMatch(titleText) ||
          titleText.contains('eintakter') ||
          titleText.contains('1:1')) {
        return XcTechnique.skatingG3;
      }
      if (RegExp(r'[\s_\-\.\/](g4)[\s_\-\.\/]').hasMatch(titleText) ||
          titleText.contains('zweitakter') ||
          titleText.contains('2:1') ||
          titleText.contains('v2 alt')) {
        return XcTechnique.skatingG4;
      }
      if (RegExp(r'[\s_\-\.\/](g5)[\s_\-\.\/]').hasMatch(titleText) ||
          titleText.contains('schlittschuhschritt') ||
          titleText.contains('ohne stöcke')) {
        return XcTechnique.skatingG5;
      }
      return XcTechnique.unknown;
    }

    if (hasClassic) {
      if (titleText.contains('diagonal')) return XcTechnique.classicDiagonal;
      if (titleText.contains('gräte') || titleText.contains('herringbone')) {
        return XcTechnique.classicHerringbone;
      }
      if (titleText.contains('doppelstock mit') ||
          titleText.contains('pole kick')) {
        return XcTechnique.classicDoublePoleKick;
      }
      return XcTechnique.unknown;
    }

    return XcTechnique.unknown;
  }
}

/// Adapter für First-Party Einheiten vom Ercolina-Oberkörperergometer.
class ErcolinaRecapAdapter {
  const ErcolinaRecapAdapter._();

  static NormalizedSession toNormalized(
    SessionRecap recap, {
    required String athleteId,
    String? title,
  }) {
    final durationSec = recap.duration.inSeconds;
    final workJoule = recap.averagePowerWatt * durationSec;
    final strokeCount = (recap.strokeRatePerMinute * (durationSec / 60.0))
        .round();

    final hasClassic = recap.hasClassicStrokes;
    final sessionTitle =
        title ??
        (hasClassic
            ? 'Ercolina Wechselzug / Diagonal'
            : 'Ercolina Doppelstock');

    return NormalizedSession(
      id: 'ercolina_${recap.sessionId}',
      athleteId: athleteId,
      source: NormalizedSessionSource.ercolina,
      sourceId: recap.sessionId,
      startedAtUtcUs: recap.startedAtUtcUs,
      durationSeconds: durationSec,
      movingTimeSeconds: durationSec,
      modality: XcModality.ercolinaDoublePoling,
      technique: hasClassic ? XcTechnique.unknown : XcTechnique.doublePoling,
      classificationProvenance: ClassificationProvenance.explicitSourceMetadata,
      isIndoor: true,
      title: sessionTitle,
      distanceMetres: null,
      elevationGainMetres: null,
      elevationLossMetres: null,
      externalMetrics: SessionExternalMetrics(
        sessionAveragePowerWatt: recap.averagePowerWatt,
        workPhaseAveragePowerWatt: recap.averageStrokePowerWatt,
        workJoule: workJoule,
        strokeOrCadenceRate: recap.strokeRatePerMinute,
        strokeCount: strokeCount,
        leftRightSymmetryPercent: recap.symmetryPercent,
        classicLeftWorkPercent: recap.classicLeftWorkPercent,
      ),
      internalMetrics: const SessionInternalMetrics(),
      dataQuality: const SessionDataQuality(
        confidence: 1.0,
        externalConfidence: 1.0,
        hasPower: true,
        hasCadenceOrStroke: true,
        hasHeartRate: false,
        hasGps: false,
        hasDropouts: false,
      ),
      rawMetadata: {
        'sessionId': recap.sessionId,
        'classicLeftStrokeCount': recap.classicLeftStrokeCount,
        'classicRightStrokeCount': recap.classicRightStrokeCount,
        if (recap.powerDeltaWatt != null)
          'powerDeltaWatt': recap.powerDeltaWatt,
      },
    );
  }
}

/// Adapter für Strava-Aktivitäten.
class StravaActivityAdapter {
  const StravaActivityAdapter._();

  static NormalizedSession toNormalized(
    StravaActivity strava, {
    required String athleteId,
  }) {
    final classification = EvidenceBasedModalityClassifier.classify(
      sport: strava.sportType,
      title: strava.name,
    );

    final isIndoor =
        strava.sportType.toLowerCase().contains('virtual') ||
        strava.sportType.toLowerCase().contains('indoor');

    final workJoule = strava.averageWatts != null
        ? strava.averageWatts! * strava.movingTimeSeconds
        : null;

    final hasHr =
        strava.averageHeartRateBpm != null && strava.averageHeartRateBpm! > 0;
    final hasPower = strava.averageWatts != null && strava.averageWatts! > 0;

    return NormalizedSession(
      id: 'strava_${strava.id}',
      athleteId: athleteId,
      source: NormalizedSessionSource.strava,
      sourceId: strava.id,
      startedAtUtcUs: strava.startDateLocal.toUtc().microsecondsSinceEpoch,
      durationSeconds: strava.elapsedTimeSeconds,
      movingTimeSeconds: strava.movingTimeSeconds,
      modality: classification.modality,
      technique: classification.technique,
      classificationProvenance: classification.provenance,
      isIndoor: isIndoor,
      title: strava.name,
      distanceMetres: strava.distanceMetres,
      elevationGainMetres: strava.totalElevationGainMetres,
      externalMetrics: SessionExternalMetrics(
        averagePowerWatt: strava.averageWatts,
        normalizedPowerWatt: strava.weightedAverageWatts,
        workJoule: workJoule,
      ),
      internalMetrics: SessionInternalMetrics(
        averageHeartRateBpm: strava.averageHeartRateBpm,
        peakHeartRateBpm: strava.maxHeartRateBpm,
      ),
      dataQuality: SessionDataQuality(
        confidence:
            classification.provenance == ClassificationProvenance.titleInferred
            ? 0.80
            : 0.85,
        externalConfidence: hasPower ? 0.80 : null,
        internalConfidence: hasHr ? 0.90 : null,
        hasHeartRate: hasHr,
        hasPower: hasPower,
        hasGps: strava.distanceMetres > 0,
      ),
      rawMetadata: {
        'originalSportType': strava.sportType,
        if (strava.sufferScore != null) 'sufferScore': strava.sufferScore,
      },
    );
  }
}

/// Adapter für externe Dateien (Garmin FIT, Wahoo etc.).
class ExternalActivityAdapter {
  const ExternalActivityAdapter._();

  static NormalizedSession toNormalized(
    ExternalActivityImport imported, {
    required String athleteId,
  }) {
    final classification = EvidenceBasedModalityClassifier.classify(
      sport: imported.activity.sport,
      title: imported.fileName,
    );

    final unit = imported.summary.loadUnit ?? imported.activity.samples.firstOrNull?.loadUnit;
    // Older power-summary imports predate a stored unit.
    final power = unit == null || unit == 'W';
    final provider = imported.activity.provider;
    final source = provider.isStrava
        ? NormalizedSessionSource.strava
        : (provider == ExternalProvider.garmin
              ? NormalizedSessionSource.garmin
              : NormalizedSessionSource.manual);

    final durationSec = imported.summary.elapsedSeconds > 0
        ? imported.summary.elapsedSeconds
        : ((imported.activity.endedAtUtcUs - imported.activity.startedAtUtcUs) /
                  Duration.microsecondsPerSecond)
              .round();

    final movingSec = imported.summary.activeSeconds > 0
        ? imported.summary.activeSeconds
        : durationSec;

    final hasHr =
        imported.summary.averageHeartRateBpm != null &&
        imported.summary.averageHeartRateBpm! > 0;
    final hasPower =
        power && imported.summary.averageLoad != null &&
        imported.summary.averageLoad! > 0;
    final hasGps =
        imported.summary.distanceMetres != null &&
        imported.summary.distanceMetres! > 0;
    final hasCadence =
        imported.summary.averageCadencePerMinute != null &&
        imported.summary.averageCadencePerMinute! > 0;

    return NormalizedSession(
      id: 'garmin_${imported.activity.sourceId}',
      athleteId: athleteId,
      source: source,
      sourceId: imported.activity.sourceId,
      startedAtUtcUs: imported.activity.startedAtUtcUs,
      durationSeconds: durationSec,
      movingTimeSeconds: movingSec,
      modality: classification.modality,
      technique: classification.technique,
      classificationProvenance: classification.provenance,
      isIndoor: false,
      title: imported.fileName,
      distanceMetres: imported.summary.distanceMetres,
      externalMetrics: SessionExternalMetrics(
        averagePowerWatt: power ? imported.summary.averageLoad : null,
        peakPowerWatt: power ? imported.summary.peakLoad : null,
        workJoule: imported.summary.workJoule,
        strokeOrCadenceRate: imported.summary.averageCadencePerMinute,
      ),
      internalMetrics: SessionInternalMetrics(
        averageHeartRateBpm: imported.summary.averageHeartRateBpm?.toDouble(),
        peakHeartRateBpm: imported.summary.peakHeartRateBpm,
      ),
      dataQuality: SessionDataQuality(
        confidence:
            classification.provenance == ClassificationProvenance.titleInferred
            ? 0.90
            : 0.95,
        externalConfidence: hasPower ? 0.95 : null,
        internalConfidence: hasHr ? 0.95 : null,
        hasHeartRate: hasHr,
        hasPower: hasPower,
        hasCadenceOrStroke: hasCadence,
        hasGps: hasGps,
        warnings: imported.warnings,
      ),
      rawMetadata: {
        'originalSportType': imported.activity.sport,
        'fileName': imported.fileName,
        if (imported.deviceName != null) 'deviceName': imported.deviceName,
        'recordCount': imported.recordCount,
        'decoderVersion': imported.decoderVersion,
        if (imported.activity.fitFileOrigin != null) 'fileOrigin': imported.activity.fitFileOrigin!.name,
      },
    );
  }
}

/// Ob diese Einheit die Frage «welche Laufdauer ist dieser Athlet gewohnt?»
/// beantworten darf.
///
/// Der Importadapter fasst oben `Run`, `Walk` und `Hike` zu
/// [XcModality.running] zusammen — der Kommentar dort sagt es selbst:
/// «Laufen / Gehen». Als Eintrag im Trainingstagebuch ist das in Ordnung, es
/// war in allen Fällen zu Fuss. Als Grundlage einer **Laufdosis** ist es
/// falsch: Eine vierstündige Bergwanderung belegt nicht, dass ein
/// zweistündiger Lauf orthopädisch verträglich ist.
///
/// Darum keine neue Modalität und kein Umschreiben gespeicherter Einheiten,
/// sondern eine Frage an die Quelle: Die rohe Sportart liegt in
/// [NormalizedSession.rawMetadata] unter `originalSportType`.
///
/// Fehlt die Angabe, gilt die Einheit als Lauf — eine Einheit ohne
/// Quellinformation stillschweigend zu verwerfen wäre schlimmer, als sie zu
/// zählen, und betrifft nur Quellen, die ihre Sportart nicht mitgeben.
bool isRunningDoseEvidence(NormalizedSession session) {
  if (session.modality != XcModality.running) return true;
  final raw = session.rawMetadata['originalSportType'];
  if (raw is! String) return true;
  return !const {'hike', 'walk', 'snowshoe'}.contains(raw.toLowerCase());
}
