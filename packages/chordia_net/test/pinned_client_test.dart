import 'dart:convert';
import 'dart:io';

import 'package:chordia_net/chordia_net.dart';
import 'package:test/test.dart';

/// Reads the DER bytes out of a PEM certificate so the test can derive the expected fingerprint
/// from the same file the server presents, rather than hard-coding a hash that would silently rot
/// if the fixtures were ever regenerated.
List<int> derOfPem(String pem) {
  final body = pem
      .split('\n')
      .map((l) => l.trim())
      .where((l) => !l.startsWith('-----') && l.isNotEmpty)
      .join();
  return base64Decode(body);
}

void main() {
  final fixtures = Directory('test/fixtures');
  final certA = File('${fixtures.path}/serverA.crt');
  final keyA = File('${fixtures.path}/serverA.key');
  final certB = File('${fixtures.path}/serverB.crt');

  late HttpServer server;
  late Uri baseUri;

  setUp(() async {
    final context = SecurityContext()
      ..useCertificateChain(certA.path)
      ..usePrivateKey(keyA.path);
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    baseUri = Uri.parse('https://localhost:${server.port}/hello');
    server.listen((req) async {
      req.response
        ..statusCode = 200
        ..write('ok');
      await req.response.close();
    });
  });

  tearDown(() async => server.close(force: true));

  Future<String> get(HttpClient client, Uri uri) async {
    final req = await client.getUrl(uri);
    final res = await req.close();
    return res.transform(utf8.decoder).join();
  }

  group('CertFingerprint', () {
    test('parses lowercase, uppercase and colon-separated hex identically', () {
      final plain = CertFingerprint.tryParse('a' * 64);
      final upper = CertFingerprint.tryParse(('a' * 64).toUpperCase());
      final grouped = CertFingerprint.tryParse(List.filled(32, 'AA').join(':'));

      expect(plain, isNotNull);
      expect(upper, plain);
      expect(grouped, plain);
    });

    test(
      'treats the empty fingerprint as "validate normally", not as a value',
      () {
        // The directory stores an empty string for libraries that terminate TLS at an edge proxy.
        expect(CertFingerprint.tryParse(''), isNull);
        expect(CertFingerprint.tryParse('   '), isNull);
        expect(CertFingerprint.tryParse(null), isNull);
      },
    );

    test('rejects malformed fingerprints rather than truncating them', () {
      expect(CertFingerprint.tryParse('deadbeef'), isNull, reason: 'too short');
      expect(CertFingerprint.tryParse('z' * 64), isNull, reason: 'not hex');
      expect(CertFingerprint.tryParse('a' * 65), isNull, reason: 'too long');
    });
  });

  group('PinnedHttpClientFactory', () {
    test('accepts the server whose certificate matches the pin', () async {
      final factory = PinnedHttpClientFactory();
      final pin = CertFingerprint.ofDer(derOfPem(certA.readAsStringSync()));
      final client = factory.pinnedTo(pin);
      addTearDown(() => client.close(force: true));

      expect(await get(client, baseUri), 'ok');
    });

    test('rejects a server presenting a different certificate', () async {
      final factory = PinnedHttpClientFactory();
      final wrongPin = CertFingerprint.ofDer(
        derOfPem(certB.readAsStringSync()),
      );
      final client = factory.pinnedTo(wrongPin);
      addTearDown(() => client.close(force: true));

      await expectLater(
        get(client, baseUri),
        throwsA(isA<HandshakeException>()),
      );

      final mismatch = factory.takeLastMismatch();
      expect(mismatch, isNotNull);
      expect(mismatch!.expected, wrongPin);
      expect(
        mismatch.actual,
        CertFingerprint.ofDer(derOfPem(certA.readAsStringSync())),
      );
    });

    test(
      'an unpinned client will not accept a self-signed certificate',
      () async {
        final client = PinnedHttpClientFactory().unpinned();
        addTearDown(() => client.close(force: true));

        await expectLater(
          get(client, baseUri),
          throwsA(isA<HandshakeException>()),
        );
      },
    );

    test('pinning to null falls back to system validation', () async {
      // "No fingerprint advertised" must behave exactly like the unpinned client, so call sites
      // never have to branch on it.
      final client = PinnedHttpClientFactory().pinnedTo(null);
      addTearDown(() => client.close(force: true));

      await expectLater(
        get(client, baseUri),
        throwsA(isA<HandshakeException>()),
      );
    });

    test(
      'a pinned client rejects a publicly trusted certificate it was not pinned to',
      () async {
        // The empty trust store is what makes this true: without it, a CA-signed certificate for the
        // host would pass chain validation and never reach the pin check at all.
        final factory = PinnedHttpClientFactory();
        final pin = CertFingerprint.ofDer(derOfPem(certA.readAsStringSync()));
        final client = factory.pinnedTo(pin);
        addTearDown(() => client.close(force: true));

        await expectLater(
          get(client, Uri.parse('https://example.com/')),
          throwsA(isA<HandshakeException>()),
        );
      },
    );
  });
}
