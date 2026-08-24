import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/tokens.dart';
import '../admin/data/admin_providers.dart';
import '../catalog/widgets/list_row.dart';
import '../social/data/social_providers.dart';

/// The account control the web keeps in its top bar on every `/app` page, phones included
/// (`components/layout/UserMenu.tsx`, ungated — contrast the hamburger beside it, which is `md:`).
///
/// It carries the two things nothing else on this client offers from where the listener is
/// standing: your own profile as YOU rather than as a stats tab, and a way out. Sign out used to be
/// four levels down (drawer → Settings → Account → Sign out), which is where you put a setting, not
/// where you put the answer to "whose phone is this".
///
/// HOST: the web hangs this off the top bar, which on this client belongs to the app shell
/// (`app/shell.dart`) and to each root screen's own `AppBar`. This button lives in the drawer's
/// header instead — one tap further than the web, and reachable from every tab root. Dropping it
/// into those bars as well is a one-line change each and would close the remaining difference.
class NavAccountButton extends ConsumerWidget {
  const NavAccountButton({super.key});

  /// The web's trigger is `size-(--control-h-lg)`; the glyph inside it is the avatar.
  static const _avatar = ChordiaControl.lg - 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewer = ref.watch(viewerProvider).value;
    // Nothing to name and nothing to open. A placeholder avatar here would offer a control that
    // cannot answer the one question it exists to answer.
    if (viewer == null) return const SizedBox.shrink();

    final name = accountName(viewer.displayName, viewer.handle);
    return IconButton(
      tooltip: name,
      iconSize: _avatar,
      onPressed: () {
        // Opened before the drawer is dismissed, so the sheet reads its tab off a location that is
        // still mounted; the drawer then goes, or it would sit over whatever the sheet opens.
        final sheet = showAccountMenu(context);
        Scaffold.maybeOf(context)?.closeDrawer();
        unawaited(sheet);
      },
      icon: CoverArt(
        sha256: artHashOf(viewer.avatarUrl),
        size: _avatar,
        shape: BoxShape.circle,
        fallbackInitial: name,
        semanticLabel: name,
      ),
    );
  }
}

/// What to call somebody: their display name, or their handle when they have not set one.
@visibleForTesting
String accountName(String displayName, String handle) =>
    displayName.isEmpty ? handle : displayName;

/// The menu itself: the web's list, in the web's order.
///
/// A sheet rather than a dropdown, because that is what every other menu on this client is — the
/// entity menus, the library card menu, the player menu.
///
/// The router and the tab are read HERE, before the sheet exists. Every destination below is
/// tab-relative (the first path segment is the tab, as everywhere else in this app), and by the
/// time a row is tapped the drawer that raised the sheet has been dismissed — so the location has
/// to be taken while there is still one to take.
Future<void> showAccountMenu(BuildContext context) {
  final router = GoRouter.of(context);
  final tab = GoRouterState.of(context).uri.pathSegments.firstOrNull;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: _AccountSheet(
        open: (suffix) {
          Navigator.of(sheetContext).pop();
          if (tab != null) router.push('/$tab/$suffix');
        },
      ),
    ),
  );
}

class _AccountSheet extends ConsumerWidget {
  const _AccountSheet({required this.open});

  /// Pushes a tab-relative path and dismisses the sheet on the way.
  final void Function(String suffix) open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final viewer = ref.watch(viewerProvider).value;
    // "Not known yet" and "not an admin" both mean "show nothing", and they have to look identical:
    // an admin row that appears a beat late has already been offered to an ordinary listener.
    final admin = ref.watch(isAdminProvider).value == true;
    if (viewer == null) return const SizedBox.shrink();

    final name = accountName(viewer.displayName, viewer.handle);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListRow(
          leading: CoverArt(
            sha256: artHashOf(viewer.avatarUrl),
            size: 40,
            shape: BoxShape.circle,
            fallbackInitial: name,
            semanticLabel: name,
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('@${viewer.handle}'),
        ),
        const Divider(height: 1),
        AccountMenuRow(
          icon: Icons.person_outline,
          label: t(CommonKeys.userMenuProfile),
          onTap: () => open('u/${Uri.encodeComponent(viewer.handle)}'),
        ),
        AccountMenuRow(
          icon: Icons.people_outline,
          label: t(CommonKeys.navFriends),
          onTap: () => open('friends'),
        ),
        AccountMenuRow(
          icon: Icons.folder_copy_outlined,
          label: t(CommonKeys.userMenuLibraries),
          onTap: () => open('libraries'),
        ),
        AccountMenuRow(
          icon: Icons.settings_outlined,
          label: t(CommonKeys.userMenuSettings),
          onTap: () => open('settings'),
        ),
        if (admin)
          AccountMenuRow(
            icon: Icons.shield_outlined,
            label: t(CommonKeys.userMenuAdmin),
            onTap: () => open('admin'),
          ),
        const Divider(height: 1),
        // Its own section, in the destructive colour — the web bordered it off from the
        // destinations above for the same reason.
        AccountMenuRow(
          icon: Icons.logout_rounded,
          label: t(CommonKeys.userMenuSignOut),
          colour: scheme.error,
          onTap: () => unawaited(_signOut(context, ref)),
        ),
      ],
    );
  }

  /// Confirmed, and named after the hub being left: this phone can hold several, and signing out of
  /// the wrong one costs a re-pair. The same confirmation the settings screen asks for.
  Future<void> _signOut(BuildContext sheetContext, WidgetRef ref) async {
    final t = ref.read(translationsProvider).call;
    final hub = ref.read(activeHubProvider)?.name ?? '';
    // Read before the sheet is popped: this `ref` dies with it, and the sign-out runs after.
    final auth = ref.read(authControllerProvider.notifier);

    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: Text(t(CommonKeys.actionsSignOut)),
        content: Text(t(SettingsKeys.accountSignOutConfirm, {'hub': hub})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t(CommonKeys.actionsCancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t(CommonKeys.actionsSignOut)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // The sheet goes first: the router's redirect is what leaves the app, and a modal route left
    // standing would sit over the sign-in screen it lands on.
    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
    await auth.signOut();
  }
}

/// One row of the account sheet.
///
/// Shaped like [NavDrawerRow] rather than being it, because a drawer row dismisses the drawer on
/// tap and these dismiss a sheet — the same shape, a different thing to close.
@visibleForTesting
class AccountMenuRow extends StatelessWidget {
  const AccountMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
    this.colour,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Set only by the destructive row.
  final Color? colour;

  @override
  Widget build(BuildContext context) => ListRow(
    leading: Icon(icon, color: colour),
    title: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: colour == null ? null : TextStyle(color: colour),
    ),
    onTap: onTap,
  );
}
