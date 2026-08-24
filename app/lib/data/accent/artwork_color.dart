/// Pick one usable accent colour out of the cover that is playing.
///
/// A port of `frontend/src/lib/app/album-color.ts`, and it keeps that file's numbers rather than
/// re-deriving them, because the two clients painting different colours for the same sleeve is the
/// thing this is here to prevent.
///
/// **"Dominant colour" is the obvious framing and the wrong one.** The most common pixel in an
/// album cover is very often near-black or near-white, because covers have backgrounds; the mean of
/// every pixel is always grey-brown mud. What an accent wants is the most *characteristic* colour —
/// the one a person would name if asked what colour the sleeve is — which means weighting by chroma
/// and then dragging the result into a lightness band where it still works as a button.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Color;

import 'package:chordia_api/chordia_api.dart' show AccentMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../playback/current_cover.dart';
import '../playback/notification_art.dart';
import 'oklab.dart';

/// Downscale target, matching the web's `SIZE`. 576 pixels is plenty to find a colour and small
/// enough that the sampling loop is free.
const int artworkSampleSize = 24;

/// The band an accent has to land in, matching the web's `MIN_L`/`MAX_L`.
///
/// Below the floor, the accent on a near-black surface is invisible and its own foreground has
/// nowhere to go. Above the ceiling, every "on accent" label goes dark and the app reads as washed
/// out. Covers routinely give up colours outside both ends, so this clamp is the difference between
/// the mode being usable and being a novelty that occasionally makes the UI unreadable.
const double artworkMinLightness = 0.45;
const double artworkMaxLightness = 0.8;

/// Chroma ceiling on the result, matching the web. Pushing lightness up on an already-saturated
/// colour can land well outside sRGB, where `oklab.dart` has to clip per channel and the hue
/// drifts.
const double artworkMaxChroma = 0.28;

/// How much chroma a pixel needs before it is allowed to vote, and how much the answer needs before
/// it counts as a colour at all.
///
/// The web has no equivalent constant: it drops a pixel on `weight <= 0`, which in exact arithmetic
/// is every grey. In floating point a grey sleeve's pixels come back with a chroma of `1e-17` and a
/// weight that is merely tiny rather than zero, so the guard never fires and a black-and-white
/// cover yields a clamped mid-grey — the mud this whole file exists to avoid. 0.02 in OKLCH is
/// around the point a tint stops being nameable, so below it there is nothing to call an accent
/// and the palette colour the listener actually chose is the better answer.
const double artworkMinChroma = 0.02;

/// The accent colour for a block of RGBA pixels, or null when there is no colour worth using.
///
/// Pure and exported so the choice can be tested without decoding anything: the hard part is the
/// weighting, not the drawing.
Color? pickArtworkAccent(Uint8List rgba) {
  var wr = 0.0;
  var wg = 0.0;
  var wb = 0.0;
  var total = 0.0;

  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final r = rgba[i] / 255;
    final g = rgba[i + 1] / 255;
    final b = rgba[i + 2] / 255;

    final (l, c, _) = oklchOf(Color.from(alpha: 1, red: r, green: g, blue: b));
    // Weight by chroma, and drop the extremes of lightness entirely. A cover that is 70% black
    // background and 30% red lettering should give red — the unweighted mean gives dark grey.
    if (l < 0.15 || l > 0.95) continue;
    if (c < artworkMinChroma) continue;

    final weight = c * c;
    wr += r * weight;
    wg += g * weight;
    wb += b * weight;
    total += weight;
  }

  // A greyscale sleeve genuinely has no accent in it, and so does one that is nothing but shadow.
  // Saying so lets the caller keep the colour the person actually chose, which is a better answer
  // than a grey accent.
  if (total == 0) return null;

  final (l, c, h) = oklchOf(
    Color.from(alpha: 1, red: wr / total, green: wg / total, blue: wb / total),
  );
  if (c < artworkMinChroma) return null;
  return oklch(
    l.clamp(artworkMinLightness, artworkMaxLightness),
    math.min(c, artworkMaxChroma),
    h,
  );
}

/// Reads a cover off disk and returns its accent colour, or null when the file cannot be read or
/// holds nothing worth using.
///
/// **On threads.** The obvious shape is `compute()`, and it does not work: `dart:ui`'s decoders
/// refuse outright on a spawned isolate — `ImmutableBuffer.fromFilePath` throws *"UI actions are
/// only available on root isolate"* — and pulling a JPEG apart in pure Dart to get around that
/// would put far more work on a Dart thread than this path does now. What is used instead keeps the
/// expensive half off the UI thread anyway, and does it in native code:
///
/// * [ui.ImmutableBuffer.fromFilePath] reads the file on the engine's IO thread, and the encoded
///   bytes never enter the Dart heap.
/// * [ui.ImageDescriptor.instantiateCodec] with a target size decodes **and downsamples** on the
///   engine's worker pool, so a 512px cover is never a full-size bitmap on the UI thread — the
///   downscale is the averaging pass, done in native code, exactly as the web leans on
///   `drawImage(img, 0, 0, 24, 24)`.
///
/// What is left for Dart is 576 pixels of arithmetic, which is smaller than the cost of spawning an
/// isolate to carry it.
Future<Color?> accentFromArtworkFile(String path) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromFilePath(path);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    codec = await descriptor.instantiateCodec(
      targetWidth: artworkSampleSize,
      targetHeight: artworkSampleSize,
    );
    image = (await codec.getNextFrame()).image;
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (pixels == null) return null;
    return pickArtworkAccent(pixels.buffer.asUint8List());
  } on Object {
    // Art that cannot be decoded is a normal condition, not an error: a cover can be a format this
    // platform has no codec for, and the cache file can be gone by the time this runs. Either way
    // the answer is "no colour", which the caller already renders.
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Turns a cover file into an accent colour. Injected so a test can count analyses without owning
/// an image decoder.
typedef ArtworkAnalyser = Future<Color?> Function(String path);

final artworkAnalyserProvider = Provider<ArtworkAnalyser>(
  (ref) => accentFromArtworkFile,
);

/// The accent colour of the playing cover, or null when there is not one to use.
///
/// Null is the whole of the fallback: it means "use the configured palette colour", which is what
/// the accent engine already does for every other mode. Nothing here ever invents a colour.
///
/// Three properties this has to hold, all of which the web holds too:
///
/// * **Only in artwork mode.** The extraction never happens for the people not using it — the mode
///   is watched, so switching *into* artwork mode with a track already playing extracts right then
///   rather than waiting for a track change three minutes away.
/// * **Once per cover.** Keyed by content hash, so the same sleeve reached from a queue, a restart
///   of playback or a different hub is one analysis. Bounded, because a long listening session
///   would otherwise grow the map without limit.
/// * **Never stale.** The track can change again while the decode is in flight; applying a colour
///   that belongs to the previous cover is worse than applying none.
class ArtworkAccentNotifier extends Notifier<Color?> {
  /// Cover hash to colour, in least-recently-resolved-first order. A `null` **value** is a real
  /// answer — "this sleeve has no accent in it" — and must be told apart from an absent key, which
  /// is why every lookup goes through [containsKey].
  final _cache = <String, Color?>{};

  /// Matches the web's `CACHE_MAX`.
  static const _cacheMax = 64;

  /// The cover the in-flight analysis belongs to.
  String? _pending;

  @override
  Color? build() {
    final mode = ref.watch(
      userSettingsProvider.select((s) => s.value?.accentMode),
    );
    final hash = ref.watch(currentCoverHashProvider);

    if (mode != AccentMode.artwork || hash == null) {
      _pending = null;
      return null;
    }
    if (_cache.containsKey(hash)) {
      _pending = null;
      return _cache[hash];
    }

    _pending = hash;
    unawaited(_analyse(hash));
    // Until it resolves, the palette colour: an accent that flashes through an intermediate value
    // on every track change is more distracting than one that simply arrives.
    return null;
  }

  Future<void> _analyse(String hash) async {
    // Both reads happen before the first await. A `Ref` may not be touched once its provider has
    // been disposed, and a decode can easily outlive one — closing the app mid-track is exactly
    // that — so nothing here reaches back through `ref` after a gap.
    final art = ref.read(artCacheProvider);
    final analyse = ref.read(artworkAnalyserProvider);

    Color? colour;
    try {
      // The width the media session already downloaded for this very track, so this reads a file
      // that is on disk rather than pulling a second variant down the wire.
      final file = await art.file(hash, width: kNotificationArtWidth);
      if (file != null) colour = await analyse(file.path);
    } on Object {
      colour = null;
    }

    // The cover can have changed again while the decode was in flight, and the notifier can have
    // gone away entirely: a stale colour is worse than none, and assigning to a disposed provider
    // throws outright.
    if (!ref.mounted || _pending != hash) return;
    _pending = null;
    _remember(hash, colour);
    state = colour;
  }

  void _remember(String hash, Color? colour) {
    if (_cache.length >= _cacheMax) {
      // Oldest first — Dart maps preserve insertion order, and the current cover is the one most
      // likely to be asked for again.
      _cache.remove(_cache.keys.first);
    }
    _cache[hash] = colour;
  }
}

/// The colour the accent engine should use while artwork mode is on, or null to fall back to the
/// palette.
final artworkAccentProvider = NotifierProvider<ArtworkAccentNotifier, Color?>(
  ArtworkAccentNotifier.new,
);
