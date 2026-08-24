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
import '../../widgets/tokens.dart';
import 'catalog_routes.dart';
import 'data/catalog_api.dart';
import 'data/catalog_providers.dart';
import 'data/playback.dart';
import 'format.dart';
import 'live_album_screen.dart';
import 'widgets/album_grid.dart';
import 'widgets/artist_row.dart';
import 'widgets/catalog_state.dart';
import 'widgets/entity_links.dart';
import 'widgets/entity_menu.dart';
import 'widgets/list_row.dart';
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
          if (artist.value case final loaded?)
            EntityMenuButton(
              menu: (page, sheetRef) =>
                  artistDetailMenu(page, sheetRef, loaded),
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

    // Split of the discography. Feature appearances get their own shelf rather than sitting
    // unmarked beside the artist's own records, and singles/EPs are separated from albums because
    // a listener looking for "the albums" does not mean forty single sleeves.
    final albums = artist.albums;
    final featuring = albums.where((a) => a.appearsOn ?? false).toList();
    final own = albums.where((a) => !(a.appearsOn ?? false)).toList();
    // Version pressings come out before anything else is decided, the way the web takes them out
    // (`ArtistView.tsx:161-170`): an instrumental or live version shares its TITLE with the studio
    // record it was cut from, so beside it on the main shelf the pair reads as a duplicate.
    final versions = own.where((a) => a.versionType != null).toList();
    final studio = own.where((a) => a.versionType == null).toList();
    final singlesAndEps = studio.where(_isSingleOrEp).toList();
    final mainAlbums = studio.where((a) => !_isSingleOrEp(a)).toList();
    final instrumentals = versions
        .where((a) => a.versionType == 'instrumental')
        .toList();
    final liveVersions = versions
        .where((a) => a.versionType == 'live')
        .toList();
    // Owned live material the Hub can gather into a collection, which is a wider set than the live
    // RELEASES above.
    final hasLiveCollection = (artist.liveTrackCount ?? 0) > 0;

    final popular = _allPopular
        ? artist.topTracks
        : artist.topTracks.take(_popularPreview).toList();
    final labels = artist.labels ?? const <ArtistLabel>[];
    final related = artist.related ?? const <ArtistRelation>[];
    final similar = ref.watch(similarArtistsProvider(artist.id)).value;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: ArtistHeader(artist: artist)),
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
              RingIconButton(
                icon: Icons.radio_rounded,
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
          // The credited line stays ON here, unlike the album page's conditional suppression. An
          // artist's popular list is exactly where "feat. someone" is the fact worth reading, and
          // it is the only tap target the featured artist gets — the web renders `TrackList
          // variant="list"` (ArtistView.tsx:521), which always draws `ArtistLinks`.
          SliverTrackList(tracks: popular, playContext: playContext),
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
          SliverToBoxAdapter(
            child: AlbumShelf(albums: mainAlbums, limit: catalogShelfPreview),
          ),
        ],

        if (singlesAndEps.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: t(CatalogKeys.artistDiscographyAllFilterSinglesEps),
            ),
          ),
          SliverToBoxAdapter(
            child: AlbumShelf(
              albums: singlesAndEps,
              limit: catalogShelfPreview,
            ),
          ),
        ],

        if (instrumentals.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: t(CatalogKeys.artistVersionsInstrumental),
            ),
          ),
          SliverToBoxAdapter(
            child: AlbumShelf(
              albums: instrumentals,
              limit: catalogShelfPreview,
            ),
          ),
        ],

        // The Live shelf is gated on the live TRACK count as well as on live releases, because
        // most of an artist's live material is bonus tracks sitting on ordinary records: an artist
        // with none of the one and plenty of the other had no route to any of it. The card leads
        // the shelf and reaches everything the Hub can gather, releases included.
        if (liveVersions.isNotEmpty || hasLiveCollection) ...[
          SliverToBoxAdapter(
            child: SectionHeader(title: t(CatalogKeys.artistVersionsLive)),
          ),
          SliverToBoxAdapter(
            child: AlbumShelf(
              albums: liveVersions,
              leading: hasLiveCollection
                  ? ArtistLiveCard(artistId: artist.id)
                  : null,
              limit: catalogShelfPreview,
            ),
          ),
        ],

        if (featuring.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: t(CatalogKeys.artistAlbumsFeaturing, {
                'name': artist.name,
              }),
            ),
          ),
          SliverToBoxAdapter(
            child: AlbumShelf(albums: featuring, limit: catalogShelfPreview),
          ),
        ],

        // Co-listen similarity. A different relation from `related` below, which is MusicBrainz
        // aliases and memberships — naming them the same thing is the ambiguity this avoids.
        if (similar != null && similar.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(title: t(CatalogKeys.artistFansAlsoLike)),
          ),
          SliverToBoxAdapter(
            child: ArtistShelf(artists: similar, limit: catalogShelfPreview),
          ),
        ],

        if (related.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: t(CatalogKeys.artistAliasesAndProjects),
            ),
          ),
          // The same shelf box as every other rail on the page. The web lays the relations out as
          // wrapping pills rather than cards, but it does so in a desktop-width flex row; below
          // `md` that degrades to a tall stack, so this keeps the page's one shelf rhythm.
          SliverToBoxAdapter(
            child: CatalogShelf(
              itemCount: related.length,
              itemBuilder: (context, index) => ArtistTile(
                artistId: related[index].id,
                name: related[index].name,
                imageUrl: related[index].imageUrl,
                caption: t(_relationKey(related[index].relation)),
                width: catalogCardWidth,
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

/// The artist hero.
///
/// Ported from the web's below-`md` artist header (`components/catalog/ArtistView.tsx`): banner art
/// across the top at half opacity and faded into the page — or, with no banner of its own, the
/// accent mesh of `DefaultArtistBanner.tsx` filling the whole hero — then the round portrait, the
/// name, monthly listeners, genres, the facts line, and the bio, stacked and left-aligned.
///
/// The order is the web's, and it is not arbitrary: what the artist is called, how many people are
/// listening, what they play, where they are from, then who they are.
class ArtistHeader extends ConsumerWidget {
  const ArtistHeader({required this.artist, super.key});

  final ArtistDetail artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    // `text-sm text-muted-foreground` on monthly listeners, `text-xs` on the facts line.
    final muted = ChordiaType.sm.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final bannerHash = artHashOf(artist.bannerUrl);
    final facts = joinFacts([
      artist.beginArea ?? artist.area,
      _lifeSpan(ref, artist),
    ]);
    final genres = artist.genres ?? const <String>[];

    return HeroSurface(
      // The web's `min-h-80`.
      minHeight: 320,
      background: Stack(
        fit: StackFit.expand,
        children: [
          // No banner art → a soft on-theme glow filling the whole hero edge to edge; with art,
          // the banner band across the top. Either way the scrim below fades it into the page.
          if (bannerHash == null)
            const AccentBanner()
          else
            ArtistBanner(sha256: bannerHash),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: heroScrim(theme.colorScheme)),
            ),
          ),
        ],
      ),
      // `px-4 pt-16 pb-6` — the top inset is what lets the banner read above the portrait.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          catalogGutter,
          64,
          catalogGutter,
          24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverArt(
              // `size-40`, round, with the web's monogram fallback: "an imageless artist reads as
              // a tasteful monogram" rather than as a generic person glyph (`CoverArt.tsx`).
              sha256: artHashOf(artist.imageUrl),
              size: 160,
              shape: BoxShape.circle,
              fallbackIcon: Icons.person_rounded,
              fallbackInitial: artist.name,
              semanticLabel: artist.name,
            ),
            // The web's `gap-5` between the portrait and the metadata column.
            const SizedBox(height: 20),
            Text(
              artist.name,
              // `display-title font-bold text-5xl`. Big on a phone, and deliberately so: this is
              // the one place the artist's name is the page.
              style: theme.textTheme.displaySmall?.copyWith(
                fontSize: 48,
                height: 1.05,
                fontWeight: FontWeight.w700,
              ),
            ),
            if ((artist.monthlyListeners ?? 0) > 0) ...[
              const SizedBox(height: 8),
              Text(
                t(PlayerKeys.monthlyListeners, {
                  'count': artist.monthlyListeners,
                }),
                style: muted,
              ),
            ],
            if (genres.isNotEmpty) ...[
              const SizedBox(height: 8),
              GenreChips(genres: genres),
            ],
            if (facts.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                t(CatalogKeys.artistFactsJoin, {'facts': facts}),
                style: ChordiaType.xs.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (artist.bio != null) ...[
              const SizedBox(height: 12),
              ExpandableText(text: artist.bio!),
            ],
          ],
        ),
      ),
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
    return ListRow(
      leading: const Icon(Icons.sell_outlined, size: 20),
      title: Text(label.name),
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
