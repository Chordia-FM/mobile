import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../i18n/translations.dart';
import 'settings_api.dart';

/// Each slice of the Hub the settings screens speak to, or null when there is no hub session to
/// speak through. Separate providers rather than one, so a test overrides only the calls it is
/// about — see the interfaces in `settings_api.dart`.
final settingsApiProvider = Provider<SettingsApi?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : HubSettingsApi(hub);
});

final accountApiProvider = Provider<AccountApi?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : HubAccountApi(hub);
});

final securityApiProvider = Provider<SecurityApi?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : HubSecurityApi(hub);
});

final connectionsApiProvider = Provider<ConnectionsApi?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : HubConnectionsApi(hub);
});

final dataApiProvider = Provider<DataApi?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : HubDataApi(hub);
});

final planApiProvider = Provider<PlanApi?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : HubPlanApi(hub);
});

/// The signed-in account's own profile, for the fields the Account screen edits.
///
/// Read here rather than taken from `authControllerProvider`, whose `user` is only populated for a
/// session established in this run of the app — a session restored from the keystore carries
/// tokens, not a profile, and the Account screen must render either way.
final myProfileProvider = FutureProvider<UserProfile>((ref) {
  final api = ref.watch(accountApiProvider);
  if (api == null) throw StateError('No hub session to read a profile from.');
  return api.profile();
});

/// The account's own **public** profile, which is where the bio, banner and links live.
///
/// A family keyed by handle rather than a chain off [myProfileProvider], so a test can seed it
/// directly and so a handle change re-reads under the new key instead of serving the old profile.
final myPublicProfileProvider = FutureProvider.family<PublicProfile, String>((
  ref,
  handle,
) {
  final api = ref.watch(accountApiProvider);
  if (api == null) throw StateError('No hub session to read a profile from.');
  return api.publicProfile(handle);
});

/// Which credentials the account has, and whether its address is confirmed.
final accountInfoProvider = FutureProvider<AccountInfo>((ref) {
  final api = ref.watch(accountApiProvider);
  if (api == null) throw StateError('No hub session to read an account from.');
  return api.account();
});

final authSessionsProvider = FutureProvider<List<SessionInfo>>((ref) {
  final api = ref.watch(securityApiProvider);
  if (api == null) throw StateError('No hub session to list sessions from.');
  return api.sessions();
});

final lastfmStatusProvider = FutureProvider<LastfmStatus>((ref) {
  final api = ref.watch(connectionsApiProvider);
  if (api == null) throw StateError('No hub session to read Last.fm from.');
  return api.lastfmStatus();
});

final importJobsProvider = FutureProvider<List<ImportJob>>((ref) {
  final api = ref.watch(dataApiProvider);
  if (api == null) throw StateError('No hub session to list imports from.');
  return api.imports();
});

/// The billing view of the account beside its entitlements, and the pricing table.
///
/// Fetched together because the Plan screen cannot render either half alone: the table has to know
/// which row is the current one, and the current tier means nothing without the prices beside it.
final planStateProvider = FutureProvider<(BillingMe, PlansResponse)>((
  ref,
) async {
  final api = ref.watch(planApiProvider);
  if (api == null) throw StateError('No hub session to read a plan from.');
  final account = await api.account();
  // Only when this Hub sells anything. A self-hoster must never meet a pricing table on their own
  // machine, and asking for one is how a client ends up with something to render.
  if (account.entitlements.billingEnabled == false) {
    return (account, const PlansResponse(billingEnabled: false, plans: []));
  }
  return (account, await api.plans());
});

/// The languages this build ships catalogs for, as BCP-47 tags.
///
/// Read from the bundled manifest rather than hard-coded, so a locale that arrives from Crowdin
/// appears in the picker as soon as `tool/sync_i18n.dart` has copied it in.
final availableLocalesProvider = FutureProvider<List<String>>(
  (ref) => Translations.availableLocales(rootBundle),
);
