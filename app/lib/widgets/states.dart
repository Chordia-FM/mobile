/// Loading, empty and error, styled the way the web client styles them.
///
/// These three were the phone's plainest tell. The web has one skeleton primitive with a shimmer
/// sweep (`.skeleton`, styles.css:1091-1113), one dashed-outline empty card
/// (`routes/_authed/app/library/index.tsx:432`) and an error block with a headline over a muted
/// detail line; the phone had a pulsing grey rectangle, a bare paragraph and a centred
/// `Text` + button. Nothing about those was wrong, and all of them read as a stock Material app.
///
/// Both `features/catalog/widgets/catalog_state.dart` and
/// `features/library/widgets/library_states.dart` render through this file, so the Catalog tab and
/// the Library tab cannot drift apart again.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import 'brand/logo.dart';
import 'surface.dart';
import 'tokens.dart';

/// The skeleton primitive: a muted block with a highlight sweeping across it.
///
/// `.skeleton` in the web's stylesheet — `color-mix(in oklch, var(--muted) 65%, transparent)` under
/// a `linear-gradient(90deg, transparent, foreground 6%, transparent)` translated from -100% to
/// 100% over 1.8s. Deliberately low-contrast and slow so it reads as "loading", not a strobe.
///
/// The sweep replaces an opacity pulse. A pulse and a sweep say the same thing, but only one of
/// them is what the other client does, and a skeleton is on screen at exactly the moment someone is
/// deciding whether these are the same product.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
  });

  final double? width;
  final double height;
  final BorderRadius? borderRadius;
  final BoxShape shape;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHigh.withValues(alpha: 0.65);
    final highlight = scheme.onSurface.withValues(alpha: 0.06);
    final circle = widget.shape == BoxShape.circle;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // The sweep is expressed as moving gradient alignments rather than a translated child, so
          // nothing is laid out per frame — it is a paint-only animation, like the CSS one.
          final t = Curves.easeInOut.transform(_controller.value) * 3 - 1;
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: base,
              shape: widget.shape,
              borderRadius: circle
                  ? null
                  : (widget.borderRadius ?? ChordiaRadius.mdAll),
              gradient: LinearGradient(
                begin: Alignment(t - 1, 0),
                end: Alignment(t + 1, 0),
                colors: [Colors.transparent, highlight, Colors.transparent],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// "Nothing here" — a statement, not a failure.
///
/// A dashed outline, not a filled card: a filled card says "here is a thing", and the whole point
/// of an empty state is that there is no thing. That is the web's own choice at
/// `library/index.tsx:432` (`rounded-2xl border border-border border-dashed p-8 text-center`) and
/// `PlaylistEmptyState.tsx:112`.
///
/// [message] is the headline, [hint] the muted line under it — the same two-line shape as the web's
/// `list.empty.title` over `list.empty.hint`, because one sentence naming the action that fills a
/// collection is the entire value of this state.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.message,
    super.key,
    this.hint,
    this.icon,
    this.action,
    this.padding = const EdgeInsets.fromLTRB(16, 24, 16, 24),
  });

  final String message;
  final String? hint;
  final IconData? icon;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: DashedPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 32,
                // The one flash of accent in an otherwise muted state, so an empty screen still
                // belongs to the app rather than looking switched off.
                color: scheme.primary.withValues(alpha: 0.8),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: ChordiaType.lg.copyWith(
                fontWeight: ChordiaType.semibold,
                color: scheme.onSurface,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: ChordiaType.sm.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// A load failure, with the one thing worth offering: another go.
///
/// [title] is the headline and [detail] the server's own words for what went wrong, already in the
/// reader's language. Worth showing separately, because "unreachable" and "you may not see this
/// library" are the same headline and very different problems.
class ErrorState extends StatelessWidget {
  const ErrorState({
    required this.title,
    required this.actionLabel,
    required this.onRetry,
    super.key,
    this.detail,
  });

  final String title;
  final String? detail;
  final String actionLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: IslandPanel(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIconsDuotone.warningCircle,
                size: 32,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                // The web's own failure block is `display-title font-semibold text-2xl`
                // (`ErrorState.tsx:402`) — the serif, one of the 19 page H1s that carry it. This
                // is the same component: `live.tsx:22` hands a page's load failure to it.
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: ChordiaType.semibold,
                  color: scheme.onSurface,
                ),
              ),
              if (detail != null) ...[
                const SizedBox(height: 6),
                Text(
                  detail!,
                  textAlign: TextAlign.center,
                  style: ChordiaType.sm.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.tonal(onPressed: onRetry, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Something is in flight and there is no shaped skeleton to show instead.
///
/// The record plays rather than a `CircularProgressIndicator` spinning: `AuthPage.tsx:22` does
/// exactly this on the web ("play the record while something is in flight — the sign-in hand-off
/// has no other spinner"), and 13-brand.md names a route-level loading state as one of the three
/// places the mark is allowed to move at all.
///
/// Prefer a skeleton wherever the page's shape is known — a silhouette that matches what is coming
/// beats any indicator. This is for the cases where it genuinely is not.
class BrandLoading extends StatelessWidget {
  const BrandLoading({required this.label, super.key});

  /// Already localised; also the accessible name.
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandLoader(semanticLabel: label),
          const SizedBox(height: 16),
          Text(
            label,
            style: ChordiaType.sm.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
