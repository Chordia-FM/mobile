import '../hub.dart';
import '../json.dart';
import '../models.g.dart';

/// The server directory: where a library server is reachable, and what certificate it presents.
///
/// The other two routes under this tag are absent on purpose. Minting a capability token
/// (`POST /v1/directory/grant`) belongs to `GrantManager`, which caches and de-duplicates it;
/// heartbeat is a library server reporting in with a server API key, not something a client does.
extension DirectoryEndpoints on HubClient {
  /// Resolves a server to its endpoint and advertised TLS fingerprint.
  ///
  /// The fingerprint is the pin: library servers usually run self-signed certificates, and this is
  /// what makes that safe. Nothing should connect to a library on an endpoint learned any other
  /// way.
  Future<ResolvedServer> resolveServer(String serverId) => get(
    '/v1/directory/servers/$serverId',
    (json) => ResolvedServer.fromJson(asObject(json)),
  );
}
