import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/xc_athlete_state.dart';
import 'garmin_personal.dart';

Map? activityHistoryStatus(GarminArchive archive) {
  final raw = archive.setting('historyFeeds');
  if (raw == null) return null;
  return (jsonDecode(raw) as List)
      .whereType<Map>()
      .where((feed) => feed['feed'] == 'activities')
      .firstOrNull;
}

String historyLabel(GarminArchive archive) {
  final feed = activityHistoryStatus(archive);
  if ((archive.setting('historyError') ?? '').isNotEmpty)
    return archive.setting('historyError')!;
  if (feed == null) return 'Historienstatus noch offen';
  if (feed['reason'] == 'endpoint_disabled')
    return 'Historischer Aktivitätsabruf bei Garmin deaktiviert';
  if (feed['code'] == 412 || feed['state'] == 'denied')
    return 'Garmin hat den historischen Aktivitätsabruf abgelehnt (HTTP ${feed['code']}).';
  if (feed['state'] == 'unavailable')
    return 'Garmin liefert für diesen Zeitraum keine Zusage (HTTP ${feed['code']}).';
  if (feed['state'] == 'waiting')
    return 'Historienabruf wartet auf einen neuen Versuch';
  if ((feed['until_s'] as int) < (feed['first_s'] as int)) {
    final from = DateTime.fromMillisecondsSinceEpoch(
      ((feed['until_s'] as int) + 1) * 1000,
    );
    return 'Aktivitäten ab ${from.day}.${from.month}.${from.year} bei Garmin angefordert';
  }
  return 'Historienabruf vorgemerkt';
}

class GarminTrainingStatus extends StatelessWidget {
  const GarminTrainingStatus({
    super.key,
    required this.archive,
    required this.state,
    required this.onConnect,
  });
  final GarminArchive archive;
  final XCAthleteState state;
  final VoidCallback onConnect;
  @override
  Widget build(BuildContext context) {
    final rows = archive.store.db.raw.select(
      "SELECT id,title,started_at_utc_us,moving_time_seconds FROM xc_normalized_session WHERE athlete_id=? AND source='garmin' AND started_at_utc_us<=? ORDER BY started_at_utc_us DESC LIMIT 1",
      [archive.athlete, DateTime.now().microsecondsSinceEpoch],
    );
    final last = rows.firstOrNull;
    final inDecision =
        last != null && state.eliteAnalysis.latestGarminSessionId == last['id'];
    final checked = DateTime.tryParse(
      archive.setting('lastPushCheck') ?? '',
    )?.toLocal();
    final mat = MaterialLocalizations.of(context);
    String stamp(DateTime d) =>
        '${mat.formatShortDate(d)} · ${TimeOfDay.fromDateTime(d).format(context)}';
    final day = last == null
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(last['started_at_utc_us'] as int);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xffe6efea),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.watch_outlined, color: Color(0xff17634f)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Zuletzt von Garmin',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
              ),
              IconButton(
                tooltip: 'Garmin-Verbindung ansehen',
                onPressed: onConnect,
                icon: const Icon(Icons.arrow_outward),
              ),
            ],
          ),
          Text(
            last == null
                ? 'Noch keine Garmin-Einheit im Trainingsbuch'
                : '${last['title']} · ${((last['moving_time_seconds'] as int) / 60).round()} min',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          if (day != null)
            Text(
              '${stamp(day)} · ${inDecision ? 'Im Trainingsumfang der Tagesempfehlung berücksichtigt' : 'Im Trainingsbuch erfasst'}',
            ),
          const SizedBox(height: 8),
          Text(historyLabel(archive)),
          if (checked != null)
            Text(
              'Eingang geprüft am ${stamp(checked)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
