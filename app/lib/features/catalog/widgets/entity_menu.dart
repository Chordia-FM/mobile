import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/providers.dart';
import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import './list_row.dart';

// One import for the whole menu system: half the app opens a track's menu, and asking each of
// those files to import the model AND the builders is how one of them ends up with a menu the
// others do not have.
export 'entity_actions.dart';

/// What an entity's actions ARE, with no knowledge of how they are drawn.
///
/// One definition per entity kind feeds every surface that can open a menu — the ⋮ button, a long
/// press on a row, a card, the player. The web client learned this the expensive way: the same
/// track answered differently depending on how you asked for it, because each surface built its
/// own list inline. Mobile started from the other end of the same mistake — one entity (a track)
/// had a menu and the other eleven had none at all.
///
/// The renderer below is deliberately the only thing here that knows about sheets, and the builders
/// in `entity_actions.dart` are the only things that know about the Hub. That split is what makes
/// "does an album menu offer Start radio?" a question a plain test can ask.

/// The thing a menu is about — drives the header row above the actions.
enum MenuTargetKind {
  track,
  album,
  artist,
  playlist,
  genre,
  label,
  mix,
  library,
}

@immutable
class MenuTarget {
  const MenuTarget({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.round = false,
  });

  final MenuTargetKind kind;
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;

  /// Artists are round everywhere else in the app; the header has to agree.
  final bool round;
}

/// A row that draws itself, for the few whose label depends on live state the menu does not own.
typedef MenuRowBuilder =
    Widget Function(BuildContext context, VoidCallback close);

@immutable
class MenuAction {
  const MenuAction({
    required this.id,
    required this.label,
    required this.icon,
    this.onSelect,
    this.enabled = true,
    this.destructive = false,
  }) : row = null;

  /// An action whose row is a widget of its own — the download tile, whose label depends on what is
  /// already held on the device.
  const MenuAction.custom({required this.id, required MenuRowBuilder builder})
    : row = builder,
      label = '',
      icon = null,
      onSelect = null,
      enabled = true,
      destructive = false;

  /// Stable across translations, so a test can name an action without naming its label.
  final String id;

  /// Already translated by the builder — the renderer never calls `t()` on an action.
  final String label;
  final IconData? icon;
  final FutureOr<void> Function()? onSelect;
  final bool enabled;
  final bool destructive;
  final MenuRowBuilder? row;

  bool get isEnabled => enabled && (row != null || onSelect != null);
}

/// Groups render with a divider between them; empty groups are dropped.
@immutable
class MenuSection {
  const MenuSection({required this.id, required this.items});

  final String id;
  final List<MenuAction> items;
}

@immutable
class EntityMenu {
  /// Drops the sections a builder's inline conditionals emptied, so an absent action never leaves a
  /// stray divider behind.
  factory EntityMenu({
    required MenuTarget target,
    required List<MenuSection> sections,
  }) => EntityMenu._(
    target: target,
    sections: [
      for (final section in sections)
        if (section.items.isNotEmpty) section,
    ],
  );

  const EntityMenu._({required this.target, required this.sections});

  final MenuTarget target;
  final List<MenuSection> sections;

  /// Every action id, in order — what a test asserts against.
  List<String> get actionIds => [
    for (final section in sections)
      for (final action in section.items) action.id,
  ];

  bool has(String actionId) => actionIds.contains(actionId);
}

/// Builds the menu against live state.
///
/// A callback rather than a value because the rows have to follow what they report: the heart says
/// "Save" or "Remove" depending on a provider that can settle while the sheet is open. [page] is
/// the context UNDER the sheet — the sheet's own dies with the pop, so anything that outlives it (a
/// snack bar, a navigation, another sheet) has to run against the page.
typedef EntityMenuBuilder =
    EntityMenu Function(BuildContext page, WidgetRef ref);

/// Opens an entity's actions.
///
/// A bottom sheet rather than a popup menu: these are the same actions the web client puts in a
/// right-click menu, and on a phone a sheet is the only shape that can hold a header saying WHAT is
/// being acted on — which matters when the menu was opened by long-pressing one row of forty.
Future<void> showEntityMenu(BuildContext context, EntityMenuBuilder build) {
  // Captured before the sheet exists, so no action closes over a context the pop invalidates.
  final page = Navigator.of(context).context;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _EntityMenuSheet(page: page, builder: build),
  );
}

class _EntityMenuSheet extends ConsumerWidget {
  const _EntityMenuSheet({required this.page, required this.builder});

  final BuildContext page;
  final EntityMenuBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = builder(page, ref);
    final theme = Theme.of(context);
    void close() => Navigator.of(context).pop();

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MenuHeader(target: menu.target),
            for (var i = 0; i < menu.sections.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              for (final action in menu.sections[i].items)
                if (action.row case final row?)
                  row(context, close)
                else
                  ListRow(
                    leading: Icon(
                      action.icon,
                      color: action.destructive
                          ? theme.colorScheme.error
                          : null,
                    ),
                    title: Text(
                      action.label,
                      style: action.destructive
                          ? TextStyle(color: theme.colorScheme.error)
                          : null,
                    ),
                    enabled: action.isEnabled,
                    onTap: () {
                      close();
                      unawaited(
                        Future<void>.sync(() => action.onSelect?.call()),
                      );
                    },
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.target});

  final MenuTarget target;

  @override
  Widget build(BuildContext context) {
    final subtitle = target.subtitle;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListRow(
          leading: CoverArt(
            sha256: artHashOf(target.imageUrl),
            size: 48,
            shape: target.round ? BoxShape.circle : BoxShape.rectangle,
            fallbackIcon: switch (target.kind) {
              MenuTargetKind.artist => Icons.person_rounded,
              MenuTargetKind.playlist => Icons.queue_music_rounded,
              MenuTargetKind.library => Icons.dns_rounded,
              MenuTargetKind.genre => Icons.category_rounded,
              MenuTargetKind.label => Icons.business_rounded,
              _ => Icons.album_rounded,
            },
          ),
          title: Text(
            target.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: subtitle == null
              ? null
              : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// The ⋮ button, so a menu is reachable without knowing the long-press gesture exists.
class EntityMenuButton extends ConsumerWidget {
  const EntityMenuButton({required this.menu, super.key, this.iconSize});

  final EntityMenuBuilder menu;
  final double? iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    icon: const Icon(Icons.more_vert_rounded),
    iconSize: iconSize,
    tooltip: ref.t(CommonKeys.actionsMore),
    onPressed: () => unawaited(showEntityMenu(context, menu)),
  );
}

/// Long press is the phone's right-click. Wraps anything tappable with the menu its ⋮ would open.
class EntityMenuGesture extends StatelessWidget {
  const EntityMenuGesture({required this.menu, required this.child, super.key});

  final EntityMenuBuilder menu;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onLongPress: () => unawaited(showEntityMenu(context, menu)),
    child: child,
  );
}

/// A link to this entity on the hub's public web frontend, or null when the hub never told us
/// where that is.
///
/// The `/app` prefix the client navigates under is deliberately absent: shared links resolve
/// through the frontend's public redirect stubs (`/albums/{id}`, `/artists/{id}`, `/tracks/{id}`),
/// and a link into `/app` would 404 for anyone not already signed in on that device.
Uri? shareUrlFor(WidgetRef ref, String path) {
  final frontend = ref.read(activeHubProvider)?.frontendUrl;
  return frontend?.resolve(path);
}

/// Opens the platform share sheet, or says nothing can be shared.
Future<void> shareCatalogLink(
  BuildContext context,
  WidgetRef ref, {
  required String path,
  required String title,
}) => shareCatalogPath(
  context,
  frontend: ref.read(activeHubProvider)?.frontendUrl,
  path: path,
  title: title,
  errorMessage: ref.t(ErrorsKeys.generic),
);

/// The same share, for a caller that no longer has a `WidgetRef`.
///
/// A menu action runs after the sheet that built it has popped, so it cannot read a provider — it
/// carries the frontend URL it read while the sheet was alive.
Future<void> shareCatalogPath(
  BuildContext context, {
  required Uri? frontend,
  required String path,
  required String title,
  required String errorMessage,
}) async {
  final url = frontend?.resolve(path);
  if (url == null) {
    showCatalogSnack(context, errorMessage);
    return;
  }
  await SharePlus.instance.share(ShareParams(uri: url, title: title));
}

/// One line of feedback, in the app's own snack bar styling.
void showCatalogSnack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
