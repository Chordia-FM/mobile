import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_net/chordia_net.dart';
import 'package:test/test.dart';

Grant grantFor(PermissionLevel? level) => Grant(
  token: 'cap-1',
  expiresAt: 1700000300000,
  permissionLevel: level,
  server: const ServerEndpoint(
    endpoint: 'https://library.example:8443',
    lastHeartbeat: 1700000000000,
    online: true,
    ownerId: 'owner',
    serverId: 'server',
    tlsFingerprint: '',
  ),
);

void main() {
  LibraryClient clientFor(PermissionLevel? level) =>
      LibraryClient(grant: grantFor(level), factory: PinnedHttpClientFactory());

  test('a download says so, spelled the way the server parses', () {
    final client = clientFor(PermissionLevel.download);
    addTearDown(client.close);

    final url = client.streamUrl(
      'ref-1',
      QualityProfile.original,
      download: true,
    );

    expect(
      url.queryParameters,
      {'profile': 'original', 'download': 'true'},
      reason:
          'StreamQuery.download is a Rust bool: `1` fails the whole '
          'query and the library answers 400',
    );
  });

  test('a playback stream carries no download flag at all', () {
    final client = clientFor(PermissionLevel.download);
    addTearDown(client.close);

    final url = client.streamUrl('ref-1', QualityProfile.original);

    expect(url.queryParameters, {'profile': 'original'});
  });

  group('allowsDownload', () {
    test('a stream-only grant refuses', () {
      expect(grantFor(PermissionLevel.read).allowsDownload, isFalse);
    });

    test('a download grant allows', () {
      expect(grantFor(PermissionLevel.download).allowsDownload, isTrue);
    });

    test('a Hub that said nothing is not treated as stream-only', () {
      // An older Hub omits the field; the library still applies its own gate, and failing closed
      // here would break every download against a Hub nobody has upgraded.
      expect(grantFor(null).allowsDownload, isTrue);
    });
  });
}
