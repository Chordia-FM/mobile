import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../data/catalog_providers.dart';
import '../data/playback.dart';
import '../../../widgets/surface.dart';
import '../../../widgets/tokens.dart';
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
    // The one row the accent actually lands on. `isActive && "text-primary"` (TrackList.tsx:610,
    // :681) is the web's only per-row use of the colour, and its absence here is why the phone's
    // lists gave no answer to "which of these is playing".
    //
    // Selected as the BOOLEAN, not the id: a `select` that returns the id would rebuild every row
    // on every track change, and `TrackRow` is the most-built widget in the app. This way exactly
    // two rows rebuild — the one that stopped and the one that started.
    final isActive = ref.watch(
      nowPlayingTrackIdProvider.select((playing) => playing == track.id),
    );
    return TrackRowLayout(
      onTap: onTap,
      // Long press is the phone's right-click. The ⋮ button opens the same sheet, so the actions
      // are reachable without knowing the gesture exists.
      onLongPress: () =>
          unawaited(showTrackMenu(context, ref, track, onPlay: onTap)),
      dense: dense,
      active: isActive,
      trackNumber: trackNumber,
      coverSha: artHashOf(track.coverUrl),
      title: track.title,
      badges: TrackBadges(track: track),
      subtitle: showArtists
          ? ArtistLinks(
              artists: track.artists,
              fallbackName: track.artist,
              fallbackId: track.artistId,
            )
          : null,
      durationMs: track.durationMs,
      // The web's phone column is `[art +] title/artist · liked · ⋮` and nothing else
      // (TrackList.tsx:102). The duration is `hidden … sm:block` there (:798) — the note on that
      // rule measured keeping it at ~210px of a 310px row, leaving the title unreadable — so the
      // heart takes its place rather than sitting beside it.
      showDuration: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LikeHeart(trackId: track.id),
          EntityMenuButton(
            menu: (page, sheetRef) =>
                trackMenu(page, sheetRef, track, onPlay: onTap),
          ),
        ],
      ),
    );
  }
}

/// The like heart a catalog row carries, always visible.
///
/// The web hides Hide behind the row's `…` on a phone but keeps this one on screen
/// (`max-sm:opacity-100`, TrackList.tsx:769): liked status is worth seeing at a glance and worth
/// one tap, and the alternative here was a long press, a sheet and a scan of eleven rows.
///
/// 44px square, not `IconButton`'s 48: the web's box is `size-(--control-h-xs)`, which the coarse
/// block collapses to 44 (`widgets/tokens.dart`, [ChordiaControl.xs]). Those four pixels are the
/// difference between a title that ellipses at the artist's name and one that does not.
class LikeHeart extends ConsumerWidget {
  const LikeHeart({required this.trackId, super.key});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final scheme = Theme.of(context).colorScheme;
    // The BOOLEAN, not the set: selecting the whole set would rebuild every heart in the list on
    // every like, and this widget sits on the most-built row in the app.
    final liked = ref.watch(
      likedTrackIdsProvider.select((set) => set.value?.contains(trackId)),
    );

    Future<void> toggle() async {
      try {
        await ref.read(likedTrackIdsProvider.notifier).toggle(trackId);
      } on Object {
        // The controller has already put the old state back by the time this runs; without the
        // message the revert is indistinguishable from a tap that never registered.
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(t(ErrorsKeys.changeFailed))));
      }
    }

    return IconButton(
      // Null until the set has loaded. A heart that reports the wrong state is worse than one
      // that is briefly unavailable — the same call `LikeButton` makes in the player.
      onPressed: liked == null ? null : () => unawaited(toggle()),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: ChordiaControl.xs,
        height: ChordiaControl.xs,
      ),
      iconSize: 20,
      tooltip: t(
        (liked ?? false) ? LibraryKeys.likedRemove : LibraryKeys.likedSave,
      ),
      icon: Icon(
        PhosphorIcons.heart(
          (liked ?? false)
              ? PhosphorIconsStyle.fill
              : PhosphorIconsStyle.regular,
        ),
        color: (liked ?? false) ? scheme.primary : scheme.onSurfaceVariant,
      ),
    );
  }
}

/// The shape of a track row, with nothing in it that knows what a track is.
///
/// Ported from `components/catalog/TrackList.tsx:602-820`, which is one row for the whole web
/// client. Every number below is from that block:
///
/// - the box is `rounded-md px-3 py-1.5 transition-none hover:bg-accent/50` — [ChordiaRadius.md],
///   an instant fill, no ripple (see [PressFill]);
/// - the cover is `size-10` (40px) with `gap-3` after it, not the 48px a Material `ListTile` gives;
/// - the title is `truncate font-medium text-sm` and the artist line `text-muted-foreground
///   text-xs` — the phone was rendering 16px over 12px, a size too big on the line that matters;
/// - the duration is `text-right text-muted-foreground text-sm tabular-nums`;
/// - a hidden row is `opacity-40`;
/// - the active row is `text-primary` throughout, and its number slot shows `♪`.
///
/// The `ListTile` it replaces was not merely a different size. `ListTile` owns its own heights,
/// its own leading/trailing insets and its own ink ripple, so a row built from one is a Material
/// row wearing this app's colours — which is the whole complaint in miniature.
class TrackRowLayout extends StatelessWidget {
  const TrackRowLayout({
    required this.title,
    required this.durationMs,
    super.key,
    this.onTap,
    this.onLongPress,
    this.trackNumber,
    this.coverSha,
    this.leading,
    this.badges,
    this.subtitle,
    this.trailing,
    this.active = false,
    this.hidden = false,
    this.dense = false,
    this.showDuration = true,
  });

  final String title;
  final int durationMs;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Shown in place of the cover on an album, where forty copies of the same cover say nothing.
  final int? trackNumber;

  final String? coverSha;

  /// Replaces the artwork entirely — a drag handle in reorder mode, a queue position.
  final Widget? leading;

  /// Explicit / variant markers, beside the title.
  final Widget? badges;

  /// The second line. A widget, because on a catalog row every credited artist is its own link.
  final Widget? subtitle;

  final Widget? trailing;

  /// This row is the track currently playing.
  final bool active;

  /// Hidden by the listener — `opacity-40` on the web.
  final bool hidden;

  final bool dense;

  /// Whether the duration takes its cell.
  ///
  /// The web's is `hidden … sm:block` (TrackList.tsx:798) — a phone never shows it. It stays on
  /// here for the rows that carry nothing in the actions cell, where the pixels are free and the
  /// runtime is the only fact a downloads or queue row has left to say; a row that gains the like
  /// heart gives it up, exactly as the web's phone column does.
  final bool showDuration;

  /// The web's `size-10` cover.
  static const coverSize = 40.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final ink = active ? scheme.primary : scheme.onSurface;
    final number = trackNumber;

    final row = Padding(
      // `px-3 py-1.5` inside the box. The 8 outside plus this 8 puts the content on the page
      // gutter while the fill still stops short of the screen edge, exactly as a `rounded-md` row
      // does inside the web's padded list.
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: dense ? 4 : 6),
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (number != null)
            SizedBox(
              width: 24,
              child: Text(
                // The web swaps the number for a marker on the playing row. Same idea, same glyph.
                active ? '♪' : '$number',
                textAlign: TextAlign.end,
                style: ChordiaType.sm.copyWith(
                  color: active ? scheme.primary : muted,
                  fontFeatures: ChordiaType.tabular,
                ),
              ),
            )
          else
            CoverArt(sha256: coverSha, size: coverSize, semanticLabel: title),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ChordiaType.sm.copyWith(
                          fontWeight: ChordiaType.medium,
                          color: ink,
                        ),
                      ),
                    ),
                    ?badges,
                  ],
                ),
                if (subtitle != null)
                  DefaultTextStyle.merge(
                    style: ChordiaType.xs.copyWith(color: muted),
                    child: subtitle!,
                  ),
              ],
            ),
          ),
          if (showDuration) ...[
            const SizedBox(width: 8),
            Text(
              formatTrackLength(durationMs),
              style: ChordiaType.sm.copyWith(
                color: muted,
                fontFeatures: ChordiaType.tabular,
              ),
            ),
          ],
          ?trailing,
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Opacity(
        opacity: hidden ? chordiaHiddenOpacity : 1,
        child: PressFill(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: ChordiaRadius.mdAll,
          fill: scheme.rowHighlight,
          child: row,
        ),
      ),
    );
  }
}

/// The markers that qualify a recording: explicit, and whatever was lifted out of the title.
///
/// The title is what is LEFT once the variants were removed, so the two are read together — this is
/// what stops every line of an album repeating "(Album Version (Explicit))".
class TrackBadges extends ConsumerWidget {
  /// The catalog's row.
  TrackBadges({required BrowseTrack track, super.key})
    : advisory = track.advisory,
      variants = [
        for (final variant in track.variants ?? const <TrackVariant>[])
          variant.wire,
      ];

  /// The same badges from the wire values alone, for a caller whose track is not a [BrowseTrack] —
  /// the player's queue entry carries the same two facts under `chordia_sync`'s own enum.
  const TrackBadges.of({
    required this.advisory,
    required this.variants,
    super.key,
  });

  /// `"explicit"` / `"clean"`, or null for unknown — a third state, not the same as clean.
  final String? advisory;

  /// Variant wire values, ordered by how much the marker changes the recording.
  final List<String> variants;

  /// Beyond this many, the rest are dropped: a row with six chips has lost the plot
  /// (`components/catalog/VariantBadges.tsx`).
  static const _limit = 2;

  /// Two letters, not a word: this sits in a track row where the title needs the width, and a chip
  /// reading "REMASTER" would cost more than the suffix it replaced. The full word is the
  /// accessible name.
  static const _short = <String, String>{
    'live': 'LV',
    'acoustic': 'AC',
    'instrumental': 'IN',
    'remix': 'RX',
    'demo': 'DM',
    'cover': 'CV',
    'karaoke': 'KA',
    'extended': 'EX',
    'radio_edit': 'RE',
    'single_version': 'SV',
    'remaster': 'RM',
    'bonus': 'BN',
    'deluxe': 'DX',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final scheme = Theme.of(context).colorScheme;
    if (advisory != 'explicit' && variants.isEmpty) {
      return const SizedBox.shrink();
    }

    // `size-[15px] rounded-[3px] bg-muted-foreground/85 font-bold text-[10px] text-background` —
    // a FILLED square with the page's own background as the letter, which is what makes the marker
    // read at a glance. The phone's version was a 25%-alpha fill under muted text, i.e. the one
    // badge in the app that was quieter than the line it annotates.
    Widget explicit(String label) => Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        width: 15,
        height: 15,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
          borderRadius: ChordiaRadius.badgeAll,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            height: 1,
            fontWeight: ChordiaType.bold,
            color: scheme.surface,
          ),
        ),
      ),
    );

    // `h-[15px] rounded-[3px] px-1 font-semibold text-[9px] text-muted-foreground ring-1
    // ring-border`.
    Widget variant(String label) => Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        height: 15,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.line),
          borderRadius: ChordiaRadius.badgeAll,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            height: 1,
            fontWeight: ChordiaType.semibold,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (advisory == 'explicit')
          Semantics(
            label: t(CatalogKeys.trackExplicit),
            child: explicit(t(CatalogKeys.trackExplicitShort)),
          ),
        // Already ordered by how much the marker changes the recording, so taking the first two
        // keeps the ones that matter rather than whichever the tagger happened to write first.
        for (final wire in variants.take(_limit))
          Semantics(
            label: t(variantKey(wire)),
            child: variant(_short[wire] ?? t(variantKey(wire))),
          ),
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
String variantKey(String variantWire) => 'catalog:track.variant.$variantWire';
