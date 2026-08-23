import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/data/playback/eq.dart';
import 'package:flutter_test/flutter_test.dart';

/// A curve with one band boosted and the rest flat.
List<EqBand> onlyBand(double freq, double gain) => [
  for (final f in eqFreqs)
    EqBand(freq: f, gain: f == freq ? gain : 0, q: defaultQ),
];

void main() {
  group('the model matches the web client', () {
    test('ten ISO bands at the standard Q', () {
      expect(eqFreqs, [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]);
      expect(defaultEqBands.map((b) => b.q), everyElement(defaultQ));
      expect(defaultEqBands.map((b) => b.gain), everyElement(0));
    });

    test('every preset carries one gain per band', () {
      for (final preset in builtInPresets) {
        expect(
          preset.gains.length,
          eqFreqs.length,
          reason: '${preset.name} is not aligned to the band list',
        );
        expect(preset.bands.map((b) => b.freq).toList(), eqFreqs);
      }
    });

    test('the default config is the Flat preset', () {
      expect(matchingPreset(defaultEq)?.name, 'Flat');
      // A curve the listener shaped themselves is not any preset, and the picker has to be able to
      // say so rather than showing whichever preset it drifted nearest to.
      expect(
        matchingPreset(EqConfig(preamp: 0, bands: onlyBand(1000, 4))),
        isNull,
      );
    });

    test('a config the Hub left half-filled reads as the defaults', () {
      // Every field of `EqConfig` is optional on the wire, and a Hub that has never been told about
      // this account's EQ sends an object with nothing in it.
      const empty = EqConfig();
      expect(enabledOf(empty), isFalse);
      expect(preampOf(empty), 0);
      expect(bandsOf(empty).length, eqFreqs.length);
      expect(bandsOf(null).length, eqFreqs.length);
    });
  });

  group('the analytic response', () {
    test('a flat chain is transparent', () {
      final curve = eqCurveDb(defaultEqBands, 0, logFreqs(32));
      expect(curve, everyElement(closeTo(0, 1e-9)));
    });

    test('preamp offsets the whole curve', () {
      final curve = eqCurveDb(defaultEqBands, -3, logFreqs(16));
      expect(curve, everyElement(closeTo(-3, 1e-9)));
    });

    test('a peaking band hits its own gain at its own frequency', () {
      // The defining property of an RBJ peaking filter: at f0 the magnitude is exactly the gain it
      // was given. It is what makes evaluating the curve at a device band a meaningful answer.
      expect(
        peakingDb(f0: 1000, gainDb: 6, q: defaultQ, f: 1000),
        closeTo(6, 1e-9),
      );
      expect(
        peakingDb(f0: 1000, gainDb: -6, q: defaultQ, f: 1000),
        closeTo(-6, 1e-9),
      );
    });

    test('a band falls away either side of itself', () {
      final at1k = peakingDb(f0: 1000, gainDb: 8, q: defaultQ, f: 1000);
      final at500 = peakingDb(f0: 1000, gainDb: 8, q: defaultQ, f: 500);
      final at200 = peakingDb(f0: 1000, gainDb: 8, q: defaultQ, f: 200);
      expect(at500, lessThan(at1k));
      expect(at200, lessThan(at500));
      expect(at200, greaterThan(0));
    });

    test('the frequency axis is log-spaced across the audible band', () {
      final freqs = logFreqs(5, min: 20, max: 20000);
      expect(freqs.first, closeTo(20, 1e-6));
      expect(freqs.last, closeTo(20000, 1e-6));
      // Equal ratios, not equal differences: each step is the same multiple of the last.
      for (var i = 1; i < freqs.length - 1; i++) {
        expect(freqs[i + 1] / freqs[i], closeTo(freqs[i] / freqs[i - 1], 1e-9));
      }
    });
  });

  group('resampling onto the device equalizer', () {
    /// A five-band `android.media.audiofx.Equalizer`, which is what most phones report. None of
    /// these centres is one of ours — that is the whole problem this function exists for.
    const deviceCentres = [60.0, 230.0, 910.0, 3600.0, 14000.0];

    test('one gain per device band, in the device\'s order', () {
      final gains = deviceBandGains(
        bands: defaultEqBands,
        preamp: 0,
        centreFrequencies: deviceCentres,
        minDb: -15,
        maxDb: 15,
      );
      expect(gains.length, deviceCentres.length);
      expect(gains, everyElement(closeTo(0, 1e-9)));
    });

    test('a device band sitting on one of ours gets that band\'s gain', () {
      // The exact case: ask for +6 at 1 kHz and give the device a band at 1 kHz. Neighbouring
      // bands are flat, so nothing else contributes.
      final gains = deviceBandGains(
        bands: onlyBand(1000, 6),
        preamp: 0,
        centreFrequencies: const [1000],
        minDb: -15,
        maxDb: 15,
      );
      expect(gains.single, closeTo(6, 1e-9));
    });

    test('a device band between ours gets the response there, not a copy', () {
      final gains = deviceBandGains(
        bands: onlyBand(1000, 6),
        preamp: 0,
        centreFrequencies: deviceCentres,
        minDb: -15,
        maxDb: 15,
      );
      final at910 = gains[2];
      final at3600 = gains[3];
      // 910 Hz is close to the boost and gets most of it; 3.6 kHz is far enough up that the skirt
      // has nearly gone. Neither is 6 dB, and neither is 0: that is what interpolation means here.
      expect(at910, greaterThan(4));
      expect(at910, lessThan(6));
      expect(at3600, greaterThan(0));
      expect(at3600, lessThan(1.5));
    });

    test(
      'the preamp rides along, because the platform has no other place for it',
      () {
        final gains = deviceBandGains(
          bands: defaultEqBands,
          preamp: -4,
          centreFrequencies: deviceCentres,
          minDb: -15,
          maxDb: 15,
        );
        expect(gains, everyElement(closeTo(-4, 1e-9)));
      },
    );

    test('gains outside the device range are clamped, not wrapped', () {
      // Hardware that admits ±10 dB simply cannot render a +12 dB peak, and asking it to would
      // either throw or be silently ignored by the platform.
      final gains = deviceBandGains(
        bands: onlyBand(1000, 12),
        preamp: 6,
        centreFrequencies: const [1000, 60],
        minDb: -10,
        maxDb: 10,
      );
      expect(gains[0], 10);
      expect(gains[1], closeTo(6, 0.5));

      final cut = deviceBandGains(
        bands: onlyBand(1000, -12),
        preamp: -6,
        centreFrequencies: const [1000],
        minDb: -10,
        maxDb: 10,
      );
      expect(cut.single, -10);
    });

    test('a preset resamples to the shape it was drawn as', () {
      final bassBoost = builtInPresets.firstWhere(
        (p) => p.name == 'Bass Boost',
      );
      final gains = deviceBandGains(
        bands: bassBoost.bands,
        preamp: bassBoost.preamp,
        centreFrequencies: deviceCentres,
        minDb: -15,
        maxDb: 15,
      );
      // Bass lifted, treble left where the preamp put it: the curve survives the resample even
      // though not one device band lines up with one of ours.
      expect(gains[0], greaterThan(gains[2]));
      expect(gains[2], greaterThan(gains[4]));
      expect(gains[4], closeTo(bassBoost.preamp, 0.5));
    });
  });

  test('dB converts to a linear multiplier', () {
    expect(dbToGain(0), closeTo(1, 1e-9));
    expect(dbToGain(6), closeTo(1.99526, 1e-5));
    expect(dbToGain(-6), closeTo(0.50119, 1e-5));
  });
}
