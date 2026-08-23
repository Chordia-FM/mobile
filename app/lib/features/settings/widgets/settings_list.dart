import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../data/settings_controller.dart';
import '../data/settings_messages.dart';
import '../data/settings_patch.dart';

/// The frame every settings page shares: a title, a scroll, and room under the player bar.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    required this.title,
    required this.children,
    super.key,
    this.onRefresh,
  });

  final String title;
  final List<Widget> children;

  /// Pull-to-refresh, where the page has something worth re-reading.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: onRefresh == null
          ? list
          : RefreshIndicator(onRefresh: onRefresh!, child: list),
    );
  }
}

/// A titled group of rows, drawn as one card.
///
/// The card is what makes a list of switches read as settings rather than as a form: it groups
/// the rows that belong together and puts a visible edge between groups, which is the whole job of
/// a section header on a phone.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.title,
    required this.children,
    super.key,
    this.description,
  });

  final String title;

  /// A sentence under the header, for a group whose name is not self-explanatory.
  final String? description;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 4),
                Text(
                  description!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// A row that leads somewhere else.
class SettingsDisclosureRow extends StatelessWidget {
  const SettingsDisclosureRow({
    required this.label,
    required this.onTap,
    super.key,
    this.description,
    this.icon,
    this.value,
    this.destructive = false,
  });

  final String label;
  final String? description;
  final IconData? icon;

  /// The current setting, shown at the end of the row so the list answers "what is this set to"
  /// without anything having to be opened.
  final String? value;

  final bool destructive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return ListTile(
      onTap: onTap,
      leading: icon == null ? null : Icon(icon, color: tint),
      title: Text(
        label,
        style: destructive ? TextStyle(color: theme.colorScheme.error) : null,
      ),
      subtitle: description == null ? null : Text(description!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                value!,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

/// A row that is on or off.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
    this.description,
  });

  final String label;
  final String? description;
  final bool value;

  /// Null while the setting is not known yet, which disables the switch rather than showing a
  /// confident "off" for something that may well be on.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    value: value,
    onChanged: onChanged,
    title: Text(label),
    subtitle: description == null ? null : Text(description!),
  );
}

/// A row that opens a sheet of mutually exclusive choices.
///
/// A sheet rather than an inline segmented control: these lists run to four and five options whose
/// labels are full words in every shipped language, and a segmented control at 320px either
/// ellipses them or wraps into something that no longer reads as one control.
class SettingsChoiceRow<T> extends ConsumerWidget {
  const SettingsChoiceRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
    this.description,
  });

  final String label;
  final String? description;
  final T? value;

  /// Each choice with its already-localised label, in the order they should be offered.
  final List<(T, String)> options;

  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = options.where((option) => option.$1 == value).firstOrNull;
    return SettingsDisclosureRow(
      label: label,
      description: description,
      value: selected?.$2,
      onTap: onChanged == null ? null : () => _open(context, ref),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final chosen = await showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
            ),
            RadioGroup<T>(
              groupValue: value,
              onChanged: (picked) => Navigator.of(sheetContext).pop(picked),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in options)
                    RadioListTile<T>(value: option.$1, title: Text(option.$2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen != null) onChanged?.call(chosen);
  }
}

/// A row whose choices each carry a sentence explaining them.
///
/// Streaming quality is the case this exists for: "Source" and "High" mean nothing without the
/// bitrate beside them, and a bare list of four words is not a choice anybody can make.
class SettingsRadioGroup<T> extends StatelessWidget {
  const SettingsRadioGroup({
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final T? value;

  /// Each choice with its localised label and its localised description.
  final List<(T, String, String)> options;

  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) => RadioGroup<T>(
    groupValue: value,
    // Null arrives only from a toggleable radio, which none of these are.
    onChanged: (picked) => picked == null ? null : onChanged?.call(picked),
    child: Column(
      children: [
        for (final option in options)
          RadioListTile<T>(
            value: option.$1,
            enabled: onChanged != null,
            title: Text(option.$2),
            subtitle: Text(option.$3),
          ),
      ],
    ),
  );
}

/// A row with a slider over a bounded integer setting.
///
/// The value is committed on release, not while dragging: every commit is a full `PUT` of the
/// settings document, and a drag across a twelve-stop slider would otherwise be a dozen of them.
class SettingsSliderRow extends StatefulWidget {
  const SettingsSliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.describe,
    required this.onChanged,
    super.key,
    this.description,
  });

  final String label;
  final String? description;
  final int value;
  final int min;
  final int max;

  /// The value as the row should read it — "Off", "6 seconds".
  final String Function(int value) describe;

  final ValueChanged<int>? onChanged;

  @override
  State<SettingsSliderRow> createState() => _SettingsSliderRowState();
}

class _SettingsSliderRowState extends State<SettingsSliderRow> {
  /// Where the thumb is while a finger is on it. Null when the setting itself is what is shown.
  int? _dragging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Clamped for display as well as on write: a document that arrived holding something outside
    // the range would otherwise assert inside `Slider`, taking the whole screen down.
    final shown = (_dragging ?? widget.value)
        .clamp(widget.min, widget.max)
        .toInt();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.label, style: theme.textTheme.bodyLarge),
              ),
              Text(
                widget.describe(shown),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          if (widget.description != null)
            Text(
              widget.description!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          Slider(
            value: shown.toDouble(),
            min: widget.min.toDouble(),
            max: widget.max.toDouble(),
            divisions: widget.max - widget.min,
            label: widget.describe(shown),
            onChanged: widget.onChanged == null
                ? null
                : (value) => setState(() => _dragging = value.round()),
            onChangeEnd: (value) {
              setState(() => _dragging = null);
              widget.onChanged?.call(value.round());
            },
          ),
        ],
      ),
    );
  }
}

/// A paragraph of explanation between sections.
class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// One asynchronous read, in the three states it can be in.
///
/// Stale data survives a failed refresh: a value already on screen keeps rendering when a
/// background re-read fails, because replacing a settings page with an error card because a
/// refresh timed out throws away something the reader was in the middle of.
class SettingsBody<T> extends ConsumerWidget {
  const SettingsBody({
    required this.value,
    required this.onRetry,
    required this.builder,
    super.key,
  });

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(BuildContext context, T value) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = value.value;
    if (loaded != null) return builder(context, loaded);
    if (value.hasError) {
      return SettingsFailure(error: value.error!, onRetry: onRetry);
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: CircularProgressIndicator.adaptive()),
    );
  }
}

/// A failure, with the one thing worth offering: another go.
class SettingsFailure extends ConsumerWidget {
  const SettingsFailure({
    required this.error,
    required this.onRetry,
    super.key,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            describeSettingsError(error, t),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: Text(t(CommonKeys.actionsTryAgain)),
          ),
        ],
      ),
    );
  }
}

/// Applies one settings edit, and says so when the Hub refuses it.
///
/// The single call site for every switch, slider and picker on these screens: the controller has
/// already put the old value back by the time this returns false, and without the message that
/// revert is indistinguishable from a tap that never registered.
Future<void> applySettingsPatch(
  BuildContext context,
  WidgetRef ref,
  SettingsPatch change,
) async {
  final controller = ref.read(settingsControllerProvider.notifier);
  if (await controller.patch(change)) return;
  final failure = controller.failure;
  if (failure == null || !context.mounted) return;
  showSettingsMessage(
    context,
    describeSettingsError(failure, ref.read(translationsProvider).call),
  );
}

/// Says what went wrong, where the user is looking.
///
/// Every write on these screens is optimistic, so a failure has already been undone on screen by
/// the time this runs — without the message the revert looks like the tap simply did nothing.
void showSettingsMessage(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
