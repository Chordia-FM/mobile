import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/list_row.dart';
import '../../widgets/cover_art.dart';
import '../library/widgets/library_states.dart';
import 'data/libraries_api.dart';
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

    return ListRow(
      leading: CoverArt(
        sha256: artHashOf(summary.imageUrl),
        size: 40,
        shape: summary.kind == OverrideKind.artist
            ? BoxShape.circle
            : BoxShape.rectangle,
        fallbackIcon: switch (summary.kind) {
          OverrideKind.artist => Icons.person_rounded,
          OverrideKind.album => Icons.album_rounded,
          OverrideKind.track => Icons.music_note_rounded,
        },
      ),
      title: Text(summary.name),
      subtitle: Text(
        // The catalog's own name, present only when the override changes it — so a row shows both
        // what the library calls it and what everyone else does.
        summary.originalName == null
            ? subtitle
            : '$subtitle\n${t(LibraryKeys.metadataOverridesWasCalled, {'name': summary.originalName})}',
      ),
      // The whole point of this page is answering "what have I changed", and the answer people
      // want to act on most often is "put that one back". Reaching it only by opening the editor
      // and scrolling past every field to a text button at the bottom is the long way round.
      trailing: IconButton(
        icon: const Icon(Icons.settings_backup_restore_rounded),
        tooltip: t(LibraryKeys.metadataOverridesReset),
        onPressed: () => unawaited(_reset(context, ref)),
      ),
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

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final api = ref.read(overridesApiProvider);
    if (api == null || !await askToClearOverride(context, ref)) return;
    final t = ref.read(translationsProvider).call;
    try {
      await clearOverride(
        api,
        libraryId: libraryId,
        kind: summary.kind,
        entityId: summary.id,
      );
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(LibraryKeys.metadataOverridesSaveFailed))),
        );
      }
      return;
    }
    ref.invalidate(libraryOverridesProvider(libraryId));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(LibraryKeys.metadataOverridesResetDone))),
      );
    }
  }
}

/// The "are you sure" every route to clearing an override goes through.
///
/// Shared with the editor sheet's own reset button so both spell the warning the same way: an
/// override is the only record that the catalog was ever wrong about this entity, and clearing it
/// cannot be undone by re-typing what you remember it saying.
Future<bool> askToClearOverride(BuildContext context, WidgetRef ref) async {
  final t = ref.read(translationsProvider).call;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: Text(t(LibraryKeys.metadataOverridesResetConfirm)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(t(CommonKeys.actionsCancel)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(t(LibraryKeys.metadataOverridesReset)),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Clears one override, whichever kind of entity it is on.
Future<void> clearOverride(
  OverridesApi api, {
  required String libraryId,
  required OverrideKind kind,
  required String entityId,
}) => switch (kind) {
  OverrideKind.artist => api.clearArtist(libraryId, entityId),
  OverrideKind.album => api.clearAlbum(libraryId, entityId),
  OverrideKind.track => api.clearTrack(libraryId, entityId),
};

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
