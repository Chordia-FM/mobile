import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../catalog/catalog_routes.dart';
import '../catalog/widgets/catalog_state.dart';
import 'data/coverage_format.dart';
import 'data/manager_providers.dart';
import 'data/releases.dart';
import 'manager_routes.dart';
import 'widgets/manager_widgets.dart';

/// One artist from the Hub's MusicBrainz cache — owned or not — and their full discography with
/// what the library holds overlaid on it.
///
/// This is where a follow is made: following an artist is the only outward action the Manager has,
/// and it buys a notification when they release something, not a download.
class DiscoverArtistScreen extends ConsumerWidget {
  const DiscoverArtistScreen({required this.artistMbid, super.key});

  final String artistMbid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final artist = ref.watch(discoverArtistProvider(artistMbid));

    return Scaffold(
      appBar: AppBar(
        title: Text(artist.value?.name ?? t(ManagerKeys.discoverTitle)),
      ),
      body: CatalogBody<ExtArtistDetail>(
        value: artist,
        errorTitle: t(ManagerKeys.loadFailed),
        onRetry: () => ref.invalidate(discoverArtistProvider(artistMbid)),
        skeleton: const CatalogDetailSkeleton(circularArt: true),
        builder: (context, value) => _Loaded(artist: value),
      ),
    );
  }
}

class _Loaded extends ConsumerStatefulWidget {
  const _Loaded({required this.artist});

  final ExtArtistDetail artist;

  @override
  ConsumerState<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends ConsumerState<_Loaded> {
  /// The selected type chip, or null for "All" — the web's `tab === "all"`.
  String? _type;

  @override
  Widget build(BuildContext context) {
    final artist = widget.artist;
    final t = ref.t;
    final theme = Theme.of(context);
    final ownedArtistId = artist.ownedArtistId;

    // Collapsed BEFORE anything is counted or filtered, exactly as the web does: the chips are
    // derived from the grouped list, so a type that only ever appears on a swallowed edition does
    // not get a chip that filters to nothing.
    final releases = groupReleases(artist.releaseGroups);
    final types = presentReleaseTypes(releases);
    final selected = _type;
    final visible = selected == null
        ? releases
        : [
            for (final release in releases)
              if ((release.primaryType ?? 'Other') == selected) release,
          ];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ManagerCard(
                child: Column(
                  children: [
                    CoverArt(
                      sha256: artHashOf(artist.imageUrl),
                      size: 120,
                      shape: BoxShape.circle,
                      fallbackIcon: PhosphorIconsFill.microphoneStage,
                    ),
                    const SizedBox(height: 12),
                    Text(artist.name, style: theme.textTheme.titleLarge),
                    if (artist.disambiguation != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        artist.disambiguation!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (artist.genres != null && artist.genres!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        children: [
                          for (final genre in artist.genres!.take(5))
                            Chip(
                              label: Text(genre),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    FollowButton(
                      artistMbid: artist.mbid,
                      name: artist.name,
                      following: artist.following,
                    ),
                    if (ownedArtistId != null) ...[
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () => context.goToArtist(ownedArtistId),
                        child: Text(t(CommonKeys.actionsGoToArtist)),
                      ),
                      TextButton(
                        onPressed: () =>
                            context.goToArtistCoverage(ownedArtistId),
                        child: Text(t(ManagerKeys.coverageAlbumLabel)),
                      ),
                    ],
                    if (artist.bio != null) ...[
                      const SizedBox(height: 12),
                      Text(artist.bio!, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              if (artist.refreshing)
                ManagerNotice(t(ManagerKeys.artistFetching)),
              ManagerSectionHeader(title: t(ManagerKeys.discoverReleases)),
              // Only worth a control when there is more than one thing to choose between: a chip
              // row reading "All · Album" filters nothing and costs a line.
              if (types.length > 1)
                _TypeChips(
                  types: types,
                  selected: selected,
                  onSelected: (type) => setState(() => _type = type),
                ),
            ],
          ),
        ),
        if (releases.isEmpty)
          SliverToBoxAdapter(
            child: CatalogEmpty(message: t(ManagerKeys.discoverNoResults)),
          )
        else
          SliverList.builder(
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final release = visible[index];
              return ReleaseGroupTile(
                title: release.title,
                owned: release.owned,
                coverUrl: release.coverUrl,
                subtitle: [
                  releaseYear(release.firstReleaseDate),
                  release.primaryType,
                  if (release.versionType == 'live')
                    t(ManagerKeys.discoverVersionLive)
                  else if (release.versionType == 'instrumental')
                    t(ManagerKeys.discoverVersionInstrumental),
                ].where((p) => p != null && p.isNotEmpty).join(' · '),
                onTap: () => context.goToReleaseGroup(release.mbid),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

/// The release-type filter: All, then whichever of Album / EP / Single / Sessions / Other this
/// discography actually contains.
///
/// The web's `TypeChip` row (`manager/discover/artists/$artistMbid.tsx:150-166`). A row of chips
/// rather than a segmented control or a dropdown: the list is one to five entries whose labels are
/// full words in every shipped language, and the count differs per artist.
class _TypeChips extends ConsumerWidget {
  const _TypeChips({
    required this.types,
    required this.selected,
    required this.onSelected,
  });

  final List<String> types;

  /// Null is "All".
  final String? selected;

  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: Text(t(ManagerKeys.discoverAllTypes)),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final type in types)
            ChoiceChip(
              label: Text(t(releaseTypeKey(type))),
              selected: selected == type,
              onSelected: (_) => onSelected(type),
            ),
        ],
      ),
    );
  }
}
