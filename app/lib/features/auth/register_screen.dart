import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'auth_messages.dart';
import 'auth_scaffold.dart';

/// Creates an account on the hub the sign-in screen is pointed at.
///
/// No client-side validation beyond "is anything filled in": handle rules, password length and
/// email shape are all enforced by the Hub, which returns them as localised problem titles. A
/// second copy of those rules here would be a second thing to keep in step, and it would be the
/// copy that is wrong.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _displayName = TextEditingController();
  final _handle = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _displayName.dispose();
    _handle.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _complete =>
      _displayName.text.trim().isNotEmpty &&
      _handle.text.trim().isNotEmpty &&
      _email.text.trim().isNotEmpty &&
      _password.text.isNotEmpty;

  Future<void> _register() async {
    final repository = ref.read(authRepositoryProvider);
    if (repository == null) {
      setState(() => _error = ref.t(AuthKeys.hubChooseFirst));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await repository.register(
        displayName: _displayName.text.trim(),
        handle: _handle.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      ref.read(authControllerProvider.notifier).completeSignIn(response);
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
      title: t(AuthKeys.registerTitle),
      subtitle: t(AuthKeys.registerSubtitle),
      onBack: () => context.pop(),
      children: [
        if (_error != null) AuthErrorText(_error!),
        TextField(
          controller: _displayName,
          enabled: !_busy,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: t(SettingsKeys.accountDisplayName),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _handle,
          enabled: !_busy,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: t(AuthKeys.fieldsUsername),
            hintText: t(SettingsKeys.accountHandlePlaceholder),
            helperText: t(AuthKeys.registerUsernamePatternHint),
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: t(AuthKeys.fieldsEmail)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          enabled: !_busy,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.go,
          autofillHints: const [AutofillHints.newPassword],
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _busy || !_complete ? null : _register(),
          decoration: InputDecoration(
            labelText: t(AuthKeys.fieldsPassword),
            hintText: t(AuthKeys.registerPasswordPlaceholder),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              tooltip: t(
                _obscure
                    ? SettingsKeys.securityPasswordShowAria
                    : SettingsKeys.securityPasswordHideAria,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy || !_complete ? null : _register,
          child: Text(
            t(
              _busy
                  ? AuthKeys.registerCreatingAccount
                  : AuthKeys.registerCreateAccount,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              t(AuthKeys.registerHaveAccount),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextButton(
              onPressed: _busy ? null : () => context.pop(),
              child: Text(t(AuthKeys.loginSignIn)),
            ),
          ],
        ),
      ],
    );
  }
}
