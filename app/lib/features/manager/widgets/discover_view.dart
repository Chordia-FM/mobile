import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../../catalog/widgets/catalog_state.dart';
import '../../catalog/widgets/list_row.dart';
import '../data/coverage_format.dart';
import '../data/manager_providers.dart';
import '../data/releases.dart';
import '../manager_routes.dart';
import 'manager_widgets.dart';

/// Browse-all search over the Hub's MusicBrainz cache: artists and release groups, owned-tagged.
///
/// Nothing here acts on a result that is missing from the library. Tapping one opens the detail,
/// which is where the coverage story continues.
class DiscoverView extends ConsumerStatefulWidget {
  const DiscoverView({super.key, this.initialQuery});

  /// The term a menu arrived with, off `manager?q=`.
  ///
  /// Seeded once, in [State.initState], rather than watched: this field is the reader's from the
  /// first keystroke, and re-applying the URL's term on a later rebuild would overwrite what they
  /// had typed.
  final String? initialQuery;

  @override
  ConsumerState<DiscoverView> createState() => _DiscoverViewState();
}

class _DiscoverViewState extends ConsumerState<DiscoverView> {
  late final _controller = TextEditingController(
    text: widget.initialQuery ?? '',
  );

  /// The query the provider is actually keyed on. Separate from the field's text so a family
  /// provider is not created per keystroke — each one would be its own in-flight request.
  late String _query = widget.initialQuery?.trim() ?? '';

  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final tooShort = _query.length < minDiscoverQueryLength;
    final results = ref.watch(discoverProvider(_query));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _controller,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (value) {
              _debounce?.cancel();
              setState(() => _query = value.trim());
            },
            decoration: InputDecoration(
              prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
              hintText: t(ManagerKeys.discoverPlaceholder),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: tooShort
              ? CatalogEmpty(message: t(ManagerKeys.discoverHint))
              : CatalogBody<DiscoverResults>(
                  value: results,
                  errorTitle: t(ManagerKeys.loadFailed),
                  onRetry: () => ref.invalidate(discoverProvider(_query)),
                  skeleton: const ManagerListSkeleton(rows: 5),
                  builder: (context, value) => _Results(results: value),
                ),
        ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.results});

  final DiscoverResults results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    if (results.artists.isEmpty && results.releaseGroups.isEmpty) {
      return CatalogEmpty(message: t(ManagerKeys.discoverNoResults));
    }

    // The same collapse the web runs over its results list (`discover/index.tsx:60-63`), and for
    // the same reason: a search for an album returns its every edition, and eight tiles of "X
    // (Deluxe)" push the artist the reader was looking for off the screen.
    final releases = groupReleases(results.releaseGroups);

    return CustomScrollView(
      slivers: [
        if (results.artists.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: ManagerSectionHeader(title: t(ManagerKeys.discoverArtists)),
          ),
          SliverList.builder(
            itemCount: results.artists.length,
            itemBuilder: (context, index) =>
                _ArtistRow(artist: results.artists[index]),
          ),
        ],
        if (releases.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: ManagerSectionHeader(title: t(ManagerKeys.discoverReleases)),
          ),
          SliverList.builder(
            itemCount: releases.length,
            itemBuilder: (context, index) {
              final release = releases[index];
              return ReleaseGroupTile(
                title: release.title,
                owned: release.owned,
                coverUrl: release.coverUrl,
                subtitle: _releaseSubtitle(release),
                onTap: () => context.goToReleaseGroup(release.mbid),
              );
            },
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

/// Artist, year and type on one line — the facts that tell two same-named releases apart.
String? _releaseSubtitle(DiscoverReleaseGroup release) {
  final parts = [
    release.artistName,
    releaseYear(release.firstReleaseDate),
    release.primaryType,
  ].where((part) => part != null && part.isNotEmpty);
  return parts.isEmpty ? null : parts.join(' · ');
}

class _ArtistRow extends ConsumerWidget {
  const _ArtistRow({required this.artist});

  final DiscoverArtist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return ListRow(
      onTap: () => context.goToDiscoverArtist(artist.mbid),
      leading: CoverArt(
        sha256: artHashOf(artist.imageUrl),
        size: 40,
        shape: BoxShape.circle,
        fallbackIcon: PhosphorIconsFill.microphoneStage,
      ),
      title: Text(artist.name),
      subtitle: Text(
        [
          artist.disambiguation,
          artist.genres?.take(2).join(', '),
        ].where((part) => part != null && part.isNotEmpty).join(' · '),
      ),
      trailing: OwnedBadge(
        owned: artist.owned,
        ownedLabel: t(ManagerKeys.discoverOwned),
        missingLabel: t(ManagerKeys.discoverAvailable),
      ),
    );
  }
}
