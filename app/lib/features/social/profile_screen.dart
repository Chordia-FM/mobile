import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../catalog/catalog_routes.dart';
import '../catalog/widgets/catalog_state.dart';
import '../catalog/widgets/section.dart';
import '../insights/widgets/insights_tabs.dart';
import 'data/social_messages.dart';
import 'data/social_providers.dart';
import 'widgets/person_row.dart';
import 'widgets/user_identity.dart';

/// One listener's public profile: who they are, what the viewer may do about it, and their
/// listening surfaces.
///
/// **Two different walls, from two different settings, with two different copies.**
/// `hidden` means the whole profile is withheld — every field below it is a placeholder rather
/// than a fact, and nothing under it is rendered. `private` walls only the listening activity,
/// leaving identity, bio, links and shelves in place. Conflating them produces a page announcing
/// "this profile is private" while showing the person's bio and banner.
///
/// Neither is ever inferred from the shape of the data. The locked shell is a zeroed DTO and a
/// genuinely visible profile can produce a byte-identical one — a new account with no bio and no
/// followers — so guessing walls real people behind the "not shared with you" copy.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({required this.handle, super.key});

  final String handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final profile = ref.watch(publicProfileProvider(handle));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          profile.value?.user.displayName ?? '@$handle',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: CatalogBody<PublicProfile>(
        value: profile,
        // A 404 is "no user with that handle" — which is also what a block answers with, on
        // purpose — while anything else is worth a retry.
        errorTitle:
            profile.error is ApiException &&
                (profile.error! as ApiException).isNotFound
            ? t(SocialKeys.profileNotFound)
            : t(SocialKeys.profileLoadError),
        onRetry: () => ref.invalidate(publicProfileProvider(handle)),
        skeleton: const CatalogDetailSkeleton(circularArt: true),
        builder: (context, value) =>
            _ProfileView(handle: handle, profile: value),
      ),
    );
  }
}

class _ProfileView extends ConsumerWidget {
  const _ProfileView({required this.handle, required this.profile});

  final String handle;
  final PublicProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final user = profile.user;
    final own = ref.watch(viewerProvider).value?.id == user.id;
    final hidden = profile.hidden ?? false;

    return ListView(
      children: [
        _Header(profile: profile, own: own),
        if (hidden)
          _Wall(
            title: t(SocialKeys.profileHiddenTitle),
            description: t(SocialKeys.profileHiddenDescription, {
              'name': user.displayName,
            }),
          )
        else ...[
          if (profile.bio case final bio?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ExpandableText(text: bio),
            ),
          _Links(links: profile.links ?? const []),
          _Counts(profile: profile),
          // `null` is the server's "you may not see this surface" and renders nothing at all; an
          // empty list is visible-and-empty and renders the empty line. The client never decides.
          if (profile.playlists case final playlists?)
            _PlaylistShelf(playlists: playlists),
          if (profile.followedArtists case final artists?)
            _ArtistShelf(artists: artists),
          if (profile.private)
            _Wall(
              title: t(SocialKeys.profilePrivateTitle),
              description: t(SocialKeys.profilePrivateDescription, {
                'name': user.displayName,
              }),
            )
          else
            InsightsTabView(
              // The viewer's own profile still asks about "me" rather than about a handle: the
              // Hub then buckets in their own timezone setting instead of resolving it again.
              handle: own ? null : handle,
              own: own,
              shareHandle: own ? handle : null,
            ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.profile, required this.own});

  final PublicProfile profile;
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final user = profile.user;
    final joined = DateFormat.yMMMM(
      ref.watch(translationsProvider).locale,
    ).format(DateTime.fromMillisecondsSinceEpoch(profile.createdAt));

    return Column(
      children: [
        if (artHashOf(profile.bannerUrl) case final banner?)
          AspectRatio(
            aspectRatio: 3,
            child: CoverArt(
              sha256: banner,
              // The banner fills the width; `CoverArt` is square-sized, so the side it is given is
              // the larger of the two the layout will use.
              size: MediaQuery.sizeOf(context).width,
              borderRadius: BorderRadius.zero,
              fallbackIcon: Icons.image_outlined,
            ),
          ),
        const SizedBox(height: 16),
        UserAvatar(user: user, size: 96),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DisplayName(
            name: user.displayName,
            flair: user.flair,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            maxLines: 2,
          ),
        ),
        const SizedBox(height: 8),
        BadgeRow(badges: profile.badges, alignment: WrapAlignment.center),
        const SizedBox(height: 8),
        Text(
          [
            '@${user.handle}',
            t(SocialKeys.profileJoinedLabel, {'date': joined}),
            if (!profile.private)
              t(SocialKeys.profileTotalPlays, {'count': profile.totalPlays}),
          ].join(' · '),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (!(profile.hidden ?? false) && !own) ...[
          const SizedBox(height: 12),
          _Actions(profile: profile),
        ],
      ],
    );
  }
}

/// Follow / Unfollow, and the ⋮ that holds the friendship lifecycle.
///
/// Friendship is deliberately not a second button here: following and being friends are two
/// different graphs, and two adjacent buttons is precisely what made people think they were the
/// same one. The menu explains the difference in a line of copy.
class _Actions extends ConsumerWidget {
  const _Actions({required this.profile});

  final PublicProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final handle = profile.user.handle;
    // The controller's override wins once the viewer has acted; before that the fetched profile is
    // the truth. Defaulting to false would render "Follow" on somebody you already follow for as
    // long as the profile took to load.
    final following =
        ref.watch(followControllerProvider(handle)) ??
        (profile.viewerFollows ?? false);
    final canFollow = profile.canFollow ?? false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // `can_follow` goes false once you already follow, so Unfollow's reachability rides on
        // `viewer_follows` instead.
        if (canFollow || following)
          following
              ? OutlinedButton.icon(
                  onPressed: () => _toggle(context, ref, following: false),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(t(SocialKeys.followFollowing)),
                )
              : FilledButton.icon(
                  onPressed: () => _toggle(context, ref, following: true),
                  icon: const Icon(Icons.person_add_alt_rounded),
                  label: Text(t(SocialKeys.followFollow)),
                )
        else
          Text(
            t(SocialKeys.followNotOpen),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(width: 8),
        IconButton.outlined(
          icon: const Icon(Icons.more_horiz_rounded),
          tooltip: t(CommonKeys.actionsMore),
          onPressed: () => showPersonActions(
            context,
            ref,
            profile.user,
            switch (profile.friendship) {
              FriendshipStatus.accepted => FriendTie.friends,
              FriendshipStatus.blocked => FriendTie.blocked,
              // `FriendshipStatus` carries no direction. The viewer's own incoming list is what
              // disambiguates a pending edge, and it is the only place that can.
              FriendshipStatus.pending => _pendingTie(ref, profile.user.id),
              null => FriendTie.none,
            },
          ),
        ),
      ],
    );
  }

  FriendTie _pendingTie(WidgetRef ref, String userId) {
    final lists = ref.read(friendsControllerProvider).value;
    if (lists == null) return FriendTie.outgoing;
    return lists.incoming.any((u) => u.id == userId)
        ? FriendTie.incoming
        : FriendTie.outgoing;
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref, {
    required bool following,
  }) async {
    final t = ref.read(translationsProvider).call;
    try {
      await ref
          .read(followControllerProvider(profile.user.handle).notifier)
          .setFollowing(following: following);
    } on Object catch (error) {
      if (!context.mounted) return;
      showSocialMessage(context, describeSocialError(error, t));
    }
  }
}

/// Followers · Following · Playlists, as plain counts.
///
/// Counts the viewer may not see are omitted rather than shown as zero — a zero is a claim, and
/// the visibility flags exist so the client does not have to make one.
class _Counts extends ConsumerWidget {
  const _Counts({required this.profile});

  final PublicProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final entries = <String>[
      if (profile.followersVisible ?? false)
        '${profile.followerCount ?? 0} ${t(SocialKeys.profileStatsFollowers)}',
      if (profile.followingVisible ?? false)
        '${profile.followingCount ?? 0} ${t(SocialKeys.profileStatsFollowing)}',
      if (profile.playlists != null)
        '${profile.playlistCount ?? 0} ${t(SocialKeys.profileStatsPlaylists)}',
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Text(
        entries.join(' · '),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _Links extends StatelessWidget {
  const _Links({required this.links});

  final List<ProfileLink> links;

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final link in links)
            ActionChip(
              avatar: const Icon(Icons.link_rounded, size: 16),
              label: Text(link.kind),
              onPressed: () {
                final url = Uri.tryParse(link.url);
                // Free text on somebody else's profile: anything that is not a parseable web
                // address is not something this app hands to the platform browser.
                if (url == null || !url.hasScheme) return;
                launchUrl(url, mode: LaunchMode.externalApplication).ignore();
              },
            ),
        ],
      ),
    );
  }
}

class _PlaylistShelf extends ConsumerWidget {
  const _PlaylistShelf({required this.playlists});

  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            t(SocialKeys.profileShelvesPlaylists),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (playlists.isEmpty)
          CatalogEmpty(message: t(SocialKeys.profileShelvesNoPlaylists))
        else
          for (final playlist in playlists)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: CoverArt(
                sha256: artHashOf(playlist.coverUrl),
                size: 44,
                fallbackIcon: Icons.queue_music_rounded,
              ),
              title: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                t(CatalogKeys.trackCount, {'count': playlist.trackCount}),
              ),
            ),
      ],
    );
  }
}

class _ArtistShelf extends ConsumerWidget {
  const _ArtistShelf({required this.artists});

  final List<ProfileArtist> artists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            t(SocialKeys.profileShelvesFollowedArtists),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (artists.isEmpty)
          CatalogEmpty(message: t(SocialKeys.profileShelvesNoArtists))
        else
          for (final artist in artists)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: CoverArt(
                sha256: artHashOf(artist.imageUrl),
                size: 44,
                shape: BoxShape.circle,
                fallbackIcon: Icons.person_rounded,
              ),
              title: Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // Only an artist that resolves in this hub's catalog has a page to open; one known
              // to the follow list by MBID alone has nowhere to go.
              onTap: artist.artistId == null
                  ? null
                  : () => context.goToArtist(artist.artistId!),
            ),
      ],
    );
  }
}

/// One lock card. Two copies use it: the whole-page lock and the activity-only wall.
class _Wall extends StatelessWidget {
  const _Wall({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            Icons.lock_outline_rounded,
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
