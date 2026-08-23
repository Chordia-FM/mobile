import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart';
import 'package:meta/meta.dart';

/// Where a track's bytes come from, and at what tier.
///
/// Resolution is deliberately not a URL: a downloaded track is a local file needing no credential
/// at all, while a streamed one needs a capability token that expires faster than some tracks
/// play. Keeping the distinction in the type stops a caller treating them alike.
@immutable
sealed class EngineSource {
  const EngineSource({required this.track});

  final PlayerTrack track;

  /// Identity for caching and for deciding whether a quality swap is even possible.
  String get cacheKey;
}

/// A track already on disk. Plays with no network and no grant.
class DownloadedSource extends EngineSource {
  const DownloadedSource({
    required super.track,
    required this.filePath,
    required this.profile,
  });

  final String filePath;
  final QualityProfile profile;

  @override
  String get cacheKey => 'file:$filePath';
}

/// A track streamed from a library server, fetched over a pinned connection.
class StreamedSource extends EngineSource {
  const StreamedSource({
    required super.track,
    required this.libraryId,
    required this.trackRef,
    required this.profile,
    this.contentHash,
  });

  final String libraryId;
  final String trackRef;
  final QualityProfile profile;

  /// The library's SHA-256 of the file, which doubles as its ETag. Lets a cached partial file be
  /// revalidated instead of refetched.
  final String? contentHash;

  @override
  String get cacheKey => '$libraryId:$trackRef:${profile.wire}';
}

/// A position report from the engine.
@immutable
class EnginePosition {
  const EnginePosition({
    required this.position,
    required this.buffered,
    required this.duration,
    required this.tick,
  });

  final Duration position;

  /// How far ahead of [position] the engine has buffered.
  final Duration buffered;
  final Duration? duration;

  /// Time since the previous report. The adaptive-quality controller accumulates real elapsed
  /// time rather than counting ticks, so an irregular tick rate cannot skew its decisions.
  final Duration tick;

  Duration get bufferedAhead {
    final ahead = buffered - position;
    return ahead.isNegative ? Duration.zero : ahead;
  }
}

enum EngineState { idle, loading, buffering, ready, completed }

/// Health signals the adaptive-quality controller reads.
@immutable
class EngineHealth {
  const EngineHealth({
    required this.stalled,
    required this.bufferedAhead,
    required this.tick,
  });

  /// True when the engine wants to play but has run out of data.
  final bool stalled;
  final Duration bufferedAhead;
  final Duration tick;
}

/// The seam a different playback implementation slots into.
///
/// Today this is just_audio over ExoPlayer/AVPlayer. The scaffold this app replaced promised a
/// bespoke bit-perfect and Atmos engine; that remains worth building, and when it is, it
/// implements this interface rather than replacing everything above it. Nothing outside
/// `src/engine` may reference just_audio, so the swap stays a one-package change.
abstract interface class PlaybackEngine {
  /// Loads [source] and optionally begins playing at [initialPosition].
  Future<void> load(
    EngineSource source, {
    Duration initialPosition = Duration.zero,
    bool autoPlay = false,
  });

  /// Declares the upcoming sources so the engine can prepare them, which is what makes a
  /// transition gapless. Ignored by engines that cannot preload.
  Future<void> setUpcoming(List<EngineSource> sources);

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);

  /// 0..1, applied after [setPreampGain].
  Future<void> setVolume(double volume);

  /// Linear ReplayGain multiplier for the current track. Values above 1 cannot be reached by
  /// attenuation alone; an engine may implement them with a platform amplifier or clamp.
  Future<void> setPreampGain(double linear);

  /// Replaces the current source in place, keeping the playhead — how a quality change happens
  /// without the listener hearing a restart.
  Future<void> swapSource(EngineSource source);

  /// Fades from the current source into [source] over [fade]. Engines without a second deck may
  /// fall back to [load]; callers must not assume a crossfade actually overlapped.
  Future<void> crossfadeTo(EngineSource source, Duration fade);

  Future<void> setEq(EqConfig? config);

  Stream<EnginePosition> get positions;
  Stream<EngineState> get states;
  Stream<EngineHealth> get health;

  /// Fires when the current source plays to its end. Distinct from [states] reaching
  /// [EngineState.completed], because a crossfade retires a deck without the queue advancing.
  Stream<void> get completions;

  Future<void> dispose();
}
