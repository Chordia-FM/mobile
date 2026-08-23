import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_net/chordia_net.dart';
import 'package:flutter/foundation.dart';

import 'hub_transport.dart';

/// Why an address could not become a hub.
enum HubProbeFailure {
  /// Not parseable as a web address at all.
  invalidUrl,

  /// Plain HTTP to another machine, in a build that refuses it.
  insecure,

  /// Nothing that looks like a Chordia Hub answered at any candidate address.
  unreachable,
}

class HubProbeException implements Exception {
  const HubProbeException(this.failure, {this.cause});

  final HubProbeFailure failure;

  /// The last transport error, kept for logs — never for the user, who gets the localised
  /// message the failure maps to.
  final Object? cause;

  @override
  String toString() => 'HubProbeException(${failure.name})';
}

/// An address that answered, and what it said about itself.
@immutable
class HubProbeResult {
  const HubProbeResult({required this.url, required this.info});

  /// The API base that actually answered, which is not always what was typed.
  final Uri url;
  final InstanceInfo info;
}

/// Normalises what somebody typed into a base URL.
///
/// People type `chordia.example.com`, paste `https://chordia.example.com/app/`, and occasionally
/// leave a trailing space. All three mean the same server and must produce the same string, or the
/// registry grows duplicates that each hold a separate session.
///
/// A scheme is only prepended when there genuinely is none: testing for `https?://` and prepending
/// otherwise turns `ftp://chordia.dev` into `https://ftp://chordia.dev`, whose host parses as
/// `ftp` — nonsense, offered back to the user as if it were what they meant.
Uri? normalizeHubUrl(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  final hasScheme = RegExp(
    r'^[a-z][a-z0-9+.-]*:',
    caseSensitive: false,
  ).hasMatch(trimmed);
  final parsed = Uri.tryParse(hasScheme ? trimmed : 'https://$trimmed');
  if (parsed == null || !parsed.hasAuthority) return null;
  if (parsed.scheme != 'https' && parsed.scheme != 'http') return null;
  if (parsed.host.isEmpty) return null;
  // Origin only: path, query and fragment are the website's business, never the API base's.
  return Uri(
    scheme: parsed.scheme,
    host: parsed.host,
    port: parsed.hasPort ? parsed.port : null,
  );
}

/// Addresses to try, in order, for an origin somebody typed.
///
/// People know their Chordia by its **website** — `chordia.dev` — while the API conventionally
/// lives at `api.chordia.dev`. Requiring the API host makes the obvious answer the wrong one: the
/// app says "no Chordia server here" about an address where there very plainly is one.
///
/// So the typed origin goes first (somebody who knows the API host is not made to pay for
/// knowing it), then the same host with `api.` in front, then with a leading `api.` removed.
/// Two requests at worst, once, when adding a server.
List<Uri> probeCandidates(Uri origin) {
  final host = origin.host;
  final bare = host.startsWith('api.') ? host.substring(4) : host;
  final alternate = bare == host ? 'api.$host' : bare;
  return [origin, origin.replace(host: alternate)];
}

/// Whether this address sends credentials across a network in clear text.
///
/// Loopback is exempt: it never leaves the device, and it is how a self-hoster tries things out
/// against a hub running on the same machine.
bool isInsecureRemote(Uri url) {
  if (url.scheme != 'http') return false;
  const loopback = {'localhost', '127.0.0.1', '::1', '10.0.2.2'};
  return !loopback.contains(url.host);
}

/// Asks an address whether it is a Chordia Hub, and what it is called.
class HubProbe {
  HubProbe({
    required this.allowInsecureHubs,
    required Future<InstanceInfo> Function(Uri baseUrl) fetch,
  }) : _fetch = fetch;

  /// The plain-HTTP probe over the app's own client, used everywhere but tests.
  factory HubProbe.over(
    PinnedHttpClientFactory factory, {
    required bool allowInsecureHubs,
  }) => HubProbe(
    allowInsecureHubs: allowInsecureHubs,
    fetch: (baseUrl) => withBareHubClient(
      baseUrl,
      factory,
      (hub) => hub.get<InstanceInfo>(
        '/v1/instance',
        (json) => InstanceInfo.fromJson(jsonObject(json)),
        authenticated: false,
      ),
    ),
  );

  /// Whether a plaintext hub may be added at all. False in a release build, so a typo in an
  /// address cannot silently downgrade a real session to cleartext.
  final bool allowInsecureHubs;

  final Future<InstanceInfo> Function(Uri baseUrl) _fetch;

  /// Resolves what somebody typed to a hub, or throws [HubProbeException].
  ///
  /// Sequential rather than parallel: the first candidate is right most of the time, and firing
  /// every guess at somebody's server at once to save a few hundred milliseconds is rude.
  Future<HubProbeResult> probe(String input) async {
    final origin = normalizeHubUrl(input);
    if (origin == null) {
      throw const HubProbeException(HubProbeFailure.invalidUrl);
    }
    if (!allowInsecureHubs && isInsecureRemote(origin)) {
      throw const HubProbeException(HubProbeFailure.insecure);
    }

    Object? lastError;
    for (final candidate in probeCandidates(origin)) {
      try {
        final info = await _fetch(candidate);
        return HubProbeResult(url: candidate, info: info);
      } on Object catch (error) {
        // A 200 in the wrong shape is some other server answering — a proxy, a router's login
        // page — and calling that a Chordia Hub would strand the user on a broken sign-in. The
        // decode throws, and it lands here with every other kind of "no".
        lastError = error;
      }
    }
    throw HubProbeException(HubProbeFailure.unreachable, cause: lastError);
  }
}
