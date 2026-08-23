import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/accent/accent_canvas.dart';
import '../data/accent/accent_providers.dart';
import '../data/accent/accent_scope.dart';
import '../features/update/update_sheet.dart';
import 'router.dart';

class ChordiaApp extends ConsumerStatefulWidget {
  const ChordiaApp({super.key});

  @override
  ConsumerState<ChordiaApp> createState() => _ChordiaAppState();
}

class _ChordiaAppState extends ConsumerState<ChordiaApp> {
  // Built once: rebuilding a GoRouter throws away every navigation stack.
  late final _router = buildRouter();

  /// Which section the ambient wash is lit for, the phone's `data-surface`.
  ///
  /// A notifier rather than state, so a navigation moves the bloom by repainting one canvas instead
  /// of rebuilding the app above the Navigator.
  final _bloom = ValueNotifier(AccentBloom.home);

  @override
  void initState() {
    super.initState();
    _router.routerDelegate.addListener(_syncBloom);
    _syncBloom();
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_syncBloom);
    _bloom.dispose();
    super.dispose();
  }

  void _syncBloom() => _bloom.value = accentBloomFor(
    _router.routerDelegate.currentConfiguration.uri.path,
  );

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Chordia',
    debugShowCheckedModeBanner: false,
    // Derived from the account's accent, not frozen: every pane, card and hairline is a
    // `color-mix` off `--primary` on the web, and this is that. Rebuilds when the accent changes
    // and at no other time — the *moving* modes publish through `AccentScope` below instead, so a
    // cross-fade never rebuilds the tree. See `data/accent/accent_scope.dart`.
    theme: ref.watch(chordiaThemeProvider),
    // The app draws its own dark palette; following the system into light mode would render
    // half the surfaces unreadable until a light theme actually exists.
    themeMode: ThemeMode.dark,
    routerConfig: _router,
    // Wraps every screen rather than sitting on one, because the app is not on a store and
    // nothing else will tell somebody a newer build exists. It draws nothing until there is one.
    //
    // Both accent scopes sit above the Navigator so that every route — and every canvas inside one
    // — can reach them; neither rebuilds anything below itself when its value changes.
    builder: (context, child) => AccentScope(
      frame: ref.watch(accentEngineProvider).frame,
      child: AccentBloomScope(
        bloom: _bloom,
        child: UpdateGate(child: child ?? const SizedBox.shrink()),
      ),
    ),
  );
}
