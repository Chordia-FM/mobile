import 'dart:async';
import 'dart:convert';

import 'package:chordia_api/chordia_api.dart';
import 'package:test/test.dart';

String jwtWithExp(int exp) {
  String seg(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${seg({'alg': 'EdDSA'})}.${seg({'exp': exp})}.signature';
}

Session sessionExpiring(int at) => Session(
  accessToken: jwtWithExp(at),
  refreshToken: 'refresh-1',
  expiresAt: at,
);

void main() {
  group('expiryOf', () {
    test('reads exp verbatim, in the milliseconds the Hub actually sends', () {
      // The Hub mints exp in epoch MILLIS and validates it by hand. A decoder that assumed
      // seconds would place this token's expiry about 50,000 years out and never refresh.
      const millis = 1893456000000; // 2030-01-01
      expect(expiryOf(jwtWithExp(millis)), millis);
    });

    test('returns null for a token it cannot read rather than guessing', () {
      expect(expiryOf('not-a-jwt'), isNull);
      expect(expiryOf('a.b'), isNull);
      expect(expiryOf('a.!!!not-base64!!!.c'), isNull);
    });
  });

  group('SessionManager', () {
    late int now;
    late int refreshCalls;

    setUp(() {
      now = 1000000;
      refreshCalls = 0;
    });

    SessionManager build({
      required Future<Session> Function(String) refresher,
      SessionStore? store,
    }) => SessionManager(
      hubId: 'hub',
      store: store ?? MemorySessionStore(),
      refresher: refresher,
      clock: () => now,
    );

    test('reuses a token that is not near expiry', () async {
      final m = build(
        refresher: (_) async {
          refreshCalls++;
          throw StateError('should not refresh');
        },
      );
      final session = sessionExpiring(
        now + const Duration(minutes: 10).inMilliseconds,
      );
      await m.adopt(session);

      expect(await m.freshAccessToken(), session.accessToken);
      expect(refreshCalls, 0);
    });

    test('refreshes inside the skew window', () async {
      final m = build(
        refresher: (_) async {
          refreshCalls++;
          return sessionExpiring(now + const Duration(hours: 1).inMilliseconds);
        },
      );
      await m.adopt(
        sessionExpiring(now + const Duration(seconds: 30).inMilliseconds),
      );

      final token = await m.freshAccessToken();
      expect(refreshCalls, 1);
      expect(token, isNot(equals('')));
      expect(m.current!.expiresAt, greaterThan(now));
    });

    test('concurrent callers share ONE refresh', () async {
      // Refresh tokens rotate and are single-use: a second concurrent refresh presents a token the
      // server already retired, and the session dies. This is the test that pins that down.
      final gate = Completer<void>();
      final m = build(
        refresher: (_) async {
          refreshCalls++;
          await gate.future;
          return sessionExpiring(now + const Duration(hours: 1).inMilliseconds);
        },
      );
      await m.adopt(sessionExpiring(now + 1));

      final calls = List.generate(8, (_) => m.freshAccessToken());
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      final tokens = await Future.wait(calls);

      expect(refreshCalls, 1);
      expect(
        tokens.toSet().length,
        1,
        reason: 'every caller got the same token',
      );
    });

    test('a rejected refresh signs out instead of retrying forever', () async {
      final store = MemorySessionStore();
      final m = build(
        store: store,
        refresher: (_) async {
          refreshCalls++;
          throw const ApiException(
            status: 401,
            title: 'nope',
            method: 'POST',
            path: '/v1/auth/refresh',
          );
        },
      );
      await m.adopt(sessionExpiring(now + 1));

      final signedOut = m.onSignedOut.first;
      expect(await m.freshAccessToken(), isNull);
      await signedOut.timeout(const Duration(seconds: 1));

      expect(m.isSignedIn, isFalse);
      expect(
        await store.read('hub'),
        isNull,
        reason: 'the dead session is not left on disk',
      );
      // A second attempt must not re-hit the endpoint with a token already known to be spent.
      expect(await m.freshAccessToken(), isNull);
      expect(refreshCalls, 1);
    });

    test('a network failure keeps the session rather than signing out', () async {
      // Opening the app with no connection must not log someone out — that would take their
      // downloaded music with it. Only an answer from the server ends a session.
      final store = MemorySessionStore();
      final m = build(
        store: store,
        refresher: (_) async {
          refreshCalls++;
          throw const ApiException(
            status: 0,
            title: 'offline',
            method: 'POST',
            path: '/v1/auth/refresh',
          );
        },
      );
      await m.adopt(sessionExpiring(now + 1));

      expect(
        await m.freshAccessToken(),
        isNull,
        reason: 'no usable token right now',
      );
      expect(m.isSignedIn, isTrue, reason: 'but still signed in');
      expect(m.isOffline, isTrue);
      expect(
        await store.read('hub'),
        isNotNull,
        reason: 'the session stays on disk',
      );
    });

    test('a refresh that succeeds later clears the offline flag', () async {
      var offline = true;
      final m = build(
        refresher: (_) async {
          refreshCalls++;
          if (offline) {
            throw const ApiException(
              status: 0,
              title: 'offline',
              method: 'POST',
              path: '/v1/auth/refresh',
            );
          }
          return sessionExpiring(now + const Duration(hours: 1).inMilliseconds);
        },
      );
      await m.adopt(sessionExpiring(now + 1));

      await m.freshAccessToken();
      expect(m.isOffline, isTrue);

      offline = false;
      await m.forceRefresh();

      expect(m.isOffline, isFalse);
      expect(m.isSignedIn, isTrue);
    });

    test('a later refresh works after an earlier one finished', () async {
      final m = build(
        refresher: (_) async {
          refreshCalls++;
          return sessionExpiring(now + const Duration(hours: 1).inMilliseconds);
        },
      );
      await m.adopt(sessionExpiring(now + 1));

      await m.freshAccessToken();
      expect(refreshCalls, 1);

      now += const Duration(hours: 1).inMilliseconds;
      await m.freshAccessToken();
      expect(
        refreshCalls,
        2,
        reason: 'the in-flight guard released after the first completed',
      );
    });

    test('signing out clears the stored session', () async {
      final store = MemorySessionStore();
      final m = build(
        store: store,
        refresher: (_) async => throw StateError('no'),
      );
      await m.adopt(sessionExpiring(now + 999999));

      await m.signOut();
      expect(m.current, isNull);
      expect(await store.read('hub'), isNull);
      expect(await m.freshAccessToken(), isNull);
    });
  });

  group('image widths', () {
    test('snaps up to a width the Hub actually derives', () {
      // Anything off the ladder is ignored by the Hub and the ORIGINAL is served — several MB from
      // a fanart.tv source. Snapping up is the whole point of routing every caller through here.
      expect(snapImageWidth(1), 64);
      expect(snapImageWidth(64), 64);
      expect(snapImageWidth(65), 96);
      expect(snapImageWidth(200), 256);
      expect(snapImageWidth(1024), 1024);
      expect(
        snapImageWidth(4000),
        1024,
        reason: 'capped at the largest derived width',
      );
    });
  });

  group('ByteRange', () {
    test('renders the two forms the library server can parse', () {
      expect(const ByteRange(0).header, 'bytes=0-');
      expect(const ByteRange(100, 199).header, 'bytes=100-199');
    });

    test('rewrites a suffix range into an absolute one', () {
      // `bytes=-500` falls through the library's parser to a 200 with the whole body, turning a
      // tail probe into a full download.
      final r = ByteRange.fromSuffix(500, totalBytes: 10000);
      expect(r.header, 'bytes=9500-9999');
    });

    test('a suffix longer than the file starts at zero', () {
      final r = ByteRange.fromSuffix(9999, totalBytes: 100);
      expect(r.header, 'bytes=0-99');
    });
  });
}
