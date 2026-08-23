import 'package:audio_service/audio_service.dart';
import 'package:chordia_sync/chordia_sync.dart' hide PlaybackState;
import 'package:meta/meta.dart';

/// The browse tree Android Auto (and any other `MediaBrowserService` client) walks.
///
/// ## Why the ids are strings that describe themselves
///
/// Auto can bind the media service into a process that has never built a widget: the car is
/// connected, the driver taps a playlist, and the whole of `playFromMediaId` runs with no router, no
/// screen and no in-memory catalog. An id that meant "row 3 of the list I showed you earlier" would
/// be meaningless there. So every id carries everything needed to act on it — `playlist:{id}`,
/// `track:{libraryId}:{trackRef}`, `downloads` — and [BrowseId.decode] turns any of them back into a
/// request without consulting state. Auto also persists the last-played id across reboots and hands
/// it back cold, which is the same requirement with a longer gap.
///
/// ## Limits
///
/// Auto is a driving surface, and both the platform and the guidelines are strict about it: the
/// hierarchy stays within [maxDepth] levels (root → section → collection → tracks) and a single
/// list is served in pages of at most [maxPageSize]. Auto asks for a page explicitly through the
/// browse options; when it does not, the first page is what it gets.
class AutoBrowse {
  AutoBrowse({required this.sections, required this.source});

  /// The fixed top level. Supplied by the app because these are the only nodes whose titles are
  /// translated strings rather than catalog data, and this package has no catalogs.
  final List<BrowseNode> sections;

  final AutoBrowseSource source;

  /// Levels below the root, inclusive of it. Auto's guidelines cap browse depth; going deeper turns
  /// a glance into a task.
  static const int maxDepth = 4;

  /// Most items served for one browse request.
  static const int maxPageSize = 100;

  /// The id Android's `MediaBrowserService` starts from.
  static const String rootId = 'root';

  /// `android.media.browse.extra.PAGE`, as `MediaBrowserCompat` spells it in the options bundle.
  static const String pageKey = 'android.media.browse.extra.PAGE';
  static const String pageSizeKey = 'android.media.browse.extra.PAGE_SIZE';

  /// Children of [parentMediaId], as media items.
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    final page = _int(options?[pageKey]) ?? 0;
    final size = (_int(options?[pageSizeKey]) ?? maxPageSize).clamp(
      1,
      maxPageSize,
    );

    if (parentMediaId == rootId) {
      // The root is a fixed, short list; paging it would only ever return an empty second page.
      return page == 0 ? [for (final node in sections) node.toMediaItem()] : [];
    }

    final id = BrowseId.decode(parentMediaId);
    // An id this build does not understand is a stale one Auto kept across an upgrade. An empty
    // list is what the car should see, not a crash inside the media service. A node whose children
    // would sit at level [maxDepth] is refused for the same reason: a song has nothing under it,
    // and the source is not asked.
    if (id == null || id.depth + 1 >= maxDepth) return const [];

    final children = await source.children(
      id,
      offset: page * size,
      limit: size,
    );
    return [for (final node in children) node.toMediaItem()];
  }

  /// One node by id, for a client that has an id but never browsed to it.
  Future<MediaItem?> getMediaItem(String mediaId) async {
    if (mediaId == rootId) return null;
    final id = BrowseId.decode(mediaId);
    if (id == null) return null;
    return (await source.node(id))?.toMediaItem();
  }

  /// What playing [mediaId] means: the tracks, where to start, and what to call the source.
  ///
  /// Null when the id names something that cannot be played, or names content this account can no
  /// longer reach.
  Future<BrowsePlayback?> playback(String mediaId) async {
    final id = BrowseId.decode(mediaId);
    if (id == null) return null;
    return source.playback(id);
  }

  static int? _int(Object? value) => value is int ? value : null;
}

/// Where a browse request's content comes from. Implemented by the app against the Hub and the
/// downloads table; an interface here so the tree's shape can be tested without either.
abstract interface class AutoBrowseSource {
  /// The children of a browsable node, already windowed.
  Future<List<BrowseNode>> children(
    BrowseId parent, {
    required int offset,
    required int limit,
  });

  /// One node's own description.
  Future<BrowseNode?> node(BrowseId id);

  /// The tracks [id] stands for. A single track resolves to its collection where there is one, so
  /// picking a song in the car does not leave a queue of exactly one behind it.
  Future<BrowsePlayback?> playback(BrowseId id);
}

/// A self-describing media id: a kind and its arguments.
///
/// Encoded as `kind:arg:arg`, with every segment percent-escaped, so an argument that itself
/// contains a colon (a library track ref is opaque and may) cannot change the shape of the id it is
/// carried in.
@immutable
class BrowseId {
  const BrowseId(this.kind, [this.args = const []]);

  final String kind;
  final List<String> args;

  /// Which level of the tree this id names: root 0, a section 1, a collection 2, a song 3.
  ///
  /// The level, not the argument count — an id's shape is what places it, and [AutoBrowse.maxDepth]
  /// is enforced against this rather than against how deep the car happened to click.
  int get depth => switch (kind) {
    AutoBrowse.rootId => 0,
    home || library || downloads => 1,
    track => 3,
    _ => 2,
  };

  // The fixed sections.
  static const String home = 'home';
  static const String library = 'library';
  static const String downloads = 'downloads';

  // Collections.
  static const String playlists = 'playlists';
  static const String playlist = 'playlist';
  static const String albums = 'albums';
  static const String album = 'album';
  static const String liked = 'liked';
  static const String mix = 'mix';

  /// A single track, addressed the way the engine addresses it: the library that holds the bytes
  /// and that library's own id for them. Not the Hub catalog id — a cold `playFromMediaId` has to
  /// reach a library server without first asking the Hub what a catalog id resolves to.
  static const String track = 'track';

  static BrowseId section(String kind) => BrowseId(kind);

  static BrowseId of(String kind, String id) => BrowseId(kind, [id]);

  static BrowseId forTrack(PlayerTrack t) =>
      BrowseId(track, [t.libraryId, t.trackRef]);

  String encode() => [
    Uri.encodeComponent(kind),
    for (final arg in args) Uri.encodeComponent(arg),
  ].join(':');

  /// Parses an id, or null when it is not one this build knows how to read.
  static BrowseId? decode(String raw) {
    if (raw.isEmpty) return null;
    final parts = raw.split(':');
    final decoded = <String>[];
    for (final part in parts) {
      try {
        decoded.add(Uri.decodeComponent(part));
      } on ArgumentError {
        // A malformed escape means this is not an id we wrote.
        return null;
      }
    }
    final kind = decoded.removeAt(0);
    if (kind.isEmpty) return null;
    return BrowseId(kind, List.unmodifiable(decoded));
  }

  /// The first argument, or null for a kind that takes none.
  String? get arg => args.isEmpty ? null : args.first;

  @override
  bool operator ==(Object other) =>
      other is BrowseId &&
      other.kind == kind &&
      other.args.length == args.length &&
      _sameArgs(other.args);

  bool _sameArgs(List<String> other) {
    for (var i = 0; i < args.length; i++) {
      if (args[i] != other[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(kind, Object.hashAll(args));

  @override
  String toString() => encode();
}

/// One row in the browse tree.
@immutable
class BrowseNode {
  const BrowseNode({
    required this.id,
    required this.title,
    this.subtitle,
    this.album,
    this.artUri,
    this.duration,
    this.playable = false,
  });

  final BrowseId id;
  final String title;
  final String? subtitle;
  final String? album;

  /// A `file://` URI. Auto fetches artwork with native code that knows nothing of the pinned
  /// client, so a remote URL against a self-hosted server would simply fail to load.
  final Uri? artUri;

  final Duration? duration;

  /// Playable rows are songs; the rest are browsable folders.
  final bool playable;

  MediaItem toMediaItem() => MediaItem(
    id: id.encode(),
    title: title,
    artist: subtitle,
    album: album,
    duration: duration,
    artUri: artUri,
    playable: playable,
  );
}

/// What a play request from the car resolves to.
@immutable
class BrowsePlayback {
  const BrowsePlayback({
    required this.tracks,
    this.startIndex = 0,
    this.context,
  });

  final List<PlayerTrack> tracks;

  /// Where in [tracks] to begin. Picking the fourth song of an album plays the album from there.
  final int startIndex;

  /// What to call the source, so a play recorded from the car reads the same as one from the app.
  final PlayContext? context;
}
