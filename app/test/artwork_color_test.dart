import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/providers.dart';
import 'package:chordia_mobile/data/accent/artwork_color.dart';
import 'package:chordia_mobile/data/accent/oklab.dart';
import 'package:chordia_mobile/data/art/art_cache.dart';
import 'package:chordia_mobile/data/playback/current_cover.dart';
import 'package:chordia_mobile/data/playback/notification_art.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _redHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _blueHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// A sleeve: `count` pixels of each colour, as the RGBA bytes a decoder hands back.
Uint8List _pixels(List<(int r, int g, int b, int count)> blocks) {
  final out = BytesBuilder();
  for (final (r, g, b, count) in blocks) {
    for (var i = 0; i < count; i++) {
      out.add([r, g, b, 255]);
    }
  }
  return out.toBytes();
}

void main() {
  // The decode goes through `dart:ui`, which needs the engine the test binding brings up.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('picking a colour', () {
    test('a cover with one strong colour yields that colour', () {
      // Deliberately mostly background: a real sleeve is, and the mean of every pixel here is a
      // dark muddy brown rather than anything a person would call the colour of this cover.
      final colour = pickArtworkAccent(
        _pixels([
          (10, 8, 14, 700), // near-black background
          (214, 36, 48, 300), // the lettering
        ]),
      );

      expect(colour, isNotNull);
      final (_, chroma, hue) = oklchOf(colour!);
      final (_, _, sourceHue) = oklchOf(const Color.fromARGB(255, 214, 36, 48));
      expect(
        _hueGap(hue, sourceHue),
        lessThan(8),
        reason: 'the red lettering is what the cover reads as',
      );
      expect(chroma, greaterThan(0.1), reason: 'and it reads as a colour');
    });

    test('the answer is dragged into the band an accent has to live in', () {
      // Every pixel of this one is far too dark to use as `--primary` directly, but it is a real
      // colour and the mode should still produce one.
      final colour = pickArtworkAccent(_pixels([(70, 12, 90, 1000)]));

      expect(colour, isNotNull);
      final (lightness, chroma, _) = oklchOf(colour!);
      expect(lightness, greaterThanOrEqualTo(artworkMinLightness - 0.01));
      expect(lightness, lessThanOrEqualTo(artworkMaxLightness + 0.01));
      expect(chroma, lessThanOrEqualTo(artworkMaxChroma + 0.01));
    });

    test('a near-black cover falls back rather than returning mud', () {
      expect(
        pickArtworkAccent(_pixels([(4, 4, 6, 900), (12, 9, 15, 100)])),
        isNull,
      );
    });

    test('a greyscale cover falls back rather than returning mud', () {
      // The trap this guards: every one of these pixels is inside the lightness band and carries a
      // chroma of about 1e-17 rather than exactly zero, so a `weight <= 0` test never fires and the
      // weighted mean comes back as a mid-grey that would be painted as the accent.
      expect(
        pickArtworkAccent(
          _pixels([
            (60, 60, 60, 300),
            (128, 128, 128, 400),
            (200, 200, 200, 300),
          ]),
        ),
        isNull,
      );
    });

    test('transparent pixels do not vote', () {
      final rgba = Uint8List.fromList([
        ...[214, 36, 48, 0], // a red the sleeve does not actually show
        ...[60, 60, 60, 255],
      ]);
      expect(pickArtworkAccent(rgba), isNull);
    });
  });

  group('decoding a cover off disk', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('chordia_artwork');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('a real image file yields its dominant colour', () async {
      final file = File('${temp.path}/cover.png');
      await file.writeAsBytes(
        _png(32, 32, (x, y) => y < 22 ? (10, 8, 14) : (214, 36, 48)),
      );

      final colour = await accentFromArtworkFile(file.path);

      expect(colour, isNotNull);
      final (_, _, hue) = oklchOf(colour!);
      final (_, _, sourceHue) = oklchOf(const Color.fromARGB(255, 214, 36, 48));
      expect(_hueGap(hue, sourceHue), lessThan(10));
    });

    test('a file that is not an image is no colour, not a crash', () async {
      final file = File('${temp.path}/not-an-image');
      await file.writeAsBytes(Uint8List.fromList(List.filled(64, 7)));
      expect(await accentFromArtworkFile(file.path), isNull);
    });

    test('a missing file is no colour, not a crash', () async {
      expect(await accentFromArtworkFile('${temp.path}/gone.png'), isNull);
    });
  });

  group('following the player', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('chordia_artwork');
    });

    tearDown(() async {
      // Best-effort: on Windows a decode still holding the file makes this throw, and a cleanup
      // failure must not be reported as a test failure.
      try {
        if (await temp.exists()) await temp.delete(recursive: true);
      } on FileSystemException {
        // Left for the OS to reap.
      }
    });

    /// A container wired to fake covers, a fake mode, and an analyser that counts its calls and
    /// answers by hash — so a test can assert on how many analyses happened, which is the property
    /// that matters and the one an image decoder would hide.
    Future<({ProviderContainer container, List<String> analysed})> build({
      AccentMode? mode = AccentMode.artwork,
    }) async {
      final analysed = <String>[];
      final cache = ArtCache(
        directory: Future.value(temp),
        fetch: (sha, width) async => Uint8List.fromList(List.filled(16, 7)),
      );
      // Both covers land on disk before the accent ever asks for one, which is also the order the
      // app runs in: the media session fetches the playing cover for the lock screen first. It is
      // what keeps these tests off the clock — the art cache then answers without touching the
      // disk, so a pumped event queue is enough to settle them.
      for (final hash in [_redHash, _blueHash]) {
        await cache.file(hash, width: kNotificationArtWidth);
      }

      final container = ProviderContainer(
        overrides: [
          _modeProvider.overrideWith(() => _Mode(mode)),
          userSettingsProvider.overrideWith(
            (ref) => _settings(ref.watch(_modeProvider)),
          ),
          currentCoverHashProvider.overrideWith(
            (ref) => ref.watch(_coverProvider),
          ),
          artCacheProvider.overrideWithValue(cache),
          artworkAnalyserProvider.overrideWithValue((path) async {
            final hash = path.split(RegExp(r'[\\/]')).last.split('-').first;
            analysed.add(hash);
            return hash == _redHash
                ? const Color.fromARGB(255, 214, 36, 48)
                : const Color.fromARGB(255, 40, 90, 220);
          }),
        ],
      );
      addTearDown(container.dispose);
      container.listen(artworkAccentProvider, (_, _) {});
      return (container: container, analysed: analysed);
    }

    test('the accent follows the playing cover', () async {
      final built = await build();
      final container = built.container;
      final analysed = built.analysed;

      container.read(_coverProvider.notifier).show(_redHash);
      await _settle(container);

      expect(analysed, [_redHash]);
      expect(container.read(artworkAccentProvider), isNotNull);
      final (_, _, hue) = oklchOf(container.read(artworkAccentProvider)!);
      final (_, _, red) = oklchOf(const Color.fromARGB(255, 214, 36, 48));
      expect(_hueGap(hue, red), lessThan(1));
    });

    test('the same cover is never analysed twice', () async {
      final built = await build();
      final container = built.container;
      final analysed = built.analysed;

      container.read(_coverProvider.notifier).show(_redHash);
      await _settle(container);
      container.read(_coverProvider.notifier).show(_blueHash);
      await _settle(container);
      container.read(_coverProvider.notifier).show(_redHash);
      await _settle(container);

      expect(analysed, [_redHash, _blueHash]);
      // And the remembered answer is applied, not merely skipped.
      final (_, _, hue) = oklchOf(container.read(artworkAccentProvider)!);
      final (_, _, red) = oklchOf(const Color.fromARGB(255, 214, 36, 48));
      expect(_hueGap(hue, red), lessThan(1));
    });

    test('nothing is analysed outside artwork mode', () async {
      final built = await build(mode: AccentMode.fade);
      final container = built.container;
      final analysed = built.analysed;

      container.read(_coverProvider.notifier).show(_redHash);
      await _settle(container);

      expect(analysed, isEmpty);
      expect(container.read(artworkAccentProvider), isNull);
    });

    test('nothing is analysed before any settings have loaded', () async {
      final built = await build(mode: null);
      final container = built.container;
      final analysed = built.analysed;

      container.read(_coverProvider.notifier).show(_redHash);
      await _settle(container);

      expect(analysed, isEmpty);
      expect(container.read(artworkAccentProvider), isNull);
    });

    test(
      'switching into artwork mode extracts the cover already playing',
      () async {
        // The player only reports on change, and the next change can be three minutes away — so a
        // mode that only listened to the player would look broken for the length of a track.
        final built = await build(mode: AccentMode.staticValue);
        final container = built.container;
        final analysed = built.analysed;

        container.read(_coverProvider.notifier).show(_redHash);
        await _settle(container);
        expect(analysed, isEmpty);

        container.read(_modeProvider.notifier).use(AccentMode.artwork);
        await _settle(container);

        expect(analysed, [_redHash]);
        expect(container.read(artworkAccentProvider), isNotNull);
      },
    );

    test('leaving artwork mode drops the colour', () async {
      final container = (await build()).container;

      container.read(_coverProvider.notifier).show(_redHash);
      await _settle(container);
      expect(container.read(artworkAccentProvider), isNotNull);

      container.read(_modeProvider.notifier).use(AccentMode.chroma);
      await _settle(container);

      expect(container.read(artworkAccentProvider), isNull);
    });

    test('a cover with no art is no colour', () async {
      final container = (await build()).container;

      container.read(_coverProvider.notifier).show(_redHash);
      await _settle(container);
      container.read(_coverProvider.notifier).show(null);
      await _settle(container);

      expect(container.read(artworkAccentProvider), isNull);
    });
  });
}

/// Lets the accent catch up with a change to the cover or the mode.
///
/// The read is what makes this work rather than the pump: with no widget tree there are no frames,
/// and Riverpod schedules a dependent's rebuild against one — so a provider nobody reads stays
/// stale here in a way it never does in the app. Reading flushes it, then the pump lets the decode
/// it kicked off finish, then the second read picks up the state that landed.
Future<void> _settle(ProviderContainer container) async {
  container.read(artworkAccentProvider);
  await pumpEventQueue();
  container.read(artworkAccentProvider);
}

/// Degrees between two hues, the short way round.
double _hueGap(double a, double b) {
  final gap = (a - b).abs() % 360;
  return gap > 180 ? 360 - gap : gap;
}

UserSettings _settings(AccentMode? mode) => UserSettings(
  streamingQuality: QualityProfile.high,
  normalizeVolume: false,
  autoplay: true,
  crossfadeSeconds: 0,
  preloadCount: 2,
  accent: 'pink',
  accentMode: mode,
  scrobble: true,
  scrobblePrivacy: ScrobblePrivacy.friends,
  eq: const EqConfig(bands: [], enabled: true, preamp: 0),
);

/// Stands in for the player: the cover on screen, changeable from a test.
class _Cover extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String? hash) => state = hash;
}

final _coverProvider = NotifierProvider<_Cover, String?>(_Cover.new);

/// Stands in for the accent mode the account is in.
class _Mode extends Notifier<AccentMode?> {
  _Mode(this._initial);

  final AccentMode? _initial;

  @override
  AccentMode? build() => _initial;

  void use(AccentMode? mode) => state = mode;
}

final _modeProvider = NotifierProvider<_Mode, AccentMode?>(
  () => _Mode(AccentMode.artwork),
);

// ── a real image to decode ────────────────────────────────────────────────────────────────────

/// Encodes a truecolour PNG, so the decode test exercises a real codec rather than a fixture.
///
/// Written by hand because the app has no image-encoding dependency and should not grow one for a
/// test: PNG's container is a handful of length-prefixed, CRC'd chunks around a zlib stream, and
/// `dart:io` already brings the zlib.
Uint8List _png(
  int width,
  int height,
  (int, int, int) Function(int x, int y) at,
) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // filter: none
    for (var x = 0; x < width; x++) {
      final (r, g, b) = at(x, y);
      raw.add([r, g, b]);
    }
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2) // colour type: truecolour
    ..setUint8(10, 0) // deflate
    ..setUint8(11, 0) // adaptive filtering
    ..setUint8(12, 0); // no interlace

  final out = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_chunk('IHDR', header.buffer.asUint8List()))
    ..add(_chunk('IDAT', ZLibCodec().encode(raw.toBytes())))
    ..add(_chunk('IEND', const []));
  return out.toBytes();
}

Uint8List _chunk(String type, List<int> data) {
  final body = <int>[...type.codeUnits, ...data];
  final length = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc32(body));
  return (BytesBuilder()
        ..add(length.buffer.asUint8List())
        ..add(body)
        ..add(crc.buffer.asUint8List()))
      .toBytes();
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
