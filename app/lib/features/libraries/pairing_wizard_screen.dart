import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/list_row.dart';
import '../library/data/formatting.dart';
import '../library/data/library_providers.dart';
import '../library/widgets/library_states.dart';
import 'data/libraries_providers.dart';
import 'data/pairing_controller.dart';

/// Connects a library server to the account, and answers with the library it created.
Future<LibrarySummary?> openPairingWizard(BuildContext context) =>
    Navigator.of(context).push<LibrarySummary>(
      MaterialPageRoute<LibrarySummary>(
        builder: (_) => const PairingWizardScreen(),
      ),
    );

/// The first thing a new listener does, and the one place the two-plane design becomes visible.
///
/// Every step says what is happening and why, in that order. Pairing is a three-party handshake —
/// phone, Hub, home server — and the parts that would otherwise read as arbitrary (a fingerprint
/// to confirm, a pass that expires) are exactly the parts that make it safe to stream from a
/// machine with a certificate nobody has signed.
class PairingWizardScreen extends ConsumerStatefulWidget {
  const PairingWizardScreen({super.key});

  @override
  ConsumerState<PairingWizardScreen> createState() =>
      _PairingWizardScreenState();
}

class _PairingWizardScreenState extends ConsumerState<PairingWizardScreen> {
  PairingController? _pairing;
  final _link = TextEditingController();
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    final hub = ref.read(librariesApiProvider);
    if (hub == null) return;
    _pairing = PairingController(
      hub: hub,
      transport: ref.read(pairingTransportProvider),
    )..addListener(_onChanged);
  }

  @override
  void dispose() {
    _pairing
      ?..removeListener(_onChanged)
      ..dispose();
    _link.dispose();
    _name.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    // The libraries list is stale the moment one exists that was not in it. Done here rather than
    // in `build`, where invalidating a provider is a write during a read.
    if (_pairing?.step == PairingStep.done && !_invalidated) {
      _invalidated = true;
      ref
        ..invalidate(myLibrariesProvider)
        ..invalidate(libraryCoverageProvider);
    }
    setState(() {});
  }

  /// So a rebuild does not re-invalidate on every notification once pairing has finished.
  var _invalidated = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final pairing = _pairing;

    return Scaffold(
      appBar: AppBar(title: Text(t(LibraryKeys.pairingTitle))),
      body: pairing == null
          ? EmptyNote(message: t(ErrorsKeys.failedToLoad))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _stepper(pairing, t),
                const SizedBox(height: 16),
                ...switch (pairing.step) {
                  PairingStep.link => _linkStep(pairing, t),
                  PairingStep.trust => _trustStep(pairing, t),
                  PairingStep.claiming => _claimingStep(pairing, t),
                  PairingStep.naming => _namingStep(pairing, t),
                  PairingStep.done => _doneStep(pairing, t),
                },
                if (pairing.failure != null) ...[
                  const SizedBox(height: 16),
                  _failureNote(pairing, t),
                ],
              ],
            ),
    );
  }

  /// Which of the three parties is being talked to. The names match the sentences below, so
  /// "introducing your account" and the highlighted step are the same thing said twice.
  Widget _stepper(PairingController pairing, Translate t) {
    final index = switch (pairing.step) {
      PairingStep.link || PairingStep.trust => 0,
      PairingStep.claiming => 1,
      PairingStep.naming || PairingStep.done => 2,
    };
    final labels = [
      t(LibraryKeys.setupStepPair),
      t(LibraryKeys.pairingClaimingTitle),
      t(LibraryKeys.setupStepDone),
    ];
    final theme = Theme.of(context);

    return Column(
      children: [
        Row(children: _dots(labels.length, index, theme)),
        const SizedBox(height: 8),
        Text(labels[index], style: theme.textTheme.labelLarge),
      ],
    );
  }

  List<Widget> _dots(int count, int index, ThemeData theme) => [
    for (var i = 0; i < count; i++) ...[
      if (i > 0)
        Expanded(
          child: Divider(
            color: i <= index
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
      CircleAvatar(
        radius: 14,
        backgroundColor: i <= index
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        child: Text(
          '${i + 1}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: i <= index
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ],
  ];

  List<Widget> _linkStep(PairingController pairing, Translate t) => [
    _para(t(LibraryKeys.pairingIntro)),
    const SizedBox(height: 20),
    _numbered(
      1,
      t(LibraryKeys.pairingStepStartTitle),
      t(LibraryKeys.pairingStepStartBody),
    ),
    const SizedBox(height: 12),
    _numbered(
      2,
      t(LibraryKeys.pairingStepLinkTitle),
      t(LibraryKeys.pairingStepLinkBody),
    ),
    const SizedBox(height: 16),
    TextField(
      controller: _link,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.url,
      decoration: InputDecoration(
        labelText: t(LibraryKeys.pairingLinkLabel),
        hintText: 'https://192.168.1.20:8443/setup/…',
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (value) => pairing.submitLink(value),
    ),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: pairing.busy || _link.text.trim().isEmpty
          ? null
          : () => pairing.submitLink(_link.text),
      child: pairing.busy
          ? Text(t(LibraryKeys.pairingCheckingTitle))
          : Text(t(LibraryKeys.pairingConnect)),
    ),
    if (pairing.busy) ...[
      const SizedBox(height: 12),
      _para(
        t(LibraryKeys.pairingCheckingBody, {
          'host': pairing.serverBase?.host ?? '',
        }),
      ),
    ],
  ];

  List<Widget> _trustStep(PairingController pairing, Translate t) => [
    Text(
      t(LibraryKeys.pairingTrustTitle),
      style: Theme.of(context).textTheme.titleMedium,
    ),
    const SizedBox(height: 8),
    _para(
      t(LibraryKeys.pairingTrustBody, {'host': pairing.serverBase?.host ?? ''}),
    ),
    const SizedBox(height: 16),
    Card(
      child: ListRow(
        title: Text(t(LibraryKeys.pairingTrustFingerprint)),
        // Grouped hex, which is the form a fingerprint is printed in everywhere else — a
        // sixty-four character run is unreadable and therefore uncheckable.
        subtitle: SelectableText(
          pairing.fingerprint?.toDisplayString() ?? '',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        ),
      ),
    ),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: pairing.busy ? null : pairing.trustCertificate,
      child: Text(t(LibraryKeys.pairingTrustConfirm)),
    ),
    TextButton(
      onPressed: pairing.busy ? null : _restart,
      child: Text(t(LibraryKeys.pairingStartOver)),
    ),
  ];

  List<Widget> _claimingStep(PairingController pairing, Translate t) => [
    Text(
      t(LibraryKeys.pairingClaimingTitle),
      style: Theme.of(context).textTheme.titleMedium,
    ),
    const SizedBox(height: 8),
    _para(t(LibraryKeys.pairingClaimingBody)),
    const SizedBox(height: 16),
    if (pairing.busy) const LinearProgressIndicator(),
  ];

  List<Widget> _namingStep(PairingController pairing, Translate t) => [
    Text(
      t(LibraryKeys.pairingNameTitle),
      style: Theme.of(context).textTheme.titleMedium,
    ),
    const SizedBox(height: 8),
    _para(t(LibraryKeys.pairingNameBody)),
    const SizedBox(height: 16),
    TextField(
      controller: _name,
      decoration: InputDecoration(
        labelText: t(LibraryKeys.manageNameLabel),
        hintText: t(LibraryKeys.pairingNamePlaceholder),
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (value) => pairing.registerLibrary(value),
    ),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: pairing.busy || _name.text.trim().isEmpty
          ? null
          : () => pairing.registerLibrary(_name.text),
      child: pairing.busy
          ? Text(t(LibraryKeys.pairingRegistering))
          : Text(t(CommonKeys.actionsSave)),
    ),
  ];

  List<Widget> _doneStep(PairingController pairing, Translate t) {
    final library = pairing.library;
    return [
      Icon(
        Icons.check_circle_rounded,
        size: 48,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 12),
      Text(
        t(LibraryKeys.pairingDoneTitle, {'name': library?.name ?? ''}),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      _para(t(LibraryKeys.pairingDoneBody)),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(library),
        child: Text(t(LibraryKeys.pairingDoneAction)),
      ),
    ];
  }

  Widget _failureNote(PairingController pairing, Translate t) {
    final theme = Theme.of(context);
    final host = pairing.serverBase?.host ?? '';
    final message = switch (pairing.failure!) {
      PairingFailure.badLink => t(LibraryKeys.pairingLinkInvalid),
      PairingFailure.unreachable => t(LibraryKeys.pairingUnreachable, {
        'host': host,
      }),
      PairingFailure.alreadyPaired => t(LibraryKeys.pairingRefused),
      PairingFailure.refused => t(LibraryKeys.pairingRefused),
      PairingFailure.ticketExpired => t(LibraryKeys.pairingTicketExpired),
      PairingFailure.hubRefused => describeError(
        pairing.error ?? t(ErrorsKeys.generic),
        t,
      ),
    };
    // "Try again" only where trying again can work. A spent setup link needs a fresh one from the
    // server, so the only honest action there is starting over.
    final canRetry =
        pairing.failure == PairingFailure.ticketExpired ||
        pairing.failure == PairingFailure.unreachable ||
        pairing.failure == PairingFailure.hubRefused;

    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (canRetry)
                  FilledButton(
                    onPressed: pairing.busy ? null : pairing.retry,
                    child: Text(t(CommonKeys.actionsTryAgain)),
                  ),
                if (canRetry) const SizedBox(width: 8),
                TextButton(
                  onPressed: pairing.busy ? null : _restart,
                  child: Text(t(LibraryKeys.pairingStartOver)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _restart() {
    _link.clear();
    _pairing?.startOver();
  }

  Widget _para(String text) => Text(
    text,
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );

  Widget _numbered(int number, String title, String body) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleAvatar(
        radius: 12,
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        child: Text('$number', style: Theme.of(context).textTheme.labelSmall),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            _para(body),
          ],
        ),
      ),
    ],
  );
}
