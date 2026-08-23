import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../library/data/library_providers.dart';
import '../library/widgets/library_states.dart';
import 'data/libraries_providers.dart';
import 'library_manage_screen.dart';
import 'pairing_wizard_screen.dart';

/// The libraries this account owns, the ones friends have shared with it, and the way to add one.
///
/// Owned and shared are separate sections rather than one list with badges, because they answer
/// different questions: what you can change, and what you can listen to.
class LibrariesHomeScreen extends ConsumerWidget {
  const LibrariesHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final mine = ref.watch(myLibrariesProvider);
    final shared = ref.watch(sharedLibrariesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t(LibraryKeys.listTitle))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openPairingWizard(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(t(LibraryKeys.listConnectServer)),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(myLibrariesProvider)
            ..invalidate(sharedLibrariesProvider)
            ..invalidate(libraryCoverageProvider);
        },
        child: ListView(
          // Room for the button, which would otherwise sit on top of the last row.
          padding: const EdgeInsets.only(bottom: 88),
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
                  _EmptyState()
                else
                  for (final library in libraries)
                    LibraryCard(library: library, owned: true),
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
                    LibraryCard(library: library, owned: false),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What to do when there are no libraries: connect a server, explained in one sentence.
class _EmptyState extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            Icons.dns_outlined,
            size: 40,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            t(LibraryKeys.listEmptyTitle),
            style: Theme.of(context).textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            t(LibraryKeys.listConnectServerBody),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => openPairingWizard(context),
            icon: const Icon(Icons.link_rounded),
            label: Text(t(LibraryKeys.listOpenSetup)),
          ),
        ],
      ),
    );
  }
}

/// One library, with whether the machine hosting it is answering and what is inside it.
///
/// The online badge is resolved per SERVER rather than per library: one paired machine can host
/// several libraries, and asking the directory once per library would ask the same question four
/// times over.
class LibraryCard extends ConsumerWidget {
  const LibraryCard({required this.library, required this.owned, super.key});

  final LibrarySummary library;
  final bool owned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final server = ref.watch(serverStatusProvider(library.serverId));
    final online = server.value?.endpoint.online;
    final counts = ref.watch(libraryCoverageProvider).value?[library.id];

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
        counts == null
            ? t(LibraryKeys.cardTrackCount, {'count': library.trackCount})
            : '${t(LibraryKeys.cardTrackCount, {'count': counts.trackCount})} · '
                  '${counts.albumCount} ${t(LibraryKeys.manageCountAlbums)} · '
                  '${counts.artistCount} ${t(LibraryKeys.manageCountArtists)}',
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
          builder: (_) =>
              LibraryManageScreen(libraryId: library.id, owned: owned),
        ),
      ),
    );
  }
}
