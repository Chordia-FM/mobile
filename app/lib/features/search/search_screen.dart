import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/catalog_routes.dart';
import '../catalog/widgets/artist_row.dart';
import '../catalog/widgets/catalog_state.dart';
import '../catalog/widgets/entity_menu.dart';
import '../catalog/widgets/list_row.dart';
import '../catalog/widgets/section.dart';
import '../catalog/widgets/track_list.dart';
import '../home/data/discovery_nav.dart';
import 'data/search_controller.dart';
import 'widgets/result_row.dart';

/// The search tab: one field, results grouped by kind, and the terms searched before.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  /// The field owns the text; [SearchState.term] is only ever the term the *results* belong to.
  /// Keeping the two apart is what lets the debounce exist at all.
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(catalogSearchProvider);
    final search = ref.read(catalogSearchProvider.notifier);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _SearchField(
                controller: _field,
                onChanged: search.typed,
                onSubmitted: (value) => unawaited(search.submit(value)),
                onClear: () {
                  _field.clear();
                  search.typed('');
                },
              ),
            ),
            Expanded(child: _body(state)),
          ],
        ),
      ),
    );
  }

  Widget _body(SearchState state) {
    final t = ref.t;
    final search = ref.read(catalogSearchProvider.notifier);

    if (state.error != null) {
      return CatalogError(
        // The server's own words when it gave any — already in the language the app asked for.
        title: state.error is ApiException
            ? (state.error! as ApiException).title
            : t(CommonKeys.errorFailedToLoad),
        error: state.error,
        onRetry: () => unawaited(search.retry()),
      );
    }

    final results = state.results;

    // Typing, with nothing yet to replace: rows in outline, not a spinner over a blank tab.
    if (results == null && state.isLoading) return const _ResultsSkeleton();

    if (results == null) {
      return state.recent.isEmpty
          ? CatalogEmpty(message: t(SearchKeys.prompt))
          : _RecentSearches(
              terms: state.recent,
              onPick: (term) {
                _field
                  ..text = term
                  ..selection = TextSelection.collapsed(offset: term.length);
                unawaited(search.submit(term));
              },
              onClear: () => unawaited(search.clearRecent()),
            );
    }

    if (results.isEmpty) {
      return CatalogEmpty(
        message: t(SearchKeys.noResults, {'term': state.term}),
      );
    }

    return CustomScrollView(
      // Every group is its own lazy list, so a thousand matching tracks build the dozen rows on
      // screen while the headings stay in one flat scroll.
      slivers: [
        for (final group in results.groups) ...[
          SliverToBoxAdapter(child: SectionHeader(title: _groupTitle(group))),
          _groupSliver(group, results, state.term),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  String _groupTitle(SearchGroup group) => ref.t(switch (group) {
    SearchGroup.tracks => CatalogKeys.sectionSongs,
    SearchGroup.albums => CatalogKeys.sectionAlbums,
    SearchGroup.artists => CatalogKeys.sectionArtists,
    SearchGroup.playlists => CatalogKeys.sectionPlaylists,
    SearchGroup.labels => CatalogKeys.sectionLabels,
    SearchGroup.genres => CatalogKeys.sectionGenres,
  });

  Widget _groupSliver(SearchGroup group, SearchGroups results, String term) {
    final t = ref.t;
    switch (group) {
      case SearchGroup.tracks:
        // The catalog's own list: tapping plays the whole group from that row, and the player is
        // told it is playing from a search — which is what the scrobbles are credited to.
        return SliverTrackList(
          tracks: results.tracks,
          playContext: SearchContext(name: term),
        );

      case SearchGroup.albums:
        return SliverList.builder(
          itemCount: results.albums.length,
          itemBuilder: (context, index) {
            final album = results.albums[index];
            return ResultRow(
              imageUrl: album.coverUrl,
              title: album.title,
              subtitle: album.artist,
              onTap: () => context.goToAlbum(album.id),
              // `mbid` travels with the row, which is what lets "Open in Discover" land on the
              // release group rather than being dropped for want of an id the row already had.
              menu: (page, ref) => albumMenu(
                page,
                ref,
                AlbumLike(
                  id: album.id,
                  title: album.title,
                  artist: album.artist,
                  artistId: album.artistId,
                  coverUrl: album.coverUrl,
                  mbid: album.mbid,
                ),
              ),
            );
          },
        );

      case SearchGroup.artists:
        return SliverList.builder(
          itemCount: results.artists.length,
          itemBuilder: (context, index) =>
              ArtistRow(artist: results.artists[index]),
        );

      case SearchGroup.playlists:
        return SliverList.builder(
          itemCount: results.playlists.length,
          itemBuilder: (context, index) {
            final playlist = results.playlists[index];
            final auto = playlist.autoCoverUrls;
            // A playlist with no cover of its own borrows the first tile of its auto mosaic,
            // which is what the web client shows in the same row.
            final cover =
                playlist.coverUrl ??
                (auto == null || auto.isEmpty ? null : auto.first);
            return ResultRow(
              imageUrl: cover,
              title: playlist.name,
              subtitle: t(PlaylistsKeys.songCount, {
                'count': playlist.trackCount,
              }),
              fallbackIcon: Icons.queue_music_rounded,
              onTap: () => context.goToPlaylist(playlist.id),
              menu: (page, ref) => playlistMenu(
                page,
                ref,
                PlaylistLike(
                  id: playlist.id,
                  name: playlist.name,
                  coverUrl: cover,
                ),
              ),
            );
          },
        );

      case SearchGroup.labels:
        return SliverList.builder(
          itemCount: results.labels.length,
          itemBuilder: (context, index) {
            final label = results.labels[index];
            final id = label.id;
            return ResultRow(
              imageUrl: label.logoUrl,
              title: label.name,
              subtitle: t(CatalogKeys.labelAlbumCount, {
                'count': label.albumCount,
              }),
              fallbackIcon: Icons.business_rounded,
              // The synthetic "Unlabeled" bucket carries no id and so has no page of its own —
              // and a menu whose every row leads to that page has nothing to offer either.
              onTap: id == null ? null : () => context.goToLabel(id),
              menu: id == null
                  ? null
                  : (page, ref) => labelMenu(
                      page,
                      ref,
                      labelId: id,
                      name: label.name,
                      logoUrl: label.logoUrl,
                    ),
            );
          },
        );

      case SearchGroup.genres:
        return SliverList.builder(
          itemCount: results.genres.length,
          itemBuilder: (context, index) {
            final genre = results.genres[index];
            return ResultRow(
              imageUrl: genre.imageUrl,
              title: genre.name,
              fallbackIcon: Icons.category_rounded,
              onTap: () => context.goToGenre(genre.slug),
              menu: (page, ref) =>
                  genreMenu(page, ref, slug: genre.slug, name: genre.name),
            );
          },
        );
    }
  }
}

class _SearchField extends ConsumerWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      // No autofocus: this is a tab, not a modal, and a keyboard that opens itself every time the
      // tab is touched covers the results the user came back to read.
      decoration: InputDecoration(
        hintText: t(CatalogKeys.searchPlaceholder),
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
                tooltip: t(CommonKeys.actionsClose),
              ),
      ),
    );
  }
}

/// The terms searched before, newest first.
class _RecentSearches extends ConsumerWidget {
  const _RecentSearches({
    required this.terms,
    required this.onPick,
    required this.onClear,
  });

  final List<String> terms;
  final ValueChanged<String> onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t(SearchKeys.recentTitle),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton(
                onPressed: onClear,
                child: Text(t(CommonKeys.actionsClearAll)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: terms.length,
            itemBuilder: (context, index) => ListRow(
              leading: const Icon(Icons.history_rounded),
              title: Text(
                terms[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => onPick(terms[index]),
            ),
          ),
        ),
      ],
    );
  }
}

/// Rows in outline while the first results are on their way.
class _ResultsSkeleton extends StatelessWidget {
  const _ResultsSkeleton();

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.symmetric(vertical: 12),
    itemCount: 8,
    itemBuilder: (context, index) => const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SkeletonBox(width: 48, height: 48),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 180, height: 14),
                SizedBox(height: 8),
                SkeletonBox(width: 110, height: 11),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
