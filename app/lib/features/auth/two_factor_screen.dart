import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'auth_messages.dart';
import 'auth_scaffold.dart';

/// The second step of a sign-in, for accounts with two-factor turned on.
///
/// [mfaToken] is the short-lived challenge `POST /v1/auth/login` handed back instead of a session.
/// It is carried in the route's `extra` rather than the path: it is a credential, and a credential
/// in a URL ends up in history, in a crash report, and in anything that logs navigation.
class TwoFactorScreen extends ConsumerStatefulWidget {
  const TwoFactorScreen({required this.mfaToken, super.key});

  final String mfaToken;

  @override
  ConsumerState<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends ConsumerState<TwoFactorScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final repository = ref.read(authRepositoryProvider);
    if (repository == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await repository.verifyMfa(
        mfaToken: widget.mfaToken,
        // Authenticator apps space their digits and recovery codes are hyphenated; nobody should
        // fail a sign-in because they typed what they were shown.
        code: _code.text.replaceAll(' ', '').trim(),
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
      title: t(AuthKeys.twoFactorTitle),
      subtitle: t(AuthKeys.twoFactorSubtitle),
      onBack: () => context.pop(),
      children: [
        if (_error != null) AuthErrorText(_error!),
        TextField(
          controller: _code,
          autofocus: true,
          enabled: !_busy,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.go,
          autofillHints: const [AutofillHints.oneTimeCode],
          onSubmitted: (_) => _busy ? null : _verify(),
          decoration: InputDecoration(
            labelText: t(AuthKeys.twoFactorCodeLabel),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: Text(
            t(_busy ? AuthKeys.twoFactorVerifying : CommonKeys.actionsVerify),
          ),
        ),
        TextButton(
          onPressed: _busy ? null : () => context.pop(),
          child: Text(t(AuthKeys.twoFactorBackToSignIn)),
        ),
      ],
    );
  }
}
