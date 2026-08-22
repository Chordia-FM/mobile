import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'data/library_providers.dart';
import 'library_detail_screen.dart';
import 'widgets/library_states.dart';

/// The libraries this account owns, and the ones friends have shared with it.
///
/// Pairing a new library server is a later milestone: the handshake is authenticated as a SERVER
/// rather than a user, and a phone never performs it — the empty state says what does.
class LibrariesScreen extends ConsumerWidget {
  const LibrariesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final mine = ref.watch(myLibrariesProvider);
    final shared = ref.watch(sharedLibrariesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t(LibraryKeys.listTitle))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(myLibrariesProvider)
            ..invalidate(sharedLibrariesProvider);
        },
        child: ListView(
          children: [
            ...mine.when(
              loading: () => const [ListSkeleton(rows: 3)],
              error: (error, stack) => [
                ErrorRetry(
                  error: error,
                  onRetry: () => ref.invalidate(myLibrariesProvider),
                ),
              ],
              data: (libraries) => [
                if (libraries.isEmpty)
                  EmptyNote(
                    message:
                        '${t(LibraryKeys.listEmptyTitle)}\n'
                        '${t(LibraryKeys.listEmptyHint)}',
                    icon: Icons.dns_outlined,
                  )
                else
                  for (final library in libraries)
                    LibraryRow(library: library, owned: true),
              ],
            ),
            // The shared section appears only when something is in it: a permanent empty heading
            // implies the viewer is missing something, when in fact nobody has shared anything.
            ...shared.maybeWhen(
              orElse: () => const <Widget>[],
              data: (libraries) => [
                if (libraries.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Text(
                      t(LibraryKeys.listSharedWithYou),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  for (final library in libraries)
                    LibraryRow(library: library, owned: false),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One library, with whether the machine hosting it is answering.
///
/// The online badge is resolved per SERVER rather than per library: one paired machine can host
/// several libraries, and asking the directory once per library would ask the same question four
/// times over.
class LibraryRow extends ConsumerWidget {
  const LibraryRow({required this.library, required this.owned, super.key});

  final LibrarySummary library;
  final bool owned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final server = ref.watch(serverStatusProvider(library.serverId));
    final online = server.value?.endpoint.online;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHigh,
        child: Icon(
          owned ? Icons.library_music_rounded : Icons.folder_shared_rounded,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(library.name),
      subtitle: Text(
        t(LibraryKeys.cardTrackCount, {'count': library.trackCount}),
      ),
      // Nothing at all until the directory answers: a row that says "Offline" while the request
      // is still in flight accuses a server that is fine.
      trailing: online == null
          ? null
          : Text(
              t(
                online
                    ? LibraryKeys.listServerOnline
                    : LibraryKeys.listServerOffline,
              ),
              style: theme.textTheme.labelMedium?.copyWith(
                color: online
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) =>
              LibraryDetailScreen(libraryId: library.id, owned: owned),
        ),
      ),
    );
  }
}
