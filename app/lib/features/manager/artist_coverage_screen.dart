import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/catalog_routes.dart';
import '../catalog/widgets/catalog_state.dart';
import 'data/coverage_format.dart';
import 'data/manager_providers.dart';
import 'manager_routes.dart';
import 'widgets/manager_widgets.dart';

/// What MusicBrainz says one artist released, against what the library actually holds.
///
/// The missing releases are listed as **information**. There is deliberately no action on one:
/// Chordia does not acquire music, and a row with nothing behind it would be a promise the product
/// cannot keep. Seeing the gap is the point of the page.
class ArtistCoverageScreen extends ConsumerWidget {
  const ArtistCoverageScreen({required this.artistId, super.key});

  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final coverage = ref.watch(artistCoverageProvider(artistId));

    return Scaffold(
      appBar: AppBar(title: Text(coverage.value?.name ?? t(ManagerKeys.title))),
      body: CatalogBody<ArtistCoverage>(
        value: coverage,
        errorTitle: t(ManagerKeys.artistLoadFailed),
        onRetry: () => ref.invalidate(artistCoverageProvider(artistId)),
        skeleton: const CatalogDetailSkeleton(circularArt: true),
        builder: (context, value) => _Loaded(coverage: value),
      ),
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.coverage});

  final ArtistCoverage coverage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final percent = artistCoveragePercentOf(coverage);
    final hasMbid = (coverage.artistMbid ?? '').isNotEmpty;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ManagerCard(
                child: CoverageMeter(
                  label: coverage.name,
                  percent: percent,
                  caption: t(ManagerKeys.coverageOwnedOfTotal, {
                    'owned': coverage.owned.length,
                    'total': coverage.owned.length + coverage.missing.length,
                  }),
                ),
              ),
              if (!hasMbid) ManagerNotice(t(ManagerKeys.artistNoMbid)),
              if (coverage.refreshing)
                ManagerNotice(t(ManagerKeys.artistFetching)),
              ManagerSectionHeader(title: t(ManagerKeys.artistOwned)),
            ],
          ),
        ),
        if (coverage.owned.isEmpty)
          SliverToBoxAdapter(
            child: CatalogEmpty(message: t(ManagerKeys.artistsEmpty)),
          )
        else
          SliverList.builder(
            itemCount: coverage.owned.length,
            itemBuilder: (context, index) {
              final album = coverage.owned[index];
              return ReleaseGroupTile(
                title: album.title,
                owned: true,
                coverUrl: album.coverUrl,
                subtitle: [
                  album.artist,
                  releaseYear(album.releaseDate) ?? album.year?.toString(),
                  album.albumType,
                ].where((p) => p != null && p.isNotEmpty).join(' · '),
                onTap: () => context.goToAlbum(album.id),
              );
            },
          ),
        SliverToBoxAdapter(
          child: ManagerSectionHeader(
            title: t(ManagerKeys.artistMissing),
            description: coverage.missing.isEmpty
                ? null
                : t(ManagerKeys.artistMissingCount, {
                    'count': coverage.missing.length,
                  }),
          ),
        ),
        if (coverage.missing.isEmpty)
          SliverToBoxAdapter(
            child: CatalogEmpty(
              message: hasMbid
                  ? t(ManagerKeys.artistNoMissing)
                  : t(ManagerKeys.artistNoMbid),
            ),
          )
        else
          SliverList.builder(
            itemCount: coverage.missing.length,
            itemBuilder: (context, index) {
              final release = coverage.missing[index];
              return ReleaseGroupTile(
                title: release.title,
                owned: false,
                coverUrl: release.coverUrl,
                subtitle: [
                  releaseYear(release.firstReleaseDate),
                  release.primaryType,
                  ...?release.secondaryTypes,
                ].where((p) => p != null && p.isNotEmpty).join(' · '),
                // The only thing a missing release offers: its tracklist, so you can see which
                // songs on it you already have from somewhere else.
                onTap: () => context.goToReleaseGroup(release.mbid),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
