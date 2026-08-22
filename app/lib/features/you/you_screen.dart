import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../admin/admin_entry_tile.dart';
import '../manager/manager_entry_tile.dart';

/// The account tab: who you are, and everything that is about you rather than about music.
///
/// Deliberately a plain list. It is the least-visited tab and the one people arrive at knowing
/// what they came for, so it should be scannable rather than designed.
class YouScreen extends ConsumerWidget {
  const YouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Scaffold(
      appBar: AppBar(title: Text(t(CommonKeys.navYou))),
      body: ListView(
        children: [
          _Row(
            icon: Icons.insights_outlined,
            label: t(CommonKeys.navInsights),
            onTap: () => context.go('/you/insights'),
          ),
          _Row(
            icon: Icons.people_outline,
            label: t(CommonKeys.navFriends),
            onTap: () => context.go('/you/friends'),
          ),
          const Divider(height: 1),
          const ManagerEntryTile(),
          // Renders nothing at all for anyone who is not an admin, so it is safe unconditionally.
          const AdminEntryTile(),
          const Divider(height: 1),
          _Row(
            icon: Icons.settings_outlined,
            label: t(CommonKeys.navSettings),
            onTap: () => context.go('/you/settings'),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}
