import 'package:flutter/material.dart';

/// What the app shows while it works out whether anybody is signed in.
///
/// It exists so "we have not read the keystore yet" is a state of its own rather than being
/// rendered as "signed out". Without it, every cold start flashes a sign-in form at somebody who
/// is signed in — which reads as the app having forgotten them.
class ResolvingScreen extends StatelessWidget {
  const ResolvingScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
