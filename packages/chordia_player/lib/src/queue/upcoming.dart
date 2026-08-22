/// Pure index arithmetic the queue and the prefetcher both need.
///
/// Ports of `frontend/src/lib/player/prefetch.ts` and `frontend/src/lib/player/queue-order.ts`.
/// Both are separate from the controller for the same reason they are separate on the web: the
/// windowing and the move bookkeeping are where the off-by-ones live, and they are far easier to
/// pin down as functions than as observed side effects of a command.
library;

/// Which queue positions to preload ahead of [current]: up to [count] entries after it, wrapping
/// to the start only when repeat-all is on, and never re-listing the current entry.
///
/// The wrap rule is the whole point. With repeat off, the tracks past the end are not coming, so
/// fetching them spends a listener's data on audio that will never sound; with repeat-all they are
/// the very next thing to play.
List<int> upcomingIndices(
  int current,
  int length,
  int count, {
  required bool wrap,
}) {
  final out = <int>[];
  if (length <= 0 || count <= 0 || current < 0 || current >= length) return out;
  for (var k = 1; k <= count && out.length < length - 1; k++) {
    var i = current + k;
    if (i >= length) {
      if (!wrap) break;
      i %= length;
    }
    if (i == current || out.contains(i)) continue;
    out.add(i);
  }
  return out;
}

/// Where the entry at index [current] ends up after moving the entry at [from] to [to], using
/// standard array-move semantics (remove at [from], then insert at [to] in the resulting list).
///
/// Called with the playing index so a drag in the queue panel never changes what is sounding.
int indexAfterMove(int current, int from, int to) {
  if (from == current) return to;
  var i = current;
  if (from < i) i -= 1;
  if (to <= i) i += 1;
  return i;
}
