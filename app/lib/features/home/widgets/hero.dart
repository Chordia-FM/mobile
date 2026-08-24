import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/surface.dart';
import '../../../widgets/tokens.dart';
import '../../catalog/catalog_routes.dart';
import '../../catalog/widgets/section.dart';
import '../../nav/nav_tabs.dart';
import '../data/discovery_nav.dart';
import '../data/home_feed.dart';
import 'cards.dart';
import 'rail.dart';

/// Home's focal point, ported from the web's `components/discovery/HomeHero.tsx`.
///
/// Three deterministic variants, in the web's order:
///
///   1. no libraries and nothing to play → a card straight into the pairing flow;
///   2. libraries but no history yet     → the top mix, or a way to start looking;
///   3. otherwise                        → the resume block: the last thing played, large, with
///      the rest of "Jump back in" beside it and a "See all" over them.
///
/// The variant is a pure function of a [HomeFeed] that is already in hand, which is what keeps the
/// page from swapping its focal point under a thumb after paint — the same property the web calls
/// out at the top of its file.
///
/// Variant 3 is why there is no "Jump back in" rail below: the hero IS that shelf, promoted.
class HomeHero extends ConsumerWidget {
  const HomeHero({required this.feed, super.key});

  final HomeFeed feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (feed.needsLibrary) return const _OnboardHero();
    if (feed.recent.isEmpty) return _StartHero(mix: feed.mixes.firstOrNull);
    return _ResumeHero(recent: feed.recent);
  }
}

/// Variant 1: nothing is paired, so the only useful thing on this page is the way to pair.
///
/// The web links `/library/setup`; this pushes the pairing wizard, which is the same flow with the
/// browser hand-off already built for a phone.
class _OnboardHero extends ConsumerWidget {
  const _OnboardHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _HeroCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroTitle(text: ref.t(DiscoveryKeys.heroOnboardTitle)),
        const SizedBox(height: 8),
        _HeroBody(text: ref.t(DiscoveryKeys.heroOnboardBody)),
        const SizedBox(height: 20),
        FilledButton(
          // The libraries feature declares no navigation extension of its own, so this uses the
          // shared tab-relative push directly — the destination is `libraries/pair` in whichever
          // tab the listener is standing in, exactly as every `goTo…` resolves it.
          onPressed: () => pushInCurrentTab(context, 'libraries/pair'),
          child: Text(ref.t(DiscoveryKeys.heroOnboardCta)),
        ),
      ],
    ),
  );
}

/// Variant 2: paired, but this account has never played anything.
class _StartHero extends ConsumerWidget {
  const _StartHero({required this.mix});

  /// The top "Made for you" mix, when the Hub has managed to weave one. Null on an account so new
  /// that even the mixes are empty, which is the branch below.
  final DailyMix? mix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final mix = this.mix;
    if (mix == null) {
      // Nothing to offer as artwork. It still gets a sentence explaining what happens next and a
      // way to start, rather than a card holding one orphaned line of text.
      return _HeroCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeroTitle(text: t(DiscoveryKeys.homeNoHistoryTitle)),
            const SizedBox(height: 8),
            _HeroBody(text: t(DiscoveryKeys.homeNoHistoryBody)),
            const SizedBox(height: 20),
            FilledButton(
              // A branch switch rather than a push: Search is a tab, and pushing a second copy of
              // it onto Home's stack would strand the listener behind a back button.
              onPressed: () => GoRouter.of(context).go(NavTab.search.path),
              child: Text(t(DiscoveryKeys.heroStartTitle)),
            ),
          ],
        ),
      );
    }

    return _HeroCard(
      child: PressFill(
        onTap: () => context.goToDailyMix(mix.seedArtistId),
        borderRadius: ChordiaRadius.lgAll,
        child: Row(
          children: [
            CoverArt(
              sha256: artHashOf(mix.imageUrl),
              size: 96,
              fallbackIcon: Icons.radio_rounded,
              semanticLabel: mix.title,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeroTitle(text: t(DiscoveryKeys.heroStartTitle)),
                  const SizedBox(height: 6),
                  Text(
                    mix.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ChordiaType.base.copyWith(
                      fontWeight: ChordiaType.semibold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    mix.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ChordiaType.sm.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Variant 3: the resume block — what was last played, then the rest of it.
///
/// The featured entry is a full-width card rather than one more 160px tile, because the whole point
/// of the hero is that the page has a focal point. Everything after it is the ordinary shelf, so
/// the eye reads one big thing and then a row, not eleven equal things.
class _ResumeHero extends ConsumerWidget {
  const _ResumeHero({required this.recent});

  final List<RecentItem> recent;

  /// The web's `recent.slice(1, 9)` — enough to run off the right edge of any phone.
  static const _tileLimit = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final featured = recent.first;
    final tiles = recent.skip(1).take(_tileLimit).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroHeader(
          title: ref.t(DiscoveryKeys.heroResumeTitle),
          onSeeAll: () => context.goToJumpBackIn(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: catalogGutter),
          child: _FeaturedCard(item: featured),
        ),
        if (tiles.isNotEmpty) ...[
          const SizedBox(height: 16),
          RailShelf(
            height: shelfHeight,
            itemCount: tiles.length,
            itemBuilder: (context, index) => RecentCard(item: tiles[index]),
          ),
        ],
      ],
    );
  }
}

/// The last thing played, at the size of a thing worth resuming.
class _FeaturedCard extends ConsumerWidget {
  const _FeaturedCard({required this.item});

  final RecentItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final round = item.kind == RecentKind.artist;
    return PressFill(
      onTap: () => switch (item.kind) {
        RecentKind.album => context.goToAlbum(item.id),
        RecentKind.artist => context.goToArtist(item.id),
        RecentKind.playlist => context.goToPlaylist(item.id),
      },
      borderRadius: ChordiaRadius.xlAll,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.surfaces.card,
          borderRadius: ChordiaRadius.xlAll,
        ),
        child: Row(
          children: [
            CoverArt(
              sha256: artHashOf(item.imageUrl),
              size: 88,
              shape: round ? BoxShape.circle : BoxShape.rectangle,
              fallbackInitial: round ? item.name : null,
              fallbackIcon: switch (item.kind) {
                RecentKind.artist => Icons.person_rounded,
                RecentKind.playlist => Icons.queue_music_rounded,
                RecentKind.album => Icons.album_rounded,
              },
              semanticLabel: item.name,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    // `text-lg font-bold` — the one line on this page set larger than a card's.
                    style: ChordiaType.lg.copyWith(
                      fontWeight: ChordiaType.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ChordiaType.sm.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── the shared pieces ──────────────────────────────────────────────────────────────────────────

/// A hero that is a card: the two onboarding variants, which are prose and a button.
class _HeroCard extends ConsumerWidget {
  const _HeroCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    // `space-y-6` under the greeting; the rails supply their own top gutter below.
    padding: const EdgeInsets.fromLTRB(catalogGutter, 24, catalogGutter, 0),
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surfaces.card,
        borderRadius: ChordiaRadius.xlAll,
      ),
      child: child,
    ),
  );
}

/// The hero's own heading row, with the route to the full list at the far end.
///
/// Not [SectionHeader]: that one leads with `space-y-10` of air, which is right between two rails
/// and wrong directly under the greeting this sits against.
class _HeroHeader extends ConsumerWidget {
  const _HeroHeader({required this.title, required this.onSeeAll});

  final String title;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(catalogGutter, 24, 8, 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: ChordiaType.xl.copyWith(
              fontWeight: ChordiaType.semibold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        TextButton(
          onPressed: onSeeAll,
          child: Text(ref.t(CommonKeys.actionsSeeAll)),
        ),
      ],
    ),
  );
}

class _HeroTitle extends StatelessWidget {
  const _HeroTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: ChordiaType.xl2.copyWith(
      fontWeight: ChordiaType.bold,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );
}

class _HeroBody extends StatelessWidget {
  const _HeroBody({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: ChordiaType.sm.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}
