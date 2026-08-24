import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/entity_menu.dart';
import '../playlists/data/playlists_providers.dart';
import '../playlists/data/smart_model.dart';
import '../playlists/smart_rules_screen.dart';
import 'data/formatting.dart';
import 'data/library_providers.dart';
import 'data/pins.dart';
import 'data/rules_summary.dart';
import 'widgets/collection_header.dart';
import 'widgets/library_states.dart';
import 'widgets/track_tile.dart';

/// A rule-driven playlist: what it currently holds, what its rules say, and a rebuild button.
///
/// It wears the hand-built playlist's shape down to the cover size and the meta line, because a
/// smart playlist IS a playlist — one that maintains itself. Three things differ, and only three:
/// the description slot holds the RULES (a smart playlist has no description and never will, and
/// unlike a description rules cannot go stale), the meta line ends with the refresh schedule, and
/// the action row carries Refresh.
///
/// The rules are EDITED in the builder this screen's menu opens ([openSmartRules]) rather than
/// inline: a rule set is long enough to leave and come back to, which is a screen and not a sheet.
class SmartPlaylistScreen extends ConsumerStatefulWidget {
  const SmartPlaylistScreen({required this.playlistId, super.key});

  final String playlistId;

  @override
  ConsumerState<SmartPlaylistScreen> createState() =>
      _SmartPlaylistScreenState();
}

class _SmartPlaylistScreenState extends ConsumerState<SmartPlaylistScreen> {
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final snapshot = ref.watch(smartPlaylistProvider(widget.playlistId));

    final playlist = snapshot.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist?.name ?? t(PlaylistsKeys.smartKindLabel)),
        actions: [
          // The rule builder, the pin and the delete live behind one button, for the same reason
          // the hand-built playlist's do: a phone header has room for two actions, and the ones
          // that get cut are always the ones nobody can find anywhere else.
          if (playlist != null)
            PopupMenuButton<_SmartAction>(
              // Explicit rather than the adaptive default, so this button is the same glyph as the
              // hand-built playlist's: the two pages are the same shape and must not differ here.
              icon: const Icon(PhosphorIconsBold.dotsThree),
              tooltip: t(CommonKeys.actionsMore),
              onSelected: (action) => unawaited(_runAction(action, playlist)),
              itemBuilder: (menuContext) => [
                PopupMenuItem(
                  value: _SmartAction.editRules,
                  child: Text(t(PlaylistsKeys.smartEditRules)),
                ),
                PopupMenuItem(
                  value: _SmartAction.pin,
                  child: Text(
                    t(pinLabel(isPinned(ref, PinKind.playlist, playlist.id))),
                  ),
                ),
                PopupMenuItem(
                  value: _SmartAction.delete,
                  child: Text(t(PlaylistsKeys.smartDeleteTitle)),
                ),
              ],
            ),
        ],
      ),
      body: snapshot.when(
        loading: () => const ListSkeleton(),
        error: (error, stack) => ErrorRetry(
          error: error,
          onRetry: () =>
              ref.invalidate(smartPlaylistProvider(widget.playlistId)),
        ),
        data: _body,
      ),
    );
  }

  Widget _body(SmartPlaylistDetail playlist) {
    final t = ref.t;
    final handoff = ref.watch(libraryHandoffProvider);
    final playContext = SmartPlaylistContext(
      id: playlist.id,
      name: playlist.name,
    );
    final rules = summariseSmartRules(playlist.rules, t);

    return RefreshIndicator(
      onRefresh: () async =>
          ref.invalidate(smartPlaylistProvider(widget.playlistId)),
      child: ListView.builder(
        // One lazily-built list, header included: a smart playlist can resolve to a thousand
        // tracks, and none below the fold should be built to show the top of the screen.
        itemCount: playlist.tracks.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return _header(playlist, rules, playContext, handoff);
          final track = playlist.tracks[index - 1];
          return TrackTile(
            key: ValueKey(track.id),
            title: track.title,
            artist: track.artist,
            durationMs: track.durationMs,
            coverSha: artHashOf(track.coverUrl),
            onTap: handoff == null
                ? null
                : () => handoff.playTracks(
                    playlist.tracks,
                    startIndex: index - 1,
                    context: playContext,
                  ),
            // The same full menu every other track row in the app carries. A rule-driven playlist
            // is still a playlist: its songs queue, download, get liked and get filed like any
            // other, and offering none of that here made them read as a lesser kind of song.
            onLongPress: () => unawaited(showTrackMenu(context, ref, track)),
            trailing: IconButton(
              icon: const Icon(PhosphorIconsBold.dotsThree),
              tooltip: ref.t(CommonKeys.actionsMore),
              onPressed: () => unawaited(showTrackMenu(context, ref, track)),
            ),
          );
        },
      ),
    );
  }

  Widget _header(
    SmartPlaylistDetail playlist,
    String rules,
    PlayContext playContext,
    LibraryHandoff? handoff,
  ) {
    final t = ref.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CollectionHeader(
          eyebrow: t(PlaylistsKeys.smartKindLabel),
          title: playlist.name,
          // The rules stand in for a description. When there are none the catalogs have a sentence
          // for that too, rather than an empty slot that reads as a missing field.
          description: rules.isEmpty ? t(PlaylistsKeys.smartNoRulesYet) : rules,
          meta: _meta(playlist, t),
          artwork: MosaicCover(
            coverUrl: playlist.coverUrl,
            autoCoverUrls: playlist.autoCoverUrls,
            size: 200,
            semanticLabel: playlist.name,
          ),
        ),
        CollectionActions(
          onPlay: playlist.tracks.isEmpty || handoff == null
              ? null
              : () => handoff.playTracks(playlist.tracks, context: playContext),
          onShuffle: playlist.tracks.isEmpty || handoff == null
              ? null
              : () => handoff.playTracks(
                  playlist.tracks,
                  shuffle: true,
                  context: playContext,
                ),
          extra: [
            OutlinedButton.icon(
              onPressed: _refreshing ? null : () => _refreshNow(playlist.id),
              icon: _refreshing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(PhosphorIconsBold.arrowsClockwise),
              label: Text(t(PlaylistsKeys.smartRefreshAction)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (playlist.tracks.isEmpty)
          EmptyNote(
            message: t(PlaylistsKeys.smartEmpty),
            icon: PhosphorIcons.sparkle(),
          ),
      ],
    );
  }

  String _meta(SmartPlaylistDetail playlist, Translate t) {
    final durationMs = playlist.tracks.fold<int>(
      0,
      (sum, track) => sum + track.durationMs,
    );
    return [
      t(PlaylistsKeys.songCount, {'count': playlist.tracks.length}),
      if (durationMs > 0) totalDuration(durationMs, t),
      smartRefreshLabel(playlist.refreshIntervalMinutes ?? 0, t),
      if (playlist.refreshedAt == null)
        t(PlaylistsKeys.smartRefreshNeverRefreshed),
    ].join(' · ');
  }

  /// Rebuilds now, and reports what actually changed — including "nothing", which is a result and
  /// not a failure.
  Future<void> _refreshNow(String playlistId) async {
    final api = ref.read(smartPlaylistsApiProvider);
    if (api == null) return;
    setState(() => _refreshing = true);
    try {
      final result = await api.refresh(playlistId);
      if (!mounted) return;
      ref.invalidate(smartPlaylistProvider(playlistId));
      final t = ref.read(translationsProvider).call;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.added == 0 && result.removed == 0
                ? t(PlaylistsKeys.smartRefreshUnchanged, {
                    'count': result.total,
                  })
                : t(PlaylistsKeys.smartRefreshChanged, {
                    'added': result.added,
                    'removed': result.removed,
                    'total': result.total,
                  }),
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeError(error, ref.read(translationsProvider).call),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _runAction(
    _SmartAction action,
    SmartPlaylistDetail playlist,
  ) async {
    switch (action) {
      case _SmartAction.editRules:
        await _editRules(playlist);
      case _SmartAction.pin:
        await togglePin(context, ref, kind: PinKind.playlist, id: playlist.id);
      case _SmartAction.delete:
        await _delete(playlist);
    }
  }

  /// Opens the rule builder on this playlist's own rules.
  ///
  /// Seeded from the snapshot rather than re-fetched: the snapshot already carries the rules, and
  /// a second read would only widen the window in which they could change under the editor.
  Future<void> _editRules(SmartPlaylistDetail playlist) async {
    final saved = await openSmartRules(
      context,
      existing: SmartSource.ofDetail(playlist),
    );
    if (saved != null && mounted) {
      ref.invalidate(smartPlaylistProvider(playlist.id));
    }
  }

  Future<void> _delete(SmartPlaylistDetail playlist) async {
    final t = ref.read(translationsProvider).call;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t(PlaylistsKeys.smartDeleteTitle)),
        content: Text(t(PlaylistsKeys.smartDeleteConfirmBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t(CommonKeys.actionsCancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t(CommonKeys.actionsDelete)),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;

    final api = ref.read(smartPlaylistsApiProvider);
    if (api == null) return;
    try {
      await api.delete(playlist.id);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(PlaylistsKeys.toastDeleteFailed))),
      );
      return;
    }
    if (!mounted) return;
    ref.invalidate(smartPlaylistsProvider);
    // The page has to go with it: a deleted playlist has nothing left to reload.
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t(PlaylistsKeys.toastDeleted, {'name': playlist.name})),
      ),
    );
  }
}

/// What the smart playlist's own menu offers.
enum _SmartAction { editRules, pin, delete }
