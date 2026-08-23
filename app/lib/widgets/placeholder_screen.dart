import 'package:flutter/material.dart';

import 'brand/logo.dart';
import 'surface.dart';
import 'tokens.dart';

/// Stands in for a screen that has not been built yet.
///
/// It exists so the shell, routing and localisation can be exercised end to end before any feature
/// lands, and so a half-built tab is obviously unfinished rather than looking broken.
///
/// The dashed outline is what carries "unfinished" — it is the web's own empty-state material
/// (`routes/_authed/app/library/index.tsx:432`), and a filled card here would read as a screen that
/// simply has nothing on it. The mark sits at rest: `idle` is the only state allowed outside a real
/// loading moment, and a placeholder is not one.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DashedPanel(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ChordiaLogo(size: 40, color: scheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: ChordiaType.lg.copyWith(
                    fontWeight: ChordiaType.semibold,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
