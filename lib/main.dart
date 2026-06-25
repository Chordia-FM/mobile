import 'package:flutter/material.dart';

void main() => runApp(const ChordiaApp());

class ChordiaApp extends StatelessWidget {
  const ChordiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chordia',
      theme: ThemeData.dark(useMaterial3: true),
      home: const Scaffold(
        body: Center(
          child: Text('Chordia - mobile scaffold'),
        ),
      ),
    );
  }
}
