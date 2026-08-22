import 'dart:convert';
import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_net/chordia_net.dart';
import 'package:test/test.dart';

/// A stand-in Hub, so the client is exercised over a real socket rather than a mocked seam.
class FakeHub {
  FakeHub(this._server) {
    _server.listen((req) async {
      try {
        await _handle(req);
      } on Object catch (e, st) {
        // Without this the connection is left open and the client simply waits, turning a bug in
        // the fake into an unexplained timeout.
        // ignore: avoid_print
        print('FakeHub failed on ${req.method} ${req.uri.path}: $e\n$st');
        req.response.statusCode = 500;
        await req.response.close();
      }
    });
  }

  static Future<FakeHub> start() async =>
      FakeHub(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;

  /// Requests seen, as `METHOD path`, with the bearer token that carried them.
  final seen = <({String line, String? bearer, String? language})>[];

  /// Raw request bodies, in order, so a test can assert what was actually sent.
  final requestBodies = <String>[];

  /// Tokens the fake will accept. Anything else gets a 401.
  var validTokens = <String>{'access-1'};
  var refreshCount = 0;
  var grantCount = 0;

  /// When false, refreshing succeeds but hands back a token this server still rejects — the shape
  /// of a session revoked server-side, where retrying cannot help.
  var refreshMintsUsableToken = true;

  Uri get baseUri => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> _handle(HttpRequest req) async {
    // Drain before responding: with keep-alive, writing a response while the request body is still
    // unread stalls the connection, and every POST would simply hang.
    final body = await utf8.decoder.bind(req).join();
    requestBodies.add(body);

    final auth = req.headers.value(HttpHeaders.authorizationHeader);
    final bearer = auth?.startsWith('Bearer ') ?? false
        ? auth!.substring(7)
        : null;
    seen.add((
      line: '${req.method} ${req.uri.path}',
      bearer: bearer,
      language: req.headers.value(HttpHeaders.acceptLanguageHeader),
    ));

    void send(int status, Object? body) {
      req.response.statusCode = status;
      if (body != null) {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(body));
      }
      req.response.close();
    }

    if (req.uri.path == '/v1/auth/refresh') {
      refreshCount++;
      if (refreshMintsUsableToken) validTokens = {'access-${refreshCount + 1}'};
      send(200, {
        'access_token': 'access-${refreshCount + 1}',
        'refresh_token': 'refresh-${refreshCount + 1}',
        'expires_at': DateTime.now()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      });
      return;
    }

    if (bearer == null || !validTokens.contains(bearer)) {
      send(401, {
        'type': 'https://chordia.fm/problems/unauthorized',
        'title': 'Not signed in',
        'status': 401,
      });
      return;
    }

    switch (req.uri.path) {
      case '/v1/directory/grant':
        grantCount++;
        send(200, {
          'token': 'cap-$grantCount',
          'expires_at': DateTime.now()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          'server': {
            'server_id': '11111111-1111-1111-1111-111111111111',
            'owner_id': '22222222-2222-2222-2222-222222222222',
            'endpoint': 'https://library.example:8443',
            'tls_fingerprint': 'a' * 64,
            'online': true,
            'last_heartbeat': 1700000000000,
          },
        });
      case '/v1/teapot':
        send(418, {
          'title': "I'm a teapot",
          'status': 418,
          'detail': 'short and stout',
        });
      case '/v1/empty':
        send(204, null);
      default:
        send(404, {'title': 'Not found', 'status': 404});
    }
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late FakeHub hub;
  late HubClient client;
  late SessionManager sessions;

  setUp(() async {
    hub = await FakeHub.start();
    final factory = PinnedHttpClientFactory();
    sessions = SessionManager(
      hubId: 'test',
      store: MemorySessionStore(),
      refresher: (refreshToken) async {
        final raw = await JsonTransportForTest.post(
          hub.baseUri.replace(path: '/v1/auth/refresh'),
          {'refresh_token': refreshToken},
        );
        return Session(
          accessToken: raw['access_token']! as String,
          refreshToken: raw['refresh_token']! as String,
          expiresAt: raw['expires_at']! as int,
        );
      },
    );
    client = HubClient(
      baseUrl: hub.baseUri,
      sessions: sessions,
      factory: factory,
      acceptLanguage: () => 'en-GB',
    );
  });

  tearDown(() async {
    client.close();
    await hub.stop();
  });

  Future<void> signIn({required int expiresAt}) => sessions.adopt(
    Session(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
      expiresAt: expiresAt,
    ),
  );

  final farFuture = DateTime.now()
      .add(const Duration(hours: 1))
      .millisecondsSinceEpoch;

  test('sends the bearer token and the accept-language header', () async {
    await signIn(expiresAt: farFuture);
    await client.get('/v1/empty', (_) => null);

    expect(hub.seen.single.bearer, 'access-1');
    expect(hub.seen.single.language, 'en-GB');
  });

  test('a 204 decodes as a null body rather than a parse error', () async {
    await signIn(expiresAt: farFuture);
    expect(await client.get<Object?>('/v1/empty', (json) => json), isNull);
  });

  test('surfaces a problem document as a typed error', () async {
    await signIn(expiresAt: farFuture);

    await expectLater(
      client.get('/v1/teapot', (_) => null),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 418)
            .having((e) => e.title, 'title', "I'm a teapot")
            .having((e) => e.detail, 'detail', 'short and stout')
            .having((e) => e.path, 'path', '/v1/teapot'),
      ),
    );
  });

  test('an unreachable server is status 0, not an HTTP error', () async {
    await signIn(expiresAt: farFuture);
    final dead = HubClient(
      // Port 1 is reserved and nothing listens on it.
      baseUrl: Uri.parse('http://127.0.0.1:1'),
      sessions: sessions,
      factory: PinnedHttpClientFactory(),
    );
    addTearDown(dead.close);

    await expectLater(
      dead.get('/v1/anything', (_) => null),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 0)
            .having((e) => e.isNetworkFailure, 'isNetworkFailure', isTrue),
      ),
    );
  });

  test(
    'refreshes and replays once when a token is rejected mid-flight',
    () async {
      // The token still looks valid to us — the session was revoked elsewhere, or clocks disagree —
      // so only the 401 reveals it.
      await signIn(expiresAt: farFuture);
      hub.validTokens = {'nothing-matches'};

      final grants = GrantManager(hub: client);
      final grant = await grants.forLibrary(
        '33333333-3333-3333-3333-333333333333',
      );

      expect(hub.refreshCount, 1);
      expect(grant.token, 'cap-1');
      expect(
        hub.seen.map((r) => r.line).toList(),
        [
          'POST /v1/directory/grant',
          'POST /v1/auth/refresh',
          'POST /v1/directory/grant',
        ],
        reason:
            'the original request is replayed after the refresh, not abandoned',
      );
    },
  );

  test(
    'a 401 that survives a refresh is reported rather than looped',
    () async {
      await signIn(expiresAt: farFuture);
      hub.validTokens = {};
      hub.refreshMintsUsableToken = false;

      await expectLater(
        client.get('/v1/empty', (_) => null),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
      expect(
        hub.refreshCount,
        1,
        reason: 'refreshed once, replayed once, then gave up',
      );
    },
  );

  group('GrantManager', () {
    test('caches a grant and reuses it while it has margin left', () async {
      await signIn(expiresAt: farFuture);
      final grants = GrantManager(hub: client);

      final a = await grants.forLibrary('lib-1');
      final b = await grants.forLibrary('lib-1');

      expect(hub.grantCount, 1);
      expect(a.token, b.token);
      expect(a.fingerprint, isNotNull, reason: 'the advertised pin is parsed');
      expect(a.endpoint.host, 'library.example');
    });

    test(
      'mints once when several callers want the same library at once',
      () async {
        await signIn(expiresAt: farFuture);
        final grants = GrantManager(hub: client);

        final all = await Future.wait(
          List.generate(6, (_) => grants.forLibrary('lib-1')),
        );

        expect(hub.grantCount, 1);
        expect(all.map((g) => g.token).toSet().length, 1);
      },
    );

    test('re-mints once the cached grant is inside the margin', () async {
      await signIn(expiresAt: farFuture);
      var now = DateTime.now().millisecondsSinceEpoch;
      final grants = GrantManager(hub: client, clock: () => now);

      await grants.forLibrary('lib-1');
      now += const Duration(minutes: 5).inMilliseconds;
      await grants.forLibrary('lib-1');

      expect(hub.grantCount, 2);
    });

    test(
      'clearing drops cached tokens so a signed-out app cannot stream',
      () async {
        await signIn(expiresAt: farFuture);
        final grants = GrantManager(hub: client);

        await grants.forLibrary('lib-1');
        grants.clear();
        await grants.forLibrary('lib-1');

        expect(hub.grantCount, 2);
      },
    );
  });
}

/// Minimal POST helper for the refresher, which sits outside the client under test.
abstract final class JsonTransportForTest {
  static Future<Map<String, Object?>> post(Uri url, Object body) async {
    final c = HttpClient();
    try {
      final req = await c.postUrl(url);
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      return (jsonDecode(text) as Map).cast<String, Object?>();
    } finally {
      c.close(force: true);
    }
  }
}
