import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/catalog_state.dart';
import 'data/social_messages.dart';
import 'data/social_providers.dart';
import 'widgets/friends_listening.dart';
import 'widgets/person_row.dart';

/// Friends, the requests either side of them, and finding new ones.
///
/// One screen rather than a tab per list: on a phone the three lists are short, and splitting them
/// meant an incoming request could sit unseen behind a tab nobody opens. They are sections of one
/// scroll, each present only when it has something in it.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _query = TextEditingController();

  /// The query the results are for, updated on a debounce so a search does not fire per keystroke.
  String _searched = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() => _searched = '');
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => setState(() => _searched = trimmed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final lists = ref.watch(friendsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t(SocialKeys.friendsTitle))),
      body: RefreshIndicator(
        onRefresh: () => ref.read(friendsControllerProvider.notifier).refresh(),
        child: CatalogBody<FriendsState>(
          value: lists,
          errorTitle: t(SocialKeys.profileLoadError),
          onRetry: () => ref.invalidate(friendsControllerProvider),
          skeleton: const _FriendsSkeleton(),
          builder: (context, value) => _FriendsBody(
            lists: value,
            query: _query,
            searched: _searched,
            onQueryChanged: _onQueryChanged,
          ),
        ),
      ),
    );
  }
}

class _FriendsBody extends ConsumerWidget {
  const _FriendsBody({
    required this.lists,
    required this.query,
    required this.searched,
    required this.onQueryChanged,
  });

  final FriendsState lists;
  final TextEditingController query;
  final String searched;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final searching = searched.isNotEmpty;

    return ListView(
      // Always scrollable, so pull-to-refresh works on a short list too.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: query,
            onChanged: onQueryChanged,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: t(SocialKeys.searchPlaceholder),
              border: const OutlineInputBorder(),
              suffixIcon: searching
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      tooltip: t(CommonKeys.actionsClearAll),
                      onPressed: () {
                        query.clear();
                        onQueryChanged('');
                      },
                    )
                  : null,
            ),
          ),
        ),

        // While a search is on screen it owns the page: the lists below are still there when the
        // field is cleared, and showing both at once made it unclear which rows the query matched.
        if (searching)
          _SearchResults(query: searched, lists: lists)
        else ...[
          const FriendsListening(),
          _Section(
            title: t(SocialKeys.requestsPendingHeading, {
              'count': lists.incoming.length,
            }),
            people: lists.incoming,
            tie: FriendTie.incoming,
            trailing: (user) => _AcceptButton(user: user),
          ),
          _Section(
            title: t(SocialKeys.requestsSentHeading, {
              'count': lists.outgoing.length,
            }),
            people: lists.outgoing,
            tie: FriendTie.outgoing,
          ),
          _Section(
            title: t(SocialKeys.friendsHeading, {
              'count': lists.friends.length,
            }),
            people: lists.friends,
            tie: FriendTie.friends,
            emptyMessage: t(SocialKeys.friendsEmpty),
          ),
          _Section(
            title: t(SocialKeys.blockBlockedHeading, {
              'count': lists.blocked.length,
            }),
            people: lists.blocked,
            tie: FriendTie.blocked,
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}

/// One headed list of people, or nothing at all when it is empty and has no empty copy of its own.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.people,
    required this.tie,
    this.emptyMessage,
    this.trailing,
  });

  final String title;
  final List<PublicUser> people;
  final FriendTie tie;

  /// Shown under the heading when the list is empty. Only the friends list has one — an empty
  /// "Sent requests" heading is noise, but an empty Friends section is the state that needs
  /// explaining.
  final String? emptyMessage;

  final Widget Function(PublicUser user)? trailing;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty && emptyMessage == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (people.isEmpty)
          CatalogEmpty(message: emptyMessage!)
        else
          for (final user in people)
            PersonRow(
              key: ValueKey(user.id),
              user: user,
              tie: tie,
              trailing: trailing?.call(user),
            ),
      ],
    );
  }
}

/// The one-tap Accept on an incoming request.
class _AcceptButton extends ConsumerWidget {
  const _AcceptButton({required this.user});

  final PublicUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return FilledButton(
      onPressed: () async {
        try {
          await ref.read(friendsControllerProvider.notifier).accept(user);
        } on Object catch (error) {
          if (!context.mounted) return;
          showSocialMessage(context, describeSocialError(error, t));
        }
      },
      child: Text(t(SocialKeys.requestsAccept)),
    );
  }
}

/// People matching what was typed, plus the escape hatch for a handle search did not surface.
class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query, required this.lists});

  final String query;
  final FriendsState lists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final results = ref.watch(peopleSearchProvider(query));

    return results.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(t(SocialKeys.searchSearching)),
      ),
      error: (error, _) => CatalogError(
        title: t(ErrorsKeys.failedToLoad),
        error: error,
        onRetry: () => ref.invalidate(peopleSearchProvider(query)),
      ),
      data: (people) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (people.isEmpty)
            CatalogEmpty(message: t(SocialKeys.searchNoResults))
          else
            for (final result in people)
              PersonRow(
                key: ValueKey(result.user.id),
                user: result.user,
                tie: FriendTie.of(result.relationship, lists, result.user.id),
                trailing: _AddButton(
                  user: result.user,
                  tie: FriendTie.of(result.relationship, lists, result.user.id),
                ),
              ),
          // Search matches handles and display names, but an account can be findable by handle and
          // still rank below the fold — and somebody typing an exact handle they were given is not
          // browsing, they are trying to add one person.
          _AddByHandle(query: query, results: people),
        ],
      ),
    );
  }
}

/// The primary action on a search result, which depends on where the viewer already stands.
class _AddButton extends ConsumerWidget {
  const _AddButton({required this.user, required this.tie});

  final PublicUser user;
  final FriendTie tie;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final isSelf = ref.watch(viewerProvider).value?.id == user.id;
    if (isSelf) return const SizedBox.shrink();

    return switch (tie) {
      FriendTie.friends => Text(
        t(SocialKeys.discoveryFriendsStatus),
        style: Theme.of(context).textTheme.labelMedium,
      ),
      FriendTie.outgoing => Text(
        t(SocialKeys.discoveryRequestSent),
        style: Theme.of(context).textTheme.labelMedium,
      ),
      FriendTie.blocked => Text(
        t(SocialKeys.modMenuBlocked),
        style: Theme.of(context).textTheme.labelMedium,
      ),
      FriendTie.incoming => FilledButton(
        onPressed: () => _run(context, ref, (c) => c.accept(user)),
        child: Text(t(SocialKeys.requestsAccept)),
      ),
      FriendTie.none => FilledButton.tonal(
        onPressed: () => _run(context, ref, (c) => c.sendRequest(user)),
        child: Text(t(CommonKeys.actionsAdd)),
      ),
    };
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(FriendsController) action,
  ) async {
    final t = ref.read(translationsProvider).call;
    try {
      await action(ref.read(friendsControllerProvider.notifier));
    } on Object catch (error) {
      if (!context.mounted) return;
      showSocialMessage(context, describeSocialError(error, t));
    }
  }
}

/// "Send a friend request to @handle", for a handle typed in full.
///
/// Only offered when the exact handle is not already among the results, so it never sits under a
/// row for the same person.
class _AddByHandle extends ConsumerWidget {
  const _AddByHandle({required this.query, required this.results});

  final String query;
  final List<DiscoveryResult> results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final handle = query.startsWith('@') ? query.substring(1) : query;
    final looksLikeHandle = RegExp(r'^[A-Za-z0-9_.-]{2,32}$').hasMatch(handle);
    final alreadyListed = results.any(
      (r) => r.user.handle.toLowerCase() == handle.toLowerCase(),
    );
    if (!looksLikeHandle || alreadyListed) return const SizedBox.shrink();

    return ListTile(
      leading: const Icon(Icons.person_add_alt_1_rounded),
      title: Text(t(SocialKeys.friendsRequestByHandle, {'handle': handle})),
      onTap: () async {
        final controller = ref.read(friendsControllerProvider.notifier);
        final translate = ref.read(translationsProvider).call;
        try {
          // Resolved first, so the row that appears under "Sent" is the account the request went
          // to rather than a name assembled from what was typed.
          final user = await ref.read(userByHandleProvider(handle).future);
          await controller.sendRequest(user);
          if (!context.mounted) return;
          showSocialMessage(
            context,
            translate(SocialKeys.discoveryRequestSent),
          );
        } on Object catch (error) {
          if (!context.mounted) return;
          showSocialMessage(context, describeSocialError(error, translate));
        }
      },
    );
  }
}

class _FriendsSkeleton extends StatelessWidget {
  const _FriendsSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const SkeletonBox(height: 48),
      const SizedBox(height: 24),
      for (var i = 0; i < 6; i++) ...[
        Row(
          children: [
            const SkeletonBox(width: 40, height: 40, shape: BoxShape.circle),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 160 - (i % 3) * 24, height: 14),
                  const SizedBox(height: 8),
                  const SkeletonBox(width: 90, height: 11),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
      ],
    ],
  );
}
