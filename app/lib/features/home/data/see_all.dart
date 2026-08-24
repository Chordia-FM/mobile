import 'package:chordia_api/chordia_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'home_feed.dart';

/// The full lists behind home's two "See all" links.
///
/// Read through [HomeSource] rather than the Hub client, because these pages ARE the home rails at
/// their full length — one seam for the shelf and the page it opens means a test can script both
/// with the same fake, and the limits below sit next to the shelf's in one file.
///
/// Auto-disposed and not cached: unlike the feed these are opened deliberately, one at a time, and
/// a listener who taps "See all" is asking for the current answer.

/// The web's `/app/jump-back-in`: fifty, against the shelf's twelve.
const jumpBackInPageLength = 50;

/// The web's `/app/made-for-you`: twelve, which is also the shelf's — the page differs in shape,
/// not in how much it holds.
const madeForYouPageLength = 12;

Duration? _noAutoRetry(int attempt, Object error) => null;

final jumpBackInPageProvider = FutureProvider.autoDispose<List<RecentItem>>(
  (ref) => _source(ref).jumpBackIn(limit: jumpBackInPageLength),
  retry: _noAutoRetry,
);

final madeForYouPageProvider = FutureProvider.autoDispose<List<DailyMix>>(
  (ref) => _source(ref).dailyMixes(limit: madeForYouPageLength),
  retry: _noAutoRetry,
);

/// Both pages sit behind the auth gate, so "no hub" is a bug rather than a state to render.
HomeSource _source(Ref ref) {
  final source = ref.watch(homeSourceProvider);
  if (source == null) {
    throw StateError('no active hub — home is behind the auth gate');
  }
  return source;
}
