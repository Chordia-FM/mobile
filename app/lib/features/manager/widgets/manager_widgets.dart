import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/tokens.dart';
import '../../catalog/widgets/catalog_state.dart';
import '../../catalog/widgets/list_row.dart';
import '../data/coverage_format.dart';
import '../data/manager_providers.dart';

/// A completeness figure with the ratio it came from, drawn as a bar.
///
/// [percent] is nullable on purpose: a null is "nothing measured yet", and this renders it as a
/// dash and an empty track rather than a confident, wrong zero. See [coveragePercent].
class CoverageMeter extends StatelessWidget {
  const CoverageMeter({
    required this.label,
    required this.percent,
    required this.caption,
    super.key,
  });

  final String label;
  final int? percent;

  /// The counts behind the figure, already localised — "7 of 10 releases owned".
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = percent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
            Text(
              pct == null ? '—' : '$pct%',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          // `rounded-full`, like every bar on the web (`library/$libraryId/edit.tsx:697`).
          borderRadius: ChordiaRadius.pill,
          child: LinearProgressIndicator(
            value: pct == null ? 0 : pct / 100,
            minHeight: 8,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          caption,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The card every Manager section sits in, so a page reads as grouped rows rather than a form.
class ManagerCard extends StatelessWidget {
  const ManagerCard({required this.child, super.key, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: ChordiaRadius.xlAll,
      // `rounded-xl border border-border/60 bg-card/40` (`manager/index.tsx:107`) — the manager
      // cards are the softer bordered card, not an island panel, and the phone was drawing the
      // fill without the edge.
      border: Border.all(color: Theme.of(context).colorScheme.lineSoft),
    ),
    child: child,
  );
}

/// A section heading with an optional sentence under it.
class ManagerSectionHeader extends StatelessWidget {
  const ManagerSectionHeader({
    required this.title,
    super.key,
    this.description,
  });

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Still fetching" — said out loud, because a coverage figure computed over a discography that
/// has not arrived is provisional and looks like a wrong answer otherwise.
class ManagerNotice extends StatelessWidget {
  const ManagerNotice(
    this.text, {
    super.key,
    this.icon = PhosphorIconsRegular.arrowClockwise,
  });

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One release group, owned or not.
///
/// A missing release is **information**, not an offer: it carries a badge saying it is not in the
/// library and nothing that would act on it. That is the whole point of the coverage view.
class ReleaseGroupTile extends ConsumerWidget {
  const ReleaseGroupTile({
    required this.title,
    required this.owned,
    super.key,
    this.coverUrl,
    this.subtitle,
    this.onTap,
  });

  final String title;
  final bool owned;
  final String? coverUrl;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return ListRow(
      onTap: onTap,
      leading: CoverArt(sha256: artHashOf(coverUrl), size: 40),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: OwnedBadge(
        owned: owned,
        ownedLabel: t(ManagerKeys.discoverOwned),
        missingLabel: t(ManagerKeys.discoverAvailable),
      ),
    );
  }
}

/// "In library" / "Not in library".
class OwnedBadge extends StatelessWidget {
  const OwnedBadge({
    required this.owned,
    required this.ownedLabel,
    required this.missingLabel,
    super.key,
  });

  final bool owned;
  final String ownedLabel;
  final String missingLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: owned ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: ChordiaRadius.pill,
      ),
      child: Text(
        owned ? ownedLabel : missingLabel,
        style: theme.textTheme.labelSmall?.copyWith(
          color: owned ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Follow / Following, wired to the follows controller.
///
/// Stateless beyond the controller: the button reflects the list of follows, so following an
/// artist from Discover and unfollowing them from the Following tab cannot disagree.
class FollowButton extends ConsumerWidget {
  const FollowButton({
    required this.artistMbid,
    super.key,
    this.name,
    this.following,
  });

  final String artistMbid;
  final String? name;

  /// What the server said when this page loaded, used until the follows list has arrived — a
  /// button that reads "Follow" for an artist you already follow is worse than a brief delay.
  final bool? following;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final follows = ref.watch(followsControllerProvider);
    final isFollowing = follows.hasValue
        ? follows.requireValue.any((f) => f.artistMbid == artistMbid)
        : (following ?? false);

    Future<void> toggle() async {
      final controller = ref.read(followsControllerProvider.notifier);
      final ok = isFollowing
          ? await controller.unfollow(artistMbid)
          : await controller.follow(artistMbid, name: name);
      if (ok || !context.mounted) return;
      final failure = controller.failure;
      if (failure != null) showManagerFailure(context, failure, t);
    }

    return isFollowing
        ? OutlinedButton.icon(
            onPressed: toggle,
            icon: const Icon(PhosphorIconsRegular.check, size: 18),
            label: Text(t(ManagerKeys.followFollowing)),
          )
        : FilledButton.tonalIcon(
            onPressed: toggle,
            icon: const Icon(PhosphorIconsRegular.plus, size: 18),
            label: Text(t(ManagerKeys.followFollow)),
          );
  }
}

/// The Hub's own words for a refusal, already in the reader's language, or a generic failure when
/// the request never reached it.
///
/// Worth showing rather than a blanket message: "you may not see this library" and "the server is
/// unreachable" are the same headline and very different problems.
String describeManagerFailure(
  Object error,
  String Function(String, [Map<String, Object?>]) t,
) => error is ApiException && !error.isNetworkFailure
    ? error.title
    : t(CommonKeys.errorFailedToLoad);

/// Says what went wrong where the reader is looking.
///
/// Every write in the Manager is optimistic, so a failure has already been undone on screen by the
/// time this runs — without the message the revert looks like a tap that never registered.
void showManagerFailure(
  BuildContext context,
  Object error,
  String Function(String, [Map<String, Object?>]) t,
) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(describeManagerFailure(error, t))));
}

/// The rows a Manager list stands in for while its first read is in flight.
///
/// A `Column`, not a `ListView`: this also goes inside a `SliverToBoxAdapter`, which hands its
/// child unbounded height — and an unbounded scrollable is a layout assertion, not a skeleton.
class ManagerRowsSkeleton extends StatelessWidget {
  const ManagerRowsSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows; i++) ...[
          Row(
            children: [
              const SkeletonBox(width: 48, height: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 200 - (i % 3) * 40, height: 14),
                    const SizedBox(height: 8),
                    const SkeletonBox(width: 120, height: 11),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ],
    ),
  );
}

/// The whole-page version of [ManagerRowsSkeleton], for a screen whose body is the list.
class ManagerListSkeleton extends StatelessWidget {
  const ManagerListSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) =>
      ListView(children: [ManagerRowsSkeleton(rows: rows)]);
}
