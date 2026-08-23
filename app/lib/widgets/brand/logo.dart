/// The Chordia mark: a vinyl record, in a wide lockup (record + wordmark) or a square one
/// (record + C).
///
/// Ported from `frontend/src/components/brand/Logo.tsx` and `mark.ts`, number for number. The web
/// keeps geometry and component apart because a build script renders the same drawing into the
/// favicon; the phone has no such generator — its launcher icons come from the artwork the frontend
/// already publishes (`app/pubspec.yaml`, `flutter_launcher_icons`) — so one file is the whole mark
/// here.
///
/// ## The artwork is a PLACEHOLDER, on both clients
///
/// A commissioned mark is in progress. The swap contract is the five groups, and they survive here
/// as the five private paint methods: `_paintBase`, `_paintRecord`, `_paintLabel`, `_paintWordmark`
/// and `_paintNeedle`. Replace their contents, keep the 64-unit coordinate space and the two pivots
/// ([_recordCentre] and [_needlePivot]), and the animation and every call site keep working.
///
/// ## Two decisions the artwork encodes
///
/// **Rings, not a filled disc.** A real record is black, and a black disc is invisible on a dark
/// background. Concentric strokes read as a record from either theme.
///
/// **The plinth and the tonearm do not exist at rest.** A rounded rectangle around the mark reads
/// as a container border in an app bar, and a tonearm is noise at 20px. They fade in for the
/// sequence and back out again.
///
/// ## The spin is event-scoped and NEVER idle
///
/// `docs/overhaul/13-brand.md` is explicit, and the web's stylesheet repeats it: a mark that spins
/// in the app shell is a permanently animating element on every screen, which is the exact category
/// of thing the perf work removed. So [ChordiaLogoState.idle] starts no ticker at all — not a
/// paused one — and `test/identity_test.dart` asserts an idle mark schedules no frame callbacks.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

// ── Geometry (mark.ts) ────────────────────────────────────────────────────────────────────────

/// The square lockup's coordinate space.
const _viewBox = 64.0;

/// The record's centre. `#record` rotates about this point, so nothing may assume otherwise.
const _recordCentre = Offset(32, 32);

/// The tonearm's pivot. `#needle` rotates about this point.
const _needlePivot = Offset(58, 8);

/// The rings, outermost first: the record's edge, then two grooves.
const _rings = [
  (r: 29.0, width: 3.0, opacity: 1.0),
  (r: 24.0, width: 1.2, opacity: 0.45),
  (r: 20.5, width: 1.2, opacity: 0.45),
];

/// The C — the whole idea of the mark, since the letter sitting on the record IS the C of
/// "Chordia".
const _cRadius = 15.0;
const _cStroke = 5.0;

/// Degrees either side of east that the C leaves open.
const _cGapDeg = 48.0;

/// The centre label: a stroked ring, so the spindle hole is transparent without a mask.
const _labelRadius = 3.5;
const _labelStroke = 2.5;

/// The wedge each groove leaves empty, in degrees either side of east — wide enough for the tail's
/// ascenders, not just its x-height. The square lockup has nothing to make way for, so its grooves
/// close.
const _runoutDeg = 52.0;

/// The C's outer extent. The tail's cap height and baseline are these.
const _cTop = 32 - _cRadius - _cStroke / 2;
const _cBaseline = 32 + _cRadius + _cStroke / 2;

/// Where the tail begins: just past the C's open side, inside the run-out wedge.
const _tailX = 50.0;
const _tailWidth = 150.0;

/// Sized so the tail's ascenders (`h`, `d`) land on the C's own top edge.
///
/// A ratio of the C's height rather than a number, because the C is the reference: the two are one
/// word, and a tail that does not reach the C's cap line reads as a smaller word set beside a logo.
/// 0.73 is the ascender-to-em ratio of a typical bold sans — placeholder detail, like the web's,
/// since the delivered mark will be outlined paths with no font metrics to depend on.
const _tailFontSize = (_cBaseline - _cTop) / 0.73;

/// The wide lockup's full width in its own units.
const _wideWidth = _tailX + _tailWidth + 6;

// ── Motion (styles.css, the `.logo` block) ────────────────────────────────────────────────────

const _spin = Duration(milliseconds: 2400);
const _spinDelay = Duration(milliseconds: 860);
const _tailRetract = (start: 0, end: 380);
const _ringsCrossFade = (start: 260, end: 560);
const _baseFade = (start: 380, end: 700);
const _needleDrop = (start: 520, end: 940);

/// How far the tonearm sits off the record before it lands, in degrees.
const _needleLiftDeg = -22.0;

/// One turn of the sequence, from the first frame to the record's first full revolution.
final _sequence = _spinDelay + _spin;

enum ChordiaLogoVariant {
  /// Record + wordmark.
  wide,

  /// Record + C. What the wide lockup contracts into.
  square,
}

/// There is deliberately no "always spinning" state — see the note at the top of this file.
enum ChordiaLogoState {
  /// The resting mark. Starts no ticker.
  idle,

  /// Runs the sequence: the tail retracts into the C, the run-out closes, the plinth fades in, the
  /// tonearm swings over, the record spins.
  playing,
}

/// The mark.
///
/// [size] is the drawing's HEIGHT. The square lockup is that wide too; the wide lockup is
/// `size * 206 / 64`, so a caller never has to know the aspect ratio.
class ChordiaLogo extends StatefulWidget {
  const ChordiaLogo({
    super.key,
    this.variant = ChordiaLogoVariant.square,
    this.state = ChordiaLogoState.idle,
    this.size = 32,
    this.color,
    this.accentColor,
    this.semanticLabel,
  });

  final ChordiaLogoVariant variant;
  final ChordiaLogoState state;
  final double size;

  /// The rings, plinth, tonearm and the wordmark's tail. Defaults to the surrounding text colour,
  /// which is what `fill="currentColor"` buys the web.
  final Color? color;

  /// The C and the centre label. Defaults to the live accent (`--logo-accent: var(--primary)`), so
  /// the mark re-tints with everything else. A caller placing the mark ON an accent surface passes
  /// [color] here to opt out, exactly as the web sets `--logo-accent: currentColor`.
  final Color? accentColor;

  /// Sets an accessible name. Omit when the mark already sits beside the word "Chordia".
  final String? semanticLabel;

  @override
  State<ChordiaLogo> createState() => _ChordiaLogoState();
}

class _ChordiaLogoState extends State<ChordiaLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _sequence,
  );

  /// Where the loop re-enters: the frame the record starts turning.
  ///
  /// The lead-in — tail, rings, plinth, tonearm — happens ONCE. Looping the whole sequence would
  /// stall the disc for 860ms every revolution while the set dressing it already has re-played.
  static final _loopStart =
      _spinDelay.inMilliseconds / _sequence.inMilliseconds;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_onStatus);
    _sync();
  }

  @override
  void didUpdateWidget(ChordiaLogo old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _sync();
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (widget.state != ChordiaLogoState.playing) return;
    // One revolution per `_spin`, so the disc turns at the rate the lead-in handed it over at.
    _controller.repeat(min: _loopStart, max: 1, period: _spin);
  }

  /// The only place the ticker is started or stopped.
  ///
  /// `idle` calls [AnimationController.stop], which unregisters the ticker's frame callback
  /// entirely — a paused-but-registered animation would still keep the widget on the frame
  /// schedule, which is the cost the "never idle" rule exists to avoid.
  void _sync() {
    if (widget.state == ChordiaLogoState.playing) {
      _controller
        ..value = 0
        ..forward();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink =
        widget.color ??
        DefaultTextStyle.of(context).style.color ??
        scheme.onSurface;
    final accent = widget.accentColor ?? scheme.primary;
    final wide = widget.variant == ChordiaLogoVariant.wide;
    final width = widget.size * (wide ? _wideWidth / _viewBox : 1);

    return Semantics(
      label: widget.semanticLabel,
      image: widget.semanticLabel != null,
      child: SizedBox(
        width: width,
        height: widget.size,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              painter: _LogoPainter(
                wide: wide,
                ink: ink,
                accent: accent,
                elapsedMs: _controller.value * _sequence.inMilliseconds,
                playing: widget.state == ChordiaLogoState.playing,
                textDirection: Directionality.of(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter({
    required this.wide,
    required this.ink,
    required this.accent,
    required this.elapsedMs,
    required this.playing,
    required this.textDirection,
  });

  final bool wide;
  final Color ink;
  final Color accent;
  final double elapsedMs;
  final bool playing;
  final TextDirection textDirection;

  /// 0 before [start], 1 after [end], eased in between. The stylesheet's `both` fill, which is what
  /// keeps a step at its end value for the rest of the sequence instead of snapping back.
  double _phase(({int start, int end}) window) {
    if (!playing) return 0;
    if (elapsedMs <= window.start) return 0;
    if (elapsedMs >= window.end) return 1;
    return Curves.easeOut.transform(
      (elapsedMs - window.start) / (window.end - window.start),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Everything below is authored in the 64-unit space the web draws in.
    final scale = size.height / _viewBox;
    canvas.save();
    canvas.scale(scale);

    final spun = playing
        ? ((elapsedMs - _spinDelay.inMilliseconds) / _spin.inMilliseconds)
              .clamp(0.0, 1.0)
        : 0.0;

    _paintBase(canvas, _phase(_baseFade));
    _paintRecord(canvas, spun);
    _paintWordmark(canvas, spun);
    _paintLabel(canvas, spun);
    _paintNeedle(canvas, _phase(_needleDrop));

    canvas.restore();
  }

  Paint _stroke(Color color, double width, double opacity) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..color = color.withValues(alpha: color.a * opacity);

  /// Rotates the canvas about the record's centre — the one transform the disc, the C and the label
  /// share, so they ride round together rather than the C sitting still inside a spinning record.
  void _spinAbout(Canvas canvas, double turns) {
    canvas.translate(_recordCentre.dx, _recordCentre.dy);
    canvas.rotate(turns * 2 * math.pi);
    canvas.translate(-_recordCentre.dx, -_recordCentre.dy);
  }

  /// `#base` — the turntable plinth, seen from above. Hidden at rest.
  void _paintBase(Canvas canvas, double phase) {
    if (phase == 0) return;
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0.75, 0.75, 62.5, 62.5),
          const Radius.circular(12),
        ),
        _stroke(ink, 1.25, 0.28 * phase),
      )
      // The tonearm's mounting post — where the needle swings from.
      ..drawCircle(_needlePivot, 3, _stroke(ink, 1.25, 0.45 * phase));
  }

  /// `#record` — the disc. The wide lockup's grooves are broken by the run-out so the tail reads
  /// out of them; they close as the tail retracts, which is what makes the square lockup what the
  /// wide one leaves behind rather than a second drawing.
  void _paintRecord(Canvas canvas, double turns) {
    final closed = wide ? _phase(_ringsCrossFade) : 1.0;
    canvas.save();
    _spinAbout(canvas, turns);
    for (final ring in _rings) {
      if (closed < 1) {
        canvas.drawPath(
          _openArc(ring.r, _runoutDeg),
          _stroke(ink, ring.width, ring.opacity * (1 - closed)),
        );
      }
      if (closed > 0) {
        canvas.drawCircle(
          _recordCentre,
          ring.r,
          _stroke(ink, ring.width, ring.opacity * closed),
        );
      }
    }
    canvas.restore();
  }

  /// `#wordmark` — the C, plus (wide only) "hordia" continuing out of it on the same baseline.
  void _paintWordmark(Canvas canvas, double turns) {
    canvas.save();
    _spinAbout(canvas, turns);
    canvas.drawPath(_openArc(_cRadius, _cGapDeg), _stroke(accent, _cStroke, 1));

    if (wide) {
      // The tail retracts INTO the C rather than merely fading, so the C reads as what is left of
      // the word rather than a different mark appearing where a word used to be.
      final retracted = _phase(_tailRetract);
      if (retracted < 1) _paintTail(canvas, 1 - retracted);
    }
    canvas.restore();
  }

  void _paintTail(Canvas canvas, double extent) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'hordia',
        style: TextStyle(
          fontSize: _tailFontSize,
          fontWeight: FontWeight.w700,
          height: 1,
          color: ink.withValues(alpha: ink.a * extent),
        ),
      ),
      textDirection: textDirection,
    )..layout();

    canvas.save();
    // `textLength` + `lengthAdjust="spacingAndGlyphs"` on the web: the tail is pinned to exactly
    // 150 units whatever font resolves, so the lockup's width cannot drift between platforms.
    // The horizontal squeeze also IS the retraction, collapsing toward the C's open side.
    canvas
      ..translate(_tailX, _cBaseline)
      ..scale((_tailWidth / painter.width) * extent, 1);
    // `y` in SVG text is the BASELINE; Flutter paints from the top of the line box.
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    painter.paint(canvas, Offset(0, -baseline));
    canvas.restore();
    painter.dispose();
  }

  /// `#label` — the centre label. A stroked ring rather than a filled circle, so the spindle hole
  /// is transparent for free; punching a hole through a filled label would need a mask, and a mask
  /// cannot know the colour behind it.
  void _paintLabel(Canvas canvas, double turns) {
    canvas.save();
    _spinAbout(canvas, turns);
    canvas.drawCircle(
      _recordCentre,
      _labelRadius,
      _stroke(accent, _labelStroke, 1),
    );
    canvas.restore();
  }

  /// `#needle` — the tonearm. Hidden at rest; swings over the record for the sequence.
  void _paintNeedle(Canvas canvas, double phase) {
    if (phase == 0) return;
    canvas.save();
    canvas
      ..translate(_needlePivot.dx, _needlePivot.dy)
      ..rotate(_needleLiftDeg * (1 - phase) * math.pi / 180)
      ..translate(-_needlePivot.dx, -_needlePivot.dy);
    final paint = _stroke(ink, 1.6, 0.6 * phase);
    canvas
      ..drawPath(
        Path()
          ..moveTo(_needlePivot.dx, _needlePivot.dy)
          ..lineTo(47, 19.5)
          ..lineTo(41.5, 25),
        paint,
      )
      ..drawCircle(
        const Offset(41.5, 25),
        1.5,
        Paint()..color = ink.withValues(alpha: ink.a * 0.6 * phase),
      );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.elapsedMs != elapsedMs ||
      old.playing != playing ||
      old.wide != wide ||
      old.ink != ink ||
      old.accent != accent;
}

/// A ring open to the east, sweeping the long way round from `+gap` to `-gap` — `openArc` in
/// `mark.ts`. Flutter's arc angles run clockwise from the +x axis in a y-down space, which is
/// exactly SVG's convention, so the two agree without a sign flip.
Path _openArc(double r, double gapDeg) {
  final gap = gapDeg * math.pi / 180;
  return Path()..addArc(
    Rect.fromCircle(center: _recordCentre, radius: r),
    gap,
    2 * math.pi - 2 * gap,
  );
}

/// The mark, playing, as a loading indicator.
///
/// This is the web's own choice, not an invention: `AuthPage.tsx:22` plays the record "while
/// something is in flight — the sign-in hand-off has no other spinner", and 13-brand.md names the
/// boot skeleton as the place where "the animated mark IS the boot indicator". A phone showing a
/// Material `CircularProgressIndicator` where the desktop shows the brand is one of the plainest
/// ways the two read as different products.
class BrandLoader extends StatelessWidget {
  const BrandLoader({super.key, this.size = 48, this.semanticLabel});

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Center(
    child: ChordiaLogo(
      state: ChordiaLogoState.playing,
      size: size,
      semanticLabel: semanticLabel,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}
