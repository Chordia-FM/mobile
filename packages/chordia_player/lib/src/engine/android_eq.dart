import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Resamples a Chordia EQ curve onto the frequencies a device equalizer actually has.
///
/// Injected rather than implemented here: the analytic response is the same function that draws the
/// curve on the EQ screen, and it lives with the rest of the model in the app. Passing it in is what
/// guarantees the picture and the sound are computed from one definition.
typedef EqCurveMapper =
    List<double> Function({
      required List<EqBand> bands,
      required double preamp,
      required List<double> centreFrequencies,
      required double minDb,
      required double maxDb,
    });

/// The device equalizer behind just_audio's `AudioPipeline`.
///
/// ## Why this is not `PlaybackEngine.setEq`
///
/// An `AndroidEqualizer` is an `AudioEffect`, and just_audio accepts effects only through an
/// `AudioPipeline` handed to `AudioPlayer`'s constructor. A curve therefore cannot be attached to a
/// player that already exists, which is why the engine's `setEq` refuses outright: whoever
/// *constructs* the players owns the equalizer. This class is that owner, and it hands the engine a
/// `createPlayer` that builds players already wired to it.
///
/// One effect instance per player, never shared — just_audio documents that the same effect cannot
/// sit on two players at once, and this engine runs two decks.
///
/// ## What the listener actually hears
///
/// `android.media.audiofx.Equalizer` reports its own band count and centre frequencies, chosen by
/// the device. Five bands is typical; ten at our frequencies is not available on any device the app
/// can ask. [mapCurve] therefore evaluates our response at each of the device's centre frequencies
/// and that value becomes the band's gain — an approximation of the curve, exact only where a device
/// band happens to sit on one of ours. There is no separate preamp control in the platform effect,
/// so the preamp is folded into the same evaluation.
///
/// Everywhere other than Android this class is inert by construction: [createPlayer] builds a plain
/// player and [apply] stores the config without anything to send it to.
class AndroidEqualizerController {
  AndroidEqualizerController({
    required this.mapCurve,
    @visibleForTesting bool? supported,
    @visibleForTesting
    AudioPlayer Function(AudioPipeline? pipeline)? createAudioPlayer,
  }) : _supported =
           supported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
       _createAudioPlayer =
           createAudioPlayer ??
           ((pipeline) => AudioPlayer(audioPipeline: pipeline));

  final EqCurveMapper mapCurve;
  final bool _supported;
  final AudioPlayer Function(AudioPipeline?) _createAudioPlayer;

  final _equalizers = <AndroidEqualizer>[];

  EqConfig? _config;

  /// Bumped on every [apply]. A device's band parameters are only readable once the effect has been
  /// activated by a source actually loading, so an apply can be left waiting arbitrarily long — and
  /// a stale one landing after a newer curve would silently undo it.
  int _generation = 0;

  /// Whether a curve reaches the audio on this platform at all. False on iOS.
  bool get supported => _supported;

  /// The curve last asked for, whether or not it could be applied.
  EqConfig? get config => _config;

  /// Builds a player wired to a fresh equalizer of its own. Passed to the engine as its
  /// `createPlayer`, so every deck it opens carries the pipeline from birth.
  AudioPlayer createPlayer() {
    if (!_supported) return _createAudioPlayer(null);
    final equalizer = AndroidEqualizer();
    _equalizers.add(equalizer);
    final player = _createAudioPlayer(
      AudioPipeline(androidAudioEffects: [equalizer]),
    );
    // A player built after a curve was set must not start flat.
    unawaited(_push(equalizer, _config, _generation));
    return player;
  }

  /// Applies [config] to every deck. A null config, or one that is not enabled, turns the effect
  /// off rather than flattening it — an inactive effect is not in the signal path at all.
  Future<void> apply(EqConfig? config) async {
    _config = config;
    final generation = ++_generation;
    if (!_supported) return;
    await Future.wait([
      for (final equalizer in _equalizers) _push(equalizer, config, generation),
    ]);
  }

  Future<void> _push(
    AndroidEqualizer equalizer,
    EqConfig? config,
    int generation,
  ) async {
    final enabled = config?.enabled ?? false;
    final bands = config?.bands ?? const <EqBand>[];
    try {
      await equalizer.setEnabled(enabled && bands.isNotEmpty);
      if (!enabled || bands.isEmpty) return;

      // Resolves only once a source has been loaded on this player: the effect has no parameters to
      // report before the platform has attached it to an audio session.
      final parameters = await equalizer.parameters;
      if (generation != _generation) return;

      final gains = mapCurve(
        bands: bands,
        preamp: config?.preamp ?? 0,
        centreFrequencies: [
          for (final band in parameters.bands) band.centerFrequency,
        ],
        minDb: parameters.minDecibels,
        maxDb: parameters.maxDecibels,
      );
      for (var i = 0; i < parameters.bands.length && i < gains.length; i++) {
        await parameters.bands[i].setGain(gains[i]);
        if (generation != _generation) return;
      }
    } on Object {
      // A device whose equalizer refuses to attach still has to play music. The curve is kept in
      // [config] so a later deck, or a later apply, can try again.
    }
  }

  Future<void> dispose() async {
    _equalizers.clear();
  }
}
