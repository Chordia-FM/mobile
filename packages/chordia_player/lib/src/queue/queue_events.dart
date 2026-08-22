/// What a [QueueController] tells the world.
///
/// One stream carries both "something changed, re-read me" and "engine, do this now", because the
/// two must stay ordered: a handler that started a track before the queue it belongs to was visible
/// would publish a snapshot naming a track that is not in it. Every command emits at most one
/// [QueueStateChanged], and it is always emitted before the intent that came with it.
library;

import 'package:chordia_sync/chordia_sync.dart';
import 'package:meta/meta.dart';

@immutable
sealed class QueueEvent {
  const QueueEvent();
}

/// Some observable part of the controller moved: the queue, the index, history, shuffle, repeat,
/// the context, or the sleep timer. Carries no payload on purpose — the controller's getters are
/// the state, and a diff would only invite two sources of truth.
@immutable
final class QueueStateChanged extends QueueEvent {
  const QueueStateChanged();
}

/// Start this entry from the beginning, now.
///
/// Emitted for a repeat-one replay too, which is why it is a hard start rather than a seek: the
/// web client reloads the source for that case, and matching it keeps a repeated track's scrobble
/// timing and now-playing report identical to any other track change.
@immutable
final class PlayEntryRequested extends QueueEvent {
  const PlayEntryRequested({required this.index, required this.track});

  final int index;
  final PlayerTrack track;

  @override
  String toString() => 'PlayEntryRequested($index, $track)';
}

/// Seek the current track back to zero without reloading it — "previous" pressed after the restart
/// threshold, or at the head of the queue where there is nothing to go back to.
@immutable
final class RestartCurrentRequested extends QueueEvent {
  const RestartCurrentRequested();
}

/// The armed sleep timer's deadline passed: pause. The timer disarms itself, so the handler only
/// has to stop the audio.
@immutable
final class SleepTimerElapsed extends QueueEvent {
  const SleepTimerElapsed();
}
