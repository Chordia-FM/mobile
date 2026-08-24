import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/accent/accent_fill.dart';
import '../../data/mesh/providers.dart';
import '../../data/playback/notification_art.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../catalog/widgets/artist_links.dart';
import '../catalog/widgets/entity_menu.dart';
import '../devices/mirror_player.dart';
import 'full_player.dart';
import 'play_context_nav.dart';
import 'player_badges.dart';
import 'player_menu.dart';

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
    // Another device owning playback takes this slot instead: what is playing is real and
    // controllable, it simply is not sounding here. Showing the local bar as well would offer two
    // transports for one stream.
    if (ref.watch(mirrorStateProvider).active) return const MirrorBar();

    final track = ref.watch(currentTrackProvider);
    if (track == null) return const SizedBox.shrink();

    final t = ref.t;
    final theme = Theme.of(context);
    final playing = ref.watch(playerStateProvider.select((s) => s.playing));

    return KeyedSubtree(
      // The one context the player can navigate from: the bar lives under the shell's route, so it
      // knows which tab is showing. See `play_context_nav.dart`.
      key: playerNavHostKey,
      child: Material(
        // `--surface-strong` with a hairline over it, exactly as `PlayerBar.tsx` paints itself:
        // fixed chrome that content passes under, opaque on purpose so a bright cover sliding
        // beneath does not read as dirt.
        color: context.surfaces.surfaceStrong,
        shape: Border(top: BorderSide(color: theme.colorScheme.outline)),
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
              // The same actions the full player's ⋮ offers, without opening it first — the phone's
              // equivalent of right-clicking the web's player bar.
              onLongPress: () => unawaited(
                showEntityMenu(
                  context,
                  (page, sheetRef) => playerTrackMenu(page, sheetRef, track),
                ),
              ),
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
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                    PlayerTrackBadges(track: track),
                                  ],
                                ),
                                // The bar opens the player and the credited names open their
                                // artists. Nested targets, which the web could not do at all with a
                                // button inside a button: here the names are spans carrying their own
                                // recognizers, and a deeper hit wins the gesture arena.
                                ArtistLinks(
                                  artists: playerArtistRefs(track.artists),
                                  fallbackName: track.artist,
                                  fallbackId: track.artistId,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  linkStyle: theme.textTheme.bodySmall
                                      ?.copyWith(
                                        color: theme.colorScheme.onSurface,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          // The heart, the same one the full player shows: liking the song you are
                          // hearing is the action a listener takes without opening anything.
                          LikeButton(trackId: track.id, iconSize: 22),
                          IconButton(
                            onPressed: () => ref
                                .read(playerActionsProvider)
                                .setPlaying(!playing),
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
                            onPressed: () =>
                                ref.read(playerActionsProvider).next(),
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
      ),
    );
  }
}

/// The two-pixel line across the top of the bar.
///
/// Its own widget because it is the only part of the mini player that follows the playhead: kept
/// inline, the whole bar — cover, two text lines, two buttons — would re-lay-out twice a second.
///
/// Hand-rolled rather than a [LinearProgressIndicator], and that is the accent's doing rather than
/// a layout preference. `PlayerBar.tsx:197` writes the filled part as `h-0.5 bg-primary`, so the
/// blanket rule in `styles.css` puts `--accent-gradient` on it and repaints it on every tick along
/// with every other solid accent surface in the app. A `LinearProgressIndicator` takes one flat
/// `color` and has nowhere to put a gradient, so it would sit at the resting accent while the
/// play button two inches to its right was mid-fade.
///
/// Nobody drags this line — the full player owns the scrubber — so there is no held thumb for a
/// cross-fade to disagree with, which is the case [AccentSurface] warns about.
class _ProgressHairline extends ConsumerWidget {
  const _ProgressHairline();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final duration = ref.watch(playerStateProvider.select((s) => s.duration));
    final position = ref.watch(playerPositionProvider).value ?? Duration.zero;
    final progress = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return SizedBox(
      height: 2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: theme.colorScheme.outline),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress,
              child: const AccentSurface(child: SizedBox.expand()),
            ),
          ),
        ],
      ),
    );
  }
}
