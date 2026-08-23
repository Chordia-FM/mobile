import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../library/data/library_providers.dart';
import '../library/data/pins.dart';
import '../library/widgets/library_states.dart';
import 'collaborators_sheet.dart';
import 'cover_sheet.dart';
import 'data/playlists_providers.dart';
import 'widgets/visibility_choice.dart';

/// What a management action did to the playlist, which is what the caller needs to know.
enum PlaylistManageOutcome {
  /// Nothing changed, or the sheet was dismissed.
  unchanged,

  /// The playlist still exists and is different — reload it.
  edited,

  /// It is gone from the viewer's world, by deletion or by leaving. The page showing it has to go
  /// with it: there is nothing left to reload.
  removed,
}

/// Every edit a playlist's owner or collaborator can make to it, gathered in one sheet.
///
/// One sheet rather than a row of icons in the app bar: a phone header has room for two actions,
/// and the ones that end up cut are always delete and sharing — the two nobody can find anywhere
/// else.
Future<PlaylistManageOutcome> showPlaylistManageSheet(
  BuildContext context, {
  required PlaylistDetail detail,
}) async =>
    await showModalBottomSheet<PlaylistManageOutcome>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _ManageSheet(detail: detail),
    ) ??
    PlaylistManageOutcome.unchanged;

class _ManageSheet extends ConsumerWidget {
  const _ManageSheet({required this.detail});

  final PlaylistDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final owned = detail.owned ?? false;
    final canEdit = detail.canEdit ?? owned;
    final pinned = isPinned(ref, PinKind.playlist, detail.id);

    // Every action below runs on THIS context and closes afterwards with what actually happened.
    // Closing first and opening the next surface on the page beneath would be tidier to look at
    // and would lose the answer: the caller has to be told whether the playlist still exists, and
    // a sheet that has already popped has nothing left to tell it with.
    void close(PlaylistManageOutcome outcome) {
      if (context.mounted) Navigator.of(context).pop(outcome);
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(detail.name),
            subtitle: Text(t(PlaylistsKeys.editTitle)),
          ),
          const Divider(height: 1),
          if (owned)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(t(PlaylistsKeys.editTitle)),
              onTap: () async {
                final saved = await showPlaylistDetailsSheet(
                  context,
                  detail: detail,
                );
                if (saved) ref.invalidate(playlistsProvider);
                close(
                  saved
                      ? PlaylistManageOutcome.edited
                      : PlaylistManageOutcome.unchanged,
                );
              },
            ),
          if (owned)
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(t(PlaylistsKeys.editChoosePhoto)),
              onTap: () async {
                final changed = await showPlaylistCoverSheet(
                  context,
                  playlistId: detail.id,
                  autoCoverUrls: detail.autoCoverUrls ?? const [],
                  hasCover: detail.coverUrl != null,
                );
                if (changed) ref.invalidate(playlistsProvider);
                close(
                  changed
                      ? PlaylistManageOutcome.edited
                      : PlaylistManageOutcome.unchanged,
                );
              },
            ),
          if (canEdit)
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: Text(t(PlaylistsKeys.collaboratorsManage)),
              onTap: () async {
                final left = await showCollaboratorsSheet(
                  context,
                  playlistId: detail.id,
                  initial: detail.collaborators ?? const [],
                  owned: owned,
                );
                ref.invalidate(playlistsProvider);
                close(
                  left
                      ? PlaylistManageOutcome.removed
                      : PlaylistManageOutcome.edited,
                );
              },
            ),
          // Pinning is offered to anybody who can see the playlist, owner or not: the pinned shelf
          // is about what THIS reader reaches for, which is the same question for a playlist
          // somebody shared with them. The web client's playlist menu makes the same call.
          ListTile(
            leading: Icon(
              pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            ),
            title: Text(t(pinLabel(pinned))),
            onTap: () async {
              await togglePin(
                context,
                ref,
                kind: PinKind.playlist,
                id: detail.id,
              );
              close(PlaylistManageOutcome.unchanged);
            },
          ),
          if (owned)
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(t(PlaylistsKeys.confirmDeleteTitle)),
              // The confirmation runs on THIS context rather than after a pop: the answer decides
              // what this sheet reports back, and a sheet that has already closed has no way to
              // tell the page underneath that the playlist it is showing no longer exists.
              onTap: () async {
                if (await confirmDeletePlaylist(context, ref, detail)) {
                  ref.invalidate(playlistsProvider);
                  close(PlaylistManageOutcome.removed);
                }
              },
            )
          // Not the owner: the way out is leaving, and it is the only destructive action a
          // collaborator has. Offering "Delete" to somebody who cannot delete is worse than not
          // offering it at all.
          else if (canEdit)
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: Text(t(PlaylistsKeys.leaveTitle)),
              onTap: () async {
                if (await confirmLeavePlaylist(context, ref, detail.id)) {
                  ref.invalidate(playlistsProvider);
                  close(PlaylistManageOutcome.removed);
                }
              },
            ),
        ],
      ),
    );
  }
}

/// Name, description and who can see it. Answers true when anything was saved.
Future<bool> showPlaylistDetailsSheet(
  BuildContext context, {
  required PlaylistDetail detail,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _DetailsSheet(detail: detail),
    ) ??
    false;

class _DetailsSheet extends ConsumerStatefulWidget {
  const _DetailsSheet({required this.detail});

  final PlaylistDetail detail;

  @override
  ConsumerState<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends ConsumerState<_DetailsSheet> {
  late final _name = TextEditingController(text: widget.detail.name);
  late final _description = TextEditingController(
    text: widget.detail.description ?? '',
  );
  late var _visibility = widget.detail.visibility ?? PlaylistVisibility.private;
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t(PlaylistsKeys.editTitle),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: t(PlaylistsKeys.editName),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: t(PlaylistsKeys.editDescription),
                  hintText: t(PlaylistsKeys.editDescriptionPlaceholder),
                ),
              ),
              const SizedBox(height: 16),
              VisibilityChoice(
                value: _visibility,
                onChanged: (value) => setState(() => _visibility = value),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(t(CommonKeys.actionsSave)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final api = ref.read(playlistsEditApiProvider);
    if (api == null) return;
    final detail = widget.detail;
    final name = _name.text.trim();
    final description = _description.text.trim();
    final clearing = description.isEmpty;

    // One PATCH, not three. Each field is sent only when it changed, and an emptied description is
    // sent as an explicit clear — an omitted field means "leave alone", not "erase".
    final changes = PlaylistPatch(
      name: name.isNotEmpty && name != detail.name ? name : null,
      description: !clearing && description != (detail.description ?? '')
          ? description
          : null,
      clearDescription: clearing && (detail.description ?? '').isNotEmpty
          ? true
          : null,
      visibility: _visibility != detail.visibility ? _visibility : null,
    );
    if (changes.name == null &&
        changes.description == null &&
        changes.clearDescription == null &&
        changes.visibility == null) {
      Navigator.of(context).pop(false);
      return;
    }

    setState(() => _saving = true);
    try {
      await api.update(detail.id, changes);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeError(error, ref.read(translationsProvider).call),
          ),
        ),
      );
    }
  }
}

/// Asks, then removes the signed-in user from the playlist. Answers true when they are off it.
///
/// The same call an owner uses to remove somebody else — the Hub lets a collaborator delete their
/// own membership — which is why walking away does not need the owner to be around to be asked.
Future<bool> confirmLeavePlaylist(
  BuildContext context,
  WidgetRef ref,
  String playlistId,
) async {
  final t = ref.read(translationsProvider).call;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(t(PlaylistsKeys.leaveTitle)),
      content: Text(t(PlaylistsKeys.leaveConfirmBody)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(t(CommonKeys.actionsCancel)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(t(PlaylistsKeys.leaveConfirmLabel)),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false)) return false;

  final api = ref.read(playlistsEditApiProvider);
  if (api == null) return false;
  try {
    await api.removeCollaborator(playlistId, await api.myUserId());
    return true;
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(describeError(error, t))));
    }
    return false;
  }
}

/// Asks, then deletes. Answers true when the playlist is gone.
Future<bool> confirmDeletePlaylist(
  BuildContext context,
  WidgetRef ref,
  PlaylistDetail detail,
) async {
  final t = ref.read(translationsProvider).call;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(t(PlaylistsKeys.confirmDeleteTitle)),
      content: Text(
        t(PlaylistsKeys.confirmDeleteMessage, {'name': detail.name}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(t(CommonKeys.actionsCancel)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(t(CommonKeys.actionsDelete)),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false)) return false;

  final api = ref.read(playlistsEditApiProvider);
  if (api == null) return false;
  try {
    await api.delete(detail.id);
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(PlaylistsKeys.toastDeleteFailed))),
      );
    }
    return false;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t(PlaylistsKeys.toastDeleted, {'name': detail.name})),
      ),
    );
  }
  return true;
}
