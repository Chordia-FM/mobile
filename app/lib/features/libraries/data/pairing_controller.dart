import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_net/chordia_net.dart';
import 'package:flutter/foundation.dart';

import 'libraries_api.dart';
import 'pairing_transport.dart';

/// Where the pairing wizard is.
///
/// Each value is a screen the person is looking at, not an internal phase — which is why there is
/// no "working" step: work happens inside a step and is reported by [PairingController.busy], so
/// the explanation of what is being done stays on screen while it is being done.
enum PairingStep {
  /// Waiting for the setup link the library server printed.
  link,

  /// The server signed its own certificate; it has to be confirmed before anything is sent.
  trust,

  /// The ticket is being handed over.
  claiming,

  /// Paired. Naming the first library on it.
  naming,

  /// Done, with a library to open.
  done,
}

/// Why pairing stopped, when it stopped for a reason worth a specific sentence.
///
/// A generic "something went wrong" is the wrong answer for every one of these: each has a
/// different next action, and the whole point of the wizard is that pairing a home server from a
/// phone should not feel like debugging a protocol.
enum PairingFailure {
  /// The link is not a setup link.
  badLink,

  /// Nothing answered at that address.
  unreachable,

  /// The server is already paired with an account, so its setup token is gone.
  alreadyPaired,

  /// The server rejected the setup token — a link is single-use.
  refused,

  /// The one-time pass expired before the server used it.
  ticketExpired,

  /// The Hub would not mint a ticket, or would not register the library.
  hubRefused,
}

/// Drives pairing a library server from a phone.
///
/// The shape of the flow is forced by one rule: the library server never sees the session token.
/// The Hub mints a ticket that authorises exactly one call on exactly one endpoint and lives two
/// minutes; the phone hands that to the server; the server trades it with the Hub for its own
/// credentials. Everything else in here — the certificate confirmation, the expiry handling — is
/// what that rule costs, and each part is a step the wizard explains rather than a failure it
/// reports afterwards.
class PairingController extends ChangeNotifier {
  PairingController({
    required LibrariesApi hub,
    required PairingTransport transport,
    DateTime Function() clock = DateTime.now,
  }) : _hub = hub,
       _transport = transport,
       _clock = clock;

  final LibrariesApi _hub;
  final PairingTransport _transport;
  final DateTime Function() _clock;

  var _step = PairingStep.link;
  var _busy = false;
  PairingFailure? _failure;
  Object? _error;
  bool _disposed = false;

  SetupLink? _link;
  CertFingerprint? _fingerprint;
  String? _ticket;
  DateTime? _ticketExpiresAt;
  String? _serverId;
  LibrarySummary? _library;

  PairingStep get step => _step;

  /// A call is in flight. The step does not change while this is true, so the sentence explaining
  /// what is happening stays on screen for as long as it is happening.
  bool get busy => _busy;

  PairingFailure? get failure => _failure;

  /// The underlying error, for the cases with no [PairingFailure] of their own.
  Object? get error => _error;

  /// The certificate the person is being asked to confirm, or has confirmed.
  CertFingerprint? get fingerprint => _fingerprint;

  /// The server's address, for the sentences that name it.
  Uri? get serverBase => _link?.base;

  /// The paired server's id, once the handshake has gone through.
  String? get serverId => _serverId;

  /// The library that was registered, once there is one.
  LibrarySummary? get library => _library;

  /// Reads a pasted setup link and gets as far as it can without asking anything else.
  ///
  /// A server on plain HTTP or behind a real certificate goes straight to the handshake; a
  /// self-signed one stops at [PairingStep.trust], because sending a credential to a certificate
  /// nobody has vouched for is the one thing this flow must not do quietly.
  Future<void> submitLink(String raw) async {
    final link = SetupLink.tryParse(raw);
    if (link == null) {
      _fail(PairingFailure.badLink);
      return;
    }
    _link = link;
    _fingerprint = null;
    await _run(() async {
      final probe = await _transport.probe(link.base);
      if (probe.alreadyPaired) {
        _fail(PairingFailure.alreadyPaired);
        return;
      }
      _fingerprint = probe.fingerprint;
      if (probe.fingerprint != null) {
        _step = PairingStep.trust;
        return;
      }
      await _claim();
    }, onError: (error) => _fail(PairingFailure.unreachable, error));
  }

  /// The person has confirmed the certificate. Nothing is sent before this returns.
  Future<void> trustCertificate() async {
    if (_step != PairingStep.trust) return;
    await _run(
      _claim,
      onError: (error) => _fail(PairingFailure.unreachable, error),
    );
  }

  /// Another go after a failure, from wherever it stopped.
  ///
  /// An expired ticket retries the handshake with a fresh one, which is why the failure is worth
  /// naming: the fix is a button, not starting over.
  Future<void> retry() async {
    _failure = null;
    _error = null;
    switch (_step) {
      case PairingStep.link:
      case PairingStep.trust:
      case PairingStep.claiming:
        if (_link == null) {
          _step = PairingStep.link;
          _notify();
          return;
        }
        await _run(
          _claim,
          onError: (error) => _fail(PairingFailure.unreachable, error),
        );
      case PairingStep.naming:
      case PairingStep.done:
        _notify();
    }
  }

  /// Registers the first logical library on the newly paired server.
  Future<void> registerLibrary(String name) async {
    final serverId = _serverId;
    final trimmed = name.trim();
    if (serverId == null || trimmed.isEmpty) return;
    await _run(() async {
      _library = await _hub.createLibrary(
        CreateLibraryRequest(name: trimmed, serverId: serverId),
      );
      _step = PairingStep.done;
    }, onError: (error) => _fail(PairingFailure.hubRefused, error));
  }

  /// Back to the beginning, keeping nothing. Used after a failure the person has to fix on the
  /// server side, where retrying the same link cannot work.
  void startOver() {
    _step = PairingStep.link;
    _failure = null;
    _error = null;
    _link = null;
    _fingerprint = null;
    _ticket = null;
    _ticketExpiresAt = null;
    _serverId = null;
    _library = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Mints a ticket if the one in hand is missing or spent, then hands it over.
  Future<void> _claim() async {
    final link = _link;
    if (link == null) return;
    _step = PairingStep.claiming;
    _notify();

    if (_ticket == null || _expired) {
      // A ticket is minted as late as possible and used immediately. Minting it earlier — when
      // the wizard opened, say — is what would let it die while somebody reads the certificate
      // explanation, and an expired credential is indistinguishable from a rejected one at the
      // far end.
      try {
        // The clock is read BEFORE the call, not after: the Hub starts the two minutes when it
        // issues the ticket, so the round trip back to the phone is spent out of that window.
        // Dating the expiry from the answer would make a slow connection look like a fresh pass.
        final requestedAt = _clock();
        final minted = await _hub.mintPairTicket();
        _ticket = minted.ticket;
        _ticketExpiresAt = requestedAt.add(
          Duration(seconds: minted.expiresInSecs),
        );
      } on Object catch (error) {
        _fail(PairingFailure.hubRefused, error);
        return;
      }
    }

    if (_expired) {
      // Between minting and sending, which can happen on a slow connection. Reported rather than
      // silently re-minted: a loop that quietly re-mints forever would hide a clock that is wrong.
      _fail(PairingFailure.ticketExpired);
      return;
    }

    try {
      _serverId = await _transport.claim(
        base: link.base,
        pin: _fingerprint,
        ticket: _ticket!,
        setupToken: link.token,
      );
      _ticket = null;
      _ticketExpiresAt = null;
      _step = PairingStep.naming;
    } on ApiException catch (error) {
      // The library rejects a spent setup token itself (401); a ticket the HUB refuses reaches it
      // as a failed upstream call, which it reports as a bad gateway. Two different fixes, so two
      // different sentences.
      _ticket = null;
      _ticketExpiresAt = null;
      _fail(
        error.status == 401
            ? PairingFailure.refused
            : error.status == 502 || error.status == 504
            ? PairingFailure.ticketExpired
            : PairingFailure.unreachable,
        error,
      );
    }
  }

  bool get _expired {
    final expiry = _ticketExpiresAt;
    return expiry == null || !_clock().isBefore(expiry);
  }

  Future<void> _run(
    Future<void> Function() body, {
    required void Function(Object error) onError,
  }) async {
    _busy = true;
    _failure = null;
    _error = null;
    _notify();
    try {
      await body();
    } on Object catch (error) {
      if (_disposed) return;
      onError(error);
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _fail(PairingFailure failure, [Object? error]) {
    _failure = failure;
    _error = error;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
