/// The playback vocabulary shared by the mesh and the player.
///
/// These live in the sync package rather than the player package because the mesh is the reason
/// they have to agree byte-for-byte with the web client: a queue crosses the wire whenever
/// playback moves between devices. Keeping them free of any engine dependency is what lets the
/// protocol be tested without an audio device — and what lets `chordia_api` map catalog rows into
/// them without depending on the player.
///
/// Field names on the wire are the web client's, which is why they are camelCase here and not the
/// Hub's snake_case: the Hub never reads a mesh frame, it only relays one.
library;

import 'package:meta/meta.dart';

import 'coerce.dart';

/// What an engine is doing. Mirrors `PlaybackState` in the web client's audio engine.
enum PlaybackState {
  idle('idle'),
  loading('loading'),
  playing('playing'),
  paused('paused'),
  ended('ended');

  const PlaybackState(this.wire);

  /// The string this state is written as in a mesh frame.
  final String wire;

  static PlaybackState? tryParse(Object? value) {
    for (final candidate in values) {
      if (candidate.wire == value) return candidate;
    }
    return null;
  }
}

enum RepeatMode {
  off('off'),
  all('all'),
  one('one');

  const RepeatMode(this.wire);

  final String wire;

  static RepeatMode? tryParse(Object? value) {
    for (final candidate in values) {
      if (candidate.wire == value) return candidate;
    }
    return null;
  }
}

/// What a generated station was seeded from. Absent means `artist`, for the reason the web client
/// documents: contexts serialised before the field existed, and the legacy artist-radio route,
/// both produce a station with no kind, and a consumer that defaults differently builds a dead
/// "Playing from" link.
enum StationKind {
  artist('artist'),
  track('track'),
  album('album'),
  genre('genre'),
  playlist('playlist');

  const StationKind(this.wire);

  final String wire;

  static StationKind? tryParse(Object? value) {
    for (final candidate in values) {
      if (candidate.wire == value) return candidate;
    }
    return null;
  }
}

/// One marker stripped from a track title, ordered by how much it changes the recording.
///
/// Mirrors the `TrackVariant` contract enum. An unrecognised marker from a newer peer is dropped
/// rather than rejected: a badge we cannot name is not a reason to discard somebody's queue.
enum TrackVariant {
  live('live'),
  acoustic('acoustic'),
  instrumental('instrumental'),
  remix('remix'),
  demo('demo'),
  cover('cover'),
  karaoke('karaoke'),
  extended('extended'),
  radioEdit('radio_edit'),
  singleVersion('single_version'),
  remaster('remaster'),
  bonus('bonus'),
  deluxe('deluxe');

  const TrackVariant(this.wire);

  final String wire;

  static TrackVariant? tryParse(Object? value) {
    for (final candidate in values) {
      if (candidate.wire == value) return candidate;
    }
    return null;
  }
}

/// One credited artist on a track, enough to render a chip and open that artist.
///
/// Named for its role rather than mirroring `chordia_api`'s `ArtistRef`, because it cannot BE that
/// type: `chordia_api` depends on this package, so the dependency only runs one way. The wire
/// shape is identical (`id`, `name`, `image_url`) — these objects are copied out of a catalog
/// response into a queue unchanged.
@immutable
class TrackArtist {
  const TrackArtist({required this.id, required this.name, this.imageUrl});

  final String id;
  final String name;

  /// Hub-relative `/v1/images/{hash}` path, or null where the artist has no picture.
  final String? imageUrl;

  static TrackArtist? tryFromJson(Object? raw) {
    final json = objectOrNull(raw);
    if (json == null) return null;
    final id = stringOrNull(json['id']);
    final name = stringOrNull(json['name']);
    if (id == null || name == null) return null;
    return TrackArtist(
      id: id,
      name: name,
      imageUrl: stringOrNull(json['image_url']),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (imageUrl != null) 'image_url': imageUrl,
  };

  @override
  bool operator ==(Object other) =>
      other is TrackArtist &&
      other.id == id &&
      other.name == name &&
      other.imageUrl == imageUrl;

  @override
  int get hashCode => Object.hash(id, name, imageUrl);

  @override
  String toString() => 'TrackArtist($id, $name)';
}

/// One entry in a queue.
///
/// Every optional field is omitted from the JSON when null rather than written as `null`, because
/// that is what the web client emits and what its validators accept for the `?:` fields. `album`
/// is the exception: it is `string | null` there, always present.
@immutable
class PlayerTrack {
  const PlayerTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.libraryId,
    required this.trackRef,
    required this.contentHash,
    this.qid,
    this.artistId,
    this.artists,
    this.albumId,
    this.plays,
    this.coverUrl,
    this.advisory,
    this.variants,
    this.autoplay,
  });

  /// Stable per-queue-entry id, assigned by the player.
  ///
  /// The same track can sit in a queue twice, so its catalog [id] does not identify the entry —
  /// reordering or removing "that one" needs something that does.
  final String? qid;

  final String id;
  final String title;

  /// The credited-artist display line ("X feat. Y"), as the Hub reconstructs it.
  final String artist;

  /// The primary artist's id, for the one-artist link.
  final String? artistId;

  /// All credited artists, ordered with the primary first. Null on a legacy entry that predates
  /// the field; an empty list means the Hub had nothing to credit.
  final List<TrackArtist>? artists;

  final String? album;
  final String? albumId;
  final int? plays;
  final int durationMs;
  final String? coverUrl;

  /// Hub library id, used to obtain a capability grant.
  final String libraryId;

  /// The library's own track id, used to build the stream URL.
  final String trackRef;

  final String contentHash;

  /// Content advisory (`"explicit"` / `"clean"`) from the file's rating tag. Null means unknown,
  /// which is a third state and not the same as "clean".
  final String? advisory;

  /// Markers taken out of the title, drawn beside it exactly as [advisory] is.
  final List<TrackVariant>? variants;

  /// Appended by autoplay rather than chosen by the listener, so the queue panel can mark where
  /// their queue ended and the station took over.
  final bool? autoplay;

  static PlayerTrack? tryFromJson(Object? raw) {
    final json = objectOrNull(raw);
    if (json == null) return null;
    final id = stringOrNull(json['id']);
    final title = stringOrNull(json['title']);
    final artist = stringOrNull(json['artist']);
    final libraryId = stringOrNull(json['libraryId']);
    final trackRef = stringOrNull(json['trackRef']);
    final contentHash = stringOrNull(json['contentHash']);
    final durationMs = millisOrNull(json['durationMs']);
    if (id == null ||
        title == null ||
        artist == null ||
        libraryId == null ||
        trackRef == null ||
        contentHash == null ||
        durationMs == null) {
      return null;
    }
    final albumValue = json['album'];
    if (albumValue != null && albumValue is! String) return null;
    if (!isOptionalString(json['artistId']) ||
        !isOptionalString(json['albumId']) ||
        !isOptionalString(json['coverUrl']) ||
        !isOptionalString(json['qid']) ||
        !isOptionalString(json['advisory'])) {
      return null;
    }
    final playsValue = json['plays'];
    if (playsValue != null && millisOrNull(playsValue) == null) return null;
    final artistsValue = json['artists'];
    List<TrackArtist>? artists;
    if (artistsValue != null) {
      artists = listOrNull(artistsValue, TrackArtist.tryFromJson);
      if (artists == null) return null;
    }
    final variantsValue = json['variants'];
    List<TrackVariant>? variants;
    if (variantsValue != null) {
      if (variantsValue is! List) return null;
      variants = [
        for (final marker in variantsValue) ?TrackVariant.tryParse(marker),
      ];
    }
    final autoplayValue = json['autoplay'];
    if (autoplayValue != null && autoplayValue is! bool) return null;
    return PlayerTrack(
      id: id,
      title: title,
      artist: artist,
      artistId: stringOrNull(json['artistId']),
      artists: artists,
      album: albumValue as String?,
      albumId: stringOrNull(json['albumId']),
      plays: playsValue == null ? null : millisOrNull(playsValue),
      durationMs: durationMs,
      coverUrl: stringOrNull(json['coverUrl']),
      libraryId: libraryId,
      trackRef: trackRef,
      contentHash: contentHash,
      advisory: stringOrNull(json['advisory']),
      variants: variants,
      qid: stringOrNull(json['qid']),
      autoplay: autoplayValue as bool?,
    );
  }

  Map<String, Object?> toJson() => {
    if (qid != null) 'qid': qid,
    'id': id,
    'title': title,
    'artist': artist,
    if (artistId != null) 'artistId': artistId,
    if (artists != null)
      'artists': [for (final artist in artists!) artist.toJson()],
    'album': album,
    if (albumId != null) 'albumId': albumId,
    if (plays != null) 'plays': plays,
    'durationMs': durationMs,
    if (coverUrl != null) 'coverUrl': coverUrl,
    'libraryId': libraryId,
    'trackRef': trackRef,
    'contentHash': contentHash,
    if (advisory != null) 'advisory': advisory,
    if (variants != null)
      'variants': [for (final variant in variants!) variant.wire],
    if (autoplay != null) 'autoplay': autoplay,
  };

  PlayerTrack copyWith({String? qid}) => PlayerTrack(
    id: id,
    title: title,
    artist: artist,
    artistId: artistId,
    artists: artists,
    album: album,
    albumId: albumId,
    plays: plays,
    durationMs: durationMs,
    coverUrl: coverUrl,
    libraryId: libraryId,
    trackRef: trackRef,
    contentHash: contentHash,
    advisory: advisory,
    variants: variants,
    qid: qid ?? this.qid,
    autoplay: autoplay,
  );

  @override
  bool operator ==(Object other) =>
      other is PlayerTrack &&
      other.qid == qid &&
      other.id == id &&
      other.title == title &&
      other.artist == artist &&
      other.artistId == artistId &&
      _sameArtists(other.artists) &&
      other.album == album &&
      other.albumId == albumId &&
      other.plays == plays &&
      other.durationMs == durationMs &&
      other.coverUrl == coverUrl &&
      other.libraryId == libraryId &&
      other.trackRef == trackRef &&
      other.contentHash == contentHash &&
      other.advisory == advisory &&
      _sameVariants(other.variants) &&
      other.autoplay == autoplay;

  bool _sameArtists(List<TrackArtist>? other) =>
      (other == null) == (artists == null) &&
      (artists == null || listEquals(artists!, other!));

  bool _sameVariants(List<TrackVariant>? other) =>
      (other == null) == (variants == null) &&
      (variants == null || listEquals(variants!, other!));

  @override
  int get hashCode => Object.hash(
    qid,
    id,
    title,
    artist,
    artistId,
    album,
    albumId,
    durationMs,
    libraryId,
    trackRef,
    contentHash,
    advisory,
    autoplay,
  );

  @override
  String toString() => 'PlayerTrack($trackRef, $title)';
}

/// Where a station should resume from, distinguished from "nobody has asked yet".
///
/// Three states have to survive a hand-off, and a plain `String?` only carries two. A station the
/// receiving device believes is exhausted stops autoplaying; a station it has simply never paged
/// keeps going. Collapsing the two would silently end somebody's radio when they moved it to
/// their phone, which is why the absent case is the null [StationCursor] and the exhausted case is
/// a [StationCursor] holding null.
@immutable
class StationCursor {
  const StationCursor(this.value);

  /// The opaque resume token, or null once the station is finite and exhausted.
  final String? value;

  @override
  bool operator ==(Object other) =>
      other is StationCursor && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'StationCursor(${value ?? 'exhausted'})';
}

/// Where the current queue was started from, for the "Playing from …" back-link.
@immutable
sealed class PlayContext {
  const PlayContext({required this.name});

  /// The human-readable source name, shown as-is.
  final String name;

  /// The `kind` discriminator on the wire.
  String get kind;

  /// The source's id, or null for the two kinds that have none.
  String? get id;

  static PlayContext? tryFromJson(Object? raw) {
    final json = objectOrNull(raw);
    if (json == null) return null;
    final name = stringOrNull(json['name']);
    if (name == null) return null;
    final kind = json['kind'];
    if (kind == 'liked') return LikedContext(name: name);
    if (kind == 'search') return SearchContext(name: name);
    final id = stringOrNull(json['id']);
    if (id == null) return null;
    switch (kind) {
      case 'album':
        return AlbumContext(id: id, name: name);
      case 'artist':
        return ArtistContext(id: id, name: name);
      case 'radio':
        return RadioContext(
          id: id,
          name: name,
          stationKind: StationKind.tryParse(json['stationKind']),
          stationCursor: json.containsKey('stationCursor')
              ? StationCursor(stringOrNull(json['stationCursor']))
              : null,
        );
      case 'playlist':
        return PlaylistContext(id: id, name: name);
      case 'smart':
        return SmartPlaylistContext(id: id, name: name);
      case 'library':
        return LibraryContext(id: id, name: name);
      default:
        return null;
    }
  }

  Map<String, Object?> toJson();
}

@immutable
class AlbumContext extends PlayContext {
  const AlbumContext({required this.id, required super.name});

  @override
  final String id;

  @override
  String get kind => 'album';

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'id': id, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is AlbumContext && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(kind, id, name);
}

@immutable
class ArtistContext extends PlayContext {
  const ArtistContext({required this.id, required super.name});

  @override
  final String id;

  @override
  String get kind => 'artist';

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'id': id, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is ArtistContext && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(kind, id, name);
}

/// A generated station. [id] is the SEED, whose meaning depends on [stationKind] — an artist id, a
/// track id, an album id, a playlist id, or a genre SLUG.
@immutable
class RadioContext extends PlayContext {
  const RadioContext({
    required this.id,
    required super.name,
    this.stationKind,
    this.stationCursor,
  });

  @override
  final String id;

  /// Null means `artist`; see [StationKind].
  final StationKind? stationKind;

  /// Null means nobody has paged this station yet; see [StationCursor].
  final StationCursor? stationCursor;

  @override
  String get kind => 'radio';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'id': id,
    'name': name,
    if (stationKind != null) 'stationKind': stationKind!.wire,
    if (stationCursor != null) 'stationCursor': stationCursor!.value,
  };

  @override
  bool operator ==(Object other) =>
      other is RadioContext &&
      other.id == id &&
      other.name == name &&
      other.stationKind == stationKind &&
      other.stationCursor == stationCursor;

  @override
  int get hashCode => Object.hash(kind, id, name, stationKind, stationCursor);
}

@immutable
class PlaylistContext extends PlayContext {
  const PlaylistContext({required this.id, required super.name});

  @override
  final String id;

  @override
  String get kind => 'playlist';

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'id': id, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is PlaylistContext && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(kind, id, name);
}

/// A SMART playlist, and deliberately not [PlaylistContext]: [id] indexes a different table, and
/// treating the two as one wrote smart-playlist ids into the append-only listening-events fact
/// table on the web, where nothing could reject them and nothing could undo it.
@immutable
class SmartPlaylistContext extends PlayContext {
  const SmartPlaylistContext({required this.id, required super.name});

  @override
  final String id;

  @override
  String get kind => 'smart';

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'id': id, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is SmartPlaylistContext && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(kind, id, name);
}

@immutable
class LibraryContext extends PlayContext {
  const LibraryContext({required this.id, required super.name});

  @override
  final String id;

  @override
  String get kind => 'library';

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'id': id, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is LibraryContext && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(kind, id, name);
}

@immutable
class LikedContext extends PlayContext {
  const LikedContext({required super.name});

  @override
  String? get id => null;

  @override
  String get kind => 'liked';

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'name': name};

  @override
  bool operator ==(Object other) => other is LikedContext && other.name == name;

  @override
  int get hashCode => Object.hash(kind, name);
}

@immutable
class SearchContext extends PlayContext {
  const SearchContext({required super.name});

  @override
  String? get id => null;

  @override
  String get kind => 'search';

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is SearchContext && other.name == name;

  @override
  int get hashCode => Object.hash(kind, name);
}

/// An armed sleep timer: a wall-clock deadline, or "stop at the end of the current track".
@immutable
sealed class SleepTimer {
  const SleepTimer();

  static SleepTimer? tryFromJson(Object? raw) {
    final json = objectOrNull(raw);
    if (json == null) return null;
    if (json['kind'] == 'track' && json.length == 1) {
      return const SleepAtTrackEnd();
    }
    if (json['kind'] == 'time') {
      final endsAt = millisOrNull(json['endsAt']);
      if (endsAt != null) return SleepAtTime(endsAt: endsAt);
    }
    return null;
  }

  Map<String, Object?> toJson();
}

/// Stop at a wall-clock deadline, as epoch milliseconds.
@immutable
class SleepAtTime extends SleepTimer {
  const SleepAtTime({required this.endsAt});

  final int endsAt;

  @override
  Map<String, Object?> toJson() => {'kind': 'time', 'endsAt': endsAt};

  @override
  bool operator ==(Object other) =>
      other is SleepAtTime && other.endsAt == endsAt;

  @override
  int get hashCode => endsAt.hashCode;
}

/// Stop when the current track ends.
///
/// Serialised as exactly `{"kind":"track"}` — the web validator counts the keys, so an extra field
/// here would make every peer reject the whole snapshot.
@immutable
class SleepAtTrackEnd extends SleepTimer {
  const SleepAtTrackEnd();

  @override
  Map<String, Object?> toJson() => {'kind': 'track'};

  @override
  bool operator ==(Object other) => other is SleepAtTrackEnd;

  @override
  int get hashCode => 'track'.hashCode;
}

/// What to arm a sleep timer with, as it crosses the wire in a `setSleepTimer` command.
///
/// Null cancels; the two subclasses are the web client's `number | "track"`.
@immutable
sealed class SleepTimerOption {
  const SleepTimerOption();

  static SleepTimerOption? tryFromWire(Object? value) {
    if (value == 'track') return const SleepAfterCurrentTrack();
    final minutes = finiteOrNull(value);
    return minutes == null ? null : SleepAfterMinutes(minutes);
  }

  /// The raw JSON value: a number, or the string `"track"`.
  Object toWire();
}

/// Stop this many minutes from now. Minutes, not milliseconds — the web client multiplies by
/// 60 000 on receipt, so sending milliseconds would arm a timer 60 000 times too long.
@immutable
class SleepAfterMinutes extends SleepTimerOption {
  const SleepAfterMinutes(this.minutes);

  final double minutes;

  @override
  Object toWire() =>
      minutes == minutes.roundToDouble() ? minutes.toInt() : minutes;

  @override
  bool operator ==(Object other) =>
      other is SleepAfterMinutes && other.minutes == minutes;

  @override
  int get hashCode => minutes.hashCode;
}

@immutable
class SleepAfterCurrentTrack extends SleepTimerOption {
  const SleepAfterCurrentTrack();

  @override
  Object toWire() => 'track';

  @override
  bool operator ==(Object other) => other is SleepAfterCurrentTrack;

  @override
  int get hashCode => 'track-option'.hashCode;
}
