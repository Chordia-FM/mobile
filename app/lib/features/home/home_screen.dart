import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/catalog_routes.dart';
import '../catalog/data/playback.dart';
import '../catalog/widgets/album_grid.dart';
import '../catalog/widgets/artist_row.dart';
import '../catalog/widgets/catalog_state.dart';
import '../social/social_routes.dart';
import 'data/daypart.dart';
import 'data/discovery_nav.dart';
import 'data/home_feed.dart';
import 'widgets/cards.dart';
import 'widgets/hero.dart';
import 'widgets/rail.dart';

/// The home tab: a scrolling feed of horizontal shelves.
///
/// Nothing here decides what a rail contains or whether it appears — [HomeFeed.rails] does, so this
/// is a renderer for an ordered list and "an empty rail is not a rail" lives in one place instead
/// of nine.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeFeedProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: ref.read(homeFeedProvider.notifier).refresh,
          child: CustomScrollView(
            // The feed stays draggable even when it is one error card, or pull-to-retry is
            // unreachable exactly when it is needed.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _Greeting(now: DateTime.now())),
              ..._body(context, ref, state),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, WidgetRef ref, HomeState state) {
    final feed = state.feed;

    if (feed == null && state.error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: CatalogError(
            // The Hub's own words when it gave any: it names the actual problem, in the language
            // the app asked for, where a client-side string can only say that something failed.
            title: state.error is ApiException
                ? (state.error! as ApiException).title
                : ref.t(CommonKeys.errorFailedToLoad),
            error: state.error,
            onRetry: ref.read(homeFeedProvider.notifier).refresh,
          ),
        ),
      ];
    }

    // Nothing known yet: the shape of the page, not a spinner over a blank screen.
    if (feed == null) {
      return const [SliverToBoxAdapter(child: HomeSkeleton())];
    }

    // No empty state below this point, and that is the web's shape rather than an omission: the
    // hero has a variant for every degree of nothing — no library, no history, no mixes — and each
    // one hands the listener something to press. `CatalogEmpty` here was a sentence and a shrug.
    final rails = feed.rails;
    return [
      SliverToBoxAdapter(child: HomeHero(feed: feed)),
      SliverList.builder(
        itemCount: rails.length,
        itemBuilder: (context, index) =>
            _rail(context, ref, rails[index], feed),
      ),
    ];
  }

  Widget _rail(
    BuildContext context,
    WidgetRef ref,
    HomeRail rail,
    HomeFeed feed,
  ) {
    final t = ref.t;
    switch (rail) {
      case HomeRail.quickAccess:
        return RailSection(
          title: t(DiscoveryKeys.quickAccessTitle),
          child: RailShelf(
            height: PinPill.shelfHeight,
            itemCount: feed.pins.length,
            itemBuilder: (context, index) {
              final pin = feed.pins[index];
              return PinPill(
                name: pin.name,
                imageUrl: pin.imageUrl,
                round: pin.kind == PinKind.artist || pin.kind == PinKind.radio,
                onTap: () => switch (pin.kind) {
                  PinKind.album => context.goToAlbum(pin.id),
                  PinKind.artist => context.goToArtist(pin.id),
                  PinKind.playlist => context.goToPlaylist(pin.id),
                  PinKind.radio => context.goToArtistRadio(pin.id),
                },
              );
            },
          ),
        );

      case HomeRail.madeForYou:
        return RailSection(
          title: t(DiscoveryKeys.madeForYouTitle),
          onSeeAll: () => context.goToMadeForYou(),
          child: RailShelf(
            height: shelfHeight,
            itemCount: feed.mixes.length,
            itemBuilder: (context, index) => MixCard(mix: feed.mixes[index]),
          ),
        );

      case HomeRail.recentlyAdded:
        return RailSection(
          title: t(DiscoveryKeys.shelfRecentlyAdded),
          child: AlbumShelf(albums: feed.recentlyAdded),
        );

      case HomeRail.recommended:
        return RailSection(
          title: t(DiscoveryKeys.shelfRecommended),
          child: AlbumShelf(albums: feed.recommended),
        );

      case HomeRail.trendingAlbums:
        return RailSection(
          title: t(DiscoveryKeys.shelfTrendingAlbums),
          child: AlbumShelf(albums: feed.trendingAlbums),
        );

      case HomeRail.trendingArtists:
        return RailSection(
          title: t(DiscoveryKeys.shelfTrendingArtists),
          child: ArtistShelf(artists: feed.trendingArtists),
        );

      case HomeRail.trendingTracks:
        return RailSection(
          title: t(DiscoveryKeys.shelfTrendingTracks),
          child: RailShelf(
            height: shelfHeight,
            itemCount: feed.trendingTracks.length,
            itemBuilder: (context, index) {
              final track = feed.trendingTracks[index];
              return EntityCard(
                imageUrl: track.coverUrl,
                title: track.title,
                subtitle: track.artist,
                fallbackIcon: Icons.music_note_rounded,
                // The whole shelf becomes the queue, so what is trending keeps playing after the
                // song that was tapped. There is no `PlayContext` kind for a chart, and inventing
                // one here would put a name on the wire the other clients do not know.
                onTap: () => playTracksFrom(
                  ref,
                  tracks: feed.trendingTracks,
                  index: index,
                  playContext: null,
                ),
              );
            },
          ),
        );

      case HomeRail.friendsListening:
        return RailSection(
          title: t(DiscoveryKeys.shelfFriendsListening),
          child: RailShelf(
            height: shelfHeight,
            itemCount: feed.friends.length,
            itemBuilder: (context, index) {
              final friend = feed.friends[index];
              return FriendCard(
                avatarUrl: friend.avatarUrl,
                displayName: friend.displayName,
                line: t(DiscoveryKeys.friendsNowPlaying, {
                  'title': friend.title,
                  'artist': friend.artist,
                }),
                onTap: () => context.goToProfile(friend.handle),
              );
            },
          ),
        );
    }
  }
}

/// The header: a greeting for the hour and a line under it.
class _Greeting extends ConsumerWidget {
  const _Greeting({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final part = Daypart.at(now);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(part.greetingKey),
            // `display-title font-bold text-2xl md:text-3xl` (HomeView.tsx:260) — the phone column
            // is below `md`, so `text-2xl`, which is the `displaySmall` slot.
            style: theme.textTheme.displaySmall,
          ),
          const SizedBox(height: 4),
          Text(
            t(part.subtitleKey),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
