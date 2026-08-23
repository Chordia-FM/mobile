import 'dart:convert';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:chordia_api/chordia_api.dart';
import 'package:crypto/crypto.dart';

import 'secret_store.dart';

/// Redeems a one-time code, given the verifier it was bound to.
///
/// A function rather than the whole `AuthRepository`, so this flow's only dependency on the
/// network is the one call it actually makes — and so it can be exercised without one.
typedef DesktopExchange =
    Future<AuthResponse> Function({
      required String code,
      required String verifier,
    });

/// Deep links the operating system delivers to this app.
///
/// An interface so the flow can be exercised without a method channel — and because the two ways
/// a link arrives (the one that launched the app, and the ones that arrive while it runs) are the
/// whole difficulty here and deserve to be named.
abstract interface class DeepLinkSource {
  /// The link the app was launched with, if it was. Null on an ordinary launch.
  Future<Uri?> initialLink();

  /// Links delivered while the app is already running.
  Stream<Uri> links();
}

/// The real source, over the `app_links` plugin.
class AppLinksDeepLinkSource implements DeepLinkSource {
  AppLinksDeepLinkSource([AppLinks? links]) : _links = links ?? AppLinks();

  final AppLinks _links;

  @override
  Future<Uri?> initialLink() => _links.getInitialLink();

  @override
  Stream<Uri> links() => _links.uriLinkStream;
}

/// Why a browser handoff did not finish.
enum BrowserHandoffFailure {
  /// This hub never told us where its website is, so there is nowhere to send the browser.
  noFrontend,

  /// No browser took the URL. Rare, but a device with every browser disabled is a real state.
  cannotOpenBrowser,

  /// The one-time code was unknown, already spent, or past its sixty seconds. Retryable: start
  /// the flow again and a fresh code is minted.
  expired,

  /// The exchange failed for some other reason.
  failed,
}

class BrowserHandoffException implements Exception {
  const BrowserHandoffException(this.failure, {this.cause});

  final BrowserHandoffFailure failure;
  final Object? cause;

  @override
  String toString() => 'BrowserHandoffException(${failure.name})';
}

/// Signing in by handing the session the system browser already has to the app.
///
/// The app and the browser cannot see each other's storage, so rather than making somebody sign in
/// a second time to a service they are already signed in to, the app opens the Hub's website at
/// `/auth/desktop`, which mints a one-time code for whoever that browser is and sends it back over
/// `chordia://auth/callback`. Every sign-in method the website supports — Discord, a second
/// factor, whatever gets added later — comes along for free, and this app knows about none of them.
///
/// **The verifier is what makes an intercepted code worthless.** A high-entropy secret is invented
/// here, only its SHA-256 travels to the Hub as the `challenge`, and the code is bound to that
/// hash. Something that steals the deep link holds a code it cannot redeem. So the verifier never
/// leaves the device — not in the URL, not in a log, not to the Hub. It is written to the keystore
/// for exactly as long as the flow is open, because on Android the browser hop can *relaunch* the
/// app: a verifier held only in memory would be gone at the moment the code came back.
class BrowserHandoff {
  BrowserHandoff({
    required DesktopExchange exchange,
    required SecretStore secrets,
    required DeepLinkSource links,
    required Future<bool> Function(Uri url) launcher,
    required this.hubId,
    Random? entropy,
    int Function()? clock,
  }) : _exchange = exchange,
       _secrets = secrets,
       _links = links,
       _launcher = launcher,
       _entropy = entropy ?? Random.secure(),
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// The scheme the OS routes back to this app. Also sent to the website as `scheme=`, which
  /// checks it against its own allowlist before it will redirect anywhere.
  static const callbackScheme = 'chordia';

  /// A pending verifier older than this is abandoned rather than used. The code it pairs with
  /// lives sixty seconds, so anything this old belongs to a flow the user walked away from.
  static const pendingLifetime = Duration(minutes: 10);

  final String hubId;
  final DesktopExchange _exchange;
  final SecretStore _secrets;
  final DeepLinkSource _links;
  final Future<bool> Function(Uri url) _launcher;
  final Random _entropy;
  final int Function() _clock;

  String get _pendingKey => 'chordia_pkce::$hubId';

  /// A fresh verifier: 256 bits, base64url, unpadded.
  static String newVerifier(Random entropy) {
    final bytes = List<int>.generate(32, (_) => entropy.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// The challenge for a verifier: lowercase hex SHA-256 of its UTF-8 bytes, which is what the
  /// Hub recomputes and compares.
  static String challengeFor(String verifier) =>
      sha256.convert(utf8.encode(verifier)).toString();

  /// The website page that mints the code, on this hub's own frontend.
  static Uri authorizeUrl({
    required Uri frontendUrl,
    required String challenge,
  }) {
    final base = frontendUrl.path.endsWith('/')
        ? frontendUrl.path.substring(0, frontendUrl.path.length - 1)
        : frontendUrl.path;
    return frontendUrl.replace(
      path: '$base/auth/desktop',
      queryParameters: {'challenge': challenge, 'scheme': callbackScheme},
    );
  }

  /// The code carried by a `chordia://auth/callback?code=…` link, or null for any other link.
  ///
  /// Checked structurally rather than by prefix match: a link is the one thing here that arrives
  /// from outside the app, and `chordia://auth/callback.evil.example/…` must not read as ours.
  static String? codeOf(Uri link) {
    if (link.scheme != callbackScheme) return null;
    if (link.host != 'auth' || link.path != '/callback') return null;
    final code = link.queryParameters['code'];
    return code == null || code.isEmpty ? null : code;
  }

  /// Every callback link, whether it launched the app or arrived while it ran.
  ///
  /// Both paths are real and neither is optional: on iOS the scheme reaches the running app, while
  /// on Android the app may have been evicted and is started fresh by the link. Duplicates are
  /// dropped because some platforms replay the launch link onto the live stream as well.
  Stream<Uri> callbacks() async* {
    Uri? seen;
    final initial = await _links.initialLink();
    if (initial != null && codeOf(initial) != null) {
      seen = initial;
      yield initial;
    }
    await for (final link in _links.links()) {
      if (codeOf(link) == null || link == seen) continue;
      seen = link;
      yield link;
    }
  }

  /// Invents a verifier, remembers it, and sends the browser to the website.
  ///
  /// Returns once the browser is open. The code comes back through [callbacks].
  Future<void> start({required Uri? frontendUrl}) async {
    if (frontendUrl == null || !frontendUrl.hasAuthority) {
      throw const BrowserHandoffException(BrowserHandoffFailure.noFrontend);
    }
    final verifier = newVerifier(_entropy);
    await _secrets.write(
      _pendingKey,
      jsonEncode({'verifier': verifier, 'created_at': _clock()}),
    );
    final opened = await _launcher(
      authorizeUrl(frontendUrl: frontendUrl, challenge: challengeFor(verifier)),
    );
    if (!opened) {
      await _secrets.delete(_pendingKey);
      throw const BrowserHandoffException(
        BrowserHandoffFailure.cannotOpenBrowser,
      );
    }
  }

  /// Redeems a callback link, returning the session it bought.
  ///
  /// Null means this link is not ours to act on — no flow was open, or the one that was has aged
  /// out. That is not an error: a stale link can be delivered to a freshly launched app, and
  /// showing a failure for it would be a failure the user cannot act on.
  Future<AuthResponse?> complete(Uri link) async {
    final code = codeOf(link);
    if (code == null) return null;
    final verifier = await _takePending();
    if (verifier == null) return null;
    try {
      return await _exchange(code: code, verifier: verifier);
    } on ApiException catch (error) {
      // The Hub answers 401 for unknown, expired, replayed and mismatched alike — deliberately,
      // so a caller cannot probe which. All four mean "start again", which is what expiry means.
      throw BrowserHandoffException(
        error.isUnauthorized
            ? BrowserHandoffFailure.expired
            : BrowserHandoffFailure.failed,
        cause: error,
      );
    }
  }

  /// Discards a flow the user backed out of, so its verifier does not sit in the keystore.
  Future<void> abandon() => _secrets.delete(_pendingKey);

  /// Reads and removes the pending verifier. Single-use on our side too: the code it pairs with
  /// is spent by one exchange, so keeping the verifier past that would only widen the window.
  Future<String?> _takePending() async {
    final raw = await _secrets.read(_pendingKey);
    if (raw == null) return null;
    await _secrets.delete(_pendingKey);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final verifier = decoded['verifier'];
      final createdAt = decoded['created_at'];
      if (verifier is! String || createdAt is! int) return null;
      final age = _clock() - createdAt;
      return age >= 0 && age <= pendingLifetime.inMilliseconds
          ? verifier
          : null;
    } on FormatException {
      return null;
    }
  }
}
