/// The playback-device picker.
library;

import 'package:chordia_api/chordia_api.dart' show DeviceNowPlaying;
import 'package:chordia_sync/chordia_sync.dart' hide PlaybackState;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/mesh/providers.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/surface.dart';
import '../../widgets/tokens.dart';
import '../catalog/widgets/list_row.dart';

/// Opens the device picker.
Future<void> showDevicePickerSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const DevicePickerSheet(),
    );

/// Every device this account is signed in on, and which one is playing.
///
/// The mesh is the source of truth for what is reachable, so a row here is something playback can
/// actually be moved to — with one deliberate exception at the bottom of the list; see
/// [_UnreachableRow].
class DevicePickerSheet extends ConsumerWidget {
  const DevicePickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final tabId = ref.watch(playerSyncTabIdProvider);
    final mesh = ref.watch(meshStateProvider).value ?? const PlayerSyncState();
    final transport = ref.watch(meshTransportProvider);

    // Only worth asking when this device is not the one playing: if it is, the Hub's entry is this
    // device's own report and listing it would offer the listener their own phone as somewhere
    // else to send the music.
    final reported = mesh.activeTabId == tabId
        ? null
        : ref.watch(remoteNowPlayingProvider).value;
    final liveDeviceIds = {
      for (final device in mesh.devices)
        if (device.deviceId != null) device.deviceId!,
    };
    final showReported =
        reported != null &&
        (reported.deviceId == null ||
            !liveDeviceIds.contains(reported.deviceId));

    return SafeArea(
      // The sheet's own material: a sheet and a dialog are one element on the web, carrying
      // `island-shell island-shell-modal` (`responsive-dialog.tsx:206`). The inner `Material` is
      // where the rows' press fill lands — the sheet's own is transparent here.
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
                    t(PlayerKeys.devicesTitle),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              if (!mesh.available)
                // Not an error, and not retryable from here. There is one pipe on a phone, and while
                // it is down this device is a mesh of one that plays its own music perfectly well.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 18,
                        color: ChordiaColors.mutedForeground,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t(PlayerKeys.devicesOffline),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ChordiaColors.mutedForeground,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (mesh.devices.isEmpty && !showReported)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      t(PlayerKeys.devicesNone),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ChordiaColors.mutedForeground,
                      ),
                    ),
                  ),
                ),
              for (final device in mesh.devices)
                _DeviceRow(
                  device: device,
                  isLocal: device.tabId == tabId,
                  isTarget: device.tabId == mesh.activeTabId,
                  onTap: () {
                    transport.transferTo(device.tabId);
                    Navigator.of(context).pop();
                  },
                ),
              if (showReported) _UnreachableRow(entry: reported),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceRow extends ConsumerWidget {
  const _DeviceRow({
    required this.device,
    required this.isLocal,
    required this.isTarget,
    required this.onTap,
  });

  final PlayerSyncDevice device;
  final bool isLocal;
  final bool isTarget;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return ListRow(
      // Tapping the device that is already playing is a no-op the protocol also treats as one, so
      // it stays tappable rather than becoming a dead row somebody presses twice.
      onTap: onTap,
      leading: Icon(
        Icons.speaker_rounded,
        color: isTarget
            ? context.surfaces.accent
            : ChordiaColors.mutedForeground,
      ),
      title: Text(device.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: isLocal ? Text(t(PlayerKeys.devicesThisDevice)) : null,
      trailing: isTarget
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: context.surfaces.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  t(PlayerKeys.devicesCurrent),
                  style: TextStyle(color: context.surfaces.accent),
                ),
              ],
            )
          : null,
    );
  }
}

/// A device the Hub heard from that the mesh cannot see.
///
/// Not a button, and that is the point: there is no live connection to hand playback to, so
/// offering it as a target would produce exactly the failure this picker exists to avoid — the
/// "current device" moves and no audio does.
class _UnreachableRow extends ConsumerWidget {
  const _UnreachableRow({required this.entry});

  final DeviceNowPlaying entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Opacity(
      opacity: 0.7,
      child: ListRow(
        leading: const Icon(
          Icons.speaker_rounded,
          color: ChordiaColors.mutedForeground,
        ),
        title: Text(
          entry.deviceLabel ?? t(PlayerKeys.remoteUnnamedDevice),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(t(PlayerKeys.devicesUnreachable)),
      ),
    );
  }
}
