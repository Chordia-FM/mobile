import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';

/// Which list the identity panel is showing. Playlists is the default.
enum ProfileList { playlists, followers, following }

/// Playlists · Followers · Following, as one horizontally scrolling strip of counts.
///
/// **Tabs, not a line of statistics.** These three counts are the primary navigation into the
/// person's playlists and either direction of their follow graph; a static "12 · 40 · 8" tells you
/// the numbers and takes you nowhere.
///
/// Scrolls rather than wraps: three localised labels with counts do not fit a 375px phone, and a
/// strip that wrapped to two lines would push the panel below it around every time a count crossed
/// a digit. A tab the viewer may not see is omitted rather than disabled — a disabled tab
/// advertises that a private list exists, which is the inference the visibility flags are shaped
/// to prevent.
class ProfileListTabs extends ConsumerWidget {
  const ProfileListTabs({
    required this.profile,
    required this.current,
    required this.onSelect,
    super.key,
  });

  final PublicProfile profile;
  final ProfileList current;
  final ValueChanged<ProfileList> onSelect;

  /// The tabs this viewer may see, in the web's order.
  static List<ProfileList> tabsFor(PublicProfile profile) => [
    if (profile.playlists != null) ProfileList.playlists,
    if (profile.followersVisible ?? false) ProfileList.followers,
    if (profile.followingVisible ?? false) ProfileList.following,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final numbers = NumberFormat.decimalPattern(
      ref.watch(translationsProvider).locale,
    );
    final tabs = tabsFor(profile);
    if (tabs.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final tab in tabs)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: ChoiceChip(
                label: Text('${numbers.format(_count(tab))} ${t(_label(tab))}'),
                selected: tab == current,
                onSelected: (_) => onSelect(tab),
              ),
            ),
        ],
      ),
    );
  }

  int _count(ProfileList tab) => switch (tab) {
    ProfileList.playlists => profile.playlistCount ?? 0,
    ProfileList.followers => profile.followerCount ?? 0,
    ProfileList.following => profile.followingCount ?? 0,
  };

  static String _label(ProfileList tab) => switch (tab) {
    ProfileList.playlists => SocialKeys.profileStatsPlaylists,
    ProfileList.followers => SocialKeys.profileStatsFollowers,
    ProfileList.following => SocialKeys.profileStatsFollowing,
  };
}
