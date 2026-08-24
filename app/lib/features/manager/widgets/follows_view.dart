import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../../catalog/widgets/catalog_state.dart';
import '../../catalog/widgets/list_row.dart';
import '../data/manager_providers.dart';
import '../manager_routes.dart';
import 'manager_widgets.dart';

/// The artists followed for new-release notifications, and the one action they carry: stop.
class FollowsView extends ConsumerWidget {
  const FollowsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final follows = ref.watch(followsControllerProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(followsControllerProvider);
        await ref.read(followsControllerProvider.future);
      },
      child: CatalogBody<List<FollowedArtist>>(
        value: follows,
        errorTitle: t(ManagerKeys.followsLoadFailed),
        onRetry: () => ref.invalidate(followsControllerProvider),
        skeleton: const ManagerListSkeleton(rows: 5),
        builder: (context, rows) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ManagerSectionHeader(
                title: t(ManagerKeys.followsTitle),
                description: t(ManagerKeys.followsSubtitle),
              ),
            ),
            if (rows.isEmpty)
              SliverToBoxAdapter(
                child: CatalogEmpty(message: t(ManagerKeys.followsEmpty)),
              )
            else
              SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) =>
                    _FollowRow(follow: rows[index]),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _FollowRow extends ConsumerWidget {
  const _FollowRow({required this.follow});

  final FollowedArtist follow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return ListRow(
      onTap: () => context.goToDiscoverArtist(follow.artistMbid),
      leading: CoverArt(
        sha256: artHashOf(follow.imageUrl),
        size: 40,
        shape: BoxShape.circle,
        fallbackIcon: PhosphorIconsFill.microphoneStage,
      ),
      // A follow made before the Hub knew the artist's name has only its MBID, and showing that is
      // more honest than an empty row.
      title: Text(follow.name ?? follow.artistMbid),
      subtitle: follow.monitorTypes == null || follow.monitorTypes!.isEmpty
          ? null
          : Text(follow.monitorTypes!.join(' · ')),
      trailing: TextButton(
        onPressed: () async {
          final controller = ref.read(followsControllerProvider.notifier);
          if (await controller.unfollow(follow.artistMbid)) return;
          final failure = controller.failure;
          if (failure != null && context.mounted) {
            showManagerFailure(context, failure, t);
          }
        },
        child: Text(t(ManagerKeys.followsUnfollow)),
      ),
    );
  }
}
