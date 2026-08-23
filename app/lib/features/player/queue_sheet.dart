import 'package:chordia_sync/chordia_sync.dart' hide PlaybackState;
// Flutter's material library exports a `RepeatMode` of its own (for repeating animations). The
// one this screen means is the queue's.
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/playback/notification_art.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import 'player_format.dart';

/// Opens the queue over the player.
Future<void> showQueueSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => const _QueueSheet(),
);

class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final snapshot = ref.watch(playerStateProvider);
    final actions = ref.watch(playerActionsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => DecoratedBox(
        decoration: const BoxDecoration(
          color: ChordiaColors.paneRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const _Grabber(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Row(
                children: [
                  Text(
                    t(PlayerKeys.queueTitle),
                    style: theme.textTheme.titleMedium,
                  ),
                  const Spacer(),
                  if (snapshot.repeat == RepeatMode.one)
                    Tooltip(
                      message: t(PlayerKeys.queueRepeatOne),
                      child: const Icon(
                        Icons.repeat_one_rounded,
                        color: ChordiaColors.accent,
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: snapshot.queue.isEmpty
                  ? Center(
                      child: Text(
                        t(PlayerKeys.queueEmpty),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ChordiaColors.mutedForeground,
                        ),
                      ),
                    )
                  : ReorderableListView.builder(
                      scrollController: scrollController,
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: snapshot.queue.length,
                      onReorderItem: actions.reorderQueue,
                      itemBuilder: (context, index) {
                        final track = snapshot.queue[index];
                        final current = index == snapshot.currentIndex;
                        return ListTile(
                          // The queue entry id, not the track id: the same track can sit in a
                          // queue twice, and two rows with one key is a reorder that scrambles.
                          key: ValueKey(track.qid ?? '${track.id}-$index'),
                          onTap: () => actions.jumpTo(index),
                          leading: CoverArt(
                            sha256: artHashOf(track.coverUrl),
                            size: 40,
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: current
                                ? theme.textTheme.bodyMedium?.copyWith(
                                    color: ChordiaColors.accent,
                                    fontWeight: FontWeight.w600,
                                  )
                                : theme.textTheme.bodyMedium,
                          ),
                          subtitle: Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formatPlaybackTime(
                                  Duration(milliseconds: track.durationMs),
                                ),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: ChordiaColors.mutedForeground,
                                ),
                              ),
                              IconButton(
                                onPressed: () => actions.removeFromQueue(index),
                                tooltip: t(PlayerKeys.queueRemoveFromQueue),
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.drag_handle_rounded,
                                    color: ChordiaColors.mutedForeground,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 4,
    margin: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: ChordiaColors.line,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}
