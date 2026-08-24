import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/tokens.dart';
import '../../catalog/widgets/catalog_state.dart';
import '../data/admin_api.dart';
import '../data/admin_models.dart';
import '../data/admin_providers.dart';
import 'admin_widgets.dart';

/// The report queue, and the one thing a queue is for: closing an entry.
///
/// Resolve and Dismiss are the only writes the phone's admin section makes. Suspending, deleting
/// and badge editing stay on the desktop clients — they are consequential enough to want a
/// keyboard and the fuller context those screens show.
class AdminModerationView extends ConsumerStatefulWidget {
  const AdminModerationView({super.key});

  @override
  ConsumerState<AdminModerationView> createState() =>
      _AdminModerationViewState();
}

class _AdminModerationViewState extends ConsumerState<AdminModerationView> {
  String _status = 'open';

  Future<void> _close(ModerationReport report, String action) async {
    final t = ref.t;
    final api = ref.read(adminApiProvider);
    if (api == null) return;
    try {
      await api.resolveReport(report.id, action);
      ref.invalidate(adminReportsProvider(_status));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              describeAdminFailure(error, t, AdminKeys.moderationLoadFailed),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;
    final reports = ref.watch(adminReportsProvider(_status));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'open',
                label: Text(t(AdminKeys.reportsStatusOpen)),
              ),
              ButtonSegment(
                value: 'resolved',
                label: Text(t(AdminKeys.reportsStatusResolved)),
              ),
              ButtonSegment(
                value: 'dismissed',
                label: Text(t(AdminKeys.reportsStatusDismissed)),
              ),
            ],
            selected: {_status},
            onSelectionChanged: (picked) =>
                setState(() => _status = picked.first),
          ),
        ),
        Expanded(
          child: CatalogBody<List<ModerationReport>>(
            value: reports,
            errorTitle: t(AdminKeys.moderationLoadFailed),
            onRetry: () => ref.invalidate(adminReportsProvider(_status)),
            skeleton: const _QueueSkeleton(),
            builder: (context, rows) => rows.isEmpty
                ? CatalogEmpty(message: t(AdminKeys.reportsEmpty))
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    itemCount: rows.length,
                    itemBuilder: (context, index) => _ReportCard(
                      report: rows[index],
                      locale: locale,
                      onResolve: () => _close(rows[index], 'resolved'),
                      onDismiss: () => _close(rows[index], 'dismissed'),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ReportCard extends ConsumerWidget {
  const _ReportCard({
    required this.report,
    required this.locale,
    required this.onResolve,
    required this.onDismiss,
  });

  final ModerationReport report;
  final String locale;
  final VoidCallback onResolve;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final open = report.status == 'open';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: ChordiaRadius.xlAll,
        // `rounded-xl border border-border bg-card p-3` (`admin/moderation.tsx:121`). The
        // hairline is not decoration: on this palette a card and the page behind it are close
        // enough in lightness that an edgeless card reads as no card at all.
        border: Border.all(color: theme.colorScheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(report.reason, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            [
              if (report.reporterHandle != null) '@${report.reporterHandle}',
              if (report.targetHandle != null) '→ @${report.targetHandle}',
              t(AdminKeys.reportsCreatedAt, {
                'date': formatAdminMoment(report.createdAtMs, locale),
              }),
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (report.details != null) ...[
            const SizedBox(height: 8),
            Text(report.details!, style: theme.textTheme.bodyMedium),
          ],
          if (open) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDismiss,
                  child: Text(t(AdminKeys.reportsDismiss)),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: onResolve,
                  child: Text(t(AdminKeys.reportsResolve)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _QueueSkeleton extends StatelessWidget {
  const _QueueSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      for (var i = 0; i < 4; i++) ...[
        const SkeletonBox(height: 96),
        const SizedBox(height: 12),
      ],
    ],
  );
}
