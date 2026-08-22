import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../library/downloads_screen.dart';
import '../player/eq_screen.dart';
import 'data/settings_controller.dart';
import 'data/settings_patch.dart';
import 'data/settings_values.dart';
import 'settings_screen.dart';
import 'widgets/settings_list.dart';

/// How music sounds and how much of it is fetched ahead.
///
/// Everything here writes through [SettingsController], so a change is on screen before the round
/// trip and put back if the Hub refuses it. The two entry points at the bottom lead to screens
/// this feature does not own — the equalizer belongs to the player, downloads to the library —
/// because this is where people come looking for them.
class PlaybackScreen extends ConsumerWidget {
  const PlaybackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final settings = ref.watch(settingsControllerProvider);

    return SettingsScaffold(
      title: t(SettingsKeys.playbackTitle),
      onRefresh: () => ref.read(settingsControllerProvider.notifier).reload(),
      children: [
        SettingsBody<UserSettings>(
          value: settings,
          onRetry: () => ref.invalidate(settingsControllerProvider),
          builder: (context, value) => _PlaybackControls(settings: value),
        ),
        // Outside the settings read on purpose: what is already on the device is the one thing
        // still worth reaching when the Hub cannot be reached at all.
        SettingsSection(
          title: t(SettingsKeys.downloadsTitle),
          children: [
            SettingsDisclosureRow(
              icon: Icons.download_rounded,
              label: t(LibraryKeys.downloadsTitle),
              description: t(SettingsKeys.playbackStorageDesc),
              onTap: () => openSettingsScreen(context, const DownloadsScreen()),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlaybackControls extends ConsumerWidget {
  const _PlaybackControls({required this.settings});

  final UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;

    Future<void> write(SettingsPatch change) =>
        applySettingsPatch(context, ref, change);

    return Column(
      children: [
        SettingsSection(
          title: t(SettingsKeys.playbackStreamingQuality),
          children: [
            SettingsRadioGroup<QualityProfile>(
              value: settings.streamingQuality ?? QualityProfile.original,
              options: [
                for (final tier in qualityTiers)
                  (tier.$1, t(tier.$2), t(tier.$3)),
              ],
              onChanged: (quality) =>
                  write(SettingsPatch(streamingQuality: quality)),
            ),
          ],
        ),
        SettingsSection(
          title: t(SettingsKeys.playbackTitle),
          children: [
            SettingsSwitchRow(
              label: t(SettingsKeys.playbackNormalizeLabel),
              description: t(SettingsKeys.playbackNormalizeDesc),
              value: settings.normalizeVolume ?? false,
              onChanged: (on) => write(SettingsPatch(normalizeVolume: on)),
            ),
            SettingsSwitchRow(
              label: t(SettingsKeys.playbackAutoplayLabel),
              description: t(SettingsKeys.playbackAutoplayDesc),
              value: settings.autoplay ?? true,
              onChanged: (on) => write(SettingsPatch(autoplay: on)),
            ),
            SettingsSliderRow(
              label: t(SettingsKeys.playbackCrossfadeLabel),
              description: t(SettingsKeys.playbackCrossfadeDesc),
              value: clampCrossfadeSeconds(settings.crossfadeSeconds ?? 0),
              min: 0,
              max: maxCrossfadeSeconds,
              describe: (seconds) => seconds == 0
                  ? t(CommonKeys.statesOff)
                  : t(SettingsKeys.playbackCrossfadeSeconds, {
                      'count': seconds,
                    }),
              onChanged: (seconds) =>
                  write(SettingsPatch(crossfadeSeconds: seconds)),
            ),
            SettingsSliderRow(
              label: t(SettingsKeys.playbackPreloadLabel),
              description: t(SettingsKeys.playbackPreloadDesc),
              value: clampPreloadCount(settings.preloadCount ?? 0),
              min: 0,
              max: maxPreloadCount,
              // A bare count: the description above already says what is being counted, and
              // repeating "tracks" on every stop is what made the web control too wide to read.
              describe: (count) =>
                  count == 0 ? t(CommonKeys.statesOff) : '$count',
              onChanged: (count) => write(SettingsPatch(preloadCount: count)),
            ),
            // Inside this section rather than beside Downloads: the equalizer edits `eq` on the
            // very document above it, so it has nothing to show until that document is in hand.
            SettingsDisclosureRow(
              icon: Icons.tune_rounded,
              label: t(SettingsKeys.equalizerTitle),
              description: t(SettingsKeys.playbackEqualizerDesc),
              // The player's own entry point rather than a route of ours: it opens on the root
              // navigator, over the tab bar and the mini-player, the way the full player does.
              onTap: () => openEqualizer(context),
            ),
          ],
        ),
      ],
    );
  }
}
