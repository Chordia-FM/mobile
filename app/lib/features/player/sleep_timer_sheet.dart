import 'package:chordia_sync/chordia_sync.dart' hide PlaybackState;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/surface.dart';
import '../../widgets/tokens.dart';
import '../catalog/widgets/list_row.dart';

/// The minute offsets offered, before the hour and the end-of-track options.
const List<int> _minuteOptions = [15, 30, 45];

/// Opens the sleep-timer picker.
Future<void> showSleepTimerSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SleepTimerSheet(),
    );

class _SleepTimerSheet extends ConsumerWidget {
  const _SleepTimerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final armed = ref.watch(playerStateProvider.select((s) => s.sleepTimer));
    final actions = ref.watch(playerActionsProvider);

    void arm(SleepTimerOption? option) {
      actions.setSleepTimer(option);
      Navigator.of(context).pop();
    }

    return SafeArea(
      // The sheet's own material, not a flat pane fill: the web renders a sheet and a dialog as
      // one element carrying `island-shell island-shell-modal` (`responsive-dialog.tsx:206`), and
      // `ModalPanel` is that. The inner `Material` is what the rows' press highlight paints into —
      // the sheet's own Material is transparent here, so without one the fill has nowhere to land.
      child: ModalPanel(
        padding: EdgeInsets.zero,
        borderRadius: ChordiaRadius.sheetTop,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t(PlayerKeys.sleepTimerTitle),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              for (final minutes in _minuteOptions)
                ListRow(
                  onTap: () => arm(SleepAfterMinutes(minutes.toDouble())),
                  title: Text(
                    t(PlayerKeys.sleepTimerMinutes, {'count': minutes}),
                  ),
                ),
              ListRow(
                onTap: () => arm(const SleepAfterMinutes(60)),
                title: Text(t(PlayerKeys.sleepTimerOneHour)),
              ),
              ListRow(
                onTap: () => arm(const SleepAfterCurrentTrack()),
                title: Text(t(PlayerKeys.sleepTimerEndOfTrack)),
                // The only armed state that can be recognised from the outside: a minutes timer
                // becomes a wall-clock deadline the moment it is set, so which option produced it is
                // no longer knowable — and guessing from the remaining time would tick out of date.
                trailing: armed is SleepAtTrackEnd
                    ? Icon(Icons.check_rounded, color: context.surfaces.accent)
                    : null,
              ),
              if (armed != null)
                ListRow(
                  onTap: () => arm(null),
                  destructive: true,
                  title: Text(t(PlayerKeys.sleepTimerTurnOff)),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
