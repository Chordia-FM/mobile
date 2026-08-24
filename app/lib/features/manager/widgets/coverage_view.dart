import 'dart:async';

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
import '../data/coverage_format.dart';
import '../data/manager_providers.dart';
import '../manager_routes.dart';
import 'manager_widgets.dart';

/// The Manager's headline: how much of what you own is complete, which libraries that is measured
/// over, and the artists to open for the detail.
class CoverageView extends ConsumerWidget {
  const CoverageView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final coverage = ref.watch(coverageControllerProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(coverageControllerProvider)
          ..invalidate(ownedArtistsProvider);
        await ref.read(coverageControllerProvider.future);
      },
      child: CatalogBody<CoverageSummary>(
        value: coverage,
        errorTitle: t(ManagerKeys.loadFailed),
        onRetry: () => ref.invalidate(coverageControllerProvider),
        skeleton: const ManagerListSkeleton(),
        builder: (context, summary) => _Loaded(summary: summary),
      ),
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.summary});

  final CoverageSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final artists = ref.watch(ownedArtistsProvider);
    final rows = artists.value ?? const <BrowseArtist>[];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (coverageIsUnmeasured(summary))
                CatalogEmpty(message: t(ManagerKeys.coverageEmpty))
              else
                _Headline(summary: summary),
              if (summary.pendingArtists > 0) ...[
                ManagerNotice(t(ManagerKeys.coverageFetching)),
                ManagerNotice(
                  t(ManagerKeys.coveragePending, {
                    'count': summary.pendingArtists,
                  }),
                  icon: PhosphorIconsRegular.hourglass,
                ),
              ],
              ManagerSectionHeader(
                title: t(ManagerKeys.librariesTitle),
                description: t(ManagerKeys.librariesHint),
              ),
              const _LibraryScope(),
              _ExclusionList(summary: summary),
              ManagerSectionHeader(
                title: t(ManagerKeys.artistsTitle),
                description: t(ManagerKeys.artistsSubtitle),
              ),
            ],
          ),
        ),
        if (artists.hasError && rows.isEmpty)
          SliverToBoxAdapter(
            child: CatalogError(
              title: t(ManagerKeys.loadFailed),
              error: artists.error,
              onRetry: () => ref.invalidate(ownedArtistsProvider),
            ),
          )
        else if (artists.isLoading && rows.isEmpty)
          const SliverToBoxAdapter(child: ManagerRowsSkeleton(rows: 4))
        else if (rows.isEmpty)
          SliverToBoxAdapter(
            child: CatalogEmpty(message: t(ManagerKeys.artistsEmpty)),
          )
        else
          SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final artist = rows[index];
              return ListRow(
                leading: CoverArt(
                  sha256: artHashOf(artist.imageUrl),
                  size: 40,
                  shape: BoxShape.circle,
                ),
                title: Text(artist.name),
                subtitle: Text(
                  t(CatalogKeys.artistCardAlbumCount, {
                    'count': artist.albumCount,
                  }),
                ),
                trailing: listRowChevron,
                onTap: () => context.goToArtistCoverage(artist.id),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _Headline extends ConsumerWidget {
  const _Headline({required this.summary});

  final CoverageSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return ManagerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CoverageMeter(
            label: t(ManagerKeys.coverageAlbumLabel),
            percent: albumCoveragePercent(summary),
            caption: t(ManagerKeys.coverageOwnedOfTotal, {
              'owned': summary.ownedRgs,
              'total': summary.totalRgs,
            }),
          ),
          const SizedBox(height: 20),
          CoverageMeter(
            label: t(ManagerKeys.coverageArtistLabel),
            percent: artistCoveragePercent(summary),
            caption: t(ManagerKeys.coverageTouched, {
              'count': summary.touchedArtists,
            }),
          ),
          const SizedBox(height: 12),
          Text(
            t(ManagerKeys.coverageComplete, {'count': summary.completeArtists}),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The one switch that changes the scope rather than one library: whether shared-with-me libraries
/// count at all.
class _LibraryScope extends ConsumerWidget {
  const _LibraryScope();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final prefs = ref.watch(managerPrefsControllerProvider);
    final included = prefs.value?.includeShared ?? true;
    // Disabled until the document has arrived: a confident "on" for something that is off is a lie
    // the next launch silently corrects.
    Future<void> set(bool include) async {
      final controller = ref.read(managerPrefsControllerProvider.notifier);
      if (await controller.setIncludeShared(include: include)) return;
      final failure = controller.failure;
      if (failure != null && context.mounted) {
        showManagerFailure(context, failure, t);
      }
    }

    // `settings/Toggle.tsx`: the label reads as the row and the control sits at its end.
    return ListRow(
      title: Text(t(ManagerKeys.librariesIncludeShared)),
      onTap: prefs.hasValue ? () => unawaited(set(!included)) : null,
      trailing: Switch(
        value: included,
        onChanged: prefs.hasValue ? (v) => unawaited(set(v)) : null,
      ),
    );
  }
}

/// Which libraries count toward coverage. Unchecking one excludes it.
class _ExclusionList extends ConsumerWidget {
  const _ExclusionList({required this.summary});

  final CoverageSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    if (summary.perLibrary.isEmpty) {
      return CatalogEmpty(message: t(ManagerKeys.coverageEmpty));
    }
    Future<void> exclude(String libraryId, {required bool excluded}) async {
      final controller = ref.read(coverageControllerProvider.notifier);
      if (await controller.setExcluded(libraryId, excluded: excluded)) return;
      final failure = controller.failure;
      if (failure != null && context.mounted) {
        showManagerFailure(context, failure, t);
      }
    }

    return Column(
      children: [
        for (final library in summary.perLibrary)
          ListRow(
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    library.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                OwnedBadge(
                  owned: library.owned,
                  ownedLabel: t(ManagerKeys.librariesOwned),
                  missingLabel: t(ManagerKeys.librariesShared),
                ),
              ],
            ),
            subtitle: Text(
              t(ManagerKeys.librariesCounts, {
                'tracks': library.trackCount,
                'albums': library.albumCount,
                'artists': library.artistCount,
              }),
            ),
            // The stored flag is "excluded"; the box asks the positive question, because a list
            // of boxes you tick to leave things OUT is the one nobody reads correctly.
            trailing: Checkbox(
              value: !library.excluded,
              onChanged: (included) => unawaited(
                exclude(library.libraryId, excluded: !(included ?? true)),
              ),
            ),
            onTap: () => unawaited(
              exclude(library.libraryId, excluded: !library.excluded),
            ),
          ),
      ],
    );
  }
}
