import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/auth_repository.dart';
import '../../data/browser_handoff.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'auth_messages.dart';
import 'auth_routes.dart';
import 'auth_scaffold.dart';
import 'hub_picker.dart';

/// Pick a server, then sign in to it — with a password here, or with the session the phone's
/// browser already has.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _obscure = true;
  bool _remember = true;
  bool _busy = false;
  bool _waitingForBrowser = false;
  String? _error;

  ProviderSubscription<BrowserHandoff?>? _handoffListener;
  StreamSubscription<Uri>? _callbacks;

  @override
  void initState() {
    super.initState();
    // Listening starts with the screen, not with the button. On Android the browser hop can
    // relaunch a killed app, so the callback that finishes the flow arrives before anybody has
    // pressed anything in this run of the process — there is nothing to "resume", only a link
    // already waiting.
    _handoffListener = ref.listenManual<BrowserHandoff?>(
      browserHandoffProvider,
      (_, handoff) => _watch(handoff),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    unawaited(_callbacks?.cancel());
    _handoffListener?.close();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _watch(BrowserHandoff? handoff) {
    unawaited(_callbacks?.cancel());
    _callbacks = handoff?.callbacks().listen(_redeem);
  }

  Future<void> _redeem(Uri link) async {
    final handoff = ref.read(browserHandoffProvider);
    if (handoff == null) return;
    setState(() {
      _waitingForBrowser = true;
      _error = null;
    });
    try {
      final response = await handoff.complete(link);
      if (!mounted) return;
      // Null means no flow was open for this link — a stale one delivered to a fresh launch. Not
      // something to show a failure for, because there is nothing the user could do about it.
      if (response == null) {
        setState(() => _waitingForBrowser = false);
        return;
      }
      ref.read(authControllerProvider.notifier).completeSignIn(response);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _waitingForBrowser = false;
        _error = describeAuthError(error, ref.t);
      });
    }
  }

  Future<void> _signIn() async {
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
      final outcome = await repository.login(
        email: _email.text.trim(),
        password: _password.text,
        remember: _remember,
      );
      if (!mounted) return;
      switch (outcome) {
        case LoginAuthenticated(:final response):
          // No `setState` back to idle: the router redirects on the state change, and clearing the
          // busy flag first would flash an enabled form on the way out.
          ref.read(authControllerProvider.notifier).completeSignIn(response);
        case LoginMfaRequired(:final mfaToken):
          setState(() => _busy = false);
          await context.push<void>(AuthRoutes.twoFactor, extra: mfaToken);
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeAuthError(error, ref.t);
      });
    }
  }

  Future<void> _signInWithBrowser() async {
    final handoff = ref.read(browserHandoffProvider);
    final hub = ref.read(activeHubProvider);
    if (handoff == null || hub == null) {
      setState(() => _error = ref.t(AuthKeys.hubChooseFirst));
      return;
    }
    setState(() {
      _waitingForBrowser = true;
      _error = null;
    });
    try {
      await handoff.start(frontendUrl: hub.frontendUrl);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _waitingForBrowser = false;
        _error = describeAuthError(error, ref.t);
      });
    }
  }

  Future<void> _cancelBrowser() async {
    setState(() => _waitingForBrowser = false);
    await ref.read(browserHandoffProvider)?.abandon();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final hasHub = ref.watch(activeHubProvider) != null;
    return AuthScaffold(
      title: t(AuthKeys.loginTitle),
      subtitle: t(AuthKeys.loginSubtitle),
      children: [
        const HubPicker(),
        const SizedBox(height: 24),
        if (_error != null) AuthErrorText(_error!),
        if (_waitingForBrowser)
          ..._waiting(t)
        else
          ..._credentials(context, t, hasHub: hasHub),
      ],
    );
  }

  List<Widget> _waiting(Translate t) => [
    const Center(child: CircularProgressIndicator()),
    const SizedBox(height: 20),
    Text(t(AuthKeys.desktopWaitingForBrowser), textAlign: TextAlign.center),
    const SizedBox(height: 20),
    FilledButton(
      onPressed: _signInWithBrowser,
      child: Text(t(AuthKeys.desktopSignInWithBrowserAgain)),
    ),
    TextButton(
      onPressed: _cancelBrowser,
      child: Text(t(CommonKeys.actionsCancel)),
    ),
  ];

  List<Widget> _credentials(
    BuildContext context,
    Translate t, {
    required bool hasHub,
  }) => [
    TextField(
      controller: _email,
      enabled: !_busy,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.username],
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
      autofillHints: const [AutofillHints.password],
      onSubmitted: (_) => _busy ? null : _signIn(),
      decoration: InputDecoration(
        labelText: t(AuthKeys.fieldsPassword),
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
    CheckboxListTile(
      value: _remember,
      onChanged: _busy ? null : (v) => setState(() => _remember = v ?? true),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(t(AuthKeys.loginKeepSignedIn)),
    ),
    const SizedBox(height: 8),
    FilledButton(
      onPressed: _busy || !hasHub ? null : _signIn,
      child: Text(t(_busy ? AuthKeys.loginSigningIn : AuthKeys.loginSignIn)),
    ),
    TextButton(
      onPressed: _busy
          ? null
          : () => context.push<void>(AuthRoutes.forgotPassword),
      child: Text(t(AuthKeys.loginForgotPassword)),
    ),
    const SizedBox(height: 4),
    _Divider(label: t(AuthKeys.loginOr)),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: _busy || !hasHub ? null : _signInWithBrowser,
      icon: const Icon(Icons.open_in_browser),
      label: Text(t(AuthKeys.desktopSignInWithBrowser)),
    ),
    const SizedBox(height: 20),
    // Wraps rather than a Row: these are two translated strings side by side, and a language that
    // spells either of them longer than English overflows a Row on a narrow phone.
    Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          t(AuthKeys.loginNoAccount),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => context.push<void>(AuthRoutes.register),
          child: Text(t(AuthKeys.loginCreateOne)),
        ),
      ],
    ),
  ];
}

/// A hairline with a word in it. Separates "sign in here" from "sign in over there".
class _Divider extends StatelessWidget {
  const _Divider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(child: Divider()),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: ChordiaColors.mutedForeground),
        ),
      ),
      const Expanded(child: Divider()),
    ],
  );
}
