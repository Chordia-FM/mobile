import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/playback/notification_art.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import 'full_player.dart';

/// Height of the docked bar, art and all. Exported so a layout can reserve the same space.
const double kMiniPlayerHeight = 64;

/// The bar docked above the tab bar.
///
/// Renders nothing at all until there is something playing — not an empty shell, not a disabled
/// row — so the tab bar sits flush against the content on a fresh install, and the player's arrival
/// is what makes room for it.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    if (track == null) return const SizedBox.shrink();

    final t = ref.t;
    final theme = Theme.of(context);
    final playing = ref.watch(playerStateProvider.select((s) => s.playing));
    final actions = ref.watch(playerActionsProvider);

    return Material(
      color: ChordiaColors.paneRaised,
      child: Semantics(
        button: true,
        label: t(PlayerKeys.expandedExpand),
        child: GestureDetector(
          // A flick upward opens the full player: the bar's position invites that gesture, and
          // people try it before they try tapping.
          onVerticalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -200) openFullPlayer(context);
          },
          child: InkWell(
            onTap: () => openFullPlayer(context),
            child: SizedBox(
              height: kMiniPlayerHeight,
              child: Column(
                children: [
                  const _ProgressHairline(),
                  Expanded(
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        CoverArt(sha256: artHashOf(track.coverUrl), size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: ChordiaColors.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => actions.setPlaying(!playing),
                          tooltip: t(
                            playing
                                ? PlayerKeys.controlsPause
                                : PlayerKeys.controlsPlay,
                          ),
                          icon: Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 28,
                          ),
                        ),
                        IconButton(
                          onPressed: actions.next,
                          tooltip: t(PlayerKeys.controlsNext),
                          icon: const Icon(Icons.skip_next_rounded, size: 26),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The two-pixel line across the top of the bar.
///
/// Its own widget because it is the only part of the mini player that follows the playhead: kept
/// inline, the whole bar — cover, two text lines, two buttons — would re-lay-out twice a second.
class _ProgressHairline extends ConsumerWidget {
  const _ProgressHairline();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final duration = ref.watch(playerStateProvider.select((s) => s.duration));
    final position = ref.watch(playerPositionProvider).value ?? Duration.zero;
    final progress = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return LinearProgressIndicator(
      value: progress,
      minHeight: 2,
      backgroundColor: ChordiaColors.line,
      color: ChordiaColors.accent,
    );
  }
}
