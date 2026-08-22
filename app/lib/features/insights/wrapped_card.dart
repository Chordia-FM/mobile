import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The card's pixel size. Portrait 4:5, which is what every social surface crops to least.
const wrappedCardWidth = 1080.0;
const wrappedCardHeight = 1350.0;

/// One ranked entry on the card.
@immutable
class WrappedCardEntry {
  const WrappedCardEntry({required this.name, this.cover});

  final String name;

  /// Already-decoded cover bytes, or null when this entity has no artwork the Hub could serve.
  /// A missing cover degrades to a tinted tile carrying the entry's initial — never to a failed
  /// render, because one art-less track should not cost somebody their whole card.
  final Uint8List? cover;
}

/// Everything the card draws, already translated and formatted.
///
/// The card takes strings rather than a [WrappedReport] on purpose: it is also what the share
/// preview shows, and a widget that formats numbers is a widget that has to know the locale, the
/// catalogs and the period — three things the caller already has in hand.
@immutable
class WrappedCardData {
  const WrappedCardData({
    required this.heading,
    required this.subheading,
    required this.handle,
    required this.heroValue,
    required this.heroLabel,
    required this.statLine,
    required this.topArtistsLabel,
    required this.topArtists,
    required this.topTracksLabel,
    required this.topTracks,
    required this.footer,
    this.topGenreLabel,
    this.topGenre,
  });

  final String heading;
  final String subheading;

  /// "@handle", or empty when the report is not attributable to a handle.
  final String handle;

  final String heroValue;
  final String heroLabel;
  final String statLine;
  final String topArtistsLabel;
  final List<WrappedCardEntry> topArtists;
  final String topTracksLabel;
  final List<WrappedCardEntry> topTracks;
  final String footer;
  final String? topGenreLabel;
  final String? topGenre;
}

/// Rows each column of the card holds.
const _cardRows = 5;

/// The shareable Wrapped card.
///
/// Laid out in the card's own pixel units — a `SizedBox` of exactly [wrappedCardWidth] by
/// [wrappedCardHeight] — so the capture is 1:1 at a pixel ratio of one whatever the phone's screen
/// is doing. Scaling for display is the caller's job (a `FittedBox`), which changes how it is
/// painted but not the size it lays out at, and therefore not the size of the PNG.
class WrappedCard extends StatelessWidget {
  const WrappedCard({required this.data, super.key, this.boundaryKey});

  final WrappedCardData data;

  /// The key [captureWrappedCard] captures through.
  final Key? boundaryKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      key: boundaryKey,
      child: SizedBox(
        width: wrappedCardWidth,
        height: wrappedCardHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  scheme.primary.withValues(alpha: 0.55),
                  scheme.surface,
                ),
                scheme.surface,
              ],
            ),
          ),
          child: DefaultTextStyle(
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 34,
              height: 1.2,
              decoration: TextDecoration.none,
            ),
            child: Padding(
              padding: const EdgeInsets.all(72),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.heading,
                    style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    data.subheading,
                    style: TextStyle(
                      fontSize: 36,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 56),
                  Text(
                    data.heroValue,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 148,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    data.heroLabel,
                    style: TextStyle(
                      fontSize: 38,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    data.statLine,
                    style: TextStyle(
                      fontSize: 32,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 48),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _CardColumn(
                            label: data.topArtistsLabel,
                            entries: data.topArtists,
                            circular: true,
                          ),
                        ),
                        const SizedBox(width: 32),
                        Expanded(
                          child: _CardColumn(
                            label: data.topTracksLabel,
                            entries: data.topTracks,
                            circular: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (data.topGenre case final genre?) ...[
                    Text(
                      data.topGenreLabel ?? '',
                      style: TextStyle(
                        fontSize: 26,
                        letterSpacing: 1.2,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      genre,
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  Row(
                    children: [
                      Text(
                        data.footer,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        data.handle,
                        style: TextStyle(
                          fontSize: 30,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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

class _CardColumn extends StatelessWidget {
  const _CardColumn({
    required this.label,
    required this.entries,
    required this.circular,
  });

  final String label;
  final List<WrappedCardEntry> entries;

  /// Artists get round thumbnails, tracks square ones — the same shapes the rest of the app uses.
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 26,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        for (final (index, entry) in entries.take(_cardRows).indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                _Thumb(entry: entry, circular: circular),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    '${index + 1}. ${entry.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 30, color: scheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One cover, or a tinted tile carrying the entry's initial.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.entry, required this.circular});

  final WrappedCardEntry entry;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    final scheme = Theme.of(context).colorScheme;
    final shape = circular
        ? const CircleBorder()
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    final bytes = entry.cover;

    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: SizedBox(
        width: size,
        height: size,
        child: bytes == null
            ? ColoredBox(
                color: scheme.primaryContainer,
                child: Center(
                  child: Text(
                    entry.name.runes.isEmpty
                        ? '?'
                        : String.fromCharCode(
                            entry.name.runes.first,
                          ).toUpperCase(),
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              )
            : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}

/// Rasterises the card behind [boundaryKey] to PNG bytes.
///
/// The pixel ratio is one because the card lays out at its own pixel size, so the result is exactly
/// [wrappedCardWidth] by [wrappedCardHeight] whatever the device's screen density is — a card that
/// came out 3240px wide on one phone and 2160 on another would be the same card at two sizes.
///
/// Waits for the end of the current frame first: a boundary that has been built but not yet painted
/// has no layer to rasterise, which is the difference between a card and an exception.
Future<Uint8List> captureWrappedCard(GlobalKey boundaryKey) async {
  // Resolved before the await, not after: holding a `BuildContext` across an asynchronous gap is
  // how a widget that has since been disposed gets asked to paint. The render object it names
  // outlives the gap on its own.
  final boundary = boundaryKey.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) {
    throw StateError(
      'The Wrapped card is not mounted, so it cannot be shared.',
    );
  }
  // Only when it would actually paint differently. Waiting unconditionally hangs anywhere that
  // does not raise frames on its own — a widget test outside `pump`, most notably — and costs a
  // frame everywhere else for a boundary that is already on screen and up to date.
  if (boundary.debugNeedsPaint) await _nextFrame();
  final image = await boundary.toImage();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('The Wrapped card could not be encoded as an image.');
    }
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Resolves once the frame currently being built has been painted.
Future<void> _nextFrame() {
  final binding = WidgetsBinding.instance;
  final completer = Completer<void>();
  binding.addPostFrameCallback((_) => completer.complete());
  // A binding that is idle raises no frame on its own, so one is asked for. Harmless when a frame
  // was already scheduled.
  binding.scheduleFrame();
  return completer.future;
}
