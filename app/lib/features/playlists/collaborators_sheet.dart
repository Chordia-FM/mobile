import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../library/data/formatting.dart';
import '../library/widgets/library_states.dart';
import 'data/collaborators_controller.dart';
import 'data/playlists_providers.dart';

/// Who may edit a collaborative playlist: the roster, an invite box, and the way out.
///
/// Answers true when the viewer LEFT, because that is the one outcome the page underneath cannot
/// survive — a playlist you are no longer on is a playlist you can no longer read.
Future<bool> showCollaboratorsSheet(
  BuildContext context, {
  required String playlistId,
  required List<PublicUser> initial,
  required bool owned,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _CollaboratorsSheet(
        playlistId: playlistId,
        initial: initial,
        owned: owned,
      ),
    ) ??
    false;

class _CollaboratorsSheet extends ConsumerStatefulWidget {
  const _CollaboratorsSheet({
    required this.playlistId,
    required this.initial,
    required this.owned,
  });

  final String playlistId;
  final List<PublicUser> initial;

  /// Only the owner may invite. A collaborator sees the roster and their own way out.
  final bool owned;

  @override
  ConsumerState<_CollaboratorsSheet> createState() =>
      _CollaboratorsSheetState();
}

class _CollaboratorsSheetState extends ConsumerState<_CollaboratorsSheet> {
  CollaboratorsController? _controller;
  final _handle = TextEditingController();

  @override
  void initState() {
    super.initState();
    final api = ref.read(playlistsEditApiProvider);
    if (api == null) return;
    final controller = CollaboratorsController(
      playlistId: widget.playlistId,
      api: api,
      onFailure: _report,
      // Seeded from the detail the caller already holds, so the roster is on screen in the first
      // frame and the load below only confirms it.
      initial: widget.initial,
    )..addListener(_onChanged);
    _controller = controller;
    controller.load();
  }

  @override
  void dispose() {
    _controller
      ?..removeListener(_onChanged)
      ..dispose();
    _handle.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _report(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          describeError(error, ref.read(translationsProvider).call),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final controller = _controller;
    if (controller == null) {
      return EmptyNote(message: t(ErrorsKeys.failedToLoad));
    }
    final people = controller.people;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    t(PlaylistsKeys.collaboratorsManage),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (people.isEmpty)
                  EmptyNote(message: t(PlaylistsKeys.collaboratorsInvitePrompt))
                else
                  for (final person in people) _row(controller, person, t),
                if (widget.owned) _invite(controller, t),
                if (!widget.owned)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton.icon(
                      onPressed: () => _leave(controller),
                      icon: const Icon(Icons.logout_rounded),
                      label: Text(t(PlaylistsKeys.leaveConfirmLabel)),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    CollaboratorsController controller,
    PublicUser person,
    Translate t,
  ) {
    final pending = CollaboratorsController.isPending(person);
    return ListTile(
      leading: CoverArt(
        sha256: artHashOf(person.avatarUrl),
        size: 40,
        shape: BoxShape.circle,
        fallbackIcon: Icons.person_rounded,
      ),
      title: Text(person.displayName),
      subtitle: Text('@${person.handle}'),
      // A pending row is the optimistic placeholder: it is already on the list, but the Hub has
      // not yet said who it resolved to, so there is nothing to remove by id yet.
      trailing: pending
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: t(PlaylistsKeys.collaboratorsRemoveTitle, {
                'name': person.displayName,
              }),
              onPressed: () => controller.remove(person.id),
            ),
    );
  }

  Widget _invite(CollaboratorsController controller, Translate t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _handle,
            decoration: InputDecoration(
              labelText: t(PlaylistsKeys.collaboratorsInvitePrompt),
              // People type the "@" they see everywhere else; the Hub takes a bare handle, and the
              // controller strips it.
              prefixText: '@',
            ),
            onSubmitted: (_) => _add(controller),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: () => _add(controller),
          child: Text(t(CommonKeys.actionsAdd)),
        ),
      ],
    ),
  );

  Future<void> _add(CollaboratorsController controller) async {
    final handle = _handle.text.trim().replaceFirst(RegExp('^@'), '');
    if (handle.isEmpty) return;
    _handle.clear();
    if (await controller.add(handle) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(translationsProvider)(PlaylistsKeys.collaboratorsInvited, {
              'handle': handle,
            }),
          ),
        ),
      );
    }
  }

  Future<void> _leave(CollaboratorsController controller) async {
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
    if (!(confirmed ?? false)) return;
    final left = await controller.leave();
    if (left && mounted) Navigator.of(context).pop(true);
  }
}
