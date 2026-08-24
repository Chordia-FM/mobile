import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'notification_art.dart';

/// The content hash of the cover the player is showing, or null when nothing is playing and when
/// the entry carries art the Hub does not address by hash.
///
/// This is the one place that says "the cover on screen right now", and it says it as a **hash**
/// rather than a URL on purpose: the hash is what the art cache is keyed by, what the accent
/// extraction is cached by, and what makes the same sleeve reached through two different hub URLs
/// one piece of work instead of two.
///
/// It is derived rather than pushed — the web pushes the same fact into its accent engine from the
/// player's sync layer (`setAccentCover` in `frontend/src/lib/settings/store.ts`), which is what a
/// framework without a dependency graph has to do. Here the graph already exists: anything that
/// wants to follow the playing cover watches this, and a consumer that is not mounted costs
/// nothing.
final currentCoverHashProvider = Provider<String?>(
  (ref) => artHashOf(ref.watch(currentTrackProvider)?.coverUrl),
);
