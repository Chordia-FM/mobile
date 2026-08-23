import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../library/data/library_providers.dart';
import '../library/widgets/library_states.dart';
import 'create_playlist_sheet.dart';
import 'data/playlists_providers.dart';

/// Files one or more tracks into a playlist, from anywhere in the app.
///
/// [trackIds] is a list rather than one id so an album, a queue or a selection all use this one
/// sheet — the alternative is three copies of the same picker that drift apart.
///
/// [label] names what is being filed, for the confirmation. It is the track title for one track
/// and the album name for many; a toast that says "Added to Road Trip" without saying what was
/// added is useless when it lands two seconds after somebody moved on.
Future<void> showAddToPlaylistSheet(
  BuildContext context, {
  required List<String> trackIds,
  String? label,
}) {
  if (trackIds.isEmpty) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) =>
        _AddToPlaylistSheet(trackIds: trackIds, label: label),
  );
}

class _AddToPlaylistSheet extends ConsumerStatefulWidget {
  const _AddToPlaylistSheet({required this.trackIds, required this.label});

  final List<String> trackIds;
  final String? label;

  @override
  ConsumerState<_AddToPlaylistSheet> createState() =>
      _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends ConsumerState<_AddToPlaylistSheet> {
  final _query = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final playlists = ref.watch(playlistsProvider);
    final typed = _query.text.trim();
    final rows = [
      for (final playlist in playlists.value ?? const <Playlist>[])
        // Only playlists the viewer may write to. A read-only shared playlist in this list is a
        // row that can only ever fail.
        if ((playlist.owned ?? true) || (playlist.collaborative ?? false))
          if (typed.isEmpty ||
              playlist.name.toLowerCase().contains(typed.toLowerCase()))
            playlist,
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t(PlaylistsKeys.addToPlaylist),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    // What is being filed. A sheet opened by long-pressing one row of forty has to
                    // say which row, or the confirmation two seconds later means nothing.
                    if (widget.label != null)
                      Text(
                        widget.label!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: t(PlaylistsKeys.searchPlaceholder),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add_rounded),
                title: Text(t(PlaylistsKeys.newKey)),
                // Typing a name that matches nothing and then tapping this makes exactly that
                // playlist, rather than opening an empty form the person fills in twice.
                subtitle: typed.isEmpty ? null : Text(typed),
                enabled: !_busy,
                onTap: _busy ? null : _createAndAdd,
              ),
              const Divider(height: 1),
              Flexible(child: _list(playlists, rows)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(AsyncValue<List<Playlist>> playlists, List<Playlist> rows) {
    final t = ref.t;
    if (playlists.value == null) {
      return playlists.hasError
          ? ErrorRetry(
              error: playlists.error!,
              onRetry: () => ref.invalidate(playlistsProvider),
            )
          : const ListSkeleton(rows: 3, height: 56);
    }
    if (rows.isEmpty) {
      return EmptyNote(message: t(PlaylistsKeys.menuEmpty));
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final playlist = rows[index];
        final autoCovers = playlist.autoCoverUrls ?? const <String>[];
        return ListTile(
          leading: CoverArt(
            sha256: artHashOf(
              playlist.coverUrl ??
                  (autoCovers.isEmpty ? null : autoCovers.first),
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
            t(PlaylistsKeys.songCount, {'count': playlist.trackCount}),
          ),
          enabled: !_busy,
          onTap: _busy ? null : () => _addTo(playlist),
        );
      },
    );
  }

  Future<void> _createAndAdd() async {
    setState(() => _busy = true);
    final created = await createPlaylistNamed(
      context,
      ref,
      _query.text.trim().isEmpty
          ? ref.read(translationsProvider)(PlaylistsKeys.newKey)
          : _query.text,
    );
    if (!mounted) return;
    if (created == null) {
      setState(() => _busy = false);
      return;
    }
    ref.invalidate(playlistsProvider);
    await _addTo(created);
  }

  Future<void> _addTo(Playlist playlist) async {
    final api = ref.read(playlistsEditApiProvider);
    if (api == null) return;
    final t = ref.read(translationsProvider).call;
    // The sheet's own context dies with the pop, so the snack bar runs against the page under it.
    final page = Navigator.of(context).context;
    setState(() => _busy = true);

    try {
      // Sequential rather than concurrent: the Hub appends, so a burst of parallel adds would file
      // an album in an order nobody chose.
      for (final trackId in widget.trackIds) {
        await api.addTrack(playlist.id, trackId);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ref.invalidate(playlistsProvider);
      if (page.mounted) {
        ScaffoldMessenger.of(page).showSnackBar(
          SnackBar(
            content: Text(
              widget.trackIds.length == 1
                  ? t(PlaylistsKeys.addedToast, {'playlist': playlist.name})
                  : t(PlaylistsKeys.addedAlbumToast, {
                      'count': widget.trackIds.length,
                      'playlist': playlist.name,
                    }),
            ),
          ),
        );
      }
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t(PlaylistsKeys.addError))));
    }
  }
}
