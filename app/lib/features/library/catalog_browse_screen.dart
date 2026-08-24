import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/list_row.dart';
import '../../widgets/cover_art.dart';
import 'data/library_providers.dart';
import 'widgets/library_states.dart';

/// How the artists list is ordered. Mirrors the web client's `CatalogFilterBar`, including its
/// order: name first because that is how somebody looks for one they already have in mind.
enum ArtistSort { name, albums, tracks }

/// Every artist across the libraries the viewer can reach, searchable.
class ArtistsScreen extends ConsumerStatefulWidget {
  const ArtistsScreen({super.key, this.libraryId});

  /// Scopes the list to one library. Null means every library the viewer can reach.
  final String? libraryId;

  @override
  ConsumerState<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends ConsumerState<ArtistsScreen> {
  final _search = TextEditingController();
  ArtistSort _sort = ArtistSort.name;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final artists = ref.watch(catalogArtistsProvider(widget.libraryId));

    return Scaffold(
      appBar: AppBar(
        title: Text(t(LibraryKeys.artistsTitle)),
        actions: [
          PopupMenuButton<ArtistSort>(
            tooltip: t(LibraryKeys.artistsSortLabel),
            icon: const Icon(PhosphorIconsRegular.arrowsDownUp),
            initialValue: _sort,
            onSelected: (sort) => setState(() => _sort = sort),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: ArtistSort.name,
                child: Text(t(LibraryKeys.artistsSortName)),
              ),
              PopupMenuItem(
                value: ArtistSort.albums,
                child: Text(t(LibraryKeys.artistsSortAlbums)),
              ),
              PopupMenuItem(
                value: ArtistSort.tracks,
                child: Text(t(LibraryKeys.artistsSortTracks)),
              ),
            ],
          ),
        ],
      ),
      body: artists.when(
        loading: () => const ListSkeleton(),
        error: (error, stack) => ErrorRetry(
          error: error,
          onRetry: () =>
              ref.invalidate(catalogArtistsProvider(widget.libraryId)),
        ),
        data: (all) => _list(all),
      ),
    );
  }

  Widget _list(List<BrowseArtist> all) {
    final t = ref.t;
    final handoff = ref.watch(libraryHandoffProvider);
    final query = _search.text.trim();
    final rows = filterArtists(all, query, _sort);

    return Column(
      children: [
        // Outside the empty branches so the box does not appear, vanish and reappear as the list
        // loads, and so a typed query survives a background refresh.
        if (all.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
                hintText: t(LibraryKeys.artistsSearchPlaceholder),
              ),
            ),
          ),
        Expanded(
          child: all.isEmpty
              ? EmptyNote(message: t(LibraryKeys.artistsEmpty))
              // Distinct from an empty library: one says there is nothing here, the other says
              // the search matched nothing, and telling somebody their library is empty when it
              // is not is the more alarming of the two.
              : rows.isEmpty
              ? EmptyNote(
                  message: t(LibraryKeys.artistsNoMatches, {'query': query}),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final artist = rows[index];
                    return ListRow(
                      leading: CoverArt(
                        sha256: artHashOf(artist.imageUrl),
                        size: 40,
                        shape: BoxShape.circle,
                        fallbackIcon: PhosphorIconsFill.microphoneStage,
                      ),
                      title: Text(artist.name),
                      subtitle: Text(
                        [
                          t(CatalogKeys.artistCardAlbumCount, {
                            'count': artist.albumCount,
                          }),
                          t(LibraryKeys.trackCount, {
                            'count': artist.trackCount,
                          }),
                        ].join(' · '),
                      ),
                      onTap: handoff == null
                          ? null
                          : () => handoff.openArtist(context, artist.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Filters and orders the artist list.
///
/// A pure function so the ordering can be reasoned about without a widget: "most albums" ties are
/// broken by name, or a rebuild would shuffle equal-ranked artists into a different order each
/// time the list is scrolled back to.
List<BrowseArtist> filterArtists(
  List<BrowseArtist> all,
  String query,
  ArtistSort sort,
) {
  final needle = query.trim().toLowerCase();
  final rows =
      [
        for (final artist in all)
          if (needle.isEmpty || artist.name.toLowerCase().contains(needle))
            artist,
      ]..sort(
        (a, b) => switch (sort) {
          ArtistSort.name => a.name.toLowerCase().compareTo(
            b.name.toLowerCase(),
          ),
          ArtistSort.albums =>
            b.albumCount != a.albumCount
                ? b.albumCount.compareTo(a.albumCount)
                : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          ArtistSort.tracks =>
            b.trackCount != a.trackCount
                ? b.trackCount.compareTo(a.trackCount)
                : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        },
      );
  return rows;
}

/// Albums that most recently appeared in the viewer's libraries.
///
/// Deliberately titled "Recently added" rather than "Albums": the Hub has no flat album browse —
/// the endpoint behind this is capped at fifty server-side — and a screen called Albums that shows
/// fifty of them would be a lie about the size of somebody's collection.
class RecentAlbumsScreen extends ConsumerWidget {
  const RecentAlbumsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final albums = ref.watch(recentAlbumsProvider);
    final handoff = ref.watch(libraryHandoffProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t(DiscoveryKeys.shelfRecentlyAdded))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(recentAlbumsProvider),
        child: albums.when(
          loading: () => const ListSkeleton(),
          error: (error, stack) => ErrorRetry(
            error: error,
            onRetry: () => ref.invalidate(recentAlbumsProvider),
          ),
          data: (rows) => rows.isEmpty
              ? EmptyNote(
                  message: t(DiscoveryKeys.homeEmptyState),
                  icon: PhosphorIcons.disc(),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final album = rows[index];
                    return ListRow(
                      leading: CoverArt(
                        sha256: artHashOf(album.coverUrl),
                        size: 40,
                        fallbackIcon: PhosphorIconsFill.musicNotes,
                      ),
                      title: Text(album.title),
                      subtitle: Text(
                        [
                          album.artist,
                          if (album.year != null) '${album.year}',
                        ].join(' · '),
                      ),
                      onTap: handoff == null
                          ? null
                          : () => handoff.openAlbum(context, album.id),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
