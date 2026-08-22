import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_db/chordia_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../data/downloads_providers.dart';
import '../downloads_api.dart';

/// The download state of one track, as a row needs to draw it.
///
/// Folded into a single value so a row rebuilds when its own track changes state and not when
/// anything else in the queue moves — a screen showing forty rows during a batch download would
/// otherwise relayout forty times a second.
@immutable
class TrackDownloadState {
  const TrackDownloadState({required this.downloaded, this.task});

  final bool downloaded;
  final DownloadTask? task;

  bool get isQueued => task != null;

  /// 0…1 once the server has said how long the file is, null while it has not.
  double? get progress {
    final task = this.task;
    if (task == null || task.totalBytes <= 0) return null;
    return (task.bytesDone / task.totalBytes).clamp(0.0, 1.0).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      other is TrackDownloadState &&
      other.downloaded == downloaded &&
      other.task == task;

  @override
  int get hashCode => Object.hash(downloaded, task);
}

/// Reads one track's download state out of the two streams that describe it.
TrackDownloadState watchTrackDownload(WidgetRef ref, String trackId) {
  final downloaded = ref.watch(
    downloadedTrackIdsProvider.select(
      (ids) => ids.value?.contains(trackId) ?? false,
    ),
  );
  final task = ref.watch(
    downloadQueueProvider.select((queue) {
      for (final task in queue.value ?? const <DownloadTask>[]) {
        if (task.trackId == trackId) return task;
      }
      return null;
    }),
  );
  return TrackDownloadState(downloaded: downloaded, task: task);
}

/// The download affordance for a single track: save, watch, or remove.
///
/// One control for all three states rather than three, because they are the same question asked at
/// different times — "is this song on my phone?" — and a row has space for one answer.
class DownloadIconButton extends ConsumerWidget {
  const DownloadIconButton({required this.track, super.key});

  final BrowseTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final state = watchTrackDownload(ref, track.id);
    final theme = Theme.of(context);

    if (state.downloaded) {
      return IconButton(
        icon: Icon(
          Icons.download_done_rounded,
          color: theme.colorScheme.primary,
        ),
        tooltip: t(LibraryKeys.downloadsActionRemove),
        onPressed: () => removeDownload(context, ref, track.id),
      );
    }

    final task = state.task;
    if (task != null) {
      return IconButton(
        icon: SizedBox(
          width: 20,
          height: 20,
          child: task.state == DownloadState.failed
              ? Icon(
                  Icons.error_outline_rounded,
                  color: theme.colorScheme.error,
                )
              // An indeterminate spinner until the length is known: a bar sitting at zero reads as
              // "stuck", which is the one thing a working download must not look like.
              : CircularProgressIndicator(
                  strokeWidth: 2,
                  value: state.progress,
                ),
        ),
        tooltip: t(
          task.state == DownloadState.failed
              ? LibraryKeys.downloadsActionRetry
              : LibraryKeys.downloadsActionCancel,
        ),
        onPressed: () => task.state == DownloadState.failed
            ? ref.read(downloadsApiProvider).retry(track.id)
            : ref.read(downloadsApiProvider).cancel(track.id),
      );
    }

    return IconButton(
      icon: const Icon(Icons.download_for_offline_outlined),
      tooltip: t(LibraryKeys.downloadsActionDownload),
      onPressed: () => saveDownloads(context, ref, [track]),
    );
  }
}

/// The download action as a menu row, for the track sheet and the album/playlist ⋮ menus.
///
/// A widget rather than a `ListTile` built at the call site, so the label tracks whether the
/// collection is already held without every menu re-deriving that.
class DownloadMenuTile extends ConsumerWidget {
  const DownloadMenuTile({
    required this.tracks,
    this.label,
    this.onDone,
    super.key,
  });

  /// The rows to save. One for a track menu, the whole tracklist for an album or playlist.
  final List<BrowseTrack> tracks;

  /// Overrides the label — "Download album", "Download playlist".
  final String? label;

  /// Closes the sheet the tile lives in, before the snack bar it triggers.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final ids = ref.watch(
      downloadedTrackIdsProvider.select((ids) => ids.value ?? const <String>{}),
    );
    final held = tracks.isNotEmpty && tracks.every((v) => ids.contains(v.id));

    return ListTile(
      leading: Icon(
        held
            ? Icons.download_done_rounded
            : Icons.download_for_offline_outlined,
      ),
      title: Text(
        held
            ? t(LibraryKeys.downloadsActionRemove)
            : (label ?? t(LibraryKeys.downloadsActionDownload)),
      ),
      onTap: () {
        onDone?.call();
        if (held) {
          removeDownloads(context, ref, [for (final track in tracks) track.id]);
        } else {
          saveDownloads(context, ref, tracks);
        }
      },
    );
  }
}

/// Queues [tracks] and says what happened, in one line.
///
/// The counts are reported rather than swallowed because the two non-obvious outcomes — "you
/// already have these" and "these did not fit" — are both things the user would otherwise
/// interpret as the button not working.
Future<void> saveDownloads(
  BuildContext context,
  WidgetRef ref,
  Iterable<BrowseTrack> tracks,
) async {
  final t = ref.read(translationsProvider).call;
  final messenger = ScaffoldMessenger.of(context);
  final batch = await ref.read(downloadsApiProvider).saveAll(tracks);

  final parts = <String>[
    if (batch.queued > 0)
      t(LibraryKeys.downloadsToastQueued, {'count': batch.queued}),
    if (batch.queued == 0 && batch.existing > 0)
      t(LibraryKeys.downloadsToastExisting),
    if (batch.refused > 0)
      t(LibraryKeys.downloadsToastRefused, {'count': batch.refused}),
  ];
  if (parts.isEmpty) return;
  _snack(messenger, parts.join(' · '));
}

/// Removes one download, or explains why it stayed.
Future<void> removeDownload(
  BuildContext context,
  WidgetRef ref,
  String trackId,
) async {
  final t = ref.read(translationsProvider).call;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final removed = await ref.read(downloadsApiProvider).remove(trackId);
    _snack(
      messenger,
      t(
        removed
            ? LibraryKeys.downloadsToastRemoved
            : LibraryKeys.downloadsToastInUse,
      ),
    );
  } on Object {
    _snack(messenger, t(LibraryKeys.downloadsRemoveError));
  }
}

/// Removes a whole collection's downloads.
Future<void> removeDownloads(
  BuildContext context,
  WidgetRef ref,
  Iterable<String> trackIds,
) async {
  final t = ref.read(translationsProvider).call;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await ref.read(downloadsApiProvider).removeAll(trackIds);
    _snack(
      messenger,
      [
        t(LibraryKeys.downloadsToastCleared, {'count': result.removed}),
        if (result.skipped > 0)
          t(LibraryKeys.downloadsToastSkipped, {'count': result.skipped}),
      ].join(' · '),
    );
  } on Object {
    _snack(messenger, t(LibraryKeys.downloadsRemoveError));
  }
}

/// One line of feedback.
///
/// Held as a messenger captured before the await rather than a `BuildContext` used after it: the
/// sheet or row these actions are invoked from is usually gone by the time the queue answers.
void _snack(ScaffoldMessengerState messenger, String message) {
  if (!messenger.mounted) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
