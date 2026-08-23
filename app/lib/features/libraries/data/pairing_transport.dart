import 'dart:convert';
import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_net/chordia_net.dart';

/// What a library server presented when it was asked who it is.
class ServerProbe {
  const ServerProbe({required this.fingerprint, required this.alreadyPaired});

  /// The leaf certificate the server signed itself with, or null when it presented one the system
  /// trust store accepts (a reverse proxy with a real certificate, or plain HTTP on a LAN).
  ///
  /// Non-null means the phone has to be told to trust exactly this certificate before anything is
  /// sent to it — which is the whole reason the wizard has a step that shows a fingerprint.
  final CertFingerprint? fingerprint;

  /// The server already belongs to an account. Pairing it again is not possible: the setup token
  /// is cleared the moment the first pairing succeeds.
  final bool alreadyPaired;
}

/// The two calls the phone makes directly to a library server while pairing.
///
/// An interface because the state machine that drives it is the part worth testing, and because
/// both calls happen over TLS the test environment cannot produce: probing means reading a
/// certificate off a live handshake.
abstract interface class PairingTransport {
  /// Asks the server at [base] who it is, without sending it anything.
  Future<ServerProbe> probe(Uri base);

  /// Hands the server the one-time ticket and the setup token from its own printed link, and
  /// answers with the server id the Hub allocated for it.
  ///
  /// [pin] is the certificate the person confirmed, or null when the server validates normally.
  Future<String> claim({
    required Uri base,
    required CertFingerprint? pin,
    required String ticket,
    required String setupToken,
  });
}

/// A library server reached over the app's own pinned client factory.
///
/// Nothing here opens a socket of its own: every connection comes from the shared factory, which
/// is what keeps "the one place Chordia opens a socket" true even during a handshake that has no
/// pin yet.
class HttpPairingTransport implements PairingTransport {
  const HttpPairingTransport(
    this._factory, {
    this.timeout = const Duration(seconds: 10),
  });

  final PinnedHttpClientFactory _factory;
  final Duration timeout;

  /// A fingerprint no certificate can match, used to LEARN one.
  ///
  /// `pinnedTo` gives its client an empty trust store and routes every certificate through the
  /// comparison, recording what it actually saw when the comparison fails. Pinning to a value that
  /// cannot match therefore turns one refused handshake into the server's real fingerprint —
  /// using only the factory's own API, rather than a second HTTP client with certificate checking
  /// switched off.
  static final _impossible = CertFingerprint.tryParse('0' * 64)!;

  @override
  Future<ServerProbe> probe(Uri base) async {
    final url = base.replace(path: '${base.path}/v1/ping');

    // Plain HTTP has no certificate to pin, and https with a publicly trusted certificate needs
    // no pin either — both answer here and the wizard skips its trust step.
    try {
      final body = await _get(_factory.unpinned(), url);
      return ServerProbe(
        fingerprint: null,
        alreadyPaired: body['paired'] == true,
      );
    } on Object {
      if (base.scheme != 'https') rethrow;
    }

    // Self-signed, almost certainly. Learn which certificate, so the person can be shown it.
    try {
      await _get(_factory.pinnedTo(_impossible), url);
    } on Object {
      final mismatch = _factory.takeLastMismatch();
      if (mismatch == null) rethrow;
      // Read it a second time over the now-known pin, so "already paired" is answered on the same
      // certificate the wizard is about to ask the person to trust.
      final body = await _get(_factory.pinnedTo(mismatch.actual), url);
      return ServerProbe(
        fingerprint: mismatch.actual,
        alreadyPaired: body['paired'] == true,
      );
    }
    // The impossible pin matched, which cannot happen.
    throw StateError('pin probe succeeded against an unmatchable fingerprint');
  }

  @override
  Future<String> claim({
    required Uri base,
    required CertFingerprint? pin,
    required String ticket,
    required String setupToken,
  }) async {
    final client = _factory.pinnedTo(pin);
    try {
      final url = base.replace(path: '${base.path}/v1/pairing/claim');
      final request = await client.postUrl(url).timeout(timeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        // The TICKET, never the session token. A library server is a machine the Hub does not
        // vouch for, and this credential authorises exactly one call on exactly one endpoint.
        ..set(HttpHeaders.authorizationHeader, 'Bearer $ticket')
        ..set('X-Setup-Token', setupToken);
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 400) {
        throw ApiException(
          status: response.statusCode,
          title: response.reasonPhrase,
          method: 'POST',
          path: url.path,
          detail: text.isEmpty ? null : text,
        );
      }
      final decoded = jsonDecode(text);
      final serverId = decoded is Map ? decoded['server_id'] : null;
      if (serverId is! String || serverId.isEmpty) {
        throw ApiException(
          status: response.statusCode,
          title: 'The server paired but did not say which server it is.',
          method: 'POST',
          path: url.path,
        );
      }
      return serverId;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, Object?>> _get(HttpClient client, Uri url) async {
    try {
      final request = await client.getUrl(url).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 400) {
        throw ApiException(
          status: response.statusCode,
          title: response.reasonPhrase,
          method: 'GET',
          path: url.path,
        );
      }
      final decoded = jsonDecode(text);
      return decoded is Map ? decoded.cast<String, Object?>() : const {};
    } finally {
      client.close(force: true);
    }
  }
}

/// The two halves of the link a library server prints at startup.
class SetupLink {
  const SetupLink({required this.base, required this.token});

  /// The server's origin, which every later call is built from.
  final Uri base;

  /// The one-time code at the end of the printed link.
  final String token;

  /// Parses `https://host:8443/setup/TOKEN`, which is what the server prints and what somebody
  /// copies out of a terminal.
  ///
  /// Deliberately strict about the `/setup/` segment: a bare origin is not a setup link, and
  /// accepting one would send a pairing ticket to a server that never asked to be paired.
  static SetupLink? tryParse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;

    final segments = [
      for (final segment in uri.pathSegments)
        if (segment.isNotEmpty) segment,
    ];
    if (segments.length < 2) return null;
    if (segments[segments.length - 2] != 'setup') return null;
    final token = segments.last;
    if (token.isEmpty) return null;

    // Everything before `/setup/` is the server's base path, so a library behind a reverse proxy
    // at `/library` keeps its prefix instead of having its API looked for at the root.
    final prefix = segments.sublist(0, segments.length - 2);
    return SetupLink(
      base: uri.replace(
        path: prefix.isEmpty ? '' : '/${prefix.join('/')}',
        query: null,
        fragment: null,
      ),
      token: token,
    );
  }
}
