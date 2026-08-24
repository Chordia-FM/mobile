import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/list_row.dart';
import '../../widgets/cover_art.dart';
import '../library/data/library_providers.dart';
import '../library/widgets/library_states.dart';
import 'data/libraries_providers.dart';

/// Gives a friend access to a library.
///
/// Friends only, and that is a Hub rule rather than a UI shortcut: sharing has no invite path of
/// its own, so somebody who is not a friend yet has to become one first. The sheet says so instead
/// of offering a search box that could never find them.
Future<void> showShareLibrarySheet(
  BuildContext context, {
  required String libraryId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => _ShareSheet(libraryId: libraryId),
);

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.libraryId});

  final String libraryId;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  final _filter = TextEditingController();
  var _level = PermissionLevel.read;
  String? _sharing;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final friends = ref.watch(shareCandidatesProvider);
    final shares = ref.watch(librarySharesProvider(widget.libraryId)).value;
    final already = {for (final share in shares ?? const []) share.grantee.id};
    final typed = _filter.text.trim().toLowerCase();

    final rows = [
      for (final friend in friends.value ?? const <PublicUser>[])
        // Somebody who already has access is not a candidate; they are a row in the list above,
        // with a Remove button.
        if (!already.contains(friend.id))
          if (typed.isEmpty ||
              friend.displayName.toLowerCase().contains(typed) ||
              friend.handle.toLowerCase().contains(typed))
            friend,
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  t(LibraryKeys.shareManagerAddFriend),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: PermissionChoice(
                  value: _level,
                  onChanged: (value) => setState(() => _level = value),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _filter,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      PhosphorIconsRegular.magnifyingGlass,
                    ),
                    hintText: t(LibraryKeys.shareFilterFriends),
                  ),
                ),
              ),
              Flexible(child: _list(friends, rows)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(AsyncValue<List<PublicUser>> friends, List<PublicUser> rows) {
    final t = ref.t;
    if (friends.value == null) {
      return friends.hasError
          ? ErrorRetry(
              error: friends.error!,
              onRetry: () => ref.invalidate(shareCandidatesProvider),
            )
          : const ListSkeleton(rows: 2, height: 56);
    }
    if (rows.isEmpty) {
      return EmptyNote(message: t(LibraryKeys.shareNoFriends));
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final friend = rows[index];
        return ListRow(
          leading: CoverArt(
            sha256: artHashOf(friend.avatarUrl),
            size: 40,
            shape: BoxShape.circle,
            fallbackIcon: PhosphorIconsFill.user,
          ),
          title: Text(friend.displayName),
          subtitle: Text('@${friend.handle}'),
          trailing: _sharing == friend.id
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          enabled: _sharing == null,
          onTap: () => _share(friend),
        );
      },
    );
  }

  Future<void> _share(PublicUser friend) async {
    final api = ref.read(librariesApiProvider);
    if (api == null) return;
    final t = ref.read(translationsProvider).call;
    setState(() => _sharing = friend.id);
    try {
      await api.share(
        widget.libraryId,
        ShareBody(granteeId: friend.id, permissionLevel: _level),
      );
      ref.invalidate(librarySharesProvider(widget.libraryId));
      if (!mounted) return;
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() => _sharing = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t(LibraryKeys.shareFailed))));
    }
  }
}

/// What a grantee may do with the library.
class PermissionChoice extends ConsumerWidget {
  const PermissionChoice({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final PermissionLevel value;
  final ValueChanged<PermissionLevel> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t(LibraryKeys.sharePermission),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        SegmentedButton<PermissionLevel>(
          segments: [
            for (final level in PermissionLevel.values)
              ButtonSegment(
                value: level,
                label: Text(t(permissionLabelKey(level))),
              ),
          ],
          selected: {value},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ],
    );
  }
}

String permissionLabelKey(PermissionLevel level) => switch (level) {
  PermissionLevel.read => LibraryKeys.sharePermissionStreamOnly,
  PermissionLevel.download => LibraryKeys.sharePermissionStreamDownload,
};

/// One person who already has access, and the two things that can be done about it.
class ShareRow extends ConsumerStatefulWidget {
  const ShareRow({
    required this.libraryId,
    required this.share,
    required this.onChanged,
    super.key,
  });

  final String libraryId;
  final LibraryShare share;

  /// Called after a change lands, so the list that owns this row re-reads itself.
  final VoidCallback onChanged;

  @override
  ConsumerState<ShareRow> createState() => _ShareRowState();
}

class _ShareRowState extends ConsumerState<ShareRow> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final share = widget.share;

    return ListRow(
      leading: CoverArt(
        sha256: artHashOf(share.grantee.avatarUrl),
        size: 40,
        shape: BoxShape.circle,
        fallbackIcon: PhosphorIconsFill.user,
      ),
      title: Text(share.grantee.displayName),
      subtitle: Text(
        '@${share.grantee.handle} · ${t(permissionLabelKey(share.permissionLevel))}',
      ),
      trailing: _busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : PopupMenuButton<_ShareAction>(
              tooltip: t(CommonKeys.actionsMore),
              onSelected: _run,
              itemBuilder: (context) => [
                for (final level in PermissionLevel.values)
                  if (level != share.permissionLevel)
                    PopupMenuItem(
                      value: _ShareAction.level(level),
                      child: Text(t(permissionLabelKey(level))),
                    ),
                PopupMenuItem(
                  value: const _ShareAction.revoke(),
                  child: Text(
                    t(LibraryKeys.shareManagerRemoveAccess, {
                      'name': share.grantee.displayName,
                    }),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _run(_ShareAction action) async {
    final api = ref.read(librariesApiProvider);
    if (api == null) return;
    final t = ref.read(translationsProvider).call;
    setState(() => _busy = true);
    try {
      final level = action.level;
      if (level == null) {
        await api.revoke(widget.libraryId, widget.share.grantee.id);
      } else {
        // The same POST that granted it: the Hub upserts on (library, grantee), so changing a
        // permission is granting again at the new level rather than a revoke-and-regrant that
        // would kick somebody mid-track.
        await api.share(
          widget.libraryId,
          ShareBody(granteeId: widget.share.grantee.id, permissionLevel: level),
        );
      }
      widget.onChanged();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(LibraryKeys.shareManagerUpdateFailed))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Either "set the permission to this" or "take access away".
class _ShareAction {
  const _ShareAction.level(this.level);

  const _ShareAction.revoke() : level = null;

  final PermissionLevel? level;
}
