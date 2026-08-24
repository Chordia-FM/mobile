import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../app/providers.dart';
import '../data/accent/accent_fill.dart';
import '../data/accent/accent_scope.dart';
import 'tokens.dart';

/// Album, artist or playlist artwork.
///
/// Reads through [ArtCache], so a cover is fetched once at a width the Hub actually derives and
/// then comes off disk — which is also what puts a `file://` path within reach of the media
/// notification, whose native side cannot use our pinned HTTP client.
///
/// ## The missing-artwork tile is accent-derived, and that is the point
///
/// A browse grid is mostly placeholder tiles, so they are among the largest accent-coloured areas
/// in the app — the web says exactly that at `styles.css:1044-1049`, where `.accent-art` is defined
/// precisely so a chosen colour reaches "most of what someone actually looks at". This used to
/// paint `surfaceContainerHighest`, a flat grey, which is a large part of why the phone's colour
/// scheme read as not working at all: the accent was on buttons and nowhere else.
class CoverArt extends ConsumerStatefulWidget {
  const CoverArt({
    required this.sha256,
    required this.size,
    super.key,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.fallbackIcon = PhosphorIconsFill.musicNotes,
    this.fallbackInitial,
    this.semanticLabel,
  });

  /// The Hub content address, or null for an entity with no artwork.
  final String? sha256;

  /// Logical size. The pixel width actually requested is this times the device pixel ratio,
  /// snapped up to the Hub's ladder.
  final double size;

  final BorderRadius? borderRadius;

  /// Circular for artists, rectangular for everything else.
  final BoxShape shape;
  final IconData fallbackIcon;

  /// When there is no image, show this name's initial as a monogram on a glossy accent sphere
  /// instead of the glyph — `CoverArt.tsx`'s `fallbackInitial`, used for artist avatars "so an
  /// imageless artist reads as a tasteful monogram" rather than a flat wash.
  final String? fallbackInitial;

  final String? semanticLabel;

  @override
  ConsumerState<CoverArt> createState() => _CoverArtState();
}

class _CoverArtState extends ConsumerState<CoverArt> {
  File? _file;
  bool _resolved = false;

  /// The request in flight, so a late answer for a cover we have navigated away from cannot
  /// overwrite the one now on screen.
  Object? _token;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(CoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sha256 != widget.sha256 || oldWidget.size != widget.size) {
      _load();
    }
  }

  Future<void> _load() async {
    final sha = widget.sha256;
    if (sha == null || sha.isEmpty) {
      setState(() {
        _file = null;
        _resolved = true;
      });
      return;
    }

    final token = Object();
    _token = token;

    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final file = await ref
        .read(artCacheProvider)
        .file(sha, width: (widget.size * ratio).ceil());

    if (!mounted || !identical(_token, token)) return;
    setState(() {
      _file = file;
      _resolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // `rounded-md` (10px), the ONE corner value `CoverArt.tsx` uses at every size — its `rounded`
    // prop is only ever overridden to `rounded-full` or `rounded-none`. A radius proportional to
    // the tile (what this used to do) made a 48px row cover almost square and a 200px hero visibly
    // rounder than the same artwork on the desktop.
    final radius = widget.shape == BoxShape.circle
        ? null
        : (widget.borderRadius ?? ChordiaRadius.mdAll);

    final file = _file;
    Widget placeholder({required bool settled}) => _Placeholder(
      size: widget.size,
      icon: widget.fallbackIcon,
      initial: widget.fallbackInitial,
      settled: settled,
    );
    final child = file == null
        // Only shimmer while there is still something to wait for; a cover the Hub does not have
        // would otherwise pulse forever as if it were about to arrive.
        ? placeholder(settled: _resolved)
        : Image.file(
            file,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => placeholder(settled: true),
          );

    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: ClipPath(
          clipper: ShapeBorderClipper(
            shape: widget.shape == BoxShape.circle
                ? const CircleBorder()
                : RoundedRectangleBorder(borderRadius: radius!),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The tile shown wherever an entity has no artwork.
///
/// Two treatments, both lifted from `CoverArt.tsx`:
///
/// - With an [initial]: the glossy accent "sphere" of its `MONOGRAM_BG` — a light highlight up and
///   left, the accent through the middle, a deeper edge — under a bold monogram. Its own note says
///   this is so an imageless artist "reads as a bold, distinct chip rather than a flat wash".
/// - Without one: `.accent-art` (styles.css:1050-1056), a 135° accent gradient, under the fallback
///   glyph at `size-1/3` and 30% of the foreground.
///
/// Both are written in `var(--primary)`, which the accent engine repaints, so both move with the
/// accent on the web and both do here — through [AccentArt] and [_Monogram]. They subscribe
/// separately, and one level below this widget on purpose: a tick then rebuilds the one leaf that
/// draws the colour, not the tile, the cover it is standing in for, or the grid around it.
class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.size,
    required this.icon,
    required this.initial,
    required this.settled,
  });

  final double size;
  final IconData icon;
  final String? initial;
  final bool settled;

  @override
  Widget build(BuildContext context) {
    final monogram = initial?.trim();
    final letter = (monogram == null || monogram.isEmpty)
        ? null
        : monogram.characters.first.toUpperCase();

    if (letter != null && settled) return _Monogram(size: size, letter: letter);

    return AccentArt(
      child: settled
          ? Center(
              child: Icon(
                icon,
                size: size / 3,
                // `text-foreground/30`, and deliberately not an accent role: the glyph is the one
                // mark on the tile that has to stay legible whatever the wash under it is doing.
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            )
          : const SizedBox.expand(),
    );
  }
}

/// `MONOGRAM_BG` (`CoverArt.tsx:36`): an imageless artist as a glossy accent sphere.
///
/// A leaf that subscribes to the frame directly rather than an [AccentBuilder], because everything
/// it draws moves — the sphere is three mixes of `--primary` and the letter is
/// `fill-primary-foreground`, which in Fade can flip to the other side of the crossover between one
/// stop and the next. There is nothing under it worth keeping across a tick.
class _Monogram extends StatelessWidget {
  const _Monogram({required this.size, required this.letter});

  final double size;
  final String letter;

  @override
  Widget build(BuildContext context) {
    final frame = AccentScope.of(context);
    // The blend, in Gradient mode: `--primary` stays one colour, and a three-stop sphere lit by a
    // palette as well would have nothing left to read the letter against.
    final accent = frame.accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          // `125% 125% at 30% 24%` — 30%/24% of the box maps onto Flutter's -1..1 alignment.
          center: const Alignment(-0.4, -0.52),
          radius: 1.25,
          colors: [
            Color.lerp(accent, Colors.white, 0.26)!,
            accent,
            Color.lerp(accent, Colors.black, 0.44)!,
          ],
          stops: const [0, 0.42, 1],
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            // `fontSize: 44` in a 100-unit viewBox, so it scales with the frame.
            fontSize: size * 0.44,
            height: 1,
            fontWeight: ChordiaType.semibold,
            letterSpacing: size * 0.0044,
            color: frame.foreground,
          ),
        ),
      ),
    );
  }
}
