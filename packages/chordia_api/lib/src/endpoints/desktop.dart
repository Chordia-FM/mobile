import '../hub.dart';
import '../json.dart';
import '../models.g.dart';

/// The desktop app's release feed, served by the Hub.
extension DesktopEndpoints on HubClient {
  /// The newest desktop build and its per-platform downloads.
  Future<DesktopRelease> latestDesktopRelease() => get(
    '/v1/desktop/latest',
    (json) => DesktopRelease.fromJson(asObject(json)),
  );
}
