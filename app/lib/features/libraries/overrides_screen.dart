import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../library/widgets/library_states.dart';
import 'data/libraries_providers.dart';
import 'override_editor_sheet.dart';

/// Everything the owner has corrected about one library's metadata.
///
/// A list first, and search second, because the question this page exists to answer is "what have
/// I changed" — which a search-first editor cannot answer at all: an override you have forgotten
/// about is invisible until you go looking for the exact entity again.
class OverridesScreen extends ConsumerWidget {
  const OverridesScreen({required this.libraryId, super.key});

  final String libraryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final overrides = ref.watch(libraryOverridesProvider(libraryId));

    return Scaffold(
      appBar: AppBar(title: Text(t(LibraryKeys.metadataTitle))),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(libraryOverridesProvider(libraryId)),
        child: overrides.when(
          loading: () => const ListSkeleton(),
          error: (error, stack) => ErrorRetry(
            error: error,
            onRetry: () => ref.invalidate(libraryOverridesProvider(libraryId)),
          ),
          data: (rows) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  t(LibraryKeys.metadataIntro),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (rows.isEmpty)
                EmptyNote(
                  message: t(LibraryKeys.metadataOverridesNone),
                  icon: Icons.edit_note_rounded,
                )
              else
                for (final row in rows)
                  _OverrideRow(libraryId: libraryId, summary: row),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverrideRow extends ConsumerWidget {
  const _OverrideRow({required this.libraryId, required this.summary});

  final String libraryId;
  final LibraryOverrideSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final subtitle = [
      t(overrideKindKey(summary.kind)),
      // Which fields were changed, not merely that something was.
      ...summary.fields.map((field) => t(overrideFieldKey(field))),
      if (summary.overrideMain) t(LibraryKeys.metadataOverridesMain),
    ].join(' · ');

    return ListTile(
      leading: CoverArt(
        sha256: artHashOf(summary.imageUrl),
        size: 44,
        shape: summary.kind == OverrideKind.artist
            ? BoxShape.circle
            : BoxShape.rectangle,
        fallbackIcon: switch (summary.kind) {
          OverrideKind.artist => Icons.person_rounded,
          OverrideKind.album => Icons.album_rounded,
          OverrideKind.track => Icons.music_note_rounded,
        },
      ),
      title: Text(summary.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        // The catalog's own name, present only when the override changes it — so a row shows both
        // what the library calls it and what everyone else does.
        summary.originalName == null
            ? subtitle
            : '$subtitle\n${t(LibraryKeys.metadataOverridesWasCalled, {'name': summary.originalName})}',
      ),
      isThreeLine: summary.originalName != null,
      onTap: () async {
        await showOverrideEditor(
          context,
          libraryId: libraryId,
          kind: summary.kind,
          entityId: summary.id,
          name: summary.name,
        );
        ref.invalidate(libraryOverridesProvider(libraryId));
      },
    );
  }
}

String overrideKindKey(OverrideKind kind) => switch (kind) {
  OverrideKind.artist => LibraryKeys.metadataOverridesKindArtist,
  OverrideKind.album => LibraryKeys.metadataOverridesKindAlbum,
  OverrideKind.track => LibraryKeys.metadataOverridesKindTrack,
};

/// The label for one overridden field name, as the Hub spells it on the wire.
///
/// Unknown names fall back to the raw string rather than to a lookup miss: the Hub can add a field
/// this build has never heard of, and a row that says `bpm` reads badly where one that says
/// `library:metadata.overrides.field.bpm` reads as broken.
String overrideFieldKey(String field) => switch (field) {
  'album' => LibraryKeys.metadataOverridesFieldAlbum,
  'album_type' => LibraryKeys.metadataOverridesFieldAlbumType,
  'artist' => LibraryKeys.metadataOverridesFieldArtist,
  'banner' => LibraryKeys.metadataOverridesFieldBanner,
  'bio' => LibraryKeys.metadataOverridesFieldBio,
  'cover' => LibraryKeys.metadataOverridesFieldCover,
  'disc_no' => LibraryKeys.metadataOverridesFieldDiscNo,
  'genre' => LibraryKeys.metadataOverridesFieldGenre,
  'genres' => LibraryKeys.metadataOverridesFieldGenres,
  'image' => LibraryKeys.metadataOverridesFieldImage,
  'label' => LibraryKeys.metadataOverridesFieldLabel,
  'name' => LibraryKeys.metadataOverridesFieldName,
  'title' => LibraryKeys.metadataOverridesFieldTitle,
  'track_no' => LibraryKeys.metadataOverridesFieldTrackNo,
  'year' => LibraryKeys.metadataOverridesFieldYear,
  _ => field,
};
