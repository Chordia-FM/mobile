import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/foundation.dart';

import '../../library/data/optimistic.dart';
import 'playlists_api.dart';

/// The people who may edit one playlist, and every change to that list.
///
/// A `ChangeNotifier` rather than a Riverpod family notifier for the same reason the playlist
/// detail controller is one: the optimistic rules are the part worth testing, and this way a test
/// drives them with a fake [PlaylistsApi] and no container and no widget tree.
///
/// Adding is optimistic even though the Hub is the only thing that can turn a handle into a user.
/// The row that appears is a PLACEHOLDER carrying the typed handle — [isPending] identifies it —
/// and it is replaced by the real profile when the roster is re-read. Waiting for two round trips
/// (invite, then re-read) before the name appears is what makes an invite on a phone feel like it
/// did nothing.
class CollaboratorsController extends ChangeNotifier {
  CollaboratorsController({
    required this.playlistId,
    required PlaylistsApi api,
    required void Function(Object error) onFailure,
    List<PublicUser> initial = const [],
  }) : _api = api,
       _onFailure = onFailure,
       _people = List.of(initial);

  final String playlistId;
  final PlaylistsApi _api;
  final void Function(Object error) _onFailure;

  List<PublicUser> _people;
  bool _loading = false;
  bool _disposed = false;
  Object? _error;

  List<PublicUser> get people => List.unmodifiable(_people);

  bool get loading => _loading;

  /// The last load failure, cleared by a load that succeeds.
  Object? get error => _error;

  /// The id a not-yet-resolved invite carries. Not a valid user id and never sent anywhere: it
  /// exists so the optimistic row has a key, and so the sheet can render it as in-flight.
  static String pendingIdFor(String handle) => 'pending:$handle';

  static bool isPending(PublicUser person) => person.id.startsWith('pending:');

  Future<void> load() async {
    _loading = true;
    _notify();
    try {
      final loaded = await _api.collaborators(playlistId);
      if (_disposed) return;
      _people = loaded;
      _error = null;
    } on Object catch (error) {
      if (_disposed) return;
      // Keep whatever is already on screen: a refetch that fails is a reason to say so, not a
      // reason to blank a roster somebody is looking at.
      _error = error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Invites by handle, with the "@" people type stripped — the Hub takes a bare handle.
  ///
  /// A handle already on the list is a no-op rather than a second row: the Hub treats re-adding an
  /// existing collaborator as success, so an optimistic duplicate would survive until the reload.
  Future<bool> add(String rawHandle) async {
    final handle = rawHandle.trim().replaceFirst(RegExp('^@'), '');
    if (handle.isEmpty) return false;
    if (_people.any((p) => p.handle.toLowerCase() == handle.toLowerCase())) {
      return true;
    }

    final snapshot = List.of(_people);
    final placeholder = PublicUser(
      displayName: '@$handle',
      handle: handle,
      id: pendingIdFor(handle),
    );
    final added = await optimistic(
      apply: () => _apply([..._people, placeholder]),
      revert: () => _apply(snapshot),
      server: () => _api.addCollaborator(playlistId, handle),
      onFailure: _onFailure,
    );
    // Only once the invite stuck: the reload is what turns the placeholder into a real profile,
    // and running it after a failure would re-fetch a list nothing changed.
    if (added) await load();
    return added;
  }

  Future<bool> remove(String userId) {
    final snapshot = List.of(_people);
    return optimistic(
      apply: () => _apply([
        for (final person in _people)
          if (person.id != userId) person,
      ]),
      revert: () => _apply(snapshot),
      server: () => _api.removeCollaborator(playlistId, userId),
      onFailure: _onFailure,
    );
  }

  /// Removes the signed-in user from the playlist.
  ///
  /// The same call as [remove]; the Hub lets a collaborator delete their own membership. Doing it
  /// through the same route rather than a "leave" endpoint is why a collaborator can walk away
  /// from a playlist whose owner is not around to be asked.
  Future<bool> leave() async {
    final String me;
    try {
      me = await _api.myUserId();
    } on Object catch (error) {
      _onFailure(error);
      return false;
    }
    return remove(me);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _apply(List<PublicUser> people) {
    _people = people;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
