import 'dart:convert';

import 'package:xc_coach/observation/observation.dart';
import 'package:xc_coach/database/observation_repository_sqlite.dart';

import 'coach_store.dart';

/// The raw display and its qualifier survive even when no exact observation
/// can be projected. In particular a bounded reading has no exact value.
({String kind, double? number}) parseScoutDisplay(String raw) {
  final text = raw.trim().toLowerCase();
  if (text == 'fehlend' || text == 'lo' || text == 'hi') {
    return (
      kind: {'fehlend': 'missing', 'lo': 'below', 'hi': 'above'}[text]!,
      number: null,
    );
  }
  final match = RegExp(r'^([<>]?)\s*(\d+(?:[,.]\d+)?)$').firstMatch(text);
  final value = match == null
      ? null
      : double.tryParse(match[2]!.replaceAll(',', '.'));
  if (match == null || value == null || !value.isFinite || value <= 0) {
    throw const FormatException(
      'Geräteanzeige eingeben, z. B. 2,4 oder <0,5. Möglich sind auch LO, HI und fehlend.',
    );
  }
  return (
    kind: switch (match[1]) {
      '<' => 'below',
      '>' => 'above',
      _ => 'exact',
    },
    number: value,
  );
}

/// An athlete-scoped journal. Each correction checks the revision the user saw.
/// The observation table contains exactly one current projection per timed sample.
class ScoutSamples {
  ScoutSamples(this.store, this.athleteId);
  final CoachStore store;
  final String athleteId;

  void _authorize() {
    if (!store.athletes.any((p) => p.id == athleteId))
      throw StateError('Profil nicht freigegeben.');
  }

  List<Map<String, dynamic>> history() {
    _authorize();
    return store.db.raw
        .select(
          'SELECT * FROM xc_scout_revision WHERE athlete_id = ? ORDER BY recorded_at_utc_us DESC, revision DESC',
          [athleteId],
        )
        .map(
          (r) => {
            ...jsonDecode(r['document'] as String) as Map<String, dynamic>,
            'sampleId': r['sample_id'],
            'revision': r['revision'],
            'recordedAtUs': r['recorded_at_utc_us'],
            'recordedBy': r['recorded_by'],
            'athleteId': athleteId,
          },
        )
        .toList();
  }

  String save({
    required String raw,
    required DateTime? sampledAt,
    required String timing,
    required String occasion,
    String stage = '',
    String device = '',
    String site = '',
    String notes = '',
    int? secondsAfterLoad,
    String? correctionOf,
    int? expectedRevision,
    String correctionReason = '',
  }) {
    _authorize();
    final result = parseScoutDisplay(raw);
    if (!['known', 'estimated', 'unknown'].contains(timing) ||
        (sampledAt == null) != (timing == 'unknown'))
      throw ArgumentError('Probezeit prüfen.');
    if (secondsAfterLoad != null && secondsAfterLoad < 0)
      throw ArgumentError('Abstand zum Belastungsende prüfen.');
    if (correctionOf != null && correctionReason.trim().isEmpty)
      throw const FormatException('Korrekturgrund angeben.');
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    return store.db.transaction(() {
      final sql = store.db.raw;
      final id =
          correctionOf ??
          'scout-${sql.select("SELECT lower(hex(randomblob(16))) AS id").single['id']}';
      var revision = 1;
      if (correctionOf != null) {
        final last = sql.select(
          'SELECT MAX(revision) AS current FROM xc_scout_revision WHERE athlete_id=? AND sample_id=?',
          [athleteId, id],
        ).single['current'];
        if (last == null || last != expectedRevision)
          throw StateError(
            'Probe zwischenzeitlich geändert oder anderem Profil zugeordnet.',
          );
        revision = (last as int) + 1;
        sql.execute('DELETE FROM observation WHERE athlete_id=? AND id=?', [
          athleteId,
          id,
        ]);
      }
      final doc = {
        'raw': raw.trim(),
        'kind': result.kind,
        'number': result.number,
        'unit': 'mmol/L',
        'source': 'manual',
        'method': 'capillary_meter',
        'sampledAtUs': sampledAt?.microsecondsSinceEpoch,
        'timeOffsetMinutes': sampledAt?.timeZoneOffset.inMinutes,
        'timing': timing,
        'occasion': occasion,
        'stage': stage,
        'device': device,
        'site': site,
        'notes': notes,
        'secondsAfterLoad': secondsAfterLoad,
        'correctionReason': correctionReason.trim(),
      };
      sql.execute(
        'INSERT INTO xc_scout_revision(athlete_id,sample_id,revision,recorded_at_utc_us,recorded_by,document) VALUES(?,?,?,?,?,?)',
        [athleteId, id, revision, now, owner, jsonEncode(doc)],
      );
      if (sampledAt != null && result.kind == 'exact' && timing == 'known') {
        SqliteObservationRepository(store.db).record(
          Observation(
            id: id,
            athleteId: athleteId,
            observedAtUtcUs: sampledAt.microsecondsSinceEpoch,
            type: ObservationType.lactate,
            value: result.number,
            context: const ObservationContext(),
            text: notes,
            unit: 'mmol/L',
            recordedByUserId: owner,
            occasion: occasion,
            sampleSite: site.isEmpty ? null : site,
            timeSinceLoadEndSeconds: secondsAfterLoad,
          ),
        );
      }
      return id;
    });
  }
}
