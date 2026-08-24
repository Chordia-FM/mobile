import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/playback/adaptive.dart';
import '../../data/playback/quality.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/surface.dart';
import '../../widgets/tokens.dart';
import '../catalog/widgets/list_row.dart';
import '../settings/data/settings_controller.dart';
import '../settings/data/settings_patch.dart';
import '../settings/widgets/settings_list.dart' show applySettingsPatch;

/// What is playing, and the one thing the listener can do about it.
///
/// A seam of its own rather than reaching for [adaptiveQualityProvider] from the widgets: that
/// provider builds the whole adaptation service — engine, cache probe, connectivity — which a
/// widget test cannot stand up, and "is the quality sheet reachable from the player?" is exactly
/// the kind of question that has to stay testable.
@immutable
class QualityControl {
  const QualityControl({required this.status, required this.restore});

  final ValueListenable<QualityStatus> status;

  /// Undoes an automatic downgrade, back up to the listener's ceiling.
  final Future<void> Function() restore;
}

final qualityControlProvider = Provider<QualityControl>((ref) {
  final service = ref.watch(adaptiveQualityProvider);
  return QualityControl(status: service.status, restore: service.restore);
});

/// Opens the streaming-quality readout.
Future<void> showQualitySheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const QualitySheet(),
    );

/// The player's way in: what tier is sounding, and a warning when it is not the one chosen.
///
/// The controller has always computed the downgrade and nothing ever showed it — the sheet that
/// explains it had no caller at all, so the ladder, the reason and Restore were unreachable. This
/// is that entry point, and it doubles as the readout: a listener who never opens it still sees
/// which tier is playing.
class QualityButton extends ConsumerWidget {
  const QualityButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return ValueListenableBuilder<QualityStatus>(
      valueListenable: ref.watch(qualityControlProvider).status,
      builder: (context, status, _) {
        final limited = status.limit != QualityLimit.none;
        return TextButton.icon(
          onPressed: () => unawaited(showQualitySheet(context)),
          icon: Icon(
            limited ? Icons.warning_amber_rounded : Icons.graphic_eq_rounded,
            size: 18,
            color: limited
                ? context.surfaces.accent
                : ChordiaColors.mutedForeground,
          ),
          label: Text(
            t(qualityLabelKeyOf(status.playing)),
            style: TextStyle(
              color: limited
                  ? context.surfaces.accent
                  : ChordiaColors.mutedForeground,
            ),
          ),
        );
      },
    );
  }
}

/// What tier is streaming, what was asked for, and the choice between the four.
///
/// The web opens `QualityModal` from the expanded player's `…` (ExpandedPlayer.tsx:224-227) and
/// every row in it is a radio that writes the setting on the spot (QualityModal.tsx:58-68) — two
/// taps from the player to change tier. This sheet used to render the same four tiers inert, on
/// the reasoning that the account's tier belongs to the settings screen. That reasoning does not
/// survive contact with [applySettingsPatch]: it is the *same* call the settings screen makes, it
/// persists to the account, and it is optimistic, so the row moves under the finger. The
/// capability was there and only the call site was missing.
///
/// Two different facts share these rows, and they are drawn in two different columns because they
/// disagree often enough to matter: the radio is what you CHOSE (settings, optimistic), and the
/// trailing meter is what is actually ARRIVING. The web splits the same pair across `QualityModal`
/// and the `FileQuality` card; on a phone there is one sheet, so they sit side by side.
class QualitySheet extends ConsumerWidget {
  const QualitySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final control = ref.watch(qualityControlProvider);
    // The settings document, not `status.chosen`: `SettingsController.patch` updates this
    // optimistically and only invalidates the playback-side read after the Hub answers, so a radio
    // driven by the status would sit still for the length of a round trip after being tapped.
    final chosen = ref
        .watch(settingsControllerProvider)
        .value
        ?.streamingQuality;

    return SafeArea(
      // The sheet's own material: `responsive-dialog.tsx:206` draws a sheet and a dialog as one
      // element carrying `island-shell island-shell-modal`, which is [ModalPanel]. A `Material`
      // still has to sit between that and the tier rows — a plain decoration between a row and the
      // nearest Material is where its press fill goes to die, and Flutter asserts on exactly that.
      child: ModalPanel(
        padding: EdgeInsets.zero,
        borderRadius: ChordiaRadius.sheetTop,
        child: Material(
          type: MaterialType.transparency,
          child: ValueListenableBuilder<QualityStatus>(
            valueListenable: control.status,
            builder: (context, status, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      t(SettingsKeys.qualityTitle),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                QualityNote(status: status),
                for (final profile in qualityLadder)
                  _TierRow(
                    profile: profile,
                    status: status,
                    // Before the settings read lands there is still a defensible answer: the tier
                    // the adaptive service was built with. It is the same document, one read older.
                    chosen: chosen ?? status.chosen,
                  ),
                if (status.restorable)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          await control.restore();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        child: Text(t(PlayerKeys.qualityRestore)),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The one line that says why what is playing is not what was chosen.
///
/// Public, and shared by the sheet and the file-quality card on the now-playing tab: the web draws
/// the same sentence in `NowPlayingPanel.tsx:349-375` and calls it "the one line in the card
/// telling the listener they are not hearing what they picked". Two surfaces wording that
/// differently would be worse than either of them alone.
class QualityNote extends ConsumerWidget {
  const QualityNote({
    required this.status,
    super.key,
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 12),
  });

  final QualityStatus status;

  /// The sheet insets it to its own gutter; a card already has one.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);

    final message = switch (status) {
      // A downloaded or fully cached track is not being fetched at all, so neither the tier nor the
      // connection has anything to do with what is sounding. Saying "reduced" there would be a lie
      // about a file that is simply what it is.
      QualityStatus(fixed: true) => t(PlayerKeys.qualityFixedLocal),
      QualityStatus(limit: QualityLimit.adaptive) => t(
        PlayerKeys.qualityReducedAdaptive,
        {'selected': t(qualityLabelKeyOf(status.ceiling))},
      ),
      QualityStatus(limit: QualityLimit.network) => t(
        PlayerKeys.qualityReducedNetwork,
        {'selected': t(qualityLabelKeyOf(status.chosen))},
      ),
      _ => null,
    };
    if (message == null) return const SizedBox(height: 8);

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2, right: 10),
            child: Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: ChordiaColors.mutedForeground,
            ),
          ),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ChordiaColors.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One tier, as a choice.
class _TierRow extends ConsumerWidget {
  const _TierRow({
    required this.profile,
    required this.status,
    required this.chosen,
  });

  final QualityProfile profile;
  final QualityStatus status;

  /// The tier in the listener's settings — what the radio reflects and what a tap writes.
  final QualityProfile chosen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final playing = profile == status.playing && !status.fixed;
    final selected = profile == chosen;

    return ListRow(
      onTap: selected
          ? null
          : () => unawaited(
              applySettingsPatch(
                context,
                ref,
                SettingsPatch(streamingQuality: profile),
              ),
            ),
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_off_rounded,
        color: selected
            ? context.surfaces.accent
            : ChordiaColors.mutedForeground.withValues(alpha: 0.7),
        size: 22,
      ),
      // The row's own type scale carries the rest: `ListRow` is `text-sm` over a muted `text-xs`,
      // which is the web's list row. Only the chosen tier's weight is this row's business — the
      // Material `selected:` tint it used to lean on has no counterpart on the web, where a picked
      // option is marked by its radio and nothing else.
      title: Text(
        t(qualityLabelKeyOf(profile)),
        style: selected ? const TextStyle(fontWeight: ChordiaType.bold) : null,
      ),
      subtitle: Text(t(_descKeyOf(profile))),
      // The meter marks the tier the bytes NOW SOUNDING were fetched at, which is not always the
      // one chosen — that divergence is the whole reason this sheet exists, and putting it in the
      // radio's own column would have made the two claims look like one.
      trailing: playing
          ? Semantics(
              label: t(PlayerKeys.qualityPlayingAt),
              child: Icon(
                Icons.graphic_eq_rounded,
                size: 20,
                color: context.surfaces.accent,
              ),
            )
          : null,
    );
  }
}

/// The settings screen's tier names, reused so the two surfaces cannot drift apart.
String qualityLabelKeyOf(QualityProfile profile) => switch (profile) {
  QualityProfile.original => SettingsKeys.qualityLosslessLabel,
  QualityProfile.high => SettingsKeys.qualityHighLabel,
  QualityProfile.normal => SettingsKeys.qualityNormalLabel,
  QualityProfile.dataSaver => SettingsKeys.qualityDataSaverLabel,
};

String _descKeyOf(QualityProfile profile) => switch (profile) {
  QualityProfile.original => SettingsKeys.qualityLosslessDesc,
  QualityProfile.high => SettingsKeys.qualityHighDesc,
  QualityProfile.normal => SettingsKeys.qualityNormalDesc,
  QualityProfile.dataSaver => SettingsKeys.qualityDataSaverDesc,
};
