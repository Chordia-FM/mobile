import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/providers.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/tokens.dart';
import '../catalog/widgets/list_row.dart';
import 'data/settings_messages.dart';
import 'data/settings_providers.dart';
import 'data/settings_values.dart';
import 'data/two_factor_controller.dart';
import 'widgets/settings_list.dart';

/// Everything about how this account signs in.
///
/// Password leads: it is the credential the other two protect. Two-factor sits under it, and the
/// list of signed-in devices last — that order answers "how is my account secured" from the inside
/// out.
class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final account = ref.watch(accountInfoProvider);

    return SettingsScaffold(
      title: t(SettingsKeys.securityTitle),
      onRefresh: () async {
        ref
          ..invalidate(accountInfoProvider)
          ..invalidate(authSessionsProvider);
      },
      children: [
        SettingsBody<AccountInfo>(
          value: account,
          onRetry: () => ref.invalidate(accountInfoProvider),
          builder: (context, value) => Column(
            children: [
              _PasswordSection(account: value),
              _TwoFactorSection(
                // Rebuilt from scratch when the account's 2FA state changes underneath it, so the
                // controller can never start from a stage that contradicts the server.
                key: ValueKey(value.totpEnabled),
                enabled: value.totpEnabled,
              ),
            ],
          ),
        ),
        const _SessionsSection(),
      ],
    );
  }
}

class _PasswordSection extends ConsumerStatefulWidget {
  const _PasswordSection({required this.account});

  final AccountInfo account;

  @override
  ConsumerState<_PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends ConsumerState<_PasswordSection> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  /// Sign the other devices out with the change. Defaults on, which is the safe reading of a
  /// password change: the old one may be the reason it is being changed.
  bool _revokeOthers = true;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final api = ref.read(accountApiProvider);
    if (api == null) return;
    final t = ref.read(translationsProvider).call;
    if (_next.text != _confirm.text) {
      setState(() => _error = t(SettingsKeys.securityPasswordMismatch));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.changePassword(
        ChangePasswordRequest(
          currentPassword: _current.text,
          newPassword: _next.text,
          revokeOtherSessions: _revokeOthers,
        ),
      );
      if (!mounted) return;
      _current.clear();
      _next.clear();
      _confirm.clear();
      // Revoking the others invalidates the list on screen behind this card.
      if (_revokeOthers) ref.invalidate(authSessionsProvider);
      showSettingsMessage(context, t(SettingsKeys.securityPasswordChanged));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = describeSettingsError(error, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestSetLink() async {
    final api = ref.read(accountApiProvider);
    if (api == null) return;
    final t = ref.read(translationsProvider).call;
    setState(() => _busy = true);
    try {
      await api.requestPasswordSet();
      if (!mounted) return;
      showSettingsMessage(context, t(SettingsKeys.securitySetPasswordSent));
    } on Object catch (error) {
      if (!mounted) return;
      showSettingsMessage(context, describeSettingsError(error, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    if (!widget.account.hasPassword) {
      // Discord-only sign-ups have no password to change. They are also excluded from the public
      // reset flow, so an emailed link is their only route to one — and it has to go to an address
      // they have proved they own.
      final verified = widget.account.emailVerified;
      return SettingsSection(
        title: t(SettingsKeys.securitySetPasswordTitle),
        children: [
          SettingsNote(t(SettingsKeys.securitySetPasswordBody)),
          if (!verified)
            SettingsNote(t(SettingsKeys.securitySetPasswordNeedsVerifiedEmail)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: FilledButton(
              onPressed: _busy || !verified ? null : _requestSetLink,
              child: Text(t(SettingsKeys.securitySetPasswordAction)),
            ),
          ),
        ],
      );
    }

    return SettingsSection(
      title: t(SettingsKeys.securityPasswordTitle),
      description: t(SettingsKeys.securityPasswordStoredHint),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _current,
                obscureText: _obscure,
                enabled: !_busy,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: t(SettingsKeys.securityPasswordCurrent),
                  suffixIcon: IconButton(
                    tooltip: t(
                      _obscure
                          ? SettingsKeys.securityPasswordShowAria
                          : SettingsKeys.securityPasswordHideAria,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? PhosphorIconsRegular.eye
                          : PhosphorIconsRegular.eyeSlash,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _next,
                obscureText: _obscure,
                enabled: !_busy,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: t(SettingsKeys.securityPasswordNew),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirm,
                obscureText: _obscure,
                enabled: !_busy,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: t(SettingsKeys.securityPasswordConfirm),
                ),
              ),
            ],
          ),
        ),
        SettingsSwitchRow(
          label: t(SettingsKeys.securityPasswordRevokeOthers),
          description: t(SettingsKeys.securityPasswordRevokeOthersDesc),
          value: _revokeOthers,
          onChanged: _busy ? null : (on) => setState(() => _revokeOthers = on),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(
                  t(
                    _busy
                        ? CommonKeys.statesSaving
                        : SettingsKeys.securityPasswordSave,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t(SettingsKeys.securityPasswordLockoutNote),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Two-factor enrollment, driven by [TwoFactorController].
///
/// The stages are the whole design here — see that controller. This widget only draws whichever
/// one is current and hands typed codes back to it.
class _TwoFactorSection extends ConsumerStatefulWidget {
  const _TwoFactorSection({required this.enabled, super.key});

  final bool enabled;

  @override
  ConsumerState<_TwoFactorSection> createState() => _TwoFactorSectionState();
}

class _TwoFactorSectionState extends ConsumerState<_TwoFactorSection> {
  final _code = TextEditingController();

  /// Null only when there is no hub session to enroll against, which is also the one state in
  /// which this section has nothing to say.
  TwoFactorController? _controller;

  @override
  void initState() {
    super.initState();
    final api = ref.read(securityApiProvider);
    if (api == null) return;
    _controller = TwoFactorController(api: api, enabled: widget.enabled)
      ..addListener(_onChanged);
  }

  @override
  void dispose() {
    _code.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    final controller = _controller;
    if (controller == null) return;
    final failure = controller.error;
    if (failure != null) {
      showSettingsMessage(
        context,
        describeSettingsError(failure, ref.read(translationsProvider).call),
      );
    }
  }

  /// The rest of the app reads `totp_enabled` from the profile and the account, so both have to be
  /// re-read whenever this flow turns 2FA on or off.
  void _refreshAccount() {
    ref
      ..invalidate(accountInfoProvider)
      ..invalidate(myProfileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();

    return SettingsSection(
      title: t(SettingsKeys.twoFactorTitle),
      children: switch (controller.stage) {
        TwoFactorStage.off => _off(t, controller),
        TwoFactorStage.enrolling => _enrolling(t, controller),
        TwoFactorStage.showingCodes => _codes(t, controller),
        TwoFactorStage.on => _on(t, controller),
      },
    );
  }

  List<Widget> _off(Translate t, TwoFactorController controller) => [
    ListRow(
      gutter: 0,
      title: Text(t(SettingsKeys.twoFactorStatusOff)),
      subtitle: Text(t(SettingsKeys.twoFactorAddHint)),
      leading: const Icon(PhosphorIconsRegular.shield, size: 20),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: FilledButton(
        onPressed: controller.busy ? null : controller.begin,
        child: Text(t(SettingsKeys.twoFactorEnableCta)),
      ),
    ),
  ];

  List<Widget> _enrolling(Translate t, TwoFactorController controller) {
    final setup = controller.setup!;
    return [
      SettingsNote(t(SettingsKeys.twoFactorScanHint)),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: ChordiaRadius.lgAll,
            ),
            // Drawn from the `otpauth://` URI rather than the SVG the Hub also returns: rendering
            // that would mean shipping an SVG engine to display a picture of a string we already
            // have.
            child: QrImageView(
              data: setup.otpauthUrl,
              size: 200,
              backgroundColor: Colors.white,
              semanticsLabel: t(SettingsKeys.twoFactorQrAlt),
            ),
          ),
        ),
      ),
      // Offered for anyone whose authenticator is on this same phone, where there is no second
      // screen to point a camera at.
      ListRow(
        gutter: 0,
        title: Text(
          t(SettingsKeys.twoFactorSecretManual, {'secret': setup.secret}),
        ),
        trailing: const Icon(PhosphorIconsRegular.copy),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: setup.secret));
          if (!mounted) return;
          showSettingsMessage(context, t(SettingsKeys.twoFactorCopied));
        },
      ),
      _codeField(t, t(SettingsKeys.twoFactorEnable), () async {
        if (await controller.confirm(_code.text)) {
          _code.clear();
          _refreshAccount();
        }
      }, numeric: true),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: TextButton(
          onPressed: controller.busy ? null : controller.cancelEnrollment,
          child: Text(t(CommonKeys.actionsCancel)),
        ),
      ),
    ];
  }

  /// The recovery codes, on their only render.
  ///
  /// Copy is offered because the alternative is transcribing ten codes by hand before the card can
  /// be dismissed — and the Hub keeps only hashes of them, so there is no second chance.
  List<Widget> _codes(Translate t, TwoFactorController controller) {
    final codes = controller.recoveryCodes ?? const <String>[];
    return [
      SettingsNote(t(SettingsKeys.twoFactorRecoveryIntro)),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SelectableText(
          codes.join('\n'),
          style: const TextStyle(fontFamily: 'monospace', height: 1.6),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: codes.join('\n')));
                if (!mounted) return;
                showSettingsMessage(context, t(SettingsKeys.twoFactorCopied));
              },
              icon: const Icon(PhosphorIconsRegular.copy),
              label: Text(t(SettingsKeys.twoFactorCopyAll)),
            ),
            const Spacer(),
            FilledButton(
              onPressed: controller.acknowledgeCodes,
              child: Text(t(CommonKeys.actionsDone)),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _on(Translate t, TwoFactorController controller) => [
    ListRow(
      gutter: 0,
      title: Text(t(SettingsKeys.twoFactorStatusOn)),
      subtitle: Text(t(SettingsKeys.twoFactorEnabledHint)),
      leading: Icon(
        PhosphorIconsFill.shieldCheck,
        size: 20,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
    // Not capped at six characters and not numeric-only: this field also takes a recovery code
    // (`a1b2c-d3e4f`), and either restriction would make one un-enterable.
    _codeField(t, t(SettingsKeys.twoFactorDisable), () async {
      if (await controller.disable(_code.text)) {
        _code.clear();
        _refreshAccount();
      }
    }, destructive: true),
  ];

  Widget _codeField(
    Translate t,
    String action,
    Future<void> Function() onSubmit, {
    bool numeric = false,
    bool destructive = false,
  }) {
    final busy = _controller?.busy ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _code,
            enabled: !busy,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: numeric ? TextInputType.number : TextInputType.text,
            autofillHints: const [AutofillHints.oneTimeCode],
            onSubmitted: (_) => busy ? null : onSubmit(),
            decoration: InputDecoration(
              labelText: t(AuthKeys.twoFactorCodeLabel),
              hintText: '123456',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            onPressed: busy ? null : onSubmit,
            child: Text(t(busy ? CommonKeys.statesVerifying : action)),
          ),
        ],
      ),
    );
  }
}

class _SessionsSection extends ConsumerWidget {
  const _SessionsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final sessions = ref.watch(authSessionsProvider);
    return SettingsSection(
      title: t(SettingsKeys.sessionsTitle),
      description: t(SettingsKeys.sessionsBody),
      children: [
        SettingsBody<List<SessionInfo>>(
          value: sessions,
          onRetry: () => ref.invalidate(authSessionsProvider),
          builder: (context, rows) => Column(
            children: [
              for (final session in rows) _SessionRow(session: session),
            ],
          ),
        ),
        SettingsDisclosureRow(
          icon: PhosphorIconsRegular.signOut,
          label: t(SettingsKeys.sessionsSignOutEverywhere),
          destructive: true,
          onTap: () => _signOutEverywhere(context, ref),
        ),
      ],
    );
  }

  Future<void> _signOutEverywhere(BuildContext context, WidgetRef ref) async {
    final t = ref.read(translationsProvider).call;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t(SettingsKeys.sessionsSignOutEverywhere)),
        content: Text(t(SettingsKeys.sessionsSignOutEverywhereConfirm)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t(CommonKeys.actionsCancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t(CommonKeys.actionsSignOut)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final api = ref.read(securityApiProvider);
    try {
      await api?.signOutEverywhere();
    } on Object catch (error) {
      if (!context.mounted) return;
      showSettingsMessage(context, describeSettingsError(error, t));
      return;
    }
    // "Everywhere" includes this device, so the local session goes too — otherwise the app keeps
    // showing a signed-in shell backed by a refresh token the Hub has already forgotten.
    await ref.read(authControllerProvider.notifier).signOut();
  }
}

class _SessionRow extends ConsumerWidget {
  const _SessionRow({required this.session});

  final SessionInfo session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;
    final format = DateFormat.yMMMd(locale).add_jm();
    String when(int epochMillis) =>
        format.format(DateTime.fromMillisecondsSinceEpoch(epochMillis));

    return ListRow(
      gutter: 0,
      subtitleMaxLines: 3,
      leading: Icon(
        session.current
            ? PhosphorIconsRegular.deviceMobile
            : PhosphorIconsRegular.devices,
        size: 20,
        color: session.current ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        describeDevice(
          session.userAgent,
          t(SettingsKeys.sessionsUnknownDevice),
        ),
      ),
      subtitle: Text(
        [
          if (session.current) t(SettingsKeys.sessionsThisDevice),
          t(SettingsKeys.sessionsLastActive, {
            'date': when(session.lastUsedAt),
          }),
          t(SettingsKeys.sessionsSignedIn, {'date': when(session.createdAt)}),
        ].join('\n'),
      ),
      // The session making this request cannot revoke itself here: that is signing out, and it
      // lives under Account where it does the local cleanup too.
      trailing: session.current
          ? null
          : TextButton(
              onPressed: () => _revoke(context, ref),
              child: Text(t(CommonKeys.actionsSignOut)),
            ),
    );
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref) async {
    final api = ref.read(securityApiProvider);
    if (api == null) return;
    final t = ref.read(translationsProvider).call;
    try {
      await api.revokeSession(session.sessionId);
    } on Object catch (error) {
      // The row stays. Dropping it on a failed revoke would tell somebody signing out a device
      // they do not recognise that it is gone, while it keeps a live refresh token.
      if (!context.mounted) return;
      showSettingsMessage(context, describeSettingsError(error, t));
      return;
    }
    ref.invalidate(authSessionsProvider);
  }
}

/// A short device label from a raw User-Agent.
///
/// Chordia's own clients name themselves, so nothing has to be guessed for them — sniffing the
/// desktop app for a browser produced "Browser" on no operating system at all, because the request
/// comes from Rust. Everything else falls back to the same browser/OS pair the web client shows.
String describeDevice(String? userAgent, String unknownLabel) {
  if (userAgent == null || userAgent.trim().isEmpty) return unknownLabel;
  if (userAgent.startsWith('Chordia')) return userAgent.split(' ').first;

  final browser = switch (userAgent) {
    final ua when ua.contains('Edg') => 'Edge',
    final ua when ua.contains('OPR') || ua.contains('Opera') => 'Opera',
    final ua when ua.contains('Chrome') => 'Chrome',
    final ua when ua.contains('Firefox') => 'Firefox',
    final ua when ua.contains('Safari') => 'Safari',
    _ => unknownLabel,
  };
  final system = switch (userAgent) {
    final ua when ua.contains('Windows') => 'Windows',
    final ua when ua.contains('Mac OS X') || ua.contains('Macintosh') =>
      'macOS',
    final ua when ua.contains('Android') => 'Android',
    final ua when ua.contains('iPhone') || ua.contains('iPad') => 'iOS',
    final ua when ua.contains('Linux') => 'Linux',
    _ => null,
  };
  // A user-agent that names an OS but no browser we know reads better as the OS alone than as
  // "Unknown device · Windows".
  if (browser == unknownLabel) return system ?? unknownLabel;
  return system == null ? browser : '$browser · $system';
}
