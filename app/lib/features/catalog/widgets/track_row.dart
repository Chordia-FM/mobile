import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../format.dart';
import 'artist_links.dart';
import 'entity_menu.dart';

/// One song, everywhere a song is listed.
///
/// The album page, an artist's popular list, a genre's top tracks and search results all use this
/// one row. That is the point: these lists sit two taps from each other, and a row that is 56px
/// tall on one screen and 64px on the next is the single most obvious way an app reads as
/// unfinished.
class TrackRow extends ConsumerWidget {
  const TrackRow({
    required this.track,
    required this.onTap,
    super.key,
    this.trackNumber,
    this.showArtists = true,
    this.dense = false,
  });

  final BrowseTrack track;

  /// Plays the list this row belongs to, from this row. Supplied by the host, because only the host
  /// knows what the list IS — see `SliverTrackList`.
  final VoidCallback onTap;

  /// Shown in place of the cover on an album, where forty copies of the same cover say nothing.
  final int? trackNumber;

  /// Hidden on an album whose every track is by the album artist, where the line is pure repetition.
  final bool showArtists;

  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final number = trackNumber;

    return ListTile(
      dense: dense,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      onTap: onTap,
      // Long press is the phone's right-click. The ⋮ button opens the same sheet, so the actions
      // are reachable without knowing the gesture exists.
      onLongPress: () => unawaited(showTrackMenu(context, ref, track)),
      leading: number == null
          ? CoverArt(sha256: artHashOf(track.coverUrl), size: 48)
          : SizedBox(
              width: 32,
              child: Text(
                '$number',
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          TrackBadges(track: track),
        ],
      ),
      subtitle: showArtists
          ? ArtistLinks(
              artists: track.artists,
              fallbackName: track.artist,
              fallbackId: track.artistId,
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatTrackLength(track.durationMs),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: ref.t(CommonKeys.actionsMore),
            onPressed: () => unawaited(showTrackMenu(context, ref, track)),
          ),
        ],
      ),
    );
  }
}

/// The markers that qualify a recording: explicit, and whatever was lifted out of the title.
///
/// The title is what is LEFT once the variants were removed, so the two are read together — this is
/// what stops every line of an album repeating "(Album Version (Explicit))".
class TrackBadges extends ConsumerWidget {
  const TrackBadges({required this.track, super.key});

  final BrowseTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final variants = track.variants ?? const <TrackVariant>[];
    if (track.advisory != 'explicit' && variants.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget chip(String label, {bool solid = false}) => Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: solid
              ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.25)
              : null,
          border: solid ? null : Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.2,
          ),
        ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (track.advisory == 'explicit')
          Semantics(
            label: t(CatalogKeys.trackExplicit),
            child: chip(t(CatalogKeys.trackExplicitShort), solid: true),
          ),
        for (final variant in variants) chip(t(variantKey(variant))),
      ],
    );
  }
}

/// The catalog key naming one variant.
///
/// Derived from the wire value rather than switched on the enum, because the two are defined
/// together: the catalog keys are literally `catalog:track.variant.<wire>`, so a variant added to
/// the contract cannot silently render an English fallback here — it renders the key, which is
/// visible immediately.
String variantKey(TrackVariant variant) =>
    'catalog:track.variant.${variant.wire}';
