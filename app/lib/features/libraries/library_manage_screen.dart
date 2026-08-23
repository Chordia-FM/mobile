import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../library/data/formatting.dart';
import '../library/data/library_providers.dart';
import '../library/widgets/library_states.dart';
import 'data/libraries_providers.dart';
import 'icon_picker_sheet.dart';
import 'libraries_home_screen.dart';
import 'library_icons.dart';
import 'overrides_screen.dart';
import 'share_library_sheet.dart';

/// One library: what is in it, where it lives, who can reach it, and what its owner may change.
///
/// A shared library shows the same facts and none of the controls. Rendering the controls disabled
/// would suggest the viewer could gain them; a sentence saying whose library it is answers the
/// question instead.
class LibraryManageScreen extends ConsumerStatefulWidget {
  const LibraryManageScreen({
    required this.libraryId,
    required this.owned,
    super.key,
  });

  final String libraryId;
  final bool owned;

  @override
  ConsumerState<LibraryManageScreen> createState() =>
      _LibraryManageScreenState();
}

class _LibraryManageScreenState extends ConsumerState<LibraryManageScreen> {
  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final library = ref.watch(libraryDetailProvider(widget.libraryId));

    return Scaffold(
      appBar: AppBar(
        title: Text(library.value?.name ?? t(LibraryKeys.manageTitle)),
      ),
      body: library.when(
        loading: () => const ListSkeleton(),
        error: (error, stack) => ErrorRetry(
          error: error,
          onRetry: () =>
              ref.invalidate(libraryDetailProvider(widget.libraryId)),
        ),
        data: (summary) => RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(libraryDetailProvider(widget.libraryId))
              ..invalidate(libraryCoverageProvider)
              ..invalidate(librarySharesProvider(widget.libraryId));
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _contents(t),
              const Divider(),
              _server(summary, t),
              const Divider(),
              if (widget.owned) ...[
                _rename(summary, t),
                _icon(summary, t),
                const Divider(),
                _sharing(t),
                const Divider(),
                _overrides(t),
                const Divider(),
                _remove(summary, t),
              ] else
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(t(LibraryKeys.manageNotOwner)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tracks, albums and artists, from the Manager's coverage report.
  ///
  /// The Hub has no per-library album or artist count of its own, and adding up a page of browse
  /// results would print a number quietly capped at whatever that page holds.
  Widget _contents(Translate t) {
    final coverage = ref.watch(libraryCoverageProvider);
    final counts = coverage.value?[widget.libraryId];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            t(LibraryKeys.manageContents),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (counts == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              coverage.hasError
                  ? describeError(coverage.error!, t)
                  : t(LibraryKeys.manageCountsUnavailable),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _Count(
                  label: t(LibraryKeys.manageCountTracks),
                  value: counts.trackCount,
                ),
                _Count(
                  label: t(LibraryKeys.manageCountAlbums),
                  value: counts.albumCount,
                ),
                _Count(
                  label: t(LibraryKeys.manageCountArtists),
                  value: counts.artistCount,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _server(LibrarySummary summary, Translate t) {
    final server = ref.watch(serverStatusProvider(summary.serverId));
    final endpoint = server.value?.endpoint;
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(
        endpoint == null
            ? Icons.cloud_queue_rounded
            : endpoint.online
            ? Icons.cloud_done_rounded
            : Icons.cloud_off_rounded,
        color: (endpoint?.online ?? false)
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(t(LibraryKeys.manageServerSection)),
      subtitle: Text(
        endpoint == null
            ? t(LibraryKeys.listLoading)
            // The host, not the whole URL: the scheme and port are the same on every library
            // server and say nothing about which machine this is.
            : '${t(endpoint.online ? LibraryKeys.listServerOnline : LibraryKeys.listServerOffline)} · '
                  '${Uri.tryParse(endpoint.endpoint)?.host ?? endpoint.endpoint}',
      ),
    );
  }

  Widget _rename(LibrarySummary summary, Translate t) => ListTile(
    leading: const Icon(Icons.drive_file_rename_outline_rounded),
    title: Text(t(LibraryKeys.manageNameLabel)),
    subtitle: Text(summary.name),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => _renameDialog(summary, t),
  );

  /// The icon this library wears everywhere it is listed.
  ///
  /// Stored as a slug (or `emoji:` plus a literal emoji), which is what makes it the SAME icon on
  /// the web client — the column holds a name both clients agree on, never a drawing.
  Widget _icon(LibrarySummary summary, Translate t) => ListTile(
    leading: LibraryIcon(
      icon: summary.icon,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    title: Text(t(LibraryKeys.editIconLabel)),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => unawaited(_pickIcon(summary, t)),
  );

  Future<void> _pickIcon(LibrarySummary summary, Translate t) async {
    final chosen = await showLibraryIconPicker(context, current: summary.icon);
    if (chosen == null || chosen == summary.icon) return;
    final api = ref.read(librariesApiProvider);
    if (api == null) return;
    try {
      await api.update(summary.id, UpdateLibraryRequest(icon: chosen));
      ref
        ..invalidate(libraryDetailProvider(widget.libraryId))
        ..invalidate(myLibrariesProvider);
      if (mounted) _snack(t(LibraryKeys.editIconSaved));
    } on Object {
      if (mounted) _snack(t(LibraryKeys.editIconSaveFailed));
    }
  }

  /// Removing the library from the Hub. Last, and on its own, because it is the one action here
  /// that cannot be undone by doing it again.
  Widget _remove(LibrarySummary summary, Translate t) => ListTile(
    leading: Icon(
      Icons.delete_outline_rounded,
      color: Theme.of(context).colorScheme.error,
    ),
    title: Text(t(LibraryKeys.editRemoveTitle)),
    subtitle: Text(t(LibraryKeys.editRemoveHelp)),
    onTap: () => unawaited(_removeLibrary(summary)),
  );

  Future<void> _removeLibrary(LibrarySummary summary) async {
    if (await confirmRemoveLibrary(context, ref, summary) && mounted) {
      // The page has to go with it: a library that is no longer in the directory has nothing left
      // to read, and its own refresh would fail on the way to saying so.
      Navigator.of(context).pop();
    }
  }

  Future<void> _renameDialog(LibrarySummary summary, Translate t) async {
    final field = TextEditingController(text: summary.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t(LibraryKeys.manageNameLabel)),
        content: TextField(controller: field, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t(CommonKeys.actionsCancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(field.text),
            child: Text(t(CommonKeys.actionsSave)),
          ),
        ],
      ),
    );
    field.dispose();

    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty || trimmed == summary.name) return;
    final api = ref.read(librariesApiProvider);
    if (api == null) return;
    try {
      await api.update(summary.id, UpdateLibraryRequest(name: trimmed));
      ref
        ..invalidate(libraryDetailProvider(widget.libraryId))
        ..invalidate(myLibrariesProvider);
      if (mounted) _snack(t(LibraryKeys.editNameSaved));
    } on Object {
      if (mounted) _snack(t(LibraryKeys.editRenameFailed));
    }
  }

  Widget _sharing(Translate t) {
    final shares = ref.watch(librarySharesProvider(widget.libraryId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            t(LibraryKeys.shareManagerTitle),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            t(LibraryKeys.shareManagerHelp),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        ...shares.when(
          loading: () => const [ListSkeleton(rows: 1, height: 56)],
          error: (error, stack) => [
            ErrorRetry(
              error: error,
              onRetry: () =>
                  ref.invalidate(librarySharesProvider(widget.libraryId)),
            ),
          ],
          data: (rows) => [
            if (rows.isEmpty)
              EmptyNote(message: t(LibraryKeys.shareManagerEmpty))
            else
              for (final share in rows)
                ShareRow(
                  libraryId: widget.libraryId,
                  share: share,
                  onChanged: () =>
                      ref.invalidate(librarySharesProvider(widget.libraryId)),
                ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: OutlinedButton.icon(
            onPressed: () async {
              await showShareLibrarySheet(context, libraryId: widget.libraryId);
              ref.invalidate(librarySharesProvider(widget.libraryId));
            },
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: Text(t(LibraryKeys.shareManagerAddFriend)),
          ),
        ),
      ],
    );
  }

  Widget _overrides(Translate t) {
    final overrides = ref.watch(libraryOverridesProvider(widget.libraryId));
    final count = overrides.value?.length;

    return ListTile(
      leading: const Icon(Icons.edit_note_rounded),
      title: Text(t(LibraryKeys.manageOpenOverrides)),
      subtitle: Text(
        count == null
            ? t(LibraryKeys.listLoading)
            : t(LibraryKeys.metadataOverridesTitle, {'count': count}),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OverridesScreen(libraryId: widget.libraryId),
        ),
      ),
    );
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: theme.textTheme.headlineSmall),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
