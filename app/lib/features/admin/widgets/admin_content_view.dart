import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../../catalog/catalog_routes.dart';
import '../../catalog/widgets/catalog_state.dart';
import '../../catalog/widgets/list_row.dart';
import '../data/admin_providers.dart';
import 'admin_widgets.dart';

/// Look up anything in the shared catalog every account sees, and open it.
///
/// A viewing surface: editing the global catalog — renaming an artist, replacing artwork,
/// re-attributing a release — stays on the desktop clients, where the art pickers and merge flows
/// have room to be safe.
class AdminContentView extends ConsumerStatefulWidget {
  const AdminContentView({super.key});

  @override
  ConsumerState<AdminContentView> createState() => _AdminContentViewState();
}

class _AdminContentViewState extends ConsumerState<AdminContentView> {
  final _controller = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final tooShort = _query.length < adminSearchMinLength;
    final results = ref.watch(adminCatalogSearchProvider(_query));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _controller,
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), () {
                if (mounted) setState(() => _query = value.trim());
              });
            },
            decoration: InputDecoration(
              prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
              hintText: t(AdminKeys.metadataSearchPlaceholder),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            t(AdminKeys.contentDescription),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: tooShort
              ? CatalogEmpty(message: t(AdminKeys.contentEmpty))
              : CatalogBody<(List<BrowseArtist>, List<BrowseAlbum>)>(
                  value: results,
                  errorTitle: t(AdminKeys.metadataLoadError),
                  onRetry: () =>
                      ref.invalidate(adminCatalogSearchProvider(_query)),
                  skeleton: const _ContentSkeleton(),
                  builder: (context, value) =>
                      _Results(artists: value.$1, albums: value.$2),
                ),
        ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.artists, required this.albums});

  final List<BrowseArtist> artists;
  final List<BrowseAlbum> albums;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    if (artists.isEmpty && albums.isEmpty) {
      return CatalogEmpty(message: t(AdminKeys.metadataNoMatches));
    }
    return CustomScrollView(
      slivers: [
        if (artists.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: AdminSection(title: t(AdminKeys.contentArtists)),
          ),
          SliverList.builder(
            itemCount: artists.length,
            itemBuilder: (context, index) {
              final artist = artists[index];
              return ListRow(
                onTap: () => context.goToArtist(artist.id),
                leading: CoverArt(
                  sha256: artHashOf(artist.imageUrl),
                  size: 44,
                  shape: BoxShape.circle,
                  fallbackIcon: PhosphorIconsFill.microphoneStage,
                ),
                title: Text(
                  artist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  t(AdminKeys.metadataArtistSubtitle, {
                    'albumCount': artist.albumCount,
                    'trackCount': artist.trackCount,
                  }),
                ),
              );
            },
          ),
        ],
        if (albums.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: AdminSection(title: t(AdminKeys.contentAlbums)),
          ),
          SliverList.builder(
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              return ListRow(
                onTap: () => context.goToAlbum(album.id),
                leading: CoverArt(sha256: artHashOf(album.coverUrl), size: 44),
                title: Text(
                  album.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    album.artist,
                    album.year?.toString(),
                  ].where((p) => p != null && p.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _ContentSkeleton extends StatelessWidget {
  const _ContentSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      for (var i = 0; i < 7; i++) ...[
        Row(
          children: [
            const SkeletonBox(width: 44, height: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 190 - (i % 3) * 35, height: 14),
                  const SizedBox(height: 8),
                  const SkeletonBox(width: 110, height: 11),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    ],
  );
}
