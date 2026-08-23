import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/foundation.dart';

import 'settings_values.dart';

/// One edit to the listener's settings.
///
/// `PUT /v1/me/settings` replaces the blob wholesale rather than merging a delta, and the
/// generated [UserSettings] has no `copyWith` — so a screen that wants to flip one switch would
/// otherwise have to retype all twenty-six fields, and would silently drop any it forgot. This
/// carries just the fields being changed and [applyTo] folds them onto the settings last read from
/// the Hub.
///
/// A field left null is "not part of this edit", never "set to null". None of these settings has a
/// meaningful null on the wire — every one has a server-side default — so nothing is lost by
/// spending null on the sentinel.
@immutable
class SettingsPatch {
  const SettingsPatch({
    this.streamingQuality,
    this.normalizeVolume,
    this.crossfadeSeconds,
    this.preloadCount,
    this.autoplay,
    this.accent,
    this.accentMode,
    this.accentPalette,
    this.accentSpeed,
    this.nameAccent,
    this.showProfileAccents,
    this.locale,
    this.defaultSurface,
    this.scrobble,
    this.scrobblePrivacy,
    this.emailNotifications,
    this.profileVisibility,
    this.followersVisibility,
    this.followingVisibility,
    this.playlistsVisibility,
    this.followedArtistsVisibility,
    this.openToFollows,
  });

  final QualityProfile? streamingQuality;
  final bool? normalizeVolume;

  /// Clamped to the contract's range by [applyTo], not by whatever control produced it.
  final int? crossfadeSeconds;
  final int? preloadCount;

  final bool? autoplay;
  final String? accent;
  final AccentMode? accentMode;
  final List<String>? accentPalette;
  final AccentSpeed? accentSpeed;
  final bool? nameAccent;
  final bool? showProfileAccents;
  final String? locale;
  final String? defaultSurface;
  final bool? scrobble;
  final ScrobblePrivacy? scrobblePrivacy;
  final bool? emailNotifications;
  final Audience? profileVisibility;
  final Audience? followersVisibility;
  final Audience? followingVisibility;
  final Audience? playlistsVisibility;
  final Audience? followedArtistsVisibility;
  final bool? openToFollows;

  /// This edit folded onto [base].
  ///
  /// Goes through JSON rather than a hand-written field-by-field copy on purpose: the Hub owns
  /// this shape, and a field added to the contract has to survive a round trip through a client
  /// that has never heard of it. A copy constructor would drop it; a map merge carries it.
  UserSettings applyTo(UserSettings base) =>
      UserSettings.fromJson({...base.toJson(), ..._changes()});

  Map<String, Object?> _changes() => {
    if (streamingQuality != null) 'streaming_quality': streamingQuality!.wire,
    if (normalizeVolume != null) 'normalize_volume': normalizeVolume,
    if (crossfadeSeconds != null)
      'crossfade_seconds': clampCrossfadeSeconds(crossfadeSeconds!),
    if (preloadCount != null) 'preload_count': clampPreloadCount(preloadCount!),
    if (autoplay != null) 'autoplay': autoplay,
    if (accent != null) 'accent': accent,
    if (accentMode != null) 'accent_mode': accentMode!.wire,
    if (accentPalette != null) 'accent_palette': accentPalette,
    if (accentSpeed != null) 'accent_speed': accentSpeed!.wire,
    if (nameAccent != null) 'name_accent': nameAccent,
    if (showProfileAccents != null) 'show_profile_accents': showProfileAccents,
    if (locale != null) 'locale': locale,
    if (defaultSurface != null) 'default_surface': defaultSurface,
    if (scrobble != null) 'scrobble': scrobble,
    if (scrobblePrivacy != null) 'scrobble_privacy': scrobblePrivacy!.wire,
    if (emailNotifications != null) 'email_notifications': emailNotifications,
    if (profileVisibility != null)
      'profile_visibility': profileVisibility!.wire,
    if (followersVisibility != null)
      'followers_visibility': followersVisibility!.wire,
    if (followingVisibility != null)
      'following_visibility': followingVisibility!.wire,
    if (playlistsVisibility != null)
      'playlists_visibility': playlistsVisibility!.wire,
    if (followedArtistsVisibility != null)
      'followed_artists_visibility': followedArtistsVisibility!.wire,
    if (openToFollows != null) 'open_to_follows': openToFollows,
  };
}
