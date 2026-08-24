import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/tokens.dart';
import '../library/widgets/library_states.dart';
import 'library_icons.dart';

/// Picks a library's icon. Answers with the value to store, or null when nothing was chosen.
///
/// Two tabs, matching the web client: a curated glyph set both clients agree on by name, and
/// emoji, which is where a much larger selection comes from at no cost. Reset WRITES the default
/// rather than clearing the column — the Hub COALESCEs `icon` on update, so it can never be nulled
/// from here, and `music-notes` is what "no icon" has always meant on the read side anyway.
Future<String?> showLibraryIconPicker(
  BuildContext context, {
  required String? current,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => _IconPickerSheet(current: current),
);

class _IconPickerSheet extends ConsumerStatefulWidget {
  const _IconPickerSheet({required this.current});

  final String? current;

  @override
  ConsumerState<_IconPickerSheet> createState() => _IconPickerSheetState();
}

enum _Tab { icons, emoji }

class _IconPickerSheetState extends ConsumerState<_IconPickerSheet> {
  final _filter = TextEditingController();
  late var _tab = (widget.current ?? '').startsWith(emojiIconPrefix)
      ? _Tab.emoji
      : _Tab.icons;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final term = _filter.text.trim();
    final current = widget.current ?? defaultLibraryIcon;

    final icons = [
      for (final entry in libraryIcons.entries)
        if (libraryIconMatches(
          term,
          entry.key.replaceAll('-', ' '),
          libraryIconKeywords[entry.key] ?? const [],
        ))
          entry.key,
    ];
    final emoji = [
      for (final row in libraryEmoji)
        if (libraryIconMatches(term, row.emoji, row.keywords)) row,
    ];
    final shown = _tab == _Tab.icons ? icons.length : emoji.length;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                t(LibraryKeys.editIconLabel),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<_Tab>(
                segments: [
                  ButtonSegment(
                    value: _Tab.icons,
                    label: Text(t(LibraryKeys.editIconTabIcons)),
                  ),
                  ButtonSegment(
                    value: _Tab.emoji,
                    label: Text(t(LibraryKeys.editIconTabEmoji)),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (selection) =>
                    setState(() => _tab = selection.first),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _filter,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: t(LibraryKeys.editIconSearchPlaceholder),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 12),
            if (shown == 0)
              EmptyNote(message: t(LibraryKeys.editIconNoMatches))
            else
              Flexible(
                child: GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 6,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: _tab == _Tab.icons
                      ? [
                          for (final name in icons)
                            _Tile(
                              value: name,
                              selected: current == name,
                              onPick: _pick,
                            ),
                        ]
                      : [
                          for (final row in emoji)
                            _Tile(
                              value: '$emojiIconPrefix${row.emoji}',
                              selected:
                                  current == '$emojiIconPrefix${row.emoji}',
                              onPick: _pick,
                            ),
                        ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextButton(
                onPressed: current == defaultLibraryIcon
                    ? null
                    : () => _pick(defaultLibraryIcon),
                child: Text(t(LibraryKeys.editIconReset)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pick(String value) => Navigator.of(context).pop(value);
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.value,
    required this.selected,
    required this.onPick,
  });

  final String value;
  final bool selected;
  final void Function(String value) onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: () => onPick(value),
        borderRadius: ChordiaRadius.mdAll,
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: ChordiaRadius.mdAll,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            color: selected ? scheme.primaryContainer : null,
          ),
          child: Center(
            child: LibraryIcon(
              icon: value,
              size: 24,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
