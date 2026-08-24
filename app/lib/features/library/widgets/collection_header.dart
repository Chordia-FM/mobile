import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/accent/accent_scope.dart';
import '../../../data/accent/accent_surfaces.dart';
import '../../../data/art/art_cache.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/surface.dart';
import '../../../widgets/tokens.dart';
import '../../catalog/widgets/section.dart' as catalog;

/// A playlist's face: the cover its owner chose, or a mosaic of what is inside it.
///
/// The mosaic is not decoration. A playlist with no chosen cover and a single album's artwork
/// stretched across it looks like that album; four tiles say "this is a collection" without a
/// word, and it re-shuffles as the playlist changes so it can never be out of date.
///
/// The recipe is the web's (`components/catalog/PlaylistCover.tsx`), tile for tile:
/// 1 → full · 2 → side by side · 3 → two on top and one across the bottom · 4 → a 2×2. With no
/// covers at all it falls through to the accent gradient, not to a grey square.
class MosaicCover extends StatelessWidget {
  const MosaicCover({
    required this.coverUrl,
    required this.autoCoverUrls,
    required this.size,
    super.key,
    this.semanticLabel,
  });

  final String? coverUrl;
  final List<String>? autoCoverUrls;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final chosen = artHashOf(coverUrl);
    final tiles = [
      for (final url in autoCoverUrls ?? const <String>[]) ?artHashOf(url),
    ];

    // A cover its owner chose always wins.
    if (chosen != null) {
      return CoverArt(sha256: chosen, size: size, semanticLabel: semanticLabel);
    }
    if (tiles.isEmpty) {
      // Nothing to build a mosaic from — the web's `CoverArt` fallback, which is the accent
      // gradient with a music glyph on it rather than an empty grey frame.
      return GradientArtwork(
        icon: Icons.queue_music_rounded,
        size: size,
        semanticLabel: semanticLabel,
      );
    }
    if (tiles.length == 1) {
      return CoverArt(
        sha256: tiles.first,
        size: size,
        semanticLabel: semanticLabel,
      );
    }

    final half = size / 2;
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ClipRRect(
        borderRadius: ChordiaRadius.mdAll,
        child: SizedBox(
          width: size,
          height: size,
          child: Column(
            children: [
              Row(
                children: [
                  for (final hash in tiles.take(2))
                    // Two covers sit side by side across the FULL height; three and four split the
                    // square into rows.
                    _MosaicTile(
                      sha256: hash,
                      width: half,
                      height: tiles.length == 2 ? size : half,
                    ),
                ],
              ),
              if (tiles.length == 3)
                // The third tile spans the bottom row, as the web's `col-span-2` does.
                _MosaicTile(sha256: tiles[2], width: size, height: half)
              else if (tiles.length >= 4)
                Row(
                  children: [
                    for (final hash in tiles.skip(2).take(2))
                      _MosaicTile(sha256: hash, width: half, height: half),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One cell of a [MosaicCover], cropped to fill a rectangle that is not necessarily square.
///
/// [CoverArt] is square by contract — it also feeds the media notification — so a half-width,
/// full-height cell is produced by cropping a square rather than by asking for a shape the art
/// pipeline does not have.
class _MosaicTile extends StatelessWidget {
  const _MosaicTile({
    required this.sha256,
    required this.width,
    required this.height,
  });

  final String? sha256;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: CoverArt(
        sha256: sha256,
        size: width > height ? width : height,
        borderRadius: BorderRadius.zero,
      ),
    ),
  );
}

/// The artwork size a collection hero wears — the web's `size-40` below `sm`.
const collectionArtSize = 160.0;

/// The hero every collection screen wears: artwork, what kind of thing this is, its name, one
/// optional description, and one line of facts about it.
///
/// Ported from the web's playlist hero (`routes/_authed/app/playlists/$playlistId.tsx`, matched by
/// `liked.tsx` and `downloads.tsx`): below `sm` it is a left-aligned column — artwork, then an
/// uppercase kind eyebrow, the name at `text-3xl`, a two-line description clamp, and the meta line.
/// Not centred: the web centres nothing here, and a centred hero over a left-aligned track list is
/// most of why these pages read as a different app.
///
/// Identical between playlists, smart playlists, liked songs and downloads on purpose. The web's
/// four collection pages used to differ in cover size and meta order, and the result was that each
/// read as a different species of object rather than four collections.
class CollectionHeader extends StatelessWidget {
  const CollectionHeader({
    required this.eyebrow,
    required this.title,
    required this.meta,
    required this.artwork,
    super.key,
    this.description,
    this.metaLeading,
    this.onEditTitle,
    this.onEditArtwork,
  });

  final String eyebrow;
  final String title;

  /// The facts line: track count, runtime, owner, schedule. Already joined by the caller, which
  /// is what keeps the separator out of the catalogs.
  final String meta;

  final Widget artwork;

  /// The description, or the smart playlist's rules in the slot a description would take.
  final String? description;

  /// What sits in FRONT of [meta] on the same line, for the one fact that is not text.
  ///
  /// A playlist's owner: the web's meta line opens with an avatar and a name linking to
  /// `/app/u/$handle` (`playlists/$playlistId.tsx:425-439`), then joins the counts after it with a
  /// `·`. Folding the owner into the joined string, as this page used to, spends the same pixels
  /// and throws the route away.
  final Widget? metaLeading;

  /// The title IS the edit affordance where there is one — no pencil, matching the web client.
  final VoidCallback? onEditTitle;

  final VoidCallback? onEditArtwork;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final heading = Text(
      title,
      // `display-title break-words font-bold text-3xl`. The class is the serif, so this reads the
      // `displayMedium` slot rather than restating `text-3xl` in the sans — `.display-title` is on
      // 19 elements on the web and every one is a page H1, which is exactly what this is.
      style: Theme.of(
        context,
      ).textTheme.displayMedium?.copyWith(color: scheme.onSurface),
    );

    return Padding(
      // The page's `p-4`, with the hero's own `mb-6` under it.
      padding: const EdgeInsets.fromLTRB(
        catalog.catalogGutter,
        8,
        catalog.catalogGutter,
        24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onEditArtwork == null)
            artwork
          else
            // A fill, not a ripple — see [PressFill]; the web's rows and cards all carry
            // `transition-none` for the reason recorded there.
            PressFill(
              onTap: onEditArtwork,
              borderRadius: ChordiaRadius.mdAll,
              child: artwork,
            ),
          // The web's `gap-4` between the artwork and the metadata column.
          const SizedBox(height: 16),
          Text(
            eyebrow.toUpperCase(),
            // `text-muted-foreground text-xs uppercase tracking-wide`. Tailwind's `tracking-wide`
            // is 0.025em, which at 12px is 0.3px — not the 1.1px this carried, which is nearly four
            // times as wide and read as a spaced-out label from a different design system.
            style: ChordiaType.xs.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          if (onEditTitle == null)
            heading
          else
            PressFill(
              onTap: onEditTitle,
              borderRadius: ChordiaRadius.smAll,
              child: heading,
            ),
          if (description != null && description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description!,
              // `line-clamp-2 text-muted-foreground text-sm`.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ChordiaType.sm.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          // `flex flex-wrap items-center gap-x-2 gap-y-1.5`: the owner and the counts are one
          // line that wraps rather than two stacked ones, and the `·` between them belongs to
          // this layout rather than to the joined string.
          DefaultTextStyle.merge(
            // The meta line is `text-sm`, one size up from the eyebrow above it.
            style: ChordiaType.sm.copyWith(color: scheme.onSurfaceVariant),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                if (metaLeading case final leading?) ...[
                  leading,
                  const Text('·'),
                ],
                Text(meta),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Play and Shuffle, plus whatever else a collection offers.
///
/// One definition, shared with the catalog's headers ([catalog.CollectionActions]) so a playlist,
/// an album and an artist cannot drift apart — the web makes the same point in
/// `components/catalog/CollectionActions.tsx`: "these pages should match" kept being something four
/// files each agreed to separately.
class CollectionActions extends ConsumerWidget {
  const CollectionActions({
    required this.onPlay,
    required this.onShuffle,
    super.key,
    this.extra = const [],
  });

  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      catalog.CollectionActions(
        onPlay: onPlay,
        onShuffle: onShuffle,
        trailing: extra,
      );
}

/// The square gradient tile a collection with no artwork wears.
///
/// The web's rule for this one is **not** `.accent-art`, whatever the previous comment here said:
/// `liked.tsx:50` is `bg-linear-to-br from-primary to-accent/60`, a two-stop sweep from `--primary`
/// to `--accent` at 60% opacity. `.accent-art` is the coverless-tile recipe — two mixes at 35% and
/// 22% over whatever is behind them — and it is a visibly dimmer, more translucent thing. This
/// tile ported the wrong end of it: `--accent` is `paneElevated`, the lightest of the shadcn
/// surfaces, and the [ColorScheme] slot it was reading (`surfaceContainerHigh`) is `card`.
///
/// It moves, because `from-primary` is `var(--primary)` and the engine rewrites that on every tick.
/// A 160px tile at the top of a page is a large enough accent surface that holding it still while
/// the Play button under it cross-fades is the disagreement this whole seam exists to remove.
/// Gradient mode is the one case it stays put, and correctly so — `--primary` is a single colour
/// there by construction, and a palette sweep here would be a second gradient inside the first.
///
/// They have no cover to show and never will, so the alternative to a gradient is a grey box that
/// reads as artwork that failed to load.
class GradientArtwork extends StatelessWidget {
  const GradientArtwork({
    required this.icon,
    required this.size,
    super.key,
    this.colors,
    this.semanticLabel,
  });

  final IconData icon;
  final double size;

  /// Overrides the accent pair, for the one page the web gives its own colours (Downloads is
  /// `from-emerald-500 to-sky-600` under a `text-white` glyph). Fixed colours, so a tile wearing
  /// them does not subscribe to the accent at all.
  final List<Color>? colors;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    // `size-16` in a `size-40` tile.
    final glyph = Icon(icon, size: size * 0.4);

    if (colors case final override?) {
      return _tile(gradient: override, foreground: Colors.white, child: glyph);
    }

    final surfaces = context.surfaces;
    return AccentBuilder(
      builder: (context, frame, child) {
        // `--accent` is itself a `color-mix` off `--primary`, so a browser recomputes it in the
        // frame the accent moves in. The theme carries the resting derivation; re-deriving is only
        // worth doing while a mode is actually moving the accent.
        final elevated = frame.accent == surfaces.accent
            ? surfaces.paneElevated
            : paneElevatedFor(frame.accent);
        return _tile(
          gradient: [frame.accent, elevated.withValues(alpha: 0.6)],
          // `text-primary-foreground`, not a literal white: the accent picker reaches lightnesses
          // (amber, lime) where the web flips this to near-black, and a hard white glyph would be
          // the one mark on the page that stops being legible. It takes the FRAME's foreground
          // rather than the theme's, because in Fade the two ends of a palette can want opposite
          // sides of the crossover — that is how a glyph goes unreadable halfway through.
          foreground: frame.foreground,
          child: child!,
        );
      },
      // Built once and carried through every tick: the glyph is the one mark on the tile nobody
      // has asked to move, only to stay readable.
      child: glyph,
    );
  }

  Widget _tile({
    required List<Color> gradient,
    required Color foreground,
    required Widget child,
  }) => Semantics(
    label: semanticLabel,
    image: true,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: ChordiaRadius.mdAll,
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: chordiaCoverShadow,
      ),
      child: IconTheme.merge(
        data: IconThemeData(color: foreground),
        child: Center(child: child),
      ),
    ),
  );
}
