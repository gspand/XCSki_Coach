/// Durable, idempotent storage for completed external activities.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../database/giulia_database.dart';
import '../database/platform_repository.dart';
import '../database/session_repository.dart';
import '../domain/platform.dart';
import 'activity_import.dart';
import 'source_authority.dart';

class ExternalActivityImportResult {
  const ExternalActivityImportResult({
    required this.sessionId,
    required this.athleteId,
    required this.alreadyImported,
    required this.samplesWritten,
    required this.canonicalActivityId,
    this.mergedWithExistingActivity = false,
  });

  final String sessionId;
  final String athleteId;
  final bool alreadyImported;
  final int samplesWritten;
  final String canonicalActivityId;

  /// True when this provider record describes an activity GIULIA already
  /// knows from another source. Both originals remain stored, while only the
  /// higher-authority session enters training load and Athlete State.
  final bool mergedWithExistingActivity;
}

class ActivityImportRepository {
  factory ActivityImportRepository(
    GiuliaDatabase database, {
    PlatformRepository? platform,
    SessionRepository? sessions,
    SourceAuthorityPolicy authority = const SourceAuthorityPolicy(),
    ActivityDeduplicator deduplicator = const ActivityDeduplicator(),
  }) {
    final effectivePlatform = platform ?? PlatformRepository(database);
    return ActivityImportRepository._(
      database,
      effectivePlatform,
      sessions ?? SessionRepository(database, platform: effectivePlatform),
      authority,
      deduplicator,
    );
  }

  const ActivityImportRepository._(
    this.database,
    this.platform,
    this.sessions,
    this.authority,
    this.deduplicator,
  );

  final GiuliaDatabase database;
  final PlatformRepository platform;
  final SessionRepository sessions;
  final SourceAuthorityPolicy authority;
  final ActivityDeduplicator deduplicator;

  ExternalActivityImportResult write(
    ExternalActivityImport imported, {
    required String organizationId,
    required String athleteId,
    required String actorUserId,
    required int importedAtUtcUs,
  }) {
    final activity = imported.activity;
    if (!activity.eligibleForCoach) {
      throw UnsupportedError('Die Herkunft dieser Aktivität ist für XC Ski Coach nicht freigegeben.');
    }
    if (platform.organizationOfAthlete(athleteId) != organizationId) {
      throw const PlatformAccessException(
        'Die Aktivität gehört nicht zu diesem Arbeitsbereich.',
      );
    }
    platform.assertCanRecordFor(userId: actorUserId, athleteId: athleteId);
    _validate(imported);

    final existing = database.raw.select(
      '''SELECT imported.athlete_id, imported.session_id,
                source.canonical_activity_id
           FROM external_activity_import imported
           LEFT JOIN canonical_activity_source source
             ON source.organization_id = imported.organization_id
            AND source.provider_id = imported.provider_id
            AND source.source_id = imported.source_id
          WHERE imported.organization_id = ? AND imported.provider_id = ?
            AND imported.source_id = ?''',
      [organizationId, activity.provider.id, activity.sourceId],
    );
    void recordFileOrigin() {
      final origin = activity.fitFileOrigin;
      if (origin != null) {
        platform.setAppState(key: 'xc.fitOrigin.$athleteId.${activity.sourceId}',
            value: origin.name, nowUtcUs: importedAtUtcUs);
      }
    }
    if (existing.isNotEmpty) {
      if (existing.first['athlete_id'] == athleteId) recordFileOrigin();
      return ExternalActivityImportResult(
        sessionId: existing.first['session_id'] as String,
        athleteId: existing.first['athlete_id'] as String,
        alreadyImported: true,
        samplesWritten: 0,
        canonicalActivityId:
            existing.first['canonical_activity_id'] as String? ??
            existing.first['session_id'] as String,
      );
    }

    final signature = CanonicalActivitySignature.fromImport(imported);
    final canonical = _findCanonicalActivity(
      organizationId: organizationId,
      athleteId: athleteId,
      signature: signature,
    );

    final identity = sha256
        .convert(
          utf8.encode(
            '$organizationId:${activity.provider.id}:${activity.sourceId}',
          ),
        )
        .toString()
        .substring(0, 24);
    final sessionId = 'external-activity-$identity';
    final elapsedSeconds = imported.summary.elapsedSeconds > 0
        ? imported.summary.elapsedSeconds
        : ((activity.endedAtUtcUs - activity.startedAtUtcUs) /
                  Duration.microsecondsPerSecond)
              .round();
    final activeSeconds = imported.summary.activeSeconds
        .clamp(0, elapsedSeconds)
        .toInt();
    final pausedUs =
        (elapsedSeconds - activeSeconds) * Duration.microsecondsPerSecond;
    final raw = imported.rawFile;
    final rawHash = raw == null ? null : sha256.convert(raw).toString();
    final metrics = _metrics(imported, activeSeconds: activeSeconds);

    return database.transaction(() {
      recordFileOrigin();
      sessions.recordCompletedSession(
        session: SessionStart(
          id: sessionId,
          organizationId: organizationId,
          athleteId: athleteId,
          recordedByUserId: actorUserId,
          startedAtUtcUs: activity.startedAtUtcUs,
          algorithmVersion: imported.decoderVersion,
          processingConfigJson: jsonEncode({
            'source': 'external_activity',
            'provider': activity.provider.id,
            'sourceId': activity.sourceId,
            if (activity.fitFileOrigin != null) 'fileOrigin': activity.fitFileOrigin!.name,
          }),
          movementType: activity.sport,
        ),
        endedAtUtcUs: activity.endedAtUtcUs,
        notes:
            '${imported.fileName} · importiert aus ${activity.provider.id} · '
            '${activity.sourceId}',
      );
      database.raw.execute('UPDATE session SET paused_us = ? WHERE id = ?', [
        pausedUs,
        sessionId,
      ]);
      database.raw.execute(
        '''INSERT INTO external_activity_import(
             organization_id, provider_id, source_id, athlete_id, session_id,
             file_name, raw_file, raw_sha256, decoder_version, warnings_json,
             imported_at_utc_us)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          organizationId,
          activity.provider.id,
          activity.sourceId,
          athleteId,
          sessionId,
          imported.fileName,
          raw,
          rawHash,
          imported.decoderVersion,
          jsonEncode(imported.warnings),
          importedAtUtcUs,
        ],
      );

      final sampleStatement = database.raw.prepare(
        '''INSERT INTO external_activity_sample(
             organization_id, provider_id, source_id, ordinal,
             recorded_at_utc_us, load_value, load_unit, heart_rate_bpm,
             cadence_per_minute)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      );
      final heartRateStatement = database.raw.prepare(
        '''INSERT OR IGNORE INTO heart_rate_sample(
             session_id, recorded_at_us, bpm, rr_intervals_ms,
             contact_detected)
           VALUES (?, ?, ?, NULL, NULL)''',
      );
      try {
        for (final (ordinal, sample) in activity.samples.indexed) {
          sampleStatement.execute([
            organizationId,
            activity.provider.id,
            activity.sourceId,
            ordinal,
            sample.atUtcUs,
            sample.loadValue,
            sample.loadUnit,
            sample.heartRateBpm,
            sample.cadencePerMinute,
          ]);
          if (sample.heartRateBpm case final bpm?) {
            heartRateStatement.execute([sessionId, sample.atUtcUs, bpm]);
          }
        }
      } finally {
        sampleStatement.dispose();
        heartRateStatement.dispose();
      }

      database.raw.execute(
        '''INSERT INTO session_metrics(
             session_id, calculated_at_utc_us, algorithm_version,
             metrics_json)
           VALUES (?, ?, ?, ?)''',
        [
          sessionId,
          importedAtUtcUs,
          imported.decoderVersion,
          jsonEncode(metrics),
        ],
      );
      platform.enqueueSync(
        organizationId: organizationId,
        entity: 'external_activity_import',
        entityId: sessionId,
        operation: 'insert',
        nowUtcUs: importedAtUtcUs,
      );
      platform.writeAudit(
        organizationId: organizationId,
        actorUserId: actorUserId,
        action: 'external_activity_imported',
        entity: 'session',
        entityId: sessionId,
        nowUtcUs: importedAtUtcUs,
      );
      final canonicalActivityId = _linkCanonicalActivity(
        imported: imported,
        organizationId: organizationId,
        athleteId: athleteId,
        sessionId: sessionId,
        importedAtUtcUs: importedAtUtcUs,
        signature: signature,
        existing: canonical,
      );
      return ExternalActivityImportResult(
        sessionId: sessionId,
        athleteId: athleteId,
        alreadyImported: false,
        samplesWritten: activity.samples.length,
        canonicalActivityId: canonicalActivityId,
        mergedWithExistingActivity: canonical != null,
      );
    });
  }

  _CanonicalActivity? _findCanonicalActivity({
    required String organizationId,
    required String athleteId,
    required CanonicalActivitySignature signature,
  }) {
    final tolerance = const Duration(minutes: 5).inMicroseconds;
    final rows = database.raw.select(
      '''SELECT c.id, s.movement_type AS sport, s.started_at_utc_us,
                ROUND((s.ended_at_utc_us - s.started_at_utc_us) / 1000000.0) AS elapsed_seconds,
                json_extract(m.metrics_json, '\$.distanceMetres') AS distance_metres,
                source.provider_id AS preferred_provider_id
           FROM xc_canonical_source source
           JOIN canonical_activity c ON c.id = source.canonical_activity_id
           JOIN xc_session s ON s.id = source.session_id
           LEFT JOIN session_metrics m ON m.session_id = s.id
          WHERE source.preference = 1 AND s.organization_id = ? AND s.athlete_id = ?
            AND s.started_at_utc_us BETWEEN ? AND ? AND s.ended_at_utc_us IS NOT NULL
          ORDER BY ABS(s.started_at_utc_us - ?)''',
      [
        organizationId,
        athleteId,
        signature.startedAtUtcUs - tolerance,
        signature.startedAtUtcUs + tolerance,
        signature.startedAtUtcUs,
      ],
    );
    for (final row in rows) {
      final candidate = CanonicalActivitySignature(
        sport: normalizeExternalSport(row['sport'] as String),
        startedAtUtcUs: row['started_at_utc_us'] as int,
        elapsedSeconds: (row['elapsed_seconds'] as num).round(),
        distanceMetres: (row['distance_metres'] as num?)?.toDouble(),
      );
      if (deduplicator.isSameActivity(signature, candidate)) {
        return _CanonicalActivity(
          id: row['id'] as String,
          preferredProviderId: row['preferred_provider_id'] as String,
        );
      }
    }
    return null;
  }

  String _linkCanonicalActivity({
    required ExternalActivityImport imported,
    required String organizationId,
    required String athleteId,
    required String sessionId,
    required int importedAtUtcUs,
    required CanonicalActivitySignature signature,
    required _CanonicalActivity? existing,
  }) {
    final providerId = imported.activity.provider.id;
    final sourceId = imported.activity.sourceId;
    final providerRank = authority.rank(
      providerId,
      ExternalMetric.activityIdentity,
    );
    final canonicalId =
        existing?.id ??
        'canonical-${sha256.convert(utf8.encode('$organizationId:$athleteId:$providerId:$sourceId')).toString().substring(0, 24)}';
    if (existing == null) {
      database.raw.execute(
        '''INSERT INTO canonical_activity(
             id, organization_id, athlete_id, sport, started_at_utc_us,
             elapsed_seconds, distance_metres, preferred_provider_id,
             preferred_source_id, preferred_session_id, created_at_utc_us,
             updated_at_utc_us)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          canonicalId,
          organizationId,
          athleteId,
          signature.sport,
          signature.startedAtUtcUs,
          signature.elapsedSeconds,
          signature.distanceMetres,
          providerId,
          sourceId,
          sessionId,
          importedAtUtcUs,
          importedAtUtcUs,
        ],
      );
    }
    database.raw.execute(
      '''INSERT INTO canonical_activity_source(
           organization_id, provider_id, source_id, canonical_activity_id,
           session_id, authority_rank, linked_at_utc_us)
         VALUES (?, ?, ?, ?, ?, ?, ?)''',
      [
        organizationId,
        providerId,
        sourceId,
        canonicalId,
        sessionId,
        providerRank,
        importedAtUtcUs,
      ],
    );
    if (existing != null &&
        authority.shouldReplace(
          currentProviderId: existing.preferredProviderId,
          candidateProviderId: providerId,
          metric: ExternalMetric.activityIdentity,
        )) {
      database.raw.execute(
        '''UPDATE canonical_activity
              SET preferred_provider_id = ?, preferred_source_id = ?,
                  preferred_session_id = ?, distance_metres = ?,
                  elapsed_seconds = ?, started_at_utc_us = ?,
                  updated_at_utc_us = ?
            WHERE id = ?''',
        [
          providerId,
          sourceId,
          sessionId,
          signature.distanceMetres,
          signature.elapsedSeconds,
          signature.startedAtUtcUs,
          importedAtUtcUs,
          canonicalId,
        ],
      );
    }
    return canonicalId;
  }

  Map<String, Object?> _metrics(
    ExternalActivityImport imported, {
    required int activeSeconds,
  }) {
    final summary = imported.summary;
    final unit = imported.summary.loadUnit ?? imported.activity.samples.firstOrNull?.loadUnit;
    return <String, Object?>{
      'source': 'external_activity',
      'provider': imported.activity.provider.id,
      'sourceId': imported.activity.sourceId,
      'fileName': imported.fileName,
      'activeSeconds': activeSeconds,
      'loadUnit': unit,
      if (unit == 'W') 'averagePowerWatt': summary.averageLoad,
      if (unit == 'W') 'peakPowerWatt': summary.peakLoad,
      if (unit == 'km/h') 'averageSpeedKmh': summary.averageLoad,
      if (unit == 'km/h') 'peakSpeedKmh': summary.peakLoad,
      'workJoule': summary.workJoule,
      'distanceMetres': summary.distanceMetres,
      'averageHeartRateBpm': summary.averageHeartRateBpm,
      'peakHeartRateBpm': summary.peakHeartRateBpm,
      'averageCadencePerMinute': summary.averageCadencePerMinute,
      'peakCadencePerMinute': summary.peakCadencePerMinute,
    }..removeWhere((_, value) => value == null);
  }

  void _validate(ExternalActivityImport imported) {
    final activity = imported.activity;
    if (activity.startedAtUtcUs <= 0 ||
        activity.endedAtUtcUs < activity.startedAtUtcUs ||
        (activity.samples.isEmpty && !(imported.decoderVersion == 'xc-coach-fit-1' && imported.rawFile != null && imported.recordCount > 0)) ||
        imported.summary.elapsedSeconds < 0 ||
        imported.summary.activeSeconds < 0 ||
        imported.summary.activeSeconds > imported.summary.elapsedSeconds ||
        activity.provider.id.trim().isEmpty ||
        activity.sourceId.trim().isEmpty) {
      throw const FormatException('Die Aktivität ist unvollständig.');
    }
    var previous = activity.startedAtUtcUs - 1;
    for (final sample in activity.samples) {
      if (sample.atUtcUs < previous ||
          sample.atUtcUs < activity.startedAtUtcUs ||
          sample.atUtcUs > activity.endedAtUtcUs ||
          !sample.loadValue.isFinite ||
          sample.loadValue <= 0 ||
          sample.loadUnit.trim().isEmpty ||
          (sample.heartRateBpm != null &&
              (sample.heartRateBpm! < 20 || sample.heartRateBpm! > 250))) {
        throw const FormatException(
          'Die Aktivität enthält ungültige oder ungeordnete Messpunkte.',
        );
      }
      previous = sample.atUtcUs;
    }
  }
}

class _CanonicalActivity {
  const _CanonicalActivity({
    required this.id,
    required this.preferredProviderId,
  });

  final String id;
  final String preferredProviderId;
}
