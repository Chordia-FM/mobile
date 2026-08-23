import 'package:flutter/material.dart';

/// Stands in for a screen that has not been built yet.
///
/// It exists so the shell, routing and localisation can be exercised end to end before any feature
/// lands, and so a half-built tab is obviously unfinished rather than looking broken.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
    ),
  );
}
