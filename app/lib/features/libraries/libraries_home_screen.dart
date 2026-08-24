import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/list_row.dart';
import '../library/data/library_providers.dart';
import '../library/library_detail_screen.dart';
import '../library/widgets/library_states.dart';
import 'data/libraries_providers.dart';
import 'library_icons.dart';
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
        icon: const Icon(PhosphorIconsRegular.plus),
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
            PhosphorIconsRegular.hardDrives,
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
            icon: const Icon(PhosphorIconsRegular.plus),
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

    return ListRow(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: theme.colorScheme.surfaceContainerHigh,
        // The icon its owner chose, not one picked by whether the viewer owns it: the whole point
        // of the icon is that this library is recognisable at a glance, and it has to be the same
        // glyph here as it is on the web client's sidebar.
        child: LibraryIcon(
          icon: library.icon,
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Nothing at all until the directory answers: a row that says "Offline" while the
          // request is still in flight accuses a server that is fine.
          if (online != null)
            Text(
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
          IconButton(
            icon: const Icon(PhosphorIconsBold.dotsThree),
            tooltip: t(CommonKeys.actionsMore),
            onPressed: () => unawaited(_menu(context, ref)),
          ),
        ],
      ),
      // The MUSIC, not the settings. A library is only interesting as what is inside it, and the
      // web client's library card links to `/app/library/{id}` — its artists — with editing one
      // level in from there. Opening settings on a tap made the catalog unreachable entirely.
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              LibraryDetailScreen(libraryId: library.id, owned: owned),
        ),
      ),
      onLongPress: () => unawaited(_menu(context, ref)),
    );
  }

  /// Open, manage, and — for an owner — remove. The same three the web client's card menu offers.
  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final t = ref.read(translationsProvider).call;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListRow(
              title: Text(library.name),
              subtitle: Text(
                t(LibraryKeys.cardTrackCount, {'count': library.trackCount}),
              ),
            ),
            const Divider(height: 1),
            ListRow(
              leading: const Icon(PhosphorIconsRegular.folderOpen, size: 20),
              title: Text(t(CommonKeys.actionsOpen)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LibraryDetailScreen(
                      libraryId: library.id,
                      owned: owned,
                    ),
                  ),
                );
              },
            ),
            ListRow(
              leading: const Icon(PhosphorIconsRegular.pencilSimple, size: 20),
              title: Text(t(LibraryKeys.manageTitle)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LibraryManageScreen(
                      libraryId: library.id,
                      owned: owned,
                    ),
                  ),
                );
              },
            ),
            if (owned)
              ListRow(
                destructive: true,
                leading: const Icon(PhosphorIconsRegular.trash, size: 20),
                title: Text(t(LibraryKeys.editRemoveTitle)),
                subtitle: Text(t(LibraryKeys.editRemoveHelp)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(confirmRemoveLibrary(context, ref, library));
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks, then removes the library from the Hub. Answers true when it is gone.
///
/// The audio files are untouched — the Hub never had them — which is exactly what the confirmation
/// says, because "delete library" reads like "delete my music" to anybody who has not been told
/// otherwise.
Future<bool> confirmRemoveLibrary(
  BuildContext context,
  WidgetRef ref,
  LibrarySummary library,
) async {
  final t = ref.read(translationsProvider).call;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(t(LibraryKeys.editDeleteConfirmTitle)),
      content: Text(t(LibraryKeys.editDeleteConfirmMessage)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(t(CommonKeys.actionsCancel)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(t(LibraryKeys.editDeleteConfirmConfirmLabel)),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false)) return false;

  final api = ref.read(librariesApiProvider);
  if (api == null) return false;
  try {
    await api.remove(library.id);
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t(LibraryKeys.editDeleteFailed))));
    }
    return false;
  }
  ref
    ..invalidate(myLibrariesProvider)
    ..invalidate(libraryCoverageProvider);
  return true;
}
