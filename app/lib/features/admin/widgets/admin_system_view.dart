import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/tokens.dart';
import '../../catalog/widgets/catalog_state.dart';
import '../../catalog/widgets/list_row.dart';
import '../../library/data/formatting.dart';
import '../data/admin_providers.dart';
import 'admin_widgets.dart';

/// Operator health: version, database size, rollup lag and the enrichment backlog.
///
/// Everything an admin would otherwise open psql for — and the honest list of what this phone
/// deliberately does not carry.
class AdminSystemView extends ConsumerWidget {
  const AdminSystemView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;
    final system = ref.watch(adminSystemProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(adminSystemProvider);
        await ref.read(adminSystemProvider.future);
      },
      child: CatalogBody<AdminSystemHealth>(
        value: system,
        errorTitle: t(AdminKeys.systemLoadFailed),
        onRetry: () => ref.invalidate(adminSystemProvider),
        skeleton: const _SystemSkeleton(),
        builder: (context, health) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            AdminSection(title: t(AdminKeys.tabsSystem)),
            AdminStatGrid(
              children: [
                AdminStat(
                  label: t(AdminKeys.systemVersion),
                  value: health.version,
                ),
                AdminStat(
                  label: t(AdminKeys.systemDatabase),
                  value: formatBytes(health.dbBytes),
                  caption: t(AdminKeys.systemPartitions, {
                    'count': health.listeningEventsPartitions,
                  }),
                ),
                AdminStat(
                  label: t(AdminKeys.systemMigrations, {
                    'count': health.migrationsApplied,
                  }),
                  value: formatAdminCount(health.migrationsApplied, locale),
                ),
              ],
            ),
            AdminSection(
              title: t(AdminKeys.systemRollups),
              description: t(AdminKeys.systemRollupLagHelp),
            ),
            if (health.rollups.isEmpty)
              CatalogEmpty(message: t(AdminKeys.systemNoRollups))
            else
              for (final rollup in health.rollups)
                ListRow(
                  title: Text(rollup.name),
                  subtitle: Text(
                    rollup.lagSeconds <= 0
                        ? t(AdminKeys.systemKeepingUp)
                        : '${t(AdminKeys.systemBehind)}: '
                              '${_lag(rollup.lagSeconds, locale)}',
                  ),
                  trailing: Icon(
                    rollup.lagSeconds <= 60
                        ? PhosphorIconsFill.checkCircle
                        : PhosphorIconsRegular.clock,
                    color: rollup.lagSeconds <= 60
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            AdminSection(title: t(AdminKeys.systemEnrichment)),
            _Backlog(backlog: health.enrichment, locale: locale),
            AdminSection(
              title: t(AdminKeys.systemBiggestTables),
              description: t(AdminKeys.systemSizeDesc),
            ),
            for (final table in health.biggestTables)
              ListRow(
                title: Text(table.name),
                subtitle: Text(
                  '${t(AdminKeys.systemRows)}: '
                  '${formatAdminCount(table.rows, locale)}',
                ),
                trailing: Text(formatBytes(table.bytes)),
              ),
            const _DesktopOnlyNote(),
          ],
        ),
      ),
    );
  }
}

/// Lag as the coarsest unit that still says something useful.
String _lag(int seconds, String locale) {
  if (seconds < 120) return '${formatAdminCount(seconds, locale)}s';
  if (seconds < 7200) return '${formatAdminCount(seconds ~/ 60, locale)}m';
  return '${formatAdminCount(seconds ~/ 3600, locale)}h';
}

class _Backlog extends ConsumerWidget {
  const _Backlog({required this.backlog, required this.locale});

  final AdminEnrichmentBacklog backlog;
  final String locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return AdminStatGrid(
      children: [
        AdminStat(
          label: t(AdminKeys.systemArtistsMissingArt),
          value: formatAdminCount(backlog.artistsMissingArt, locale),
        ),
        AdminStat(
          label: t(AdminKeys.systemArtistsNeverEnriched),
          value: formatAdminCount(backlog.artistsNeverEnriched, locale),
        ),
        AdminStat(
          label: t(AdminKeys.systemTracksMissingRecording),
          value: formatAdminCount(backlog.tracksMissingRecording, locale),
        ),
        AdminStat(
          label: t(AdminKeys.systemTracksMissingIsrcs),
          value: formatAdminCount(backlog.tracksMissingIsrcs, locale),
        ),
        AdminStat(
          label: t(AdminKeys.systemTracksMissingLyrics),
          value: formatAdminCount(backlog.tracksMissingLyrics, locale),
        ),
      ],
    );
  }
}

/// Says out loud which admin surfaces this client does not carry.
///
/// Named rather than silently absent: an operator who knows Backups exists and cannot find it will
/// assume the phone is broken or the feature was dropped. Saying "on purpose, and where to find
/// it" costs one card and answers both.
class _DesktopOnlyNote extends ConsumerWidget {
  const _DesktopOnlyNote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 24, 12, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: ChordiaRadius.xlAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsRegular.monitor, size: 18),
              const SizedBox(width: 8),
              Text(
                t(AdminKeys.desktopOnlyTitle),
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t(AdminKeys.desktopOnlyBody),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '· ${t(AdminKeys.tabsBackups)}\n· ${t(AdminKeys.tabsExplorer)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SystemSkeleton extends StatelessWidget {
  const _SystemSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const SkeletonBox(width: 140, height: 20),
      const SizedBox(height: 16),
      const Row(
        children: [
          Expanded(child: SkeletonBox(height: 84)),
          SizedBox(width: 8),
          Expanded(child: SkeletonBox(height: 84)),
        ],
      ),
      const SizedBox(height: 24),
      for (var i = 0; i < 6; i++) ...[
        const SkeletonBox(height: 40),
        const SizedBox(height: 12),
      ],
    ],
  );
}
