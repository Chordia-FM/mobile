import 'package:chordia_api/chordia_api.dart';

import '../../../i18n/keys.g.dart';

/// A lookup into the loaded catalogs. `Translations` itself satisfies it, and so does `ref.t`.
typedef Translate = String Function(String key, [Map<String, Object?> args]);

/// What to tell the user when a social or insights call failed.
///
/// An [ApiException]'s `title` is used as-is: the Hub localises problem titles from the
/// `Accept-Language` this client already sends, so it is both translated and specific — "You can't
/// send a friend request to yourself" rather than a client-side guess at what a 400 meant. Only a
/// request that never reached a server has to be worded here, because there was no server to word
/// it.
String describeSocialError(Object error, Translate t) {
  if (error is ApiException) {
    return error.isNetworkFailure ? t(ErrorsKeys.httpNetwork) : error.title;
  }
  return t(ErrorsKeys.changeFailed);
}
