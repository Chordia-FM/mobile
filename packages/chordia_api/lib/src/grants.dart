import 'dart:async';

import 'package:chordia_net/chordia_net.dart';
import 'package:meta/meta.dart';

import 'hub.dart';
import 'json.dart';
import 'models.g.dart';

/// A capability token plus the server it authorises, and when it stops working.
@immutable
class Grant {
  const Grant({
    required this.token,
    required this.server,
    required this.expiresAt,
  });

  final String token;
  final ServerEndpoint server;

  /// Epoch milliseconds, like every other timestamp on this API.
  final int expiresAt;

  /// The pin to validate this server's certificate against, or null when it terminates TLS at an
  /// edge proxy and advertised no fingerprint.
  CertFingerprint? get fingerprint =>
      CertFingerprint.tryParse(server.tlsFingerprint);

  Uri get endpoint => Uri.parse(server.endpoint);

  bool usableAt(int now, Duration margin) =>
      expiresAt - now > margin.inMilliseconds;
}

/// Mints and caches capability tokens, one per library.
///
/// **Tokens live five minutes, which is shorter than plenty of tracks.** Rather than watching for
/// expiry mid-playback and swapping the player's URL, everything that fetches audio asks for a
/// grant per request — the audio proxy included. A request that starts inside the window completes
/// on the token it began with, and the next one simply gets a newer token. Expiry stops being an
/// event anything has to handle.
class GrantManager {
  GrantManager({
    required this.hub,
    Duration margin = const Duration(seconds: 5),
    @visibleForTesting int Function()? clock,
  }) : _margin = margin,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final HubClient hub;
  final Duration _margin;
  final int Function() _clock;

  final _cache = <String, Grant>{};
  final _inFlight = <String, Future<Grant>>{};

  /// A usable grant for [libraryId], reusing the cached one while it has [_margin] left.
  Future<Grant> forLibrary(String libraryId) {
    final cached = _cache[libraryId];
    if (cached != null && cached.usableAt(_clock(), _margin)) {
      return Future.value(cached);
    }

    // Playback, artwork and a download can all want the same library at once; minting three tokens
    // for one library wastes a round trip each and races the cache.
    final existing = _inFlight[libraryId];
    if (existing != null) return existing;

    // The body must be a block, not an arrow. `Map.remove` returns the value it removed — this
    // very future — and `whenComplete` awaits a returned Future before completing, so an arrow
    // here makes the future wait on itself and it never resolves.
    final attempt = _mint(libraryId).whenComplete(() {
      _inFlight.remove(libraryId);
    });
    _inFlight[libraryId] = attempt;
    return attempt;
  }

  Future<Grant> _mint(String libraryId) async {
    final response = await hub.post<GrantResponse>(
      '/v1/directory/grant',
      (json) => GrantResponse.fromJson(asObject(json)),
      // Resource and action are omitted deliberately: the Hub defaults to the whole library at
      // stream_read, which is what ordinary playback wants.
      body: GrantRequest(libraryId: libraryId).toJson(),
    );
    final grant = Grant(
      token: response.token,
      server: response.server,
      expiresAt: response.expiresAt,
    );
    _cache[libraryId] = grant;
    return grant;
  }

  /// Drops everything. Called on sign-out: a capability token outlives the session that minted it,
  /// so leaving one cached would let a signed-out app keep streaming.
  void clear() {
    _cache.clear();
    _inFlight.clear();
  }
}
