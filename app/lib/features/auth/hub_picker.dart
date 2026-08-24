import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../app/providers.dart';
import '../../data/hub.dart';
import '../../data/hub_probe.dart';
import '../../app/theme.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/tokens.dart';
import 'auth_messages.dart';

/// Picks which Chordia server to sign in to, and adds new ones.
///
/// Chordia is self-hosted, so "which server" is a question the app has to ask before it can ask
/// anything else — and people run more than one: their own, and a friend's.
class HubPicker extends ConsumerWidget {
  const HubPicker({super.key});

  /// The dropdown entry that opens the add-a-server form. A sentinel rather than a button beside
  /// the field because on a first launch the list is empty and there is nothing else to tap.
  static const _addSentinel = '\u0000add';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final snapshot = ref.watch(hubsProvider).value;
    final hubs = snapshot?.hubs ?? const <Hub>[];
    final active = snapshot?.active;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          // A plain `DropdownButton`, not a `DropdownButtonFormField`: the form field keeps its
          // own selection, so picking "New server…" and then cancelling would leave the field
          // reading "New server…" while the app was still pointed at the previous hub. This one
          // renders exactly what the registry says and nothing else.
          child: InputDecorator(
            decoration: InputDecoration(labelText: t(AuthKeys.hubLabel)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: active?.id,
                isExpanded: true,
                borderRadius: ChordiaRadius.lgAll,
                hint: Text(t(AuthKeys.hubNone)),
                items: [
                  for (final hub in hubs)
                    DropdownMenuItem(
                      value: hub.id,
                      child: Text(hub.name, overflow: TextOverflow.ellipsis),
                    ),
                  // An action, not a server. Given the same plain row as the real entries it reads
                  // as one — a hub someone might already be signed in to — so it carries an icon and
                  // the accent to say it does something instead of naming somewhere.
                  DropdownMenuItem(
                    value: _addSentinel,
                    child: Row(
                      children: [
                        const Icon(
                          PhosphorIconsRegular.plus,
                          size: 18,
                          color: ChordiaColors.accent,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          t(AuthKeys.hubAdd),
                          style: const TextStyle(color: ChordiaColors.accent),
                        ),
                      ],
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  if (value == _addSentinel) {
                    showAddHubDialog(context);
                    return;
                  }
                  ref.read(hubsProvider.notifier).setActive(value);
                },
              ),
            ),
          ),
        ),
        if (active != null) ...[
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(PhosphorIconsRegular.trash),
            tooltip: t(AuthKeys.hubRemove),
            onPressed: () => _confirmRemove(context, ref, active),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    Hub hub,
  ) async {
    final t = ref.t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(AuthKeys.hubRemoveTitle)),
        content: Text(t(AuthKeys.hubRemoveBody, {'name': hub.name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(CommonKeys.actionsCancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t(CommonKeys.actionsRemove)),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(hubsProvider.notifier).remove(hub.id);
    }
  }
}

/// Opens the add-a-server form.
Future<void> showAddHubDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _AddHubDialog());

class _AddHubDialog extends ConsumerStatefulWidget {
  const _AddHubDialog();

  @override
  ConsumerState<_AddHubDialog> createState() => _AddHubDialogState();
}

class _AddHubDialogState extends ConsumerState<_AddHubDialog> {
  final _address = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final result = await ref.read(hubProbeProvider).probe(_address.text);
      if (!mounted) return;
      // Only reachable in a build that allows cleartext at all; the probe refuses it otherwise.
      // Even then it is worth saying out loud, because the cost lands on the user, not the app.
      if (isInsecureRemote(result.url) && !await _confirmInsecure(result.url)) {
        if (mounted) setState(() => _checking = false);
        return;
      }
      await ref.read(hubsProvider.notifier).addProbed(result);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = describeAuthError(error, ref.t);
      });
    }
  }

  Future<bool> _confirmInsecure(Uri url) async {
    final t = ref.t;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(AuthKeys.hubInsecureTitle)),
        content: Text(t(AuthKeys.hubInsecureBody, {'url': url.toString()})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(CommonKeys.actionsCancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t(AuthKeys.hubAddAnyway)),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    return AlertDialog(
      title: Text(t(AuthKeys.hubAddServer)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _address,
            autofocus: true,
            enabled: !_checking,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _checking ? null : _check(),
            decoration: InputDecoration(
              labelText: t(AuthKeys.hubAddLabel),
              hintText: 'chordia.example.com',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            t(AuthKeys.hubAddHint),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(),
          child: Text(t(CommonKeys.actionsCancel)),
        ),
        FilledButton(
          onPressed: _checking ? null : _check,
          child: Text(t(_checking ? AuthKeys.hubChecking : AuthKeys.hubCheck)),
        ),
      ],
    );
  }
}
