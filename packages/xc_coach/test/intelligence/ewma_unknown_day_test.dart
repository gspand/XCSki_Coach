import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/intelligence/load/ewma_load_tracker.dart';
import 'package:xc_coach/intelligence/load/load_models.dart';

void main() {
  group('EwmaLoadTracker Unknown Day Semantics', () {
    const tracker = EwmaLoadTracker();
    final baseDate = DateTime.utc(2026, 10, 1);
    const initialAcute = 80.0;
    const initialChronic = 100.0;
    const initialConfidence = 1.0;

    test('ConfirmedRestDay causes mathematical EWMA decay and preserves confidence', () {
      final stateA = tracker.step(
        date: baseDate,
        dailyLoad: 0.0,
        previousAcute: initialAcute,
        previousChronic: initialChronic,
        classification: DayClassification.confirmedRestDay,
        previousConfidence: initialConfidence,
      );

      // Decays according to alpha: acute < 80, chronic < 100
      expect(stateA.acuteLoad, lessThan(initialAcute));
      expect(stateA.chronicLoad, lessThan(initialChronic));
      expect(stateA.confidence, equals(initialConfidence));
      expect(stateA.isConfirmedRestDay, isTrue);
    });

    test('UnknownDay does NOT decay (no artificial recovery) and degrades confidence', () {
      final stateB = tracker.step(
        date: baseDate,
        dailyLoad: 0.0,
        previousAcute: initialAcute,
        previousChronic: initialChronic,
        classification: DayClassification.unknownDay,
        previousConfidence: initialConfidence,
      );

      // State is frozen, no artificial recovery!
      expect(stateB.acuteLoad, equals(initialAcute));
      expect(stateB.chronicLoad, equals(initialChronic));
      // Confidence is downgraded due to missing data
      expect(stateB.confidence, lessThan(initialConfidence));
      expect(stateB.confidence, closeTo(0.85, 0.01));
      expect(stateB.isUnknownDay, isTrue);
    });

    test('Comparative: UnknownDay vs ConfirmedRestDay from identical starting state', () {
      final restDayState = tracker.step(
        date: baseDate,
        dailyLoad: 0.0,
        previousAcute: initialAcute,
        previousChronic: initialChronic,
        classification: DayClassification.confirmedRestDay,
        previousConfidence: initialConfidence,
      );

      final unknownDayState = tracker.step(
        date: baseDate,
        dailyLoad: 0.0,
        previousAcute: initialAcute,
        previousChronic: initialChronic,
        classification: DayClassification.unknownDay,
        previousConfidence: initialConfidence,
      );

      // Crucial invariant: unknownDay does NOT produce the same artificial recovery as confirmedRestDay!
      expect(unknownDayState.acuteLoad, greaterThan(restDayState.acuteLoad));
      expect(unknownDayState.chronicLoad, greaterThan(restDayState.chronicLoad));
      expect(unknownDayState.confidence, lessThan(restDayState.confidence));
    });
  });
}
