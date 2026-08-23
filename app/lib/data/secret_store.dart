import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A key/value store whose values are held by the platform keystore.
///
/// Deliberately narrower than `FlutterSecureStorage`: it is the one seam a test has to fake, and
/// keeping the plugin behind it means nothing that merely wants to remember a secret drags in a
/// live method channel. Everything Chordia stores here is a credential — refresh tokens and the
/// in-flight PKCE verifier — so there is no "convenience" variant that writes to preferences.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// The real store: Keychain on iOS/macOS, an AES-GCM record wrapped by the Android keystore.
///
/// The plugin's defaults are the strong ones as of v10 — no options are passed, because every
/// option available here weakens something.
class KeystoreSecretStore implements SecretStore {
  const KeystoreSecretStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Secrets held in memory, for tests. Never reachable from a release build.
class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
