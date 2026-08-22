import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// The frame every auth screen sits in.
///
/// One place rather than four copies, so the screens cannot drift apart in width, spacing or where
/// the keyboard pushes things — the differences nobody notices until they see two of the screens
/// side by side.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    required this.title,
    required this.children,
    this.subtitle,
    this.onBack,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// Shown as a back arrow when this screen has somewhere to go back to.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: onBack == null
          ? null
          : AppBar(leading: BackButton(onPressed: onBack)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            // Generous vertical padding so the card sits optically centred rather than
            // mathematically centred, and never touches the notch on a short device.
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: text.headlineSmall),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle!,
                      style: text.bodyMedium?.copyWith(
                        color: ChordiaColors.mutedForeground,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A failure the user can read, in the place the thing that failed lives.
class AuthErrorText extends StatelessWidget {
  const AuthErrorText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      message,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: ChordiaColors.danger),
    ),
  );
}
