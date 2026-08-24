import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/entity_menu.dart';
import '../catalog/widgets/list_row.dart';
import '../playlists/create_playlist_sheet.dart';
import '../playlists/data/smart_model.dart';
import '../playlists/smart_rules_screen.dart';
import 'data/library_providers.dart';
import 'playlist_detail_screen.dart';
import 'smart_playlist_screen.dart';
import 'widgets/collection_header.dart';
import 'widgets/library_states.dart';

/// Every hand-built playlist the viewer owns or collaborates on.
class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final playlists = ref.watch(playlistsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t(LibraryKeys.sidebarPlaylists))),
      // The only place in the app a playlist can be made from nothing. The picker's "New playlist"
      // row needs a track to be filing somewhere first, so without this a listener could not make
      // an empty playlist at all.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: Text(t(PlaylistsKeys.newKey)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(playlistsProvider),
        child: playlists.when(
          loading: () => const ListSkeleton(),
          error: (error, stack) => ErrorRetry(
            error: error,
            onRetry: () => ref.invalidate(playlistsProvider),
          ),
          data: (rows) => rows.isEmpty
              ? EmptyNote(
                  message: t(PlaylistsKeys.emptyStateTitle),
                  icon: Icons.queue_music_rounded,
                )
              : ListView.builder(
                  // Room for the button, which would otherwise sit on top of the last row.
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: rows.length,
                  itemBuilder: (context, index) =>
                      PlaylistRow(playlist: rows[index]),
                ),
        ),
      ),
    );
  }

  /// Makes one, then opens it — a new empty playlist that stays on the list behind you is a thing
  /// you have to find again before you can put anything in it.
  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final created = await showCreatePlaylistSheet(context, ref);
    if (created == null || !context.mounted) return;
    ref.invalidate(playlistsProvider);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PlaylistDetailScreen(playlistId: created.id),
      ),
    );
  }
}

/// Every rule-driven playlist.
class SmartPlaylistsScreen extends ConsumerWidget {
  const SmartPlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final playlists = ref.watch(smartPlaylistsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t(PlaylistsKeys.smartKindLabel))),
      // Straight into the rule builder rather than a name-only sheet: a smart playlist saved with
      // no rules is one that matches the entire library, which is never what anybody meant.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: Text(t(PlaylistsKeys.smartNew)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(smartPlaylistsProvider),
        child: playlists.when(
          loading: () => const ListSkeleton(),
          error: (error, stack) => ErrorRetry(
            error: error,
            onRetry: () => ref.invalidate(smartPlaylistsProvider),
          ),
          data: (rows) => rows.isEmpty
              ? EmptyNote(
                  message: t(PlaylistsKeys.smartDescription),
                  icon: Icons.auto_awesome_rounded,
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: rows.length,
                  itemBuilder: (context, index) =>
                      SmartPlaylistRow(playlist: rows[index]),
                ),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final id = await openSmartRules(context);
    if (id == null || !context.mounted) return;
    ref.invalidate(smartPlaylistsProvider);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => SmartPlaylistScreen(playlistId: id),
      ),
    );
  }
}

/// One playlist in a list, wearing the same mosaic its own page does.
class PlaylistRow extends ConsumerWidget {
  const PlaylistRow({required this.playlist, super.key});

  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final subtitle = [
      t(PlaylistsKeys.songCount, {'count': playlist.trackCount}),
      if (playlist.owned == false) t(PlaylistsKeys.sharedWithYou).trim(),
      if (playlist.collaborative ?? false)
        t(PlaylistsKeys.collaboratorsCollaborative),
    ].join(' · ');
    final auto = playlist.autoCoverUrls;

    return EntityMenuGesture(
      // The card menu, not the page's: the editing sheets and the two destructive confirmations
      // all need a host that owns them, and this row owns none of them. Everything a playlist can
      // do without one — play, queue, radio, pin, download, share — is here, which is the whole
      // reason the Library tab's rows were the last playlists in the app with no menu at all.
      menu: (page, sheetRef) => playlistMenu(
        page,
        sheetRef,
        PlaylistLike(
          id: playlist.id,
          name: playlist.name,
          // The mosaic's first tile when the playlist has no cover of its own, so the sheet's
          // header shows what the row shows rather than a bare glyph.
          coverUrl:
              playlist.coverUrl ??
              (auto == null || auto.isEmpty ? null : auto.first),
        ),
      ),
      child: ListRow(
        leading: MosaicCover(
          coverUrl: playlist.coverUrl,
          autoCoverUrls: playlist.autoCoverUrls,
          size: 40,
          semanticLabel: playlist.name,
        ),
        title: Text(playlist.name),
        subtitle: Text(subtitle),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => PlaylistDetailScreen(playlistId: playlist.id),
          ),
        ),
      ),
    );
  }
}

class SmartPlaylistRow extends ConsumerWidget {
  const SmartPlaylistRow({required this.playlist, super.key});

  final SmartPlaylist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final auto = playlist.autoCoverUrls;

    // A long press opened the rule builder and nothing else, which quietly said a smart playlist is
    // a lesser object: it plays, queues, pins, downloads, seeds a station and has a shareable page
    // exactly like any other playlist. `useSmartPlaylistMenu` on the web makes the same point in
    // its own words, and Edit is one row of that menu rather than the whole of it.
    return EntityMenuGesture(
      menu: (page, sheetRef) => smartPlaylistMenu(
        page,
        sheetRef,
        PlaylistLike(
          id: playlist.id,
          name: playlist.name,
          coverUrl:
              playlist.coverUrl ??
              (auto == null || auto.isEmpty ? null : auto.first),
        ),
        // The summary row already carries the whole rule set, so the builder opens from here
        // without loading the snapshot first. Refresh and Delete are absent because this row
        // cannot honour them: both want a confirmation the list does not own.
        onEdit: () async {
          final saved = await openSmartRules(
            context,
            existing: SmartSource.ofSummary(playlist),
          );
          if (saved != null) ref.invalidate(smartPlaylistsProvider);
        },
      ),
      child: ListRow(
        leading: MosaicCover(
          coverUrl: playlist.coverUrl,
          autoCoverUrls: playlist.autoCoverUrls,
          size: 40,
          semanticLabel: playlist.name,
        ),
        title: Text(playlist.name),
        // `track_count` is the size of the last SNAPSHOT, not of the rules — a smart playlist that
        // has never been resolved honestly has none to report.
        subtitle: Text(
          playlist.trackCount == null
              ? t(PlaylistsKeys.smartRefreshNeverRefreshed)
              : t(PlaylistsKeys.songCount, {'count': playlist.trackCount}),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => SmartPlaylistScreen(playlistId: playlist.id),
          ),
        ),
      ),
    );
  }
}
