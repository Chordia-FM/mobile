import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../i18n/keys.g.dart';
import '../i18n/translations_provider.dart';

/// The persistent frame: tab bar at the bottom, mini-player docked above it, tab content above
/// that. The player survives tab switches because it lives in the shell, not in any branch.
class AppShell extends ConsumerWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Scaffold(
      body: shell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _MiniPlayerSlot(),
          NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (index) => shell.goBranch(
              index,
              // Tapping the tab you are already on pops that tab back to its root.
              initialLocation: index == shell.currentIndex,
            ),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home),
                label: t(CommonKeys.navHome),
              ),
              NavigationDestination(
                icon: const Icon(Icons.search_outlined),
                selectedIcon: const Icon(Icons.search),
                label: t(CommonKeys.navSearch),
              ),
              NavigationDestination(
                icon: const Icon(Icons.library_music_outlined),
                selectedIcon: const Icon(Icons.library_music),
                label: t(CommonKeys.navLibrary),
              ),
              NavigationDestination(
                icon: const Icon(Icons.person_outline),
                selectedIcon: const Icon(Icons.person),
                label: t(CommonKeys.navYou),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Reserved for the mini-player, which arrives with the playback milestone. It renders nothing
/// until there is something playing, so the shell already has the right shape.
class _MiniPlayerSlot extends StatelessWidget {
  const _MiniPlayerSlot();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
