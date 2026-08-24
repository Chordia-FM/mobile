import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/album_grid.dart';
import '../catalog/widgets/catalog_state.dart';
import '../catalog/widgets/section.dart';
import 'data/see_all.dart';
import 'widgets/cards.dart';

/// The pages behind home's two "See all" links, ported from the web's `/app/jump-back-in` and
/// `/app/made-for-you`.
///
/// Both are the same page with a different source: a heading, a grid of the same cards the shelf
/// showed, and a sentence when there is nothing to show. That is exactly what the web builds — two
/// routes, one `DISCOVERY_GRID`, the shelf's own `RecentCard`/`MixCard` inside it — so the phone's
/// version is one widget parameterised twice rather than two.
class JumpBackInScreen extends ConsumerWidget {
  const JumpBackInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _SeeAllPage<RecentItem>(
    title: ref.t(DiscoveryKeys.shelfJumpBackIn),
    emptyMessage: ref.t(DiscoveryKeys.jumpBackInEmptyState),
    value: ref.watch(jumpBackInPageProvider),
    onRetry: () => ref.invalidate(jumpBackInPageProvider),
    tile: (item) => RecentCard(item: item),
  );
}

class MadeForYouScreen extends ConsumerWidget {
  const MadeForYouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _SeeAllPage<DailyMix>(
    title: ref.t(DiscoveryKeys.madeForYouTitle),
    emptyMessage: ref.t(DiscoveryKeys.madeForYouEmptyState),
    value: ref.watch(madeForYouPageProvider),
    onRetry: () => ref.invalidate(madeForYouPageProvider),
    tile: (mix) => MixCard(mix: mix),
  );
}

class _SeeAllPage<T> extends ConsumerWidget {
  const _SeeAllPage({
    required this.title,
    required this.emptyMessage,
    required this.value,
    required this.onRetry,
    required this.tile,
    super.key,
  });

  final String title;
  final String emptyMessage;
  final AsyncValue<List<T>> value;
  final VoidCallback onRetry;
  final Widget Function(T item) tile;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: CatalogBody<List<T>>(
      value: value,
      errorTitle: ref.t(CommonKeys.errorFailedToLoad),
      onRetry: onRetry,
      skeleton: const CatalogGridSkeleton(),
      builder: (context, items) => items.isEmpty
          ? CatalogEmpty(message: emptyMessage)
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: catalogGutter,
                    vertical: 16,
                  ),
                  sliver: SliverGrid.builder(
                    // `SliverAlbumGrid`'s metrics, so a mix tile and an album tile on two pages of
                    // the same app are the same object at the same size.
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          mainAxisSpacing: catalogCardGap,
                          crossAxisSpacing: catalogCardGap,
                          childAspectRatio: 0.74,
                        ),
                    itemCount: items.length,
                    itemBuilder: (context, index) => tile(items[index]),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
    ),
  );
}
