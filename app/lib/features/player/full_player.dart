import 'dart:async';
import 'dart:math' as math;

import 'package:chordia_sync/chordia_sync.dart' hide PlaybackState;
// Flutter's material library exports a `RepeatMode` of its own (for repeating animations). The
// one this screen means is the queue's.
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/accent/accent_fill.dart';
import '../../data/accent/accent_scope.dart';
import '../../data/playback/notification_art.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/tokens.dart';
import '../catalog/data/catalog_providers.dart';
import '../catalog/widgets/artist_links.dart';
import '../devices/device_picker_sheet.dart';
import '../catalog/widgets/entity_menu.dart';
import '../lyrics/data/lyrics_providers.dart';
import '../lyrics/lyrics_screen.dart';
import 'now_playing_detail.dart';
import 'play_context_nav.dart';
import 'player_badges.dart';
import 'player_menu.dart';
import 'player_format.dart';
import 'quality_sheet.dart';
import 'queue_panel.dart';
import 'sleep_timer_sheet.dart';

/// Opens the now-playing screen over everything, tab bar included.
///
/// The root navigator, not the shell's: the full player is not part of any tab's history, and
/// pushing it into one would make it reappear when the listener came back to that tab.
void openFullPlayer(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(fullPlayerRoute());

Route<void> fullPlayerRoute() => PageRouteBuilder<void>(
  // Not opaque, so the screen the listener came from is still drawn behind: it is what they see
  // while dragging the player down, and a black void there reads as a crash.
  opaque: false,
  transitionDuration: const Duration(milliseconds: 320),
  reverseTransitionDuration: const Duration(milliseconds: 240),
  pageBuilder: (_, _, _) => const FullPlayerScreen(),
  transitionsBuilder: (_, animation, _, child) => SlideTransition(
    position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    ),
    child: child,
  ),
);

/// The three views of the player, in the order the web client lists them.
enum PlayerTab { nowPlaying, lyrics, queue }

/// The now-playing screen.
class FullPlayerScreen extends ConsumerStatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  ConsumerState<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends ConsumerState<FullPlayerScreen> {
  PlayerTab _tab = PlayerTab.nowPlaying;

  @override
  Widget build(BuildContext context) {
    // Signing out, or clearing the queue from the queue tab, leaves this screen with nothing to
    // show. Closing it is the only honest response — the alternative is a frozen player over a
    // signed-out app.
    ref.listen(currentTrackProvider, (_, next) {
      if (next == null) Navigator.of(context).maybePop();
    });

    final snapshot = ref.watch(playerStateProvider);
    final track = snapshot.current;
    if (track == null) return const SizedBox.shrink();

    final theme = Theme.of(context);

    // Asked for as soon as the player opens, not when the lyrics tab is entered: the tab has to be
    // able to say up front whether this track has any, and the repository behind this caches both
    // answers — the miss included — so the ask costs one request per track per session.
    final lyrics = ref.watch(trackLyricsProvider(track.id));
    final hasLyrics = lyrics.hasValue
        ? (lyrics.value?.lines.isNotEmpty ?? false)
        // Loading, or a read that failed in a tunnel. Neither is evidence about the song, so the
        // tab stays reachable and the panel explains itself.
        : null;

    return _DragToDismiss(
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _Header(
                  context: snapshot.context,
                  sleepTimerOn: snapshot.sleepTimer != null,
                ),
              ),
              Expanded(
                child: switch (_tab) {
                  PlayerTab.nowPlaying => _NowPlaying(snapshot: snapshot),
                  PlayerTab.lyrics => const LyricsPanel(),
                  PlayerTab.queue => const QueuePanel(),
                },
              ),
              PlayerTabBar(
                current: _tab,
                hasLyrics: hasLyrics,
                onSelect: (tab) => setState(() => _tab = tab),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The artwork, the credits, the transport — and everything the web keeps below the fold.
///
/// **This scrolls**, which it did not before. `ExpandedPlayer.tsx:259` puts the whole now-playing
/// tab inside the sheet's scrolling body and hangs `<NowPlayingPanel …/>` off the bottom of it
/// (:392-402), so the web phone player continues past the transport into the album, the play
/// count, a card per credited artist and the file-quality readout. Mobile's was a fixed `Column`
/// with the artwork in an `Expanded`: there was no below-the-fold region for any of that to live
/// in, so none of it existed on the phone.
class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.snapshot});

  final PlayerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final track = snapshot.current;
    if (track == null) return const SizedBox.shrink();

    return ListView(
      // `space-y-5 pb-6` on the web's now-playing column, inside the body's `px-5`.
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        // The artwork is the drag handle, exactly as `{...drag.scrollHandleProps}` makes it on the
        // web (ExpandedPlayer.tsx:263). Once this tab scrolls, the scrollable wins every vertical
        // drag from the ancestor detector — so without a handle, making the player scroll would
        // have silently cost it its throw-away gesture.
        _DismissDragHandle(
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) => CoverArt(
                sha256: artHashOf(track.coverUrl),
                // `aspect-square w-full max-w-[min(78vw,26rem)]`: as wide as the column allows,
                // capped at 78% of the viewport and again at 26rem.
                size: math.min(
                  constraints.maxWidth,
                  math.min(MediaQuery.sizeOf(context).width * 0.78, 416),
                ),
                borderRadius: ChordiaRadius.xlAll,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          track.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      PlayerTrackBadges(track: track),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Each credited artist its own link, exactly as in a track row: the guest on a
                  // feature is the one thing a listener most often wants to open from here, and a
                  // joined string threw that away.
                  ArtistLinks(
                    artists: playerArtistRefs(track.artists),
                    fallbackName: track.artist,
                    fallbackId: track.artistId,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    linkStyle: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            // The heart the player never had. It sits where the web puts it — beside the title,
            // not behind a menu — because it is the one action a listener takes mid-song.
            LikeButton(trackId: track.id),
          ],
        ),
        const SizedBox(height: 12),
        const _Scrubber(),
        const SizedBox(height: 4),
        _Transport(
          playing: snapshot.playing,
          buffering: snapshot.buffering,
          shuffle: snapshot.shuffle,
          repeat: snapshot.repeat,
        ),
        // What tier is actually sounding, and a warning when the connection or the adapter has
        // taken it down from what was chosen. The controller computed both from the first day
        // and nothing on screen ever said so.
        const QualityButton(),
        const SizedBox(height: 20),
        NowPlayingDetail(track: track),
      ],
    );
  }
}

/// The heart, wherever the player shows one.
class LikeButton extends ConsumerWidget {
  const LikeButton({required this.trackId, super.key, this.iconSize});

  final String trackId;
  final double? iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final liked = ref.watch(likedTrackIdsProvider).value?.contains(trackId);
    final theme = Theme.of(context);

    return IconButton(
      // Until the liked set has loaded there is nothing to flip, and a heart that reports the wrong
      // state is worse than one that is briefly unavailable.
      onPressed: liked == null
          ? null
          : () async {
              try {
                await ref.read(likedTrackIdsProvider.notifier).toggle(trackId);
              } on Object {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(content: Text(t(ErrorsKeys.changeFailed))),
                    );
                }
              }
            },
      iconSize: iconSize,
      tooltip: t(
        liked ?? false ? LibraryKeys.likedRemove : LibraryKeys.likedSave,
      ),
      icon: Icon(
        liked ?? false ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: liked ?? false ? theme.colorScheme.primary : null,
      ),
    );
  }
}

/// The player's view switcher, pinned to the bottom edge.
///
/// Underline tabs rather than a segmented pill or a row of text buttons — the same shape the web
/// client uses on a phone, for the same reason: flush against the bottom border it reads as a
/// native tab bar, and it puts lyrics and the queue where somebody would look for them instead of
/// behind a control they have to already know about.
class PlayerTabBar extends ConsumerWidget {
  const PlayerTabBar({
    required this.current,
    required this.onSelect,
    required this.hasLyrics,
    super.key,
  });

  final PlayerTab current;
  final ValueChanged<PlayerTab> onSelect;

  /// Whether the playing track has lyrics, or null while that is not yet known.
  ///
  /// A definite `false` disables the tab and says why, rather than opening a view whose only
  /// content is an apology.
  final bool? hasLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Semantics(
        label: t(PlayerKeys.expandedTabs),
        container: true,
        child: Row(
          children: [
            _Tab(
              icon: Icons.album_rounded,
              label: t(PlayerKeys.expandedNowPlaying),
              active: current == PlayerTab.nowPlaying,
              onTap: () => onSelect(PlayerTab.nowPlaying),
            ),
            _Tab(
              // A microphone on a stand, the same glyph the web client's lyrics control uses.
              icon: Icons.mic_external_on_rounded,
              label: t(PlayerKeys.expandedLyrics),
              active: current == PlayerTab.lyrics,
              disabledReason: hasLyrics == false
                  ? t(PlayerKeys.lyricsNone)
                  : null,
              onTap: () => onSelect(PlayerTab.lyrics),
            ),
            _Tab(
              icon: Icons.queue_music_rounded,
              label: t(PlayerKeys.expandedQueue),
              active: current == PlayerTab.queue,
              onTap: () => onSelect(PlayerTab.queue),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.disabledReason,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  /// Why this tab cannot be opened, or null when it can. Carried as the tooltip and the
  /// accessibility hint, so the tab is never simply inert.
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reason = disabledReason;
    final colour = reason != null
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
        : active
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;

    final tab = Semantics(
      button: true,
      selected: active,
      enabled: reason == null,
      hint: reason,
      child: InkWell(
        onTap: reason == null ? onTap : null,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            if (active)
              const Positioned(
                left: 20,
                right: 20,
                top: 0,
                // A 2px rule reads as a capsule at any corner the scale offers; the web writes
                // exactly this mark as `h-0.5 rounded-full` (`charts.tsx:1362`). It is also
                // `bg-primary`, so the blanket rule repaints it on every tick along with the play
                // button an inch above it — and like the bar's hairline, nobody drags it.
                child: SizedBox(
                  height: 2,
                  child: AccentSurface(
                    borderRadius: ChordiaRadius.pill,
                    child: SizedBox.expand(),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: colour),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colour,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Expanded(
      child: reason == null ? tab : Tooltip(message: reason, child: tab),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.context, required this.sleepTimerOn});

  /// Where this queue was started from, or null when it was not started from anywhere nameable.
  final PlayContext? context;

  final bool sleepTimerOn;

  @override
  Widget build(BuildContext buildContext, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(buildContext);
    final source = context;

    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(buildContext).maybePop(),
          tooltip: t(PlayerKeys.expandedCollapse),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                source == null
                    ? t(PlayerKeys.expandedNowPlaying)
                    : t(PlayerKeys.nowPlayingPlayingFrom),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.6,
                ),
              ),
              // The source LEADS somewhere. It was dead text: the player named the album or the
              // playlist a queue came from and touching it did nothing, so the one screen a
              // listener spends their time on had no way back to what they were listening to.
              if (source != null)
                _PlayingFrom(source: source, player: buildContext),
            ],
          ),
        ),
        IconButton(
          onPressed: () => showSleepTimerSheet(buildContext),
          tooltip: t(PlayerKeys.sleepTimerTitle),
          icon: Icon(
            sleepTimerOn ? Icons.bedtime : Icons.bedtime_outlined,
            color: sleepTimerOn ? theme.colorScheme.primary : null,
          ),
        ),
        IconButton(
          onPressed: () => showDevicePickerSheet(buildContext),
          tooltip: t(PlayerKeys.devicesTitle),
          icon: const Icon(Icons.devices_rounded),
        ),
        const _MoreButton(),
      ],
    );
  }
}

/// The source of the queue, as a link back to it — and its own menu on a long press.
class _PlayingFrom extends StatelessWidget {
  const _PlayingFrom({required this.source, required this.player});

  final PlayContext source;

  /// The full player's context: navigating away has to dismiss it first.
  final BuildContext player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final menu = playContextMenu(source);
    return InkWell(
      onTap: () => openPlayContext(player, source),
      onLongPress: menu == null
          ? null
          : () => unawaited(showEntityMenu(context, menu)),
      child: Text(
        source.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelLarge,
      ),
    );
  }
}

/// Everything the player can do that is not a transport control.
///
/// One menu rather than a row of icons: the phone's header has room for three targets, and the web
/// keeps the same set (equalizer, quality, the track's own actions) behind its `…` for the same
/// reason.
class _MoreButton extends ConsumerWidget {
  const _MoreButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    if (track == null) return const SizedBox.shrink();
    return EntityMenuButton(
      menu: (page, sheetRef) => playerTrackMenu(page, sheetRef, track),
    );
  }
}

/// The seek bar and the two time labels.
///
/// Everything that follows the playhead lives inside this one widget, which is what keeps the
/// twice-a-second rebuild off the art, the title and the transport.
class _Scrubber extends ConsumerStatefulWidget {
  const _Scrubber();

  @override
  ConsumerState<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends ConsumerState<_Scrubber> {
  /// Where the thumb is being held, in milliseconds. Null when nobody is dragging.
  double? _dragMs;

  /// A seek that has been asked for but whose effect has not yet come back in a position sample.
  ///
  /// Held so the thumb does not snap back to the old playhead for the half-second between letting
  /// go and the engine reporting where it landed.
  int? _pending;

  @override
  Widget build(BuildContext context) {
    ref.listen(playerPositionProvider, (_, next) {
      final pending = _pending;
      final position = next.value;
      if (pending == null || position == null) return;
      if ((position.inMilliseconds - pending).abs() < 700) {
        setState(() => _pending = null);
      }
    });

    final theme = Theme.of(context);
    final duration = ref.watch(playerStateProvider.select((s) => s.duration));
    final position = ref.watch(playerPositionProvider).value ?? Duration.zero;

    final totalMs = duration.inMilliseconds.toDouble();
    final seekable = totalMs > 0;
    final currentMs =
        (_dragMs ?? _pending?.toDouble() ?? position.inMilliseconds.toDouble())
            .clamp(0.0, seekable ? totalMs : 0.0);

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            inactiveTrackColor: theme.colorScheme.outline,
          ),
          child: Slider(
            value: currentMs,
            max: seekable ? totalMs : 1,
            label: formatPlaybackTime(
              Duration(milliseconds: currentMs.round()),
            ),
            onChanged: seekable
                ? (value) => setState(() => _dragMs = value)
                : null,
            onChangeEnd: (value) {
              final target = value.round();
              setState(() {
                _dragMs = null;
                _pending = target;
              });
              ref
                  .read(playerActionsProvider)
                  .seek(Duration(milliseconds: target));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatPlaybackTime(Duration(milliseconds: currentMs.round())),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                formatPlaybackTime(duration),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Transport extends ConsumerWidget {
  const _Transport({
    required this.playing,
    required this.buffering,
    required this.shuffle,
    required this.repeat,
  });

  final bool playing;
  final bool buffering;
  final bool shuffle;
  final RepeatMode repeat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    // Read in the callbacks rather than watched: these actions never change identity in a way this
    // row draws, and watching them builds the audio handler for a screen that may only be reading
    // lyrics.
    PlayerActions actions() => ref.read(playerActionsProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          onPressed: () => actions().setShuffle(!shuffle),
          tooltip: t(PlayerKeys.controlsShuffle),
          isSelected: shuffle,
          icon: Icon(
            Icons.shuffle_rounded,
            color: shuffle
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        IconButton(
          onPressed: () => actions().prev(),
          tooltip: t(PlayerKeys.controlsPrevious),
          iconSize: 40,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        _PlayButton(playing: playing, buffering: buffering),
        IconButton(
          onPressed: () => actions().next(),
          tooltip: t(PlayerKeys.controlsNext),
          iconSize: 40,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        IconButton(
          onPressed: () => actions().cycleRepeat(),
          tooltip: t(switch (repeat) {
            RepeatMode.off => PlayerKeys.controlsRepeatOff,
            RepeatMode.all => PlayerKeys.controlsRepeatAll,
            RepeatMode.one => PlayerKeys.controlsRepeatOne,
          }),
          isSelected: repeat != RepeatMode.off,
          icon: Icon(
            repeat == RepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            color: repeat == RepeatMode.off
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _PlayButton extends ConsumerWidget {
  const _PlayButton({required this.playing, required this.buffering});

  final bool playing;
  final bool buffering;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return SizedBox(
      width: 68,
      height: 68,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // A ring around the button rather than a spinner in place of it: replacing the glyph
          // would take the control away at the exact moment somebody is most likely to press it.
          //
          // On the live accent rather than the resting one, because the disc it encircles is a
          // `FilledButton` and the theme's button style already follows every tick. Two colours
          // 2px apart on the same 68px control, disagreeing for a second and a half of every fade,
          // is worse than either of them alone. A ring cannot carry a gradient any more than a CSS
          // border can, so in Gradient mode it takes `frame.accent` — the palette's blend, which is
          // exactly what `--primary` is there.
          if (buffering)
            SizedBox(
              width: 68,
              height: 68,
              child: AccentBuilder(
                builder: (context, frame, _) => CircularProgressIndicator(
                  strokeWidth: 2,
                  color: frame.accent,
                ),
              ),
            ),
          FilledButton(
            onPressed: () =>
                ref.read(playerActionsProvider).setPlaying(!playing),
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              minimumSize: const Size(60, 60),
              padding: EdgeInsets.zero,
            ),
            child: Semantics(
              label: t(
                playing ? PlayerKeys.controlsPause : PlayerKeys.controlsPlay,
              ),
              button: true,
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 36,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lets the whole screen be dragged downward and thrown away.
///
/// The gesture is the one every music app has, and the reason it is hand-rolled rather than a
/// `DismissiblePageRoute` is that the screen has to follow the finger *and* spring back when the
/// drag does not earn a dismissal — a route transition driven by a plain animation does neither.
///
/// A list inside a tab wins the vertical drag over this, because the scrollable is deeper in the
/// hit test: reading lyrics or reordering the queue scrolls, and the artwork still throws away.
class _DragToDismiss extends StatefulWidget {
  const _DragToDismiss({required this.child});

  final Widget child;

  @override
  State<_DragToDismiss> createState() => _DragToDismissState();
}

class _DragToDismissState extends State<_DragToDismiss>
    with SingleTickerProviderStateMixin {
  /// Fraction of the screen height a drag has to cover before letting go dismisses.
  static const _dismissFraction = 0.22;

  /// Downward speed, in logical pixels per second, that dismisses however short the drag was.
  static const _dismissVelocity = 700.0;

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _settle,
    curve: Curves.easeOutCubic,
  );

  double _offset = 0;
  double _springFrom = 0;

  @override
  void initState() {
    super.initState();
    _curve.addListener(
      () => setState(() => _offset = _springFrom * (1 - _curve.value)),
    );
  }

  @override
  void dispose() {
    _curve.dispose();
    _settle.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails details) {
    if (_settle.isAnimating) _settle.stop();
    setState(() => _offset = math.max(0, _offset + details.delta.dy));
  }

  void _onEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final travelled =
        _offset > MediaQuery.sizeOf(context).height * _dismissFraction;
    if (velocity > _dismissVelocity || travelled) {
      Navigator.of(context).maybePop();
      return;
    }
    _springFrom = _offset;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onVerticalDragUpdate: _onUpdate,
    onVerticalDragEnd: _onEnd,
    child: Transform.translate(
      offset: Offset(0, _offset),
      child: _DismissDrag(
        onUpdate: _onUpdate,
        onEnd: _onEnd,
        child: widget.child,
      ),
    ),
  );
}

/// The dismiss gesture, offered to anything inside the player that should act as its handle.
///
/// The detector above is an ANCESTOR of the tabs, so a scrollable tab beats it in the gesture
/// arena — which is what makes the queue and the lyrics scroll instead of throwing the player away.
/// Once the now-playing tab scrolls too, something inside it has to opt back in, and the web picks
/// the same thing: the artwork (`drag.scrollHandleProps`, ExpandedPlayer.tsx:263).
class _DismissDrag extends InheritedWidget {
  const _DismissDrag({
    required this.onUpdate,
    required this.onEnd,
    required super.child,
  });

  final ValueChanged<DragUpdateDetails> onUpdate;
  final ValueChanged<DragEndDetails> onEnd;

  static _DismissDrag? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DismissDrag>();

  /// The callbacks are the state's own methods and never change identity, so a dependent has
  /// nothing to rebuild for.
  @override
  bool updateShouldNotify(_DismissDrag oldWidget) => false;
}

/// Makes its child a place the player can be dragged away from.
///
/// Deeper in the hit test than the enclosing scrollable, so it wins the vertical drag — a drag that
/// starts on the artwork dismisses, and one that starts anywhere else scrolls.
class _DismissDragHandle extends StatelessWidget {
  const _DismissDragHandle({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final drag = _DismissDrag.maybeOf(context);
    if (drag == null) return child;
    return GestureDetector(
      onVerticalDragUpdate: drag.onUpdate,
      onVerticalDragEnd: drag.onEnd,
      child: child,
    );
  }
}
