import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:xc_ski_coach/coach_store.dart';
import 'package:xc_ski_coach/scout_screen.dart';
import 'package:xc_ski_coach/scout_samples.dart';
import 'package:xc_coach/database/giulia_database.dart';

void main() {
  late CoachStore store;
  setUp(() => store = CoachStore(GiuliaDatabase.inMemory())..createProfiles());
  tearDown(() => store.db.dispose());
  test(
    'Scout keeps raw bounds, missing values, shared device and conflict-safe corrections',
    () {
      final a = ScoutSamples(store, 'own-athlete'),
          b = ScoutSamples(store, 'karina-puercher');
      final when = DateTime(2026, 11, 26, 8, 12);
      final id = a.save(
        raw: '2,4',
        sampledAt: when,
        timing: 'known',
        occasion: 'Belastung',
        stage: 'Stufe 3',
        device: 'Scout',
      );
      expect(
        store.db.raw.select('SELECT value FROM observation WHERE id=?', [
          id,
        ]).single['value'],
        2.4,
      );
      final other = b.save(
        raw: '<0,5',
        sampledAt: null,
        timing: 'unknown',
        occasion: 'Ruhe',
        device: 'Scout',
      );
      expect(other, isNot(id));
      expect(b.history().single['kind'], 'below');
      void correct(ScoutSamples repo, int rev) => repo.save(
        raw: 'HI',
        sampledAt: when,
        timing: 'estimated',
        occasion: 'Belastung',
        correctionOf: id,
        expectedRevision: rev,
        correctionReason: 'Anzeige geprüft',
      );
      expect(() => correct(b, 1), throwsStateError);
      correct(a, 1);
      expect(() => correct(a, 1), throwsStateError);
      expect(a.history().map((r) => r['raw']), ['HI', '2,4']);
      expect(
        store.db.raw.select('SELECT * FROM observation WHERE id=?', [id]),
        isEmpty,
      );
      expect(parseScoutDisplay('> 25,0'), (kind: 'above', number: 25.0));
      expect(parseScoutDisplay('fehlend').number, isNull);
      for (final raw in ['-1', '', 'NaN', '1,2.3', '0']) {
        expect(() => parseScoutDisplay(raw), throwsFormatException);
      }
    },
  );
  testWidgets('Quick sample confirms athlete and shows the saved raw reading', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScoutScreen(store: store, athlete: store.athletes.first),
      ),
    );
    await tester.tap(find.text('Probe erfassen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '<0,5');
    final save = find.text('Für ${store.athletes.first.name} speichern');
    await tester.scrollUntilVisible(
      save,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('<0,5 mmol/L'), findsOneWidget);
  });
}
