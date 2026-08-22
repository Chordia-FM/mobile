import 'package:chordia_api/chordia_api.dart';

/// The slices of the Hub the settings screens use.
///
/// Six narrow interfaces rather than one wide one, and rather than passing `HubClient` around.
/// Each screen's controller depends on exactly the calls it makes, so a test that wants to say
/// "saving fails" writes a fake with two methods instead of a hundred and seventy — and a screen
/// cannot quietly grow a dependency on an endpoint nobody expected it to touch.
abstract interface class SettingsApi {
  Future<UserSettings> read();

  /// Replaces the whole blob. The Hub takes the full object, not a delta, which is why
  /// [SettingsPatch] exists — see `settings_patch.dart`.
  Future<UserSettings> write(UserSettings updated);
}

/// Identity: who the account is, how it signs in, and closing it.
abstract interface class AccountApi {
  Future<UserProfile> profile();

  Future<UserProfile> updateProfile(UpdateProfile changes);

  /// Which credentials exist and whether the address is confirmed.
  Future<AccountInfo> account();

  Future<void> requestEmailVerification();

  Future<void> requestEmailChange(String email);

  Future<void> changePassword(ChangePasswordRequest request);

  /// Emails a set-password link to an account that has none (Discord-only sign-ups).
  Future<void> requestPasswordSet();

  Future<void> deleteAccount();
}

/// Two-factor enrollment and the sessions the account is signed in on.
abstract interface class SecurityApi {
  Future<TotpSetup> beginTotpSetup();

  /// Returns the recovery codes, which the Hub shows once and cannot re-read.
  Future<List<String>> enableTotp(String code);

  Future<void> disableTotp(String code);

  Future<List<SessionInfo>> sessions();

  Future<void> revokeSession(String sessionId);

  Future<void> signOutEverywhere();
}

/// Third-party accounts linked to this one.
abstract interface class ConnectionsApi {
  Future<LastfmStatus> lastfmStatus();

  Future<void> disconnectLastfm();
}

/// Data portability: what leaves, and what has been brought in.
abstract interface class DataApi {
  /// The full account export, as the Hub's JSON document. Untyped because it is a portability
  /// dump rather than a wire contract: it grows whenever the Hub grows a table, and modelling it
  /// would mean a client release for every one of those.
  Future<Object?> exportAccount();

  Future<List<ImportJob>> imports();
}

/// Plans and the links out to the payment provider. Money never moves through these.
abstract interface class PlanApi {
  Future<BillingMe> account();

  Future<PlansResponse> plans();

  /// A hosted checkout URL to open in the system browser.
  Future<CheckoutResponse> startCheckout(CheckoutRequest request);

  /// A customer-portal URL, for cards and cancellation.
  Future<PortalResponse> portal();
}

class HubSettingsApi implements SettingsApi {
  const HubSettingsApi(this._hub);

  final HubClient _hub;

  @override
  Future<UserSettings> read() => _hub.settings();

  @override
  Future<UserSettings> write(UserSettings updated) =>
      _hub.saveSettings(updated);
}

class HubAccountApi implements AccountApi {
  const HubAccountApi(this._hub);

  final HubClient _hub;

  @override
  Future<UserProfile> profile() => _hub.me();

  @override
  Future<UserProfile> updateProfile(UpdateProfile changes) =>
      _hub.updateProfile(changes);

  @override
  Future<AccountInfo> account() => _hub.account();

  @override
  Future<void> requestEmailVerification() => _hub.requestEmailVerification();

  @override
  Future<void> requestEmailChange(String email) =>
      _hub.requestEmailChange(EmailBody(email: email));

  @override
  Future<void> changePassword(ChangePasswordRequest request) =>
      _hub.changePassword(request);

  @override
  Future<void> requestPasswordSet() => _hub.requestPasswordSet();

  @override
  Future<void> deleteAccount() => _hub.deleteAccount();
}

class HubSecurityApi implements SecurityApi {
  const HubSecurityApi(this._hub);

  final HubClient _hub;

  @override
  Future<TotpSetup> beginTotpSetup() => _hub.beginTotpSetup();

  @override
  Future<List<String>> enableTotp(String code) =>
      _hub.enableTotp(CodeBody(code: code));

  @override
  Future<void> disableTotp(String code) =>
      _hub.disableTotp(CodeBody(code: code));

  @override
  Future<List<SessionInfo>> sessions() => _hub.authSessions();

  @override
  Future<void> revokeSession(String sessionId) =>
      _hub.revokeAuthSession(sessionId);

  @override
  Future<void> signOutEverywhere() => _hub.logoutEverywhere();
}

class HubConnectionsApi implements ConnectionsApi {
  const HubConnectionsApi(this._hub);

  final HubClient _hub;

  @override
  Future<LastfmStatus> lastfmStatus() => _hub.lastfmStatus();

  @override
  Future<void> disconnectLastfm() => _hub.disconnectLastfm();
}

class HubDataApi implements DataApi {
  const HubDataApi(this._hub);

  final HubClient _hub;

  /// `GET /v1/me/export` has no generated binding: `chordia_api` models wire contracts, and this
  /// response is deliberately not one. Going through [HubClient.get] keeps the session token,
  /// the language header and the problem-document decoding that every other call gets.
  @override
  Future<Object?> exportAccount() =>
      _hub.get<Object?>('/v1/me/export', (json) => json);

  @override
  Future<List<ImportJob>> imports() async => (await _hub.imports()).jobs;
}

class HubPlanApi implements PlanApi {
  const HubPlanApi(this._hub);

  final HubClient _hub;

  @override
  Future<BillingMe> account() => _hub.billingAccount();

  @override
  Future<PlansResponse> plans() => _hub.billingPlans();

  @override
  Future<CheckoutResponse> startCheckout(CheckoutRequest request) =>
      _hub.startCheckout(request);

  @override
  Future<PortalResponse> portal() => _hub.billingPortal();
}
