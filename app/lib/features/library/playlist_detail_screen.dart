import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
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
                _reordering ? Icons.check_rounded : Icons.swap_vert_rounded,
              ),
              tooltip: _reordering
                  ? t(PlaylistsKeys.reorderDone)
                  : t(PlaylistsKeys.reorderStart),
              onPressed: () => setState(() => _reordering = !_reordering),
            ),
          if (detail != null && (detail.owned ?? false))
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: t(PlaylistsKeys.editTitle),
              onPressed: () => _openEditor(detail),
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
            artwork: MosaicCover(
              coverUrl: detail.coverUrl,
              autoCoverUrls: detail.autoCoverUrls,
              size: 200,
              semanticLabel: detail.name,
            ),
            onEditTitle: (detail.owned ?? false)
                ? () => _openEditor(detail)
                : null,
            onEditArtwork: (detail.owned ?? false)
                ? () => _openCoverPicker(detail)
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
                  onPressed: () => _openCollaborators(controller, detail),
                  icon: const Icon(Icons.group_outlined),
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
          if (detail.tracks.isEmpty)
            EmptyNote(
              message: t(PlaylistsKeys.empty),
              icon: Icons.queue_music_rounded,
            ),
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
          trailing: _reordering
              ? null
              : PopupMenuButton<_TrackAction>(
                  tooltip: t(CommonKeys.actionsMore),
                  onSelected: (action) => _runTrackAction(
                    controller,
                    action,
                    index,
                    track,
                    detail.tracks.length,
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
    final parts = [
      detail.owner.displayName,
      t(PlaylistsKeys.songCount, {'count': count}),
      if (durationMs > 0) totalDuration(durationMs, t),
    ];
    final line = parts.join(' · ');
    // The Hub counts every row; `tracks` is filtered to what this viewer can actually play. Saying
    // so is the difference between a wrong count and an explained one.
    if (detail.tracks.length == count) return line;
    return '$line\n${t(PlaylistsKeys.metaPlayableNote, {'playable': detail.tracks.length, 'count': count})}';
  }

  Future<void> _openEditor(PlaylistDetail detail) async {
    final controller = _controller;
    if (controller == null) return;
    final t = ref.t;
    final name = TextEditingController(text: detail.name);
    final description = TextEditingController(text: detail.description ?? '');
    var visibility = detail.visibility ?? PlaylistVisibility.private;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t(PlaylistsKeys.editTitle),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: t(PlaylistsKeys.editName),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: t(PlaylistsKeys.editDescription),
                  hintText: t(PlaylistsKeys.editDescriptionPlaceholder),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                t(PlaylistsKeys.editVisibilityLabel),
                style: Theme.of(sheetContext).textTheme.labelLarge,
              ),
              for (final option in PlaylistVisibility.values)
                ListTile(
                  onTap: () => setSheetState(() => visibility = option),
                  contentPadding: EdgeInsets.zero,
                  title: Text(t(_visibilityLabel(option))),
                  subtitle: Text(t(_visibilityHint(option))),
                  // A check rather than a radio: `RadioListTile`'s `groupValue`/`onChanged` pair
                  // is deprecated in favour of a `RadioGroup` ancestor, and a selected-state icon
                  // says the same thing without carrying a deprecation into a new screen.
                  trailing: Icon(
                    visibility == option
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: visibility == option
                        ? Theme.of(sheetContext).colorScheme.primary
                        : null,
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                child: Text(t(CommonKeys.actionsSave)),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved ?? false) {
      final trimmed = name.text.trim();
      if (trimmed.isNotEmpty && trimmed != detail.name) {
        await controller.rename(trimmed);
      }
      if (description.text.trim() != (detail.description ?? '')) {
        await controller.setDescription(description.text);
      }
      if (visibility != detail.visibility) {
        await controller.setVisibility(visibility);
      }
    }
    name.dispose();
    description.dispose();
  }

  /// Picks the playlist's face from the covers already inside it, or drops back to the mosaic.
  ///
  /// Uploading a photo is not offered: `POST /v1/images` is a binary upload that `chordia_api`'s
  /// JSON transport cannot send, so the choice here is between covers the Hub already holds.
  Future<void> _openCoverPicker(PlaylistDetail detail) async {
    final controller = _controller;
    if (controller == null) return;
    final t = ref.t;
    final options = [
      for (final url in detail.autoCoverUrls ?? const <String>[])
        if (artHashOf(url) != null) url,
    ];

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                t(PlaylistsKeys.editChoosePhoto),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            if (options.isEmpty)
              EmptyNote(message: t(PlaylistsKeys.empty))
            else
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: options.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemBuilder: (context, index) => InkWell(
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      controller.setCover(options[index]);
                    },
                    child: CoverArt(
                      sha256: artHashOf(options[index]),
                      size: 80,
                    ),
                  ),
                ),
              ),
            if (detail.coverUrl != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    controller.clearCover();
                  },
                  child: Text(t(PlaylistsKeys.editRemovePhoto)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCollaborators(
    PlaylistDetailController controller,
    PlaylistDetail detail,
  ) async {
    final t = ref.t;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                t(PlaylistsKeys.collaboratorsManage),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final person in detail.collaborators ?? const <PublicUser>[])
              ListTile(
                leading: CoverArt(
                  sha256: artHashOf(person.avatarUrl),
                  size: 40,
                  shape: BoxShape.circle,
                  fallbackIcon: Icons.person_rounded,
                ),
                title: Text(person.displayName),
                subtitle: Text('@${person.handle}'),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: t(PlaylistsKeys.collaboratorsRemoveTitle, {
                    'name': person.displayName,
                  }),
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    controller.removeCollaborator(person.id);
                  },
                ),
              ),
            if ((detail.collaborators ?? const []).isEmpty)
              EmptyNote(message: t(PlaylistsKeys.collaboratorsInvitePrompt)),
            if (detail.owned ?? false)
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _invite(controller);
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: Text(t(PlaylistsKeys.collaboratorsInvite)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _invite(PlaylistDetailController controller) async {
    final t = ref.t;
    final handle = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t(PlaylistsKeys.collaboratorsInvitePrompt)),
        content: TextField(
          controller: handle,
          autofocus: true,
          decoration: const InputDecoration(prefixText: '@'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t(CommonKeys.actionsCancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(handle.text),
            child: Text(t(CommonKeys.actionsAdd)),
          ),
        ],
      ),
    );
    handle.dispose();

    // The Hub takes a bare handle; people type the "@" they see everywhere else.
    final cleaned = (entered ?? '').trim().replaceFirst(RegExp('^@'), '');
    if (cleaned.isEmpty) return;
    if (await controller.addCollaborator(cleaned) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(translationsProvider)(PlaylistsKeys.collaboratorsInvited, {
              'handle': cleaned,
            }),
          ),
        ),
      );
    }
  }
}

enum _TrackAction { moveUp, moveDown, remove }

String _visibilityLabel(PlaylistVisibility visibility) => switch (visibility) {
  PlaylistVisibility.private => PlaylistsKeys.editVisibilityPrivate,
  PlaylistVisibility.unlisted => PlaylistsKeys.editVisibilityUnlisted,
  PlaylistVisibility.public => PlaylistsKeys.editVisibilityPublic,
};

String _visibilityHint(PlaylistVisibility visibility) => switch (visibility) {
  PlaylistVisibility.private => PlaylistsKeys.editVisibilityPrivateHint,
  PlaylistVisibility.unlisted => PlaylistsKeys.editVisibilityUnlistedHint,
  PlaylistVisibility.public => PlaylistsKeys.editVisibilityPublicHint,
};
