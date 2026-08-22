import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'data/formatting.dart';
import 'data/library_providers.dart';
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
/// EDITING the rules is a later milestone. Everything here reads them.
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

    return Scaffold(
      appBar: AppBar(
        title: Text(snapshot.value?.name ?? t(PlaylistsKeys.smartKindLabel)),
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
                  : const Icon(Icons.refresh_rounded),
              label: Text(t(PlaylistsKeys.smartRefreshAction)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (playlist.tracks.isEmpty)
          EmptyNote(
            message: t(PlaylistsKeys.smartEmpty),
            icon: Icons.auto_awesome_rounded,
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
    final hub = ref.read(hubClientProvider);
    if (hub == null) return;
    setState(() => _refreshing = true);
    try {
      final result = await hub.refreshSmartPlaylist(playlistId);
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
}
