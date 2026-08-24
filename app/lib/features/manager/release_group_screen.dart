import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../catalog/format.dart';
import '../catalog/widgets/catalog_state.dart';
import '../catalog/widgets/list_row.dart';
import 'data/manager_providers.dart';
import 'manager_routes.dart';
import 'widgets/manager_widgets.dart';

/// Every edition MusicBrainz knows of one release group, each track flagged owned or not.
///
/// Editions are shown side by side rather than merged because a Deluxe and a Standard are not the
/// same tracklist, and "you own 12 of 18" is meaningless until you know which of the two it counts.
class ReleaseGroupScreen extends ConsumerWidget {
  const ReleaseGroupScreen({required this.releaseGroupMbid, super.key});

  final String releaseGroupMbid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final coverage = ref.watch(releaseGroupCoverageProvider(releaseGroupMbid));

    return Scaffold(
      appBar: AppBar(
        title: Text(coverage.value?.title ?? t(ManagerKeys.title)),
      ),
      body: CatalogBody<AlbumTrackCoverage>(
        value: coverage,
        errorTitle: t(ManagerKeys.albumLoadFailed),
        onRetry: () =>
            ref.invalidate(releaseGroupCoverageProvider(releaseGroupMbid)),
        skeleton: const CatalogDetailSkeleton(),
        builder: (context, value) => _Loaded(coverage: value),
      ),
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.coverage});

  final AlbumTrackCoverage coverage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final artistMbid = coverage.artistMbid;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ManagerCard(
          child: Row(
            children: [
              CoverArt(sha256: artHashOf(coverage.coverUrl), size: 88),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coverage.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (coverage.artistName != null) ...[
                      const SizedBox(height: 4),
                      if (artistMbid == null || artistMbid.isEmpty)
                        Text(coverage.artistName!)
                      else
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () =>
                              context.goToDiscoverArtist(artistMbid),
                          child: Text(coverage.artistName!),
                        ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      t(ManagerKeys.albumEditionCount, {
                        'count': coverage.editions.length,
                      }),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (coverage.refreshing) ManagerNotice(t(ManagerKeys.albumFetching)),
        if (coverage.editions.isEmpty)
          CatalogEmpty(message: t(ManagerKeys.albumNoTracks))
        else
          for (final edition in coverage.editions) _Edition(edition: edition),
      ],
    );
  }
}

class _Edition extends ConsumerWidget {
  const _Edition({required this.edition});

  final AlbumEdition edition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);

    // Grouped rather than a flat list: a two-disc edition whose second disc restarts at track 1
    // reads as a numbering bug without the disc heading between them.
    final discs = <int, List<ExtRecording>>{};
    for (final track in edition.tracks) {
      discs.putIfAbsent(track.discNo, () => []).add(track);
    }
    final discNumbers = discs.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ManagerSectionHeader(
          title: edition.isRemaster
              ? '${edition.label} · ${t(ManagerKeys.albumRemaster)}'
              : edition.label,
          description: t(ManagerKeys.albumCoverage, {
            'owned': edition.ownedCount,
            'total': edition.total,
          }),
        ),
        if (edition.tracks.isEmpty)
          CatalogEmpty(message: t(ManagerKeys.albumNoTracks))
        else
          for (final disc in discNumbers) ...[
            if (discNumbers.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  t(ManagerKeys.albumDisc, {'n': disc}),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final track in discs[disc]!)
              ListRow(
                leading: Icon(
                  (track.owned ?? false)
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: (track.owned ?? false)
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(
                  '${track.position}. ${track.title}',
                  // A track the library does not hold is information, not an offer, and reads a
                  // step back from the ones it does.
                  style: (track.owned ?? false)
                      ? null
                      : TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                trailing: track.lengthMs == null
                    ? null
                    : Text(formatTrackLength(track.lengthMs!)),
              ),
          ],
      ],
    );
  }
}
