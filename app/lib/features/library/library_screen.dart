import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/placeholder_screen.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      PlaceholderScreen(title: ref.t(CommonKeys.navLibrary));
}
