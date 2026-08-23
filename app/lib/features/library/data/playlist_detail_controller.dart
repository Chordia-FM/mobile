import 'dart:math' as math;

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/foundation.dart';

import 'library_api.dart';
import 'optimistic.dart';
import 'reorder.dart';

/// One playlist's loaded state and every edit that can be made to it.
///
/// A `ChangeNotifier` rather than a Riverpod family notifier because the edits here are the part
/// worth testing, and this way a test drives them with a fake [PlaylistApi] and no container,
/// no widget tree and no network. The screen owns an instance for as long as it is on screen.
///
/// Every mutation is optimistic: the local copy changes first, the server is told, and a refusal
/// puts the previous copy back and reports it through [onFailure]. Waiting for a round trip
/// before redrawing is what makes an edit on a phone feel broken.
class PlaylistDetailController extends ChangeNotifier {
  PlaylistDetailController({
    required this.playlistId,
    required PlaylistApi api,
    required void Function(Object error) onFailure,
  }) : _api = api,
       _onFailure = onFailure;

  final String playlistId;
  final PlaylistApi _api;
  final void Function(Object error) _onFailure;

  PlaylistDetail? _detail;
  Object? _error;
  bool _loading = true;
  bool _disposed = false;

  PlaylistDetail? get detail => _detail;

  /// The load failure, or null. Cleared the moment a load succeeds, so a transient failure during
  /// a background refresh cannot replace a playlist that is already on screen.
  Object? get error => _error;

  bool get loading => _loading;

  Future<void> load() async {
    _loading = true;
    _notify();
    try {
      final loaded = await _api.detail(playlistId);
      if (_disposed) return;
      _detail = loaded;
      _error = null;
    } on Object catch (error) {
      if (_disposed) return;
      // Keep whatever is already rendered. A refetch that fails is a reason to say so, not a
      // reason to throw away a playlist the user is looking at.
      _error = error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Moves one track, by drag or by menu. Indices are positions in the VIEWER-FILTERED list, which
  /// is what the server's permute-in-place semantics make safe to send whole — see [moveItem].
  Future<bool> moveTrack(int from, int to) {
    final snapshot = _detail;
    if (snapshot == null) return Future.value(false);
    if (from == to ||
        from < 0 ||
        to < 0 ||
        from >= snapshot.tracks.length ||
        to >= snapshot.tracks.length) {
      return Future.value(false);
    }
    final moved = moveItem(snapshot.tracks, from, to);
    final ids = [for (final track in moved) track.id];
    return optimistic(
      apply: () => _apply(snapshot.copyWithTracks(moved)),
      revert: () => _apply(snapshot),
      server: () => _api.reorderTracks(playlistId, ids),
      onFailure: _onFailure,
    );
  }

  Future<bool> removeTrack(BrowseTrack track) {
    final snapshot = _detail;
    if (snapshot == null) return Future.value(false);
    final remaining = [
      for (final other in snapshot.tracks)
        if (other.id != track.id) other,
    ];
    return optimistic(
      // The count and the runtime move with the rows, so the header can never contradict the list
      // during the round trip.
      apply: () => _apply(
        snapshot.copyWithTracks(
          remaining,
          trackCount: _clampCount(snapshot, -1),
          totalDurationMs: _clampDuration(snapshot, -track.durationMs),
        ),
      ),
      revert: () => _apply(snapshot),
      server: () => _api.removeTrack(playlistId, track.id),
      onFailure: _onFailure,
    );
  }

  Future<bool> rename(String name) => _patch(
    (detail) => detail.copyWithDetails(name: name),
    PlaylistPatch(name: name),
  );

  /// Sets or clears the description. An empty string is a clear, which the Hub needs told
  /// explicitly — an omitted field means "leave alone", not "erase".
  Future<bool> setDescription(String description) {
    final trimmed = description.trim();
    final clearing = trimmed.isEmpty;
    return _patch(
      (detail) => detail.copyWithDetails(
        description: clearing ? null : trimmed,
        clearDescription: clearing,
      ),
      clearing
          ? const PlaylistPatch(clearDescription: true)
          : PlaylistPatch(description: trimmed),
    );
  }

  Future<bool> setVisibility(PlaylistVisibility visibility) => _patch(
    (detail) => detail.copyWithDetails(visibility: visibility),
    PlaylistPatch(visibility: visibility),
  );

  /// Chooses one of the covers already in the playlist as its face.
  Future<bool> setCover(String coverUrl) {
    final snapshot = _detail;
    if (snapshot == null) return Future.value(false);
    final hash = _hashOf(coverUrl);
    if (hash == null) return Future.value(false);
    return optimistic(
      apply: () => _apply(snapshot.copyWithDetails(coverUrl: coverUrl)),
      revert: () => _apply(snapshot),
      server: () => _api.setCover(playlistId, hash),
      onFailure: _onFailure,
    );
  }

  Future<bool> clearCover() {
    final snapshot = _detail;
    if (snapshot == null) return Future.value(false);
    return optimistic(
      apply: () => _apply(snapshot.copyWithDetails(clearCover: true)),
      revert: () => _apply(snapshot),
      server: () => _api.clearCover(playlistId),
      onFailure: _onFailure,
    );
  }

  /// Invites a collaborator. Not optimistic: the Hub resolves a handle to a user, and this client
  /// has no profile to insert until it answers — so the list is refreshed instead of guessed at.
  Future<bool> addCollaborator(String handle) async {
    try {
      await _api.addCollaborator(playlistId, handle);
    } on Object catch (error) {
      _onFailure(error);
      return false;
    }
    await load();
    return true;
  }

  Future<bool> removeCollaborator(String userId) {
    final snapshot = _detail;
    if (snapshot == null) return Future.value(false);
    return optimistic(
      apply: () => _apply(
        snapshot.copyWithCollaborators([
          for (final person in snapshot.collaborators ?? const <PublicUser>[])
            if (person.id != userId) person,
        ]),
      ),
      revert: () => _apply(snapshot),
      server: () => _api.removeCollaborator(playlistId, userId),
      onFailure: _onFailure,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<bool> _patch(
    PlaylistDetail Function(PlaylistDetail detail) apply,
    PlaylistPatch changes,
  ) {
    final snapshot = _detail;
    if (snapshot == null) return Future.value(false);
    return optimistic(
      apply: () => _apply(apply(snapshot)),
      revert: () => _apply(snapshot),
      server: () => _api.update(playlistId, changes),
      onFailure: _onFailure,
    );
  }

  void _apply(PlaylistDetail detail) {
    _detail = detail;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Null stays null: a Hub deployed before these fields existed sends neither, and inventing a
  /// count from the viewer-filtered rows would print a number the playlist does not have.
  static int? _clampCount(PlaylistDetail detail, int delta) {
    final count = detail.trackCount;
    return count == null ? null : math.max(0, count + delta);
  }

  static int? _clampDuration(PlaylistDetail detail, int deltaMs) {
    final total = detail.totalDurationMs;
    return total == null ? null : math.max(0, total + deltaMs);
  }

  /// The content hash inside a `/v1/images/{hash}` reference. The cover endpoint takes the hash,
  /// while the DTOs carry whole paths — sometimes with the web client's `?w=` on the end.
  static String? _hashOf(String coverUrl) {
    final segments = Uri.tryParse(coverUrl)?.pathSegments;
    if (segments == null || segments.length < 2) return null;
    return segments[segments.length - 2] == 'images' ? segments.last : null;
  }
}

/// The two rewrites the controller needs, spelled out rather than reached for through a generated
/// `copyWith` the contract bindings do not carry.
extension on PlaylistDetail {
  PlaylistDetail copyWithTracks(
    List<BrowseTrack> tracks, {
    int? trackCount,
    int? totalDurationMs,
  }) => PlaylistDetail(
    id: id,
    name: name,
    owner: owner,
    tracks: tracks,
    autoCoverUrls: autoCoverUrls,
    canEdit: canEdit,
    collaborators: collaborators,
    coverUrl: coverUrl,
    description: description,
    owned: owned,
    totalDurationMs: totalDurationMs ?? this.totalDurationMs,
    trackCount: trackCount ?? this.trackCount,
    visibility: visibility,
  );

  PlaylistDetail copyWithDetails({
    String? name,
    String? description,
    bool clearDescription = false,
    String? coverUrl,
    bool clearCover = false,
    PlaylistVisibility? visibility,
  }) => PlaylistDetail(
    id: id,
    name: name ?? this.name,
    owner: owner,
    tracks: tracks,
    autoCoverUrls: autoCoverUrls,
    canEdit: canEdit,
    collaborators: collaborators,
    coverUrl: clearCover ? null : (coverUrl ?? this.coverUrl),
    description: clearDescription ? null : (description ?? this.description),
    owned: owned,
    totalDurationMs: totalDurationMs,
    trackCount: trackCount,
    visibility: visibility ?? this.visibility,
  );

  PlaylistDetail copyWithCollaborators(List<PublicUser> collaborators) =>
      PlaylistDetail(
        id: id,
        name: name,
        owner: owner,
        tracks: tracks,
        autoCoverUrls: autoCoverUrls,
        canEdit: canEdit,
        collaborators: collaborators,
        coverUrl: coverUrl,
        description: description,
        owned: owned,
        totalDurationMs: totalDurationMs,
        trackCount: trackCount,
        visibility: visibility,
      );
}
