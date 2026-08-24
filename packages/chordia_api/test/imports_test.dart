import 'dart:convert';
import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_net/chordia_net.dart';
import 'package:test/test.dart';

/// One request as the server actually received it, body bytes and all.
typedef RecordedUpload = ({
  String method,
  String path,
  Map<String, String> query,
  String? contentType,
  List<int> body,
});

/// A stand-in Hub for the one call whose body is a file rather than JSON.
///
/// Its own fake rather than `endpoints_test.dart`'s, which decodes the body as UTF-8 text: the
/// point of these tests is the bytes, and a fake that stringifies them cannot tell a truncated
/// upload from a complete one.
class _FakeHub {
  _FakeHub(this._server) {
    _server.listen((req) async {
      // Drain before responding: with keep-alive, writing while the request body is still unread
      // stalls the connection and every POST hangs.
      final body = <int>[];
      await for (final chunk in req) {
        body.addAll(chunk);
      }
      seen.add((
        method: req.method,
        path: req.uri.path,
        query: req.uri.queryParameters,
        contentType: req.headers.contentType?.mimeType,
        body: body,
      ));
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

  ({int status, Object? body}) reply = (status: 200, body: null);

  Uri get baseUri => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> stop() => _server.close(force: true);
}

Map<String, Object?> _job() => {
  'id': 'job-1',
  'created_at': 1700000000000,
  'source': 'spotify',
  'status': 'pending',
  'imported_rows': 0,
  'matched_rows': 0,
  'duplicate_rows': 0,
  'skipped_rows': 0,
  'total_rows': 0,
};

void main() {
  late _FakeHub hub;
  late HubClient client;

  setUp(() async {
    hub = await _FakeHub.start();
    final sessions = SessionManager(
      hubId: 'test',
      store: MemorySessionStore(),
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

  test('the export goes up as its own bytes, not wrapped in JSON', () async {
    hub.reply = (status: 200, body: _job());
    // Bytes that are not valid UTF-8, because a Last.fm CSV can carry anything and a transport
    // that re-encoded the body would corrupt exactly this.
    final bytes = [0x00, 0xFF, 0xFE, 0x41, 0x42];

    final job = await client.startImport(bytes);

    final sent = hub.seen.single;
    expect(sent.method, 'POST');
    expect(sent.path, '/v1/me/imports');
    expect(sent.body, bytes);
    expect(sent.contentType, 'application/octet-stream');
    // `auto`: with no source stated the parameter is absent rather than empty, because the Hub
    // reads an empty string and an absent one the same way only by accident.
    expect(sent.query, isEmpty);
    expect(job.id, 'job-1');
    expect(job.status, ImportJobStatus.pending);
  });

  test(
    'a stated source rides in the query, spelled as the wire spells it',
    () async {
      hub.reply = (status: 200, body: _job());

      await client.startImport([0x41], source: ImportSource.lastfm);

      expect(hub.seen.single.query, {'source': 'lastfm'});
    },
  );

  test('a refusal arrives as the problem the Hub described', () async {
    // 402 is the one this endpoint answers most: history import is a Super-Sonic capability, and
    // "Could not reach the server" would be the wrong sentence entirely.
    hub.reply = (
      status: 402,
      body: {'title': 'Your plan does not include history import.'},
    );

    await expectLater(
      client.startImport([0x41]),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 402)
            .having(
              (e) => e.title,
              'title',
              'Your plan does not include history import.',
            ),
      ),
    );
  });
}
