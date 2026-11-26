/// Returns the observed increase of a cumulative counter across resets.
///
/// A decrease starts a new counter segment. Its first value belongs to the
/// observation gap since the previous sample and is therefore retained.
int cumulativeCounterDelta(Iterable<int> values) {
  int? previous;
  var total = 0;
  for (final current in values) {
    if (previous != null) {
      total += current >= previous ? current - previous : current;
    }
    previous = current;
  }
  return total;
}
