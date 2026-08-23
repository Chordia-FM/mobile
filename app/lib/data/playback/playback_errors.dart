import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'playback_service.dart';

/// Every track the player could not sound, as it happens.
///
/// A stream rather than a held value: two tracks failing in a row are two things to say, and a
/// state field would show the second having silently replaced the first.
final playbackFailureProvider = StreamProvider<PlaybackFailure>(
  (ref) => ref.watch(playbackServiceProvider).failures,
);

/// Tells the listener when a track will not play.
///
/// Wrapped around the shell rather than dropped into the player, because the failure has to be
/// visible wherever the listener happens to be looking — browsing an artist while the track that
/// was already playing dies is the common case, and a message that only appears inside the
/// full-screen player is a message nobody reads.
///
/// It draws nothing until something fails.
class PlaybackErrorReporter extends ConsumerWidget {
  const PlaybackErrorReporter({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(playbackFailureProvider, (_, next) {
      final failure = next.value;
      if (failure == null) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      // The previous one is dropped rather than queued: a run of failures is one situation, and
      // stacking four snack bars makes the listener wait through the news to reach the controls.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(playbackFailureMessage(ref.t, failure))),
        );
    });
    return child;
  }
}

/// What a listener is told about [failure].
String playbackFailureMessage(
  String Function(String, [Map<String, Object?>]) t,
  PlaybackFailure failure,
) => t(
  switch (failure.recovery) {
    PlaybackRecovery.retrying => ErrorsKeys.playbackRetrying,
    PlaybackRecovery.skipped => ErrorsKeys.playbackSkipped,
    PlaybackRecovery.stopped => ErrorsKeys.playbackStopped,
  },
  {'title': failure.track.title},
);
