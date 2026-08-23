import 'package:chordia_api/chordia_api.dart' show ApiException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/states.dart';
import '../../../widgets/tokens.dart';

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
    final failure = error;
    return ErrorState(
      title: title,
      // The server's own words for what went wrong, already in the reader's language — the request
      // carried an `Accept-Language` it understands. Worth showing, because "unreachable" and "you
      // may not see this library" are the same headline and very different problems.
      detail: failure is ApiException && !failure.isNetworkFailure
          ? failure.title
          : null,
      actionLabel: ref.t(CommonKeys.actionsTryAgain),
      onRetry: onRetry,
    );
  }
}

/// One block standing in for content that has not arrived.
///
/// The name is kept because two dozen screens import it; the treatment is the web's [ShimmerBox],
/// so a loading phone and a loading desktop show the same thing.
class SkeletonBox extends StatelessWidget {
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
  Widget build(BuildContext context) => ShimmerBox(
    width: width,
    height: height,
    borderRadius: borderRadius,
    shape: shape,
  );
}

/// The skeleton every catalog detail page shows: art, a title block, and a few rows.
class CatalogDetailSkeleton extends StatelessWidget {
  const CatalogDetailSkeleton({super.key, this.circularArt = false});

  /// Artists get a round portrait; albums and labels get a square cover.
  final bool circularArt;

  /// The row silhouette is `TrackListSkeleton`'s (components/catalog/Skeletons.tsx:33-49): a
  /// `size-10` cover, `gap-3`, and two bars at `h-3 w-1/3` over `h-2.5 w-1/4`. Sized to the REAL
  /// row, so nothing jumps when the data lands.
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Center(
        child: SkeletonBox(
          width: 168,
          height: 168,
          shape: circularArt ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: ChordiaRadius.mdAll,
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
            const SkeletonBox(width: 40, height: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 180 - (i % 3) * 30, height: 12),
                  const SizedBox(height: 6),
                  const SkeletonBox(width: 110, height: 10),
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

  /// `GridSkeleton` (components/catalog/Skeletons.tsx:16-31): a square, then two bars at
  /// `h-3 w-3/4` and `h-2.5 w-1/2`. The grid's own metrics match `SliverAlbumGrid` so the silhouette
  /// is the page, not an approximation of it.
  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 200,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.72,
    ),
    itemCount: tileCount,
    itemBuilder: (context, index) => const Padding(
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: SkeletonBox(height: double.infinity)),
          SizedBox(height: 12),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: 0.75,
            child: SkeletonBox(height: 12),
          ),
          SizedBox(height: 6),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: 0.5,
            child: SkeletonBox(height: 10),
          ),
        ],
      ),
    ),
  );
}

/// "Nothing here" — a statement, not a failure.
class CatalogEmpty extends StatelessWidget {
  const CatalogEmpty({required this.message, super.key, this.hint, this.icon});

  final String message;

  /// The muted second line: what would put something here.
  final String? hint;

  final IconData? icon;

  @override
  Widget build(BuildContext context) =>
      EmptyState(message: message, hint: hint, icon: icon);
}
