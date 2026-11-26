import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_ski_coach/coach_store.dart';

void main() {
  final source = Platform.environment['XC_SOURCE_ARCHIVE'];
  final destination = Platform.environment['XC_NEW_ARCHIVE'];
  test(
    'import real archive, verify all training tables and compute both recommendations',
    () {
      final timer = Stopwatch()..start();
      initializeArchive(destination!, source!);
      final importMs = timer.elapsedMilliseconds;
      timer.reset();
      final copy = CoachStore(GiuliaDatabase.open(destination));
      final openingMs = timer.elapsedMilliseconds;
      final original = GiuliaDatabase.readOnly(source);
      try {
        final tables = original.raw.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != 'app_state'",
        );
        for (final table in tables) {
          final name = table['name'] as String;
          final query = 'SELECT COUNT(*) FROM "${name.replaceAll('"', '""')}"';
          expect(
            copy.db.raw.select(query).single.values.single,
            name == 'sync_outbox'
                ? 0
                : original.raw.select(query).single.values.single,
            reason: name,
          );
        }
        expect(
          copy.db.raw.select(
            "SELECT 1 FROM strava_sync_state WHERE access_token!='' OR refresh_token!='' OR session_secret!=''",
          ),
          isEmpty,
        );
        final decisionMs = <int>[];
        for (final a in copy.athletes) {
          timer.reset();
          final plan = copy.today.of(a.id);
          decisionMs.add(timer.elapsedMilliseconds);
          expect(plan.state.athleteId, a.id);
          expect(plan.decision.coachingReason, isNotEmpty);
        }
        stdout.writeln(
          'Archive replay · Import ${importMs}ms · Öffnen ${openingMs}ms · erste Tagesberechnung pro Profil ${decisionMs}ms',
        );
      } finally {
        copy.db.dispose();
        original.dispose();
      }
    },
    skip: source == null || destination == null
        ? 'Requires explicit source and unused destination'
        : false,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
