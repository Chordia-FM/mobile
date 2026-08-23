/// Clients for both Chordia planes.
///
/// The Hub carries identity, catalog and social data; a library server carries the audio. They use
/// different base URLs, different credentials, and — because a library is usually reached over a
/// self-signed certificate — different TLS validation. Keeping both here means the difference is
/// visible in one place rather than assumed at each call site.
library;

export 'src/errors.dart';
export 'src/grants.dart';
export 'src/hub.dart';
export 'src/json.dart' show JsonShapeException;
export 'src/library.dart';
export 'src/models.g.dart';
export 'src/session.dart';
export 'src/transport.dart' show queryOf;

/// The typed Hub call surface: one extension on `HubClient` per OpenAPI tag.
export 'src/endpoints/endpoints.dart';
