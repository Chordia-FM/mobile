import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/features/libraries/data/libraries_api.dart';
import 'package:chordia_mobile/features/libraries/data/pairing_controller.dart';
import 'package:chordia_mobile/features/libraries/data/pairing_transport.dart';
import 'package:chordia_net/chordia_net.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
