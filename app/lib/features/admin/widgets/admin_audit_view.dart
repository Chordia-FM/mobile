import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../../catalog/widgets/catalog_state.dart';
import '../data/admin_providers.dart';
import 'admin_widgets.dart';

/// The append-only log of every privileged action, newest first.
///
/// Read-only by definition: an audit log an operator could edit would not be one.
class AdminAuditView extends ConsumerWidget {
  const AdminAuditView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;
    final log = ref.watch(auditLogControllerProvider);
    final facets = ref.watch(adminAuditFacetsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t(AdminKeys.auditDescription),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              // The categories the log actually contains, not a hard-coded list: an action added
              // on the server shows up in the filter without a client release.
              DropdownButton<String>(
                value: log.value?.category ?? '',
                onChanged: (category) => category == null
                    ? null
                    : ref
                          .read(auditLogControllerProvider.notifier)
                          .filter(category),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(t(AdminKeys.auditAllCategories)),
                  ),
                  for (final category
                      in facets.value?.categories ?? const <String>[])
                    DropdownMenuItem(value: category, child: Text(category)),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: CatalogBody<AuditLogState>(
            value: log,
            errorTitle: t(AdminKeys.auditLoadFailed),
            onRetry: () => ref.invalidate(auditLogControllerProvider),
            skeleton: const _AuditSkeleton(),
            builder: (context, state) => state.rows.isEmpty
                ? CatalogEmpty(message: t(AdminKeys.auditNoMatches))
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    itemCount: state.rows.length + (state.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == state.rows.length) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: state.loadingMore
                                ? const CircularProgressIndicator.adaptive()
                                : OutlinedButton(
                                    onPressed: () => ref
                                        .read(
                                          auditLogControllerProvider.notifier,
                                        )
                                        .loadMore(),
                                    child: Text(t(AdminKeys.auditLoadMore)),
                                  ),
                          ),
                        );
                      }
                      return AuditEntryTile(
                        entry: state.rows[index],
                        locale: locale,
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

/// One log entry, expandable to the field-level diff behind it.
///
/// Shared with the user-detail screen, which shows the same entries filtered to one target.
class AuditEntryTile extends ConsumerWidget {
  const AuditEntryTile({required this.entry, required this.locale, super.key});

  final AuditEntry entry;
  final String locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);

    // A known action gets its sentence; an unknown one falls back to the raw verb rather than to
    // a rendered key, so an action added on the server is still legible here.
    final actionKey = 'admin:audit.actionName.${entry.action}';
    final action = ref.watch(translationsProvider).has(actionKey)
        ? t(actionKey)
        : entry.action;

    return ExpansionTile(
      leading: CoverArt(
        sha256: artHashOf(entry.targetImageUrl),
        size: 40,
        fallbackIcon: Icons.history_rounded,
      ),
      title: Text(action, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (entry.actorHandle != null) '@${entry.actorHandle}',
          if (entry.targetLabel != null) entry.targetLabel!,
          formatAdminMoment(entry.createdAtMs, locale),
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${t(AdminKeys.auditCategory)}: ${entry.category}',
          style: theme.textTheme.bodySmall,
        ),
        if (entry.targetId != null)
          Text(
            '${t(AdminKeys.auditTargetId)}: ${entry.targetId}',
            style: theme.textTheme.bodySmall,
          ),
        if (entry.detail != null)
          Text(entry.detail!, style: theme.textTheme.bodySmall),
        if (entry.backfilled) ...[
          const SizedBox(height: 6),
          Text(
            t(AdminKeys.auditBackfilledHint),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 6),
        _Diff(before: entry.before, after: entry.after),
      ],
    );
  }
}

/// What changed, field by field.
class _Diff extends ConsumerWidget {
  const _Diff({required this.before, required this.after});

  final Map<String, Object?>? before;
  final Map<String, Object?>? after;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final fields = {...?before?.keys, ...?after?.keys}.toList()..sort();
    if (fields.isEmpty) {
      return Text(
        t(AdminKeys.auditNoDiff),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    String show(Object? value) =>
        value == null ? t(AdminKeys.auditDiffUnset) : '$value';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final field in fields)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '$field: ${show(before?[field])} → ${show(after?[field])}',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _AuditSkeleton extends StatelessWidget {
  const _AuditSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      for (var i = 0; i < 8; i++) ...[
        Row(
          children: [
            const SkeletonBox(width: 40, height: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 150 - (i % 3) * 25, height: 14),
                  const SizedBox(height: 8),
                  const SkeletonBox(width: 210, height: 11),
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
