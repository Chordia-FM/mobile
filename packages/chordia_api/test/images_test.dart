import 'dart:convert';
import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_net/chordia_net.dart';
import 'package:test/test.dart';

/// One request as the server received it, plus the bearer it arrived with.
typedef RecordedUpload = ({
  String method,
  String path,
  String? contentType,
  String? authorization,
  List<int> body,
});

/// A stand-in Hub that answers a scripted status per request, in order.
///
/// The scripted sequence is what makes the 401 case testable: the retry only proves anything if the
/// first answer and the second differ, and a single fixed reply cannot express that.
class _FakeHub {
  _FakeHub(this._server) {
    _server.listen((req) async {
      // Drain before responding: with keep-alive, writing while the request body is still unread
      // stalls the connection and the upload hangs.
      final body = <int>[];
      await for (final chunk in req) {
        body.addAll(chunk);
      }
      seen.add((
        method: req.method,
        path: req.uri.path,
        contentType: req.headers.contentType?.mimeType,
        authorization: req.headers.value(HttpHeaders.authorizationHeader),
        body: body,
      ));
      final reply = replies.length > 1 ? replies.removeAt(0) : replies.first;
      req.response.statusCode = reply.status;
      if (reply.body != null) {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(reply.body));
      }
      await req.response.close();
    });
  }

  static Future<_FakeHub> start() async =>
      _FakeHub(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final seen = <RecordedUpload>[];

  var replies = <({int status, Object? body})>[(status: 200, body: null)];

  Uri get baseUri => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> stop() => _server.close(force: true);
}

Session _session(String access) => Session(
  accessToken: access,
  refreshToken: 'refresh-1',
  expiresAt: DateTime.now()
      .add(const Duration(hours: 1))
      .millisecondsSinceEpoch,
);

void main() {
  late _FakeHub hub;
  late HubClient client;
  late int refreshes;

  setUp(() async {
    hub = await _FakeHub.start();
    refreshes = 0;
    final sessions = SessionManager(
      hubId: 'test',
      store: MemorySessionStore(),
      refresher: (_) async {
        refreshes++;
        return _session('access-2');
      },
    );
    await sessions.adopt(_session('access-1'));
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

  test(
    'the picture goes up as its own bytes and answers with its hash',
    () async {
      hub.replies = [
        (status: 200, body: {'hash': 'abc123'}),
      ];
      // Bytes that are not valid UTF-8, because a JPEG is not text and a transport that re-encoded
      // the body would corrupt exactly this.
      final bytes = [0xFF, 0xD8, 0xFF, 0x00, 0x41];

      final hash = await client.uploadImage(bytes, contentType: 'image/jpeg');

      final sent = hub.seen.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/v1/images');
      expect(sent.body, bytes);
      expect(sent.contentType, 'image/jpeg');
      expect(hash, 'abc123');
    },
  );

  test('a 401 refreshes once and re-sends the same picture', () async {
    hub.replies = [
      (status: 401, body: null),
      (status: 200, body: {'hash': 'abc123'}),
    ];

    final hash = await client.uploadImage([0x41], contentType: 'image/png');

    expect(refreshes, 1);
    expect(hash, 'abc123');
    expect(hub.seen.map((r) => r.authorization), [
      'Bearer access-1',
      'Bearer access-2',
    ]);
  });

  test('a refusal arrives as the problem the Hub described', () async {
    hub.replies = [
      (status: 415, body: {'title': 'That file is not an image.'}),
    ];

    await expectLater(
      client.uploadImage([0x41]),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 415)
            .having((e) => e.title, 'title', 'That file is not an image.'),
      ),
    );
  });

  test(
    'a picture over the cap is refused without spending the upload',
    () async {
      await expectLater(
        client.uploadImage(List.filled(ImageEndpoints.maxImageBytes + 1, 0)),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 0)),
      );
      await expectLater(
        client.uploadImage(const []),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 0)),
      );
      expect(hub.seen, isEmpty);
    },
  );
}
