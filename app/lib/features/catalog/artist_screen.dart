import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart'
    show ArtistContext, RadioContext, StationCursor;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import 'catalog_routes.dart';
import 'data/catalog_api.dart';
import 'data/catalog_providers.dart';
import 'data/playback.dart';
import 'format.dart';
import 'widgets/album_grid.dart';
import 'widgets/artist_row.dart';
import 'widgets/catalog_state.dart';
import 'widgets/entity_links.dart';
import 'widgets/entity_menu.dart';
import 'widgets/section.dart';
import 'widgets/track_list.dart';

/// How many popular tracks show before "Show more".
const _popularPreview = 5;

/// How many label rows show before "Show more".
const _labelsPreview = 4;

/// One artist: who they are, what they made, and what to play.
class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({required this.artistId, super.key});

  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artist = ref.watch(artistDetailProvider(artistId));
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: ref.t(CommonKeys.actionsShare),
            onPressed: () => unawaited(
              shareCatalogLink(
                context,
                ref,
                path: '/artists/$artistId',
                title: artist.value?.name ?? '',
              ),
            ),
          ),
        ],
      ),
      body: CatalogBody<ArtistDetail>(
        value: artist,
        errorTitle: ref.t(ErrorsKeys.catalogArtistLoadFailed),
        onRetry: () => ref.invalidate(artistDetailProvider(artistId)),
        skeleton: const CatalogDetailSkeleton(circularArt: true),
        builder: (context, value) => _ArtistView(artist: value),
      ),
    );
  }
}

class _ArtistView extends ConsumerStatefulWidget {
  const _ArtistView({required this.artist});

  final ArtistDetail artist;

  @override
  ConsumerState<_ArtistView> createState() => _ArtistViewState();
}

class _ArtistViewState extends ConsumerState<_ArtistView> {
  bool _allPopular = false;
  bool _allLabels = false;

  ArtistDetail get artist => widget.artist;

  /// Builds a station around this artist and plays it.
  ///
  /// The station's own cursor travels in the context, so the queue can ask for the next page when
  /// it runs dry rather than ending the listening session at track thirty.
  Future<void> _startRadio() async {
    final player = ref.read(catalogPlayerActionsProvider);
    if (player == null) return;
    try {
      final station = await ref
          .read(catalogApiProvider)
          .station(StationKind.artist, artist.id);
      if (station.tracks.isEmpty) return;
      player
        ..setShuffle(false)
        ..playQueue(
          station.tracks.map(toPlayerTrack).toList(),
          context: RadioContext(
            id: station.seedId,
            name: station.seedName,
            stationCursor: StationCursor(station.nextCursor),
          ),
        );
    } on Object {
      if (mounted) {
        showCatalogSnack(context, ref.t(ErrorsKeys.discoveryRadioFailed));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final playContext = ArtistContext(id: artist.id, name: artist.name);
    final hasPlayer = ref.watch(catalogPlayerActionsProvider) != null;
    final canPlay = hasPlayer && artist.topTracks.isNotEmpty;

    // Three-way split of the discography. Feature appearances get their own shelf rather than
    // sitting unmarked beside the artist's own records, and singles/EPs are separated from albums
    // because a listener looking for "the albums" does not mean forty single sleeves.
    final albums = artist.albums;
    final featuring = albums.where((a) => a.appearsOn ?? false).toList();
    final own = albums.where((a) => !(a.appearsOn ?? false)).toList();
    final singlesAndEps = own.where(_isSingleOrEp).toList();
    final mainAlbums = own.where((a) => !_isSingleOrEp(a)).toList();

    final popular = _allPopular
        ? artist.topTracks
        : artist.topTracks.take(_popularPreview).toList();
    final labels = artist.labels ?? const <ArtistLabel>[];
    final related = artist.related ?? const <ArtistRelation>[];
    final similar = ref.watch(similarArtistsProvider(artist.id)).value;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _ArtistHeader(artist: artist)),
        SliverToBoxAdapter(
          child: CollectionActions(
            onPlay: canPlay
                ? () => playCollection(
                    ref,
                    tracks: artist.topTracks,
                    playContext: playContext,
                  )
                : null,
            onShuffle: canPlay
                ? () => playCollection(
                    ref,
                    tracks: artist.topTracks,
                    playContext: playContext,
                    shuffle: true,
                  )
                : null,
            trailing: [
              IconButton(
                icon: const Icon(Icons.radio_rounded),
                tooltip: t(CatalogKeys.artistRadio),
                onPressed: hasPlayer ? () => unawaited(_startRadio()) : null,
              ),
            ],
          ),
        ),

        if (artist.topTracks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(title: t(CatalogKeys.artistPopular)),
          ),
          SliverTrackList(
            tracks: popular,
            playContext: playContext,
            showArtists: false,
          ),
          if (artist.topTracks.length > _popularPreview)
            SliverToBoxAdapter(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextButton(
                    onPressed: () => setState(() => _allPopular = !_allPopular),
                    child: Text(
                      t(
                        _allPopular
                            ? CommonKeys.actionsShowLess
                            : CommonKeys.actionsSeeMore,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],

        if (mainAlbums.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: t(CatalogKeys.artistAlbums),
              // Unconditional: a section with a page of its own should always say so. Gating it on
              // a count left a phone showing two of five albums with no route to the rest.
              onSeeAll: () => context.goToArtistDiscography(artist.id),
            ),
          ),
          SliverToBoxAdapter(child: AlbumShelf(albums: mainAlbums)),
        ],

        if (singlesAndEps.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: t(CatalogKeys.artistDiscographyAllFilterSinglesEps),
            ),
          ),
          SliverToBoxAdapter(child: AlbumShelf(albums: singlesAndEps)),
        ],

        if (featuring.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: t(CatalogKeys.artistAlbumsFeaturing, {
                'name': artist.name,
              }),
            ),
          ),
          SliverToBoxAdapter(child: AlbumShelf(albums: featuring)),
        ],

        // Co-listen similarity. A different relation from `related` below, which is MusicBrainz
        // aliases and memberships — naming them the same thing is the ambiguity this avoids.
        if (similar != null && similar.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(title: t(CatalogKeys.artistFansAlsoLike)),
          ),
          SliverToBoxAdapter(child: ArtistShelf(artists: similar)),
        ],

        if (related.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: t(CatalogKeys.artistAliasesAndProjects),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 180,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: related.length,
                itemBuilder: (context, index) => ArtistTile(
                  artistId: related[index].id,
                  name: related[index].name,
                  imageUrl: related[index].imageUrl,
                  caption: t(_relationKey(related[index].relation)),
                  width: 130,
                ),
              ),
            ),
          ),
        ],

        if (labels.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(title: t(CatalogKeys.artistLabels)),
          ),
          SliverList.builder(
            itemCount: _allLabels
                ? labels.length
                : labels.length.clamp(0, _labelsPreview),
            itemBuilder: (context, index) => _LabelRow(label: labels[index]),
          ),
          if (labels.length > _labelsPreview)
            SliverToBoxAdapter(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextButton(
                    onPressed: () => setState(() => _allLabels = !_allLabels),
                    child: Text(
                      t(
                        _allLabels
                            ? CommonKeys.actionsShowLess
                            : CommonKeys.actionsShowMore,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

bool _isSingleOrEp(BrowseAlbum album) =>
    album.albumType == 'Single' || album.albumType == 'EP';

/// The catalog key naming a relation bucket, falling back to the generic one for a bucket this
/// build does not know — a newer Hub must not render a raw wire value at somebody.
String _relationKey(String relation) => switch (relation) {
  'alias' => CatalogKeys.artistRelationAlias,
  'member' => CatalogKeys.artistRelationMember,
  _ => CatalogKeys.artistRelationRelated,
};

class _ArtistHeader extends ConsumerWidget {
  const _ArtistHeader({required this.artist});

  final ArtistDetail artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final bannerHash = artHashOf(artist.bannerUrl);
    final facts = joinFacts([
      artist.beginArea ?? artist.area,
      _lifeSpan(ref, artist),
    ]);
    final genres = artist.genres ?? const <String>[];

    return Column(
      children: [
        if (bannerHash != null)
          // Banner art is wide; `CoverArt` is square by contract because it also feeds the media
          // notification. Requesting it at the viewport width and cropping vertically gets the
          // wide framing without a second art pipeline.
          SizedBox(
            height: 160,
            width: double.infinity,
            child: ClipRect(
              child: OverflowBox(
                maxHeight: double.infinity,
                child: CoverArt(
                  sha256: bannerHash,
                  size: MediaQuery.sizeOf(context).width,
                  borderRadius: BorderRadius.zero,
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            children: [
              CoverArt(
                sha256: artHashOf(artist.imageUrl),
                size: 132,
                shape: BoxShape.circle,
                fallbackIcon: Icons.person_rounded,
                semanticLabel: artist.name,
              ),
              const SizedBox(height: 12),
              Text(
                artist.name,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if ((artist.monthlyListeners ?? 0) > 0) ...[
                const SizedBox(height: 6),
                Text(
                  t(PlayerKeys.monthlyListeners, {
                    'count': artist.monthlyListeners,
                  }),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (facts.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  t(CatalogKeys.artistFactsJoin, {'facts': facts}),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (genres.isNotEmpty) ...[
                const SizedBox(height: 10),
                GenreChips(genres: genres),
              ],
              if (artist.bio != null) ...[
                const SizedBox(height: 12),
                ExpandableText(text: artist.bio!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// "Formed 1998" / "Born 1962", with the end year when the life-span has one.
String? _lifeSpan(WidgetRef ref, ArtistDetail artist) {
  final begin = yearOf(artist.beginDate);
  final end = yearOf(artist.endDate);
  if (begin == null) return end == null ? null : '– $end';
  // A group is formed and a person is born; MusicBrainz's type is the only thing that knows which.
  final started = ref.t(
    artist.artistType == 'Person'
        ? CatalogKeys.artistBorn
        : CatalogKeys.artistFormed,
    {'year': begin},
  );
  return end == null ? started : '$started – $end';
}

class _LabelRow extends ConsumerWidget {
  const _LabelRow({required this.label});

  final ArtistLabel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final span = _yearSpan(label.firstYear, label.lastYear);
    final releases = t(CatalogKeys.artistReleaseCount, {
      'count': label.albumCount,
    });
    return ListTile(
      leading: const Icon(Icons.sell_outlined),
      title: Text(label.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        span == null
            ? releases
            : t(CatalogKeys.artistLabelMetaJoin, {
                'span': span,
                'releases': releases,
              }),
      ),
      onTap: () => context.goToLabel(label.id),
    );
  }
}

String? _yearSpan(int? first, int? last) {
  if (first == null && last == null) return null;
  if (first == null) return '$last';
  if (last == null || last == first) return '$first';
  return '$first – $last';
}
