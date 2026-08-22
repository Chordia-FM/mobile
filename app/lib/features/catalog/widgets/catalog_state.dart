import 'package:chordia_api/chordia_api.dart' show ApiException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';

/// Renders one asynchronous catalog read: skeleton, failure with a retry, or the page.
///
/// A widget rather than a pattern each screen re-types, because the three states have to look the
/// same everywhere — a page that renders its own spinner while its neighbour shows a skeleton reads
/// as two different apps.
///
/// Stale data survives a failed refresh: an [AsyncError] that still carries a previous value keeps
/// showing that value. Replacing a loaded album with an error card because a background refresh
/// timed out throws away something the user was reading.
class CatalogBody<T> extends ConsumerWidget {
  const CatalogBody({
    required this.value,
    required this.errorTitle,
    required this.onRetry,
    required this.builder,
    required this.skeleton,
    super.key,
  });

  final AsyncValue<T> value;

  /// Already-localised heading for the failure state.
  final String errorTitle;

  final VoidCallback onRetry;
  final Widget Function(BuildContext context, T value) builder;
  final Widget skeleton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = value.value;
    if (loaded != null) return builder(context, loaded);
    if (value.hasError) {
      return CatalogError(
        title: errorTitle,
        error: value.error,
        onRetry: onRetry,
      );
    }
    return skeleton;
  }
}

/// A load failure the user can act on.
class CatalogError extends ConsumerWidget {
  const CatalogError({
    required this.title,
    required this.onRetry,
    super.key,
    this.error,
  });

  final String title;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final failure = error;
    final detail = failure is ApiException && !failure.isNetworkFailure
        ? failure.title
        : null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            // The server's own words for what went wrong, already in the reader's language — the
            // request carried an `Accept-Language` it understands. Worth showing, because
            // "unreachable" and "you may not see this library" are the same headline and very
            // different problems.
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: Text(t(CommonKeys.actionsTryAgain)),
            ),
          ],
        ),
      ),
    );
  }
}

/// One grey block standing in for content that has not arrived.
///
/// Pulses, because a static grey rectangle is indistinguishable from a rendering bug — the motion
/// is the part that says "still coming".
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
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
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHigh;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 0.9).animate(_controller),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          shape: widget.shape,
          borderRadius: widget.shape == BoxShape.circle
              ? null
              : (widget.borderRadius ?? BorderRadius.circular(6)),
        ),
      ),
    );
  }
}

/// The skeleton every catalog detail page shows: art, a title block, and a few rows.
class CatalogDetailSkeleton extends StatelessWidget {
  const CatalogDetailSkeleton({super.key, this.circularArt = false});

  /// Artists get a round portrait; albums and labels get a square cover.
  final bool circularArt;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Center(
        child: SkeletonBox(
          width: 168,
          height: 168,
          shape: circularArt ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      const SizedBox(height: 20),
      const SkeletonBox(width: 220, height: 26),
      const SizedBox(height: 10),
      const SkeletonBox(width: 140, height: 14),
      const SizedBox(height: 24),
      for (var i = 0; i < 8; i++) ...[
        Row(
          children: [
            const SkeletonBox(width: 44, height: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 180 - (i % 3) * 30, height: 14),
                  const SizedBox(height: 8),
                  const SkeletonBox(width: 110, height: 11),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
      ],
    ],
  );
}

/// The skeleton for a page that is a grid of tiles (genres, labels, discography).
class CatalogGridSkeleton extends StatelessWidget {
  const CatalogGridSkeleton({super.key, this.tileCount = 8});

  final int tileCount;

  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.all(16),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 200,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 0.78,
    ),
    itemCount: tileCount,
    itemBuilder: (context, index) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(child: SkeletonBox(height: double.infinity)),
        const SizedBox(height: 8),
        SkeletonBox(width: 120 - (index % 3) * 20, height: 12),
      ],
    ),
  );
}

/// "Nothing here" — a statement, not a failure.
class CatalogEmpty extends StatelessWidget {
  const CatalogEmpty({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
