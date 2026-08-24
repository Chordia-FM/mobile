import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/catalog_state.dart';
import '../catalog/widgets/section.dart';
import '../insights/widgets/insights_tabs.dart';
import '../nav/nav_drawer.dart';
import 'data/social_messages.dart';
import 'data/social_providers.dart';
import 'widgets/follow_list.dart';
import 'widgets/person_row.dart';
import 'widgets/profile_banner.dart';
import 'widgets/profile_links.dart';
import 'widgets/profile_list_tabs.dart';
import 'widgets/profile_shelves.dart';
import 'widgets/profile_wall.dart';
import 'widgets/user_identity.dart';

/// One listener's profile — **and their listening report**, which is not a second surface.
///
/// The shape is the web route's, top to bottom (`routes/_authed/app/u/$handle/route.tsx`):
///
///     banner → identity → stat row → actions → bio → links → shelves → the insights tabs
///
/// Your own profile is your own insights page. There is no separate stats screen: the reports are
/// tabs *inside* this one, under your banner and your name, so opening Insights shows you yourself
/// rather than a bare table of numbers about you.
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
        // Your own profile IS the Insights tab's root (the web redirects `/app/insights` here), and
        // a tab root has nothing to go back to — so this slot carries the nav drawer's hamburger,
        // which is where the web's top bar keeps it. On a profile reached by pushing, it is the
        // ordinary back button instead.
        leading: const NavMenuButton(),
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

class _ProfileView extends ConsumerStatefulWidget {
  const _ProfileView({required this.handle, required this.profile});

  final String handle;
  final PublicProfile profile;

  @override
  ConsumerState<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<_ProfileView> {
  /// Which of the three counted lists the panel is showing. Playlists is the default, as on the
  /// web — where it is also the one value that never appears in the URL.
  ProfileList _list = ProfileList.playlists;

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final profile = widget.profile;
    final user = profile.user;
    final own = ref.watch(viewerProvider).value?.id == user.id;
    final hidden = profile.hidden ?? false;

    return ListView(
      children: [
        _Header(profile: profile, own: own),

        // Below the header rather than inside it, so it reads as the divider between who this is
        // and what of theirs you are looking at.
        if (!hidden && ProfileListTabs.tabsFor(profile).isNotEmpty)
          ProfileListTabs(
            profile: profile,
            current: _list,
            onSelect: (next) => setState(() => _list = next),
          ),

        if (hidden)
          ProfileWall(
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
          ProfileLinkBar(links: profile.links ?? const []),

          // ONLY this section answers the tabs. Bio, links and the listening report are properties
          // of the person, not of the list you happen to be looking at — swapping the whole page
          // out was the overcorrection: opening Followers should not take someone's charts away.
          switch (_list) {
            // `null` is the server's "you may not see this surface" and renders nothing at all; an
            // empty list is visible-and-empty and renders the empty line. The client never decides.
            ProfileList.playlists =>
              profile.playlists == null
                  ? const SizedBox.shrink()
                  : PlaylistShelf(
                      key: ValueKey('playlists:${user.handle}'),
                      handle: widget.handle,
                      shelf: profile.playlists!,
                      total: profile.playlistCount ?? profile.playlists!.length,
                    ),
            ProfileList.followers => FollowList(
              key: ValueKey('followers:${user.handle}'),
              handle: widget.handle,
              followers: true,
              own: own,
            ),
            ProfileList.following => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FollowList(
                  key: ValueKey('following:${user.handle}'),
                  handle: widget.handle,
                  followers: false,
                  own: own,
                ),
                // Followed ARTISTS live here rather than in a shelf of their own: following is one
                // question, and answering half of it in a tab and the other half in an unrelated
                // section further down made them look like different things.
                if (profile.followedArtists case final artists?)
                  ArtistShelf(
                    key: ValueKey('artists:${user.handle}'),
                    handle: widget.handle,
                    shelf: artists,
                  ),
              ],
            ),
          },

          if (profile.private)
            ProfileWall(
              title: t(SocialKeys.profilePrivateTitle),
              description: t(SocialKeys.profilePrivateDescription, {
                'name': user.displayName,
              }),
            )
          else
            InsightsTabView(
              // The viewer's own profile still asks about "me" rather than about a handle: the
              // Hub then buckets in their own timezone setting instead of resolving it again.
              handle: own ? null : widget.handle,
              own: own,
              // Always this profile's handle, never the viewer's. The card is stamped with whoever
              // the report is about, which is what makes it publishable from somebody else's page:
              // hiding the button there was solving a privacy problem the stamp already solves,
              // and it left a listener unable to post the friend's rotation they were looking at.
              shareHandle: widget.handle,
            ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}

/// Banner, then one centred column: avatar → name → badges → handle line → actions.
///
/// The centred column is the web's **below-`md`** header, which is the one that belongs on a
/// phone. Its `md`+ layout puts the avatar and the identity side by side with the actions at the
/// bottom right, and that shape has nowhere to go at 375px.
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
        ProfileBanner(bannerUrl: profile.bannerUrl),
        const SizedBox(height: 16),
        UserAvatar(user: user, size: 96),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DisplayName(
            name: user.displayName,
            flair: user.flair,
            // `display-title break-words font-bold text-2xl sm:text-4xl`
            // (`u/$handle/route.tsx:204`) — `text-2xl` at phone width, which is `displaySmall`.
            style: theme.textTheme.displaySmall,
            maxLines: 2,
          ),
        ),
        // Under the name and above the handle: badges are about who this person is, so they belong
        // with the identity rather than down among the statistics.
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
        // Shown on your OWN profile too, exactly as the web shows the ⋮ there: sharing your
        // profile is the action you want from it most, and it is the only one the menu offers
        // about yourself.
        if (!(profile.hidden ?? false)) ...[
          const SizedBox(height: 12),
          _Actions(profile: profile, own: own),
        ],
      ],
    );
  }
}

/// Follow / Unfollow, and the ⋮ that holds sharing, the friendship lifecycle, report and block.
///
/// Friendship is deliberately not a second button here: following and being friends are two
/// different graphs, and two adjacent buttons is precisely what made people think they were the
/// same one. The menu explains the difference in a line of copy.
class _Actions extends ConsumerWidget {
  const _Actions({required this.profile, required this.own});

  final PublicProfile profile;
  final bool own;

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
        // `can_follow` goes false once you already follow (and on your own profile, a closed
        // account, or a social-disabled instance), so Unfollow's reachability rides on
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
        else if (!own)
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
