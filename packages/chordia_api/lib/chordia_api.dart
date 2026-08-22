/// Clients for both Chordia planes.
///
/// The Hub carries identity, catalog and social data; a library server carries the audio. They use
/// different base URLs, different credentials, and — because a library is usually reached over a
/// self-signed certificate — different TLS validation.
library;

export 'src/json.dart' show JsonShapeException;
export 'src/models.g.dart';
