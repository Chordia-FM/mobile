import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
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
                  itemCount: rows.length,
                  itemBuilder: (context, index) =>
                      PlaylistRow(playlist: rows[index]),
                ),
        ),
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
                  itemCount: rows.length,
                  itemBuilder: (context, index) =>
                      SmartPlaylistRow(playlist: rows[index]),
                ),
        ),
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

    return ListTile(
      leading: MosaicCover(
        coverUrl: playlist.coverUrl,
        autoCoverUrls: playlist.autoCoverUrls,
        size: 48,
        semanticLabel: playlist.name,
      ),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => PlaylistDetailScreen(playlistId: playlist.id),
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
    return ListTile(
      leading: MosaicCover(
        coverUrl: playlist.coverUrl,
        autoCoverUrls: playlist.autoCoverUrls,
        size: 48,
        semanticLabel: playlist.name,
      ),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    );
  }
}
