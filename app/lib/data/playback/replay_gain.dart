import 'dart:math' as math;

/// The linear multiplier to apply for a track's measured loudness.
///
/// ReplayGain 2.0 states the correction in dB against a −18 LUFS reference, so the multiplier is
/// `10^(gain/20)`. The second term is the standard clip guard: a track mastered quiet gets a
/// positive gain, and applying it in full would push its true peak past full scale and clip. Since
/// `peak` is the measured true-peak amplitude, `1/peak` is the largest multiplier that still fits,
/// and the smaller of the two wins.
///
/// Returns 1 — unity, i.e. no correction — whenever the loudness pass has not produced a figure.
/// That is the same answer as "normalisation is off", and deliberately so: a track with no
/// measurement must sound exactly as it does with the feature disabled, never louder or quieter
/// than its neighbours by accident.
double replayGainMultiplier({double? gainDb, double? peak}) {
  if (gainDb == null || !gainDb.isFinite) return 1;
  final gain = math.pow(10, gainDb / 20).toDouble();
  if (peak == null || !peak.isFinite || peak <= 0) return gain;
  return math.min(gain, 1 / peak);
}
