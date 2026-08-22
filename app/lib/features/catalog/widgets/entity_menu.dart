import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/providers.dart';
import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../catalog_routes.dart';
import '../data/catalog_api.dart';
import '../data/catalog_providers.dart';
import '../data/playback.dart';

/// A link to this entity on the hub's public web frontend, or null when the hub never told us
/// where that is.
///
/// The `/app` prefix the client navigates under is deliberately absent: shared links resolve
/// through the frontend's public redirect stubs (`/albums/{id}`, `/artists/{id}`, `/tracks/{id}`),
/// and a link into `/app` would 404 for anyone not already signed in on that device.
Uri? shareUrlFor(WidgetRef ref, String path) {
  final frontend = ref.read(activeHubProvider)?.frontendUrl;
  return frontend?.resolve(path);
}

/// Opens the platform share sheet, or says nothing can be shared.
Future<void> shareCatalogLink(
  BuildContext context,
  WidgetRef ref, {
  required String path,
  required String title,
}) async {
  final url = shareUrlFor(ref, path);
  if (url == null) {
    if (context.mounted) showCatalogSnack(context, ref.t(ErrorsKeys.generic));
    return;
  }
  await SharePlus.instance.share(ShareParams(uri: url, title: title));
}

/// One line of feedback, in the app's own snack bar styling.
void showCatalogSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// The actions a track offers, from its ⋮ button or a long press on its row.
///
/// A bottom sheet rather than a popup menu: these are the same actions the web client puts in a
/// right-click menu, and on a phone a sheet is the only shape that can hold a header saying WHAT is
/// being acted on — which matters when the menu was opened by long-pressing one row of forty.
Future<void> showTrackMenu(
  BuildContext context,
  WidgetRef ref,
  BrowseTrack track,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheetContext) => _TrackMenuSheet(track: track),
);

class _TrackMenuSheet extends ConsumerWidget {
  const _TrackMenuSheet({required this.track});

  final BrowseTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final player = ref.watch(catalogPlayerActionsProvider);
    final liked = ref.watch(likedTrackIdsProvider).value?.contains(track.id);

    // The sheet's own context dies with the pop, so anything that outlives it — a snack bar, a
    // navigation — has to run against the page underneath.
    final page = Navigator.of(context).context;

    void close() => Navigator.of(context).pop();

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CoverArt(sha256: artHashOf(track.coverUrl), size: 48),
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded),
              title: Text(t(PlayerKeys.queuePlayNext)),
              enabled: player != null,
              onTap: () {
                close();
                player?.playNext(toPlayerTrack(track));
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: Text(t(PlayerKeys.queueAdd)),
              enabled: player != null,
              onTap: () {
                close();
                player?.enqueue(toPlayerTrack(track));
              },
            ),
            ListTile(
              leading: Icon(
                liked ?? false
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
              title: Text(
                t(
                  liked ?? false
                      ? LibraryKeys.likedRemove
                      : LibraryKeys.likedSave,
                ),
              ),
              // Until the liked set has loaded there is no state to flip, and a heart that reports
              // the wrong state is worse than one that is briefly unavailable.
              enabled: liked != null,
              onTap: () async {
                close();
                try {
                  await ref
                      .read(likedTrackIdsProvider.notifier)
                      .toggle(track.id);
                } on Object {
                  if (page.mounted) {
                    showCatalogSnack(page, t(ErrorsKeys.changeFailed));
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: Text(t(PlaylistsKeys.addToPlaylist)),
              onTap: () {
                close();
                unawaited(showAddToPlaylist(page, track));
              },
            ),
            if (track.artistId != null)
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(t(CommonKeys.actionsGoToArtist)),
                onTap: () {
                  close();
                  page.goToArtist(track.artistId!);
                },
              ),
            if (track.albumId != null)
              ListTile(
                leading: const Icon(Icons.album_outlined),
                title: Text(t(CommonKeys.actionsGoToAlbum)),
                onTap: () {
                  close();
                  page.goToAlbum(track.albumId!);
                },
              ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: Text(t(CommonKeys.actionsShare)),
              onTap: () {
                close();
                unawaited(
                  shareCatalogLink(
                    page,
                    ref,
                    path: '/tracks/${track.id}',
                    title: track.title,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks one of the caller's playlists and adds [track] to it.
Future<void> showAddToPlaylist(BuildContext context, BrowseTrack track) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _PlaylistPickerSheet(track: track),
    );

class _PlaylistPickerSheet extends ConsumerWidget {
  const _PlaylistPickerSheet({required this.track});

  final BrowseTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final playlists = ref.watch(playlistsProvider);
    final page = Navigator.of(context).context;

    Future<void> add(Playlist playlist) async {
      Navigator.of(context).pop();
      try {
        await ref
            .read(catalogApiProvider)
            .addPlaylistTrack(playlist.id, track.id);
        if (page.mounted) {
          showCatalogSnack(
            page,
            t(PlaylistsKeys.addedToast, {'playlist': playlist.name}),
          );
        }
      } on Object {
        if (page.mounted) showCatalogSnack(page, t(ErrorsKeys.changeFailed));
      }
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: _pickerBody(context, ref, playlists, add),
      ),
    );
  }

  Widget _pickerBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Playlist>> playlists,
    Future<void> Function(Playlist playlist) add,
  ) {
    final t = ref.t;
    final loaded = playlists.value;

    if (loaded == null) {
      return playlists.hasError
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(t(ErrorsKeys.failedToLoad)),
            )
          : const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
    }
    if (loaded.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(t(PlaylistsKeys.menuEmpty)),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: loaded.length,
      itemBuilder: (context, index) {
        final playlist = loaded[index];
        final autoCovers = playlist.autoCoverUrls;
        return ListTile(
          leading: CoverArt(
            sha256: artHashOf(
              playlist.coverUrl ??
                  (autoCovers == null || autoCovers.isEmpty
                      ? null
                      : autoCovers.first),
            ),
            size: 44,
            fallbackIcon: Icons.queue_music_rounded,
          ),
          title: Text(
            playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            t(CatalogKeys.songCount, {'count': playlist.trackCount}),
          ),
          onTap: () => unawaited(add(playlist)),
        );
      },
    );
  }
}
