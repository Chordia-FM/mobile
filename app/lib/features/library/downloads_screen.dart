import 'dart:async';

import 'package:chordia_db/chordia_db.dart';
import 'package:chordia_sync/chordia_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../i18n/keys.g.dart';
import '../catalog/widgets/entity_menu.dart';
import '../downloads/downloads_api.dart';
import '../downloads/downloads_manager_screen.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import 'data/downloads_grouping.dart';
import 'data/formatting.dart';
import 'data/library_providers.dart';
import 'widgets/collection_header.dart';
import 'widgets/library_states.dart';
import 'widgets/track_tile.dart';

/// What is actually on this device, grouped by album.
///
/// Reads the download index, which the pipeline in `features/downloads` fills. Removing anything
/// goes back through that pipeline so the files go with the rows.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final downloads = ref.watch(downloadedTracksProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t(LibraryKeys.downloadsTitle)),
        actions: [
          // The queue and the storage budget. `DownloadsManagerScreen`'s own doc comment said it
          // was "reachable with one line from anywhere" and nothing ever wrote the line, so what
          // the phone was doing with the listener's data and storage was not visible at all.
          IconButton(
            onPressed: () => unawaited(openDownloadsManager(context)),
            tooltip: t(LibraryKeys.downloadsActionManage),
            icon: const Icon(PhosphorIconsRegular.slidersHorizontal),
          ),
        ],
      ),
      body: downloads.when(
        loading: () => const ListSkeleton(),
        error: (error, stack) => ErrorRetry(
          error: error,
          onRetry: () => ref.invalidate(downloadedTracksProvider),
        ),
        data: (rows) => _DownloadsList(rows: rows),
      ),
    );
  }
}

class _DownloadsList extends ConsumerWidget {
  const _DownloadsList({required this.rows});

  final List<DownloadedTrack> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final groups = groupDownloads(rows);
    final totalBytes = totalDownloadBytes(rows);
    final handoff = ref.watch(libraryHandoffProvider);
    final tracks = [for (final row in rows) browseTrackOf(row)];
    // Downloads are not one library's, so there is no id to name here — the label is what the
    // player shows under "Playing from", and "Downloads" is exactly what it came from.
    final playContext = LibraryContext(
      id: 'downloads',
      name: t(LibraryKeys.downloadsTitle),
    );

    return ListView.builder(
      // Header plus one entry per group. Lazily built for the same reason every other list here
      // is: a device holding a thousand downloaded songs must not build a thousand rows to show
      // the top of the screen.
      itemCount: groups.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CollectionHeader(
                eyebrow: t(LibraryKeys.downloadsEyebrow),
                title: t(LibraryKeys.downloadsTitle),
                meta: [
                  t(LibraryKeys.downloadsSongCount, {'count': rows.length}),
                  if (rows.isNotEmpty) formatBytes(totalBytes),
                  t(LibraryKeys.downloadsStoredOnDevice),
                ].join(' · '),
                artwork: const GradientArtwork(
                  icon: PhosphorIconsFill.downloadSimple,
                  size: 200,
                ),
              ),
              if (rows.isNotEmpty)
                CollectionActions(
                  onPlay: handoff == null
                      ? null
                      : () => handoff.playTracks(tracks, context: playContext),
                  onShuffle: handoff == null
                      ? null
                      : () => handoff.playTracks(
                          tracks,
                          shuffle: true,
                          context: playContext,
                        ),
                  extra: [
                    OutlinedButton.icon(
                      onPressed: () => _clearAll(context, ref),
                      icon: const Icon(PhosphorIconsRegular.trash),
                      label: Text(t(CommonKeys.actionsClearAll)),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                EmptyNote(
                  message: t(LibraryKeys.downloadsEmptyState),
                  icon: PhosphorIcons.downloadSimple(),
                ),
            ],
          );
        }
        return _AlbumGroup(group: groups[index - 1], playContext: playContext);
      },
    );
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final t = ref.read(translationsProvider).call;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t(LibraryKeys.downloadsClearConfirmTitle)),
        content: Text(t(LibraryKeys.downloadsClearConfirmMessage)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t(CommonKeys.actionsCancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t(CommonKeys.actionsClearAll)),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    try {
      // Through the download pipeline, which owns the file paths: clearing index rows alone would
      // leave the audio on disk with nothing left that knows it is there.
      await ref.read(downloadsApiProvider).clear();
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(describeError(error, t))));
    }
  }
}

/// One album's downloaded songs under a heading that says how much of the device they take.
class _AlbumGroup extends ConsumerWidget {
  const _AlbumGroup({required this.group, required this.playContext});

  final DownloadGroup group;
  final PlayContext playContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final handoff = ref.watch(libraryHandoffProvider);
    final tracks = [for (final track in group.tracks) browseTrackOf(track)];
    final subtitle = [
      if (group.artist != null) group.artist!,
      t(LibraryKeys.downloadsSongCount, {'count': group.tracks.length}),
      formatBytes(group.sizeBytes),
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              CoverArt(
                sha256: group.coverSha,
                size: 56,
                fallbackIcon: PhosphorIconsFill.musicNotes,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // A download with no album tag still needs a heading; the catalogs' name for
                      // tracks the scanner could not place is the honest one to borrow.
                      group.album ?? t(LibraryKeys.editUnknownLabel),
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (final (index, track) in group.tracks.indexed)
          TrackTile(
            key: ValueKey(track.trackId),
            title: track.title,
            artist: track.artist,
            durationMs: track.durationMs,
            coverSha: track.coverSha,
            detail: formatBytes(track.sizeBytes),
            dense: true,
            // Plays the album, starting here — the same thing tapping a row does everywhere else.
            onTap: handoff == null
                ? null
                : () => handoff.playTracks(
                    tracks,
                    startIndex: index,
                    context: playContext,
                  ),
            // The full track menu, the same one every other list in the app opens. Removing the
            // download is in it - `DownloadMenuTile` reads as "Remove" for a track already held,
            // and goes through the pipeline that owns the file rather than deleting an index row
            // and stranding the audio - and so is everything a downloaded song could not do here
            // before: queue it, like it, file it into a playlist, open its artist.
            onLongPress: () =>
                unawaited(showTrackMenu(context, ref, tracks[index])),
            trailing: IconButton(
              icon: const Icon(PhosphorIconsBold.dotsThree),
              tooltip: t(CommonKeys.actionsMore),
              onPressed: () =>
                  unawaited(showTrackMenu(context, ref, tracks[index])),
            ),
          ),
      ],
    );
  }
}
