import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_net/chordia_net.dart';
import 'package:just_audio/just_audio.dart';

import 'chordia_audio_source.dart';
import 'engine.dart';
import 'stream_cache.dart';

/// [PlaybackEngine] over just_audio, which is ExoPlayer on Android and AVQueuePlayer on iOS.
///
/// Two decks rather than one. A single player can do gapless playlists, but not crossfade — and
/// running the two modes through different machinery would mean the transition between tracks
/// behaved differently depending on a setting, which is exactly where bugs hide. So the engine
/// always has both decks and simply does not overlap them when crossfade is off.
///
/// Only this file may import just_audio. Everything above it speaks [PlaybackEngine], which is what
/// keeps a future bit-perfect native engine a package-local change.
class JustAudioEngine implements PlaybackEngine {
  JustAudioEngine({
    required this.grants,
    required this.factory,
    required this.cache,
    AudioPlayer Function()? createPlayer,
  }) : _createPlayer = createPlayer ?? AudioPlayer.new {
    _a = _createPlayer();
    _b = _createPlayer();
    _primary = _a;
    _attach(_a);
    _attach(_b);
  }

  final GrantManager grants;
  final PinnedHttpClientFactory factory;
  final StreamCache cache;
  final AudioPlayer Function() _createPlayer;

  late final AudioPlayer _a;
  late final AudioPlayer _b;
  late AudioPlayer _primary;

  AudioPlayer get _idle => identical(_primary, _a) ? _b : _a;

  final _positions = StreamController<EnginePosition>.broadcast();
  final _states = StreamController<EngineState>.broadcast();
  final _health = StreamController<EngineHealth>.broadcast();
  final _completions = StreamController<void>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];

  Timer? _ticker;
  Duration _lastPosition = Duration.zero;
  int _lastTickAt = DateTime.now().millisecondsSinceEpoch;

  /// Decks currently fading out. Their `completed` events must not advance the queue: the track
  /// they carry has already been handed over, and letting it through skips a track.
  final _fadingOut = <AudioPlayer>{};

  /// The cache key each deck is currently holding open. A pinned key survives eviction, so it has
  /// to be released when the deck moves on — otherwise every track ever played stays pinned and the
  /// cache's size cap silently stops meaning anything.
  final _pinnedKeys = <AudioPlayer, String>{};

  double _userVolume = 1;
  double _preamp = 1;

  void _attach(AudioPlayer player) {
    _subs.add(
      player.playerStateStream.listen((state) {
        if (!identical(player, _primary)) return;
        _states.add(switch (state.processingState) {
          ProcessingState.idle => EngineState.idle,
          ProcessingState.loading => EngineState.loading,
          ProcessingState.buffering => EngineState.buffering,
          ProcessingState.ready => EngineState.ready,
          ProcessingState.completed => EngineState.completed,
        });
        if (state.processingState == ProcessingState.completed &&
            !_fadingOut.contains(player)) {
          _completions.add(null);
        }
      }),
    );
  }

  void _startTicker() {
    _ticker?.cancel();
    // 2 Hz matches what the web client publishes to the mesh, so a mirrored scrubber on another
    // device moves at the same rate here.
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final tick = Duration(milliseconds: now - _lastTickAt);
      _lastTickAt = now;

      final position = _primary.position;
      final buffered = _primary.bufferedPosition;
      _positions.add(
        EnginePosition(
          position: position,
          buffered: buffered,
          duration: _primary.duration,
          tick: tick,
        ),
      );

      final ahead = buffered - position;
      _health.add(
        EngineHealth(
          // Stalled means wanting to play and having nothing to play with — not merely buffering,
          // which also happens harmlessly while paused.
          stalled:
              _primary.playing &&
              _primary.processingState == ProcessingState.buffering,
          bufferedAhead: ahead.isNegative ? Duration.zero : ahead,
          tick: tick,
        ),
      );
      _lastPosition = position;
    });
  }

  /// Points [deck] at [source], moving the cache pin with it.
  Future<void> _setDeckSource(
    AudioPlayer deck,
    EngineSource source, {
    Duration initialPosition = Duration.zero,
    bool preload = true,
  }) async {
    final previous = _pinnedKeys[deck];
    cache.pin(source.cacheKey);
    _pinnedKeys[deck] = source.cacheKey;
    try {
      await deck.setAudioSource(
        _sourceFor(source),
        initialPosition: initialPosition,
        preload: preload,
      );
    } on Object {
      cache.unpin(source.cacheKey);
      _pinnedKeys.remove(deck);
      rethrow;
    }
    // Released only after the new source is in place: the outgoing bytes may still be read while
    // the deck swaps over.
    if (previous != null && previous != source.cacheKey) cache.unpin(previous);
  }

  void _releaseDeck(AudioPlayer deck) {
    final key = _pinnedKeys.remove(deck);
    if (key != null) cache.unpin(key);
  }

  ChordiaAudioSource _sourceFor(EngineSource source) => ChordiaAudioSource(
    source: source,
    grants: grants,
    factory: factory,
    cache: cache,
  );

  @override
  Future<void> load(
    EngineSource source, {
    Duration initialPosition = Duration.zero,
    bool autoPlay = false,
  }) async {
    // A hard start cancels any crossfade in progress; otherwise the retired deck keeps fading
    // audio in under the new track.
    await _collapseCrossfade();
    await _setDeckSource(_primary, source, initialPosition: initialPosition);
    await _applyGain(_primary);
    _startTicker();
    if (autoPlay) await _primary.play();
  }

  @override
  Future<void> setUpcoming(List<EngineSource> sources) async {
    // just_audio prepares only what it is given as a playlist. The dual-deck design owns queue
    // advancement itself, so preloading here means priming the idle deck with the next track;
    // anything beyond that is the stream cache's job.
    if (sources.isEmpty) return;
    final next = sources.first;
    try {
      await _setDeckSource(_idle, next);
    } on Object {
      // Preloading is an optimisation. A library that is briefly unreachable must not take down
      // the track that is currently playing fine.
    }
  }

  @override
  Future<void> play() => _primary.play();

  @override
  Future<void> pause() async {
    await _collapseCrossfade();
    await _primary.pause();
  }

  @override
  Future<void> stop() async {
    _ticker?.cancel();
    await Future.wait([_a.stop(), _b.stop()]);
  }

  @override
  Future<void> seek(Duration position) => _primary.seek(position);

  @override
  Future<void> setVolume(double volume) async {
    _userVolume = volume.clamp(0, 1);
    await _applyGain(_primary);
  }

  @override
  Future<void> setPreampGain(double linear) async {
    _preamp = linear <= 0 ? 1 : linear;
    await _applyGain(_primary);
  }

  /// The web client shapes the slider as position², which feels linear to the ear; ReplayGain then
  /// multiplies it. The product is clamped because a player cannot amplify above unity — positive
  /// gain needs a platform amplifier, which is an Android-only follow-up.
  Future<void> _applyGain(AudioPlayer player) =>
      player.setVolume((_userVolume * _userVolume * _preamp).clamp(0.0, 1.0));

  @override
  Future<void> swapSource(EngineSource source) async {
    final at = _primary.position;
    final wasPlaying = _primary.playing;
    await _setDeckSource(_primary, source, initialPosition: at);
    await _applyGain(_primary);
    if (wasPlaying) await _primary.play();
  }

  @override
  Future<void> crossfadeTo(EngineSource source, Duration fade) async {
    if (fade <= Duration.zero) {
      await load(source, autoPlay: true);
      return;
    }

    final outgoing = _primary;
    final incoming = _idle;

    // Marked BEFORE the awaits below: the outgoing deck can reach the end of its track while the
    // incoming one is still loading, and an unguarded `completed` there would advance the queue on
    // top of the crossfade already advancing it.
    _fadingOut.add(outgoing);

    try {
      await _setDeckSource(incoming, source);
      await incoming.setVolume(0);
      await incoming.play();

      _primary = incoming;
      _startTicker();

      const steps = 32;
      final stepDuration = Duration(microseconds: fade.inMicroseconds ~/ steps);
      final target = (_userVolume * _userVolume * _preamp).clamp(0.0, 1.0);

      for (var i = 1; i <= steps; i++) {
        final t = i / steps;
        // Equal power, so the perceived loudness stays constant through the overlap rather than
        // dipping in the middle the way a linear fade does.
        await incoming.setVolume(target * _sinCurve(t));
        await outgoing.setVolume(target * _cosCurve(t));
        await Future<void>.delayed(stepDuration);
      }
    } finally {
      await outgoing.stop();
      await outgoing.setVolume(0);
      _fadingOut.remove(outgoing);
      _releaseDeck(outgoing);
    }
  }

  Future<void> _collapseCrossfade() async {
    if (_fadingOut.isEmpty) return;
    for (final deck in _fadingOut.toList()) {
      await deck.stop();
      _fadingOut.remove(deck);
      _releaseDeck(deck);
    }
    await _applyGain(_primary);
  }

  static double _sinCurve(double t) => _approxSin(t * 1.5707963267948966);
  static double _cosCurve(double t) => _approxSin((1 - t) * 1.5707963267948966);

  /// Small-domain sine, avoiding a dart:math import for two calls in a hot loop.
  static double _approxSin(double x) {
    final x2 = x * x;
    return x * (1 - x2 / 6 + x2 * x2 / 120 - x2 * x2 * x2 / 5040);
  }

  @override
  Future<void> setEq(EqConfig? config) async {
    // The Android equaliser attaches to a player's audio session through an AudioPipeline, which
    // just_audio only accepts at construction. Applying a curve therefore belongs to whoever builds
    // the players; this engine reports the request as unsupported rather than silently ignoring it.
    throw UnsupportedError(
      'EQ is applied through the AudioPipeline the players are constructed with.',
    );
  }

  @override
  Stream<EnginePosition> get positions => _positions.stream;

  @override
  Stream<EngineState> get states => _states.stream;

  @override
  Stream<EngineHealth> get health => _health.stream;

  @override
  Stream<void> get completions => _completions.stream;

  Duration get lastPosition => _lastPosition;

  @override
  Future<void> dispose() async {
    _ticker?.cancel();
    _releaseDeck(_a);
    _releaseDeck(_b);
    for (final s in _subs) {
      await s.cancel();
    }
    await Future.wait([_a.dispose(), _b.dispose()]);
    await _positions.close();
    await _states.close();
    await _health.close();
    await _completions.close();
  }
}
