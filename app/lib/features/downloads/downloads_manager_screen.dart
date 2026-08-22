import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'widgets/download_sections.dart';

/// What is arriving, and what it is costing.
///
/// Separate from the Downloads *library* screen on purpose: that screen answers "what can I play
/// on the plane?" and is a list of songs, while this one answers "what is my phone doing with my
/// data and my storage?" and is a list of jobs. Folding them together made the library list churn
/// twice a second during a batch, which is the wrong behaviour for the screen people actually
/// browse.
///
/// WIRING: reachable with one line from anywhere — `openDownloadsManager(context)`. The Downloads
/// screen's app bar is the natural home for it.
class DownloadsManagerScreen extends ConsumerWidget {
  const DownloadsManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Scaffold(
      appBar: AppBar(title: Text(t(LibraryKeys.downloadsActionManage))),
      body: ListView(
        children: [
          const DownloadStorageCard(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              t(LibraryKeys.downloadsQueueTitle),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const DownloadQueueList(),
        ],
      ),
    );
  }
}

/// Opens the manager over whatever is showing.
///
/// A plain push rather than a `go_router` route: the queue is a modal detour from wherever the
/// user was, not a place to deep-link into or to restore a tab's stack to.
Future<void> openDownloadsManager(BuildContext context) => Navigator.of(
  context,
).push<void>(MaterialPageRoute(builder: (_) => const DownloadsManagerScreen()));
