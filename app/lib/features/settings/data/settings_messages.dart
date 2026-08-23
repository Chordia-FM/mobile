import 'package:chordia_api/chordia_api.dart';

import '../../../i18n/keys.g.dart';
import 'settings_values.dart';

/// What to tell the user when a settings call failed.
///
/// An [ApiException]'s `title` is used as-is: the Hub localises problem titles from the
/// `Accept-Language` this client already sends, so it is both translated and specific — "Handle
/// already taken" rather than a client-side guess at what a 409 meant. Only a request that never
/// reached a server has to be worded here, because there was no server to word it.
String describeSettingsError(Object error, Translate t) {
  if (error is ApiException) {
    return error.isNetworkFailure ? t(ErrorsKeys.httpNetwork) : error.title;
  }
  return t(ErrorsKeys.changeFailed);
}
