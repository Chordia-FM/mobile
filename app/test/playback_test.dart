import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_db/chordia_db.dart';
import 'package:chordia_mobile/data/playback/notification_art.dart';
import 'package:chordia_mobile/data/playback/playback_service.dart';
import 'package:chordia_mobile/data/playback/quality.dart';
import 'package:chordia_mobile/data/playback/replay_gain.dart';
import 'package:chordia_mobile/data/playback/source_resolver.dart';
import 'package:chordia_player/chordia_player.dart';
import 'package:chordia_sync/chordia_sync.dart' hide PlaybackState;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('network class', () {
    test('cellular alone is metered; an unmetered link alongside it is not', () {
      expect(NetworkStatus.from([ConnectivityResult.mobile]).metered, isTrue);
      // Android keeps cellular up while Wi-Fi associates. Treating that overlap as metered would
      // cap the tier for the seconds either side of every walk through a front door.
      expect(
        NetworkStatus.from([
          ConnectivityResult.mobile,
          ConnectivityResult.wifi,
        ]).metered,
        isFalse,
      );
      expect(
        NetworkStatus.from([ConnectivityResult.none]),
        NetworkStatus.offline,
      );
      // Nothing reported at all is not evidence of anything, and guessing "offline" would refuse
      // to stream on a device that is perfectly connected.
      expect(NetworkStatus.from(const []), NetworkStatus.unknown);
    });
  });

  group('quality ceiling', () {
    const cellular = NetworkStatus(online: true, metered: true);
    const wifi = NetworkStatus(online: true, metered: false);

    test('a metered link caps lossless at the top lossy tier', () {
      expect(
        effectiveQuality(chosen: QualityProfile.original, network: cellular),
        QualityProfile.high,
      );
    });

    test('a metered link never raises a tier the listener already lowered', () {
      // The ceiling only ever lowers. Someone who chose data saver on Wi-Fi and walked outside
      // must not find themselves streaming at `high` because a rule "corrected" them upward.
      expect(
        effectiveQuality(chosen: QualityProfile.dataSaver, network: cellular),
        QualityProfile.dataSaver,
      );
      expect(
        effectiveQuality(chosen: QualityProfile.normal, network: cellular),
        QualityProfile.normal,
      );
    });

    test('an unmetered link returns the chosen tier untouched', () {
      for (final chosen in qualityLadder) {
        expect(effectiveQuality(chosen: chosen, network: wifi), chosen);
      }
    });
  });

  group('ReplayGain', () {
    test('a gain in dB becomes its linear multiplier', () {
      // −6 dB is very nearly half amplitude; +6 dB very nearly double.
      expect(replayGainMultiplier(gainDb: 0), closeTo(1, 1e-9));
      expect(replayGainMultiplier(gainDb: -6), closeTo(0.50119, 1e-5));
      expect(replayGainMultiplier(gainDb: 6), closeTo(1.99526, 1e-5));
    });

    test('the peak clamps a positive gain so the track cannot clip', () {
      // +6 dB asks for 1.995x, but a track already peaking at 0.9 has only 1.111x of headroom.
      // Applying the full correction would push it past full scale, which is audible distortion —
      // the whole reason the loudness pass records a peak at all.
      expect(
        replayGainMultiplier(gainDb: 6, peak: 0.9),
        closeTo(1 / 0.9, 1e-9),
      );
      // Below the clamp the gain stands on its own.
      expect(
        replayGainMultiplier(gainDb: 6, peak: 0.2),
        closeTo(1.99526, 1e-5),
      );
      // Attenuation can never clip, so a peak must not be able to raise it.
      expect(
        replayGainMultiplier(gainDb: -6, peak: 0.9),
        closeTo(0.50119, 1e-5),
      );
    });

    test('an unmeasured track plays at unity', () {
      expect(replayGainMultiplier(), 1);
      expect(replayGainMultiplier(peak: 0.5), 1);
      // A nonsense peak is ignored rather than turned into a division by zero or an infinity.
      expect(replayGainMultiplier(gainDb: -6, peak: 0), closeTo(0.50119, 1e-5));
      expect(replayGainMultiplier(gainDb: double.nan), 1);
    });
  });

  group('source resolution', () {
    final track = _track();

    test('a downloaded copy wins over the network, at the profile on disk', () {
      final resolver = SourceResolver(
        downloads: (id) async => _download(id, profile: 'high'),
        // A quality closure that would fail the test if it were consulted: a local file's tier is
        // whatever was fetched, and asking the network what to stream at is a question that should
        // not arise.
        quality: () => fail('the network tier was consulted for a local file'),
        probe: (_) => true,
      );

      final source = resolver(track);
      expect(
        source,
        completion(
          isA<DownloadedSource>()
              .having((s) => s.filePath, 'filePath', '/music/track-1.flac')
              .having((s) => s.profile, 'profile', QualityProfile.high),
        ),
      );
    });

    test(
      'a download row whose file is gone falls through to streaming',
      () async {
        var probed = '';
        final resolver = SourceResolver(
          downloads: (id) async => _download(id),
          quality: () => QualityProfile.normal,
          probe: (path) {
            probed = path;
            return false;
          },
        );

        final source = await resolver(track);
        expect(probed, '/music/track-1.flac');
        expect(source, isA<StreamedSource>());
        expect((source as StreamedSource).profile, QualityProfile.normal);
      },
    );

    test('with no download it streams at the effective tier', () async {
      final resolver = SourceResolver(
        downloads: (_) async => null,
        quality: () => QualityProfile.dataSaver,
      );

      final source = await resolver(track);
      expect(
        source,
        isA<StreamedSource>()
            .having((s) => s.libraryId, 'libraryId', 'lib-1')
            .having((s) => s.trackRef, 'trackRef', 'ref-1')
            .having((s) => s.contentHash, 'contentHash', 'sha-1')
            .having((s) => s.profile, 'profile', QualityProfile.dataSaver),
      );
    });
  });

  group('notification art', () {
    test('only a Hub image path yields a hash', () {
      final hash = 'a' * 64;
      expect(artHashOf('/v1/images/$hash'), hash);
      expect(artHashOf('https://hub.example/v1/images/$hash'), hash);
      expect(artHashOf('/v1/images/not-a-hash'), isNull);
      expect(artHashOf(null), isNull);
      expect(artHashOf(''), isNull);
    });
  });

  group('scrobbles', () {
    test('crossing the listening threshold records one play and flushes', () async {
      final engine = _FakeEngine();
      final queue = QueueController(newQid: () => 'qid-1');
      final recorder = _RecordedPlays();
      final service = _service(engine: engine, queue: queue, plays: recorder);
      service.start();

      final track = _track(durationMs: 120000);
      queue.playQueue([track], context: const AlbumContext(id: 'a', name: 'A'));
      // The handler resolves the source and loads it; let that settle before sampling.
      await pumpEventQueue();

      // Half of two minutes is the threshold, so a minute of playhead earns exactly one scrobble.
      for (var ms = 1000; ms <= 61000; ms += 1000) {
        engine.emit(Duration(milliseconds: ms));
      }
      await pumpEventQueue();

      expect(recorder.plays, hasLength(1));
      final play = recorder.plays.single;
      expect(play.track.id, track.id);
      expect(play.msPlayed, greaterThanOrEqualTo(60000));
      // The context travels with the play: `listening_events.playlist_id` is append-only, so a
      // play attributed to nothing can never be attributed later.
      expect(play.context, const AlbumContext(id: 'a', name: 'A'));
      // Recorded first, then delivery attempted — never the other way round.
      expect(recorder.flushes, greaterThanOrEqualTo(1));

      // Past the threshold the latch is spent: further samples must not bill a second play.
      for (var ms = 62000; ms <= 90000; ms += 1000) {
        engine.emit(Duration(milliseconds: ms));
      }
      await pumpEventQueue();
      expect(recorder.plays, hasLength(1));

      await service.dispose();
      await queue.dispose();
    });

    test('a listener with scrobbling off records nothing', () async {
      final engine = _FakeEngine();
      final queue = QueueController(newQid: () => 'qid-1');
      final recorder = _RecordedPlays();
      final service = _service(
        engine: engine,
        queue: queue,
        plays: recorder,
        preferences: const PlaybackPreferences(scrobble: false),
      );
      service.start();

      queue.playQueue([_track(durationMs: 120000)]);
      await pumpEventQueue();
      for (var ms = 1000; ms <= 90000; ms += 1000) {
        engine.emit(Duration(milliseconds: ms));
      }
      await pumpEventQueue();

      expect(recorder.plays, isEmpty);

      await service.dispose();
      await queue.dispose();
    });

    test('starting a track resets the gain and reports now-playing', () async {
      final engine = _FakeEngine();
      final queue = QueueController(newQid: () => 'qid-1');
      final reported = <PlayerTrack>[];
      final service = _service(
        engine: engine,
        queue: queue,
        plays: _RecordedPlays(),
        reportNowPlaying: reported.add,
        loudness: const AudioProperties(
          bitDepth: 16,
          channels: 2,
          codec: 'flac',
          lossless: true,
          sampleRateHz: 44100,
          spatial: false,
          gainDb: -6,
          peak: 0.9,
        ),
        preferences: const PlaybackPreferences(normalizeVolume: true),
      );
      service.start();

      queue.playQueue([_track()]);
      await pumpEventQueue();
      await pumpEventQueue();

      expect(reported, hasLength(1));
      // Unity first, then the measured correction — never the other way round, or the previous
      // track's gain would carry into this one for as long as the lookup takes.
      expect(engine.preamps.first, 1);
      expect(engine.preamps.last, closeTo(0.50119, 1e-5));

      await service.dispose();
      await queue.dispose();
    });
  });
}

// ── fixtures ────────────────────────────────────────────────────────────────────────────────────

PlayerTrack _track({int durationMs = 180000}) => PlayerTrack(
  id: 'track-1',
  title: 'Song',
  artist: 'Artist',
  album: 'Album',
  durationMs: durationMs,
  libraryId: 'lib-1',
  trackRef: 'ref-1',
  contentHash: 'sha-1',
);

DownloadedTrack _download(String trackId, {String profile = 'original'}) =>
    DownloadedTrack(
      trackId: trackId,
      libraryId: 'lib-1',
      trackRef: 'ref-1',
      contentHash: 'sha-1',
      profile: profile,
      filePath: '/music/track-1.flac',
      sizeBytes: 1000,
      savedAt: 0,
      title: 'Song',
      artist: 'Artist',
      durationMs: 180000,
    );

/// One recorded play, kept as data so a test can assert on what the pipeline was handed.
class _Play {
  _Play(this.track, this.startedAt, this.msPlayed, this.context, this.source);

  final PlayerTrack track;
  final int startedAt;
  final int msPlayed;
  final PlayContext? context;
  final PlaybackSource source;
}

class _RecordedPlays {
  final List<_Play> plays = [];
  int flushes = 0;

  Future<void> record(
    PlayerTrack track, {
    required int startedAt,
    required int msPlayed,
    PlayContext? context,
    PlaybackSource source = PlaybackSource.ownLibrary,
  }) async {
    plays.add(_Play(track, startedAt, msPlayed, context, source));
  }

  Future<void> flush({bool force = false}) async => flushes++;
}

PlaybackService _service({
  required _FakeEngine engine,
  required QueueController queue,
  required _RecordedPlays plays,
  void Function(PlayerTrack)? reportNowPlaying,
  AudioProperties? loudness,
  PlaybackPreferences preferences = const PlaybackPreferences(),
}) {
  // The handler's sinks name the service, and the service names the handler. Production closes the
  // same loop through the provider container reading one lazily; here a late local does it.
  late final PlaybackService service;
  final handler = ChordiaAudioHandler(
    engine: engine,
    controller: queue,
    resolveArt: (_) async => null,
    onScrobble: (track, msPlayed) => service.onScrobble(track, msPlayed),
    onNowPlaying: (track) => service.onTrackStarted(track),
  );
  service = PlaybackService(
    handler: handler,
    engine: engine,
    queue: queue,
    resolver: SourceResolver(
      downloads: (_) async => null,
      quality: () => preferences.quality,
    ),
    recordPlay: plays.record,
    flush: plays.flush,
    reportNowPlaying: reportNowPlaying ?? (_) {},
    readLoudness: (_) async => loudness,
    preferences: () => preferences,
    network: () => NetworkStatus.unknown,
  );
  return service;
}

/// A [PlaybackEngine] that sounds nothing and reports exactly what a test tells it to.
class _FakeEngine implements PlaybackEngine {
  final _positions = StreamController<EnginePosition>.broadcast(sync: true);
  final _states = StreamController<EngineState>.broadcast(sync: true);
  final _health = StreamController<EngineHealth>.broadcast(sync: true);
  final _completions = StreamController<void>.broadcast(sync: true);

  /// Every preamp value the service has asked for, in order.
  final List<double> preamps = [];

  EngineSource? loaded;

  void emit(Duration position) => _positions.add(
    EnginePosition(
      position: position,
      buffered: position + const Duration(seconds: 10),
      duration: null,
      tick: const Duration(seconds: 1),
    ),
  );

  @override
  Future<void> load(
    EngineSource source, {
    Duration initialPosition = Duration.zero,
    bool autoPlay = false,
  }) async => loaded = source;

  @override
  Future<void> setPreampGain(double linear) async => preamps.add(linear);

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setUpcoming(List<EngineSource> sources) async {}
  @override
  Future<void> swapSource(EngineSource source) async {}
  @override
  Future<void> crossfadeTo(EngineSource source, Duration fade) async {}
  @override
  Future<void> setEq(EqConfig? config) async {}
  @override
  Stream<EnginePosition> get positions => _positions.stream;
  @override
  Stream<EngineState> get states => _states.stream;
  @override
  Stream<EngineHealth> get health => _health.stream;
  @override
  Stream<void> get completions => _completions.stream;
  @override
  Future<void> dispose() async {
    await _positions.close();
    await _states.close();
    await _health.close();
    await _completions.close();
  }
}
