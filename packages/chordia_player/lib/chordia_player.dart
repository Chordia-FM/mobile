/// Playback: the queue, the engine that sounds it, and the record of what was heard.
///
/// The engine sits behind [PlaybackEngine] so the one implementation that knows about just_audio
/// stays swappable — the bit-perfect and spatial-audio engine this client was originally imagined
/// around is a future implementation of that interface, not a rewrite of everything above it.
library;

export 'src/engine/chordia_audio_source.dart';
export 'src/engine/engine.dart';
export 'src/engine/just_audio_engine.dart';
export 'src/engine/stream_cache.dart';
export 'src/queue/continuation.dart';
export 'src/queue/queue_controller.dart';
export 'src/queue/queue_events.dart';
export 'src/queue/upcoming.dart';
export 'src/scrobble/fingerprint.dart';
export 'src/scrobble/scrobble_latch.dart';
export 'src/scrobble/scrobble_service.dart';
