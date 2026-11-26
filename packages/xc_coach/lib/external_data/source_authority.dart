/// Explicit source-of-truth and conservative cross-provider deduplication.
///
/// Provider data is never silently averaged. Each metric has an authority
/// order and every original provider record remains stored. The order answers
/// only which copy GIULIA uses for analysis when Garmin and Strava describe
/// the same real workout.
library;

import '../domain/source_authority.dart';
import 'activity_import.dart';

export '../domain/source_authority.dart';

class CanonicalActivitySignature {
  const CanonicalActivitySignature({
    required this.sport,
    required this.startedAtUtcUs,
    required this.elapsedSeconds,
    this.distanceMetres,
  });

  factory CanonicalActivitySignature.fromImport(ExternalActivityImport value) {
    final elapsed = value.summary.elapsedSeconds > 0
        ? value.summary.elapsedSeconds
        : ((value.activity.endedAtUtcUs - value.activity.startedAtUtcUs) /
                  Duration.microsecondsPerSecond)
              .round();
    return CanonicalActivitySignature(
      sport: normalizeExternalSport(value.activity.sport),
      startedAtUtcUs: value.activity.startedAtUtcUs,
      elapsedSeconds: elapsed,
      distanceMetres: value.summary.distanceMetres,
    );
  }

  final String sport;
  final int startedAtUtcUs;
  final int elapsedSeconds;
  final double? distanceMetres;
}

class ActivityDeduplicator {
  const ActivityDeduplicator();

  /// Deliberately conservative. A match needs the same sport family, a start
  /// within five minutes, and nearly equal duration. Where both providers
  /// expose distance, it must agree as well. A false negative is preferable to
  /// merging two genuine back-to-back workouts.
  bool isSameActivity(
    CanonicalActivitySignature left,
    CanonicalActivitySignature right,
  ) {
    if (left.sport != right.sport) return false;
    if ((left.startedAtUtcUs - right.startedAtUtcUs).abs() >
        const Duration(minutes: 5).inMicroseconds) {
      return false;
    }
    final longer = left.elapsedSeconds > right.elapsedSeconds
        ? left.elapsedSeconds
        : right.elapsedSeconds;
    final durationTolerance = (longer * .05).round().clamp(90, 300);
    if ((left.elapsedSeconds - right.elapsedSeconds).abs() >
        durationTolerance) {
      return false;
    }
    final leftDistance = left.distanceMetres;
    final rightDistance = right.distanceMetres;
    if (leftDistance != null && rightDistance != null) {
      final longerDistance = leftDistance > rightDistance
          ? leftDistance
          : rightDistance;
      final distanceTolerance = (longerDistance * .03).clamp(100, 500);
      if ((leftDistance - rightDistance).abs() > distanceTolerance) {
        return false;
      }
    }
    return true;
  }
}
