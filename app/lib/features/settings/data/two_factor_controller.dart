import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/foundation.dart';

import 'settings_api.dart';

/// Where an account is in the two-factor flow.
///
/// Four stages rather than a pair of booleans, because [showingCodes] is a real state and not a
/// decoration: 2FA is already on by then, and the recovery codes are on screen for the only time
/// they ever will be. Collapsing it into [on] is what lets a redraw take them away before they
/// have been written down.
enum TwoFactorStage {
  /// No second factor. The only move is to start enrolling.
  off,

  /// A pending secret exists and its QR is on screen, waiting for a code to confirm it. Nothing
  /// is active yet — abandoning here leaves the account exactly as it was.
  enrolling,

  /// Enrollment succeeded and the recovery codes are being shown. The Hub stores only hashes of
  /// them, so this render is the one chance to keep them.
  showingCodes,

  /// On, with the codes already handed over.
  on,
}

/// The two-factor flow, as a state machine.
///
/// Separate from the screen because the transitions are the part worth being sure about: a wrong
/// one either drops the recovery codes or leaves somebody looking at a QR for a secret the Hub has
/// already discarded.
class TwoFactorController extends ChangeNotifier {
  TwoFactorController({required SecurityApi api, required bool enabled})
    : _api = api,
      _stage = enabled ? TwoFactorStage.on : TwoFactorStage.off;

  final SecurityApi _api;

  TwoFactorStage _stage;
  TotpSetup? _setup;
  List<String>? _codes;
  Object? _error;
  bool _busy = false;
  bool _disposed = false;

  TwoFactorStage get stage => _stage;

  /// The secret and its QR while [stage] is [TwoFactorStage.enrolling].
  TotpSetup? get setup => _setup;

  /// The recovery codes while [stage] is [TwoFactorStage.showingCodes], and never again.
  List<String>? get recoveryCodes => _codes;

  /// Why the last step failed, cleared when the next one starts.
  Object? get error => _error;

  bool get busy => _busy;

  /// Asks the Hub for a pending secret. A no-op unless the account currently has no second
  /// factor — the Hub refuses a second enrollment, and starting one from [TwoFactorStage.on]
  /// would put a QR on screen for a secret that can never be confirmed.
  Future<bool> begin() async {
    if (_stage != TwoFactorStage.off) return false;
    return _step(() async {
      _setup = await _api.beginTotpSetup();
      _stage = TwoFactorStage.enrolling;
    });
  }

  /// Confirms enrollment with a code from the authenticator, turning 2FA on.
  ///
  /// A rejected code leaves the enrollment standing: the pending secret on the Hub is still the
  /// one behind the QR on screen, so the only thing to do is type the next code.
  Future<bool> confirm(String code) async {
    if (_stage != TwoFactorStage.enrolling) return false;
    return _step(() async {
      _codes = await _api.enableTotp(_normalise(code));
      _setup = null;
      _stage = TwoFactorStage.showingCodes;
    });
  }

  /// Dismisses the recovery codes and drops them from memory. 2FA stays on.
  void acknowledgeCodes() {
    if (_stage != TwoFactorStage.showingCodes) return;
    _codes = null;
    _stage = TwoFactorStage.on;
    _notify();
  }

  /// Abandons an enrollment that was never confirmed.
  void cancelEnrollment() {
    if (_stage != TwoFactorStage.enrolling) return;
    _setup = null;
    _error = null;
    _stage = TwoFactorStage.off;
    _notify();
  }

  /// Turns 2FA off, given a current code or a recovery code.
  Future<bool> disable(String code) async {
    if (_stage != TwoFactorStage.on) return false;
    return _step(() async {
      await _api.disableTotp(_normalise(code));
      _codes = null;
      _stage = TwoFactorStage.off;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Runs one transition, keeping [busy] and [error] honest and leaving the stage untouched when
  /// the Hub says no.
  Future<bool> _step(Future<void> Function() run) async {
    _busy = true;
    _error = null;
    _notify();
    try {
      await run();
      return true;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Authenticator apps space their digits and recovery codes are hyphenated. Nobody should fail
  /// a step because they typed what they were shown, so only whitespace goes.
  String _normalise(String code) => code.replaceAll(' ', '').trim();

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
