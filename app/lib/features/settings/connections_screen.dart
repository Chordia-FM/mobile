import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/list_row.dart';
import 'data/settings_messages.dart';
import 'data/settings_providers.dart';
import 'widgets/settings_list.dart';

/// Other accounts linked to this one.
///
/// Both handshakes are OAuth-shaped and both are completed in a browser against the Hub's website,
/// so this screen starts them and then re-reads the result — it never handles a token itself.
class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final lastfm = ref.watch(lastfmStatusProvider);
    final account = ref.watch(accountInfoProvider);

    return SettingsScaffold(
      title: t(SettingsKeys.connectionsTitle),
      onRefresh: () async {
        ref
          ..invalidate(lastfmStatusProvider)
          ..invalidate(accountInfoProvider);
      },
      children: [
        SettingsSection(
          title: t(SettingsKeys.connectionsLastfmLabel),
          description: t(SettingsKeys.connectionsLastfmDesc),
          children: [
            SettingsBody<LastfmStatus>(
              value: lastfm,
              onRetry: () => ref.invalidate(lastfmStatusProvider),
              builder: (context, status) => _LastfmRows(status: status),
            ),
          ],
        ),
        SettingsSection(
          title: t(SettingsKeys.connectionsDiscordLabel),
          description: t(SettingsKeys.connectionsDiscordDesc),
          children: [
            SettingsBody<AccountInfo>(
              value: account,
              onRetry: () => ref.invalidate(accountInfoProvider),
              // Read-only: the Hub has no link or unlink endpoint of its own — Discord is a
              // sign-in method, and the only routes are the authorize/callback pair the website
              // drives. Showing the state without an action is the honest rendering of that.
              builder: (context, value) => ListRow(
                gutter: 0,
                leading: Icon(
                  value.discordLinked
                      ? Icons.link_rounded
                      : Icons.link_off_rounded,
                  size: 20,
                  color: value.discordLinked
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(t(SettingsKeys.connectionsDiscordLabel)),
                subtitle: Text(
                  t(
                    value.discordLinked
                        ? SettingsKeys.connectionsDiscordLinked
                        : SettingsKeys.connectionsDiscordNotLinked,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LastfmRows extends ConsumerStatefulWidget {
  const _LastfmRows({required this.status});

  final LastfmStatus status;

  @override
  ConsumerState<_LastfmRows> createState() => _LastfmRowsState();
}

class _LastfmRowsState extends ConsumerState<_LastfmRows> {
  bool _busy = false;

  /// Sends the browser to the Hub's handshake, which redirects to Last.fm and finishes back on the
  /// Hub's own website.
  ///
  /// The app cannot complete this itself: Last.fm's callback goes to the frontend URL the operator
  /// configured, and the single-use token it carries is exchanged there. The link belongs to the
  /// account rather than to the device, so it is real here the moment the browser is done — which
  /// is what the refresh below is for.
  Future<void> _connect() async {
    final hub = ref.read(activeHubProvider);
    final t = ref.read(translationsProvider).call;
    if (hub == null) return;
    setState(() => _busy = true);
    final opened = await launchUrl(
      hub.url.replace(path: '${hub.url.path}/v1/lastfm/connect'),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!opened) {
      showSettingsMessage(context, t(AuthKeys.desktopCannotOpenBrowser));
    }
  }

  Future<void> _disconnect() async {
    final api = ref.read(connectionsApiProvider);
    if (api == null) return;
    final t = ref.read(translationsProvider).call;
    setState(() => _busy = true);
    try {
      await api.disconnectLastfm();
      if (!mounted) return;
      ref.invalidate(lastfmStatusProvider);
      showSettingsMessage(
        context,
        t(SettingsKeys.connectionsLastfmDisconnected),
      );
    } on Object catch (error) {
      if (!mounted) return;
      showSettingsMessage(context, describeSettingsError(error, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final connected = widget.status.connected;
    return Column(
      children: [
        ListRow(
          gutter: 0,
          leading: Icon(
            connected ? Icons.link_rounded : Icons.link_off_rounded,
            size: 20,
            color: connected ? Theme.of(context).colorScheme.primary : null,
          ),
          title: Text(t(SettingsKeys.connectionsLastfmLabel)),
          subtitle: Text(
            connected
                ? t(SettingsKeys.connectionsLastfmConnectedAs, {
                    'username': widget.status.username ?? '',
                  })
                : t(SettingsKeys.connectionsLastfmOpensBrowser),
          ),
        ),
        if (connected)
          SettingsDisclosureRow(
            label: t(SettingsKeys.connectionsLastfmDisconnect),
            destructive: true,
            onTap: _busy ? null : _disconnect,
          )
        else ...[
          SettingsDisclosureRow(
            label: t(SettingsKeys.connectionsLastfmConnect),
            onTap: _busy ? null : _connect,
          ),
          // The browser cannot tell this screen it is done, so the only honest affordance is a way
          // to ask the Hub again.
          SettingsDisclosureRow(
            label: t(SettingsKeys.connectionsRefresh),
            onTap: () => ref.invalidate(lastfmStatusProvider),
          ),
        ],
      ],
    );
  }
}
