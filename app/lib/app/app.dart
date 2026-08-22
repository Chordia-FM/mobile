import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';

class ChordiaApp extends ConsumerStatefulWidget {
  const ChordiaApp({super.key});

  @override
  ConsumerState<ChordiaApp> createState() => _ChordiaAppState();
}

class _ChordiaAppState extends ConsumerState<ChordiaApp> {
  // Built once: rebuilding a GoRouter throws away every navigation stack.
  late final _router = buildRouter();

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Chordia',
    debugShowCheckedModeBanner: false,
    theme: buildChordiaTheme(),
    // The app draws its own dark palette; following the system into light mode would render
    // half the surfaces unreadable until a light theme actually exists.
    themeMode: ThemeMode.dark,
    routerConfig: _router,
  );
}
