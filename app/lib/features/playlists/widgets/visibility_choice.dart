import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../catalog/widgets/list_row.dart';

/// Who can see a playlist, asked once at the moment of naming.
///
/// Creation used to be a one-field prompt, which meant the decision that matters most about a
/// playlist was made *after* it existed — nobody visits a settings sheet to lock down something
/// they just made. Asking here is both fewer steps and the safer default.
class VisibilityChoice extends ConsumerWidget {
  const VisibilityChoice({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final PlaylistVisibility value;
  final ValueChanged<PlaylistVisibility> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t(PlaylistsKeys.editVisibilityLabel),
          style: theme.textTheme.labelLarge,
        ),
        for (final option in PlaylistVisibility.values)
          ListRow(
            gutter: 0,
            onTap: () => onChanged(option),
            title: Text(t(visibilityLabelKey(option))),
            subtitle: Text(t(visibilityHintKey(option))),
            // A check rather than a radio: `RadioListTile`'s `groupValue`/`onChanged` pair is
            // deprecated in favour of a `RadioGroup` ancestor, and a selected-state icon says the
            // same thing without carrying a deprecation into a new screen.
            trailing: Icon(
              value == option
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: value == option ? theme.colorScheme.primary : null,
            ),
          ),
      ],
    );
  }
}

String visibilityLabelKey(PlaylistVisibility visibility) =>
    switch (visibility) {
      PlaylistVisibility.private => PlaylistsKeys.editVisibilityPrivate,
      PlaylistVisibility.unlisted => PlaylistsKeys.editVisibilityUnlisted,
      PlaylistVisibility.public => PlaylistsKeys.editVisibilityPublic,
    };

String visibilityHintKey(PlaylistVisibility visibility) => switch (visibility) {
  PlaylistVisibility.private => PlaylistsKeys.editVisibilityPrivateHint,
  PlaylistVisibility.unlisted => PlaylistsKeys.editVisibilityUnlistedHint,
  PlaylistVisibility.public => PlaylistsKeys.editVisibilityPublicHint,
};
