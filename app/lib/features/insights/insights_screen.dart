import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../social/data/social_providers.dart';
import 'widgets/insights_tabs.dart';

/// The signed-in listener's own listening report.
///
/// The reports are asked for with no `user`, so the Hub answers about the caller — the handle is
/// only read to stamp a shared Wrapped card, and a card is offered as soon as it is known rather
/// than the whole page waiting on it.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewer = ref.watch(viewerProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(ref.t(InsightsKeys.title))),
      body: ListView(
        children: [
          InsightsTabView(handle: null, own: true, shareHandle: viewer?.handle),
        ],
      ),
    );
  }
}
