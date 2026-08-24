import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/surface.dart';
import '../../../widgets/tokens.dart';
import '../../catalog/catalog_routes.dart';
import '../format.dart';
import 'entity_kind_menu.dart';

/// The Overview's hero card: one card per entity kind, leading with the #1's artwork full bleed
/// and the runners-up ranked beneath.
///
/// Ported from `frontend/src/components/insights/TopEntityCard.tsx:29-92`, which is what the web
/// draws at every width — its wrapper is `grid-cols-1 … md:grid-cols-3`, so a phone gets these
/// cards stacked, not a fallback. Three identical ten-row lists carried the same facts and none of
/// the ranking: the report read as a table of numbers instead of as a report.
///
/// Four runners-up, matching the web. The rest of the chart is not lost — it is the Charts tab,
/// which pages the whole thing — and a card that runs to rank ten is a screen and a half of scroll
/// before the next kind starts.
class TopEntityCard extends ConsumerWidget {
  const TopEntityCard({
    required this.title,
    required this.items,
    required this.kind,
    super.key,
    this.action,
  });

  final String title;
  final List<TopItem> items;
  final EntityKind kind;

  /// A control pinned over the hero artwork — the share-grid export, on the kinds that have one.
  final Widget? action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) return const SizedBox.shrink();
    final t = ref.t;
    final theme = Theme.of(context);
    final first = items.first;
    final rest = items.skip(1).take(4).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: IslandPanel(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: ChordiaRadius.xlAll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  // The artwork only, not the whole stack: the scrim above it ignores pointers and
                  // the share control on top is its own target, so a long press anywhere on the
                  // hero reaches this and nothing else.
                  EntityKindMenu(
                    kind: kind,
                    item: first,
                    child: InkWell(
                      onTap: () => openEntity(context, kind, first.id),
                      child: LayoutBuilder(
                        // The cover is square and fills the card, so its side IS the card's width
                        // — the one number `CoverArt` needs, and the one this widget cannot know
                        // until it is laid out.
                        builder: (context, constraints) => CoverArt(
                          sha256: artHashOf(first.imageUrl),
                          size: constraints.maxWidth,
                          borderRadius: BorderRadius.zero,
                          semanticLabel: first.name,
                        ),
                      ),
                    ),
                  ),
                  // The scrim is a fixed black gradient over artwork, so the caption on it is
                  // literal white rather than a theme colour: the ink has to read against whatever
                  // the cover happens to be, not against the app's surface.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x00000000),
                              Color(0x73000000),
                              Color(0xD9000000),
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white70,
                                letterSpacing: 1,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              first.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${t(InsightsKeys.topPlaysCount, {'count': first.plays})}'
                              ' · ${msToTime(first.msPlayed, t)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (action case final control?)
                    Positioned(top: 8, right: 8, child: control),
                ],
              ),
              if (rest.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      for (final (index, item) in rest.indexed)
                        _RunnerUp(rank: index + 2, item: item, kind: kind),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunnerUp extends ConsumerWidget {
  const _RunnerUp({required this.rank, required this.item, required this.kind});

  final int rank;
  final TopItem item;
  final EntityKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    return EntityKindMenu(
      kind: kind,
      item: item,
      child: InkWell(
        borderRadius: ChordiaRadius.lgAll,
        onTap: () => openEntity(context, kind, item.id),
        child: Padding(
          // Taller than the web's `py-1.5`: every row here is a tap target, and the touch scale is
          // what `--control-h-*` collapses to under `pointer: coarse`.
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              CoverArt(
                sha256: artHashOf(item.imageUrl),
                size: 28,
                shape: kind == EntityKind.artist
                    ? BoxShape.circle
                    : BoxShape.rectangle,
                semanticLabel: item.name,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                t(InsightsKeys.topPlaysCount, {'count': item.plays}),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where a top row goes. Shared with [TopList] so the Overview's card and the Charts tab's list
/// cannot drift into two different destinations for the same name.
void openEntity(BuildContext context, EntityKind kind, String id) =>
    switch (kind) {
      EntityKind.artist => context.goToArtist(id),
      EntityKind.album => context.goToAlbum(id),
      EntityKind.track => context.goToTrack(id),
    };
