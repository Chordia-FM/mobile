import 'dart:async';
import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_db/chordia_db.dart';
import 'package:chordia_player/chordia_player.dart';
import 'package:chordia_sync/chordia_sync.dart';

import '../art/art_cache.dart';

/// Serves the catalog to a car head unit.
///
/// Every method here can be reached from a **cold process**: Android Auto may ask an app that is
/// not running to browse or resume. So this takes plain functions rather than reading a widget
/// tree, and each call tolerates having no Hub at all — a phone in a car with no signal still has
/// its downloads, and showing those beats showing an error.
class HubAutoBrowseSource implements AutoBrowseSource {
  HubAutoBrowseSource({
    required this.hub,
    required this.downloads,
    required this.artFile,
    required this.labels,
  });

  /// The Hub, or null when nobody is signed in. Null means only downloads can be served.
  final HubClient? Function() hub;
  final DownloadsDao downloads;

  /// Local artwork for a content hash, or null. Auto fetches art natively and cannot use the
  /// pinned client, so anything not already on disk is simply not shown.
  final Future<File?> Function(String sha256, int width) artFile;

  /// Translated titles for the fixed nodes. The player package has no catalogs of its own.
  final AutoBrowseLabels labels;

  static const _artWidth = 256;

  @override
  Future<List<BrowseNode>> children(
    BrowseId parent, {
    required int offset,
    required int limit,
  }) async {
    switch (parent.kind) {
      case BrowseId.home:
        return _home(offset: offset, limit: limit);
      case BrowseId.library:
        return [
          BrowseNode(
            id: BrowseId.section(BrowseId.playlists),
            title: labels.playlists,
          ),
          BrowseNode(id: const BrowseId(BrowseId.liked), title: labels.liked),
          BrowseNode(
            id: BrowseId.section(BrowseId.albums),
            title: labels.recentlyAdded,
          ),
        ];
      case BrowseId.downloads:
        return _downloadRows(offset: offset, limit: limit);
      case BrowseId.playlists:
        return _playlists(offset: offset, limit: limit);
      case BrowseId.playlist:
        return _playlistTracks(parent.args.first, offset: offset, limit: limit);
      case BrowseId.liked:
        return _liked(offset: offset, limit: limit);
      case BrowseId.albums:
        return _albums(offset: offset, limit: limit);
      case BrowseId.album:
        return _albumTracks(parent.args.first, offset: offset, limit: limit);
      case BrowseId.mix:
        return _mix(parent.args.first, offset: offset, limit: limit);
      default:
        return const [];
    }
  }

  @override
  Future<BrowseNode?> node(BrowseId id) async {
    switch (id.kind) {
      case BrowseId.home:
        return BrowseNode(id: id, title: labels.home);
      case BrowseId.library:
        return BrowseNode(id: id, title: labels.library);
      case BrowseId.downloads:
        return BrowseNode(id: id, title: labels.downloads);
      case BrowseId.track:
        final row = await downloads.byTrack(id.args.last);
        return row == null ? null : _nodeForDownload(row);
      default:
        return BrowseNode(id: id, title: labels.library);
    }
  }

  @override
  Future<BrowsePlayback?> playback(BrowseId id) async {
    switch (id.kind) {
      case BrowseId.downloads:
        final rows = await downloads.all();
        return BrowsePlayback(
          tracks: [for (final row in rows) _trackForDownload(row)],
          context: LibraryContext(id: 'downloads', name: labels.downloads),
        );

      case BrowseId.track:
        // A song picked in the car plays with its album behind it, so the queue does not end after
        // one track. Falls back to the song alone when its collection cannot be resolved.
        final row = await downloads.byTrack(id.args.last);
        if (row != null) {
          final albumId = row.albumId;
          if (albumId != null) {
            final siblings = await downloads.byAlbum(albumId);
            final index = siblings.indexWhere((t) => t.trackId == row.trackId);
            if (index >= 0) {
              return BrowsePlayback(
                tracks: [for (final t in siblings) _trackForDownload(t)],
                startIndex: index,
                context: AlbumContext(
                  id: albumId,
                  name: row.album ?? row.title,
                ),
              );
            }
          }
          return BrowsePlayback(tracks: [_trackForDownload(row)]);
        }
        return _streamedTrack(id);

      case BrowseId.playlist:
        final client = hub();
        if (client == null) return null;
        final detail = await client.playlist(id.args.first);
        return BrowsePlayback(
          tracks: [for (final t in detail.tracks) _trackForBrowse(t)],
          context: PlaylistContext(id: detail.id, name: detail.name),
        );

      case BrowseId.album:
        final client = hub();
        if (client == null) return null;
        final tracks = await client.albumTracks(id.args.first);
        return BrowsePlayback(
          tracks: [for (final t in tracks) _trackForBrowse(t)],
          context: AlbumContext(id: id.args.first, name: labels.recentlyAdded),
        );

      case BrowseId.liked:
        final client = hub();
        if (client == null) return null;
        final tracks = await client.likedTracks();
        return BrowsePlayback(
          tracks: [for (final t in tracks) _trackForBrowse(t)],
          context: LikedContext(name: labels.liked),
        );

      default:
        return null;
    }
  }

  // ── sections ────────────────────────────────────────────────────────────────────────────────

  Future<List<BrowseNode>> _home({
    required int offset,
    required int limit,
  }) async {
    final client = hub();
    if (client == null) return const [];
    try {
      final mixes = await client.dailyMixes(limit: limit);
      return [
        for (final mix in mixes.skip(offset).take(limit))
          BrowseNode(
            id: BrowseId.of(BrowseId.mix, mix.seedArtistId),
            title: mix.title,
            subtitle: mix.subtitle,
            artUri: await _art(mix.imageUrl),
          ),
      ];
    } on ApiException {
      // A car with no signal gets an empty shelf rather than a failure it cannot act on.
      return const [];
    }
  }

  Future<List<BrowseNode>> _playlists({
    required int offset,
    required int limit,
  }) async {
    final client = hub();
    if (client == null) return const [];
    try {
      final playlists = await client.playlists();
      return [
        for (final p in playlists.skip(offset).take(limit))
          BrowseNode(
            id: BrowseId.of(BrowseId.playlist, p.id),
            title: p.name,
            artUri: await _art(p.coverUrl),
          ),
      ];
    } on ApiException {
      return const [];
    }
  }

  Future<List<BrowseNode>> _playlistTracks(
    String playlistId, {
    required int offset,
    required int limit,
  }) async {
    final client = hub();
    if (client == null) return const [];
    try {
      final detail = await client.playlist(playlistId);
      return _rows([
        for (final t in detail.tracks.skip(offset).take(limit))
          _trackForBrowse(t),
      ]);
    } on ApiException {
      return const [];
    }
  }

  Future<List<BrowseNode>> _albums({
    required int offset,
    required int limit,
  }) async {
    final client = hub();
    if (client == null) return const [];
    try {
      // There is no flat "every album" endpoint, and a car does not want one — the useful shelf is
      // what arrived recently.
      final albums = await client.recentlyAdded(limit: offset + limit);
      return [
        for (final a in albums.skip(offset).take(limit))
          BrowseNode(
            id: BrowseId.of(BrowseId.album, a.id),
            title: a.title,
            subtitle: a.artist,
            artUri: await _art(a.coverUrl),
          ),
      ];
    } on ApiException {
      return const [];
    }
  }

  Future<List<BrowseNode>> _albumTracks(
    String albumId, {
    required int offset,
    required int limit,
  }) async {
    final client = hub();
    if (client == null) return const [];
    try {
      final tracks = await client.albumTracks(albumId);
      return _rows([
        for (final t in tracks.skip(offset).take(limit)) _trackForBrowse(t),
      ]);
    } on ApiException {
      return const [];
    }
  }

  Future<List<BrowseNode>> _liked({
    required int offset,
    required int limit,
  }) async {
    final client = hub();
    if (client == null) return const [];
    try {
      final tracks = await client.likedTracks();
      return _rows([
        for (final t in tracks.skip(offset).take(limit)) _trackForBrowse(t),
      ]);
    } on ApiException {
      return const [];
    }
  }

  Future<List<BrowseNode>> _mix(
    String mixId, {
    required int offset,
    required int limit,
  }) async {
    final client = hub();
    if (client == null) return const [];
    try {
      final detail = await client.dailyMix(mixId);
      return _rows([
        for (final t in detail.tracks.skip(offset).take(limit))
          _trackForBrowse(t),
      ]);
    } on ApiException {
      return const [];
    }
  }

  Future<List<BrowseNode>> _downloadRows({
    required int offset,
    required int limit,
  }) async {
    final rows = await downloads.all();
    return [
      for (final row in rows.skip(offset).take(limit))
        await _nodeForDownload(row),
    ];
  }

  // ── conversions ─────────────────────────────────────────────────────────────────────────────

  Future<List<BrowseNode>> _rows(List<PlayerTrack> tracks) async => [
    for (final track in tracks)
      BrowseNode(
        id: BrowseId(BrowseId.track, [track.libraryId, track.trackRef]),
        title: track.title,
        subtitle: track.artist,
        album: track.album,
        duration: Duration(milliseconds: track.durationMs),
        artUri: await _art(track.coverUrl),
        playable: true,
      ),
  ];

  Future<BrowseNode> _nodeForDownload(DownloadedTrack row) async => BrowseNode(
    id: BrowseId(BrowseId.track, [row.libraryId, row.trackRef]),
    title: row.title,
    subtitle: row.artist,
    album: row.album,
    duration: Duration(milliseconds: row.durationMs),
    artUri: await _artFromHash(row.coverSha),
    playable: true,
  );

  PlayerTrack _trackForDownload(DownloadedTrack row) => PlayerTrack(
    id: row.trackId,
    title: row.title,
    artist: row.artist,
    album: row.album,
    durationMs: row.durationMs,
    libraryId: row.libraryId,
    trackRef: row.trackRef,
    contentHash: row.contentHash,
  );

  PlayerTrack _trackForBrowse(BrowseTrack t) => PlayerTrack(
    id: t.id,
    title: t.title,
    artist: t.artist,
    album: t.album,
    albumId: t.albumId,
    durationMs: t.durationMs,
    libraryId: t.libraryId,
    trackRef: t.trackRef,
    contentHash: t.contentHash,
    coverUrl: t.coverUrl,
  );

  /// Resolves a streamed track that is not downloaded, by asking the library that holds it.
  Future<BrowsePlayback?> _streamedTrack(BrowseId id) async {
    if (id.args.length < 2) return null;
    final client = hub();
    if (client == null) return null;
    try {
      final track = await client.track(id.args.last);
      return BrowsePlayback(tracks: [_trackForBrowse(track)]);
    } on ApiException {
      return null;
    }
  }

  Future<Uri?> _art(String? coverUrl) => _artFromHash(artHashOf(coverUrl));

  Future<Uri?> _artFromHash(String? sha256) async {
    if (sha256 == null || sha256.isEmpty) return null;
    final file = await artFile(sha256, _artWidth);
    return file == null ? null : Uri.file(file.path);
  }
}

/// Translated titles for the tree's fixed nodes.
class AutoBrowseLabels {
  const AutoBrowseLabels({
    required this.home,
    required this.library,
    required this.downloads,
    required this.playlists,
    required this.liked,
    required this.recentlyAdded,
  });

  final String home;
  final String library;
  final String downloads;
  final String playlists;
  final String liked;
  final String recentlyAdded;
}
