import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'package:xc_ski_coach/coach_store.dart';
import 'package:xc_ski_coach/garmin_personal.dart';
import 'package:xc_ski_coach/garmin_push.dart';
import 'package:xc_ski_coach/health_trend.dart';

void main() {
  test(
    'push health reaches daily dashboard, preserves raw series and isolates cycle consent',
    () {
      final store = CoachStore(GiuliaDatabase.inMemory())..createProfiles();
      addTearDown(store.db.dispose);
      final archive = GarminArchive(store, 'karina-puercher');
      final day = CalendarDay.parse('2026-11-26');
      void receive(String kind, String type, GarminJson data) {
        storeGarminPush(archive, {
          'kind': kind,
          'type': type,
          'data': {'calendarDate': day.key, ...data},
        });
      }

      receive('health', 'sleeps', {
        'summaryId': 'first',
        'durationInSeconds': 26700,
      });
      receive('health', 'hrv', {'summaryId': 'night', 'lastNightAvg': 58});
      receive('health', 'epochs', {'summaryId': 'a'});
      receive('health', 'epochs', {'summaryId': 'b'});
      final cycle = {'summaryId': 'c', 'dayInCycle': 8};
      receive('cycle', 'mct', cycle);
      expect(HealthMeasure.sleep.series(archive, day).last, 26700);
      expect(HealthMeasure.hrv.series(archive, day).last, 58);
      expect(
        archive
            .series(day.key)
            .where((s) => s.startsWith('connectPush.epochs')),
        hasLength(2),
      );
      expect(HealthMeasure.cycle.series(archive, day).last, isNull);
      archive.setCycle(true);
      receive('cycle', 'mct', cycle);
      expect(HealthMeasure.cycle.series(archive, day).last, 8);
      final other = GarminArchive(store, 'own-athlete');
      expect(other.dates(), isEmpty);
      archive.setCycle(false);
      expect(
        archive.series(day.key).where((s) => s.startsWith('cycle')),
        isEmpty,
      );
      expect(HealthMeasure.hrv.series(archive, day).last, 58);
    },
  );
}
