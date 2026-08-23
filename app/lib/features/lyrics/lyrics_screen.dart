import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart' hide PlaybackState;
import 'package:flutter/material.dart';
// `ScrollDirection` is the rendering library's; `material.dart` does not re-export it, and it is
// what tells a user-scroll notification apart from the view's own programmatic scroll.
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/artist_links.dart';
import 'data/lyrics_providers.dart';
import 'data/lyrics_repository.dart';

/// The lyrics of whatever is playing, as a tab of the full player.
///
/// A tab rather than a sheet stacked over the player, which is where the web client puts it on a
/// phone. As a sheet behind a text button it was a feature you had to already know existed.
class LyricsPanel extends ConsumerWidget {
  const LyricsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final track = ref.watch(currentTrackProvider);
    if (track == null) return _Message(t(PlayerKeys.lyricsNothingPlaying));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LyricsHeader(track: track),
        Expanded(
          // Keyed by track, so moving to the next song rebuilds the view from scratch instead of
          // animating the old song's scroll offset onto new words.
          child: LyricsBody(track: track, key: ValueKey(track.id)),
        ),
      ],
    );
  }
}

/// What is being read, above the words.
///
/// The now-playing tab is one tap away but not on screen, and lyrics with no title over them read
/// as a page that has lost track of the song. The credited names are links here for the same
/// reason they are everywhere else — the guest verse you just heard is the one you want to open.
class _LyricsHeader extends StatelessWidget {
  const _LyricsHeader({required this.track});

  final PlayerTrack track;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
          ArtistLinks(
            artists: playerArtistRefs(track.artists),
            fallbackName: track.artist,
            fallbackId: track.artistId,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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

/// The size lyrics are set at, from `LyricsView.tsx:219`.
///
/// The web wraps the whole lyric block in `font-bold text-3xl leading-snug tracking-tight
/// md:text-4xl`. `md:` is the desktop step, so a phone renders the base: `text-3xl` is 30px,
/// `leading-snug` is 1.375, and `tracking-tight` is -0.025em, which at 30px is -0.75.
///
/// Not a detail. This view was set at `titleMedium` — 16sp, the same as a track row's subtitle —
/// and type size is the entire read of a lyrics surface: at body size the same words are a
/// paragraph of text that happens to be in the player, and at 30/700 they are a lyrics screen.
/// Colour is deliberately absent, because it is the one thing that varies per line.
const _lyricType = TextStyle(
  fontSize: 30,
  height: 1.375,
  fontWeight: FontWeight.w700,
  letterSpacing: -0.75,
);

/// Lyrics with no timing: a page of text, scrolled by hand.
class _PlainLyrics extends StatelessWidget {
  const _PlainLyrics({required this.lines});

  final List<LyricsLine> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // `text-foreground/90` (LyricsView.tsx:229). Nothing is active in an untimed document, so
    // every line sits at the same strength rather than one being picked out of the others.
    final style = _lyricType.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
    );
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
      itemCount: lines.length,
      // `space-y-3`: 12px between lines, which is half of 12 on each of two neighbours.
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

  /// Jumps to where a line starts.
  ///
  /// The one thing synced lyrics are for beyond reading along: the chorus is four taps away rather
  /// than a scrub-and-guess on a 3px-per-second bar. Following resumes, because a seek IS a
  /// statement about where the listener wants to be.
  void _seekToLine(int index) {
    if (index < 0 || index >= _starts.length) return;
    ref
        .read(playerActionsProvider)
        .seek(Duration(milliseconds: _starts[index]));
    if (!_following) setState(() => _following = true);
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
              return _SeekableLine(
                key: _keys[i],
                onTap: () => _seekToLine(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: AnimatedDefaultTextStyle(
                    // `transition-colors duration-300` (LyricsView.tsx:224). Colour is the only
                    // thing that moves between the two states — the weight is 700 throughout, so
                    // a line does not reflow as it becomes current.
                    duration: const Duration(milliseconds: 300),
                    style: _lyricType.copyWith(
                      color: isActive
                          ? theme.colorScheme.onSurface
                          // `text-muted-foreground/50` (:230). The lines around the one being
                          // sung recede hard, which is what makes the current line findable
                          // without reading any of them.
                          : theme.colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.5,
                            ),
                    ),
                    child: Text(widget.lines[i].text),
                  ),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// One tappable lyric line.
///
/// A `GestureDetector` rather than an `InkWell`: a ripple across a full-width line of lyrics reads
/// as the view breaking, and the feedback that matters is the playhead moving.
class _SeekableLine extends StatelessWidget {
  const _SeekableLine({required this.onTap, required this.child, super.key});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: child,
  );
}
