import 'package:chordia_db/chordia_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/downloads/download_storage.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/tokens.dart';
import '../../catalog/widgets/list_row.dart';
import '../../library/data/formatting.dart';
import '../data/downloads_providers.dart';
import '../downloads_api.dart';

/// What downloads take, against what they are allowed to take.
///
/// The cap lives here rather than in a settings screen because this is where the consequence is
/// visible: a limit set next to a bar showing 4.1 GB of 5 GB is a decision, and the same control
/// on a settings list is a number with no context.
class DownloadStorageCard extends ConsumerWidget {
  const DownloadStorageCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final storage = ref.watch(downloadStorageProvider).value;
    if (storage == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t(LibraryKeys.downloadsStorageTitle),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              storage.hasCap
                  ? t(LibraryKeys.downloadsStorageUsed, {
                      'used': formatBytes(storage.usedBytes),
                      'cap': formatBytes(storage.capBytes),
                    })
                  : t(LibraryKeys.downloadsStorageUsedNoCap, {
                      'used': formatBytes(storage.usedBytes),
                    }),
              style: theme.textTheme.bodyMedium,
            ),
            if (storage.hasCap) ...[
              const SizedBox(height: 8),
              ClipRRect(
                // Every progress bar on the web is `rounded-full` — `DownloadStatsPanel.tsx:139`,
                // `EntityStatsView.tsx:339`, `slider.tsx:57`. None of them is a 4px corner.
                borderRadius: ChordiaRadius.pill,
                child: LinearProgressIndicator(
                  value: storage.fraction,
                  minHeight: 6,
                  color: storage.isFull ? theme.colorScheme.error : null,
                ),
              ),
            ],
            if (storage.isFull) ...[
              const SizedBox(height: 8),
              Text(
                t(LibraryKeys.downloadsStorageFull),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _CapPicker(current: storage.capBytes)),
                TextButton.icon(
                  onPressed: storage.trackCount == 0
                      ? null
                      : () => _clear(context, ref),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(t(LibraryKeys.downloadsStorageClear)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final t = ref.read(translationsProvider).call;
    final messenger = ScaffoldMessenger.of(context);
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
      // Through the API, never the DAO: the rows are an index of files, and deleting one without
      // the other either strands bytes on disk or points the player at nothing.
      final result = await ref.read(downloadsApiProvider).clear();
      if (!messenger.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            [
              t(LibraryKeys.downloadsToastCleared, {'count': result.removed}),
              if (result.skipped > 0)
                t(LibraryKeys.downloadsToastSkipped, {'count': result.skipped}),
            ].join(' · '),
          ),
        ),
      );
    } on Object {
      if (!messenger.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(t(LibraryKeys.downloadsClearError))),
      );
    }
  }
}

class _CapPicker extends ConsumerWidget {
  const _CapPicker({required this.current});

  final int current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return PopupMenuButton<int>(
      initialValue: current,
      onSelected: (cap) => ref.read(downloadBudgetProvider).write(cap),
      itemBuilder: (context) => [
        for (final choice in DownloadBudget.choices)
          PopupMenuItem(
            value: choice,
            child: Text(
              choice == 0
                  ? t(LibraryKeys.downloadsStorageCapUnlimited)
                  : formatBytes(choice),
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t(LibraryKeys.downloadsStorageCap)),
          const SizedBox(width: 6),
          Text(
            current == 0
                ? t(LibraryKeys.downloadsStorageCapUnlimited)
                : formatBytes(current),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const Icon(Icons.arrow_drop_down_rounded),
        ],
      ),
    );
  }
}

/// Everything still arriving, with the controls each row needs.
class DownloadQueueList extends ConsumerWidget {
  const DownloadQueueList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final queue = ref.watch(downloadQueueDetailsProvider).value ?? const [];
    if (queue.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Text(
          t(LibraryKeys.downloadsQueueEmpty),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return Column(
      children: [for (final entry in queue) _QueueRow(entry: entry)],
    );
  }
}

class _QueueRow extends ConsumerWidget {
  const _QueueRow({required this.entry});

  final QueuedDownload entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final task = entry.task;
    final api = ref.read(downloadsApiProvider);
    final fraction = task.totalBytes > 0
        ? (task.bytesDone / task.totalBytes).clamp(0.0, 1.0).toDouble()
        : null;

    final subtitle = switch (task.state) {
      DownloadState.failed => describeDownloadError(task.error, t),
      DownloadState.paused => t(LibraryKeys.downloadsQueuePaused),
      DownloadState.queued => t(LibraryKeys.downloadsQueueQueued),
      // Bytes rather than a percentage while the length is unknown, so the row still shows motion
      // on a server that streams without announcing a length.
      DownloadState.running || DownloadState.done =>
        task.totalBytes > 0
            ? t(LibraryKeys.downloadsQueueProgress, {
                'done': formatBytes(task.bytesDone),
                'total': formatBytes(task.totalBytes),
              })
            : formatBytes(task.bytesDone),
    };

    return ListRow(
      key: ValueKey(task.id),
      title: Text(
        entry.request?.title ?? task.trackId,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              if (entry.request != null) entry.request!.artist,
              subtitle,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: task.state == DownloadState.failed
                ? theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  )
                : theme.textTheme.bodySmall,
          ),
          if (task.state == DownloadState.running) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(value: fraction, minHeight: 3),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          switch (task.state) {
            DownloadState.failed => IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: t(LibraryKeys.downloadsActionRetry),
              onPressed: () => api.retry(task.trackId),
            ),
            DownloadState.paused => IconButton(
              icon: const Icon(Icons.play_arrow_rounded),
              tooltip: t(LibraryKeys.downloadsActionResume),
              onPressed: () => api.resume(task.trackId),
            ),
            _ => IconButton(
              icon: const Icon(Icons.pause_rounded),
              tooltip: t(LibraryKeys.downloadsActionPause),
              onPressed: () => api.pause(task.trackId),
            ),
          },
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: t(LibraryKeys.downloadsActionCancel),
            onPressed: () => api.cancel(task.trackId),
          ),
        ],
      ),
    );
  }
}
