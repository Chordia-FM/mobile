import 'package:chordia_sync/chordia_sync.dart' show PlayerTrack, TrackVariant;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/tokens.dart';

/// The markers that qualify the playing recording: explicit, and whatever was lifted out of the
/// title — live, acoustic, remix.
///
/// The title is what is LEFT once those markers were removed, so the two are read together. Drawn
/// beside the title in the player exactly as the catalog draws them beside a row, because a
/// listener who sees "EXPLICIT · LIVE" on the album page and nothing at all on the now-playing
/// screen has been shown two different products.
///
/// A twin of the catalog's `TrackBadges` rather than a reuse of it, and the split is forced: that
/// one is typed on `chordia_api`'s [TrackVariant] and a queue entry carries `chordia_sync`'s. The
/// two enums hold the same wire values — `chordia_api` depends on `chordia_sync`, never the
/// reverse, so neither can be the other.
class PlayerTrackBadges extends ConsumerWidget {
  const PlayerTrackBadges({required this.track, super.key});

  final PlayerTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final variants = track.variants ?? const <TrackVariant>[];
    if (track.advisory != 'explicit' && variants.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget chip(String label, {bool solid = false}) => Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: solid
              ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.25)
              : null,
          border: solid ? null : Border.all(color: theme.colorScheme.outline),
          borderRadius: ChordiaRadius.badgeAll,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.2,
          ),
        ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (track.advisory == 'explicit')
          Semantics(
            label: t(CatalogKeys.trackExplicit),
            child: chip(t(CatalogKeys.trackExplicitShort), solid: true),
          ),
        // Same derivation as the catalog's, for the same reason: the catalog keys ARE
        // `catalog:track.variant.<wire>`, so a variant added to the contract renders its key here
        // — visible immediately — rather than silently falling back to English.
        for (final variant in variants)
          chip(t('catalog:track.variant.${variant.wire}')),
      ],
    );
  }
}
