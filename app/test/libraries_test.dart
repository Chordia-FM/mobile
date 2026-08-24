import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/features/libraries/data/libraries_api.dart';
import 'package:chordia_mobile/features/libraries/data/libraries_providers.dart';
import 'package:chordia_mobile/features/libraries/data/pairing_controller.dart';
import 'package:chordia_mobile/features/libraries/data/pairing_transport.dart';
import 'package:chordia_mobile/features/libraries/libraries_home_screen.dart';
import 'package:chordia_mobile/features/libraries/library_icons.dart';
import 'package:chordia_mobile/features/libraries/library_manage_screen.dart';
import 'package:chordia_mobile/features/libraries/overrides_screen.dart';
import 'package:chordia_mobile/features/library/data/library_api.dart';
import 'package:chordia_mobile/features/library/data/library_providers.dart';
import 'package:chordia_mobile/features/library/library_detail_screen.dart';
import 'package:chordia_mobile/features/library/library_screen.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_mobile/i18n/translations_provider.dart';
import 'package:chordia_net/chordia_net.dart';
import 'package:chordia_db/chordia_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loaded once, in real async: `testWidgets` runs inside a fake-async zone where an asset read
/// never completes, so the catalogs have to be in hand before the first pump.
late Translations translations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    translations = await Translations.load('en', bundle: rootBundle);
  });

  group('reading the link a library server printed', () {
    test('a setup link splits into an origin and a one-time code', () {
      final link = SetupLink.tryParse('https://192.168.1.20:8443/setup/abc123');
      expect(link, isNotNull);
      expect(link!.base, Uri.parse('https://192.168.1.20:8443'));
      expect(link.token, 'abc123');
    });

    test('a server behind a path prefix keeps its prefix', () {
      // A library reached through a reverse proxy at /library has its API there too; dropping the
      // prefix would look for `/v1/pairing/claim` at the root of somebody's website.
      final link = SetupLink.tryParse('https://home.example/library/setup/xyz');
      expect(link!.base, Uri.parse('https://home.example/library'));
      expect(link.token, 'xyz');
    });

    test('surrounding whitespace from a copied terminal line is ignored', () {
      final link = SetupLink.tryParse('  http://localhost:8443/setup/tok  \n');
      expect(link!.token, 'tok');
      expect(link.base, Uri.parse('http://localhost:8443'));
    });

    test('anything that is not a setup link is refused', () {
      // A bare origin is the dangerous one: accepting it would send a pairing ticket to a server
      // that never asked to be paired.
      expect(SetupLink.tryParse('https://192.168.1.20:8443'), isNull);
      expect(SetupLink.tryParse('https://192.168.1.20:8443/setup/'), isNull);
      expect(SetupLink.tryParse('ftp://host/setup/tok'), isNull);
      expect(SetupLink.tryParse('not a url'), isNull);
      expect(SetupLink.tryParse(''), isNull);
    });
  });

  // Each of these presses the control a person would press and checks the call it makes. Every one
  // of them covers something that was finished code with no way in: `LibrariesApi.remove` had no
  // callers, `LibraryDetailScreen` was never constructed, and `addPin`/`removePin`/`reorderPins`
  // had none between them.
  group('a library opens onto its music', () {
    testWidgets('tapping one opens the catalog, not the settings', (
      tester,
    ) async {
      await _pumpLibraries(tester, const LibrariesHomeScreen());

      await tester.tap(find.text('Hi-Fi Archive'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // A library is only interesting as the music inside it. Opening settings on a tap left the
      // catalog screen with no route to it at all.
      expect(find.byType(LibraryDetailScreen), findsOneWidget);
      expect(find.byType(LibraryManageScreen), findsNothing);
    });

    testWidgets('and its menu still reaches the settings', (tester) async {
      await _pumpLibraries(tester, const LibrariesHomeScreen());

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(_t(LibraryKeys.manageTitle)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(LibraryManageScreen), findsOneWidget);
    });

    testWidgets('an owner can remove one', (tester) async {
      final api = await _pumpLibraries(tester, const LibrariesHomeScreen());

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(_t(LibraryKeys.editRemoveTitle)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.text(_t(LibraryKeys.editDeleteConfirmConfirmLabel)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.removed, ['lib-1']);
    });
  });

  group('a library wears the icon its owner chose', () {
    testWidgets('the manage page opens a picker and saves the slug', (
      tester,
    ) async {
      final api = await _pumpLibraries(
        tester,
        const LibraryManageScreen(libraryId: 'lib-1', owned: true),
      );

      await tester.tap(find.text(_t(LibraryKeys.editIconLabel)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_t(LibraryKeys.editIconTabEmoji)), findsOneWidget);
      // Filtering by an intent rather than a name, which is the whole point of the keywords.
      await tester.enterText(find.byType(TextField).last, 'gym');
      await tester.pump();
      await tester.tap(find.byIcon(libraryIcons['barbell']!));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.updates.single.$2.icon, 'barbell');
    });
  });

  group('an override can be undone from the list it appears in', () {
    testWidgets('each row resets in place', (tester) async {
      final overrides = _FakeOverridesApi();
      await _pumpLibraries(
        tester,
        const OverridesScreen(libraryId: 'lib-1'),
        overrides: overrides,
      );

      await tester.tap(find.byIcon(Icons.settings_backup_restore_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(_t(LibraryKeys.metadataOverridesReset)).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Reaching this only through the editor sheet meant scrolling past every field to a text
      // button at the bottom, for the action this page exists to offer.
      expect(overrides.cleared, [('album', 'al-1')]);
    });
  });

  group('the pinned shelf can be changed from the phone', () {
    testWidgets('a pin can be moved and unpinned', (tester) async {
      final pins = _FakePinsApi([_pin('a', 'Alpha'), _pin('b', 'Beta')]);
      await _pumpLibraries(tester, const LibraryScreen(), pins: pins);

      await tester.longPress(find.text('Alpha'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(_t(CommonKeys.actionsMoveDown)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The Hub has no "move one pin" call — the whole shelf goes up in its new order.
      expect(pins.orders.single.map((pin) => pin.id).toList(), ['b', 'a']);

      await tester.longPress(find.text('Beta'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(_t(CommonKeys.actionsUnpin)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(pins.removed, [(PinKind.playlist, 'b')]);
    });
  });

  group('the pairing state machine', () {
    test(
      'a server with a trusted certificate pairs without a trust step',
      () async {
        final hub = _FakeLibrariesApi();
        final transport = _FakeTransport();
        final pairing = PairingController(hub: hub, transport: transport);

        await pairing.submitLink('http://localhost:8443/setup/tok');

        expect(pairing.step, PairingStep.naming);
        expect(pairing.failure, isNull);
        expect(pairing.serverId, 'srv-1');
        // The TICKET, never the session token. This is the whole reason the flow has three parties.
        expect(transport.claimedTickets, ['ticket-1']);
        expect(transport.claimedSetupTokens, ['tok']);

        await pairing.registerLibrary('  My Music  ');
        expect(pairing.step, PairingStep.done);
        expect(pairing.library?.name, 'My Music');
        expect(hub.created.single.serverId, 'srv-1');
      },
    );

    test(
      'a self-signed server stops for confirmation before anything is sent',
      () async {
        final hub = _FakeLibrariesApi();
        final transport = _FakeTransport()..fingerprint = _fingerprint('ab');
        final pairing = PairingController(hub: hub, transport: transport);

        await pairing.submitLink('https://192.168.1.20:8443/setup/tok');

        expect(pairing.step, PairingStep.trust);
        expect(pairing.fingerprint?.hex, _fingerprint('ab').hex);
        // Nothing at all has gone to the server, and no ticket has been minted for it: sending a
        // credential to a certificate nobody has vouched for is the one thing this must not do.
        expect(transport.claimedTickets, isEmpty);
        expect(hub.ticketsMinted, 0);

        await pairing.trustCertificate();
        expect(pairing.step, PairingStep.naming);
        // The confirmed certificate is what the handshake was pinned to.
        expect(transport.claimedPins.single?.hex, _fingerprint('ab').hex);
      },
    );

    test('a server that already belongs to an account says so', () async {
      final hub = _FakeLibrariesApi();
      final transport = _FakeTransport()..alreadyPaired = true;
      final pairing = PairingController(hub: hub, transport: transport);

      await pairing.submitLink('http://localhost:8443/setup/tok');

      expect(pairing.failure, PairingFailure.alreadyPaired);
      expect(transport.claimedTickets, isEmpty);
    });

    test('a link that is not a setup link never reaches the network', () async {
      final hub = _FakeLibrariesApi();
      final transport = _FakeTransport();
      final pairing = PairingController(hub: hub, transport: transport);

      await pairing.submitLink('https://192.168.1.20:8443');

      expect(pairing.failure, PairingFailure.badLink);
      expect(transport.probes, isEmpty);
    });

    test('a server that does not answer is named as unreachable', () async {
      final hub = _FakeLibrariesApi();
      final transport = _FakeTransport()..probeFails = true;
      final pairing = PairingController(hub: hub, transport: transport);

      await pairing.submitLink('http://localhost:8443/setup/tok');

      expect(pairing.failure, PairingFailure.unreachable);
      expect(pairing.step, PairingStep.link);
    });

    test(
      'a spent setup link is reported as refused, not as a network problem',
      () async {
        final hub = _FakeLibrariesApi();
        final transport = _FakeTransport()..claimStatus = 401;
        final pairing = PairingController(hub: hub, transport: transport);

        await pairing.submitLink('http://localhost:8443/setup/tok');

        // A link works once. Retrying it cannot help, and the wizard says so rather than offering
        // a button that fails the same way.
        expect(pairing.failure, PairingFailure.refused);
      },
    );

    test(
      'a one-time pass that expires before it is used is retried, not lost',
      () async {
        var now = DateTime(2026, 8, 22, 12);
        final hub = _FakeLibrariesApi()
          // The Hub round trip takes longer than the pass lives — a slow mobile connection, or a
          // phone whose clock has just been corrected.
          ..onMint = () => now = now.add(const Duration(seconds: 200));
        final transport = _FakeTransport();
        final pairing = PairingController(
          hub: hub,
          transport: transport,
          clock: () => now,
        );

        await pairing.submitLink('http://localhost:8443/setup/tok');

        expect(pairing.failure, PairingFailure.ticketExpired);
        // The dead credential is never sent. Presenting it would be refused at the far end as an
        // indistinguishable failure, and would burn the setup token doing it.
        expect(transport.claimedTickets, isEmpty);
        expect(hub.ticketsMinted, 1);

        // The fix is a button, not starting over: the link is still good.
        hub.onMint = null;
        await pairing.retry();

        expect(pairing.failure, isNull);
        expect(pairing.step, PairingStep.naming);
        expect(hub.ticketsMinted, 2);
        expect(transport.claimedTickets, ['ticket-2']);
      },
    );

    test(
      'a Hub that will not mint a ticket is not blamed on the server',
      () async {
        final hub = _FakeLibrariesApi()..mintFails = true;
        final transport = _FakeTransport();
        final pairing = PairingController(hub: hub, transport: transport);

        await pairing.submitLink('http://localhost:8443/setup/tok');

        expect(pairing.failure, PairingFailure.hubRefused);
        expect(transport.claimedTickets, isEmpty);
      },
    );

    test(
      'starting over forgets the link, the certificate and the ticket',
      () async {
        final hub = _FakeLibrariesApi();
        final transport = _FakeTransport()..fingerprint = _fingerprint('cd');
        final pairing = PairingController(hub: hub, transport: transport);

        await pairing.submitLink('https://192.168.1.20:8443/setup/tok');
        expect(pairing.step, PairingStep.trust);

        pairing.startOver();

        expect(pairing.step, PairingStep.link);
        expect(pairing.fingerprint, isNull);
        expect(pairing.serverBase, isNull);
        expect(pairing.failure, isNull);
        // With nothing to retry, retry cannot send anything.
        await pairing.retry();
        expect(transport.claimedTickets, isEmpty);
      },
    );

    test('an unnamed library is not created', () async {
      final hub = _FakeLibrariesApi();
      final pairing = PairingController(hub: hub, transport: _FakeTransport());

      await pairing.submitLink('http://localhost:8443/setup/tok');
      await pairing.registerLibrary('   ');

      expect(hub.created, isEmpty);
      expect(pairing.step, PairingStep.naming);
    });
  });
}

CertFingerprint _fingerprint(String seed) =>
    CertFingerprint.tryParse(seed * 32)!;

class _FakeTransport implements PairingTransport {
  CertFingerprint? fingerprint;
  var alreadyPaired = false;
  var probeFails = false;

  /// Non-null makes the claim fail with this HTTP status.
  int? claimStatus;

  final probes = <Uri>[];
  final claimedTickets = <String>[];
  final claimedSetupTokens = <String>[];
  final claimedPins = <CertFingerprint?>[];

  var _servers = 0;

  @override
  Future<ServerProbe> probe(Uri base) async {
    probes.add(base);
    if (probeFails) {
      throw const ApiException(
        status: 0,
        title: 'unreachable',
        method: 'GET',
        path: '/v1/ping',
      );
    }
    return ServerProbe(fingerprint: fingerprint, alreadyPaired: alreadyPaired);
  }

  @override
  Future<String> claim({
    required Uri base,
    required CertFingerprint? pin,
    required String ticket,
    required String setupToken,
  }) async {
    final status = claimStatus;
    if (status != null) {
      throw ApiException(
        status: status,
        title: 'refused',
        method: 'POST',
        path: '/v1/pairing/claim',
      );
    }
    claimedTickets.add(ticket);
    claimedSetupTokens.add(setupToken);
    claimedPins.add(pin);
    return 'srv-${++_servers}';
  }
}

class _FakeLibrariesApi implements LibrariesApi {
  var ticketsMinted = 0;
  var mintFails = false;

  /// Runs while a ticket is being minted, so a test can advance the clock the way a slow round
  /// trip would.
  void Function()? onMint;

  final created = <CreateLibraryRequest>[];

  @override
  Future<PairTicket> mintPairTicket() async {
    ticketsMinted++;
    onMint?.call();
    if (mintFails) {
      throw const ApiException(
        status: 500,
        title: 'no',
        method: 'POST',
        path: '/v1/libraries/pair-ticket',
      );
    }
    return PairTicket(expiresInSecs: 120, ticket: 'ticket-$ticketsMinted');
  }

  @override
  Future<LibrarySummary> createLibrary(CreateLibraryRequest request) async {
    created.add(request);
    return LibrarySummary(
      createdAt: 0,
      id: 'lib-${created.length}',
      name: request.name,
      ownerId: 'me',
      serverId: request.serverId,
      trackCount: 0,
    );
  }

  @override
  Future<CoverageSummary> coverage() => throw UnimplementedError();

  @override
  Future<LibrarySummary> detail(String libraryId) => throw UnimplementedError();

  @override
  Future<List<PublicUser>> friends() => throw UnimplementedError();

  @override
  Future<List<LibrarySummary>> mine() => throw UnimplementedError();

  @override
  Future<void> remove(String libraryId) => throw UnimplementedError();

  @override
  Future<ResolvedServer> resolveServer(String serverId) =>
      throw UnimplementedError();

  @override
  Future<void> revoke(String libraryId, String granteeId) =>
      throw UnimplementedError();

  @override
  Future<void> share(String libraryId, ShareBody body) =>
      throw UnimplementedError();

  @override
  Future<List<LibraryShare>> shares(String libraryId) =>
      throw UnimplementedError();

  @override
  Future<List<LibrarySummary>> sharedWithMe() => throw UnimplementedError();

  @override
  Future<LibrarySummary> update(
    String libraryId,
    UpdateLibraryRequest changes,
  ) => throw UnimplementedError();
}

// ── Widget harness ─────────────────────────────────────────────────────────────

String _t(String key, [Map<String, Object?> args = const {}]) =>
    translations(key, args);

LibrarySummary _library(String id, String name) => LibrarySummary(
  createdAt: 0,
  id: id,
  name: name,
  ownerId: 'me',
  serverId: 'srv-1',
  trackCount: 12,
);

PinnedItem _pin(String id, String name) =>
    PinnedItem(id: id, kind: PinKind.playlist, name: name);

/// Pushes [screen] onto a real navigator, so a screen that pops itself has somewhere to pop to.
Future<_ScreenLibrariesApi> _pumpLibraries(
  WidgetTester tester,
  Widget screen, {
  _FakeOverridesApi? overrides,
  _FakePinsApi? pins,
}) async {
  final api = _ScreenLibrariesApi();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        translationsProvider.overrideWithValue(translations),
        librariesApiProvider.overrideWithValue(api),
        overridesApiProvider.overrideWithValue(
          overrides ?? _FakeOverridesApi(),
        ),
        pinsApiProvider.overrideWithValue(pins ?? _FakePinsApi(const [])),
        // The Library tab's other shelves, so nothing in it reaches for a hub that is not there.
        playlistsProvider.overrideWith((ref) async => const <Playlist>[]),
        smartPlaylistsProvider.overrideWith(
          (ref) async => const <SmartPlaylist>[],
        ),
        downloadedTracksProvider.overrideWith(
          (ref) => Stream.value(const <DownloadedTrack>[]),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: SizedBox.expand())),
    ),
  );

  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  unawaited(
    navigator.push(MaterialPageRoute<void>(builder: (context) => screen)),
  );
  // Fixed frames rather than `pumpAndSettle`: the player ticks twice a second, so a settle never
  // returns anywhere this app's shell is mounted.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return api;
}

/// The library-management calls the SCREENS make, as opposed to the pairing ones above.
class _ScreenLibrariesApi implements LibrariesApi {
  final removed = <String>[];
  final updates = <(String, UpdateLibraryRequest)>[];

  @override
  Future<List<LibrarySummary>> mine() async => [
    _library('lib-1', 'Hi-Fi Archive'),
  ];

  @override
  Future<List<LibrarySummary>> sharedWithMe() async => const [];

  @override
  Future<LibrarySummary> detail(String libraryId) async =>
      _library(libraryId, 'Hi-Fi Archive');

  @override
  Future<LibrarySummary> update(
    String libraryId,
    UpdateLibraryRequest changes,
  ) async {
    updates.add((libraryId, changes));
    return _library(libraryId, changes.name ?? 'Hi-Fi Archive');
  }

  @override
  Future<void> remove(String libraryId) async => removed.add(libraryId);

  @override
  Future<ResolvedServer> resolveServer(String serverId) async => ResolvedServer(
    authorized: true,
    endpoint: ServerEndpoint(
      endpoint: 'https://box.local:8443',
      lastHeartbeat: 0,
      online: true,
      ownerId: 'me',
      serverId: serverId,
      tlsFingerprint: 'ab' * 32,
    ),
  );

  @override
  Future<CoverageSummary> coverage() async => const CoverageSummary(
    albumPct: 0,
    artistPct: 0,
    completeArtists: 0,
    excludedLibraryIds: [],
    includeShared: false,
    ownedRgs: 0,
    pendingArtists: 0,
    perLibrary: [],
    totalRgs: 0,
    touchedArtists: 0,
  );

  @override
  Future<List<LibraryShare>> shares(String libraryId) async => const [];

  @override
  Future<void> share(String libraryId, ShareBody body) async {}

  @override
  Future<void> revoke(String libraryId, String granteeId) async {}

  @override
  Future<List<PublicUser>> friends() async => const [];

  @override
  Future<PairTicket> mintPairTicket() => throw UnimplementedError();

  @override
  Future<LibrarySummary> createLibrary(CreateLibraryRequest request) =>
      throw UnimplementedError();
}

class _FakeOverridesApi implements OverridesApi {
  final cleared = <(String, String)>[];

  @override
  Future<List<LibraryOverrideSummary>> list(String libraryId) async => const [
    LibraryOverrideSummary(
      fields: ['title'],
      id: 'al-1',
      kind: OverrideKind.album,
      name: 'A Renamed Album',
      overrideMain: false,
      updatedAt: 0,
    ),
  ];

  @override
  Future<void> clearAlbum(String libraryId, String albumId) async =>
      cleared.add(('album', albumId));

  @override
  Future<void> clearArtist(String libraryId, String artistId) async =>
      cleared.add(('artist', artistId));

  @override
  Future<void> clearTrack(String libraryId, String trackId) async =>
      cleared.add(('track', trackId));

  @override
  Future<ArtistOverrideView> artist(String libraryId, String artistId) =>
      throw UnimplementedError();

  @override
  Future<AlbumOverrideView> album(String libraryId, String albumId) =>
      throw UnimplementedError();

  @override
  Future<TrackOverrideView> track(String libraryId, String trackId) =>
      throw UnimplementedError();

  @override
  Future<void> putArtist(
    String libraryId,
    String artistId,
    ArtistOverrideInput input,
  ) => throw UnimplementedError();

  @override
  Future<void> putAlbum(
    String libraryId,
    String albumId,
    AlbumOverrideInput input,
  ) => throw UnimplementedError();

  @override
  Future<void> putTrack(
    String libraryId,
    String trackId,
    TrackOverrideInput input,
  ) => throw UnimplementedError();
}

class _FakePinsApi implements PinsApi {
  _FakePinsApi(this._shelf);

  List<PinnedItem> _shelf;

  final added = <(PinKind, String)>[];
  final removed = <(PinKind, String)>[];
  final orders = <List<PinnedItem>>[];

  @override
  Future<List<PinnedItem>> pins() async => _shelf;

  @override
  Future<void> add(PinKind kind, String id) async => added.add((kind, id));

  @override
  Future<void> remove(PinKind kind, String id) async {
    removed.add((kind, id));
    _shelf = [
      for (final pin in _shelf)
        if (!(pin.kind == kind && pin.id == id)) pin,
    ];
  }

  @override
  Future<void> reorder(List<PinnedItem> order) async {
    orders.add(order);
    _shelf = order;
  }
}
