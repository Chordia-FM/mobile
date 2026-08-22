import 'dart:async';
import 'dart:math';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/app.dart';
import 'package:chordia_mobile/app/config.dart';
import 'package:chordia_mobile/app/providers.dart';
import 'package:chordia_mobile/data/auth_repository.dart';
import 'package:chordia_mobile/data/browser_handoff.dart';
import 'package:chordia_mobile/data/hub.dart';
import 'package:chordia_mobile/data/hub_probe.dart';
import 'package:chordia_mobile/data/hub_registry.dart';
import 'package:chordia_mobile/data/secret_store.dart';
import 'package:chordia_mobile/data/session_store.dart';
import 'package:chordia_mobile/features/auth/sign_in_screen.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loaded once, in real async.
///
/// `testWidgets` runs its body inside a fake-async zone where a real asset read never completes,
/// so the catalogs have to be in hand before the first pump.
late Translations translations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    translations = await Translations.load('en', bundle: rootBundle);
  });

  group('PKCE', () {
    test('the challenge is the lowercase hex SHA-256 of the verifier', () {
      // The Hub recomputes `sha256_hex(verifier)` over the raw UTF-8 bytes and compares it to the
      // challenge it stored. Nothing here may base64 it, uppercase it, or hash the bytes of some
      // other encoding — the exchange would fail with a 401 that says nothing about why.
      expect(
        BrowserHandoff.challengeFor('chordia-test-verifier'),
        '3c5f1b619f315b2ceaf377632623a78cddff46a0ea3dba8451a8bc6aad11826a',
      );
      expect(
        BrowserHandoff.challengeFor('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('a verifier is 256 bits of URL-safe text, fresh each time', () {
      final entropy = Random(7);
      final first = BrowserHandoff.newVerifier(entropy);
      final second = BrowserHandoff.newVerifier(entropy);
      // 32 bytes is 43 unpadded base64url characters, and the alphabet has to survive a query
      // string untouched — the challenge is a hash of these exact bytes.
      expect(first, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      // Successive draws must differ. A verifier reused across flows would let a code stolen from
      // one flow be redeemed by the next, which is the whole thing the binding exists to stop.
      expect(second, isNot(first));
    });

    test('the authorize URL carries the challenge and this app scheme', () {
      final url = BrowserHandoff.authorizeUrl(
        frontendUrl: Uri.parse('https://chordia.example/'),
        challenge: 'deadbeef',
      );
      expect(url.path, '/auth/desktop');
      expect(url.queryParameters['challenge'], 'deadbeef');
      expect(url.queryParameters['scheme'], 'chordia');
      // The verifier is the one thing that must never travel.
      expect(url.toString(), isNot(contains('verifier')));
    });

    test('only a well-formed callback link yields a code', () {
      expect(
        BrowserHandoff.codeOf(Uri.parse('chordia://auth/callback?code=abc')),
        'abc',
      );
      expect(
        BrowserHandoff.codeOf(Uri.parse('chordia://auth/callback')),
        isNull,
      );
      // A look-alike host must not read as ours: the link is the one input that arrives from
      // outside the app.
      expect(
        BrowserHandoff.codeOf(
          Uri.parse('chordia://auth.evil.example/callback?code=abc'),
        ),
        isNull,
      );
      expect(
        BrowserHandoff.codeOf(Uri.parse('https://auth/callback?code=abc')),
        isNull,
      );
    });
  });

  group('hub URL normalisation', () {
    test('a bare host becomes an https origin', () {
      expect(
        normalizeHubUrl('chordia.example.com'),
        Uri.parse('https://chordia.example.com'),
      );
    });

    test('paths, queries and whitespace are discarded', () {
      // All three of these are the same server. If they normalised differently the registry would
      // hold three entries, each with its own session.
      const same = 'https://chordia.example.com';
      expect(
        normalizeHubUrl('  https://chordia.example.com/app/  ').toString(),
        same,
      );
      expect(
        normalizeHubUrl('https://chordia.example.com?x=1').toString(),
        same,
      );
      expect(normalizeHubUrl('https://chordia.example.com').toString(), same);
    });

    test('a non-default port survives', () {
      expect(
        normalizeHubUrl('http://192.168.1.4:8080').toString(),
        'http://192.168.1.4:8080',
      );
    });

    test('a scheme that is already there is not doubled up', () {
      // Prepending `https://` to `ftp://chordia.dev` yields a URL whose host parses as `ftp`,
      // which would then be offered back as if it were what the user meant.
      expect(normalizeHubUrl('ftp://chordia.dev'), isNull);
      expect(normalizeHubUrl(''), isNull);
      expect(normalizeHubUrl('   '), isNull);
    });
  });

  group('probe candidates', () {
    test('the typed origin is tried first, then the api. host', () {
      expect(
        probeCandidates(
          Uri.parse('https://chordia.dev'),
        ).map((u) => u.toString()),
        ['https://chordia.dev', 'https://api.chordia.dev'],
      );
    });

    test('an api. host falls back to the bare host', () {
      expect(
        probeCandidates(
          Uri.parse('https://api.chordia.dev'),
        ).map((u) => u.toString()),
        ['https://api.chordia.dev', 'https://chordia.dev'],
      );
    });

    test('the port is carried onto the alternate candidate', () {
      expect(
        probeCandidates(
          Uri.parse('http://nas.local:8080'),
        ).map((u) => u.toString()),
        ['http://nas.local:8080', 'http://api.nas.local:8080'],
      );
    });
  });

  group('HubProbe', () {
    test('resolves the website address to the api host beside it', () async {
      final asked = <Uri>[];
      final probe = HubProbe(
        allowInsecureHubs: false,
        fetch: (url) async {
          asked.add(url);
          if (url.host != 'api.chordia.dev') throw Exception('no');
          return _instance('chordia.dev');
        },
      );

      final result = await probe.probe('chordia.dev');
      expect(result.url.toString(), 'https://api.chordia.dev');
      expect(result.info.name, 'chordia.dev');
      expect(asked.map((u) => u.host), ['chordia.dev', 'api.chordia.dev']);
    });

    test('a server that answers something else is not a hub', () async {
      // A router's login page returns a cheerful 200. Treating that as a Chordia Hub would strand
      // the user on a sign-in form that can never work.
      final probe = HubProbe(
        allowInsecureHubs: false,
        fetch: (url) async => throw const JsonShapeException('an object', null),
      );
      await expectLater(
        probe.probe('chordia.dev'),
        throwsA(
          isA<HubProbeException>().having(
            (e) => e.failure,
            'failure',
            HubProbeFailure.unreachable,
          ),
        ),
      );
    });

    test('a release build refuses a cleartext hub without asking it', () async {
      var asked = false;
      final probe = HubProbe(
        allowInsecureHubs: false,
        fetch: (url) async {
          asked = true;
          return _instance('nope');
        },
      );
      await expectLater(
        probe.probe('http://chordia.example.com'),
        throwsA(
          isA<HubProbeException>().having(
            (e) => e.failure,
            'failure',
            HubProbeFailure.insecure,
          ),
        ),
      );
      // Refused before the request, not after: a typo must not put a password on the wire even
      // once to find out whether the address was real.
      expect(asked, isFalse);
    });

    test('the dev flavour may reach a cleartext hub', () async {
      final probe = HubProbe(
        allowInsecureHubs: true,
        fetch: (url) async => _instance('dev'),
      );
      final result = await probe.probe('http://chordia.example.com');
      expect(result.url.scheme, 'http');
    });

    test('loopback is never treated as cleartext-over-a-network', () async {
      final probe = HubProbe(
        allowInsecureHubs: false,
        fetch: (url) async => _instance('local'),
      );
      final result = await probe.probe('http://localhost:8080');
      expect(result.url.toString(), 'http://localhost:8080');
      expect(isInsecureRemote(Uri.parse('http://localhost:8080')), isFalse);
      expect(isInsecureRemote(Uri.parse('http://nas.lan')), isTrue);
    });
  });

  group('login union', () {
    test('an ordinary login decodes to a session', () {
      final outcome = readLoginOutcome({
        'tokens': _tokensJson,
        'user': _userJson,
      });
      expect(outcome, isA<LoginAuthenticated>());
      expect(
        (outcome as LoginAuthenticated).response.tokens.accessToken,
        'access',
      );
    });

    test('an mfa challenge decodes to the second step', () {
      final outcome = readLoginOutcome({
        'mfa_required': true,
        'mfa_token': 'challenge-token',
      });
      expect(outcome, isA<LoginMfaRequired>());
      expect((outcome as LoginMfaRequired).mfaToken, 'challenge-token');
    });

    test('mfa_required false takes the session branch', () {
      // The flag is present and false on hubs that always send it. Branching on presence rather
      // than on the value would send everybody to a code screen they cannot answer.
      final outcome = readLoginOutcome({
        'mfa_required': false,
        'tokens': _tokensJson,
        'user': _userJson,
      });
      expect(outcome, isA<LoginAuthenticated>());
    });

    test('a challenge without a token is a shape error, not a session', () {
      expect(
        () => readLoginOutcome({'mfa_required': true}),
        throwsA(isA<JsonShapeException>()),
      );
    });
  });

  group('SecureSessionStore', () {
    test('writes only the refresh token, under a per-hub key', () async {
      final secrets = MemorySecretStore();
      final store = SecureSessionStore(secrets);

      await store.write(
        'hub-a',
        const Session(
          accessToken: 'access-jwt',
          refreshToken: 'refresh-opaque',
          expiresAt: 1234,
        ),
      );

      final raw = secrets.values['chordia_auth::hub-a'];
      expect(raw, isNotNull);
      expect(raw, contains('refresh-opaque'));
      // The access token is short-lived and re-derivable; a second copy of a credential on disk
      // buys one saved round trip an hour.
      expect(raw, isNot(contains('access-jwt')));
    });

    test(
      'a restored session is already stale, so the first use refreshes',
      () async {
        final secrets = MemorySecretStore();
        final store = SecureSessionStore(secrets);
        await store.write(
          'hub-a',
          const Session(
            accessToken: 'access-jwt',
            refreshToken: 'refresh-opaque',
            expiresAt: 9999999999999,
          ),
        );

        final restored = await store.read('hub-a');
        expect(restored!.refreshToken, 'refresh-opaque');
        expect(restored.accessToken, isEmpty);
        expect(restored.expiresWithin(Duration.zero, now: 0), isTrue);
      },
    );

    test('sessions do not leak between hubs', () async {
      final secrets = MemorySecretStore();
      final store = SecureSessionStore(secrets);
      await store.write('hub-a', const _AnySession());
      expect(await store.read('hub-b'), isNull);
      await store.clear('hub-a');
      expect(await store.read('hub-a'), isNull);
    });

    test('an unreadable record reads as no session and is swept', () async {
      final secrets = MemorySecretStore()
        ..values['chordia_auth::hub-a'] = 'not json';
      final store = SecureSessionStore(secrets);
      expect(await store.read('hub-a'), isNull);
      expect(secrets.values, isEmpty);
    });
  });

  group('SecretsHubRegistry', () {
    Hub hub(String host) => Hub(
      id: Hub.idFor(Uri.parse('https://$host')),
      url: Uri.parse('https://$host'),
      name: host,
      addedAt: 1,
    );

    test('adding a hub makes it active and survives a reload', () async {
      final secrets = MemorySecretStore();
      final registry = SecretsHubRegistry(secrets);

      await registry.add(hub('one.example'));
      final snapshot = await SecretsHubRegistry(secrets).list();
      expect(snapshot.hubs.map((h) => h.name), ['one.example']);
      expect(snapshot.active?.name, 'one.example');
    });

    test(
      'adding the same address twice replaces rather than duplicates',
      () async {
        final registry = SecretsHubRegistry(MemorySecretStore());
        await registry.add(hub('one.example'));
        final snapshot = await registry.add(hub('one.example'));
        expect(snapshot.hubs, hasLength(1));
      },
    );

    test('removing the active hub promotes a survivor', () async {
      final registry = SecretsHubRegistry(MemorySecretStore());
      await registry.add(hub('one.example'));
      await registry.add(hub('two.example'));
      final snapshot = await registry.remove(hub('two.example').id);
      // Being dropped onto "choose a server" with exactly one server listed is a dead end.
      expect(snapshot.active?.name, 'one.example');
    });

    test('setActive ignores an id that is not in the registry', () async {
      final registry = SecretsHubRegistry(MemorySecretStore());
      await registry.add(hub('one.example'));
      final snapshot = await registry.setActive('nonsense');
      expect(snapshot.active?.name, 'one.example');
    });
  });

  group('the auth gate', () {
    Hub theHub() => Hub(
      id: Hub.idFor(Uri.parse('https://api.example')),
      url: Uri.parse('https://api.example'),
      name: 'Example',
      addedAt: 1,
    );

    testWidgets('a launch with no session lands on sign-in', (tester) async {
      await _pumpApp(tester, MemorySecretStore());
      expect(find.byType(SignInScreen), findsOneWidget);
    });

    testWidgets('a launch with a stored session lands in the app', (
      tester,
    ) async {
      final secrets = MemorySecretStore();
      final hub = theHub();
      await SecretsHubRegistry(secrets).add(hub);
      await SecureSessionStore(secrets).write(
        hub.id,
        const Session(
          accessToken: '',
          refreshToken: 'refresh-opaque',
          expiresAt: 0,
        ),
      );

      await _pumpApp(tester, secrets);

      // The whole point of the resolving state: a session that is only on disk still counts, so
      // nobody is shown a sign-in form for an account the app is holding credentials for.
      expect(find.byType(SignInScreen), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });

  group('BrowserHandoff', () {
    test('a link that launched the app finishes the flow', () async {
      // The Android case: the browser hop relaunched a killed app, so the verifier is only in the
      // keystore and the callback is already waiting before anything is listening.
      final secrets = MemorySecretStore();
      final exchanged = <(String, String)>[];
      final handoff = BrowserHandoff(
        hubId: 'hub-a',
        secrets: secrets,
        links: _FakeLinks(
          initial: Uri.parse('chordia://auth/callback?code=one-time'),
        ),
        launcher: (_) async => true,
        entropy: Random(1),
        clock: () => 1000,
        exchange: ({required code, required verifier}) async {
          exchanged.add((code, verifier));
          return _authResponse;
        },
      );

      await handoff.start(frontendUrl: Uri.parse('https://chordia.example'));
      final link = await handoff.callbacks().first;
      expect(await handoff.complete(link), isNotNull);
      expect(exchanged.single.$1, 'one-time');
      expect(exchanged.single.$2, isNotEmpty);
      // Single-use on this side too: the code it pairs with is already spent.
      expect(secrets.values, isEmpty);
    });

    test('a replayed link finds nothing pending and does nothing', () async {
      final handoff = _handoff(MemorySecretStore());
      expect(
        await handoff.complete(Uri.parse('chordia://auth/callback?code=x')),
        isNull,
      );
    });

    test('a verifier older than the window is abandoned', () async {
      final secrets = MemorySecretStore();
      var now = 0;
      final handoff = BrowserHandoff(
        hubId: 'hub-a',
        secrets: secrets,
        links: _FakeLinks(),
        launcher: (_) async => true,
        entropy: Random(2),
        clock: () => now,
        exchange: ({required code, required verifier}) async =>
            throw StateError('must not exchange a stale verifier'),
      );
      await handoff.start(frontendUrl: Uri.parse('https://chordia.example'));
      now = BrowserHandoff.pendingLifetime.inMilliseconds + 1;
      expect(
        await handoff.complete(Uri.parse('chordia://auth/callback?code=x')),
        isNull,
      );
    });

    test('a 401 from the exchange is reported as retryable expiry', () async {
      final secrets = MemorySecretStore();
      final handoff = BrowserHandoff(
        hubId: 'hub-a',
        secrets: secrets,
        links: _FakeLinks(),
        launcher: (_) async => true,
        entropy: Random(3),
        clock: () => 0,
        exchange: ({required code, required verifier}) async =>
            throw const ApiException(
              status: 401,
              title: 'nope',
              method: 'POST',
              path: '/v1/auth/desktop/exchange',
            ),
      );
      await handoff.start(frontendUrl: Uri.parse('https://chordia.example'));
      await expectLater(
        handoff.complete(Uri.parse('chordia://auth/callback?code=x')),
        throwsA(
          isA<BrowserHandoffException>().having(
            (e) => e.failure,
            'failure',
            BrowserHandoffFailure.expired,
          ),
        ),
      );
    });

    test('a hub with no website address cannot hand off', () async {
      final secrets = MemorySecretStore();
      final handoff = _handoff(secrets);
      await expectLater(
        handoff.start(frontendUrl: null),
        throwsA(
          isA<BrowserHandoffException>().having(
            (e) => e.failure,
            'failure',
            BrowserHandoffFailure.noFrontend,
          ),
        ),
      );
      expect(secrets.values, isEmpty);
    });

    test('a browser that will not open leaves no verifier behind', () async {
      final secrets = MemorySecretStore();
      final handoff = BrowserHandoff(
        hubId: 'hub-a',
        secrets: secrets,
        links: _FakeLinks(),
        launcher: (_) async => false,
        entropy: Random(4),
        clock: () => 0,
        exchange: ({required code, required verifier}) async => _authResponse,
      );
      await expectLater(
        handoff.start(frontendUrl: Uri.parse('https://chordia.example')),
        throwsA(isA<BrowserHandoffException>()),
      );
      expect(secrets.values, isEmpty);
    });

    test(
      'a launch link replayed onto the live stream is only seen once',
      () async {
        final link = Uri.parse('chordia://auth/callback?code=one-time');
        final handoff = BrowserHandoff(
          hubId: 'hub-a',
          secrets: MemorySecretStore(),
          links: _FakeLinks(initial: link, live: [link]),
          launcher: (_) async => true,
          entropy: Random(5),
          clock: () => 0,
          exchange: ({required code, required verifier}) async => _authResponse,
        );
        expect(await handoff.callbacks().toList(), [link]);
      },
    );
  });
}

/// Boots the real app against an in-memory keystore.
///
/// No `pumpAndSettle`: the resolving screen spins forever by design, so settling never arrives.
/// A handful of pumps is enough — the only asynchrony between launch and a decision is a keystore
/// read that resolves in a microtask here.
Future<void> _pumpApp(WidgetTester tester, MemorySecretStore secrets) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            flavor: 'test',
            defaultHubUrl: 'https://api.example',
            allowInsecureHubs: false,
          ),
        ),
        translationsProvider.overrideWith((ref) => translations),
        secretStoreProvider.overrideWithValue(secrets),
        deepLinkSourceProvider.overrideWithValue(_FakeLinks()),
      ],
      child: const ChordiaApp(),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

BrowserHandoff _handoff(SecretStore secrets) => BrowserHandoff(
  hubId: 'hub-a',
  secrets: secrets,
  links: _FakeLinks(),
  launcher: (_) async => true,
  entropy: Random(0),
  clock: () => 0,
  exchange: ({required code, required verifier}) async => _authResponse,
);

class _FakeLinks implements DeepLinkSource {
  _FakeLinks({this.initial, this.live = const []});

  final Uri? initial;
  final List<Uri> live;

  @override
  Future<Uri?> initialLink() async => initial;

  @override
  Stream<Uri> links() => Stream.fromIterable(live);
}

/// A session whose contents no test looks at.
class _AnySession extends Session {
  const _AnySession()
    : super(accessToken: 'a', refreshToken: 'r', expiresAt: 0);
}

InstanceInfo _instance(String name) => InstanceInfo(
  discordOauth: false,
  frontendUrl: 'https://$name',
  name: name,
  socialEnabled: true,
  version: '1.0.0',
);

const _tokensJson = {
  'access_token': 'access',
  'refresh_token': 'refresh',
  'access_expires_at': 1700000000000,
};

const _userJson = {
  'created_at': 1600000000000,
  'display_name': 'Nina',
  'handle': 'nina',
  'id': 'user-1',
};

final _authResponse = AuthResponse.fromJson({
  'tokens': _tokensJson,
  'user': _userJson,
});
