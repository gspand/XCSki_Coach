import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'package:xc_coach/intelligence/workout_selection/user_override_context.dart';
import 'package:xc_coach/ui/today/today_view_model.dart';
import 'package:xc_coach/ui/plan/plan_view_model.dart';
import 'package:xc_ski_coach/coach_store.dart';
import 'package:xc_ski_coach/watch_snapshot.dart';

void main() {
  test(
    'Both profiles share one decision across Today, calendar and Watch. Replays retain each change.',
    () {
      final s = CoachStore(GiuliaDatabase.inMemory())..createProfiles();
      addTearDown(s.db.dispose);
      final clock = DateTime(2026, 11, 26, 0, 15).toUtc();
      for (final a in s.athletes) {
        final day = s.today.of(a.id, now: clock);
        final view = TodayViewModel.fromDecision(
          decision: day.decision,
          state: day.state,
        );
        final calendar = PlanViewModel.build(
          today: CalendarDay.ofLocal(clock.toLocal()),
          primaryGoal: null,
          weekWorkouts: [],
          availability: null,
          todayDecision: day.decision,
        ).activeDay;
        final payload = watchSnapshot(day, a.name);
        expect(
          s.storage.latestDailyDecision(a.id)!.toJson(),
          day.decision.toJson(),
        );
        expect(payload['athleteId'], a.id);
        expect(payload['decisionId'], '${a.id}/2026-11-26');
        expect(payload['decisionId'], view.decisionId);
        expect(payload['decisionVersion'], calendar.decisionVersion);
        expect(calendar.decisionId, view.decisionId);
        expect(calendar.title, view.heroTitle);
        expect(calendar.intensityLabel, view.qualitativeIntensity.label);
        expect(calendar.durationMinutes, payload['minutes']);
        expect(
          payload['validUntilMs'],
          DateTime(2026, 11, 27).millisecondsSinceEpoch,
        );
        s.today.invalidate(a.id);
        expect(
          watchSnapshot(
            s.today.of(a.id, now: clock.add(const Duration(minutes: 1))),
            a.name,
          )['decisionVersion'],
          view.decisionVersion,
        );
      }
      int count() =>
          s.db.raw
                  .select('SELECT COUNT(*) AS n FROM coach_decision_record')
                  .single['n']
              as int;
      expect(count(), 2);
      final id = s.athletes.first.id;
      s.storage.saveUserOverride(
        athleteId: id,
        override: const UserOverrideContext(forcedRestDay: true),
        recordedAtUtcUs: clock.microsecondsSinceEpoch,
      );
      s.today.invalidate(id);
      expect(
        watchSnapshot(s.today.of(id, now: clock), 'Test')['title'],
        'Ruhetag',
      );
      expect(count(), 3);
    },
  );
}
