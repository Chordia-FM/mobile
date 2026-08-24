import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/list_row.dart';
import '../../widgets/cover_art.dart';
import '../library/data/formatting.dart';
import '../library/widgets/library_states.dart';
import 'data/playlists_providers.dart';

/// Puts songs into a playlist from the playlist's own page.
///
/// The web client's empty-playlist panel, in the shape a phone can hold: the viewer's liked songs
/// before anything is typed, catalog search once something is. A playlist with no way to fill it
/// from inside itself is a dead end — the only other route is finding each song in the catalog and
/// filing it from that song's ⋮ menu, which nobody does twenty times in a row.
///
/// Returns nothing: every add is applied optimistically and reported here, so the caller's job on
/// close is simply to reload.
Future<void> showAddSongsSheet(
  BuildContext context, {
  required String playlistId,
  required Set<String> alreadyIn,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) =>
      _AddSongsSheet(playlistId: playlistId, alreadyIn: alreadyIn),
);

class _AddSongsSheet extends ConsumerStatefulWidget {
  const _AddSongsSheet({required this.playlistId, required this.alreadyIn});

  final String playlistId;
  final Set<String> alreadyIn;

  @override
  ConsumerState<_AddSongsSheet> createState() => _AddSongsSheetState();
}

class _AddSongsSheetState extends ConsumerState<_AddSongsSheet> {
  final _query = TextEditingController();

  /// Everything already in the playlist, plus everything added on this visit. Held here rather
  /// than re-read from the playlist, which is not reloaded until this sheet closes.
  late final Set<String> _added = {...widget.alreadyIn};

  List<BrowseTrack> _liked = const [];
  List<BrowseTrack> _results = const [];
  var _searching = false;
  var _loadingLiked = true;

  /// A burst of keystrokes must be one request, not one per letter.
  Timer? _debounce;

  /// The term the in-flight search is for, so a slow early answer cannot overwrite a later one.
  String _inFlight = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadLiked());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadLiked() async {
    final api = ref.read(playlistsEditApiProvider);
    if (api == null) {
      setState(() => _loadingLiked = false);
      return;
    }
    try {
      final rows = await api.likedTracks();
      if (!mounted) return;
      setState(() {
        _liked = rows;
        _loadingLiked = false;
      });
    } on Object {
      if (mounted) setState(() => _loadingLiked = false);
    }
  }

  void _onTyped(String value) {
    _debounce?.cancel();
    final term = value.trim();
    // A term shorter than two characters matches most of a library, so it is not sent at all —
    // and clearing the field has to bring the liked strip back.
    if (term.length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
        _inFlight = '';
      });
      return;
    }
    setState(() {});
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_search(term)),
    );
  }

  Future<void> _search(String term) async {
    final api = ref.read(playlistsEditApiProvider);
    if (api == null) return;
    setState(() {
      _searching = true;
      _inFlight = term;
    });
    try {
      final rows = await api.searchTracks(term);
      if (mounted && _inFlight == term) {
        setState(() {
          _results = rows;
          _searching = false;
        });
      }
    } on Object {
      if (mounted && _inFlight == term) setState(() => _searching = false);
    }
  }

  Future<void> _add(BrowseTrack track) async {
    final api = ref.read(playlistsEditApiProvider);
    if (api == null) return;
    // Optimistic: the check has to appear under the finger. A row that does nothing for a round
    // trip is what makes people tap it twice.
    setState(() => _added.add(track.id));
    try {
      await api.addTrack(widget.playlistId, track.id);
    } on Object {
      if (!mounted) return;
      setState(() => _added.remove(track.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ref.read(translationsProvider)(PlaylistsKeys.addError)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final theme = Theme.of(context);
    final term = _query.text.trim();

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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  t(PlaylistsKeys.emptyStateTitle),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  t(PlaylistsKeys.emptyStateAddHint),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      PhosphorIconsRegular.magnifyingGlass,
                    ),
                    hintText: t(PlaylistsKeys.emptyStateSearchPlaceholder),
                  ),
                  onChanged: _onTyped,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(child: _body(t, term)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(Translate t, String term) {
    if (term.length >= 2) {
      if (_searching && _results.isEmpty) {
        return const ListSkeleton(rows: 3, height: 48);
      }
      if (_results.isEmpty) {
        return EmptyNote(message: t(SearchKeys.noResults, {'term': term}));
      }
      return _rows(_results);
    }
    if (_loadingLiked) return const ListSkeleton(rows: 3, height: 48);
    if (_liked.isEmpty) return EmptyNote(message: t(SearchKeys.prompt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            t(PlaylistsKeys.emptyStateFromLiked),
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        Flexible(child: _rows(_liked)),
      ],
    );
  }

  Widget _rows(List<BrowseTrack> rows) => ListView.builder(
    shrinkWrap: true,
    itemCount: rows.length,
    itemBuilder: (context, index) {
      final track = rows[index];
      final held = _added.contains(track.id);
      final label = ref.t(
        held ? PlaylistsKeys.emptyStateAdded : PlaylistsKeys.addToPlaylist,
      );
      return ListRow(
        leading: CoverArt(sha256: artHashOf(track.coverUrl), size: 40),
        title: Text(track.title),
        subtitle: Text(track.artist),
        trailing: IconButton(
          icon: Icon(
            held ? PhosphorIconsBold.check : PhosphorIconsRegular.plus,
          ),
          tooltip: label,
          onPressed: held ? null : () => unawaited(_add(track)),
        ),
        onTap: held ? null : () => unawaited(_add(track)),
      );
    },
  );
}
