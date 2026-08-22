import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/providers.dart';
import 'package:chordia_mobile/features/settings/data/settings_api.dart';
import 'package:chordia_mobile/features/settings/data/settings_controller.dart';
import 'package:chordia_mobile/features/settings/data/settings_patch.dart';
import 'package:chordia_mobile/features/settings/data/settings_providers.dart';
import 'package:chordia_mobile/features/settings/data/settings_values.dart';
import 'package:chordia_mobile/features/settings/data/two_factor_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the settings write path', () {
    test('a change is on screen before the Hub has answered', () async {
      final api = _FakeSettingsApi(_settings(normalizeVolume: false));
      final container = _container(api);
      await _load(container);

      // The write is held open, so what the controller reports here is purely the optimistic
      // apply — nothing has come back from the server yet.
      api.blockNext(1);
      final pending = container
          .read(settingsControllerProvider.notifier)
          .patch(const SettingsPatch(normalizeVolume: true));
      expect(_current(container).normalizeVolume, isTrue);

      api.release(0);
      expect(await pending, isTrue);
      expect(_current(container).normalizeVolume, isTrue);
      // The whole document goes up, not a delta: `PUT /v1/me/settings` replaces the blob.
      expect(api.sent?.streamingQuality, QualityProfile.high);
    });

    test('a refused change is put back, with the reason kept', () async {
      final api = _FakeSettingsApi(_settings(normalizeVolume: false))
        ..failure = const ApiException(
          status: 500,
          title: 'Nope',
          method: 'PUT',
          path: '/v1/me/settings',
        );
      final container = _container(api);
      await _load(container);
      final controller = container.read(settingsControllerProvider.notifier);

      expect(
        await controller.patch(const SettingsPatch(normalizeVolume: true)),
        isFalse,
      );
      // Not merely "something": the exact value from before the tap. A revert that restored a
      // stale blob would be as wrong as no revert at all.
      expect(_current(container).normalizeVolume, isFalse);
      expect(_current(container).streamingQuality, QualityProfile.high);
      // Without the failure the screen has nothing to say, and the revert looks like a tap that
      // never registered.
      expect((controller.failure as ApiException?)?.title, 'Nope');
    });

    test('what the Hub actually stored replaces what was sent', () async {
      // The Hub normalises: an accent it does not recognise here comes back as the default.
      final api = _FakeSettingsApi(_settings())
        ..normalise = (sent) =>
            const SettingsPatch(accent: followInstanceAccent).applyTo(sent);
      final container = _container(api);
      await _load(container);

      expect(
        await container
            .read(settingsControllerProvider.notifier)
            .patch(const SettingsPatch(accent: 'not-a-colour')),
        isTrue,
      );
      expect(_current(container).accent, followInstanceAccent);
    });

    test('a failure does not undo an edit made after it', () async {
      final api = _FakeSettingsApi(_settings(normalizeVolume: false));
      final container = _container(api);
      await _load(container);
      final controller = container.read(settingsControllerProvider.notifier);

      api.blockNext(2);
      final first = controller.patch(
        const SettingsPatch(normalizeVolume: true),
      );
      // A second edit lands while the first is still in flight, and supersedes it on screen.
      final second = controller.patch(const SettingsPatch(autoplay: false));

      // The first write comes back refused while the second is still out, which is the only
      // moment at which a revert has something newer than itself to destroy.
      api.failNext = true;
      api.release(0);
      expect(await first, isFalse);

      // Reverting the first here would restore a blob that predates the second, silently undoing
      // a change the user made afterwards.
      expect(_current(container).autoplay, isFalse);
      expect(_current(container).normalizeVolume, isTrue);

      api.release(1);
      expect(await second, isTrue);
    });

    test(
      'a settings blob with no session to read is an error, not a guess',
      () async {
        final container = ProviderContainer(
          overrides: [
            settingsApiProvider.overrideWithValue(null),
            userSettingsProvider.overrideWith((ref) async => null),
          ],
        );
        addTearDown(container.dispose);
        container.listen(settingsControllerProvider, (_, _) {});

        // Rendering defaults here would invite somebody to "change" a setting into a save that
        // overwrites their real settings with this client's guesses.
        await expectLater(
          container.read(settingsControllerProvider.future),
          throwsA(isA<StateError>()),
        );
        expect(
          await container
              .read(settingsControllerProvider.notifier)
              .patch(const SettingsPatch(autoplay: false)),
          isFalse,
        );
      },
    );
  });

  group('a bounded setting is clamped on the write path', () {
    test('the clamps are the contract\'s range', () {
      expect(clampCrossfadeSeconds(-4), 0);
      expect(clampCrossfadeSeconds(6), 6);
      expect(clampCrossfadeSeconds(maxCrossfadeSeconds), maxCrossfadeSeconds);
      expect(clampCrossfadeSeconds(99), maxCrossfadeSeconds);

      expect(clampPreloadCount(-1), 0);
      expect(clampPreloadCount(2), 2);
      expect(clampPreloadCount(50), maxPreloadCount);
    });

    test('a patch cannot carry a value out of range', () async {
      // The clamp lives on the patch rather than on the slider, so a value from anywhere else —
      // another control, a blob written by an older build — is still brought inside the range
      // before it reaches the Hub.
      final base = _settings();
      expect(
        const SettingsPatch(
          crossfadeSeconds: 40,
        ).applyTo(base).crossfadeSeconds,
        maxCrossfadeSeconds,
      );
      expect(
        const SettingsPatch(preloadCount: 40).applyTo(base).preloadCount,
        maxPreloadCount,
      );

      final api = _FakeSettingsApi(base);
      final container = _container(api);
      await _load(container);
      await container
          .read(settingsControllerProvider.notifier)
          .patch(const SettingsPatch(crossfadeSeconds: 999));
      expect(api.sent?.crossfadeSeconds, maxCrossfadeSeconds);
    });

    test('a patch leaves every field it does not name alone', () {
      final base = _settings();
      final patched = const SettingsPatch(autoplay: false).applyTo(base);

      expect(patched.autoplay, isFalse);
      expect(patched.streamingQuality, QualityProfile.high);
      expect(patched.scrobblePrivacy, ScrobblePrivacy.friends);
      // Including a field no control on these screens touches: the settings document is replaced
      // wholesale, so anything dropped here is anything erased on the server.
      expect(patched.eq?.enabled, isTrue);
    });
  });

  group('the two-factor flow', () {
    test('enrolling walks off to the codes and then to on', () async {
      final api = _FakeSecurityApi();
      final controller = TwoFactorController(api: api, enabled: false);
      expect(controller.stage, TwoFactorStage.off);

      expect(await controller.begin(), isTrue);
      expect(controller.stage, TwoFactorStage.enrolling);
      expect(controller.setup?.otpauthUrl, 'otpauth://totp/chordia');

      expect(await controller.confirm('123 456'), isTrue);
      // Whitespace goes because authenticator apps space their digits; nobody should fail a step
      // for typing what they were shown.
      expect(api.confirmed, '123456');
      expect(controller.stage, TwoFactorStage.showingCodes);
      expect(controller.recoveryCodes, ['aaa-bbb', 'ccc-ddd']);
      // The QR is gone the moment there is nothing left to scan.
      expect(controller.setup, isNull);

      controller.acknowledgeCodes();
      expect(controller.stage, TwoFactorStage.on);
      // Shown once and then dropped: the Hub keeps only hashes, so holding them longer buys
      // nothing and risks a later redraw putting them back on screen.
      expect(controller.recoveryCodes, isNull);
    });

    test('a rejected code leaves the enrollment standing', () async {
      final api = _FakeSecurityApi()..failEnable = true;
      final controller = TwoFactorController(api: api, enabled: false);
      await controller.begin();
      final setup = controller.setup;

      expect(await controller.confirm('000000'), isFalse);
      // The pending secret on the Hub is still the one behind the QR on screen, so the only
      // thing to do is type the next code — losing the QR here would strand the enrollment.
      expect(controller.stage, TwoFactorStage.enrolling);
      expect(identical(controller.setup, setup), isTrue);
      expect(controller.error, isA<ApiException>());
      expect(controller.busy, isFalse);
    });

    test('abandoning an enrollment leaves the account untouched', () async {
      final api = _FakeSecurityApi();
      final controller = TwoFactorController(api: api, enabled: false);
      await controller.begin();

      controller.cancelEnrollment();
      expect(controller.stage, TwoFactorStage.off);
      expect(controller.setup, isNull);
      expect(api.confirmed, isNull);
    });

    test(
      'an account that already has 2FA cannot start a second enrollment',
      () async {
        final api = _FakeSecurityApi();
        final controller = TwoFactorController(api: api, enabled: true);
        expect(controller.stage, TwoFactorStage.on);

        // The Hub refuses a second enrollment, so starting one would put a QR on screen for a
        // secret that can never be confirmed.
        expect(await controller.begin(), isFalse);
        expect(api.setupCalls, 0);
        expect(controller.stage, TwoFactorStage.on);
      },
    );

    test('disabling needs the Hub to agree', () async {
      final api = _FakeSecurityApi()..failDisable = true;
      final controller = TwoFactorController(api: api, enabled: true);

      expect(await controller.disable('000000'), isFalse);
      expect(controller.stage, TwoFactorStage.on);

      api.failDisable = false;
      expect(await controller.disable('a1b2c-d3e4f'), isTrue);
      // Hyphens survive: this field takes a recovery code as well as a six-digit one.
      expect(api.disabled, 'a1b2c-d3e4f');
      expect(controller.stage, TwoFactorStage.off);
    });
  });
}

/// A container wired to [api] and nothing else.
///
/// `userSettingsProvider` is overridden because the controller invalidates it on every successful
/// save — the real one reaches for a hub client, a session manager and the platform keystore, none
/// of which exist here and none of which this test is about.
ProviderContainer _container(SettingsApi api) {
  final container = ProviderContainer(
    overrides: [
      settingsApiProvider.overrideWithValue(api),
      userSettingsProvider.overrideWith((ref) async => null),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _load(ProviderContainer container) async {
  // A listener, so the provider stays alive across the awaits below rather than being disposed
  // the moment the first read finishes.
  container.listen(settingsControllerProvider, (_, _) {});
  await container.read(settingsControllerProvider.future);
}

UserSettings _current(ProviderContainer container) =>
    container.read(settingsControllerProvider).value!;

UserSettings _settings({bool normalizeVolume = false}) => UserSettings(
  streamingQuality: QualityProfile.high,
  normalizeVolume: normalizeVolume,
  autoplay: true,
  crossfadeSeconds: 0,
  preloadCount: 2,
  accent: 'pink',
  scrobble: true,
  scrobblePrivacy: ScrobblePrivacy.friends,
  eq: const EqConfig(bands: [], enabled: true, preamp: 0),
);

class _FakeSettingsApi implements SettingsApi {
  _FakeSettingsApi(this._stored);

  UserSettings _stored;

  /// What the last [write] was handed, so a test can assert on the document rather than the patch.
  UserSettings? sent;

  /// Thrown by every write while set.
  ApiException? failure;

  /// Thrown by the next write only, for the in-flight-race case.
  bool failNext = false;

  /// Stands in for the Hub rewriting what it was sent.
  UserSettings Function(UserSettings sent)? normalise;

  /// One gate per held-open write, in the order the writes arrived. Indexed rather than shared,
  /// so a test can let the first call finish while the second is still in flight — which is the
  /// only arrangement in which a revert can be seen to clobber a later edit.
  final _gates = <Completer<void>>[];
  int _toBlock = 0;

  void blockNext(int writes) => _toBlock = writes;

  void release(int index) => _gates[index].complete();

  @override
  Future<UserSettings> read() async => _stored;

  @override
  Future<UserSettings> write(UserSettings updated) async {
    sent = updated;
    if (_toBlock > 0) {
      _toBlock--;
      final gate = Completer<void>();
      _gates.add(gate);
      await gate.future;
    }
    if (failure != null) throw failure!;
    if (failNext) {
      failNext = false;
      throw const ApiException(
        status: 503,
        title: 'Later',
        method: 'PUT',
        path: '/v1/me/settings',
      );
    }
    return _stored = normalise?.call(updated) ?? updated;
  }
}

class _FakeSecurityApi implements SecurityApi {
  int setupCalls = 0;
  String? confirmed;
  String? disabled;
  bool failEnable = false;
  bool failDisable = false;

  static const _rejected = ApiException(
    status: 400,
    title: 'Invalid code',
    method: 'POST',
    path: '/v1/auth/2fa',
  );

  @override
  Future<TotpSetup> beginTotpSetup() async {
    setupCalls++;
    return const TotpSetup(
      secret: 'BASE32SECRET',
      otpauthUrl: 'otpauth://totp/chordia',
      qrSvg: '<svg/>',
    );
  }

  @override
  Future<List<String>> enableTotp(String code) async {
    if (failEnable) throw _rejected;
    confirmed = code;
    return ['aaa-bbb', 'ccc-ddd'];
  }

  @override
  Future<void> disableTotp(String code) async {
    if (failDisable) throw _rejected;
    disabled = code;
  }

  @override
  Future<List<SessionInfo>> sessions() async => const [];

  @override
  Future<void> revokeSession(String sessionId) async {}

  @override
  Future<void> signOutEverywhere() async {}
}
