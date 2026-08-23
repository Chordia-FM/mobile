/// The colour maths the web client hands to the browser.
///
/// `frontend/src/styles.css` derives roughly forty tokens from one `--primary` with
/// `color-mix(in oklab, …)`, and `accent-engine.ts` interpolates its cross-fades the same way. CSS
/// gives that away for free; Dart has to do it by hand, and it has to be **OKLab**, not sRGB.
/// Mixing a near-black surface with a saturated accent in sRGB drags the result through the middle
/// of the RGB cube, which reads as muddy grey-brown — the difference between a pane that looks
/// *tinted* and one that looks *dirty*. In OKLab the same mix stays on the perceptual line between
/// the two colours.
///
/// The transform is the reference one (Björn Ottosson's), the same coefficients
/// `frontend/src/lib/app/album-color.ts` uses for its sRGB→OKLCH half, so a colour computed here
/// and a colour computed there agree.
///
/// **Out-of-gamut values are clipped per channel, deliberately.** `oklch(0.56 0.28 337)` — the
/// default accent — is outside sRGB, and the app's own comment says it "clips to a strong magenta
/// on both platforms, which is the intended look". Naive clipping reproduces `#cd00ae` exactly,
/// which is the value `ChordiaColors.accent` was measured from; a chroma-reduction gamut map would
/// quietly desaturate every preset away from what the web renders.
library;

import 'dart:math' as math;
import 'dart:ui' show Color;

/// A colour in the OKLab space: perceptual lightness plus two opponent axes.
class Oklab {
  const Oklab(this.l, this.a, this.b);

  /// Perceptual lightness, roughly 0 (black) to 1 (white).
  final double l;

  /// Green ↔ red.
  final double a;

  /// Blue ↔ yellow.
  final double b;
}

double _srgbToLinear(double v) =>
    v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _linearToSrgb(double v) {
  final c = v.clamp(0.0, 1.0);
  return c <= 0.0031308
      ? 12.92 * c
      : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;
}

/// Linear-light sRGB → OKLab.
Oklab _linearToOklab(double r, double g, double b) {
  final l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return Oklab(
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  );
}

/// OKLab → linear-light sRGB, as `(r, g, b)`. May fall outside `0..1`; the caller clips.
(double, double, double) _oklabToLinear(Oklab c) {
  final l = _cube(c.l + 0.3963377774 * c.a + 0.2158037573 * c.b);
  final m = _cube(c.l - 0.1055613458 * c.a - 0.0638541728 * c.b);
  final s = _cube(c.l - 0.0894841775 * c.a - 1.2914855480 * c.b);
  return (
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
  );
}

double _cbrt(double v) =>
    v < 0 ? -math.pow(-v, 1 / 3).toDouble() : math.pow(v, 1 / 3).toDouble();
double _cube(double v) => v * v * v;

/// Snap a channel to the 8-bit grid.
///
/// Every colour this library produces is quantised, which is not just tidiness: `Color` compares
/// its four channels as doubles, so an unquantised mix would never equal the `Color(0xFF……)`
/// literal it is meant to reproduce, and `ChordiaColors` could not act as the checked fallback for
/// the default accent. It is also what the framebuffer does anyway.
double _quantize(double v) => (v.clamp(0.0, 1.0) * 255).round() / 255;

/// A colour's OKLab coordinates.
Oklab oklabOf(Color color) => _linearToOklab(
  _srgbToLinear(color.r),
  _srgbToLinear(color.g),
  _srgbToLinear(color.b),
);

/// An OKLab colour as an sRGB one, clipped into gamut and snapped to 8 bits.
Color colorOfOklab(Oklab c, {double alpha = 1}) {
  final (r, g, b) = _oklabToLinear(c);
  return Color.from(
    alpha: _quantize(alpha),
    red: _quantize(_linearToSrgb(r)),
    green: _quantize(_linearToSrgb(g)),
    blue: _quantize(_linearToSrgb(b)),
  );
}

/// CSS `oklch(l c h)` — the notation every colour in `styles.css` is authored in.
///
/// [hue] is in degrees.
Color oklch(double l, double c, double hue, {double alpha = 1}) {
  final radians = hue * math.pi / 180;
  return colorOfOklab(
    Oklab(l, c * math.cos(radians), c * math.sin(radians)),
    alpha: alpha,
  );
}

/// A colour's OKLCH coordinates, as `(l, c, hue°)`.
(double, double, double) oklchOf(Color color) {
  final lab = oklabOf(color);
  final c = math.sqrt(lab.a * lab.a + lab.b * lab.b);
  final h = (math.atan2(lab.b, lab.a) * 180 / math.pi + 360) % 360;
  return (lab.l, c, h);
}

/// CSS `color-mix(in oklab, [color] [amount]%, [base])`.
///
/// [amount] is a fraction in `0..1` — `0.04` for the 4% that makes `--pane`. Alpha is carried
/// through the same weighting, which is what CSS does for two opaque colours.
Color mixOklab(Color color, double amount, Color base) {
  final t = amount.clamp(0.0, 1.0);
  final a = oklabOf(color);
  final b = oklabOf(base);
  return colorOfOklab(
    Oklab(
      a.l * t + b.l * (1 - t),
      a.a * t + b.a * (1 - t),
      a.b * t + b.b * (1 - t),
    ),
    alpha: color.a * t + base.a * (1 - t),
  );
}

/// CSS `color-mix(in srgb, [color] [amount]%, [base])`.
///
/// A handful of tokens in `styles.css` are deliberately `in srgb` rather than `in oklab` —
/// `--border`, `--sidebar-border` and `--line`. Ported as written: switching them to OKLab here
/// would give the phone a different hairline colour from the web for the same accent.
Color mixSrgb(Color color, double amount, Color base) {
  final t = amount.clamp(0.0, 1.0);
  return Color.from(
    alpha: _quantize(color.a * t + base.a * (1 - t)),
    red: _quantize(color.r * t + base.r * (1 - t)),
    green: _quantize(color.g * t + base.g * (1 - t)),
    blue: _quantize(color.b * t + base.b * (1 - t)),
  );
}

/// WCAG relative luminance, the quantity the readable-foreground crossover is expressed in.
double relativeLuminance(Color color) =>
    0.2126 * _srgbToLinear(color.r) +
    0.7152 * _srgbToLinear(color.g) +
    0.0722 * _srgbToLinear(color.b);
