import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart' show PlayContext;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../data/playback.dart';
import 'track_row.dart';

/// A lazy list of tracks that plays the WHOLE list from whichever row is tapped.
///
/// This is the piece that makes "Playing from …" and scrobble attribution correct, and the reason
/// it is a widget rather than a loop at each call site: a screen that built its own rows would have
/// to remember to pass the whole list and the right [playContext] every time, and the one that
/// forgot would queue a single track with no source — which nothing on screen would reveal until a
/// month of listening history came back wrong.
class SliverTrackList extends ConsumerWidget {
  const SliverTrackList({
    required this.tracks,
    required this.playContext,
    super.key,
    this.numbered = false,
    this.showArtists = true,
    this.groupByDisc = false,
  });

  final List<BrowseTrack> tracks;

  /// Where this list came from. Null only where there is genuinely no source to name.
  final PlayContext? playContext;

  /// Album ordering: show each track's number instead of forty copies of the same cover.
  final bool numbered;

  final bool showArtists;

  /// Inserts a "Disc N" heading when a release actually has more than one disc.
  final bool groupByDisc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = _entries(tracks, groupByDisc: groupByDisc);
    return SliverList.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final disc = entry.discHeading;
        if (disc != null) return _DiscHeading(disc: disc);
        return TrackRow(
          track: tracks[entry.trackIndex],
          trackNumber: numbered
              // The list position is the fallback, not the truth: a track with no number in its
              // tags still has a place in the running order.
              ? (tracks[entry.trackIndex].trackNo ?? entry.trackIndex + 1)
              : null,
          showArtists: showArtists,
          onTap: () => playTracksFrom(
            ref,
            tracks: tracks,
            index: entry.trackIndex,
            playContext: playContext,
          ),
        );
      },
    );
  }
}

/// One row: either a disc heading, or a position in [SliverTrackList.tracks].
///
/// Positions are carried explicitly because the heading rows shift them — deriving the track from
/// the list index would play the wrong song on any multi-disc release.
@immutable
class _Entry {
  const _Entry.track(this.trackIndex) : discHeading = null;
  const _Entry.disc(this.discHeading) : trackIndex = -1;

  final int trackIndex;
  final int? discHeading;
}

List<_Entry> _entries(List<BrowseTrack> tracks, {required bool groupByDisc}) {
  if (!groupByDisc) {
    return [for (var i = 0; i < tracks.length; i++) _Entry.track(i)];
  }
  // A single disc needs no heading — "Disc 1" above every track of a normal album is noise.
  final discs = tracks.map((track) => track.discNo ?? 1).toSet();
  if (discs.length < 2) {
    return [for (var i = 0; i < tracks.length; i++) _Entry.track(i)];
  }

  final entries = <_Entry>[];
  int? current;
  for (var i = 0; i < tracks.length; i++) {
    final disc = tracks[i].discNo ?? 1;
    if (disc != current) {
      entries.add(_Entry.disc(disc));
      current = disc;
    }
    entries.add(_Entry.track(i));
  }
  return entries;
}

class _DiscHeading extends ConsumerWidget {
  const _DiscHeading({required this.disc});

  final int disc;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(
      ref.t(CatalogKeys.albumDisc, {'n': disc}),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
