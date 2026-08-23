/// The two panel materials the web client has, and no others.
///
/// ## Solid content, glass only on a modal — and on the phone, not even there
///
/// The web spent a whole session removing `backdrop-filter` (`styles.css:636-666`, and again at
/// :456-464): a blurred panel re-blurs its entire backdrop region on ANY repaint inside it, and a
/// blurred panel inside a scroll container re-blurs on every scrolled frame. Both rules were
/// measured on production, not guessed. The verdict recorded there is blunt: "Opaque is not a
/// compromise here, it is the fix."
///
/// So: [IslandPanel] is the content panel and [ModalPanel] is the elevated one, and NEITHER uses a
/// [BackdropFilter]. A phone has less GPU headroom than the desktop that produced those numbers, so
/// there is no version of this where the phone can afford what the web could not.
/// `test/identity_test.dart` fails the build if a `BackdropFilter` appears under a scrolling
/// surface.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// A content panel: `.island-shell` (styles.css:465-475).
///
/// A 1px accent-tinted border, a 165° gradient between two accent-tinted near-blacks, and a tight
/// drop shadow with a zero-blur inset hairline. Every number comes from that rule; see
/// [ChordiaSchemeTokens] for the individual derivations.
class IslandPanel extends StatelessWidget {
  const IslandPanel({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = ChordiaRadius.xlAll,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: scheme.panelBorder),
        // 165° in CSS starts from "to top" and turns clockwise, so it runs top-left-ish to
        // bottom-right-ish. These alignments are that sweep in Flutter's coordinate space.
        gradient: LinearGradient(
          begin: const Alignment(-0.26, -1),
          end: const Alignment(0.26, 1),
          colors: [scheme.panelTop, scheme.panelBottom],
        ),
        boxShadow: chordiaPanelShadow,
      ),
      child: child,
    );
  }
}

/// An elevated panel for a sheet or a dialog: `.island-shell-modal` (styles.css:648-666).
///
/// Reads one step lighter and one step more saturated than [IslandPanel], so a dialog separates
/// from the page it covers by being elevated rather than by being a different material. Opaque, for
/// the reason at the top of this file.
class ModalPanel extends StatelessWidget {
  const ModalPanel({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = ChordiaRadius.xlAll,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: scheme.panelBorder),
        gradient: LinearGradient(
          begin: const Alignment(-0.26, -1),
          end: const Alignment(0.26, 1),
          colors: [scheme.modalTop, scheme.modalBottom],
        ),
      ),
      child: child,
    );
  }
}

/// A card or a list row: it FILLS on press, and it does not ripple.
///
/// The web is unusually explicit about this (styles.css:914-928). Its transition rule covers every
/// `button` and `a`, and list rows and cards opt straight back out with `transition-none`, because
/// "sweeping a pointer down a list overlaps a dozen 120ms transitions at once" — measured at 34
/// stuttered frames against 1. The note ends: "An instant row highlight is also just better: it's
/// what Spotify does."
///
/// A Material ink ripple is the same mistake in a different costume — a per-press animation that
/// spreads across the row, on the one surface the app scrolls fastest. So the splash is off and the
/// highlight is the whole feedback, which is also exactly what `hover:bg-accent/40` (cards) and
/// `hover:bg-accent/50` (rows) do on the desktop.
///
/// The web's `group-hover:scale-[1.03]` on a card's cover has no counterpart here on purpose: a
/// hover state does not exist on a phone, and inventing a press-scale to stand in for it would be
/// designing something the other client does not have.
class PressFill extends StatelessWidget {
  const PressFill({
    required this.child,
    super.key,
    this.onTap,
    this.onLongPress,
    this.borderRadius = ChordiaRadius.xlAll,
    this.fill,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;

  /// Defaults to a card's fill. Rows pass [ChordiaSchemeTokens.rowHighlight].
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colour = fill ?? scheme.cardHighlight;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: borderRadius,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: colour,
      hoverColor: colour,
      focusColor: colour,
      child: child,
    );
  }
}

/// The dashed outline the web uses for "there is nothing here yet".
///
/// `rounded-2xl border border-border border-dashed p-8` — `routes/_authed/app/library/index.tsx:432`
/// and `components/catalog/PlaylistEmptyState.tsx:112`. It is deliberately NOT an [IslandPanel]: a
/// filled card says "here is a thing", and the point of an empty state is that there is no thing.
class DashedPanel extends StatelessWidget {
  const DashedPanel({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(32),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: scheme.line,
        radius: ChordiaRadius.xl,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Flutter has no dashed [Border], so the rounded rect is walked with a path metric and drawn in
/// alternating 6/5 segments — CSS's own `dashed` rhythm for a 1px border.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _dash = 6.0;
  static const _gap = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
