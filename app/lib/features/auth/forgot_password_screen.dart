import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'auth_messages.dart';
import 'auth_scaffold.dart';

/// Asks the hub to email a password-reset link.
///
/// The confirmation is deliberately vague — "if an account exists for that email" — and is shown
/// whether or not one does. The Hub does not reveal which, and a screen that did would turn the
/// form into a way to test whether somebody has an account here.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final repository = ref.read(authRepositoryProvider);
    if (repository == null) {
      setState(() => _error = ref.t(AuthKeys.hubChooseFirst));
      return;
    }
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = ref.t(AuthKeys.loginEnterEmailFirst));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repository.requestPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sent = true;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeAuthError(error, ref.t);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    return AuthScaffold(
      title: t(AuthKeys.resetTitle),
      subtitle: t(AuthKeys.forgotSubtitle),
      onBack: () => context.pop(),
      children: _sent
          ? [
              Text(t(AuthKeys.loginResetSent)),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.pop(),
                child: Text(t(AuthKeys.resetGoToSignIn)),
              ),
            ]
          : [
              if (_error != null) AuthErrorText(_error!),
              TextField(
                controller: _email,
                autofocus: true,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.go,
                autofillHints: const [AutofillHints.email],
                onSubmitted: (_) => _busy ? null : _send(),
                decoration: InputDecoration(labelText: t(AuthKeys.fieldsEmail)),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _send,
                child: Text(
                  t(_busy ? AuthKeys.resetResetting : AuthKeys.forgotSend),
                ),
              ),
            ],
    );
  }
}
