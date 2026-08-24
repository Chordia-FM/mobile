import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import 'data/catalog_providers.dart';
import 'format.dart';
import 'widgets/album_grid.dart';
import 'widgets/catalog_state.dart';
import 'widgets/entity_menu.dart';
import 'widgets/section.dart';

/// One label: what it is, and everything of theirs in reach.
class LabelScreen extends ConsumerWidget {
  const LabelScreen({required this.labelId, super.key});

  final String labelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final label = ref.watch(labelDetailProvider(labelId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          label.value?.name ?? t(CatalogKeys.labelEyebrow),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          EntityMenuButton(
            menu: (page, sheetRef) => labelMenu(
              page,
              sheetRef,
              labelId: labelId,
              name: label.value?.name ?? t(CatalogKeys.labelEyebrow),
              logoUrl: label.value?.logoUrl,
            ),
          ),
        ],
      ),
      body: CatalogBody<LabelDetail>(
        value: label,
        errorTitle: t(ErrorsKeys.catalogLabelLoadFailed),
        onRetry: () => ref.invalidate(labelDetailProvider(labelId)),
        skeleton: const CatalogDetailSkeleton(),
        builder: (context, value) => _LabelView(label: value),
      ),
    );
  }
}

class _LabelView extends ConsumerWidget {
  const _LabelView({required this.label});

  final LabelDetail label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final formerNames = label.formerNames ?? const <String>[];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label.logoUrl != null) ...[
                  Center(
                    child: CoverArt(
                      sha256: artHashOf(label.logoUrl),
                      size: 140,
                      fallbackIcon: Icons.sell_outlined,
                      semanticLabel: label.name,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  t(CatalogKeys.labelEyebrow),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  label.name,
                  // `display-title font-bold text-4xl` (`labels/$labelId.tsx:73`).
                  style: theme.textTheme.displayLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  joinFacts([
                    label.labelType,
                    label.country,
                    _lifespan(ref, label),
                    t(CatalogKeys.albumCount, {'count': label.albums.length}),
                  ]),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (formerNames.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    t(CatalogKeys.labelFormerly, {
                      'names': formerNames.join(', '),
                    }),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (label.description != null) ...[
                  const SizedBox(height: 12),
                  ExpandableText(text: label.description!),
                ],
              ],
            ),
          ),
        ),
        if (label.albums.isEmpty)
          SliverToBoxAdapter(
            child: CatalogEmpty(message: t(CatalogKeys.labelNoAlbums)),
          )
        else ...[
          SliverToBoxAdapter(
            child: SectionHeader(title: t(CatalogKeys.sectionAlbums)),
          ),
          SliverAlbumGrid(albums: label.albums, showArtist: true),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

/// "Founded 2003 – 2019", "Founded 2003", or "Until 2019", from raw MusicBrainz partial dates.
String? _lifespan(WidgetRef ref, LabelDetail label) {
  final t = ref.t;
  final founded = yearOf(label.founded);
  final defunct = yearOf(label.defunct);
  if (founded != null && defunct != null) {
    return t(CatalogKeys.labelLifespanRange, {'from': founded, 'to': defunct});
  }
  if (founded != null) {
    return t(CatalogKeys.labelLifespanFounded, {'year': founded});
  }
  if (defunct != null) {
    return t(CatalogKeys.labelLifespanUntil, {'year': defunct});
  }
  return null;
}
