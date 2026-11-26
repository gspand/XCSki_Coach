import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_ski_coach/evidence_screen.dart';

// Use the shipped evidence files with synchronous I/O isolated to the test
// bundle. This keeps large-asset decoding independent of the widget fake clock.
class _EvidenceBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(File(key).readAsBytesSync());
  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      File(key).readAsStringSync();
}

Future<void> openLibrary(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DefaultAssetBundle(
        bundle: _EvidenceBundle(),
        child: const EvidenceScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shipping asset bundle includes both research registers', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(
      manifest.listAssets(),
      containsAll(<String>[
        'docs/evidence/sources.json',
        'docs/evidence/claims.json',
      ]),
    );
  });

  testWidgets(
    'offline library searches by technique and training goal, opens actual source and limitations',
    (tester) async {
      await openLibrary(tester);
      expect(find.text('47 Quellen'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Doppelstock MLSS');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('LA03')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('LA03')));
      await tester.pumpAndSettle();
      expect(find.text('Quelle LA03'), findsOneWidget);
      expect(find.text('Übertragbarkeit und Grenzen'), findsOneWidget);
      expect(find.textContaining('21,4 ± 2,8 km/h'), findsOneWidget);
      expect(find.textContaining('Doppelstockstichprobe'), findsOneWidget);
    },
  );

  testWidgets('full-text extraction is discoverable without expert approval', (
    tester,
  ) async {
    await openLibrary(tester);
    await tester.tap(find.text('Alle Prüfstände'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volltext ausgewertet').last);
    await tester.pumpAndSettle();
    expect(find.text('1 Quelle'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('LA03')));
    await tester.pumpAndSettle();
    expect(find.textContaining('6,0 ± 2,4 mmol/l'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(find.textContaining('noch nicht freigegeben'), findsOneWidget);
  });

  testWidgets(
    'source count reflects review status, including empty approved selection',
    (tester) async {
      await openLibrary(tester);
      await tester.tap(find.text('Alle Prüfstände'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Regel freigegeben').last);
      await tester.pumpAndSettle();
      expect(find.text('0 Quellen'), findsOneWidget);
      expect(
        find.text('Für diese Auswahl gibt es keine Quellen.'),
        findsOneWidget,
      );
    },
  );
}
