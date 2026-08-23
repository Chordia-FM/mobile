/// What this phone shows while another device owns playback.
library;

import 'dart:async';
import 'dart:math' as math;

// Prefixed: both Flutter's material library and the mesh export a `RepeatMode`, and the one this
// screen means is the queue's.
import 'package:chordia_sync/chordia_sync.dart' as sync show RepeatMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/mesh/mirror.dart';
import '../../data/mesh/providers.dart';
import '../../data/playback/notification_art.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../player/player_format.dart';
import 'device_picker_sheet.dart';

/// How often the mirrored playhead is redrawn.
///
/// The owner publishes a position once a second; between those it is interpolated forward, and a
/// four-times-a-second redraw is what makes that read as a moving scrubber rather than a clock.
/// Only the scrubber rebuilds at this rate — see [_MirrorScrubber].
const Duration kMirrorTick = Duration(milliseconds: 250);

/// Height of the docked mirror bar. Matches the mini player's so the shell reserves one number.
const double kMirrorBarHeight = 64;

/// Opens the mirror over everything, tab bar included.
void openMirrorPlayer(BuildContext context) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute<void>(builder: (_) => const MirrorPlayerScreen()));

/// The remote player, with working transport.
///
/// Every control here sends a command to the device that owns playback rather than touching the
/// local engine, which is the whole difference between a mirror and a second player: two devices
/// sounding at once is the failure this exists to prevent. The routing itself is not decided in
/// this file — [MeshTransport] makes that call for the whole app, so a screen cannot get it wrong
/// in one place and right in another.
class MirrorPlayerScreen extends ConsumerWidget {
  const MirrorPlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mirror = ref.watch(mirrorStateProvider);
    // The owner stopped, or handed playback here. Either way there is nothing remote left to
    // mirror, and staying would leave a frozen screen over a working player.
    ref.listen(mirrorStateProvider, (_, next) {
      if (!next.active) Navigator.of(context).maybePop();
    });
    if (!mirror.active) return const SizedBox.shrink();

    final t = ref.t;
    final theme = Theme.of(context);
    final track = mirror.track;
    final transport = ref.watch(meshTransportProvider);

    return Scaffold(
      backgroundColor: ChordiaColors.pane,
      appBar: AppBar(
        backgroundColor: ChordiaColors.pane,
        title: Text(
          t(PlayerKeys.devicesPlayingOn, {
            'device': mirror.deviceLabel ?? t(PlayerKeys.remoteUnnamedDevice),
          }),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        actions: [
          IconButton(
            onPressed: () => showDevicePickerSheet(context),
            tooltip: t(PlayerKeys.devicesTitle),
            icon: const Icon(Icons.speaker_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) => CoverArt(
                        sha256: artHashOf(track?.coverUrl),
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
                      track?.title ?? t(PlayerKeys.notPlaying),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track?.artist ?? '',
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
              const _MirrorScrubber(),
              const SizedBox(height: 4),
              _MirrorTransport(mirror: mirror),
              const SizedBox(height: 8),
              // The one control that is NOT a remote command: it asks the owner to hand playback
              // over, queue and playhead included.
              TextButton.icon(
                onPressed: transport.bringHere,
                icon: const Icon(Icons.phone_iphone_rounded),
                label: Text(t(PlayerKeys.devicesPlayHere)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// The docked bar shown in place of the mini player while another device is playing.
class MirrorBar extends ConsumerWidget {
  const MirrorBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mirror = ref.watch(mirrorStateProvider);
    if (!mirror.active) return const SizedBox.shrink();

    final t = ref.t;
    final theme = Theme.of(context);
    final track = mirror.track;
    final transport = ref.watch(meshTransportProvider);

    return Material(
      color: ChordiaColors.paneRaised,
      child: InkWell(
        onTap: () => openMirrorPlayer(context),
        child: SizedBox(
          height: kMirrorBarHeight,
          child: Row(
            children: [
              const SizedBox(width: 8),
              CoverArt(sha256: artHashOf(track?.coverUrl), size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track?.title ?? t(PlayerKeys.notPlaying),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      t(PlayerKeys.devicesPlayingOn, {
                        'device':
                            mirror.deviceLabel ??
                            t(PlayerKeys.remoteUnnamedDevice),
                      }),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ChordiaColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => transport.setPlaying(!mirror.playing),
                tooltip: t(
                  mirror.playing
                      ? PlayerKeys.controlsPause
                      : PlayerKeys.controlsPlay,
                ),
                icon: Icon(
                  mirror.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 28,
                ),
              ),
              IconButton(
                onPressed: transport.next,
                tooltip: t(PlayerKeys.controlsNext),
                icon: const Icon(Icons.skip_next_rounded, size: 26),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// The seek bar and its two time labels, over an interpolated playhead.
///
/// Its own stateful widget for the same reason the local player's scrubber is: this is the only
/// part of the mirror that moves between position ticks, and rebuilding the art and the title four
/// times a second to advance a bar by two pixels is what makes a player feel cheap.
class _MirrorScrubber extends ConsumerStatefulWidget {
  const _MirrorScrubber();

  @override
  ConsumerState<_MirrorScrubber> createState() => _MirrorScrubberState();
}

class _MirrorScrubberState extends ConsumerState<_MirrorScrubber> {
  Timer? _ticker;

  /// Where the thumb is being held, in milliseconds. Null when nobody is dragging.
  double? _dragMs;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(kMirrorTick, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Straight off the controller rather than out of the state: interpolation is a function of
    // *now*, so a value cached in a provider would be stale the instant it was published.
    final playhead = ref
        .read(playerSyncControllerProvider)
        .interpolatedPosition();
    final transport = ref.read(meshTransportProvider);

    final totalMs = playhead.durationMs.toDouble();
    final seekable = totalMs > 0;
    final currentMs = (_dragMs ?? playhead.positionMs.toDouble()).clamp(
      0.0,
      seekable ? totalMs : 0.0,
    );

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
              setState(() => _dragMs = null);
              transport.seek(Duration(milliseconds: value.round()));
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
                formatPlaybackTime(Duration(milliseconds: playhead.durationMs)),
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

class _MirrorTransport extends ConsumerWidget {
  const _MirrorTransport({required this.mirror});

  final MirrorState mirror;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final transport = ref.watch(meshTransportProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          onPressed: () => transport.setShuffle(!mirror.shuffle),
          tooltip: t(PlayerKeys.controlsShuffle),
          isSelected: mirror.shuffle,
          icon: Icon(
            Icons.shuffle_rounded,
            color: mirror.shuffle
                ? ChordiaColors.accent
                : ChordiaColors.mutedForeground,
          ),
        ),
        IconButton(
          onPressed: transport.prev,
          tooltip: t(PlayerKeys.controlsPrevious),
          iconSize: 40,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        SizedBox(
          width: 68,
          height: 68,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (mirror.buffering)
                const SizedBox(
                  width: 68,
                  height: 68,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ChordiaColors.accent,
                  ),
                ),
              FilledButton(
                onPressed: () => transport.setPlaying(!mirror.playing),
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  minimumSize: const Size(60, 60),
                  padding: EdgeInsets.zero,
                ),
                child: Semantics(
                  label: t(
                    mirror.playing
                        ? PlayerKeys.controlsPause
                        : PlayerKeys.controlsPlay,
                  ),
                  button: true,
                  child: Icon(
                    mirror.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 36,
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: transport.next,
          tooltip: t(PlayerKeys.controlsNext),
          iconSize: 40,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        IconButton(
          onPressed: transport.cycleRepeat,
          tooltip: t(switch (mirror.repeat) {
            sync.RepeatMode.off => PlayerKeys.controlsRepeatOff,
            sync.RepeatMode.all => PlayerKeys.controlsRepeatAll,
            sync.RepeatMode.one => PlayerKeys.controlsRepeatOne,
          }),
          isSelected: mirror.repeat != sync.RepeatMode.off,
          icon: Icon(
            mirror.repeat == sync.RepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            color: mirror.repeat == sync.RepeatMode.off
                ? ChordiaColors.mutedForeground
                : ChordiaColors.accent,
          ),
        ),
      ],
    );
  }
}
