import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../library/widgets/library_states.dart';
import 'data/playlists_providers.dart';
import 'widgets/visibility_choice.dart';

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
