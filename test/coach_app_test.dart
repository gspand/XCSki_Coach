import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/database/giulia_database.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:xc_coach/intelligence/workout_selection/user_override_context.dart';
import 'package:xc_ski_coach/coach_store.dart';
import 'package:xc_ski_coach/main.dart';
import 'package:xc_ski_coach/provider_import.dart';

void main() {
  test(
    'initial import and restart preserve profiles and never replace an archive',
    () {
      final dir = Directory.systemTemp.createTempSync('ski-test-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final source = '${dir.path}/source.db';
      final copy = '${dir.path}/copy.db';
      initializeArchive(source, null);
      final db = GiuliaDatabase.open(source);
      final store = CoachStore(db);
      store.storage.saveUserOverride(
        athleteId: 'own-athlete',
        override: const UserOverrideContext(forcedRestDay: true),
        recordedAtUtcUs: DateTime.now().microsecondsSinceEpoch,
      );
      initializeArchive(copy, source);
      final cloned = CoachStore(GiuliaDatabase.open(copy));
      addTearDown(cloned.db.dispose);
      expect(
        cloned.athletes.map((a) => a.id),
        containsAll(privateProfiles.keys),
      );
      expect(
        cloned.storage.latestUserOverride('own-athlete')!.forcedRestDay,
        isTrue,
      );
      expect(cloned.storage.latestUserOverride('karina-puercher'), isNull);
      expect(() => initializeArchive(copy, null), throwsStateError);
      db.dispose();
    },
  );
  test(
    'Garmin preserves source measurements and a repeat does not double the load',
    () {
      final s = CoachStore(GiuliaDatabase.inMemory())..createProfiles();
      addTearDown(s.db.dispose);
      final now = DateTime.now().toUtc();
      final session = garminSession({
        'providerActivityId': 'abc',
        'title': 'Skating',
        'activityType': 'cross_country_skiing',
        'startedAt': now.subtract(const Duration(days: 1)).toIso8601String(),
        'elapsedTime': 3600,
        'movingTime': 3550,
        'distance': 14.5,
        'averageHr': 141,
      }, 'karina-puercher');
      for (var i = 0; i < 2; i++) {
        s.storage.saveNormalizedSession(
          session,
          nowUtcUs: now.microsecondsSinceEpoch,
        );
      }
      final records = s.storage.loadNormalizedSessions('karina-puercher');
      expect(records.single.modality, XcModality.skiSkating);
      expect(records.single.distanceMetres, 14500);
      expect(records.single.averagePowerWatt, isNull);
      expect(
        s.today
            .of('karina-puercher')
            .state
            .skiExposure
            .exposureOf(XcModality.skiSkating)
            .sessionCount28d,
        1,
      );
      expect(s.storage.loadNormalizedSessions('own-athlete'), isEmpty);
    },
  );
  testWidgets(
    'switch profiles, open plan, edit goals, return to the same athlete',
    (tester) async {
      final s = CoachStore(GiuliaDatabase.inMemory())..createProfiles();
      addTearDown(s.db.dispose);
      await tester.pumpWidget(MaterialApp(home: CoachHome(store: s)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Karina').last);
      await tester.pumpAndSettle();
      expect(s.platform.appState('xc.active'), 'karina-puercher');
      await tester.tap(find.text('Plan').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Profil und Daten'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wettkampfziele').last);
      await tester.pumpAndSettle();
      expect(find.text('Deine Saisonziele'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
