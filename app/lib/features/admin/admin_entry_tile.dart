import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'admin_routes.dart';
import 'data/admin_providers.dart';

/// The row that opens site administration — and **nothing at all** for anyone who is not an admin.
///
/// Renders an empty box rather than a disabled row while the check is in flight, so a menu never
/// flashes an admin entry at an ordinary listener and then takes it away. The gate is the same
/// `/v1/me` flag the Hub enforces server-side; this only decides what is worth offering.
class AdminEntryTile extends ConsumerWidget {
  const AdminEntryTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    // `valueOrNull` rather than a loading branch: "not known yet" and "not an admin" both mean
    // "show nothing", and they should look identical.
    if (ref.watch(isAdminProvider).value != true) {
      return const SizedBox.shrink();
    }
    return ListTile(
      leading: const Icon(Icons.shield_outlined),
      title: Text(t(CommonKeys.userMenuAdmin)),
      subtitle: Text(t(AdminKeys.title)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: context.goToAdmin,
    );
  }
}
