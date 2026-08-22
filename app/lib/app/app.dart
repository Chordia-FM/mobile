import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/update/update_sheet.dart';
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
    // Wraps every screen rather than sitting on one, because the app is not on a store and
    // nothing else will tell somebody a newer build exists. It draws nothing until there is one.
    builder: (context, child) =>
        UpdateGate(child: child ?? const SizedBox.shrink()),
  );
}
