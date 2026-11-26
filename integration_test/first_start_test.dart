import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xc_ski_coach/dashboard.dart';
import 'package:xc_ski_coach/main.dart' as app;

/// Use an empty simulator installation. Never erase an existing archive here.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Erststart erzeugt zwei Profile und öffnet das Dashboard', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();
    final start = find.text('Mit leeren Profilen starten');
    expect(
      start,
      findsOneWidget,
      reason: 'Dieser Test benötigt eine leere Testinstallation.',
    );
    await tester.tap(start);
    for (
      int i = 0;
      i < 80 && find.byType(SkiDashboard).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 125));
    }
    expect(find.byType(SkiDashboard), findsOneWidget);
    expect(find.text('Trainingsübersicht'), findsOneWidget);
  });
}
