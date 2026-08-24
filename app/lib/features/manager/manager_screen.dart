import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'widgets/coverage_view.dart';
import 'widgets/discover_view.dart';
import 'widgets/follows_view.dart';

/// The Manager: coverage, discovery and follows.
///
/// A **viewing** surface. It answers "how complete is what I own", "what else exists", and "whose
/// next release should I hear about" — and stops there. There is deliberately no action on a
/// missing release: seeing the gap is the product.
class ManagerScreen extends ConsumerWidget {
  const ManagerScreen({super.key, this.query});

  /// A search term off `manager?q=`, from an "Open in Discover" on something with no MusicBrainz id
  /// — a track, always, since none travel on the wire.
  ///
  /// It picks the tab the reader was sent to AND seeds the search field, so arriving from a menu
  /// shows the results rather than an empty box on the right tab.
  final String? query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final term = query?.trim() ?? '';
    return DefaultTabController(
      length: 3,
      initialIndex: term.isEmpty ? 0 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t(ManagerKeys.title)),
          bottom: TabBar(
            tabs: [
              Tab(text: t(ManagerKeys.tabsCoverage)),
              Tab(text: t(ManagerKeys.tabsDiscover)),
              Tab(text: t(ManagerKeys.tabsFollows)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const CoverageView(),
            DiscoverView(initialQuery: term.isEmpty ? null : term),
            const FollowsView(),
          ],
        ),
      ),
    );
  }
}
