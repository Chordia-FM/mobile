import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart' hide PlaybackState;
import 'package:flutter/material.dart';
// `ScrollDirection` is the rendering library's; `material.dart` does not re-export it, and it is
// what tells a user-scroll notification apart from the view's own programmatic scroll.
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'data/lyrics_providers.dart';
import 'data/lyrics_repository.dart';

/// Opens the lyrics for whatever is playing.
Future<void> showLyricsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LyricsSheet(),
    );

/// The lyrics view, sized as a sheet over the player.
class LyricsSheet extends ConsumerWidget {
  const LyricsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final track = ref.watch(currentTrackProvider);

    // A fixed height rather than a `DraggableScrollableSheet`: that widget resizes the sheet from
    // the scroll position of a controller it supplies, and this view owns its own scrolling to
    // follow the song. Two controllers over one list means the sheet fights the auto-scroll.
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: ChordiaColors.paneRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const _Grabber(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t(PlayerKeys.lyricsTitle),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              Expanded(
                child: track == null
                    ? _Message(t(PlayerKeys.lyricsNothingPlaying))
                    // Keyed by track, so moving to the next song rebuilds the view from scratch
                    // instead of animating the old song's scroll offset onto new words.
                    : LyricsBody(track: track, key: ValueKey(track.id)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The lyrics of one track: synced lines that follow the playhead, or a plain reading.
class LyricsBody extends ConsumerWidget {
  const LyricsBody({required this.track, super.key});

  final PlayerTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final lyrics = ref.watch(trackLyricsProvider(track.id));

    return lyrics.when(
      loading: () => _Message(t(PlayerKeys.lyricsLoading)),
      // A failed read is not "this song has no lyrics" — the repository refuses to cache it as one,
      // and neither does the view claim it.
      error: (_, _) => _Message(t(ErrorsKeys.failedToLoad)),
      data: (data) {
        if (data == null || data.lines.isEmpty) {
          return _Message(t(PlayerKeys.lyricsNone));
        }
        return isSynced(data)
            ? _SyncedLyrics(lines: data.lines)
            : _PlainLyrics(lines: data.lines);
      },
    );
  }
}

/// Lyrics with no timing: a page of text, scrolled by hand.
class _PlainLyrics extends StatelessWidget {
  const _PlainLyrics({required this.lines});

  final List<LyricsLine> lines;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: ChordiaColors.foreground,
      height: 1.6,
    );
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
      itemCount: lines.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(lines[i].text, style: style),
      ),
    );
  }
}

/// Line-synced lyrics, following the playhead.
class _SyncedLyrics extends ConsumerStatefulWidget {
  const _SyncedLyrics({required this.lines});

  final List<LyricsLine> lines;

  @override
  ConsumerState<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends ConsumerState<_SyncedLyrics> {
  final _controller = ScrollController();

  /// One key per line, so the active one can be scrolled to by its real position. Lines wrap to
  /// different heights, so there is no item extent to compute an offset from.
  late List<GlobalKey> _keys;

  /// The document's start offsets, built once: see [lyricStarts].
  late List<int> _starts;

  /// Whether the view is still following the song.
  ///
  /// Touching the list stops it. Somebody scrolling back to re-read a verse is reading, and yanking
  /// them forward half a second later is the single most irritating thing a lyrics view can do.
  bool _following = true;

  int _active = -1;

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.lines.length, (_) => GlobalKey());
    _starts = lyricStarts(widget.lines);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToActive({required bool animate}) {
    if (_active < 0 || _active >= _keys.length) return;
    final context = _keys[_active].currentContext;
    // Off-screen lines are not laid out, so there is nothing to scroll to; the next line change
    // that lands inside the viewport picks the following back up.
    if (context == null) return;
    unawaited(
      Scrollable.ensureVisible(
        context,
        // A third of the way down rather than centred: the line being sung reads better with the
        // lines it is heading into visible beneath it.
        alignment: 0.35,
        duration: animate ? const Duration(milliseconds: 320) : Duration.zero,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final theme = Theme.of(context);

    // Selected down to the line index, so this rebuilds when the *line* changes and not on each of
    // the engine's two position samples a second.
    final active = ref.watch(
      playerPositionProvider.select(
        (position) => switch (position.value) {
          null => -1,
          final at => activeLyricLine(_starts, at.inMilliseconds),
        },
      ),
    );

    if (active != _active) {
      _active = active;
      if (_following) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToActive(animate: true),
        );
      }
    }

    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          // `UserScrollNotification` fires only for a drag or a fling, never for the programmatic
          // scroll above — which is what keeps the view from stopping its own following.
          onNotification: (notification) {
            if (notification.direction != ScrollDirection.idle && _following) {
              setState(() => _following = false);
            }
            return false;
          },
          child: ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 80),
            itemCount: widget.lines.length,
            itemBuilder: (context, i) {
              final isActive = i == _active;
              return Padding(
                key: _keys[i],
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style:
                      theme.textTheme.titleMedium?.copyWith(
                        height: 1.5,
                        color: isActive
                            ? ChordiaColors.foreground
                            : ChordiaColors.mutedForeground,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ) ??
                      const TextStyle(),
                  child: Text(widget.lines[i].text),
                ),
              );
            },
          ),
        ),
        if (!_following)
          Positioned(
            left: 0,
            right: 0,
            bottom: 20,
            child: Center(
              child: FilledButton.tonalIcon(
                onPressed: () {
                  setState(() => _following = true);
                  _scrollToActive(animate: true);
                },
                icon: const Icon(Icons.my_location_rounded, size: 18),
                label: Text(t(PlayerKeys.lyricsReturnToCurrent)),
              ),
            ),
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: ChordiaColors.mutedForeground),
      ),
    ),
  );
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 4,
    margin: const EdgeInsets.only(top: 10, bottom: 6),
    decoration: BoxDecoration(
      color: ChordiaColors.line,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}
