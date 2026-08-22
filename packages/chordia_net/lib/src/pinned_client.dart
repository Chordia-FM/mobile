import 'dart:io';

import 'package:meta/meta.dart';

import 'fingerprint.dart';

/// Raised when a server presents a certificate whose fingerprint is not the pinned one.
///
/// This is not a transport hiccup and must never be retried away: either the operator replaced the
/// certificate and the directory has not caught up, or something is sitting in the middle.
class CertificatePinMismatch implements Exception {
  const CertificatePinMismatch({
    required this.host,
    required this.port,
    required this.expected,
    required this.actual,
  });

  final String host;
  final int port;
  final CertFingerprint expected;
  final CertFingerprint actual;

  @override
  String toString() =>
      'Certificate for $host:$port does not match the pinned fingerprint. '
      'Expected ${expected.toDisplayString()}, got ${actual.toDisplayString()}.';
}

/// Builds the HTTP clients Chordia is allowed to use.
///
/// Two modes, chosen by whether the directory advertised a fingerprint:
///
/// * **Pinned** — the client is given an *empty* trust store. That is the load-bearing detail: with
///   no roots, chain validation fails for every certificate, publicly trusted ones included, so
///   every connection is routed through the callback and compared against the pin. A client that
///   kept the system roots would quietly accept any CA-signed certificate for the host and the pin
///   would only apply to self-signed ones.
/// * **Unpinned** — ordinary system validation, used for the Hub (a public domain with a real
///   certificate) and for libraries that terminate TLS at an edge proxy and advertise no
///   fingerprint.
class PinnedHttpClientFactory {
  PinnedHttpClientFactory({
    Duration connectionTimeout = const Duration(seconds: 15),
    Duration idleTimeout = const Duration(seconds: 30),
    String? userAgent,
    @visibleForTesting HttpClient Function(SecurityContext?)? clientFactory,
  }) : _connectionTimeout = connectionTimeout,
       _idleTimeout = idleTimeout,
       _userAgent = userAgent,
       _clientFactory = clientFactory ?? _defaultFactory;

  static HttpClient _defaultFactory(SecurityContext? context) =>
      HttpClient(context: context);

  final Duration _connectionTimeout;
  final Duration _idleTimeout;
  final String? _userAgent;
  final HttpClient Function(SecurityContext?) _clientFactory;

  /// A client that validates against the system trust store. For the Hub, and for libraries whose
  /// directory entry carries no fingerprint.
  HttpClient unpinned() => _configure(_clientFactory(null));

  /// A client that accepts exactly one certificate: the one whose DER hashes to [fingerprint].
  ///
  /// Passing null returns [unpinned]; that keeps call sites free of branching, since "no
  /// fingerprint advertised" is a legitimate directory state rather than a missing value.
  HttpClient pinnedTo(CertFingerprint? fingerprint) {
    if (fingerprint == null) return unpinned();

    final client = _clientFactory(SecurityContext(withTrustedRoots: false));
    client.badCertificateCallback = (cert, host, port) {
      final matches = fingerprint.matchesDer(cert.der);
      if (!matches) {
        _lastMismatch = CertificatePinMismatch(
          host: host,
          port: port,
          expected: fingerprint,
          actual: CertFingerprint.ofDer(cert.der),
        );
      }
      return matches;
    };
    return _configure(client);
  }

  HttpClient _configure(HttpClient client) {
    client.connectionTimeout = _connectionTimeout;
    client.idleTimeout = _idleTimeout;
    if (_userAgent != null) client.userAgent = _userAgent;
    return client;
  }

  CertificatePinMismatch? _lastMismatch;

  /// The most recent rejection, if any.
  ///
  /// `badCertificateCallback` can only answer yes or no — a throw from inside it surfaces as an
  /// opaque handshake error — so the reason is recorded here and read by the caller when a request
  /// fails, to turn "connection closed" into a message that names the real problem.
  CertificatePinMismatch? takeLastMismatch() {
    final m = _lastMismatch;
    _lastMismatch = null;
    return m;
  }
}
