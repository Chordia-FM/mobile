import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/providers.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../data/social_messages.dart';
import '../data/social_providers.dart';
import '../social_routes.dart';
import 'user_identity.dart';

/// Where the viewer stands with the person on a row.
///
/// [FriendshipStatus] carries no direction, so "they asked you" and "you asked them" would render
/// the same copy — the app telling somebody they sent a request they in fact received. The two are
/// separate values here for that reason.
enum FriendTie {
  none,
  incoming,
  outgoing,
  friends,
  blocked;

  /// The tie a search result's `relationship` describes, given what the viewer's own lists say.
  ///
  /// The Hub's `pending` is directionless, so the incoming list is what disambiguates it; anything
  /// pending that is not in that list was sent by the viewer.
  static FriendTie of(
    FriendshipStatus? relationship,
    FriendsState lists,
    String userId,
  ) {
    if (lists.blocked.any((u) => u.id == userId)) return FriendTie.blocked;
    if (lists.friends.any((u) => u.id == userId)) return FriendTie.friends;
    if (lists.incoming.any((u) => u.id == userId)) return FriendTie.incoming;
    if (lists.outgoing.any((u) => u.id == userId)) return FriendTie.outgoing;
    return switch (relationship) {
      FriendshipStatus.accepted => FriendTie.friends,
      FriendshipStatus.blocked => FriendTie.blocked,
      // Pending, and not in the incoming list read a moment ago — so the viewer sent it.
      FriendshipStatus.pending => FriendTie.outgoing,
      null => FriendTie.none,
    };
  }
}

/// The one row shape for a person.
///
/// The friends list, the request lists, the block list and search results all render this, so the
/// four surfaces cannot drift apart. One primary action sits on the right; everything else lives in
/// the ⋮ sheet, because two 24px targets four pixels apart — one of them destructive — is a
/// mis-tap machine on a phone.
class PersonRow extends ConsumerWidget {
  const PersonRow({
    required this.user,
    required this.tie,
    super.key,
    this.trailing,
    this.subtitle,
  });

  final PublicUser user;
  final FriendTie tie;

  /// The surface's own primary control — Accept on a request, Add on a search result.
  final Widget? trailing;

  /// An extra line under the handle, where the surface has something to say about this person.
  final String? subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: UserAvatar(user: user),
      title: DisplayName(
        name: user.displayName,
        flair: user.flair,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle == null ? '@${user.handle}' : '@${user.handle} · $subtitle',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => context.goToProfile(user.handle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?trailing,
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: ref.t(CommonKeys.actionsMore),
            onPressed: () => showPersonActions(context, ref, user, tie),
          ),
        ],
      ),
    );
  }
}

/// The ⋮ sheet: share the profile, then the friendship lifecycle, then block.
///
/// Friendship lives here rather than beside a Follow button because following and being friends are
/// two different graphs, and the line of copy under "Add friend" is what actually explains the
/// difference to somebody — never drop it for space.
Future<void> showPersonActions(
  BuildContext context,
  WidgetRef ref,
  PublicUser user,
  FriendTie tie,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (sheetContext) => _PersonActionsSheet(user: user, tie: tie),
);

class _PersonActionsSheet extends ConsumerWidget {
  const _PersonActionsSheet({required this.user, required this.tie});

  final PublicUser user;
  final FriendTie tie;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final isSelf = ref.watch(viewerProvider).value?.id == user.id;
    // The sheet's own context dies with the pop, so a snack bar has to run against the page
    // underneath it.
    final page = Navigator.of(context).context;
    final friends = ref.read(friendsControllerProvider.notifier);

    Future<void> run(Future<void> Function() action) async {
      Navigator.of(context).pop();
      try {
        await action();
      } on Object catch (error) {
        if (!page.mounted) return;
        showSocialMessage(page, describeSocialError(error, t));
      }
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: UserAvatar(user: user, size: 44),
            title: DisplayName(name: user.displayName, flair: user.flair),
            subtitle: Text('@${user.handle}'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.ios_share_rounded),
            title: Text(t(SocialKeys.followShareProfile)),
            onTap: () {
              Navigator.of(context).pop();
              unawaitedShare(
                ref,
                user.handle,
                t(SocialKeys.followShareProfile),
              );
            },
          ),
          if (!isSelf) ...[
            switch (tie) {
              FriendTie.friends => ListTile(
                leading: const Icon(Icons.person_remove_rounded),
                title: Text(t(SocialKeys.followRemoveFriend)),
                onTap: () async {
                  final confirmed = await _confirm(
                    context,
                    title: t(SocialKeys.followRemoveFriend),
                    message: t(SocialKeys.friendsConfirmRemove),
                    action: t(CommonKeys.actionsRemove),
                    cancel: t(CommonKeys.actionsCancel),
                  );
                  if (!confirmed) return;
                  await run(() => friends.remove(user));
                },
              ),
              FriendTie.incoming => ListTile(
                leading: const Icon(Icons.person_add_alt_1_rounded),
                title: Text(t(SocialKeys.requestsAccept)),
                subtitle: Text(t(SocialKeys.followFriendIncoming)),
                onTap: () => run(() => friends.accept(user)),
              ),
              FriendTie.outgoing => ListTile(
                leading: const Icon(Icons.schedule_rounded),
                title: Text(t(SocialKeys.requestsCancel)),
                subtitle: Text(t(SocialKeys.followFriendPending)),
                onTap: () => run(() => friends.cancelRequest(user)),
              ),
              FriendTie.blocked => ListTile(
                leading: const Icon(Icons.lock_open_rounded),
                title: Text(t(SocialKeys.blockUnblock)),
                onTap: () => run(() => friends.unblock(user)),
              ),
              FriendTie.none => ListTile(
                leading: const Icon(Icons.person_add_alt_1_rounded),
                title: Text(t(SocialKeys.followAddFriend)),
                subtitle: Text(t(SocialKeys.followVsFriends)),
                isThreeLine: true,
                onTap: () => run(() => friends.sendRequest(user)),
              ),
            },
            if (tie != FriendTie.blocked)
              ListTile(
                leading: Icon(
                  Icons.block_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  t(SocialKeys.blockConfirmLabel),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () async {
                  final confirmed = await _confirm(
                    context,
                    title: t(SocialKeys.blockConfirmTitle),
                    message: t(SocialKeys.blockConfirmMessage, {
                      'handle': user.handle,
                    }),
                    action: t(SocialKeys.blockConfirmLabel),
                    cancel: t(CommonKeys.actionsCancel),
                  );
                  if (!confirmed) return;
                  await run(() => friends.block(user));
                },
              ),
          ],
        ],
      ),
    );
  }
}

/// A yes/no the user has to answer before something destructive happens.
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  required String cancel,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// Hands a profile link to the system share sheet.
///
/// The `/app` prefix the client navigates under is deliberately absent: shared links resolve
/// through the web frontend's public redirect stubs, and a link into `/app` would 404 for anyone
/// not already signed in on that device.
void unawaitedShare(WidgetRef ref, String handle, String title) {
  final frontend = ref.read(activeHubProvider)?.frontendUrl;
  if (frontend == null) return;
  final url = frontend.resolve('/u/${Uri.encodeComponent(handle)}');
  SharePlus.instance.share(ShareParams(uri: url, title: title)).ignore();
}

/// One line of feedback, in the app's own snack bar styling.
void showSocialMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
