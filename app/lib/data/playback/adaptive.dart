// Adaptive quality. A port of the web client's `frontend/src/lib/audio/quality.ts`, constant for
// constant, so the two clients agree about what "the connection cannot keep up" means.
//
// The listener-selected tier is the CEILING. When the stream genuinely cannot keep up, step down.
// When headroom returns, recover back up toward the ceiling but never above it. Each step
// re-requests the stream at a new profile at the current playhead, which [PlaybackEngine.swapSource]
// does without the listener hearing a restart.
//
// ── Why a low buffered-ahead reading is NOT, on its own, evidence of trouble ─────────────────────
//
// The web controller used to downgrade on exactly that: two consecutive reads of "less than three
// seconds buffered". It fired on perfectly healthy streams, and it fired hardest on the listeners
// least in need of help, because a browser budgets its read-ahead in BYTES: at bit-perfect lossless
// the same byte budget buys a fraction of the seconds it buys at 128 kbps, so a healthy `original`
// stream sits at a permanently low seconds figure. Do not reinstate it here either — this client
// reads its own bytes through [StreamCache], and how far ahead it has fetched is likewise a
// statement about the read-ahead policy, not about the link.
//
// Real starvation is playback failing to keep up, which shows up as one of two things:
//
//   (A) sustained stalling — the engine wants to play and has run out of data — for
//       [downStallSeconds]. Unambiguous: the listener is hearing a gap right now.
//   (B) a sustained drain — buffered-ahead persistently shrinking for [downDrainSeconds] while
//       already under [lowBufferSeconds], i.e. bytes arriving slower than they are consumed. This
//       is the pre-stall slide, caught before it becomes audible.
//
// (A) and (B) are alternatives, never a conjunction: during an actual stall the playhead freezes
// and the buffer *grows*, so requiring both at once would never fire. [lowBufferSeconds] survives
// only as a qualifier on (B) — a *measured* drain — never as a trigger, and buffered-ahead is
// otherwise used only in the upward direction, where a large sustained value really does mean
// headroom.
//
// ── What this port does not have ────────────────────────────────────────────────────────────────
//
// The browser's `suspend` event ("I have decided I hold enough and stopped fetching") has no
// counterpart here, so [QualitySample.suspended] is wired to a constant `false` by [HealthSampler]
// and survives only as the seam a future engine can fill. Recovery therefore rides entirely on
// `bufferSeconds > highBufferSeconds`. That is honest on this platform in a way it was not on the
// web: ExoPlayer and AVPlayer budget their read-ahead in *duration*, so twenty seconds buffered
// means twenty seconds buffered whatever the bitrate.

import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_player/chordia_player.dart';
import 'package:chordia_sync/chordia_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'quality.dart';

/// Buffered-ahead seconds under which a *measured drain* is worth acting on. Never a trigger alone.
const double lowBufferSeconds = 3;

/// Buffered-ahead seconds that count as unambiguous headroom.
const double highBufferSeconds = 20;

// Durations, not tick counts: every threshold below accumulates from each sample's own tick, so
// changing the engine's cadence cannot silently retune the controller.
//
// The web client's old asymmetry was 2 ticks down (1s) against 8 up (4s per rung, 12s to climb back
// from the bottom) — one bad moment pinned the listener low on a connection that was never the
// problem. That insurance against flapping was worth paying for while a downgrade could be
// triggered by a measurement artefact; now that it takes real stalling or a real drain, it is not.

/// Sustained starvation before stepping down — an audible gap, not a blip.
const double downStallSeconds = 1.5;

/// Sustained draining-while-low before stepping down.
const double downDrainSeconds = 3;

/// Sustained headroom before stepping back up one rung.
const double upSeconds = 3;

/// Buffer shrinkage, in seconds of buffer per second of wall clock, that counts as draining. Below
/// this it is jitter or the engine's coarse buffered-position reporting, not the buffer going away.
const double drainRate = 0.1;

// "Playback has genuinely got going" is measured in seconds of audio actually *played*, not wall
// time, so a slow initial fill can never be mistaken for starvation — nothing has starved if
// nothing has played yet. The elapsed cap is the escape hatch: a source that has managed under
// [warmupPlayedSeconds] of audio after [warmupElapsedSeconds] of trying is in trouble by any
// definition, and must not be locked out of downgrading forever.
const double warmupPlayedSeconds = 5;
const double warmupElapsedSeconds = 20;

/// One observation of stream health, in the vocabulary the controller reasons in.
///
/// Deliberately a superset of what [EngineHealth] carries. The engine reports what just_audio can
/// see; the fields it cannot fill are computed by [HealthSampler] (the trend delta, the sample
/// counter) or left at their inert value ([suspended]) so the rule set stays a literal port and a
/// future engine can supply them without the rules moving.
@immutable
class QualitySample {
  const QualitySample({
    required this.tick,
    required this.playing,
    required this.starving,
    required this.bufferSeconds,
    required this.bufferDeltaSeconds,
    required this.seq,
    this.suspended = false,
  });

  /// Time since the previous sample. Every threshold accumulates from this rather than counting.
  final Duration tick;

  /// The engine is advancing. [starving], [bufferDeltaSeconds] and any trend derived from them are
  /// only meaningful while this is true.
  final bool playing;

  /// Playback is starved right now: it wants to sound and has nothing to sound with. The only
  /// field that means "the connection cannot keep up".
  final bool starving;

  /// Seconds of audio buffered ahead of the playhead. MUST NOT decide a downgrade on its own; see
  /// this file's header.
  final double bufferSeconds;

  /// Change in [bufferSeconds] since the previous sample in this series, or null when there is no
  /// comparable predecessor. Divide by the tick to get a per-second rate.
  final double? bufferDeltaSeconds;

  /// The engine has stopped fetching on purpose because it holds enough. Always false today; see
  /// the header. While true a downgrade is unreachable and recovery is granted outright.
  final bool suspended;

  /// Monotonic counter, 0 for the first sample of each new series. A consumer MUST treat 0 as a
  /// discontinuity and drop any streak state: statistics either side describe different streams or
  /// different playhead regions and are not comparable.
  final int seq;
}

/// Turns the engine's [EngineHealth] into [QualitySample]s.
///
/// Owns the two things a single health reading cannot know: whether it is comparable with the one
/// before it, and by how much the buffer moved since.
class HealthSampler {
  int _seq = 0;
  double? _lastBufferSeconds;

  /// Begins a new series. Called on a track change, a quality swap, or a detected seek.
  void restart() {
    _seq = 0;
    _lastBufferSeconds = null;
  }

  QualitySample sample(EngineHealth health, {required bool playing}) {
    final buffered = health.bufferedAhead.inMicroseconds / 1e6;
    final delta = _lastBufferSeconds == null
        ? null
        : buffered - _lastBufferSeconds!;
    final sample = QualitySample(
      tick: health.tick,
      playing: playing,
      starving: health.stalled,
      bufferSeconds: buffered,
      bufferDeltaSeconds: delta,
      seq: _seq,
    );
    _seq++;
    _lastBufferSeconds = buffered;
    return sample;
  }
}

/// The rung ladder and the streak arithmetic. No I/O, no engine, no clock of its own.
class AdaptiveQualityController {
  AdaptiveQualityController({
    required QualityProfile selected,
    this.autoDowngrade = true,
  }) : _current = selected,
       _ceilingIdx = qualityLadder.indexOf(selected);

  /// Allow automatic downgrade under bandwidth pressure.
  ///
  /// A local flag rather than a `UserSettings` field, because the Hub has none: the web client
  /// keeps this beside its own per-network tier choices. Off means this class only ever reports.
  final bool autoDowngrade;

  QualityProfile _current;

  /// Ladder index the controller may not auto-recover above (the listener's tier).
  int _ceilingIdx;

  // Evidence accumulators, all in seconds, all reset by anything that breaks their continuity.
  double _stallSeconds = 0;
  double _drainSeconds = 0;
  double _healthySeconds = 0;

  /// Audio actually played, and wall time elapsed, on the current source.
  double _playedSeconds = 0;
  double _sourceSeconds = 0;

  /// The tier actually streaming right now.
  QualityProfile get profile => _current;

  /// The tier the listener asked for — the recovery ceiling, never a floor.
  QualityProfile get selected => qualityLadder[_ceilingIdx];

  /// True while the active stream sits below the listener's tier, so the UI can say so.
  bool get downgraded => qualityLadder.indexOf(_current) > _ceilingIdx;

  /// Force the active profile back to what is really streaming (e.g. after a swap failed).
  void revertTo(QualityProfile profile) {
    _current = profile;
    resetSource();
  }

  /// Put the listener back on their chosen tier, now, at their explicit request.
  ///
  /// Distinct from [setCeiling], which only ever clamps DOWNWARD — re-picking the tier you are
  /// already set to is a no-op there, so the "you're being downgraded" readout pointed at a control
  /// that could not undo it. An explicit restore also clears the streak state, so the next
  /// observation starts from scratch rather than immediately re-tripping the rule that demoted you.
  ///
  /// Returns the new active profile if it changed, otherwise null.
  QualityProfile? restore() {
    final target = qualityLadder[_ceilingIdx];
    resetSource();
    if (_current == target) return null;
    _current = target;
    return _current;
  }

  /// The listener changed their tier, or the network class did. Resets the ceiling and clamps the
  /// active profile so it never sits above the new one.
  ///
  /// Returns the new active profile if it changed (the caller performs the gapless re-request),
  /// otherwise null.
  QualityProfile? setCeiling(QualityProfile profile) {
    final next = qualityLadder.indexOf(profile);
    final moved = next != _ceilingIdx;
    _ceilingIdx = next;
    resetSource();
    final idx = qualityLadder.indexOf(_current);
    // Active stream sits above the new ceiling: clamp down. Unconditional, because the ceiling is
    // a hard limit however it was reached.
    if (idx < next) {
      _current = profile;
      return _current;
    }
    // RAISING the ceiling takes effect immediately, rather than leaving the active stream where a
    // past downgrade parked it and waiting for `observe` to earn its way back up one rung at a
    // time. Picking a higher tier and being told "reduced from Lossless — the connection can't keep
    // up" for the next few seconds reads as the setting being ignored. A raise is either the
    // listener asking outright or the network class improving; both are grounds to try again now.
    // The evidence is reset above, so a genuinely struggling connection simply downgrades again.
    if (moved && idx > next) {
      _current = profile;
      return _current;
    }
    return null;
  }

  /// Feed one observation. Returns the new profile if it changed, otherwise null.
  QualityProfile? observe(QualitySample h) {
    // `seq == 0` marks a new sample series: a different source (track change, quality swap,
    // crossfade flip) or a seek. Nothing measured before it describes this stream, or this region
    // of it.
    if (h.seq == 0) resetSource();

    if (!autoDowngrade) return null;

    final dt = (h.tick.inMilliseconds < 1 ? 1 : h.tick.inMilliseconds) / 1000;

    // Paused or ended: there is nothing to starve and nothing to earn. Let every streak lapse
    // rather than bank it.
    if (!h.playing) {
      _stallSeconds = 0;
      _drainSeconds = 0;
      _healthySeconds = 0;
      return null;
    }

    _sourceSeconds += dt;
    if (!h.starving) _playedSeconds += dt;
    final warm =
        _playedSeconds >= warmupPlayedSeconds ||
        _sourceSeconds >= warmupElapsedSeconds;

    final idx = qualityLadder.indexOf(_current);

    // While the engine has suspended fetching it is stating outright that it is not
    // bandwidth-limited, so neither trouble signal can accumulate and a downgrade is simply not
    // reachable from that state.
    _stallSeconds = h.starving && !h.suspended ? _stallSeconds + dt : 0;

    final delta = h.bufferDeltaSeconds;
    final draining =
        !h.suspended &&
        h.bufferSeconds < lowBufferSeconds &&
        delta != null &&
        delta / dt <= -drainRate;
    _drainSeconds = draining ? _drainSeconds + dt : 0;

    if (_stallSeconds >= downStallSeconds ||
        _drainSeconds >= downDrainSeconds) {
      _healthySeconds = 0;
      if (warm && idx < qualityLadder.length - 1) {
        _current = qualityLadder[idx + 1];
        // The swap starts a fresh fetch and a fresh fill. Judge the new tier on its own evidence:
        // one bad patch must not cascade the whole ladder inside a second.
        resetSource();
        return _current;
      }
      return null;
    }

    // `suspended` counts as headroom on its own — a stronger statement about spare bandwidth than
    // any seconds figure.
    if (!h.starving && (h.suspended || h.bufferSeconds > highBufferSeconds)) {
      _healthySeconds += dt;
      if (_healthySeconds >= upSeconds && idx > _ceilingIdx) {
        _current = qualityLadder[idx - 1];
        resetSource();
        return _current;
      }
      return null;
    }

    // Neither in trouble nor clearly comfortable: hold, and decay the headroom streak so a recovery
    // has to be earned continuously rather than accumulated across rough patches.
    _healthySeconds = 0;
    return null;
  }

  /// Drop all per-source evidence (new track, seek, or a profile swap).
  void resetSource() {
    _stallSeconds = 0;
    _drainSeconds = 0;
    _healthySeconds = 0;
    _playedSeconds = 0;
    _sourceSeconds = 0;
  }
}

/// Why what is playing is not what was asked for.
enum QualityLimit {
  /// It is the chosen tier.
  none,

  /// A metered link capped it before the stream was ever requested.
  network,

  /// The controller stepped down because the stream could not keep up.
  adaptive,
}

/// What the listener asked for against what is actually sounding.
@immutable
class QualityStatus {
  const QualityStatus({
    required this.chosen,
    required this.ceiling,
    required this.playing,
    required this.fixed,
  });

  /// The tier in the listener's settings.
  final QualityProfile chosen;

  /// [chosen] after the network cap — the recovery ceiling.
  final QualityProfile ceiling;

  /// The tier the bytes now sounding were fetched at.
  final QualityProfile playing;

  /// The current source is a downloaded file or a fully cached stream, so its tier is a property of
  /// the bytes on disk and nothing can change it for this track.
  final bool fixed;

  QualityLimit get limit {
    if (fixed) return QualityLimit.none;
    if (qualityLadder.indexOf(playing) > qualityLadder.indexOf(ceiling)) {
      return QualityLimit.adaptive;
    }
    if (qualityLadder.indexOf(ceiling) > qualityLadder.indexOf(chosen)) {
      return QualityLimit.network;
    }
    return QualityLimit.none;
  }

  /// Whether an explicit "put me back" is available and would do anything.
  bool get restorable => !fixed && limit == QualityLimit.adaptive;

  @override
  bool operator ==(Object other) =>
      other is QualityStatus &&
      other.chosen == chosen &&
      other.ceiling == ceiling &&
      other.playing == playing &&
      other.fixed == fixed;

  @override
  int get hashCode => Object.hash(chosen, ceiling, playing, fixed);
}

/// Whether a source's bytes are already held in full, in which case there is nothing to adapt.
typedef CacheCompletenessProbe = Future<bool> Function(EngineSource source);

/// Drives [AdaptiveQualityController] from the live engine and publishes the divergence.
///
/// A plain object, not a notifier or a widget: Android can start the audio service into a process
/// with no UI at all, and adaptation has to work there too.
class AdaptiveQualityService {
  AdaptiveQualityService({
    required this.engine,
    required QualityProfile Function() chosen,
    required NetworkStatus Function() network,
    required bool Function() playing,
    required CacheCompletenessProbe isFullyCached,
    bool autoDowngrade = true,
  }) : _chosen = chosen,
       _network = network,
       _playing = playing,
       _isFullyCached = isFullyCached,
       _autoDowngrade = autoDowngrade {
    final ceiling = effectiveQuality(chosen: chosen(), network: network());
    _controller = AdaptiveQualityController(
      selected: ceiling,
      autoDowngrade: autoDowngrade,
    );
    _status = ValueNotifier(
      QualityStatus(
        chosen: chosen(),
        ceiling: ceiling,
        playing: ceiling,
        fixed: false,
      ),
    );
  }

  final PlaybackEngine engine;
  final QualityProfile Function() _chosen;
  final NetworkStatus Function() _network;
  final bool Function() _playing;
  final CacheCompletenessProbe _isFullyCached;
  final bool _autoDowngrade;

  late final AdaptiveQualityController _controller;
  late final ValueNotifier<QualityStatus> _status;
  final _sampler = HealthSampler();
  final _subs = <StreamSubscription<Object?>>[];

  /// What is playing versus what was asked for. Watched by the quality sheet.
  ValueListenable<QualityStatus> get status => _status;

  EngineSource? _source;

  /// Whether the current source's bytes are already held in full — null until the probe answers.
  ///
  /// Three states, not two: "not yet known" must not be drawn as "this track's tier is fixed", or
  /// every track would flash that claim for as long as a disk read takes.
  bool? _complete;

  /// A swap is worth making only for a stream that is still being fetched. A download, or a stream
  /// already held in full, would be re-fetched at a tier nobody asked for to solve a problem local
  /// playback cannot have.
  bool get _adaptable => _source is StreamedSource && _complete == false;

  bool _swapping = false;

  /// Where the playhead was expected to be at the next tick, for discontinuity detection.
  Duration? _expectedPosition;

  /// Playhead movement beyond this between two ticks is a seek or a deck flip, not playback.
  ///
  /// The engine reports no seek of its own, and a post-seek refill looks exactly like starvation —
  /// the web client excludes it explicitly, and inferring it from the playhead is how this client
  /// gets the same exclusion without the engine growing an event for it.
  static const _discontinuity = Duration(seconds: 2);

  void start() {
    _subs
      ..add(engine.positions.listen(_onPosition))
      ..add(engine.health.listen(_onHealth));
  }

  /// Wraps the app's source resolver so the service learns what is playing without the resolver
  /// having to know it exists.
  ///
  /// Install it AFTER `PlaybackService.start()`, which is what puts the inner resolver on the
  /// handler in the first place.
  Future<EngineSource> Function(PlayerTrack) decorate(
    Future<EngineSource> Function(PlayerTrack) inner,
  ) {
    return (track) async {
      final source = await inner(track);
      onSourceResolved(source);
      return source;
    };
  }

  /// A new source is about to play.
  void onSourceResolved(EngineSource source) {
    _source = source;
    _expectedPosition = null;
    _sampler.restart();
    _controller.revertTo(switch (source) {
      DownloadedSource(:final profile) => profile,
      StreamedSource(:final profile) => profile,
    });
    _complete = source is DownloadedSource ? true : null;
    _publish();
    if (source is! StreamedSource) return;
    unawaited(
      _isFullyCached(source).then((complete) {
        // A late answer about a source that has since been replaced says nothing about this one.
        if (!identical(_source, source)) return;
        _complete = complete;
        _publish();
      }),
    );
  }

  /// The listener's tier or the network class changed.
  void onCeilingChanged() {
    final ceiling = effectiveQuality(chosen: _chosen(), network: _network());
    final next = _controller.setCeiling(ceiling);
    _sampler.restart();
    if (next != null) unawaited(_swap(next));
    _publish();
  }

  /// Put the stream back on the listener's tier at their explicit request.
  Future<void> restore() async {
    final next = _controller.restore();
    _sampler.restart();
    if (next != null) await _swap(next);
    _publish();
  }

  void _onPosition(EnginePosition position) {
    final expected = _expectedPosition;
    if (expected != null) {
      final drift = position.position - expected;
      if (drift.abs() > _discontinuity) _sampler.restart();
    }
    _expectedPosition = position.position + position.tick;
  }

  void _onHealth(EngineHealth health) {
    final sample = _sampler.sample(health, playing: _playing());
    if (!_adaptable || _swapping || !_autoDowngrade) return;
    final next = _controller.observe(sample);
    if (next != null) unawaited(_swap(next));
  }

  Future<void> _swap(QualityProfile profile) async {
    final source = _source;
    if (source is! StreamedSource || source.profile == profile) return;
    final next = StreamedSource(
      track: source.track,
      libraryId: source.libraryId,
      trackRef: source.trackRef,
      profile: profile,
      contentHash: source.contentHash,
    );
    _swapping = true;
    try {
      // The engine keeps the playhead across a swap, which is what makes this inaudible.
      await engine.swapSource(next);
      _source = next;
      _sampler.restart();
    } on Object {
      // The tier that is still sounding is the old one. Telling the controller otherwise would
      // leave it measuring a stream that does not exist.
      _controller.revertTo(source.profile);
    } finally {
      _swapping = false;
      _publish();
    }
  }

  void _publish() {
    _status.value = QualityStatus(
      chosen: _chosen(),
      ceiling: _controller.selected,
      playing: _controller.profile,
      fixed: _complete ?? false,
    );
  }

  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    _status.dispose();
  }
}

/// The adaptive-quality service, built once for the life of the process.
///
/// Declared here rather than in `app/providers.dart` because everything it needs is already a
/// provider there and nothing there needs it back — the player UI reaches it through this file, and
/// `bootstrap` starts it.
final adaptiveQualityProvider = Provider<AdaptiveQualityService>((ref) {
  final cache = ref.watch(streamCacheProvider);
  final service = AdaptiveQualityService(
    engine: ref.watch(playbackEngineProvider),
    chosen: () => ref.read(playbackPreferencesProvider).quality,
    network: () => ref.read(networkStatusProvider),
    // Read from the media session rather than tracked here: it is the one place that already knows
    // whether sound is being produced, including when the OS paused us for a phone call.
    playing: () => ref.read(audioHandlerProvider).playbackState.value.playing,
    isFullyCached: (source) async =>
        (await cache.entryFor(source.cacheKey)).isComplete,
  );
  // Either of these moves the ceiling, and a ceiling that moved has to clamp or release the active
  // stream immediately rather than at the next track.
  ref
    ..listen(networkStatusProvider, (_, _) => service.onCeilingChanged())
    ..listen(
      playbackPreferencesProvider.select((p) => p.quality),
      (_, _) => service.onCeilingChanged(),
    )
    ..onDispose(service.dispose);
  return service;
});
