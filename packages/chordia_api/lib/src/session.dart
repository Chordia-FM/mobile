import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

import 'errors.dart';

/// A signed-in session for one hub.
@immutable
class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;

  /// Epoch **milliseconds**. See [expiryOf] for why this is not seconds.
  final int expiresAt;

  bool expiresWithin(Duration d, {required int now}) =>
      expiresAt - now <= d.inMilliseconds;

  Session copyWith({
    String? accessToken,
    String? refreshToken,
    int? expiresAt,
  }) => Session(
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    expiresAt: expiresAt ?? this.expiresAt,
  );

  Map<String, Object?> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt,
  };

  static Session? fromJson(Map<String, Object?> json) {
    final access = json['access_token'];
    final refresh = json['refresh_token'];
    final expires = json['expires_at'];
    if (access is! String || refresh is! String || expires is! int) return null;
    return Session(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: expires,
    );
  }
}

/// Reads `exp` out of an access token.
///
/// **Chordia's `exp` is epoch MILLISECONDS, not seconds.** The Hub disables JWT expiry validation
/// and checks it by hand for exactly this reason. Any Dart JWT package will read it as seconds and
/// place expiry roughly fifty thousand years out, so the token never looks stale and the client
/// never refreshes — until the server starts rejecting every request at the one-hour mark. Hence
/// this hand-rolled decode rather than a dependency.
int? expiryOf(String jwt) {
  final parts = jwt.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final claims = jsonDecode(payload);
    if (claims is! Map) return null;
    final exp = claims['exp'];
    return exp is int ? exp : null;
  } on Object {
    return null;
  }
}

/// Where sessions are kept. Implemented in the app over the platform keystore; a plain in-memory
/// version stands in for tests.
abstract interface class SessionStore {
  Future<Session?> read(String hubId);
  Future<void> write(String hubId, Session session);
  Future<void> clear(String hubId);
}

/// In-memory sessions, for tests.
class MemorySessionStore implements SessionStore {
  final _sessions = <String, Session>{};

  @override
  Future<Session?> read(String hubId) async => _sessions[hubId];

  @override
  Future<void> write(String hubId, Session session) async =>
      _sessions[hubId] = session;

  @override
  Future<void> clear(String hubId) async => _sessions.remove(hubId);
}

/// Holds the live session for one hub and keeps its access token fresh.
///
/// Refresh tokens rotate and are single-use: the Hub invalidates the old one the moment it issues a
/// replacement. So two concurrent refreshes are not merely wasteful, they are a bug — the loser
/// presents a token the server has already retired and the session dies. Every caller therefore
/// awaits the *same* in-flight refresh.
class SessionManager {
  SessionManager({
    required this.hubId,
    required this.store,
    required Future<Session> Function(String refreshToken) refresher,
    Duration refreshSkew = const Duration(minutes: 1),
    @visibleForTesting int Function()? clock,
  }) : _refresher = refresher,
       _refreshSkew = refreshSkew,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final String hubId;
  final SessionStore store;
  final Future<Session> Function(String refreshToken) _refresher;
  final Duration _refreshSkew;
  final int Function() _clock;

  Session? _session;
  Future<Session?>? _inFlight;

  /// The last refresh that failed for want of a network, kept so the UI can say the server is
  /// unreachable rather than silently showing stale state.
  ApiException? _lastRefreshFailure;

  /// Set when the most recent refresh could not reach the server. Cleared by a successful one.
  ApiException? get lastRefreshFailure => _lastRefreshFailure;

  /// True when there is a session whose access token could not be renewed because the server was
  /// unreachable — signed in, but currently unable to talk to the Hub.
  bool get isOffline => _session != null && _lastRefreshFailure != null;

  /// Emits on sign-out, whether the user asked or a refresh failed terminally.
  final _signedOut = StreamController<void>.broadcast();
  Stream<void> get onSignedOut => _signedOut.stream;

  Session? get current => _session;
  bool get isSignedIn => _session != null;

  Future<void> load() async {
    _session = await store.read(hubId);
  }

  Future<void> adopt(Session session) async {
    _session = session;
    await store.write(hubId, session);
  }

  Future<void> signOut() async {
    _session = null;
    await store.clear(hubId);
    _signedOut.add(null);
  }

  /// Returns a token good for the next [_refreshSkew], refreshing once if needed.
  Future<String?> freshAccessToken() async {
    final session = _session;
    if (session == null) return null;
    if (!session.expiresWithin(_refreshSkew, now: _clock())) {
      return session.accessToken;
    }
    final refreshed = await _refreshOnce();
    return refreshed?.accessToken;
  }

  /// Forces a refresh, used after a 401 on a token that still looked valid — a session revoked on
  /// another device, or a clock that disagrees with the server's.
  Future<Session?> forceRefresh() => _refreshOnce();

  Future<Session?> _refreshOnce() {
    final existing = _inFlight;
    if (existing != null) return existing;

    final session = _session;
    if (session == null) return Future.value();

    final attempt = _refresher(session.refreshToken)
        .then<Session?>((next) async {
          _lastRefreshFailure = null;
          await adopt(next);
          return next;
        })
        .catchError((Object error) async {
          // Only an answer from the server ends a session. A refresh token is rejected when it is
          // gone for good — expired, revoked, already spent — and retrying cannot help, so the
          // session is cleared rather than left insisting it is valid.
          //
          // A request that never reached the server says nothing about the token. Signing out
          // there would mean opening the app on a plane logs you out and takes your downloaded
          // music with it, which is the opposite of what an offline-capable client should do: the
          // session is kept and the next attempt retries.
          if (error is ApiException && error.isNetworkFailure) {
            _lastRefreshFailure = error;
            return null;
          }
          await signOut();
          return null;
        })
        // A block, not an arrow: `whenComplete` awaits a Future the callback returns, and an
        // assignment expression here evaluates to the value assigned.
        .whenComplete(() {
          _inFlight = null;
        });

    _inFlight = attempt;
    return attempt;
  }

  void dispose() => _signedOut.close();
}
