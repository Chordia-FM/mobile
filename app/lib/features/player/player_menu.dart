import 'dart:async';

import 'package:chordia_api/chordia_api.dart' show StationKind;
import 'package:chordia_sync/chordia_sync.dart' show PlayerTrack;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/data/catalog_providers.dart';
import '../catalog/widgets/entity_menu.dart';
import 'eq_screen.dart';
import 'play_context_nav.dart';
import 'quality_sheet.dart';

/// What the playing (or queued) track offers, and what the player itself offers.
///
/// Separate from the catalog's `trackMenu` because the player carries a [PlayerTrack], not a
/// `BrowseTrack`: it has no library row behind it, so the download tile — which needs the fields a
/// catalog row carries — is deliberately absent rather than half-working. Everything a queue entry
/// CAN do, it does: like, file into a playlist, seed a station, open its album or artist, share.
EntityMenu playerTrackMenu(
  BuildContext page,
  WidgetRef ref,
  PlayerTrack track, {
  VoidCallback? onPlay,
  VoidCallback? onRemove,

  /// The playback rows — equalizer and quality — which belong to the player as a whole and so are
  /// offered only by the player's own ⋮, not by a queue row's.
  bool playbackControls = true,
}) {
  final t = ref.t;
  final host = MenuHost(page, ref, PlayerMenuNav(page));
  final liked = ref.watch(likedTrackIdsProvider).value?.contains(track.id);

  return EntityMenu(
    target: MenuTarget(
      kind: MenuTargetKind.track,
      id: track.id,
      title: track.title,
      subtitle: track.artist,
      imageUrl: track.coverUrl,
    ),
    sections: [
      MenuSection(
        id: 'play',
        items: [
          if (onPlay != null)
            MenuAction(
              id: 'play',
              label: t(CommonKeys.actionsPlay),
              icon: PhosphorIcons.play(PhosphorIconsStyle.fill),
              onSelect: onPlay,
            ),
          MenuAction(
            id: 'radio',
            label: t(DiscoveryKeys.stationStart),
            icon: PhosphorIcons.radio(),
            enabled: host.player != null && host.api != null,
            onSelect: () => host.startStation(StationKind.track, track.id),
          ),
        ],
      ),
      MenuSection(
        id: 'collect',
        items: [
          MenuAction(
            id: 'like',
            label: t(
              liked ?? false ? LibraryKeys.likedRemove : LibraryKeys.likedSave,
            ),
            icon: PhosphorIcons.heart(
              liked ?? false
                  ? PhosphorIconsStyle.fill
                  : PhosphorIconsStyle.regular,
            ),
            enabled: liked != null,
            onSelect: () async {
              try {
                await host.liked.toggle(track.id);
              } on Object {
                host.snack(t(ErrorsKeys.changeFailed));
              }
            },
          ),
          MenuAction(
            id: 'add-to-playlist',
            label: t(PlaylistsKeys.addToPlaylist),
            icon: PhosphorIcons.playlist(),
            onSelect: () => host.addToPlaylist([track.id], track.title),
          ),
        ],
      ),
      MenuSection(
        id: 'navigate',
        items: [
          if (track.albumId case final albumId?)
            MenuAction(
              id: 'go-to-album',
              label: t(CommonKeys.actionsGoToAlbum),
              icon: PhosphorIcons.disc(),
              onSelect: () => host.nav.goToAlbum(albumId),
            ),
          if (track.artistId case final artistId?)
            MenuAction(
              id: 'go-to-artist',
              label: t(CommonKeys.actionsGoToArtist),
              icon: PhosphorIcons.microphoneStage(),
              onSelect: () => host.nav.goToArtist(artistId),
            ),
          MenuAction(
            id: 'share',
            label: t(CommonKeys.actionsShare),
            icon: PhosphorIcons.shareNetwork(),
            onSelect: () =>
                host.share(path: '/tracks/${track.id}', title: track.title),
          ),
        ],
      ),
      MenuSection(
        id: 'playback',
        items: [
          if (playbackControls) ...[
            // The equalizer had exactly one way in — Settings → Playback — against the web's six.
            // The player is where somebody decides the bass is wrong.
            MenuAction(
              id: 'equalizer',
              label: t(PlayerKeys.equalizerTitle),
              icon: PhosphorIcons.equalizer(),
              onSelect: () => openEqualizer(page),
            ),
            // The tier ladder, the reason for a downgrade and Restore. The sheet existed and
            // nothing opened it.
            MenuAction(
              id: 'quality',
              label: t(PlayerKeys.qualityTitle),
              icon: PhosphorIcons.slidersHorizontal(),
              onSelect: () => unawaited(showQualitySheet(page)),
            ),
          ],
        ],
      ),
      MenuSection(
        id: 'danger',
        items: [
          if (onRemove != null)
            MenuAction(
              id: 'remove',
              label: t(PlayerKeys.queueRemoveFromQueue),
              icon: PhosphorIcons.x(),
              destructive: true,
              onSelect: onRemove,
            ),
        ],
      ),
    ],
  );
}
