import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/tokens.dart';
import '../catalog/widgets/entity_menu.dart';
import '../social/social_routes.dart';
import '../playlists/add_songs_sheet.dart';
import '../playlists/collaborators_sheet.dart';
import '../playlists/cover_sheet.dart';
import '../playlists/playlist_manage_sheet.dart';
import 'data/formatting.dart';
import 'data/library_providers.dart';
import 'data/playlist_detail_controller.dart';
import 'widgets/collection_header.dart';
import 'widgets/library_states.dart';
import 'widgets/track_tile.dart';

/// One hand-built playlist: its header, its songs, and every edit the viewer is allowed to make.
///
/// The edits are optimistic — see [PlaylistDetailController], which owns that behaviour so it can
/// be tested without a widget tree.
class PlaylistDetailScreen extends ConsumerStatefulWidget {
  const PlaylistDetailScreen({required this.playlistId, super.key});

  final String playlistId;

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  PlaylistDetailController? _controller;

  /// Drag-to-reorder is a mode rather than always-on: a list where every row can be dragged
  /// swallows the flick that scrolls it, and a playlist is scrolled far more often than reordered.
  bool _reordering = false;

  @override
  void initState() {
    super.initState();
    // `ref.read` in `initState` is safe for a Provider that only assembles a client, and the
    // controller has to exist before the first build so the list has something to listen to.
    final api = ref.read(playlistApiProvider);
    if (api == null) return;
    final controller = PlaylistDetailController(
      playlistId: widget.playlistId,
      api: api,
      onFailure: _report,
    )..addListener(_onChanged);
    _controller = controller;
    controller.load();
  }

  @override
  void dispose() {
    _controller
      ?..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _report(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          describeError(error, ref.read(translationsProvider).call),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final controller = _controller;
    final detail = controller?.detail;

    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.name ?? t(PlaylistsKeys.kindLabel)),
        actions: [
          if (detail != null &&
              (detail.canEdit ?? false) &&
              detail.tracks.length > 1)
            IconButton(
              icon: Icon(
                _reordering
                    ? PhosphorIconsBold.check
                    : PhosphorIconsRegular.arrowsDownUp,
              ),
              tooltip: _reordering
                  ? t(PlaylistsKeys.reorderDone)
                  : t(PlaylistsKeys.reorderStart),
              onPressed: () => setState(() => _reordering = !_reordering),
            ),
          // One button rather than a row of icons: renaming, the cover, collaborators, download,
          // sharing, deleting and leaving all live behind it, which is the only shape a phone
          // header has room for. It opens `playlistMenu` — the SAME definition the player's
          // context nav and every playlist card use — so the page cannot offer a different set of
          // actions than a card for the same playlist does.
          if (detail != null)
            IconButton(
              icon: const Icon(PhosphorIconsBold.dotsThree),
              tooltip: t(CommonKeys.actionsMore),
              onPressed: () => unawaited(_openMenu(detail)),
            ),
        ],
      ),
      body: _content(controller, detail),
    );
  }

  Widget _content(
    PlaylistDetailController? controller,
    PlaylistDetail? detail,
  ) {
    final t = ref.t;
    // Null only when the app has no signed-in hub, which the auth gate makes unreachable — so this
    // is a wiring failure, and saying "failed to load" is more honest than an empty playlist.
    if (controller == null) {
      return EmptyNote(message: t(ErrorsKeys.failedToLoad));
    }
    if (detail == null) {
      return controller.loading
          ? const ListSkeleton()
          : ErrorRetry(
              error: controller.error ?? t(ErrorsKeys.failedToLoad),
              onRetry: controller.load,
            );
    }
    return RefreshIndicator(
      onRefresh: controller.load,
      child: _body(controller, detail),
    );
  }

  Widget _body(PlaylistDetailController controller, PlaylistDetail detail) {
    final t = ref.t;
    final handoff = ref.watch(libraryHandoffProvider);
    final playContext = PlaylistContext(id: detail.id, name: detail.name);
    final canEdit = detail.canEdit ?? false;

    return ReorderableListView.builder(
      // The hero, the actions and the collaborators ride in the header so the whole screen is one
      // lazily-built list — a playlist of two thousand songs must not build two thousand rows to
      // show the top of itself.
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CollectionHeader(
            eyebrow: _eyebrow(detail, t),
            title: detail.name,
            description: detail.description,
            meta: _meta(detail, t),
            metaLeading: _OwnerLink(owner: detail.owner),
            artwork: MosaicCover(
              coverUrl: detail.coverUrl,
              autoCoverUrls: detail.autoCoverUrls,
              size: 200,
              semanticLabel: detail.name,
            ),
            onEditTitle: (detail.owned ?? false)
                ? () => unawaited(_openDetails(detail))
                : null,
            onEditArtwork: (detail.owned ?? false)
                ? () => unawaited(_openCover(detail))
                : null,
          ),
          CollectionActions(
            onPlay: detail.tracks.isEmpty || handoff == null
                ? null
                : () => handoff.playTracks(detail.tracks, context: playContext),
            onShuffle: detail.tracks.isEmpty || handoff == null
                ? null
                : () => handoff.playTracks(
                    detail.tracks,
                    shuffle: true,
                    context: playContext,
                  ),
            extra: [
              if (canEdit)
                OutlinedButton.icon(
                  onPressed: () => unawaited(_openAddSongs(detail)),
                  icon: const Icon(PhosphorIconsRegular.playlist),
                  label: Text(t(PlaylistsKeys.addToPlaylist)),
                ),
              if (canEdit)
                OutlinedButton.icon(
                  onPressed: () => unawaited(_openCollaborators(detail)),
                  icon: const Icon(PhosphorIconsRegular.users),
                  label: Text(t(PlaylistsKeys.collaboratorsManage)),
                ),
            ],
          ),
          if (_reordering)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                t(PlaylistsKeys.reorderHint),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          if (detail.tracks.isEmpty) ...[
            EmptyNote(
              message: t(PlaylistsKeys.empty),
              icon: PhosphorIcons.playlist(),
            ),
            // An empty playlist with nothing to press is a dead end: the only other route in is
            // finding each song in the catalog and filing it from that song's own menu.
            if (canEdit)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Center(
                  child: FilledButton.icon(
                    onPressed: () => unawaited(_openAddSongs(detail)),
                    icon: const Icon(PhosphorIconsRegular.plus),
                    label: Text(t(PlaylistsKeys.addToPlaylist)),
                  ),
                ),
              ),
          ],
        ],
      ),
      itemCount: detail.tracks.length,
      buildDefaultDragHandles: _reordering && canEdit,
      // `onReorderItem`, not the deprecated `onReorder`: this one reports the destination already
      // corrected for the dragged row having left the list, which is the off-by-one every
      // hand-written adjustment gets wrong on a downward drag.
      onReorderItem: controller.moveTrack,
      itemBuilder: (context, index) {
        final track = detail.tracks[index];
        return TrackTile(
          // Keyed by track id: after a reorder the framework has to recognise the row that moved,
          // and an index key would make every row below the drop look like it changed identity.
          key: ValueKey(track.id),
          title: track.title,
          artist: track.artist,
          durationMs: track.durationMs,
          coverSha: artHashOf(track.coverUrl),
          onTap: handoff == null
              ? null
              : () => handoff.playTracks(
                  detail.tracks,
                  startIndex: index,
                  context: playContext,
                ),
          // A long press is the row's own route to the full track menu - queue, like, download,
          // add to another playlist, go to artist or album, share - the same set the web client
          // puts behind a right-click. The menu button carries the three actions that only make
          // sense HERE, plus a way through to the rest of them.
          onLongPress: () => unawaited(showTrackMenu(context, ref, track)),
          trailing: _reordering
              ? null
              : PopupMenuButton<_TrackAction>(
                  tooltip: t(CommonKeys.actionsMore),
                  onSelected: (action) => unawaited(
                    _runTrackAction(
                      controller,
                      action,
                      index,
                      track,
                      detail.tracks.length,
                    ),
                  ),
                  itemBuilder: (context) => [
                    if (canEdit) ...[
                      PopupMenuItem(
                        value: _TrackAction.moveUp,
                        enabled: index > 0,
                        child: Text(t(CommonKeys.actionsMoveUp)),
                      ),
                      PopupMenuItem(
                        value: _TrackAction.moveDown,
                        enabled: index < detail.tracks.length - 1,
                        child: Text(t(CommonKeys.actionsMoveDown)),
                      ),
                      PopupMenuItem(
                        value: _TrackAction.remove,
                        child: Text(t(PlaylistsKeys.removeFromPlaylist)),
                      ),
                    ],
                    PopupMenuItem(
                      value: _TrackAction.more,
                      child: Text(t(CommonKeys.actionsMore)),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _runTrackAction(
    PlaylistDetailController controller,
    _TrackAction action,
    int index,
    BrowseTrack track,
    int total,
  ) async {
    switch (action) {
      case _TrackAction.moveUp:
        await controller.moveTrack(index, index - 1);
        _announceMove(track, index - 1, total);
      case _TrackAction.moveDown:
        await controller.moveTrack(index, index + 1);
        _announceMove(track, index + 1, total);
      case _TrackAction.remove:
        await controller.removeTrack(track);
      case _TrackAction.more:
        if (mounted) await showTrackMenu(context, ref, track);
    }
  }

  /// A drag is visible; a menu move is not, so the move is spoken.
  void _announceMove(BrowseTrack track, int position, int total) {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      ref.read(translationsProvider)(PlaylistsKeys.reorderMoved, {
        'title': track.title,
        'position': position + 1,
        'count': total,
      }),
      Directionality.of(context),
    );
  }

  String _eyebrow(PlaylistDetail detail, Translate t) {
    if ((detail.collaborators ?? const []).isNotEmpty) {
      return t(PlaylistsKeys.kindCollaborative);
    }
    return detail.visibility == PlaylistVisibility.public
        ? t(PlaylistsKeys.kindPublic)
        : t(PlaylistsKeys.kindLabel);
  }

  String _meta(PlaylistDetail detail, Translate t) {
    final count = detail.trackCount ?? detail.tracks.length;
    final durationMs =
        detail.totalDurationMs ??
        detail.tracks.fold<int>(0, (sum, track) => sum + track.durationMs);
    // The owner is deliberately absent here: they are a LINK, and this string is text. See
    // [_OwnerLink], which takes the front of the same line.
    final parts = [
      t(PlaylistsKeys.songCount, {'count': count}),
      if (durationMs > 0) totalDuration(durationMs, t),
    ];
    final line = parts.join(' · ');
    // The Hub counts every row; `tracks` is filtered to what this viewer can actually play. Saying
    // so is the difference between a wrong count and an explained one.
    if (detail.tracks.length == count) return line;
    return '$line\n${t(PlaylistsKeys.metaPlayableNote, {'playable': detail.tracks.length, 'count': count})}';
  }

  /// Everything a viewer can do to the playlist itself.
  ///
  /// This used to be a second, hand-written sheet, and the two disagreed: `playlistMenu` already
  /// carried Download, Share, Play, Queue and Start radio, and none of them were reachable from
  /// the page the playlist actually lives on. Taking a playlist offline is a core feature this
  /// screen could not start. The page passes the callbacks only IT can honour — the edit sheets
  /// and the two destructive confirmations, which need a context that outlives the menu — and
  /// gets the rest for free.
  Future<void> _openMenu(PlaylistDetail detail) async {
    final owned = detail.owned ?? false;
    final canEdit = detail.canEdit ?? owned;
    await showEntityMenu(
      context,
      (page, menuRef) => playlistMenu(
        page,
        menuRef,
        PlaylistLike(
          id: detail.id,
          name: detail.name,
          coverUrl: detail.coverUrl,
          // The loaded rows, so Download and Queue skip a round trip the page has already made.
          tracks: detail.tracks,
        ),
        onEditDetails: owned ? () => unawaited(_openDetails(detail)) : null,
        onEditCover: owned ? () => unawaited(_openCover(detail)) : null,
        onCollaborators: canEdit
            ? () => unawaited(_openCollaborators(detail))
            : null,
        // Nothing to reorder with one row, and the header already offers the mode when there is.
        onReorder: canEdit && detail.tracks.length > 1
            ? () => setState(() => _reordering = true)
            : null,
        onDelete: owned ? () => unawaited(_confirmDelete(detail)) : null,
        // Not the owner: leaving is the only way out. Offering "Delete" to somebody who cannot
        // delete is worse than not offering it.
        onLeave: !owned && canEdit
            ? () => unawaited(_confirmLeave(detail))
            : null,
      ),
    );
  }

  /// Asks, deletes, and takes the page with it — a deleted playlist has nothing left to reload.
  Future<void> _confirmDelete(PlaylistDetail detail) async {
    if (!await confirmDeletePlaylist(context, ref, detail)) return;
    if (!mounted) return;
    ref.invalidate(playlistsProvider);
    Navigator.of(context).pop();
  }

  /// The same, for a playlist somebody else owns: one you are no longer on is one you cannot read.
  Future<void> _confirmLeave(PlaylistDetail detail) async {
    if (!await confirmLeavePlaylist(context, ref, detail.id)) return;
    if (!mounted) return;
    ref.invalidate(playlistsProvider);
    Navigator.of(context).pop();
  }

  /// Name, description and visibility. One PATCH, sent by the sheet itself.
  Future<void> _openDetails(PlaylistDetail detail) async {
    if (await showPlaylistDetailsSheet(context, detail: detail) && mounted) {
      ref.invalidate(playlistsProvider);
      await _controller?.load();
    }
  }

  /// A photo from the device, one of the covers already inside the playlist, or back to the
  /// generated mosaic. The upload lives in the sheet because `POST /v1/images` is the one Hub call
  /// that posts bytes, and it belongs beside the picker rather than in four copies of it.
  Future<void> _openCover(PlaylistDetail detail) async {
    final changed = await showPlaylistCoverSheet(
      context,
      playlistId: detail.id,
      autoCoverUrls: detail.autoCoverUrls ?? const [],
      hasCover: detail.coverUrl != null,
    );
    if (changed && mounted) {
      ref.invalidate(playlistsProvider);
      await _controller?.load();
    }
  }

  Future<void> _openCollaborators(PlaylistDetail detail) async {
    final left = await showCollaboratorsSheet(
      context,
      playlistId: detail.id,
      initial: detail.collaborators ?? const [],
      owned: detail.owned ?? false,
    );
    if (!mounted) return;
    ref.invalidate(playlistsProvider);
    // Leaving a playlist is the one outcome this page cannot survive: a playlist you are no longer
    // on is a playlist you can no longer read.
    if (left) {
      Navigator.of(context).pop();
    } else {
      await _controller?.load();
    }
  }

  Future<void> _openAddSongs(PlaylistDetail detail) async {
    await showAddSongsSheet(
      context,
      playlistId: detail.id,
      alreadyIn: {for (final track in detail.tracks) track.id},
    );
    if (mounted) await _controller?.load();
  }
}

enum _TrackAction { moveUp, moveDown, remove, more }

/// The playlist's owner, as a route to their profile rather than a word in a sentence.
///
/// The web puts an avatar and the display name at the head of the meta line, linking to
/// `/app/u/$handle` (`playlists/$playlistId.tsx:425-439`). Mobile has the same route —
/// `SocialNavigation.goToProfile` resolves `u/:handle` inside whichever tab the page is in — and
/// was spending the pixels on plain text.
class _OwnerLink extends StatelessWidget {
  const _OwnerLink({required this.owner});

  final PublicUser owner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => context.goToProfile(owner.handle),
      borderRadius: ChordiaRadius.smAll,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The web's `size-6`, round.
          CoverArt(
            sha256: artHashOf(owner.avatarUrl),
            size: 24,
            shape: BoxShape.circle,
            fallbackIcon: PhosphorIcons.user(),
            fallbackInitial: owner.displayName,
          ),
          const SizedBox(width: 6),
          // `font-medium text-foreground` — the owner reads a shade stronger than the counts
          // beside them, which is what marks it as the one part of the line that goes somewhere.
          Flexible(
            child: Text(
              owner.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ChordiaType.sm.copyWith(
                fontWeight: ChordiaType.medium,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
