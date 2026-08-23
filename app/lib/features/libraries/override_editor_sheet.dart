import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../library/widgets/library_states.dart';
import 'data/libraries_api.dart';
import 'data/libraries_providers.dart';
import 'overrides_screen.dart';

/// Corrects what one library calls an artist, an album or a track. Answers true when it saved.
///
/// An override is scoped to one library, not to the catalog: two owners can disagree about the
/// same album and both stay right. A blank field is not a blank value — it means "keep what the
/// catalog says", which is why clearing the whole override restores the enriched metadata rather
/// than emptying it.
Future<bool> showOverrideEditor(
  BuildContext context, {
  required String libraryId,
  required OverrideKind kind,
  required String entityId,
  required String name,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _OverrideEditor(
        libraryId: libraryId,
        kind: kind,
        entityId: entityId,
        name: name,
      ),
    ) ??
    false;

class _OverrideEditor extends ConsumerStatefulWidget {
  const _OverrideEditor({
    required this.libraryId,
    required this.kind,
    required this.entityId,
    required this.name,
  });

  final String libraryId;
  final OverrideKind kind;
  final String entityId;
  final String name;

  @override
  ConsumerState<_OverrideEditor> createState() => _OverrideEditorState();
}

class _OverrideEditorState extends ConsumerState<_OverrideEditor> {
  /// Keyed by the wire field name, so the form is a list of fields rather than a class per kind.
  final _fields = <String, TextEditingController>{};

  bool _overrideMain = false;
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  /// The fields this kind of entity has, in the order they read.
  List<String> get _names => switch (widget.kind) {
    OverrideKind.artist => const ['name', 'bio', 'genres'],
    OverrideKind.album => const [
      'title',
      'year',
      'label',
      'album_type',
      'genres',
    ],
    OverrideKind.track => const [
      'title',
      'artist',
      'album',
      'genre',
      'track_no',
      'disc_no',
    ],
  };

  @override
  void initState() {
    super.initState();
    for (final field in _names) {
      _fields[field] = TextEditingController();
    }
    _load();
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(overridesApiProvider);
    if (api == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final values = await _read(api);
      if (!mounted) return;
      values.forEach((field, value) => _fields[field]?.text = value);
      setState(() {
        _overrideMain = values['__main'] == 'true';
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      // A 404 is the normal case for an entity nobody has corrected yet, and an empty form is the
      // right thing to show for it — but the two are indistinguishable without checking, so a real
      // failure is reported and anything else opens blank.
      setState(() {
        _loading = false;
        _error = error is ApiException && error.isNotFound ? null : error;
      });
    }
  }

  /// The stored override flattened to the same string map the form edits.
  Future<Map<String, String>> _read(OverridesApi api) async {
    switch (widget.kind) {
      case OverrideKind.artist:
        final view = await api.artist(widget.libraryId, widget.entityId);
        return {
          if (view.name != null) 'name': view.name!,
          if (view.bio != null) 'bio': view.bio!,
          if (view.genres != null) 'genres': view.genres!.join(', '),
          '__main': '${view.overrideMain}',
        };
      case OverrideKind.album:
        final view = await api.album(widget.libraryId, widget.entityId);
        return {
          if (view.title != null) 'title': view.title!,
          if (view.year != null) 'year': '${view.year}',
          if (view.label != null) 'label': view.label!,
          if (view.albumType != null) 'album_type': view.albumType!,
          if (view.genres != null) 'genres': view.genres!.join(', '),
          '__main': '${view.overrideMain}',
        };
      case OverrideKind.track:
        final view = await api.track(widget.libraryId, widget.entityId);
        return {
          if (view.title != null) 'title': view.title!,
          if (view.artist != null) 'artist': view.artist!,
          if (view.album != null) 'album': view.album!,
          if (view.genre != null) 'genre': view.genre!,
          if (view.trackNo != null) 'track_no': '${view.trackNo}',
          if (view.discNo != null) 'disc_no': '${view.discNo}',
          '__main': '${view.overrideMain}',
        };
    }
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
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t(LibraryKeys.metadataOverridesEditTitle, {
                    'name': widget.name,
                  }),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  t(LibraryKeys.metadataOverridesInherited),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const ListSkeleton(rows: 3, height: 48)
                else if (_error != null)
                  ErrorRetry(error: _error!, onRetry: _load)
                else ...[
                  for (final field in _names) ...[
                    TextField(
                      controller: _fields[field],
                      keyboardType: _numeric(field)
                          ? TextInputType.number
                          : TextInputType.text,
                      minLines: field == 'bio' ? 3 : 1,
                      maxLines: field == 'bio' ? 6 : 1,
                      decoration: InputDecoration(
                        labelText: t(overrideFieldKey(field)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _overrideMain,
                    title: Text(t(LibraryKeys.metadataOverridesApplyToCatalog)),
                    subtitle: Text(
                      t(LibraryKeys.metadataOverridesApplyToCatalogHint),
                    ),
                    onChanged: (value) => setState(() => _overrideMain = value),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(t(CommonKeys.actionsSave)),
                  ),
                  TextButton(
                    onPressed: _saving ? null : _clear,
                    child: Text(t(LibraryKeys.metadataOverridesReset)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool _numeric(String field) =>
      field == 'year' || field == 'track_no' || field == 'disc_no';

  String? _text(String field) {
    final value = _fields[field]?.text.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  int? _number(String field) => int.tryParse(_text(field) ?? '');

  /// A comma-separated list, split and trimmed. Null when nothing was typed, which is "keep the
  /// catalog's genres" rather than "this has no genres".
  List<String>? _list(String field) {
    final raw = _text(field);
    if (raw == null) return null;
    final parts = [
      for (final part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    return parts.isEmpty ? null : parts;
  }

  Future<void> _save() async {
    final api = ref.read(overridesApiProvider);
    if (api == null) return;
    setState(() => _saving = true);
    try {
      switch (widget.kind) {
        case OverrideKind.artist:
          await api.putArtist(
            widget.libraryId,
            widget.entityId,
            ArtistOverrideInput(
              name: _text('name'),
              bio: _text('bio'),
              genres: _list('genres'),
              overrideMain: _overrideMain,
            ),
          );
        case OverrideKind.album:
          await api.putAlbum(
            widget.libraryId,
            widget.entityId,
            AlbumOverrideInput(
              title: _text('title'),
              year: _number('year'),
              label: _text('label'),
              albumType: _text('album_type'),
              genres: _list('genres'),
              overrideMain: _overrideMain,
            ),
          );
        case OverrideKind.track:
          await api.putTrack(
            widget.libraryId,
            widget.entityId,
            TrackOverrideInput(
              title: _text('title'),
              artist: _text('artist'),
              album: _text('album'),
              genre: _text('genre'),
              trackNo: _number('track_no'),
              discNo: _number('disc_no'),
              overrideMain: _overrideMain,
            ),
          );
      }
      _finish(LibraryKeys.metadataOverridesSaved);
    } on Object {
      _fail(LibraryKeys.metadataOverridesSaveFailed);
    }
  }

  Future<void> _clear() async {
    final api = ref.read(overridesApiProvider);
    if (api == null || !await askToClearOverride(context, ref)) return;
    if (!mounted) return;

    setState(() => _saving = true);
    try {
      await clearOverride(
        api,
        libraryId: widget.libraryId,
        kind: widget.kind,
        entityId: widget.entityId,
      );
      _finish(LibraryKeys.metadataOverridesResetDone);
    } on Object {
      _fail(LibraryKeys.metadataOverridesSaveFailed);
    }
  }

  void _finish(String messageKey) {
    if (!mounted) return;
    final message = ref.read(translationsProvider)(messageKey);
    // Resolved BEFORE the pop: this sheet's context is defunct the moment it closes, and the
    // confirmation belongs to the page underneath anyway.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _fail(String messageKey) {
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ref.read(translationsProvider)(messageKey))),
    );
  }
}
