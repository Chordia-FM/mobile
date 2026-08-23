import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/data/playback/adaptive.dart';
import 'package:chordia_player/chordia_player.dart';
import 'package:flutter_test/flutter_test.dart';

/// One scripted health reading.
///
/// Defaults describe a comfortable stream: playing, not starved, with ten seconds buffered — enough
/// that nothing is in trouble and not enough to count as headroom, so a trace only exercises the
/// rule it deliberately breaks.
QualitySample tick({
  bool playing = true,
  bool starving = false,
  double buffer = 10,
  double? delta,
  bool suspended = false,
  int seq = 1,
  int ms = 500,
}) => QualitySample(
  tick: Duration(milliseconds: ms),
  playing: playing,
  starving: starving,
  bufferSeconds: buffer,
  bufferDeltaSeconds: delta,
  suspended: suspended,
  seq: seq,
);

/// Feeds [count] identical samples and returns every profile change they caused.
List<QualityProfile> feed(
  AdaptiveQualityController controller,
  int count,
  QualitySample Function(int i) build,
) {
  final changes = <QualityProfile>[];
  for (var i = 0; i < count; i++) {
    final changed = controller.observe(build(i));
    if (changed != null) changes.add(changed);
  }
  return changes;
}

/// Gets a controller past its warm-up the honest way: by playing.
///
/// Ten half-second samples of untroubled playback is five seconds of audio, which is exactly
/// `warmupPlayedSeconds`. Nothing here is starving, so every one of them counts.
void warmUp(AdaptiveQualityController controller) {
  controller.observe(tick(seq: 0));
  feed(controller, 10, (i) => tick(seq: i + 1));
}

void main() {
  group('warm-up', () {
    test('a stall before anything has played does not downgrade', () {
      final controller = AdaptiveQualityController(
        selected: QualityProfile.original,
      );
      // Starving from the very first sample: nothing has played, so nothing has starved. The
      // stall streak is long past its threshold the whole way through.
      final changes = [
        controller.observe(tick(seq: 0, starving: true)),
        ...feed(controller, 38, (i) => tick(seq: i + 1, starving: true)),
      ].whereType<QualityProfile>().toList();

      expect(changes, isEmpty);
      expect(controller.profile, QualityProfile.original);
    });

    test('the elapsed cap eventually lets a hopeless source downgrade', () {
      final controller = AdaptiveQualityController(
        selected: QualityProfile.original,
      );
      // 40 half-second samples is 20 seconds on this source — `warmupElapsedSeconds` — and a source
      // that has produced no audio in twenty seconds must not be locked out of stepping down.
      controller.observe(tick(seq: 0, starving: true));
      final changes = feed(
        controller,
        39,
        (i) => tick(seq: i + 1, starving: true),
      );

      expect(changes, [QualityProfile.high]);
    });
  });

  group('downgrade on sustained starvation', () {
    test('three half-second stalls step down one rung', () {
      final controller = AdaptiveQualityController(
        selected: QualityProfile.original,
      );
      warmUp(controller);

      expect(controller.observe(tick(starving: true)), isNull, reason: '0.5s');
      expect(controller.observe(tick(starving: true)), isNull, reason: '1.0s');
      expect(controller.observe(tick(starving: true)), QualityProfile.high);
      expect(controller.downgraded, isTrue);
      expect(controller.selected, QualityProfile.original);
    });

    test('a single dip is not evidence of anything', () {
      final controller = AdaptiveQualityController(
        selected: QualityProfile.original,
      );
      warmUp(controller);

      expect(controller.observe(tick(starving: true)), isNull);
      // Recovered on the very next sample: the streak lapses rather than banking.
      expect(controller.observe(tick()), isNull);
      expect(controller.observe(tick(starving: true)), isNull);
      expect(controller.observe(tick()), isNull);
      expect(controller.profile, QualityProfile.original);
    });

    test('the threshold is a duration, not a count of ticks', () {
      final controller = AdaptiveQualityController(
        selected: QualityProfile.original,
      );
      controller.observe(tick(seq: 0, ms: 1000));
      feed(controller, 5, (i) => tick(seq: i + 1, ms: 1000));

      // At a one-second cadence the same 1.5 seconds of stalling is reached in two samples, not
      // three. An engine that changed its tick rate must not retune the controller with it.
      expect(controller.observe(tick(starving: true, ms: 1000)), isNull);
      expect(
        controller.observe(tick(starving: true, ms: 1000)),
        QualityProfile.high,
      );
    });

    test('one step at a time, however bad the patch', () {
      final controller = AdaptiveQualityController(
        selected: QualityProfile.original,
      );
      warmUp(controller);
      // Twelve consecutive stalled samples is four times the down threshold. The swap resets the
      // evidence, so the ladder cannot cascade inside one bad second — and the fresh source has to
      // earn its own warm-up before it can be judged.
      final changes = feed(controller, 12, (_) => tick(starving: true));

      expect(changes, [QualityProfile.high]);
    });
  });

  group('downgrade on a measured drain', () {
    /// Buffer under `lowBufferSeconds`, shrinking at 0.2 s/s — twice `drainRate`.
    QualitySample draining() => tick(buffer: 2, delta: -0.1);

    test('six half-second samples of draining step down', () {
      final controller = AdaptiveQualityController(
        selected: QualityProfile.original,
      );
      warmUp(controller);

      final changes = feed(controller, 6, (_) => draining());
      expect(changes, [QualityProfile.high]);
    });

    test('a low buffer that is not shrinking is not a drain', () {
      final controller = AdaptiveQualityController(
        selected: QualityProfile.original,
      );
      warmUp(controller);

      // The rule the web client had to delete: a small buffered-ahead figure on its own. Ten
      // seconds of it, and nothing happens.
      final changes = feed(controller, 20, (_) => tick(buffer: 1, delta: 0.05));
      expect(changes, isEmpty);
    });

    test('shrinkage below the rate threshold is jitter', () {
      final controller = AdaptiveQualityController(
        selected: QualityProfile.original,
      );
      warmUp(controller);

      // −0.02s per 0.5s tick is −0.04 s/s, well under `drainRate`.
      final changes = feed(
        controller,
        20,
        (_) => tick(buffer: 2, delta: -0.02),
      );
      expect(changes, isEmpty);
    });

    test('a drain with a healthy buffer is the engine reading ahead', () {
      final controller = AdaptiveQualityController(
        selected: QualityProfile.original,
      );
      warmUp(controller);

      // Draining hard, but from thirty seconds of buffer: that is the engine spending what it
      // fetched, not the link failing to keep up.
      final changes = feed(
        controller,
        20,
        (_) => tick(buffer: 30, delta: -0.5),
      );
      expect(changes, isEmpty);
    });
  });

  group('recovery', () {
    /// A controller already downgraded one rung by a real stall.
    AdaptiveQualityController downgraded() {
      final controller = AdaptiveQualityController(
        selected: QualityProfile.original,
      );
      warmUp(controller);
      feed(controller, 3, (_) => tick(starving: true));
      expect(controller.profile, QualityProfile.high);
      return controller;
    }

    test('sustained headroom climbs one rung back', () {
      final controller = downgraded();

      expect(controller.observe(tick(buffer: 25, seq: 0)), isNull);
      expect(controller.observe(tick(buffer: 25)), isNull);
      expect(controller.observe(tick(buffer: 25)), isNull);
      expect(controller.observe(tick(buffer: 25)), isNull);
      expect(controller.observe(tick(buffer: 25)), isNull);
      expect(controller.observe(tick(buffer: 25)), QualityProfile.original);
      expect(controller.downgraded, isFalse);
    });

    test('headroom has to be continuous, not accumulated', () {
      final controller = downgraded();
      for (var i = 0; i < 20; i++) {
        // Two comfortable samples, then one merely adequate one, forever. The streak never lasts
        // the three seconds a recovery costs.
        controller.observe(tick(buffer: 25));
        controller.observe(tick(buffer: 25));
        expect(controller.observe(tick(buffer: 8)), isNull);
      }
      expect(controller.profile, QualityProfile.high);
    });

    test('recovery stops at the ceiling', () {
      final controller = downgraded();
      final changes = feed(controller, 60, (_) => tick(buffer: 25));
      // One rung back to the listener's tier and no further, however long the connection behaves.
      expect(changes, [QualityProfile.original]);
    });

    test('a suspended fetch counts as headroom on its own', () {
      final controller = downgraded();
      // A low seconds figure while the engine has stopped fetching says the engine is not
      // bandwidth-limited. Reading it as trouble is what pinned a lossless stream at the bottom
      // rung on the web.
      final changes = feed(
        controller,
        6,
        (_) => tick(buffer: 1, suspended: true),
      );
      expect(changes, [QualityProfile.original]);
    });

    test('a stall while suspended cannot downgrade', () {
      final controller = AdaptiveQualityController(
        selected: QualityProfile.original,
      );
      warmUp(controller);
      final changes = feed(
        controller,
        20,
        (_) => tick(starving: true, suspended: true),
      );
      expect(changes, isEmpty);
    });
  });

  group('the ceiling and the listener', () {
    test('pausing lets every streak lapse', () {
      final controller = AdaptiveQualityController(
        selected: QualityProfile.original,
      );
      warmUp(controller);
      controller.observe(tick(starving: true));
      controller.observe(tick(starving: true));
      // Paused: `starving` means nothing, and banking the two samples above would downgrade on the
      // first sample after the listener presses play again.
      controller.observe(tick(playing: false, starving: true));
      expect(controller.observe(tick(starving: true)), isNull);
      expect(controller.observe(tick(starving: true)), isNull);
      expect(controller.observe(tick(starving: true)), QualityProfile.high);
    });

    test('a new series drops the evidence of the last one', () {
      final controller = AdaptiveQualityController(
        selected: QualityProfile.original,
      );
      warmUp(controller);
      controller.observe(tick(starving: true));
      controller.observe(tick(starving: true));
      // seq 0 is a different stream, or a different region of this one. Two thirds of a downgrade
      // must not carry into it.
      expect(controller.observe(tick(seq: 0, starving: true)), isNull);
      expect(controller.profile, QualityProfile.original);
    });

    test('restore puts the listener back on their tier at once', () {
      final controller = AdaptiveQualityController(
        selected: QualityProfile.original,
      );
      warmUp(controller);
      feed(controller, 3, (_) => tick(starving: true));

      expect(controller.restore(), QualityProfile.original);
      expect(controller.downgraded, isFalse);
      // Restoring clears the streaks too, so the rule that demoted them does not re-trip on the
      // very next sample.
      expect(controller.observe(tick(starving: true)), isNull);
      expect(controller.observe(tick(starving: true)), isNull);
    });

    test('restore on an undiverged stream changes nothing', () {
      final controller = AdaptiveQualityController(
        selected: QualityProfile.high,
      );
      expect(controller.restore(), isNull);
      expect(controller.profile, QualityProfile.high);
    });

    test('a lower ceiling clamps the active stream immediately', () {
      final controller = AdaptiveQualityController(
        selected: QualityProfile.original,
      );
      expect(
        controller.setCeiling(QualityProfile.normal),
        QualityProfile.normal,
      );
      expect(controller.profile, QualityProfile.normal);
      expect(controller.downgraded, isFalse);
    });

    test('a higher ceiling takes effect now rather than one rung at a time', () {
      // Starting at `high` — a metered link's cap — so that lifting the ceiling is a real move.
      // Re-selecting the ceiling you already have is deliberately a no-op here; that is what
      // `restore` is for, and the test above covers it.
      final controller = AdaptiveQualityController(
        selected: QualityProfile.high,
      );
      warmUp(controller);
      feed(controller, 3, (_) => tick(starving: true));
      expect(controller.profile, QualityProfile.normal);

      // Walking onto Wi-Fi: waiting three seconds a rung while the UI says "the connection can't
      // keep up" reads as the setting being ignored.
      expect(
        controller.setCeiling(QualityProfile.original),
        QualityProfile.original,
      );
      expect(controller.downgraded, isFalse);
    });

    test('auto-downgrade off means the controller only ever reports', () {
      final controller = AdaptiveQualityController(
        selected: QualityProfile.original,
        autoDowngrade: false,
      );
      warmUp(controller);
      expect(feed(controller, 60, (_) => tick(starving: true)), isEmpty);
      expect(controller.profile, QualityProfile.original);
    });
  });

  group('the health sampler', () {
    EngineHealth health(double bufferedSeconds, {bool stalled = false}) =>
        EngineHealth(
          stalled: stalled,
          bufferedAhead: Duration(
            milliseconds: (bufferedSeconds * 1000).round(),
          ),
          tick: const Duration(milliseconds: 500),
        );

    test('the first sample of a series has no trend to report', () {
      final sampler = HealthSampler();
      final first = sampler.sample(health(4), playing: true);
      expect(first.seq, 0);
      expect(first.bufferDeltaSeconds, isNull);

      final second = sampler.sample(health(3.5), playing: true);
      expect(second.seq, 1);
      expect(second.bufferDeltaSeconds, closeTo(-0.5, 1e-6));
    });

    test('a restart withdraws the trend as well as the counter', () {
      final sampler = HealthSampler();
      sampler.sample(health(4), playing: true);
      sampler.sample(health(3), playing: true);
      sampler.restart();

      // Comparing across a swap would report the whole difference between two streams' fill levels
      // as a drain the new one is responsible for.
      final after = sampler.sample(health(1), playing: true);
      expect(after.seq, 0);
      expect(after.bufferDeltaSeconds, isNull);
    });

    test('a stalled engine is a starving sample', () {
      final sampler = HealthSampler();
      expect(
        sampler.sample(health(0, stalled: true), playing: true).starving,
        isTrue,
      );
    });
  });

  group('the divergence a listener is shown', () {
    const wifi = QualityStatus(
      chosen: QualityProfile.original,
      ceiling: QualityProfile.original,
      playing: QualityProfile.original,
      fixed: false,
    );

    test('nothing to explain when the chosen tier is what is playing', () {
      expect(wifi.limit, QualityLimit.none);
      expect(wifi.restorable, isFalse);
    });

    test('a metered link is named as the network limit', () {
      const status = QualityStatus(
        chosen: QualityProfile.original,
        ceiling: QualityProfile.high,
        playing: QualityProfile.high,
        fixed: false,
      );
      expect(status.limit, QualityLimit.network);
      // Not restorable: nothing to undo. The cap is the network's, and pretending a button could
      // lift it would be a promise the connection has to keep.
      expect(status.restorable, isFalse);
    });

    test('a stream below the ceiling is named as the adaptive one', () {
      const status = QualityStatus(
        chosen: QualityProfile.original,
        ceiling: QualityProfile.high,
        playing: QualityProfile.dataSaver,
        fixed: false,
      );
      expect(status.limit, QualityLimit.adaptive);
      expect(status.restorable, isTrue);
    });

    test('a local copy is explained by the file, not by the connection', () {
      const status = QualityStatus(
        chosen: QualityProfile.original,
        ceiling: QualityProfile.original,
        playing: QualityProfile.normal,
        fixed: true,
      );
      expect(status.limit, QualityLimit.none);
      expect(status.restorable, isFalse);
    });
  });
}
