import 'dart:convert';
import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_net/chordia_net.dart';
import 'package:test/test.dart';

/// One request as the server actually received it.
typedef Recorded = ({
  String method,
  String path,
  List<String> segments,
  Map<String, String> query,
  String body,
});

/// A stand-in Hub that records what reached it and answers with whatever the test set.
///
/// Deliberately dumb about routing: these tests are about the *client's* half of each call — the
/// path it builds, the query it encodes, the JSON it sends and the model it decodes — so a route
/// table here would only be a second place to get the same paths wrong.
class FakeHub {
  FakeHub(this._server) {
    _server.listen((req) async {
      try {
        await _handle(req);
      } on Object catch (e, st) {
        // Left unhandled, the connection stays open and the client just waits — a bug in the fake
        // would surface as an unexplained timeout.
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

  final seen = <Recorded>[];

  /// What the next request gets back.
  ({int status, Object? body}) reply = (status: 200, body: null);

  Uri get baseUri => Uri.parse('http://127.0.0.1:${_server.port}');

  Recorded get only => seen.single;

  Future<void> _handle(HttpRequest req) async {
    // Drain before responding: with keep-alive, writing a response while the request body is still
    // unread stalls the connection and every POST hangs.
    final body = await utf8.decoder.bind(req).join();
    seen.add((
      method: req.method,
      // `Uri.path` keeps percent-escapes; `pathSegments` decodes them. Recording both is what lets
      // a test tell an escaped segment from one that split the route.
      path: req.uri.path,
      segments: req.uri.pathSegments,
      query: req.uri.queryParameters,
      body: body,
    ));

    req.response.statusCode = reply.status;
    if (reply.body != null) {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(reply.body));
    }
    await req.response.close();
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late FakeHub hub;
  late HubClient client;

  setUp(() async {
    hub = await FakeHub.start();
    final sessions = SessionManager(
      hubId: 'test',
      store: MemorySessionStore(),
      // Never called: the session below is nowhere near expiry and nothing here answers 401.
      refresher: (_) async => throw StateError('unexpected refresh'),
    );
    await sessions.adopt(
      Session(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        expiresAt: DateTime.now()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      ),
    );
    client = HubClient(
      baseUrl: hub.baseUri,
      sessions: sessions,
      factory: PinnedHttpClientFactory(),
    );
  });

  tearDown(() async {
    client.close();
    await hub.stop();
  });

  test('a GET decodes into its generated model', () async {
    hub.reply = (status: 200, body: {'connected': true, 'username': 'kanin'});

    final status = await client.lastfmStatus();

    expect(hub.only.method, 'GET');
    expect(hub.only.path, '/v1/lastfm/status');
    expect(status.connected, isTrue);
    expect(status.username, 'kanin');
  });

  test('query parameters reach the server as their wire spellings', () async {
    hub.reply = (
      status: 200,
      body: {
        'entries': <Object?>[],
        'kind': 'track',
        'offset': 40,
        'period': 'half_year',
        'total': 412,
        'window_start': 1700000000000,
        'window_end': 1710000000000,
      },
    );

    final page = await client.topChart(
      kind: EntityKind.track,
      period: Period.halfYear,
      offset: 40,
      limit: 20,
    );

    expect(hub.only.path, '/v1/insights/top');
    expect(
      hub.only.query,
      {'kind': 'track', 'period': 'half_year', 'offset': '40', 'limit': '20'},
      reason:
          'enums travel as their wire strings, not their Dart names, and the '
          'arguments left out (user, tz, from, to) send no key at all',
    );
    expect(page.total, 412);
    expect(page.period, Period.halfYear);
  });

  test('a POST sends the request model as JSON', () async {
    hub.reply = (
      status: 200,
      body: {
        'id': 'p-1',
        'name': 'Late nights',
        'created_at': 1700000000000,
        'track_count': 0,
        'visibility': 'unlisted',
      },
    );

    final created = await client.createPlaylist(
      const CreatePlaylistRequest(
        name: 'Late nights',
        visibility: PlaylistVisibility.unlisted,
      ),
    );

    expect(hub.only.method, 'POST');
    expect(hub.only.path, '/v1/playlists');
    expect(
      jsonDecode(hub.only.body),
      {'name': 'Late nights', 'visibility': 'unlisted'},
      reason: 'the absent description is omitted, not sent as null',
    );
    expect(created.id, 'p-1');
    expect(created.visibility, PlaylistVisibility.unlisted);
  });

  test('a 204 endpoint completes with no value to decode', () async {
    hub.reply = (status: 204, body: null);

    await client.likeTrack('11111111-1111-1111-1111-111111111111');

    expect(hub.only.method, 'PUT');
    expect(hub.only.path, '/v1/me/liked/11111111-1111-1111-1111-111111111111');
    expect(hub.only.body, isEmpty);
  });

  group('login', () {
    test('decodes the authenticated branch', () async {
      hub.reply = (
        status: 200,
        body: {
          'tokens': {
            'access_token': 'access-2',
            'refresh_token': 'refresh-2',
            'access_expires_at': 1700003600000,
          },
          'user': {
            'id': 'u-1',
            'handle': 'kanin',
            'display_name': 'Kanin',
            'created_at': 1700000000000,
          },
        },
      );

      final outcome = await client.login(
        const LoginRequest(email: 'im@kanin.dev', password: 'hunter2'),
      );

      expect(jsonDecode(hub.only.body), {
        'email': 'im@kanin.dev',
        'password': 'hunter2',
      });
      final signedIn = outcome as LoginSucceeded;
      expect(signedIn.auth.tokens.accessToken, 'access-2');
      expect(signedIn.auth.user.handle, 'kanin');
    });

    test('decodes the 2FA-challenge branch the schema does not describe', () async {
      // Same status, same content type, a completely different shape. Decoding this as an
      // AuthResponse — which is all the OpenAPI document promises — throws on the missing `tokens`
      // and the user is told their login failed instead of being asked for a code.
      hub.reply = (
        status: 200,
        body: {'mfa_required': true, 'mfa_token': 'challenge-1'},
      );

      final outcome = await client.login(
        const LoginRequest(email: 'im@kanin.dev', password: 'hunter2'),
      );

      expect(outcome, isA<LoginNeedsMfa>());
      expect((outcome as LoginNeedsMfa).mfaToken, 'challenge-1');
    });
  });

  test('the scrobble batch keeps its colon in the path', () async {
    hub.reply = (status: 200, body: {'accepted': 0, 'duplicates': 0});

    await client.submitScrobbles(const ScrobbleBatch(events: []));

    expect(
      hub.only.path,
      '/v1/scrobbles:batch',
      reason:
          'the colon is part of the route name; escaped, the Hub matches '
          '/v1/scrobbles/{event_id} instead and answers 404',
    );
  });

  test('a handle is escaped into one path segment', () async {
    hub.reply = (status: 204, body: null);

    await client.followUser('odd/handle');

    expect(hub.only.path, '/v1/users/odd%2Fhandle/follow');
    expect(
      hub.only.segments,
      ['v1', 'users', 'odd/handle', 'follow'],
      reason: 'the slash stays inside the handle instead of adding a segment',
    );
  });
}
