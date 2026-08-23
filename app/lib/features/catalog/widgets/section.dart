import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/tokens.dart';

/// The page gutter every catalog surface is laid out against — the web's `px-4`.
const catalogGutter = 16.0;

/// A section heading, with an optional route to the full list.
///
/// Ported from the web's section headings (`components/catalog/ArtistView.tsx`): an `h2` at
/// `font-semibold text-xl` with `mb-4` under it, sections separated by `space-y-10`, and the
/// "See all" link sitting on the heading's baseline at the far end of the row.
class SectionHeader extends ConsumerWidget {
  const SectionHeader({required this.title, super.key, this.onSeeAll});

  final String title;

  /// Shown whenever the section has a page of its own — including when everything already fits.
  /// Hiding it past a threshold on the DATA left a phone showing two of five albums with no route
  /// to the other three. (`ArtistView.tsx`: "Unconditional. This used to appear only past the
  /// six-card preview limit".)
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    // `space-y-10` above (40), `mb-4` below (16). The trailing 8 is the page gutter minus the
    // text button's own inset, so the word "See all" lands on the gutter, not 8px past it.
    padding: const EdgeInsets.fromLTRB(catalogGutter, 40, 8, 16),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            // `font-semibold text-xl`.
            style: ChordiaType.xl.copyWith(
              fontWeight: ChordiaType.semibold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            child: Text(ref.t(CommonKeys.actionsSeeAll)),
          ),
      ],
    ),
  );
}

/// The row under a collection's header: a big round Play, then ring-outlined icon controls.
///
/// Ported from the web's shared action row (`components/catalog/CollectionActions.tsx`, matched by
/// `ArtistView.tsx` and `AlbumView.tsx`): a `size-14` filled circle for play — "a play control is
/// the one button in the app that needs no label" — followed by `ICON_BTN` circles for everything
/// else. It wraps rather than scrolls, because the web measured the unwrapped row at 123px wider
/// than a 375px phone and it scrolled the whole page sideways.
///
/// Both primary actions are disabled together when there is nothing to play — an empty album, or a
/// build where the player is not wired yet. A control that looks live and does nothing is the
/// failure this avoids.
class CollectionActions extends ConsumerWidget {
  const CollectionActions({
    required this.onPlay,
    required this.onShuffle,
    super.key,
    this.trailing = const [],
  });

  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  /// Extra controls — Radio on an artist, Download on an album, Pin on a playlist. The web puts
  /// everything past this handful in the ⋮ menu rather than here.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Padding(
      padding: const EdgeInsets.fromLTRB(catalogGutter, 8, catalogGutter, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _PlayButton(onPressed: onPlay, label: t(CommonKeys.actionsPlay)),
          RingIconButton(
            icon: Icons.shuffle_rounded,
            tooltip: t(CommonKeys.actionsShuffle),
            onPressed: onShuffle,
          ),
          ...trailing,
        ],
      ),
    );
  }
}

/// The `size-14` filled circle the web gives every collection's Play control.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onPressed, required this.label});

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        shape: const CircleBorder(),
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(56),
        fixedSize: const Size.square(56),
      ),
      child: Icon(Icons.play_arrow_rounded, size: 28, semanticLabel: label),
    ),
  );
}

/// The web's `ICON_BTN`: a circular, ring-outlined icon control sized to a comfortable touch
/// target, tinting to the accent when it is holding a state.
class RingIconButton extends StatelessWidget {
  const RingIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// `text-primary ring-primary/40` on the web — the look a control wears while its state is on.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        foregroundColor: active ? scheme.primary : scheme.onSurfaceVariant,
        // `size-(--control-h-lg)`, which on a coarse pointer is the touch-target height.
        minimumSize: const Size.square(ChordiaControl.lg),
        fixedSize: const Size.square(ChordiaControl.lg),
        shape: CircleBorder(
          side: BorderSide(
            color: active
                ? scheme.primary.withValues(alpha: 0.4)
                : scheme.outline,
          ),
        ),
      ),
    );
  }
}

/// The fade that dissolves hero art into the page.
///
/// The web's `HERO_MASK` (`components/catalog/HeroWash.tsx`): held solid for the first quarter so
/// the art reads, then out by 92%. Shared by the album wash and the artist banner so the two
/// surfaces agree — the artist hero used to run to 90% and looked visibly darker at the top.
const heroMaskStops = [0.0, 0.25, 0.92];

/// The web's `HERO_SCRIM`: one gentle ramp to the page background, with no dark mid-stop, because
/// a heavier midpoint bands visibly across a wide hero.
LinearGradient heroScrim(ColorScheme scheme) => LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    scheme.surface.withValues(alpha: 0),
    scheme.surface.withValues(alpha: 0.25),
    scheme.surface,
  ],
);

/// Applies [heroMaskStops] to [child], fading it out toward the bottom of the hero.
class HeroMask extends StatelessWidget {
  const HeroMask({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (bounds) => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.black, Colors.black, Colors.transparent],
      stops: heroMaskStops,
    ).createShader(bounds),
    child: child,
  );
}

/// The blurred cover-art bloom behind an album hero.
///
/// Ported from `components/catalog/HeroWash.tsx`: an opaque base so the page cannot bleed through,
/// a 256px thumbnail scaled 1.1x and blurred, at 60% opacity, masked by [heroMaskStops], and one
/// gentle legibility scrim on top. Deliberately unrecognisable — this is a colour bloom, not art
/// the listener is meant to look at.
///
/// **The caller must clip it.** It fills its parent, so the parent needs to clip or the wash paints
/// over whatever sits below the hero.
class HeroWash extends StatelessWidget {
  const HeroWash({required this.sha256, super.key});

  final String? sha256;

  @override
  Widget build(BuildContext context) {
    final hash = sha256;
    if (hash == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: scheme.surface),
          // 256 is plenty: it is blurred and scaled 1.1x, so a larger source buys nothing but
          // bytes — the same reasoning the web records for its `sizedImageSrc(src, 256)`.
          HeroMask(
            child: Opacity(
              opacity: 0.6,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: 24,
                  sigmaY: 24,
                  tileMode: TileMode.decal,
                ),
                child: Transform.scale(
                  scale: 1.1,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: CoverArt(
                      sha256: hash,
                      size: 256,
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
              ),
            ),
          ),
          DecoratedBox(decoration: BoxDecoration(gradient: heroScrim(scheme))),
        ],
      ),
    );
  }
}

/// The soft, on-theme banner an artist with no banner art of their own wears.
///
/// Ported from `components/catalog/DefaultArtistBanner.tsx`: overlapping radial glows in the live
/// accent plus one lighter highlight hotspot, over a faint accent base wash, so it reads as a
/// modern mesh gradient rather than a flat band. The colour is read from the theme (never a
/// constant) so it tracks whatever the accent currently is.
///
/// The web's film-grain pass is dropped: it is an SVG turbulence filter with no cheap Flutter
/// equivalent, and it exists only to kill banding a gradient shader does not produce here.
class AccentBanner extends StatelessWidget {
  const AccentBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    // The web's `color-mix(in srgb, var(--primary), white 32%)` highlight.
    final highlight = Color.lerp(primary, Colors.white, 0.32)!;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Faint base wash so the whole field has presence even between the glows.
          ColoredBox(color: primary.withValues(alpha: 0.06)),
          // The four ellipses of the SVG, in its order, at its alphas. Positions are the SVG
          // centres mapped onto Flutter's -1..1 alignment space; the radii are approximate,
          // because an SVG ellipse has two radii and a Flutter radial gradient has one.
          _Glow(const Alignment(-0.62, -0.35), 1.2, primary, 0.42),
          _Glow(const Alignment(0.47, 0.25), 1.3, primary, 0.26),
          _Glow(const Alignment(-0.28, 0.9), 1.0, primary, 0.26),
          _Glow(const Alignment(0.8, -0.73), 0.8, highlight, 0.48),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow(this.center, this.radius, this.color, this.alpha);

  final Alignment center;
  final double radius;
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: center,
        radius: radius,
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: 0),
        ],
      ),
    ),
  );
}

/// A hero: art behind, the page's scrim over it, and the header content on top.
///
/// The shape every web hero shares — `relative overflow-hidden` with the art `absolute inset-0`,
/// pointer-events off, and the content in normal flow above it — so the art can never bleed past
/// the hero into the section below and the controls under it stay tappable.
class HeroSurface extends StatelessWidget {
  const HeroSurface({
    required this.child,
    super.key,
    this.background,
    this.minHeight = 0,
  });

  /// The art layer. Absent (or [SizedBox.shrink]) leaves the plain page background.
  final Widget? background;

  /// The header content, in normal flow: the hero grows to fit it.
  final Widget child;

  /// The web's `min-h-80` on the artist hero. Zero elsewhere, where the hero is sized to content
  /// so an empty band cannot pad the cover down from the top.
  final double minHeight;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Stack(
        children: [
          if (background != null) Positioned.fill(child: background!),
          child,
        ],
      ),
    ),
  );
}

/// An artist's banner art, cropped to the hero band and faded into the page.
///
/// `ArtistView.tsx` renders the banner as an image (not a background) at `h-80 object-cover
/// opacity-50` with the shared hero mask over it. Banner art is wide and [CoverArt] is square by
/// contract — it also feeds the media notification — so this asks for it at the viewport width and
/// crops vertically rather than standing up a second art pipeline.
class ArtistBanner extends StatelessWidget {
  const ArtistBanner({required this.sha256, super.key, this.height = 320});

  final String sha256;

  /// The web's `h-80`.
  final double height;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: HeroMask(
          child: Opacity(
            opacity: 0.5,
            child: ClipRect(
              child: OverflowBox(
                maxHeight: double.infinity,
                child: CoverArt(
                  sha256: sha256,
                  size: MediaQuery.sizeOf(context).width,
                  borderRadius: BorderRadius.zero,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Text that expands on demand — an artist bio, a label's description.
class ExpandableText extends ConsumerStatefulWidget {
  const ExpandableText({
    required this.text,
    super.key,
    this.collapsedLines = 4,
  });

  final String text;
  final int collapsedLines;

  @override
  ConsumerState<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends ConsumerState<ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final theme = Theme.of(context);
    // Roughly the length at which the collapsed clamp actually bites. Below it the toggle would
    // expand nothing, which is worse than no toggle. (`ArtistView.tsx`: `artist.bio.length > 240`.)
    final expandable = widget.text.length > 240;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _expanded ? null : widget.collapsedLines,
          overflow: _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
            height: 1.45,
          ),
        ),
        if (expandable)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(
              t(
                _expanded
                    ? CommonKeys.actionsShowLess
                    : CommonKeys.actionsShowMore,
              ),
            ),
          ),
      ],
    );
  }
}
