import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../widgets/surface.dart';

/// One lock card. Three copies use it: the whole-page lock, the activity-only wall, and a follow
/// list the viewer may not open.
///
/// The copies are deliberately distinct and must stay so. `social:profile.hidden.*` is "this
/// profile isn't shared with you" — the whole account is withheld. `social:profile.private.*` is
/// "this person only shares their listening with friends" — identity, bio, links and shelves are
/// still right there above it. Conflating them produces a page announcing that a profile is
/// private while showing the person's banner.
class ProfileWall extends StatelessWidget {
  const ProfileWall({
    required this.title,
    required this.description,
    super.key,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // `island-shell rounded-2xl p-6 text-center` (`u/$handle/route.tsx:422`, and the same block
    // in `social/FollowList.tsx:69`) — the panel material, not a flat fill at the same corner.
    return IslandPanel(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            PhosphorIcons.lockSimple(),
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            description,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
