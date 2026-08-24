import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../catalog/data/catalog_api.dart';
import '../../catalog/widgets/entity_menu.dart';

/// Attaches the right menu to a row whose entity kind is only known at runtime.
///
/// The insights lists are the one place in the app that render artists, albums and tracks through a
/// single component, so they are also the one place that cannot name its menu at the call site.
/// Ported from `components/ui/entity-kind-menu.tsx`, which exists for exactly this and is what
/// gives the web's charts a right-click menu on every ranked row.
///
/// A kindless row — the genre lists, which key off a slug rather than a catalog id — mounts no
/// gesture at all and renders its child directly, as the web's does.
///
/// The rows carry no MusicBrainz id (`TopItem` has none on the wire), so "Open in Discover" is
/// simply absent here rather than degrading to a name search: the phone's Manager route takes no
/// query, which is the same reason `_discoverAction` returns null without an mbid.
class EntityKindMenu extends ConsumerWidget {
  const EntityKindMenu({
    required this.item,
    required this.child,
    super.key,
    this.kind,
  });

  final TopItem item;

  /// Null for the rows that are not catalog entities; those get no menu.
  final EntityKind? kind;

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (kind) {
    EntityKind.album => EntityMenuGesture(
      menu: (page, sheetRef) => albumMenu(
        page,
        sheetRef,
        AlbumLike(id: item.id, title: item.name, coverUrl: item.imageUrl),
      ),
      child: child,
    ),
    EntityKind.artist => EntityMenuGesture(
      menu: (page, sheetRef) => artistMenu(
        page,
        sheetRef,
        ArtistLike(id: item.id, name: item.name, imageUrl: item.imageUrl),
      ),
      child: child,
    ),
    // A track's menu needs the whole catalog row — the library it lives in and the ref the stream
    // URL is built from — and a chart row carries a name and a play count. So this one fetches
    // before it opens, rather than fabricating a `BrowseTrack` whose Play, Queue and Download
    // would all be rows that do nothing. One request, only on a long press that actually happens.
    EntityKind.track => GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => unawaited(_openTrackMenu(context, ref)),
      child: child,
    ),
    null => child,
  };

  Future<void> _openTrackMenu(BuildContext context, WidgetRef ref) async {
    final failed = ref.t(ErrorsKeys.failedToLoad);
    try {
      final track = await ref.read(catalogApiProvider).track(item.id);
      if (!context.mounted) return;
      await showTrackMenu(context, ref, track);
    } on Object {
      if (context.mounted) showCatalogSnack(context, failed);
    }
  }
}
