import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';

/// A playlist's face: the cover its owner chose, or a mosaic of what is inside it.
///
/// The mosaic is not decoration. A playlist with no chosen cover and a single album's artwork
/// stretched across it looks like that album; four tiles say "this is a collection" without a
/// word, and it re-shuffles as the playlist changes so it can never be out of date.
class MosaicCover extends StatelessWidget {
  const MosaicCover({
    required this.coverUrl,
    required this.autoCoverUrls,
    required this.size,
    super.key,
    this.semanticLabel,
  });

  final String? coverUrl;
  final List<String>? autoCoverUrls;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final chosen = artHashOf(coverUrl);
    final tiles = [
      for (final url in autoCoverUrls ?? const <String>[]) ?artHashOf(url),
    ];

    if (chosen != null || tiles.length < 4) {
      return CoverArt(
        sha256: chosen ?? (tiles.isEmpty ? null : tiles.first),
        size: size,
        fallbackIcon: Icons.queue_music_rounded,
        semanticLabel: semanticLabel,
      );
    }

    return Semantics(
      label: semanticLabel,
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.08),
        child: SizedBox(
          width: size,
          height: size,
          child: Wrap(
            children: [
              for (final hash in tiles.take(4))
                CoverArt(
                  sha256: hash,
                  size: size / 2,
                  borderRadius: BorderRadius.zero,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hero every collection screen wears: artwork, what kind of thing this is, its name, and one
/// line of facts about it.
///
/// Identical between playlists, smart playlists, liked songs and downloads on purpose. The web
/// client's four collection pages used to differ in cover size and meta order, and the result was
/// that each read as a different species of object rather than four collections.
class CollectionHeader extends StatelessWidget {
  const CollectionHeader({
    required this.eyebrow,
    required this.title,
    required this.meta,
    required this.artwork,
    super.key,
    this.description,
    this.onEditTitle,
    this.onEditArtwork,
  });

  final String eyebrow;
  final String title;

  /// The facts line: track count, runtime, owner, schedule. Already joined by the caller, which
  /// is what keeps the separator out of the catalogs.
  final String meta;

  final Widget artwork;

  /// The description, or the smart playlist's rules in the slot a description would take.
  final String? description;

  /// The title IS the edit affordance where there is one — no pencil, matching the web client.
  final VoidCallback? onEditTitle;

  final VoidCallback? onEditArtwork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = Text(
      title,
      style: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: onEditArtwork == null
                ? artwork
                : InkWell(onTap: onEditArtwork, child: artwork),
          ),
          const SizedBox(height: 20),
          Text(
            eyebrow.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          if (onEditTitle == null)
            heading
          else
            InkWell(onTap: onEditTitle, child: heading),
          if (description != null && description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            meta,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Play and Shuffle, plus whatever else a collection offers.
///
/// Both buttons are disabled when the app has no player wired yet — see `libraryHandoffProvider`.
/// A button that looks live and does nothing is worse than one that admits it cannot act.
class CollectionActions extends ConsumerWidget {
  const CollectionActions({
    required this.onPlay,
    required this.onShuffle,
    super.key,
    this.extra = const [],
  });

  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(t(CommonKeys.actionsPlay)),
          ),
          OutlinedButton.icon(
            onPressed: onShuffle,
            icon: const Icon(Icons.shuffle_rounded),
            label: Text(t(CommonKeys.actionsShuffle)),
          ),
          ...extra,
        ],
      ),
    );
  }
}

/// The square gradient tile Liked Songs and Downloads wear instead of artwork.
///
/// They have no cover to show and never will, so the alternative to a gradient is a grey box that
/// reads as artwork that failed to load.
class GradientArtwork extends StatelessWidget {
  const GradientArtwork({
    required this.icon,
    required this.size,
    super.key,
    this.colors = const [ChordiaColors.accent, ChordiaColors.paneElevated],
  });

  final IconData icon;
  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * 0.08),
      gradient: LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Icon(icon, size: size * 0.4, color: Colors.white),
  );
}
