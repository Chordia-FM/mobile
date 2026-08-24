import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/surface.dart';
import '../../widgets/tokens.dart';
import '../library/data/formatting.dart';
import 'update_check.dart';

/// Puts the update prompt over whatever the app is showing.
///
/// Wraps the app rather than living on a screen, because the check runs on launch and the listener
/// could be anywhere by the time it answers.
///
/// Deliberately not a `showModalBottomSheet`: that needs a `Navigator` to push a route onto, which
/// makes the prompt a navigation event — it would land in the back stack, take the next system-back
/// press, and interrupt whatever the person was in the middle of. A new version of a music player
/// is not worth interrupting anybody for. This is an ordinary widget stacked above the app, so back
/// still does what it did, playback keeps going, and the only ways out are the two buttons and a
/// swipe down.
class UpdateGate extends ConsumerWidget {
  const UpdateGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final release = ref.watch(updateProvider).value;
    return Stack(
      // Tight constraints for [child], so wrapping the app in this cannot change how the app
      // itself lays out — a loose Stack would leave the navigator to size itself and shrink-wrap
      // screens that happen not to expand on their own.
      fit: StackFit.expand,
      children: [
        child,
        if (release != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Dismissible(
              key: ValueKey('update-${release.version}'),
              direction: DismissDirection.down,
              // A swipe is "not now", not "never": somebody flicking a card away has not read the
              // version number, and treating that as a refusal would silence the prompt for good.
              onDismissed: (_) => ref.read(updateProvider.notifier).hide(),
              child: UpdateSheet(release: release),
            ),
          ),
      ],
    );
  }
}

/// The prompt itself.
class UpdateSheet extends ConsumerWidget {
  const UpdateSheet({required this.release, super.key});

  final AppRelease release;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final open = ref.watch(openExternalUrlProvider);
    final controller = ref.read(updateProvider.notifier);
    final download = release.download;
    final running = ref.watch(appVersionProvider).value;

    // The elevated panel material, not a pane fill with a Material elevation under it: the web
    // draws every sheet and dialog as one element carrying `island-shell island-shell-modal`
    // (`responsive-dialog.tsx:206`). The shadow moves out to a `DecoratedBox` because [ModalPanel]
    // deliberately carries none — on the web a dialog separates by being lighter, not by casting —
    // and this one is stacked straight over the app with no scrim under it, so it still needs the
    // lift that told the listener it was a layer above.
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: ChordiaRadius.sheetTop,
        boxShadow: chordiaPanelShadow,
      ),
      child: ModalPanel(
        padding: EdgeInsets.zero,
        borderRadius: ChordiaRadius.sheetTop,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.surfaces.line,
                      borderRadius: ChordiaRadius.pill,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  t(CommonKeys.updateTitle, {'version': release.version}),
                  style: theme.textTheme.titleMedium,
                ),
                if (running != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    t(CommonKeys.updateYouHave, {'version': running}),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ChordiaColors.mutedForeground,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  t(CommonKeys.updateSideload),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ChordiaColors.mutedForeground,
                  ),
                ),
                if (download != null && download.sizeBytes > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    t(CommonKeys.updateFile, {
                      'name': download.filename,
                      'size': formatBytes(download.sizeBytes),
                    }),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ChordiaColors.mutedForeground,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => open(Uri.parse(release.notesUrl)),
                      child: Text(t(CommonKeys.updateNotes)),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: controller.dismiss,
                      child: Text(t(CommonKeys.updateLater)),
                    ),
                    const SizedBox(width: 8),
                    // No button at all when the release carries no APK — a "Download" that has
                    // nothing to download is worse than the notes link beside it.
                    if (download != null)
                      FilledButton(
                        onPressed: () async {
                          // Hidden rather than dismissed: the browser has the file now, but nothing
                          // here knows whether the install went through, and a download somebody
                          // abandoned should still be offered tomorrow.
                          controller.hide();
                          await open(Uri.parse(download.url));
                        },
                        child: Text(t(CommonKeys.updateDownload)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
