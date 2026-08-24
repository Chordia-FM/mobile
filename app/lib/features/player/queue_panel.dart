import 'dart:async';

import 'package:chordia_sync/chordia_sync.dart' hide PlaybackState;
import 'package:flutter/foundation.dart' show listEquals;
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
import '../catalog/widgets/list_row.dart';
import 'player_badges.dart';
import 'player_format.dart';
import 'player_menu.dart';

/// The recently-played list, most-recent first.
///
/// [QueueController] has kept this since the queue was written (`queue_controller.dart:102`, capped
/// at `kHistoryLimit`) and the device mesh already publishes it, but nothing in the app could read
/// it: `PlayerSnapshot` has no `history` field, so the half of the queue panel that shows what you
/// just heard had no data behind it. This is that missing wire.
///
/// A provider of its own rather than a field on the snapshot: the snapshot is watched by the mini
/// bar, the transport, the scrubber and the tab bar, and none of them draws history. Folding it in
/// would rebuild all of them every time a track changed — for a list only this one tab reads.
final playerHistoryProvider =
    NotifierProvider<PlayerHistoryNotifier, List<PlayerTrack>>(
      PlayerHistoryNotifier.new,
    );

/// Republishes [QueueController.history] whenever the queue reports a change.
class PlayerHistoryNotifier extends Notifier<List<PlayerTrack>> {
  @override
  List<PlayerTrack> build() {
    final queue = ref.watch(queueControllerProvider);
    // Synchronous delivery, exactly as `PlayerStateNotifier` takes it: the controller flushes one
    // event at the end of each command, so this sees a settled queue and never a half-applied one.
    final subscription = queue.events.listen((_) {
      final next = List<PlayerTrack>.unmodifiable(queue.history);
      if (!listEquals(next, state)) state = next;
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    return List<PlayerTrack>.unmodifiable(queue.history);
  }
}

/// The two halves of the panel, in the order the web's segmented control lists them.
enum QueueTab { next, history }

/// What is playing next and what was just played, as a tab of the full player.
///
/// A tab rather than a sheet over the player: that is where the web client keeps it, and a queue
/// stacked on top of the now-playing screen made "queue" a thing you had to already know was
/// there.
///
/// Two segments, as in `QueuePanel.tsx:63-75` — and full width for the reason recorded there, that
/// as an inline pill "Recently played" was cut off mid-word. Under **Next up** it shows the same
/// three things the web does, and for the same reasons:
///
/// - **Next up**, which is `queue.slice(currentIndex + 1)` — a queue view is about what has not
///   happened yet;
/// - **Autoplay**, a heading at the point the listener's own queue ended and the station took over.
///   `PlayerTrack.autoplay` has carried that flag since the queue was written and nothing read it,
///   so a run of songs nobody remembers queueing read as the player having lost track of itself;
/// - **Then repeating**, the wrapped slice under repeat-all, because "what plays after the last
///   one" is the exact question this panel exists to answer.
///
/// **Recently played** is `QueuePanel.tsx:77-97`: every row plays that track again on a tap
/// (`onClick={() => playNow(track)}`), because re-playing the song that just went past is the
/// entire point of a history list. Without it the phone's queue panel was half a panel — the paged
/// listening history on the Insights tab is several screens away and answers a different question.
class QueuePanel extends ConsumerStatefulWidget {
  const QueuePanel({super.key});

  @override
  ConsumerState<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends ConsumerState<QueuePanel> {
  QueueTab _tab = QueueTab.next;

  @override
  Widget build(BuildContext context) {
    final t = ref.t;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Semantics(
            label: t(PlayerKeys.queueTitle),
            container: true,
            child: SegmentedButton<QueueTab>(
              // Full width, and no selected-tick: the check steals the space the longer of the two
              // labels needs, which is the same problem the web solved by sizing each segment from
              // its own label rather than splitting the width evenly.
              expandedInsets: EdgeInsets.zero,
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: QueueTab.next,
                  label: Text(t(PlayerKeys.queueNextUp)),
                ),
                ButtonSegment(
                  value: QueueTab.history,
                  label: Text(t(PlayerKeys.queueRecentlyPlayed)),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (selection) =>
                  setState(() => _tab = selection.first),
            ),
          ),
        ),
        Expanded(
          child: switch (_tab) {
            QueueTab.next => const _NextUp(),
            QueueTab.history => const _RecentlyPlayed(),
          },
        ),
      ],
    );
  }
}

/// What has been played, newest first, each row a tap away from being played again.
class _RecentlyPlayed extends ConsumerWidget {
  const _RecentlyPlayed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final history = ref.watch(playerHistoryProvider);
    // Read in the callback rather than watched, exactly as the transport does it: watching the
    // actions builds the whole audio handler, and a list of what was played draws none of it.
    PlayerActions actions() => ref.read(playerActionsProvider);

    if (history.isEmpty) {
      return Center(
        child: Text(
          t(PlayerKeys.queueNothingPlayed),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: history.length,
      // `playNow`, not `jumpTo`: a history entry has no index in the live queue — the controller
      // records the track that was leaving, not where it sat — so replaying it means putting it in
      // front, which is exactly what the web row does.
      itemBuilder: (context, i) => QueueRow(
        track: history[i],
        onPlay: () => actions().playNow(history[i]),
      ),
    );
  }
}

/// What plays next, and after that.
class _NextUp extends ConsumerWidget {
  const _NextUp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final snapshot = ref.watch(playerStateProvider);
    PlayerActions actions() => ref.read(playerActionsProvider);
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
          onReorderItem: (from, to) => actions().reorderQueue(
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
                  onPlay: () => actions().jumpTo(queueIndex),
                  onRemove: () => actions().removeFromQueue(queueIndex),
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

    return ListRow(
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
