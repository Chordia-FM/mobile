import 'dart:async';

import 'package:chordia_sync/chordia_sync.dart' hide PlaybackState;
// Flutter's material library exports a `RepeatMode` of its own (for repeating animations). The
// one this panel means is the queue's.
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/playback/notification_art.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../catalog/widgets/artist_links.dart';
import '../catalog/widgets/entity_menu.dart';
import 'player_badges.dart';
import 'player_format.dart';
import 'player_menu.dart';

/// What is playing next, as a tab of the full player.
///
/// A tab rather than a sheet over the player: that is where the web client keeps it, and a queue
/// stacked on top of the now-playing screen made "queue" a thing you had to already know was
/// there.
///
/// Shows the same three things the web's `QueuePanel` does, and for the same reasons:
///
/// - **Next up**, which is `queue.slice(currentIndex + 1)` — a queue view is about what has not
///   happened yet;
/// - **Autoplay**, a heading at the point the listener's own queue ended and the station took over.
///   `PlayerTrack.autoplay` has carried that flag since the queue was written and nothing read it,
///   so a run of songs nobody remembers queueing read as the player having lost track of itself;
/// - **Then repeating**, the wrapped slice under repeat-all, because "what plays after the last
///   one" is the exact question this panel exists to answer.
class QueuePanel extends ConsumerWidget {
  const QueuePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final snapshot = ref.watch(playerStateProvider);
    final actions = ref.watch(playerActionsProvider);
    final current = snapshot.current;

    if (snapshot.queue.isEmpty || current == null) {
      return Center(
        child: Text(
          t(PlayerKeys.queueEmpty),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // Repeat-one is not a queue at all: this one song plays until the mode changes, and listing
    // forty entries under it would be a promise the transport is not going to keep.
    if (snapshot.repeat == RepeatMode.one) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          QueueRow(track: current, current: true),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              t(PlayerKeys.queueRepeatOne),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    final index = snapshot.currentIndex;
    final nextUp = snapshot.upcoming;
    // Everything up to and including the current entry plays again when the queue wraps.
    final wrapped = snapshot.repeat == RepeatMode.all && index >= 0
        ? snapshot.queue.sublist(0, index + 1)
        : const <PlayerTrack>[];
    // Appended entries are always a contiguous tail, so one index describes the split.
    final autoplayFrom = nextUp.indexWhere((track) => track.autoplay ?? false);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: QueueRow(track: current, current: true)),
        if (nextUp.isNotEmpty)
          SliverToBoxAdapter(child: _Heading(t(PlayerKeys.queueNextUp))),
        SliverReorderableList(
          itemCount: nextUp.length,
          // The list is the "Next up" SLICE and the queue's own indices are absolute; the offset
          // is what keeps a drag from moving a different song than the one under the finger.
          onReorderItem: (from, to) => actions.reorderQueue(
            nextUpIndex(index, from),
            nextUpIndex(index, to),
          ),
          itemBuilder: (context, i) {
            final track = nextUp[i];
            final queueIndex = nextUpIndex(index, i);
            return Column(
              // The queue entry id, not the track id: the same track can sit in a queue twice, and
              // two rows with one key is a reorder that scrambles.
              key: ValueKey(track.qid ?? '${track.id}-$queueIndex'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (i == autoplayFrom)
                  _Heading(t(PlayerKeys.queueAutoplayNext)),
                QueueRow(
                  track: track,
                  dragIndex: i,
                  onPlay: () => actions.jumpTo(queueIndex),
                  onRemove: () => actions.removeFromQueue(queueIndex),
                ),
              ],
            );
          },
        ),
        if (wrapped.isNotEmpty) ...[
          SliverToBoxAdapter(child: _Heading(t(PlayerKeys.queueThenRepeating))),
          SliverList.builder(
            itemCount: wrapped.length,
            // Dimmed and inert: these are a preview of the second pass, not entries you can
            // reorder or remove — doing either to them means editing the queue above.
            itemBuilder: (context, i) =>
                Opacity(opacity: 0.6, child: QueueRow(track: wrapped[i])),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

/// The absolute queue index of the nth entry in the "Next up" slice.
///
/// A named function with a test rather than `+ 1` inline in a callback: getting it wrong moves or
/// removes a different track than the one touched, and nothing on screen would say so.
int nextUpIndex(int currentIndex, int sliceIndex) =>
    currentIndex + 1 + sliceIndex;

class _Heading extends StatelessWidget {
  const _Heading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

/// One queue entry.
class QueueRow extends ConsumerWidget {
  const QueueRow({
    required this.track,
    super.key,
    this.dragIndex,
    this.current = false,
    this.onPlay,
    this.onRemove,
  });

  final PlayerTrack track;

  /// Position in the reorderable slice, for the drag handle. Absent on a row that cannot move.
  final int? dragIndex;

  final bool current;
  final VoidCallback? onPlay;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final drag = dragIndex;

    return ListTile(
      // The row plays the entry and the credited names open their artists. Two tap targets in one
      // row, never nested: the names are spans with their own recognizers, which win the gesture
      // arena over the tile because they are deeper in the hit test.
      onTap: onPlay,
      // The same menu the player's own ⋮ opens, minus the rows that belong to the player rather
      // than to this song, plus the removal this row owns.
      onLongPress: () => unawaited(
        showEntityMenu(
          context,
          (page, sheetRef) => playerTrackMenu(
            page,
            sheetRef,
            track,
            onPlay: onPlay,
            onRemove: onRemove,
            playbackControls: false,
          ),
        ),
      ),
      leading: CoverArt(sha256: artHashOf(track.coverUrl), size: 40),
      title: Row(
        children: [
          Flexible(
            child: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: current
                  ? theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    )
                  : theme.textTheme.bodyMedium,
            ),
          ),
          PlayerTrackBadges(track: track),
        ],
      ),
      subtitle: ArtistLinks(
        artists: playerArtistRefs(track.artists),
        fallbackName: track.artist,
        fallbackId: track.artistId,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatPlaybackTime(Duration(milliseconds: track.durationMs)),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              tooltip: t(PlayerKeys.queueRemoveFromQueue),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          if (drag != null)
            ReorderableDragStartListener(
              index: drag,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.drag_handle_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
