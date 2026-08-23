import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/playback/adaptive.dart';
import '../../data/playback/quality.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';

/// Opens the streaming-quality readout.
Future<void> showQualitySheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const QualitySheet(),
    );

/// What tier is streaming, what was asked for, and why they differ.
///
/// Read-only about the *choice*: the tier lives in the account's settings and changing it there is
/// the settings screen's job. The one thing this sheet can do is undo an automatic downgrade, and
/// it is here rather than there because this is where somebody notices one.
class QualitySheet extends ConsumerWidget {
  const QualitySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final service = ref.watch(adaptiveQualityProvider);

    return SafeArea(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: ChordiaColors.paneRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ValueListenableBuilder<QualityStatus>(
          valueListenable: service.status,
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
              _Explanation(status: status),
              for (final profile in qualityLadder)
                _TierRow(profile: profile, status: status),
              if (status.restorable)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        await service.restore();
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
    );
  }
}

/// The one line that says why what is playing is not what was chosen.
class _Explanation extends ConsumerWidget {
  const _Explanation({required this.status});

  final QualityStatus status;

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
        {'selected': t(_labelKeyOf(status.ceiling))},
      ),
      QualityStatus(limit: QualityLimit.network) => t(
        PlayerKeys.qualityReducedNetwork,
        {'selected': t(_labelKeyOf(status.chosen))},
      ),
      _ => null,
    };
    if (message == null) return const SizedBox(height: 8);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
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

class _TierRow extends ConsumerWidget {
  const _TierRow({required this.profile, required this.status});

  final QualityProfile profile;
  final QualityStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final playing = profile == status.playing && !status.fixed;
    final chosen = profile == status.chosen;

    return ListTile(
      // Nothing here is tappable: this sheet reports, and the account's tier is set in settings.
      // A row that looks like a choice but silently only lasts until the next launch is worse than
      // a row that plainly does not move.
      enabled: false,
      leading: Icon(
        playing ? Icons.graphic_eq_rounded : Icons.circle_outlined,
        color: playing
            ? ChordiaColors.accent
            : ChordiaColors.mutedForeground.withValues(alpha: 0.5),
        size: 20,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              t(_labelKeyOf(profile)),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: ChordiaColors.foreground,
                fontWeight: playing ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (chosen) ...[
            const SizedBox(width: 8),
            _Chip(label: t(PlayerKeys.qualityYourSetting)),
          ],
        ],
      ),
      subtitle: Text(
        t(_descKeyOf(profile)),
        style: theme.textTheme.bodySmall?.copyWith(
          color: ChordiaColors.mutedForeground,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: ChordiaColors.accent.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: ChordiaColors.accent),
    ),
  );
}

/// The settings screen's tier names, reused so the two surfaces cannot drift apart.
String _labelKeyOf(QualityProfile profile) => switch (profile) {
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
