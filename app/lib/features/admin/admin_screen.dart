import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/catalog_state.dart';
import 'data/admin_providers.dart';
import 'widgets/admin_audit_view.dart';
import 'widgets/admin_content_view.dart';
import 'widgets/admin_moderation_view.dart';
import 'widgets/admin_overview_view.dart';
import 'widgets/admin_system_view.dart';
import 'widgets/admin_users_view.dart';

/// Site administration, gated on the caller actually being an admin.
///
/// The gate is a real check against `/v1/me`, not a guess from a badge or a cached flag, and it is
/// belt-and-braces: every route underneath is enforced by the Hub's own `AdminUser` extractor, so
/// a client that got this wrong would meet a 403 rather than see anything. What the gate buys is
/// an honest screen instead of six tabs of error cards.
///
/// **Six tabs, not eight.** Backups and the data explorer are deliberately absent — see the note
/// at the foot of the System tab, which names them rather than letting their absence read as a
/// bug.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final isAdmin = ref.watch(isAdminProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t(AdminKeys.title))),
      body: CatalogBody<bool>(
        value: isAdmin,
        errorTitle: t(AdminKeys.overviewLoadFailed),
        onRetry: () => ref.invalidate(isAdminProvider),
        skeleton: const Center(child: CircularProgressIndicator()),
        builder: (context, allowed) =>
            allowed ? const _AdminTabs() : const _NoAccess(),
      ),
    );
  }
}

class _AdminTabs extends ConsumerWidget {
  const _AdminTabs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return DefaultTabController(
      length: 6,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: t(AdminKeys.tabsOverview)),
              Tab(text: t(AdminKeys.tabsUsers)),
              Tab(text: t(AdminKeys.tabsContent)),
              Tab(text: t(AdminKeys.tabsModeration)),
              Tab(text: t(AdminKeys.tabsAudit)),
              Tab(text: t(AdminKeys.tabsSystem)),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                AdminOverviewView(),
                AdminUsersView(),
                AdminContentView(),
                AdminModerationView(),
                AdminAuditView(),
                AdminSystemView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What a non-admin sees: a sentence and a way out, not an empty shell of tabs.
class _NoAccess extends ConsumerWidget {
  const _NoAccess();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsRegular.lockSimple,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              t(AdminKeys.noAccessTitle),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              t(AdminKeys.noAccessPlainBody),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(t(AdminKeys.noAccessBackToApp)),
            ),
          ],
        ),
      ),
    );
  }
}
