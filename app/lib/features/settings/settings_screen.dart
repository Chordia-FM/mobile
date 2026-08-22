import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'account_screen.dart';
import 'appearance_screen.dart';
import 'connections_screen.dart';
import 'data_screen.dart';
import 'plan_screen.dart';
import 'playback_screen.dart';
import 'privacy_screen.dart';
import 'security_screen.dart';
import 'widgets/settings_list.dart';

/// The settings index: one row per area, in the order the web client's tabs run.
///
/// A phone gets an index of pages rather than the web's tab strip. The same eight areas, but each
/// one opens as its own screen with its own back — a tab bar with eight entries either scrolls
/// horizontally (hiding half of them) or shrinks to labels nobody can read.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final hub = ref.watch(activeHubProvider);

    return SettingsScaffold(
      title: t(SettingsKeys.title),
      children: [
        SettingsSection(
          title: t(SettingsKeys.title),
          children: [
            SettingsDisclosureRow(
              icon: Icons.person_rounded,
              label: t(SettingsKeys.accountTitle),
              description: t(SettingsKeys.sectionsAccount),
              onTap: () => openSettingsScreen(context, const AccountScreen()),
            ),
            SettingsDisclosureRow(
              icon: Icons.palette_rounded,
              label: t(SettingsKeys.appearanceTitle),
              description: t(SettingsKeys.sectionsAppearance),
              onTap: () =>
                  openSettingsScreen(context, const AppearanceScreen()),
            ),
            SettingsDisclosureRow(
              icon: Icons.graphic_eq_rounded,
              label: t(SettingsKeys.playbackTitle),
              description: t(SettingsKeys.sectionsPlayback),
              onTap: () => openSettingsScreen(context, const PlaybackScreen()),
            ),
            SettingsDisclosureRow(
              icon: Icons.visibility_rounded,
              label: t(SettingsKeys.privacyTitle),
              description: t(SettingsKeys.sectionsPrivacy),
              onTap: () => openSettingsScreen(context, const PrivacyScreen()),
            ),
            SettingsDisclosureRow(
              icon: Icons.lock_rounded,
              label: t(SettingsKeys.securityTitle),
              description: t(SettingsKeys.sectionsSecurity),
              onTap: () => openSettingsScreen(context, const SecurityScreen()),
            ),
            SettingsDisclosureRow(
              icon: Icons.link_rounded,
              label: t(SettingsKeys.connectionsTitle),
              description: t(SettingsKeys.sectionsConnections),
              onTap: () =>
                  openSettingsScreen(context, const ConnectionsScreen()),
            ),
            SettingsDisclosureRow(
              icon: Icons.folder_zip_rounded,
              label: t(SettingsKeys.dataTitle),
              description: t(SettingsKeys.sectionsData),
              onTap: () => openSettingsScreen(context, const DataScreen()),
            ),
            SettingsDisclosureRow(
              icon: Icons.workspace_premium_rounded,
              label: t(SettingsKeys.planTitle),
              description: t(SettingsKeys.sectionsPlan),
              onTap: () => openSettingsScreen(context, const PlanScreen()),
            ),
          ],
        ),
        // The hub this account is on. Named rather than assumed: self-hosters run several, and
        // "sign out" means nothing until you know which server you are signed in to.
        if (hub != null) SettingsNote('${hub.name} · ${hub.url.host}'),
      ],
    );
  }
}

/// Pushes a settings page onto the current tab's own navigator.
///
/// The tab keeps its stack across tab switches and the system back button unwinds it, which is
/// what makes Settings behave like every other stack in the app.
void openSettingsScreen(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}
