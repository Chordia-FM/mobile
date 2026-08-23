// Equalizer model: the ten bands, the built-in presets, and the DSP that turns them into a curve.
//
// A port of the web client's `frontend/src/lib/audio/eq.ts`, band for band and preset for preset, so
// a listener who shapes their sound on the desktop and picks it up on the phone sees the same
// numbers. The Rust `default_eq_bands` is the third copy of the same list.
//
// ── Exact settings, approximate sound ───────────────────────────────────────────────────────────
//
// The *settings* here are exact parity: the persisted [EqConfig] is the same document the web
// client writes, and [eqCurveDb] draws the same response.
//
// What is applied to the audio is not. Android's equalizer effect exposes a band count and centre
// frequencies chosen by the DEVICE — typically five bands, at frequencies that are not ours — and
// the app does not get to ask for ten at 31 Hz…16 kHz. So the curve is *resampled*:
// [deviceBandGains] evaluates our analytic response at each centre frequency the device reports and
// hands back that gain. The shape the listener drew is preserved where the device has a control and
// smoothed where it does not, and a deep narrow notch between two device bands is simply not
// reproducible. iOS gets nothing at all: there is no equivalent effect behind just_audio's
// `AudioPipeline` on Darwin.
//
// That gap is the honest state of things until the bit-perfect native engine exists, and the EQ
// screen says so rather than implying the phone is doing what the picture shows.

import 'dart:math' as math;

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';

/// Standard 10-band ISO frequencies (Hz). Mirrors the Rust `default_eq_bands`.
const List<double> eqFreqs = [
  31,
  62,
  125,
  250,
  500,
  1000,
  2000,
  4000,
  8000,
  16000,
];

/// The Q every built-in band uses. Wide enough that ten of them overlap into a smooth curve.
const double defaultQ = 1.4;

/// The dB range the sliders span, matching the web client's.
const double eqGainRange = 12;

List<EqBand> get defaultEqBands => [
  for (final freq in eqFreqs) EqBand(freq: freq, gain: 0, q: defaultQ),
];

EqConfig get defaultEq =>
    EqConfig(enabled: false, preamp: 0, bands: defaultEqBands);

/// A preset shipped with the app.
@immutable
class BuiltInPreset {
  const BuiltInPreset({
    required this.name,
    required this.labelKey,
    required this.preamp,
    required this.gains,
  });

  /// Stable identity, persisted and matched. Not displayed — use [labelKey].
  final String name;

  /// i18n key for the display label, so the identity above stays locale-stable.
  final String labelKey;

  final double preamp;

  /// dB per band, aligned to [eqFreqs].
  final List<double> gains;

  List<EqBand> get bands => presetToBands(gains);
}

/// Built-in presets (dB gains per band). "Flat" is the identity.
const List<BuiltInPreset> builtInPresets = [
  BuiltInPreset(
    name: 'Flat',
    labelKey: PlayerKeys.eqPresetFlat,
    preamp: 0,
    gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  ),
  BuiltInPreset(
    name: 'Bass Boost',
    labelKey: PlayerKeys.eqPresetBassBoost,
    preamp: -2,
    gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0],
  ),
  BuiltInPreset(
    name: 'Bass Reducer',
    labelKey: PlayerKeys.eqPresetBassReducer,
    preamp: 0,
    gains: [-6, -5, -4, -2, 0, 0, 0, 0, 0, 0],
  ),
  BuiltInPreset(
    name: 'Treble Boost',
    labelKey: PlayerKeys.eqPresetTrebleBoost,
    preamp: -2,
    gains: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6],
  ),
  BuiltInPreset(
    name: 'Treble Reducer',
    labelKey: PlayerKeys.eqPresetTrebleReducer,
    preamp: 0,
    gains: [0, 0, 0, 0, 0, -1, -2, -4, -5, -6],
  ),
  BuiltInPreset(
    name: 'Vocal',
    labelKey: PlayerKeys.eqPresetVocal,
    preamp: -1,
    gains: [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1],
  ),
  BuiltInPreset(
    name: 'Rock',
    labelKey: PlayerKeys.eqPresetRock,
    preamp: -2,
    gains: [5, 4, 3, 1, -1, -1, 0, 2, 3, 4],
  ),
  BuiltInPreset(
    name: 'Pop',
    labelKey: PlayerKeys.eqPresetPop,
    preamp: -1,
    gains: [-1, 0, 2, 4, 4, 3, 1, 0, -1, -2],
  ),
  BuiltInPreset(
    name: 'Jazz',
    labelKey: PlayerKeys.eqPresetJazz,
    preamp: -1,
    gains: [4, 3, 1, 2, -1, -1, 0, 1, 3, 4],
  ),
  BuiltInPreset(
    name: 'Classical',
    labelKey: PlayerKeys.eqPresetClassical,
    preamp: -1,
    gains: [4, 3, 2, 1, -1, -1, 0, 2, 3, 4],
  ),
  BuiltInPreset(
    name: 'Electronic',
    labelKey: PlayerKeys.eqPresetElectronic,
    preamp: -2,
    gains: [5, 4, 1, 0, -2, 2, 1, 1, 4, 5],
  ),
  BuiltInPreset(
    name: 'Hip-Hop',
    labelKey: PlayerKeys.eqPresetHipHop,
    preamp: -2,
    gains: [6, 5, 3, 2, -1, -1, 1, 2, 2, 3],
  ),
  BuiltInPreset(
    name: 'Acoustic',
    labelKey: PlayerKeys.eqPresetAcoustic,
    preamp: -1,
    gains: [4, 4, 3, 1, 2, 2, 3, 3, 2, 2],
  ),
  BuiltInPreset(
    name: 'Loudness',
    labelKey: PlayerKeys.eqPresetLoudness,
    preamp: -3,
    gains: [6, 4, 0, 0, -2, 0, 0, 3, 6, 6],
  ),
];

/// Build full bands (with the standard freqs and Q) from a built-in dB-gain array.
List<EqBand> presetToBands(List<double> gains) => [
  for (var i = 0; i < eqFreqs.length; i++)
    EqBand(
      freq: eqFreqs[i],
      gain: i < gains.length ? gains[i] : 0,
      q: defaultQ,
    ),
];

double dbToGain(double db) => math.pow(10, db / 20).toDouble();

/// Whether two band sets and preamps are effectively equal, for "which preset is active".
bool eqMatches(
  List<EqBand> bands,
  double preamp,
  List<EqBand> otherBands,
  double otherPreamp,
) {
  if ((preamp - otherPreamp).abs() > 0.01) return false;
  if (bands.length != otherBands.length) return false;
  for (var i = 0; i < bands.length; i++) {
    final a = bands[i];
    final b = otherBands[i];
    if ((a.freq - b.freq).abs() >= 0.5) return false;
    if ((a.gain - b.gain).abs() >= 0.05) return false;
    if ((a.q - b.q).abs() >= 0.01) return false;
  }
  return true;
}

/// Log-spaced frequency axis (Hz) for the response curve.
List<double> logFreqs(int count, {double min = 20, double max = 20000}) {
  final lmin = _log10(min);
  final lmax = _log10(max);
  return [
    for (var i = 0; i < count; i++)
      math.pow(10, lmin + (i / (count - 1)) * (lmax - lmin)).toDouble(),
  ];
}

/// Magnitude (dB) of one RBJ peaking biquad at frequency [f]. Cheap enough to call per frame.
double peakingDb({
  required double f0,
  required double gainDb,
  required double q,
  required double f,
  double fs = 44100,
}) {
  final a = math.pow(10, gainDb / 40).toDouble();
  final w0 = 2 * math.pi * f0 / fs;
  final cw = math.cos(w0);
  final alpha = math.sin(w0) / (2 * q);
  final b0 = 1 + alpha * a;
  final b1 = -2 * cw;
  final b2 = 1 - alpha * a;
  final a0 = 1 + alpha / a;
  final a1 = -2 * cw;
  final a2 = 1 - alpha / a;
  final w = 2 * math.pi * f / fs;
  final cosw = math.cos(w);
  final sinw = math.sin(w);
  final cos2w = math.cos(2 * w);
  final sin2w = math.sin(2 * w);
  final numRe = b0 + b1 * cosw + b2 * cos2w;
  final numIm = -(b1 * sinw + b2 * sin2w);
  final denRe = a0 + a1 * cosw + a2 * cos2w;
  final denIm = -(a1 * sinw + a2 * sin2w);
  final num = math.sqrt(numRe * numRe + numIm * numIm);
  final den = math.sqrt(denRe * denRe + denIm * denIm);
  return 20 * _log10(num / den);
}

/// The combined analytic response (dB) of the whole chain at each of [freqs].
///
/// The same function draws the curve on screen and decides what to ask the device equalizer for, so
/// the picture and the approximation can never drift apart.
List<double> eqCurveDb(
  List<EqBand> bands,
  double preamp,
  List<double> freqs, {
  double fs = 44100,
}) => [
  for (final f in freqs)
    bands.fold<double>(
      preamp,
      (db, b) =>
          db + peakingDb(f0: b.freq, gainDb: b.gain, q: b.q, f: f, fs: fs),
    ),
];

/// Resample our ten-band curve onto whatever bands the device actually has.
///
/// [centreFrequencies] come from `AndroidEqualizerParameters`; they are the device's, not ours, and
/// there are usually five of them. Each gets the analytic response of our chain *at that frequency*
/// — preamp included, since a flat offset across every band is the only preamp an
/// android.media.audiofx.Equalizer has — clamped to the range the device admits.
///
/// The clamp is where fidelity is lost first: a ±12 dB curve on hardware that admits ±10 dB comes
/// out flattened at the extremes, and nothing downstream can tell.
List<double> deviceBandGains({
  required List<EqBand> bands,
  required double preamp,
  required List<double> centreFrequencies,
  required double minDb,
  required double maxDb,
}) => [
  for (final db in eqCurveDb(bands, preamp, centreFrequencies))
    db.clamp(minDb, maxDb).toDouble(),
];

/// The bands of a stored config, defaulted for the fields the Hub leaves optional.
List<EqBand> bandsOf(EqConfig? config) {
  final bands = config?.bands;
  return bands == null || bands.isEmpty ? defaultEqBands : bands;
}

double preampOf(EqConfig? config) => config?.preamp ?? 0;

bool enabledOf(EqConfig? config) => config?.enabled ?? false;

/// The built-in preset a config corresponds to, or null when the listener has shaped their own.
BuiltInPreset? matchingPreset(EqConfig? config) {
  final bands = bandsOf(config);
  final preamp = preampOf(config);
  for (final preset in builtInPresets) {
    if (eqMatches(bands, preamp, preset.bands, preset.preamp)) return preset;
  }
  return null;
}

double _log10(double x) => math.log(x) / math.ln10;

/// Pushes a curve at the audio path.
typedef EqSink = Future<void> Function(EqConfig? config);

Future<void> _unapplied(EqConfig? config) async {}

/// Where an edited curve goes to be heard.
///
/// Defaults to doing nothing, and is overridden in `bootstrap` with the device equalizer's `apply`.
/// A seam rather than a direct reference to `AndroidEqualizerController` because that object has to
/// exist before the engine's players are constructed — just_audio accepts an `AudioPipeline` only at
/// construction — which is earlier than any screen, and because on a platform with no equalizer
/// effect the honest implementation of "apply" is this one.
final eqSinkProvider = Provider<EqSink>((ref) => _unapplied);

/// Whether the running platform can apply a curve at all.
///
/// Android can, approximately (see this file's header). Darwin has no equalizer behind just_audio's
/// pipeline, so the screen is a stored preference and nothing more until the native engine lands.
bool get eqAppliesHere =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
