import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/list_row.dart';
import '../../widgets/cover_art.dart';
import '../libraries/library_manage_screen.dart';
import 'data/library_providers.dart';
import 'widgets/library_states.dart';

/// One library: where it lives, whether it is answering, who can reach it, and the artists in it.
///
/// The artist list is the body for the same reason it is on the web client — a library is only
/// interesting as the music inside it, and artists are the level at which a collection is browsed.
///
/// This screen READS. Renaming it, its icon, who it is shared with, its metadata overrides and
/// removing it live one level in, behind the header's settings button — the same split the web
/// client draws between `/app/library/{id}` and `/app/library/{id}/edit`.
class LibraryDetailScreen extends ConsumerWidget {
  const LibraryDetailScreen({
    required this.libraryId,
    required this.owned,
    super.key,
  });

  final String libraryId;

  /// Shares are only readable by the owner, so the section is not even asked for otherwise.
  final bool owned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final library = ref.watch(libraryDetailProvider(libraryId));
    final artists = ref.watch(catalogArtistsProvider(libraryId));

    return Scaffold(
      appBar: AppBar(
        title: Text(library.value?.name ?? t(CommonKeys.navAllLibraries)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: t(LibraryKeys.manageTitle),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    LibraryManageScreen(libraryId: libraryId, owned: owned),
              ),
            ),
          ),
        ],
      ),
      body: library.when(
        loading: () => const ListSkeleton(),
        error: (error, stack) => ErrorRetry(
          error: error,
          onRetry: () => ref.invalidate(libraryDetailProvider(libraryId)),
        ),
        data: (summary) => RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(libraryDetailProvider(libraryId))
              ..invalidate(catalogArtistsProvider(libraryId));
          },
          child: _body(context, ref, summary, artists),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    LibrarySummary summary,
    AsyncValue<List<BrowseArtist>> artists,
  ) {
    final t = ref.t;
    final rows = artists.value ?? const <BrowseArtist>[];
    // Read once, outside the item builder: `ref.watch` inside a lazily-called builder registers a
    // dependency at whatever moment a row happens to scroll into view.
    final handoff = ref.watch(libraryHandoffProvider);

    return ListView.builder(
      itemCount: rows.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Summary(summary: summary),
              if (owned) _Shares(libraryId: libraryId),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(
                  t(LibraryKeys.artistsTitle),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              ...artists.when(
                loading: () => const [ListSkeleton(rows: 4, height: 56)],
                error: (error, stack) => [
                  ErrorRetry(
                    error: error,
                    onRetry: () =>
                        ref.invalidate(catalogArtistsProvider(libraryId)),
                  ),
                ],
                data: (loaded) => [
                  if (loaded.isEmpty)
                    EmptyNote(message: t(LibraryKeys.artistsEmpty)),
                ],
              ),
            ],
          );
        }
        final artist = rows[index - 1];
        return ListRow(
          leading: CoverArt(
            sha256: artHashOf(artist.imageUrl),
            size: 40,
            shape: BoxShape.circle,
            fallbackIcon: Icons.person_rounded,
          ),
          title: Text(artist.name),
          subtitle: Text(
            t(LibraryKeys.trackCount, {'count': artist.trackCount}),
          ),
          // Disabled until the catalog milestone provides an artist screen to open.
          onTap: handoff == null
              ? null
              : () => handoff.openArtist(context, artist.id),
        );
      },
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.summary});

  final LibrarySummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final server = ref.watch(serverStatusProvider(summary.serverId));
    final endpoint = server.value?.endpoint;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.name,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t(LibraryKeys.cardTrackCount, {'count': summary.trackCount}),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (endpoint != null)
            Row(
              children: [
                Icon(
                  endpoint.online
                      ? Icons.cloud_done_rounded
                      : Icons.cloud_off_rounded,
                  size: 18,
                  color: endpoint.online
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    // The host, not the whole URL: the port and scheme are the same on every
                    // library server and say nothing about which machine this is.
                    '${t(endpoint.online ? LibraryKeys.listServerOnline : LibraryKeys.listServerOffline)} · '
                    '${Uri.tryParse(endpoint.endpoint)?.host ?? endpoint.endpoint}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Who the owner has given access to.
class _Shares extends ConsumerWidget {
  const _Shares({required this.libraryId});

  final String libraryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final shares = ref.watch(librarySharesProvider(libraryId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            t(LibraryKeys.shareManagerTitle),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        ...shares.when(
          loading: () => const [ListSkeleton(rows: 1, height: 56)],
          error: (error, stack) => [
            ErrorRetry(
              error: error,
              onRetry: () => ref.invalidate(librarySharesProvider(libraryId)),
            ),
          ],
          data: (rows) => rows.isEmpty
              ? [EmptyNote(message: t(LibraryKeys.shareManagerEmpty))]
              : [
                  for (final share in rows)
                    ListRow(
                      leading: CoverArt(
                        sha256: artHashOf(share.grantee.avatarUrl),
                        size: 40,
                        shape: BoxShape.circle,
                        fallbackIcon: Icons.person_rounded,
                      ),
                      title: Text(share.grantee.displayName),
                      subtitle: Text(
                        '@${share.grantee.handle} · '
                        '${t(share.permissionLevel == PermissionLevel.read ? LibraryKeys.sharePermissionStreamOnly : LibraryKeys.sharePermissionStreamDownload)}',
                      ),
                    ),
                ],
        ),
      ],
    );
  }
}
