import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../library/widgets/library_states.dart';
import 'data/playlists_providers.dart';
import 'smart_rules_screen.dart';
import 'widgets/visibility_choice.dart';

/// Makes a new playlist, and answers with it.
///
/// Both kinds start here. A smart playlist cannot be created in one sheet — it is nothing without
/// rules — so choosing Smart closes this and opens the rule builder, and this returns null. The
/// caller that needs a playlist back ([showAddToPlaylistSheet]) passes `allowSmart: false`, since
/// a rule-driven playlist has nowhere to put a track somebody is trying to file.
Future<Playlist?> showCreatePlaylistSheet(
  BuildContext context,
  WidgetRef ref, {
  String? seedName,
  bool allowSmart = true,
}) => showModalBottomSheet<Playlist>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) =>
      _CreateSheet(seedName: seedName, allowSmart: allowSmart),
);

class _CreateSheet extends ConsumerStatefulWidget {
  const _CreateSheet({required this.seedName, required this.allowSmart});

  final String? seedName;
  final bool allowSmart;

  @override
  ConsumerState<_CreateSheet> createState() => _CreateSheetState();
}

enum _Kind { normal, smart }

class _CreateSheetState extends ConsumerState<_CreateSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.seedName ?? '',
  );
  final _description = TextEditingController();
  var _kind = _Kind.normal;
  var _visibility = PlaylistVisibility.private;
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
    final theme = Theme.of(context);

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
                t(PlaylistsKeys.createTitle),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: t(PlaylistsKeys.createNamePlaceholder),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (widget.allowSmart) ...[
                const SizedBox(height: 20),
                Text(
                  t(PlaylistsKeys.createKindLabel),
                  style: theme.textTheme.labelLarge,
                ),
                for (final kind in _Kind.values)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => setState(() => _kind = kind),
                    title: Text(
                      t(
                        kind == _Kind.normal
                            ? PlaylistsKeys.createNormal
                            : PlaylistsKeys.createSmart,
                      ),
                    ),
                    subtitle: Text(
                      t(
                        kind == _Kind.normal
                            ? PlaylistsKeys.createNormalDescription
                            : PlaylistsKeys.createSmartDescription,
                      ),
                    ),
                    trailing: Icon(
                      _kind == kind
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: _kind == kind ? theme.colorScheme.primary : null,
                    ),
                  ),
              ],
              // A smart playlist has no description and no visibility of its own — its rules ARE
              // its description, and it is private by construction.
              if (_kind == _Kind.normal) ...[
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
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _name.text.trim().isEmpty || _saving
                    ? null
                    : _submit,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(t(PlaylistsKeys.createSubmit)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    if (_kind == _Kind.smart) {
      // The rule builder owns creation for this kind: a smart playlist saved with no rules is a
      // playlist that matches the whole library, which is never what somebody meant.
      final navigator = Navigator.of(context);
      navigator.pop();
      await openSmartRules(navigator.context, seedName: name);
      return;
    }

    final api = ref.read(playlistsEditApiProvider);
    if (api == null) return;
    setState(() => _saving = true);
    try {
      final created = await api.create(
        CreatePlaylistRequest(
          name: name,
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          visibility: _visibility,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
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

/// Creates a playlist without a sheet, for callers that already have a name.
///
/// Used by the "New playlist" row in the add-to-playlist picker, where the person has typed a name
/// into the search box and the fastest correct thing is to make exactly that.
Future<Playlist?> createPlaylistNamed(
  BuildContext context,
  WidgetRef ref,
  String name,
) async {
  final api = ref.read(playlistsEditApiProvider);
  final trimmed = name.trim();
  if (api == null || trimmed.isEmpty) return null;
  try {
    return await api.create(CreatePlaylistRequest(name: trimmed));
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeError(error, ref.read(translationsProvider).call),
          ),
        ),
      );
    }
    return null;
  }
}
