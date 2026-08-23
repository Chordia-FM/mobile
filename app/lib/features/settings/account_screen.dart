import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'data/settings_api.dart';
import 'data/settings_messages.dart';
import 'data/settings_providers.dart';
import 'security_screen.dart';
import 'settings_screen.dart';
import 'widgets/settings_list.dart';

/// Who the account is, how it is reached, and how it ends.
///
/// Profile and email are edits with a server round trip and a confirmation step; the two at the
/// bottom leave the app entirely. They share a screen because they are the same question — "this
/// account" — but the destructive pair is kept in its own section so neither can be reached by a
/// mis-tap on a field above it.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final profile = ref.watch(myProfileProvider);
    final account = ref.watch(accountInfoProvider);

    return SettingsScaffold(
      title: t(SettingsKeys.accountTitle),
      onRefresh: () async {
        ref
          ..invalidate(myProfileProvider)
          ..invalidate(accountInfoProvider);
      },
      children: [
        SettingsBody<UserProfile>(
          value: profile,
          onRetry: () => ref.invalidate(myProfileProvider),
          builder: (context, value) => _ProfileSection(
            // Keyed by the identity being edited, so a refresh that brings back a handle changed
            // on another device re-seeds the fields instead of leaving stale text in them.
            key: ValueKey('${value.id}:${value.handle}:${value.displayName}'),
            profile: value,
          ),
        ),
        SettingsBody<AccountInfo>(
          value: account,
          onRetry: () => ref.invalidate(accountInfoProvider),
          builder: (context, value) => _EmailSection(account: value),
        ),
        SettingsSection(
          title: t(SettingsKeys.securityTitle),
          children: [
            SettingsDisclosureRow(
              icon: Icons.lock_rounded,
              label: t(SettingsKeys.securityPasswordTitle),
              description: t(SettingsKeys.sectionsSecurity),
              onTap: () => openSettingsScreen(context, const SecurityScreen()),
            ),
          ],
        ),
        _DangerSection(handle: profile.value?.handle),
      ],
    );
  }
}

class _ProfileSection extends ConsumerStatefulWidget {
  const _ProfileSection({required this.profile, super.key});

  final UserProfile profile;

  @override
  ConsumerState<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends ConsumerState<_ProfileSection> {
  late final _handle = TextEditingController(text: widget.profile.handle);
  late final _displayName = TextEditingController(
    text: widget.profile.displayName,
  );
  bool _busy = false;

  @override
  void dispose() {
    _handle.dispose();
    _displayName.dispose();
    super.dispose();
  }

  /// Only the fields that actually moved are sent: `UpdateProfile` treats an omitted field as
  /// "leave it", and sending an unchanged handle makes the Hub run its uniqueness check — and
  /// fail it against the account's own current handle on some paths.
  Future<void> _save() async {
    final api = ref.read(accountApiProvider);
    if (api == null) return;
    final handle = _handle.text.trim();
    final displayName = _displayName.text.trim();
    final changes = UpdateProfile(
      handle: handle == widget.profile.handle ? null : handle,
      displayName: displayName == widget.profile.displayName
          ? null
          : displayName,
    );
    if (changes.toJson().isEmpty) return;

    setState(() => _busy = true);
    final t = ref.read(translationsProvider).call;
    try {
      await api.updateProfile(changes);
      if (!mounted) return;
      ref.invalidate(myProfileProvider);
      showSettingsMessage(context, t(CommonKeys.statusSaved));
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
    return SettingsSection(
      title: t(SettingsKeys.profileTitle),
      description: t(SettingsKeys.profileDesc),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _displayName,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: t(SettingsKeys.accountDisplayName),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _handle,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _busy ? null : _save(),
                decoration: InputDecoration(
                  labelText: t(SettingsKeys.accountHandle),
                  hintText: t(SettingsKeys.accountHandlePlaceholder),
                  helperText: t(SettingsKeys.accountHandleHint),
                  helperMaxLines: 2,
                  prefixText: '@',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(
                  t(
                    _busy
                        ? CommonKeys.statesSaving
                        : SettingsKeys.accountSaveProfile,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmailSection extends ConsumerStatefulWidget {
  const _EmailSection({required this.account});

  final AccountInfo account;

  @override
  ConsumerState<_EmailSection> createState() => _EmailSectionState();
}

class _EmailSectionState extends ConsumerState<_EmailSection> {
  bool _busy = false;

  Future<void> _run(
    Future<void> Function(AccountApi api) call,
    String done,
  ) async {
    final api = ref.read(accountApiProvider);
    if (api == null) return;
    setState(() => _busy = true);
    final t = ref.read(translationsProvider).call;
    try {
      await call(api);
      if (!mounted) return;
      showSettingsMessage(context, t(done));
    } on Object catch (error) {
      if (!mounted) return;
      showSettingsMessage(context, describeSettingsError(error, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The new address is asked for in a dialog rather than an inline field, because this is not an
  /// edit: nothing changes until the link sent to the new inbox is followed, and a field that
  /// looks like the other two on this screen implies it is.
  Future<void> _changeEmail() async {
    final t = ref.read(translationsProvider).call;
    final controller = TextEditingController();
    final address = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t(SettingsKeys.accountChangeEmailTitle)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t(SettingsKeys.accountChangeEmailBody)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: t(AuthKeys.fieldsEmail),
                hintText: t(SettingsKeys.accountNewEmailPlaceholder),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t(CommonKeys.actionsCancel)),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(t(SettingsKeys.accountSendConfirmation)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (address == null || address.isEmpty) return;
    await _run(
      (api) => api.requestEmailChange(address),
      SettingsKeys.accountEmailChangeSent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final account = widget.account;
    final verified = account.emailVerified;
    return SettingsSection(
      title: t(SettingsKeys.accountEmailTitle),
      children: [
        ListTile(
          title: Text(account.email ?? t(SettingsKeys.accountNoEmail)),
          subtitle: Text(
            t(
              verified
                  ? SettingsKeys.accountVerified
                  : SettingsKeys.accountUnverified,
            ),
          ),
          trailing: Icon(
            verified ? Icons.verified_rounded : Icons.error_outline_rounded,
            color: verified
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
          ),
        ),
        if (!verified)
          SettingsDisclosureRow(
            label: t(SettingsKeys.accountResendVerification),
            onTap: _busy
                ? null
                : () => _run(
                    (api) => api.requestEmailVerification(),
                    SettingsKeys.accountVerificationSent,
                  ),
          ),
        SettingsDisclosureRow(
          label: t(SettingsKeys.accountChangeEmail),
          onTap: _busy ? null : _changeEmail,
        ),
      ],
    );
  }
}

class _DangerSection extends ConsumerWidget {
  const _DangerSection({required this.handle});

  /// Null while the profile is still loading, which is also what keeps the delete row unreachable
  /// until there is a handle to type into the confirmation.
  final String? handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final hub = ref.watch(activeHubProvider);
    return SettingsSection(
      title: t(SettingsKeys.accountLeaveTitle),
      description: t(SettingsKeys.accountLeaveDesc),
      children: [
        SettingsDisclosureRow(
          icon: Icons.logout_rounded,
          label: t(CommonKeys.actionsSignOut),
          onTap: () => _signOut(context, ref, hub?.name ?? ''),
        ),
        SettingsDisclosureRow(
          icon: Icons.delete_forever_rounded,
          label: t(SettingsKeys.dataDeleteAccountTitle),
          destructive: true,
          onTap: handle == null
              ? null
              : () => _deleteAccount(context, ref, handle!),
        ),
      ],
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref, String hub) async {
    final t = ref.read(translationsProvider).call;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t(CommonKeys.actionsSignOut)),
        content: Text(t(SettingsKeys.accountSignOutConfirm, {'hub': hub})),
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
    // The router's redirect is what leaves this screen: it watches sign-in state, so nothing here
    // has to navigate — and nothing here can, since this screen is about to stop existing.
    await ref.read(authControllerProvider.notifier).signOut();
  }

  /// Deleting is irreversible and the Hub asks nothing further, so the confirmation is entirely
  /// this client's job. Typing the handle is the point: a destructive button behind a second
  /// button is still one mis-tap away, and this is the one action in the app that cannot be undone
  /// by any means at all.
  Future<void> _deleteAccount(
    BuildContext context,
    WidgetRef ref,
    String handle,
  ) async {
    final t = ref.read(translationsProvider).call;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _DeleteAccountDialog(handle: handle),
    );
    if (confirmed != true) return;

    final api = ref.read(accountApiProvider);
    if (api == null) return;
    try {
      await api.deleteAccount();
    } on Object catch (error) {
      if (!context.mounted) return;
      showSettingsMessage(context, describeSettingsError(error, t));
      return;
    }
    // The account is gone, so the session that was signing into it is worthless. Signing out
    // locally is what puts the app back on its sign-in screen.
    await ref.read(authControllerProvider.notifier).signOut();
  }
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog({required this.handle});

  final String handle;

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _typed = TextEditingController();

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final matches = _typed.text.trim() == widget.handle;
    return AlertDialog(
      title: Text(t(SettingsKeys.dataDeleteAccountTitle)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t(SettingsKeys.dataDeleteAccountConfirm)),
          const SizedBox(height: 16),
          TextField(
            controller: _typed,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: t(SettingsKeys.accountDeleteTypeHandle, {
                'handle': widget.handle,
              }),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t(CommonKeys.actionsCancel)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: matches ? () => Navigator.of(context).pop(true) : null,
          child: Text(t(SettingsKeys.dataDeleteForever)),
        ),
      ],
    );
  }
}
