import 'package:xc_coach/lala/core/models/test_stage.dart';

class StageSorter {
  const StageSorter();

  List<TestStage> sortByStageThenTime(List<TestStage> stages) {
    final copy = [...stages];
    copy.sort((a, b) {
      final stageCompare = a.stageNumber.compareTo(b.stageNumber);
      if (stageCompare != 0) {
        return stageCompare;
      }
      final firstTime = a.sampleTime;
      final secondTime = b.sampleTime;
      if (firstTime != null && secondTime != null) {
        final timeCompare = firstTime.compareTo(secondTime);
        if (timeCompare != 0) {
          return timeCompare;
        }
      } else if (firstTime != null) {
        return -1;
      } else if (secondTime != null) {
        return 1;
      }
      return a.load.compareTo(b.load);
    });
    return copy;
  }
}
