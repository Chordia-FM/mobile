import 'package:chordia_api/chordia_api.dart';

import '../../data/browser_handoff.dart';
import '../../data/hub_probe.dart';
import '../../i18n/keys.g.dart';

/// A translator, as `ref.t` hands one out.
typedef Translate = String Function(String, [Map<String, Object?>]);

/// Turns anything thrown by the auth layer into a sentence for the user.
///
/// An [ApiException]'s `title` is used as-is on purpose: the Hub localises problem titles from the
/// `Accept-Language` this client already sends, so it is both translated and specific — "Incorrect
/// email or password" rather than a generic client-side guess at what a 401 meant. Only a failure
/// that never reached the server has to be worded here, because there was no server to word it.
String describeAuthError(Object error, Translate t) {
  if (error is ApiException) {
    return error.isNetworkFailure ? t(ErrorsKeys.httpNetwork) : error.title;
  }
  if (error is HubProbeException) {
    return switch (error.failure) {
      HubProbeFailure.invalidUrl => t(AuthKeys.hubInvalidUrl),
      HubProbeFailure.insecure => t(AuthKeys.hubInsecureRefused),
      HubProbeFailure.unreachable => t(AuthKeys.hubUnreachable),
    };
  }
  if (error is BrowserHandoffException) {
    return switch (error.failure) {
      BrowserHandoffFailure.noFrontend => t(AuthKeys.desktopNoFrontend),
      BrowserHandoffFailure.cannotOpenBrowser => t(
        AuthKeys.desktopCannotOpenBrowser,
      ),
      BrowserHandoffFailure.expired => t(AuthKeys.desktopExpired),
      BrowserHandoffFailure.failed => t(AuthKeys.desktopFailed),
    };
  }
  return t(ErrorsKeys.generic);
}
