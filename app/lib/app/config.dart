/// Build-time configuration, supplied by `--dart-define-from-file=env/<flavor>.json`.
///
/// Only things that genuinely differ per build live here. Anything a user can change — which hub
/// they sign in to, their quality tier, their language — is runtime state, not configuration.
class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.defaultHubUrl,
    required this.allowInsecureHubs,
  });

  factory AppConfig.fromEnvironment() {
    const flavor = String.fromEnvironment(
      'CHORDIA_FLAVOR',
      defaultValue: 'prod',
    );
    return const AppConfig(
      flavor: flavor,
      defaultHubUrl: String.fromEnvironment(
        'CHORDIA_DEFAULT_HUB',
        defaultValue: 'https://api.chordia.fm',
      ),
      // Plain-HTTP hubs are a development affordance; a release build refuses them so a typo in a
      // hub address cannot silently downgrade a real session to cleartext.
      allowInsecureHubs: bool.fromEnvironment('CHORDIA_ALLOW_INSECURE_HUBS'),
    );
  }

  final String flavor;
  final String defaultHubUrl;
  final bool allowInsecureHubs;

  bool get isDev => flavor == 'dev';
}
