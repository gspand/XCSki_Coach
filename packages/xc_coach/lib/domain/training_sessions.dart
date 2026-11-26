import 'normalized_session.dart';

/// Two provider records can represent one ski outing. Only collapse records in
/// the training calculation; each original remains visible in the archive.
/// The same start, duration, family and measured distance provide a
/// conservative identity; partial matches are left alone.
List<NormalizedSession> trainingSessions(Iterable<NormalizedSession> archive) {
  final seen = <(String, int, int, String, int), int>{};
  final result = <NormalizedSession>[];
  for (final session in archive) {
    if (!session.eligibleForCoach) continue;
    final metres = session.distanceMetres;
    if (metres == null || metres <= 0 || session.durationSeconds <= 0) {
      result.add(session);
      continue;
    }
    final key = (
      session.athleteId,
      session.startedAtUtcUs,
      session.durationSeconds,
      session.modality.sportGroup,
      metres.round(),
    );
    final index = seen[key];
    if (index != null) {
      final previous = result[index];
      final differentSource =
          previous.source != session.source ||
          (previous.source == NormalizedSessionSource.garmin &&
              previous.sourceId.startsWith('fit:') !=
                  session.sourceId.startsWith('fit:'));
      if (differentSource) {
        if (_priority(session) > _priority(previous)) result[index] = session;
        continue;
      }
    }
    seen[key] = result.length;
    result.add(session);
  }
  return result;
}

int _priority(NormalizedSession s) =>
    (s.source == NormalizedSessionSource.ercolina ? 8 : 0) +
    (s.dataQuality.hasHeartRate ? 4 : 0) +
    (s.dataQuality.hasPower ? 2 : 0) +
    (s.source == NormalizedSessionSource.garmin ? 1 : 0);
