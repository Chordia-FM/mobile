import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/list_row.dart';
import '../../widgets/cover_art.dart';
import '../library/widgets/library_states.dart';
import 'data/playlists_providers.dart';

/// Sets or clears a playlist's cover. Answers true when something changed, so the caller reloads.
///
/// Three routes to a picture, in the order they are worth offering: a photo from the device, one
/// of the covers already inside the playlist, and none at all — which is not "no cover" but the
/// generated mosaic the playlist wears by default.
Future<bool> showPlaylistCoverSheet(
  BuildContext context, {
  required String playlistId,
  required List<String> autoCoverUrls,
  required bool hasCover,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _CoverSheet(
        playlistId: playlistId,
        autoCoverUrls: autoCoverUrls,
        hasCover: hasCover,
      ),
    ) ??
    false;

class _CoverSheet extends ConsumerStatefulWidget {
  const _CoverSheet({
    required this.playlistId,
    required this.autoCoverUrls,
    required this.hasCover,
  });

  final String playlistId;
  final List<String> autoCoverUrls;
  final bool hasCover;

  @override
  ConsumerState<_CoverSheet> createState() => _CoverSheetState();
}

class _CoverSheetState extends ConsumerState<_CoverSheet> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final picker = ref.watch(coverPhotoPickerProvider);
    final options = [
      for (final url in widget.autoCoverUrls)
        if (artHashOf(url) != null) artHashOf(url)!,
    ];

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              t(PlaylistsKeys.editChoosePhoto),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          // Absent, not disabled, while the app carries no gallery plugin: a row that cannot work
          // teaches nothing except that the app is broken. See `coverPhotoPickerProvider`.
          if (picker != null)
            ListRow(
              leading: const Icon(Icons.photo_library_outlined, size: 20),
              title: Text(t(PlaylistsKeys.editUploadPhoto)),
              enabled: !_busy,
              onTap: () => _upload(picker),
            ),
          if (options.isEmpty)
            EmptyNote(message: t(PlaylistsKeys.empty))
          else
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: options.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) => InkWell(
                  onTap: _busy
                      ? null
                      : () => _apply(() async => options[index]),
                  child: CoverArt(sha256: options[index], size: 80),
                ),
              ),
            ),
          if (widget.hasCover)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                onPressed: _busy ? null : _clear,
                child: Text(t(PlaylistsKeys.editRemovePhoto)),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _upload(CoverPhotoPicker pick) async {
    final photo = await pick();
    if (photo == null || !mounted) return;
    await _apply(() async {
      final api = ref.read(playlistsEditApiProvider)!;
      return api.uploadImage(photo.bytes);
    });
  }

  /// Runs [hash] for the content address, then points the playlist at it.
  ///
  /// The upload and the assignment are one action from the reader's side, so one failure message
  /// covers both: a picture that uploaded but was not applied is indistinguishable, on screen,
  /// from one that never uploaded.
  Future<void> _apply(Future<String> Function() hash) async {
    final api = ref.read(playlistsEditApiProvider);
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await api.setCover(widget.playlistId, await hash());
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(translationsProvider)(PlaylistsKeys.editPhotoError),
          ),
        ),
      );
    }
  }

  Future<void> _clear() async {
    final api = ref.read(playlistsEditApiProvider);
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await api.clearCover(widget.playlistId);
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(translationsProvider)(PlaylistsKeys.editSaveError),
          ),
        ),
      );
    }
  }
}
