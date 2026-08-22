import 'dart:math' as math;

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
import '../devices/device_picker_sheet.dart';
import '../lyrics/lyrics_screen.dart';
import 'queue_sheet.dart';
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

/// The now-playing screen.
class FullPlayerScreen extends ConsumerWidget {
  const FullPlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Signing out, or clearing the queue from the queue sheet, leaves this screen with nothing to
    // show. Closing it is the only honest response — the alternative is a frozen player over a
    // signed-out app.
    ref.listen(currentTrackProvider, (_, next) {
      if (next == null) Navigator.of(context).maybePop();
    });

    final snapshot = ref.watch(playerStateProvider);
    final track = snapshot.current;
    if (track == null) return const SizedBox.shrink();

    final t = ref.t;
    final theme = Theme.of(context);

    return _DragToDismiss(
      child: Scaffold(
        backgroundColor: ChordiaColors.pane,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _Header(context: snapshot.context),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, constraints) => CoverArt(
                          sha256: artHashOf(track.coverUrl),
                          size: math.min(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: ChordiaColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
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
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () => showSleepTimerSheet(context),
                      icon: Icon(
                        snapshot.sleepTimer == null
                            ? Icons.bedtime_outlined
                            : Icons.bedtime,
                        color: snapshot.sleepTimer == null
                            ? ChordiaColors.mutedForeground
                            : ChordiaColors.accent,
                      ),
                      label: Text(t(PlayerKeys.sleepTimerTitle)),
                    ),
                    TextButton.icon(
                      onPressed: () => showLyricsSheet(context),
                      icon: const Icon(
                        Icons.lyrics_outlined,
                        color: ChordiaColors.mutedForeground,
                      ),
                      label: Text(t(CatalogKeys.lyricsHeading)),
                    ),
                    TextButton.icon(
                      onPressed: () => showQueueSheet(context),
                      icon: const Icon(
                        Icons.queue_music_rounded,
                        color: ChordiaColors.mutedForeground,
                      ),
                      label: Text(t(PlayerKeys.queueTitle)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.context});

  /// Where this queue was started from, or null when it was not started from anywhere nameable.
  final PlayContext? context;

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
                  color: ChordiaColors.mutedForeground,
                  letterSpacing: 0.6,
                ),
              ),
              if (source != null)
                Text(
                  source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
            ],
          ),
        ),
        // Occupies the slot that used to be an empty spacer balancing the collapse button, so the
        // label above stays optically centred and this costs no extra width.
        IconButton(
          onPressed: () => showDevicePickerSheet(buildContext),
          tooltip: t(PlayerKeys.devicesTitle),
          icon: const Icon(Icons.devices_rounded),
        ),
      ],
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
            inactiveTrackColor: ChordiaColors.line,
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
                  color: ChordiaColors.mutedForeground,
                ),
              ),
              Text(
                formatPlaybackTime(duration),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ChordiaColors.mutedForeground,
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
    final actions = ref.watch(playerActionsProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          onPressed: () => actions.setShuffle(!shuffle),
          tooltip: t(PlayerKeys.controlsShuffle),
          isSelected: shuffle,
          icon: Icon(
            Icons.shuffle_rounded,
            color: shuffle
                ? ChordiaColors.accent
                : ChordiaColors.mutedForeground,
          ),
        ),
        IconButton(
          onPressed: actions.prev,
          tooltip: t(PlayerKeys.controlsPrevious),
          iconSize: 40,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        _PlayButton(playing: playing, buffering: buffering),
        IconButton(
          onPressed: actions.next,
          tooltip: t(PlayerKeys.controlsNext),
          iconSize: 40,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        IconButton(
          onPressed: actions.cycleRepeat,
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
                ? ChordiaColors.mutedForeground
                : ChordiaColors.accent,
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
          if (buffering)
            const SizedBox(
              width: 68,
              height: 68,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: ChordiaColors.accent,
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
    child: Transform.translate(offset: Offset(0, _offset), child: widget.child),
  );
}
