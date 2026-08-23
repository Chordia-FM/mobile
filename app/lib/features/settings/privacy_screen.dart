import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'data/settings_controller.dart';
import 'data/settings_patch.dart';
import 'data/settings_values.dart';
import 'widgets/settings_list.dart';

/// What Chordia records, and who gets to see it.
///
/// Grouped as the web client groups it — what is recorded, when you are emailed, who can see what
/// — because these are three different questions and a single flat list of nine controls invites
/// people to answer the wrong one.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final settings = ref.watch(settingsControllerProvider);

    return SettingsScaffold(
      title: t(SettingsKeys.privacyTitle),
      onRefresh: () => ref.read(settingsControllerProvider.notifier).reload(),
      children: [
        SettingsBody<UserSettings>(
          value: settings,
          onRetry: () => ref.invalidate(settingsControllerProvider),
          builder: (context, value) => _PrivacyControls(settings: value),
        ),
      ],
    );
  }
}

class _PrivacyControls extends ConsumerWidget {
  const _PrivacyControls({required this.settings});

  final UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;

    Future<void> write(SettingsPatch change) =>
        applySettingsPatch(context, ref, change);

    final audiences = [
      for (final choice in audienceChoices) (choice.$1, t(choice.$2)),
    ];

    return Column(
      children: [
        SettingsSection(
          title: t(SettingsKeys.privacyGroupsActivityTitle),
          description: t(SettingsKeys.privacyGroupsActivityDesc),
          children: [
            SettingsSwitchRow(
              label: t(SettingsKeys.privacyScrobbleLabel),
              description: t(SettingsKeys.privacyScrobbleDesc),
              value: settings.scrobble ?? true,
              onChanged: (on) => write(SettingsPatch(scrobble: on)),
            ),
            SettingsChoiceRow<ScrobblePrivacy>(
              label: t(SettingsKeys.privacyActivityVisibilityLabel),
              description: t(SettingsKeys.privacyActivityVisibilityDesc),
              value: settings.scrobblePrivacy ?? ScrobblePrivacy.public,
              options: [
                for (final choice in scrobblePrivacyChoices)
                  (choice.$1, t(choice.$2)),
              ],
              onChanged: (privacy) =>
                  write(SettingsPatch(scrobblePrivacy: privacy)),
            ),
          ],
        ),
        SettingsSection(
          title: t(SettingsKeys.privacyGroupsNotificationsTitle),
          description: t(SettingsKeys.privacyGroupsNotificationsDesc),
          children: [
            SettingsSwitchRow(
              label: t(SettingsKeys.privacyEmailNotificationsLabel),
              description: t(SettingsKeys.privacyEmailNotificationsDesc),
              value: settings.emailNotifications ?? true,
              onChanged: (on) => write(SettingsPatch(emailNotifications: on)),
            ),
          ],
        ),
        SettingsSection(
          title: t(SettingsKeys.privacyGroupsAudienceTitle),
          description: t(SettingsKeys.privacyGroupsAudienceDesc),
          children: [
            // Profile leads because it is the front door: every row under it is only reachable
            // once this one has let a viewer through.
            SettingsChoiceRow<Audience>(
              label: t(SettingsKeys.privacyProfileVisibilityLabel),
              description: t(SettingsKeys.privacyProfileVisibilityDesc),
              value: settings.profileVisibility ?? Audience.private,
              options: audiences,
              onChanged: (audience) =>
                  write(SettingsPatch(profileVisibility: audience)),
            ),
            SettingsChoiceRow<Audience>(
              label: t(SettingsKeys.privacyFollowersVisibilityLabel),
              description: t(SettingsKeys.privacyFollowersVisibilityDesc),
              value: settings.followersVisibility ?? Audience.friends,
              options: audiences,
              onChanged: (audience) =>
                  write(SettingsPatch(followersVisibility: audience)),
            ),
            SettingsChoiceRow<Audience>(
              label: t(SettingsKeys.privacyFollowingVisibilityLabel),
              description: t(SettingsKeys.privacyFollowingVisibilityDesc),
              value: settings.followingVisibility ?? Audience.friends,
              options: audiences,
              onChanged: (audience) =>
                  write(SettingsPatch(followingVisibility: audience)),
            ),
            SettingsChoiceRow<Audience>(
              label: t(SettingsKeys.privacyPlaylistsVisibilityLabel),
              description: t(SettingsKeys.privacyPlaylistsVisibilityDesc),
              value: settings.playlistsVisibility ?? Audience.private,
              options: audiences,
              onChanged: (audience) =>
                  write(SettingsPatch(playlistsVisibility: audience)),
            ),
            SettingsChoiceRow<Audience>(
              label: t(SettingsKeys.privacyFollowedArtistsVisibilityLabel),
              description: t(SettingsKeys.privacyFollowedArtistsVisibilityDesc),
              value: settings.followedArtistsVisibility ?? Audience.friends,
              options: audiences,
              onChanged: (audience) =>
                  write(SettingsPatch(followedArtistsVisibility: audience)),
            ),
            SettingsSwitchRow(
              label: t(SettingsKeys.privacyOpenToFollowsLabel),
              description: t(SettingsKeys.privacyOpenToFollowsDesc),
              value: settings.openToFollows ?? true,
              onChanged: (on) => write(SettingsPatch(openToFollows: on)),
            ),
          ],
        ),
      ],
    );
  }
}
