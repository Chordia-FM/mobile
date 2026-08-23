import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/list_row.dart';
import 'manager_routes.dart';

/// The row that opens the Manager, ready to drop into any list of destinations.
///
/// Lives here rather than in the screen that shows it so wiring the Manager into a menu is one
/// widget rather than a route string, a label, an icon and a navigation call that each have to be
/// kept in step with this feature.
class ManagerEntryTile extends ConsumerWidget {
  const ManagerEntryTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return ListRow(
      leading: const Icon(Icons.donut_large_rounded),
      title: Text(t(ManagerKeys.nav)),
      subtitle: Text(t(ManagerKeys.subtitle)),
      trailing: listRowChevron,
      onTap: context.goToManager,
    );
  }
}
