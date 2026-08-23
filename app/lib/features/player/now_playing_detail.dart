import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart' show PlayerTrack;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/playback/adaptive.dart' show QualityStatus;
import '../../data/playback/notification_art.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/tokens.dart';
import '../catalog/data/catalog_providers.dart';
import '../catalog/widgets/artist_links.dart';
import '../catalog/widgets/entity_menu.dart';
import 'play_context_nav.dart';
import 'quality_sheet.dart';

/// The translate call, as every other feature that formats a string outside a widget declares it.
typedef Translate = String Function(String key, [Map<String, Object?> args]);

/// Everything the web's now-playing panel shows BELOW the transport.
///
/// `NowPlayingPanel.tsx` is one component shared by the desktop aside and the phone's expanded
/// player — the phone mounts it with the artwork, the context line and the title suppressed
/// (`ExpandedPlayer.tsx:392-402`), because those are already drawn above. What is left, and what
/// this is, is `NowPlayingPanel.tsx:144-171`: the album with the play count beside it, one
/// About-the-artist card per credited artist, and the file-quality readout.
///
/// None of it existed on the phone. The album was reachable only from the player's ⋮, and the play
/// count, the artist cards and the source-format and loudness rows had nowhere to be drawn at all —
/// their i18n keys were generated and had no call site.
class NowPlayingDetail extends StatelessWidget {
  const NowPlayingDetail({required this.track, super.key});

  final PlayerTrack track;

  @override
  Widget build(BuildContext context) {
    // Every credited artist including features, falling back to the single primary for a legacy
    // entry that predates the list (`NowPlayingPanel.tsx:98-103`).
    final artistIds = switch (track.artists) {
      final artists? when artists.isNotEmpty => [
        for (final artist in artists) artist.id,
      ],
      _ => [?track.artistId],
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AlbumAndPlays(track: track),
        // `space-y-5` between the panel's blocks.
        for (final id in artistIds) ...[
          const SizedBox(height: 20),
          _AboutArtistCard(artistId: id),
        ],
        const SizedBox(height: 20),
        _FileQuality(track: track),
      ],
    );
  }
}

/// The album as a link, and how many times this track has been played.
class _AlbumAndPlays extends ConsumerWidget {
  const _AlbumAndPlays({required this.track});

  final PlayerTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    // `track.plays` was captured when the entry went into the queue, so on a track played twice in
    // one sitting it is already stale. The catalog read is the fresh count (`NowPlayingPanel.tsx:95`).
    final fresh = ref.watch(trackDetailProvider(track.id)).value?.plays;
    final plays = fresh ?? track.plays ?? 0;

    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final album = track.album ?? t(PlayerKeys.nowPlayingAlbumFallback);

    return Wrap(
      // `gap-x-4 gap-y-1` on a wrapping row.
      spacing: 16,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (track.albumId case final albumId?)
          InkWell(
            onTap: () => PlayerMenuNav(context).goToAlbum(albumId),
            child: Text(
              album,
              // The full-strength foreground against the muted count beside it, which is how
              // `ArtistLinks` already marks the tappable part of a line. The web leans on
              // `hover:text-foreground`, and a phone never hovers — so a link drawn in the muted
              // colour would be indistinguishable from the text next to it.
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          )
        else if (track.album != null)
          Text(album, style: muted),
        if (plays > 0)
          Text(t(PlayerKeys.plays, {'count': plays}), style: muted),
      ],
    );
  }
}

/// One credited artist: portrait, monthly listeners, genres and the opening of the bio.
///
/// Silent about its own failure. A card that cannot be filled is not news the listener can act on,
/// and an error box under the transport would be a worse player than one that simply shows the
/// artists it could load — which is also how the web behaves, its query rendering nothing until it
/// resolves.
class _AboutArtistCard extends ConsumerWidget {
  const _AboutArtistCard({required this.artistId});

  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artist = ref.watch(artistDetailProvider(artistId)).value;
    if (artist == null) return const SizedBox.shrink();

    final t = ref.t;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final genres = artist.genres ?? const <String>[];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(PlayerKeys.nowPlayingAboutArtist, {'name': artist.name}),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: ChordiaType.semibold,
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => openArtistLink(context, artist.id),
            // The same menu the artist's row offers anywhere else, on the same gesture — the web
            // wraps this card in an `EntityContextMenu` for exactly that.
            onLongPress: () => unawaited(
              showEntityMenu(
                context,
                (page, sheetRef) => artistMenu(
                  page,
                  sheetRef,
                  ArtistLike(id: artist.id, name: artist.name),
                  nav: PlayerMenuNav(page),
                ),
              ),
            ),
            child: Row(
              children: [
                CoverArt(
                  // `size-14`, round, with the monogram fallback the web gives every artist.
                  sha256: artHashOf(artist.imageUrl),
                  size: 56,
                  shape: BoxShape.circle,
                  fallbackIcon: Icons.person_rounded,
                  fallbackInitial: artist.name,
                  semanticLabel: artist.name,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: ChordiaType.medium,
                        ),
                      ),
                      if ((artist.monthlyListeners ?? 0) > 0)
                        Text(
                          t(PlayerKeys.monthlyListeners, {
                            'count': artist.monthlyListeners,
                          }),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                      if (genres.isNotEmpty)
                        Text(
                          // Two at most, joined the way the web joins them.
                          genres.take(2).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (artist.bio case final bio? when bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              bio,
              // `line-clamp-4`: enough to be worth reading, not enough to push the file-quality
              // card off a phone screen. The artist page is where a whole biography belongs.
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: muted?.copyWith(height: 1.625),
            ),
          ],
        ],
      ),
    );
  }
}

/// The source file's own audio properties.
///
/// The library's `GET /tracks/{id}` already carries them and the app already asks for it on every
/// track — [loudnessReaderProvider] is that call, named for its first caller (the ReplayGain
/// preamp) rather than for the block it returns. Reusing it means the card costs nothing new.
final currentAudioProvider = FutureProvider.autoDispose
    .family<AudioProperties?, PlayerTrack>(
      (ref, track) => ref.watch(loudnessReaderProvider)(track),
      // No background retry, for the reason `catalog_providers.dart` gives: a silent retry leaves a
      // pending timer behind in widget tests, and this card has nothing to heal into anyway.
      retry: (_, _) => null,
    );

/// What the file is, and what is actually arriving.
///
/// `NowPlayingPanel.tsx:233-378`. The tier row and the divergence explanation already existed on
/// the phone, in the quality sheet; the two rows that had no mobile equivalent at all are the
/// SOURCE (codec, bit depth, sample rate) and the LOUDNESS the ReplayGain pass measured.
class _FileQuality extends ConsumerWidget {
  const _FileQuality({required this.track});

  final PlayerTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(currentAudioProvider(track)).value;
    // The whole card describes a file. Until its properties are in hand there is nothing to
    // describe, and a card of empty rows reads as a broken file rather than a pending read.
    if (audio == null) return const SizedBox.shrink();

    final t = ref.t;
    final theme = Theme.of(context);
    final normalize = ref.watch(playbackPreferencesProvider).normalizeVolume;

    return ValueListenableBuilder<QualityStatus>(
      valueListenable: ref.watch(qualityControlProvider).status,
      builder: (context, status, _) {
        // The tier the bytes NOW SOUNDING were fetched at, not the one in settings: a silent
        // override is precisely the failure this readout exists to catch.
        final shown = status.playing;
        // Spatial counts as passthrough whatever the tier says — the library refuses to transcode
        // it (`want_transcode = profile != Original && !meta.spatial`), so the bytes arriving ARE
        // the file even while the controller believes it stepped down.
        final passthrough = shown == QualityProfile.original || audio.spatial;

        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          t(PlayerKeys.qualityTitle),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: ChordiaType.semibold,
                          ),
                        ),
                        // The badge makes exactly ONE claim — what reaches your ears is the file's
                        // own bytes — and is absent whenever that is untrue rather than greyed or
                        // reworded. Derived from the tier ARRIVING and never from the file alone:
                        // an MP3 played untouched is passthrough but not lossless.
                        if (passthrough && audio.lossless)
                          _Pill(
                            label:
                                t(SettingsKeys.qualityLosslessLabel) +
                                (audio.spatial
                                    ? t(PlayerKeys.qualitySpatial)
                                    : ''),
                            accent: true,
                          )
                        else if (audio.spatial)
                          // Spatial is passthrough but not necessarily lossless, and it is the one
                          // property worth a pill of its own: nothing in the rows below names it.
                          _Pill(label: t(PlayerKeys.qualitySpatialOnly)),
                      ],
                    ),
                  ),
                  // The sheet is where the tier is chosen, so this is the web's "Change" — the
                  // shortcut from the readout to the control (`NowPlayingPanel.tsx:313-319`).
                  TextButton(
                    onPressed: () => unawaited(showQualitySheet(context)),
                    child: Text(t(PlayerKeys.qualityChange)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _SpecRow(
                label: t(PlayerKeys.qualitySource),
                value: describeSource(audio, t),
              ),
              _SpecRow(
                label: t(PlayerKeys.qualityPlayingAt),
                value:
                    '${t(qualityLabelKeyOf(shown))} · '
                    '${describeDelivery(audio, shown, t)}',
              ),
              // Only when normalization is on — otherwise the gain is measured but not applied,
              // and reporting it would claim a loudness nothing is doing anything about.
              if (audio.gainDb case final gain? when normalize)
                _SpecRow(
                  label: t(PlayerKeys.qualityLoudness),
                  value: '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(1)} dB',
                ),
              // Why what is playing is not what was chosen. The same note the sheet draws, so the
              // two surfaces cannot word it differently.
              QualityNote(
                status: status,
                padding: const EdgeInsets.only(top: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// `bit-depth · kHz · CODEC` for a lossless file, `CODEC · kHz` otherwise.
///
/// Bit depth is meaningless for a lossy codec — it describes the decoder's output, not the file —
/// so the web omits it there and so does this.
String describeSource(AudioProperties audio, Translate t) {
  final codec = audio.codec.toUpperCase();
  final khz = t(PlayerKeys.qualityKhz, {
    'value': formatKhz(audio.sampleRateHz),
  });
  return audio.lossless
      ? '${audio.bitDepth}-bit · $khz · $codec'
      : '$codec · $khz';
}

/// What the chosen tier actually costs, as a rate and as data per hour.
String describeDelivery(
  AudioProperties audio,
  QualityProfile profile,
  Translate t,
) {
  if (profile == QualityProfile.original) {
    // A lossless original has no single bitrate, so the honest figure is the uncompressed ceiling
    // its PCM would occupy. For a lossy original there is nothing to state but what it is.
    return audio.lossless
        ? t(PlayerKeys.qualityUpTo, {
            'value': formatDataPerHour(profileKbps(profile, audio), t),
          })
        : t(PlayerKeys.qualityOriginalSourceFile);
  }
  final kbps = profileKbps(profile, audio);
  return t(PlayerKeys.qualityStreamingRate, {
    'kbps': kbps,
    'data': formatDataPerHour(kbps, t),
  });
}

/// Delivered bitrate in kbps for a tier.
///
/// Must track `library/src/transcode.rs` — `high` 256k, `normal` 128k, `data_saver` 96k. This card
/// exists to tell the listener the truth about what they are hearing, so a figure that disagrees
/// with what the transcoder actually encodes is worse than showing nothing.
int profileKbps(QualityProfile profile, AudioProperties audio) =>
    switch (profile) {
      QualityProfile.high => 256,
      QualityProfile.normal => 128,
      QualityProfile.dataSaver => 96,
      // The source's uncompressed PCM rate, as the "up to" figure.
      QualityProfile.original =>
        (audio.sampleRateHz * audio.bitDepth * audio.channels) ~/ 1000,
    };

/// A kbps figure as data per hour, in decimal MB/GB — the units a data plan is sold in.
String formatDataPerHour(int kbps, Translate t) {
  final mb = kbps * 3600 / 8 / 1000;
  return mb >= 1000
      ? t(PlayerKeys.qualityDataPerHourGb, {
          'value': (mb / 1000).toStringAsFixed(1),
        })
      : t(PlayerKeys.qualityDataPerHourMb, {'value': mb.round()});
}

/// Hertz as kilohertz, without a trailing `.0` — `44.1`, but `48` rather than `48.0`.
String formatKhz(int hz) {
  final value = (hz / 1000).toStringAsFixed(1);
  return value.endsWith('.0') ? value.substring(0, value.length - 2) : value;
}

/// One `label … value` line of the file-quality list.
class _SpecRow extends StatelessWidget {
  const _SpecRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// The panel both cards are drawn on: `rounded-xl border border-border/60 bg-card p-4`.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.surfaces.card,
      borderRadius: ChordiaRadius.xlAll,
      border: Border.all(color: Theme.of(context).colorScheme.lineSoft),
    ),
    child: child,
  );
}

/// A small status pill, the phone's `Badge`.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = accent
        ? context.surfaces.accent
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.16),
        borderRadius: ChordiaRadius.smAll,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: colour),
      ),
    );
  }
}
