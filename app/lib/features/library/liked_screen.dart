import 'package:chordia_sync/chordia_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'data/formatting.dart';
import 'data/liked_controller.dart';
import 'data/library_providers.dart';
import 'widgets/collection_header.dart';
import 'widgets/library_states.dart';
import 'widgets/track_tile.dart';

/// Liked Songs — the list, and the heart that takes a song back out of it.
///
/// No pin and no share: Liked Songs is a fixed entry on the Library screen, so pinning it would
/// offer a second copy of something that cannot be removed anyway.
class LikedScreen extends ConsumerStatefulWidget {
  const LikedScreen({super.key});

  @override
  ConsumerState<LikedScreen> createState() => _LikedScreenState();
}

class _LikedScreenState extends ConsumerState<LikedScreen> {
  LikedController? _controller;

  @override
  void initState() {
    super.initState();
    final api = ref.read(likedApiProvider);
    if (api == null) return;
    final controller = LikedController(api: api, onFailure: _report)
      ..addListener(_onChanged);
    _controller = controller;
    controller.load();
  }

  @override
  void dispose() {
    _controller
      ?..removeListener(_onChanged)
      ..dispose();
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

    return Scaffold(
      appBar: AppBar(title: Text(t(LibraryKeys.likedTitle))),
      body: controller == null
          ? EmptyNote(message: t(ErrorsKeys.failedToLoad))
          : _content(controller, t),
    );
  }

  Widget _content(LikedController controller, Translate t) {
    if (controller.tracks.isEmpty) {
      if (controller.loading) return const ListSkeleton();
      if (controller.error != null) {
        return ErrorRetry(error: controller.error!, onRetry: controller.load);
      }
    }

    final handoff = ref.watch(libraryHandoffProvider);
    // Built here so the "Playing from" label is in the reader's language: it is shown by the
    // player, which has no idea which collection produced the queue.
    final playContext = LikedContext(name: t(LibraryKeys.likedTitle));
    final tracks = controller.tracks;

    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView.builder(
        itemCount: tracks.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CollectionHeader(
                  eyebrow: t(LibraryKeys.likedEyebrow),
                  title: t(LibraryKeys.likedTitle),
                  meta: [
                    t(LibraryKeys.likedSongCount, {'count': tracks.length}),
                    if (controller.durationMs > 0)
                      totalDuration(controller.durationMs, t),
                  ].join(' · '),
                  artwork: const GradientArtwork(
                    icon: Icons.favorite_rounded,
                    size: 200,
                  ),
                ),
                CollectionActions(
                  onPlay: tracks.isEmpty || handoff == null
                      ? null
                      : () => handoff.playTracks(tracks, context: playContext),
                  onShuffle: tracks.isEmpty || handoff == null
                      ? null
                      : () => handoff.playTracks(
                          tracks,
                          shuffle: true,
                          context: playContext,
                        ),
                ),
                const SizedBox(height: 8),
                if (tracks.isEmpty)
                  EmptyNote(
                    message: t(LibraryKeys.likedEmpty),
                    icon: Icons.favorite_border_rounded,
                  ),
              ],
            );
          }

          final track = tracks[index - 1];
          return TrackTile(
            key: ValueKey(track.id),
            title: track.title,
            artist: track.artist,
            durationMs: track.durationMs,
            coverSha: artHashOf(track.coverUrl),
            onTap: handoff == null
                ? null
                : () => handoff.playTracks(
                    tracks,
                    startIndex: index - 1,
                    context: playContext,
                  ),
            trailing: IconButton(
              icon: const Icon(Icons.favorite_rounded),
              tooltip: t(LibraryKeys.likedRemove),
              onPressed: () => controller.unlike(track),
            ),
          );
        },
      ),
    );
  }
}
