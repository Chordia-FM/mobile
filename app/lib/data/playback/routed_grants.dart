import 'package:chordia_api/chordia_api.dart';

/// A [GrantManager] whose Hub can change underneath it.
///
/// The playback engine is built once, before `runApp`, because Android can start the audio service
/// into a process that has no UI — but the real [GrantManager] is *per Hub*, does not exist until
/// somebody signs in, and is replaced outright when they switch servers or sign out. Something has
/// to bridge those two lifetimes, and this is it: the engine holds this object forever and every
/// token request is routed to whichever manager is current at that moment.
///
/// Routing per call rather than caching the delegate is what makes sign-out safe. `AuthController`
/// clears the live manager's cache the instant a session ends; because nothing here holds a token
/// or a reference of its own, a signed-out app has nothing left to stream with.
class RoutedGrantManager implements GrantManager {
  RoutedGrantManager(this._current);

  /// The manager for the active hub, or null while there is no session to mint tokens against.
  final GrantManager? Function() _current;

  GrantManager get _delegate {
    final manager = _current();
    if (manager == null) {
      throw StateError('No hub session: nothing can mint a capability token.');
    }
    return manager;
  }

  @override
  HubClient get hub => _delegate.hub;

  @override
  Future<Grant> forLibrary(String libraryId) => _delegate.forLibrary(libraryId);

  @override
  void clear() => _current()?.clear();
}
