/// The seven badges, drawn.
///
/// All in one file on purpose, exactly as `frontend/src/components/profile/badges/BadgeArt.tsx`
/// keeps them together. They are a family, not seven unrelated icons: every one is the Chordia
/// mark's record seen small — same centre, same groove radii, same spindle — and what distinguishes
/// them is a material, a rim treatment and a label glyph. Side by side, an inconsistency is visible
/// while you are writing it; split up, the family drifts.
///
/// The phone was drawing a stock `Icons.shield_rounded` in a Material `Chip` for each, which is a
/// different object entirely: nothing about it says "record", and seven of them in a row say
/// nothing about being a set.
///
/// Every number below is the web's. The two deliberate departures are noted where they happen: the
/// translator's mirrored quote marks are approximated rather than transcribed bezier for bezier,
/// and nothing animates at rest, for the reason `widgets/brand/logo.dart` gives at length — an
/// idle spin in a scrolling list is a permanently animating element.
library;

import 'dart:math' as math;

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';

/// The mark's coordinate space, shared with the logo so a badge and the logo read as one object.
const _viewBox = 64.0;
const _centre = Offset(32, 32);

/// The record's outer edge, slightly inside the mark's 29 so a rim stroke stays in the box.
const _discR = 28.0;

/// The centre label — where every badge puts its glyph.
const _labelR = 11.0;

/// The spindle hole. A filled near-black disc with a bevel, not a stroked ring: stroked, the label
/// colour shows through and it reads as a printed dot rather than as a hole. The void is a fixed
/// colour because art cannot know what is behind it.
const _spindleR = 1.6;
const _hole = Color(0xFF08070C);

/// Super-Sonic streak thresholds, in whole months. The client owns these, so changing them needs no
/// deploy — the same contract the web states.
const superSonicStages = [
  (stage: 1, minMonths: 0, key: 'spark'),
  (stage: 2, minMonths: 3, key: 'orbit'),
  (stage: 3, minMonths: 6, key: 'nova'),
  (stage: 4, minMonths: 12, key: 'diamond'),
];

/// Which stage a streak has reached. Stages ADD to each other rather than replacing, so a badge
/// somebody has been wearing never changes out from under them — it accumulates.
({int stage, int minMonths, String key}) stageFor(int streakMonths) {
  var found = superSonicStages.first;
  for (final candidate in superSonicStages) {
    if (streakMonths >= candidate.minMonths) found = candidate;
  }
  return found;
}

/// One badge's art at whatever size it is given.
class BadgeArt extends StatelessWidget {
  const BadgeArt({required this.badge, required this.size, super.key});

  final ProfileBadge badge;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _BadgePainter(
        badge: badge,
        // Accent-driven parts follow the account's colour, the same contract the web's
        // `--badge-accent` falls back to `--primary` for.
        accent: Theme.of(context).colorScheme.primary,
        textDirection: Directionality.of(context),
      ),
    ),
  );
}

class _BadgePainter extends CustomPainter {
  const _BadgePainter({
    required this.badge,
    required this.accent,
    required this.textDirection,
  });

  final ProfileBadge badge;
  final Color accent;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / _viewBox, size.height / _viewBox);
    switch (badge) {
      case ProfileBadgeDeveloper():
        _developer(canvas);
      case ProfileBadgeStaff():
        _staff(canvas);
      case ProfileBadgeTranslator():
        _translator(canvas);
      case ProfileBadgeEarlyBird():
        _earlyBird(canvas);
      case ProfileBadgeEarlySupporter(:final rank):
        _earlySupporter(canvas, rank);
      case ProfileBadgeSonic():
        _sonic(canvas);
      case ProfileBadgeSuperSonic(:final streakMonths):
        _superSonic(canvas, stageFor(streakMonths).stage);
    }
    _spindle(canvas);
    canvas.restore();
  }

  // ── The shell every badge shares ──────────────────────────────────────────────────────────

  /// Disc, two grooves at the mark's own radii, and the centre label.
  ///
  /// The grooves are most of what makes this read as vinyl rather than as a coin.
  void _disc(
    Canvas canvas, {
    required Shader material,
    required Color label,
    double grooveOpacity = 0.18,
  }) {
    canvas.drawCircle(_centre, _discR, Paint()..shader = material);
    for (final radius in const [23.0, 19.5]) {
      canvas.drawCircle(
        _centre,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = Colors.black.withValues(alpha: grooveOpacity),
      );
    }
    canvas.drawCircle(_centre, _labelR, Paint()..color = label);
  }

  /// A rim stroke just inside the disc's edge.
  void _rim(Canvas canvas, Color color, {double width = 1, double alpha = 1}) =>
      canvas.drawCircle(
        _centre,
        _discR - 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = color.withValues(alpha: alpha),
      );

  /// Evenly spaced tick marks around a radius — the "sound wave" rim treatment.
  void _ticks(
    Canvas canvas, {
    required int count,
    required double radius,
    required double length,
    required Color color,
    double width = 1.2,
    double alpha = 1,
  }) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: alpha);
    for (var i = 0; i < count; i++) {
      final angle = i * 2 * math.pi / count;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        _centre + direction * radius,
        _centre + direction * (radius + length),
        paint,
      );
    }
  }

  /// A hole in a solid object is legible from its rim, not from being dark: a bright arc where the
  /// cut edge catches the light, a dark one opposite where the record's own thickness shades it.
  void _spindle(Canvas canvas) {
    canvas.drawCircle(_centre, _spindleR, Paint()..color = _hole);
    final box = Rect.fromCircle(center: _centre, radius: _spindleR);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawArc(
        box,
        math.pi,
        math.pi / 2,
        false,
        stroke..color = Colors.white.withValues(alpha: 0.45),
      )
      ..drawArc(
        box,
        0,
        math.pi / 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..strokeCap = StrokeCap.round
          ..color = Colors.black.withValues(alpha: 0.45),
      );
  }

  Shader _linear(
    List<Color> colors,
    List<double> stops,
    Offset from,
    Offset to,
  ) => LinearGradient(
    begin: Alignment(from.dx * 2 - 1, from.dy * 2 - 1),
    end: Alignment(to.dx * 2 - 1, to.dy * 2 - 1),
    colors: colors,
    stops: stops,
  ).createShader(const Rect.fromLTWH(0, 0, _viewBox, _viewBox));

  /// The sound wave through the label — the badge's own small piece of sound.
  void _wave(Canvas canvas, Color color, {double width = 1.9}) {
    final path = Path()
      ..moveTo(26, 32)
      ..quadraticBezierTo(29, 27, 32, 32)
      ..quadraticBezierTo(35, 37, 38, 32);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  void _text(
    Canvas canvas,
    String value, {
    required double fontSize,
    required Color color,
    FontWeight weight = FontWeight.w700,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          color: color,
          height: 1,
        ),
      ),
      textDirection: textDirection,
    )..layout();
    painter.paint(
      canvas,
      _centre - Offset(painter.width / 2, painter.height / 2),
    );
  }

  // ── The seven ─────────────────────────────────────────────────────────────────────────────

  /// Obsidian, a thin accent rim, and the one glyph that means "wrote this".
  void _developer(Canvas canvas) {
    _disc(
      canvas,
      material: _linear(
        const [Color(0xFF26242E), Color(0xFF0D0C11)],
        const [0, 1],
        const Offset(0, 0),
        const Offset(0, 1),
      ),
      label: const Color(0xFF0B0A0F),
      grooveOpacity: 0.5,
    );
    _rim(canvas, accent, width: 1.1, alpha: 0.9);
    final chevrons = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = accent;
    canvas
      ..drawPath(
        Path()
          ..moveTo(28.5, 28.5)
          ..lineTo(25, 32)
          ..lineTo(28.5, 35.5),
        chevrons,
      )
      ..drawPath(
        Path()
          ..moveTo(35.5, 28.5)
          ..lineTo(39, 32)
          ..lineTo(35.5, 35.5),
        chevrons,
      );
  }

  /// Gunmetal and a shield. Deliberately the least decorated of the seven: it is a role, not a
  /// prize.
  void _staff(Canvas canvas) {
    _disc(
      canvas,
      material: _linear(
        const [Color(0xFF5B6472), Color(0xFF39404B), Color(0xFF272C34)],
        const [0, 0.55, 1],
        const Offset(0.2, 0),
        const Offset(0.8, 1),
      ),
      label: const Color(0xFF20232B),
      grooveOpacity: 0.45,
    );
    _rim(canvas, const Color(0xFF9AA6B6), alpha: 0.55);
    final shield = Path()
      ..moveTo(32, 26.5)
      ..lineTo(37, 28.4)
      ..lineTo(37, 31.8)
      ..cubicTo(37, 34.8, 34.9, 37.2, 32, 38)
      ..cubicTo(29.1, 37.2, 27, 34.8, 27, 31.8)
      ..lineTo(27, 28.4)
      ..close();
    canvas.drawPath(shield, Paint()..color = const Color(0xFFC8D2E0));
  }

  /// Teal enamel and a speech mark said twice — the same thing in two voices, which is the job.
  ///
  /// Deliberately not a flag or a globe: the catalogs are languages, not countries, and a flag
  /// picks one country per language and is wrong about most of them. The pair here is drawn as two
  /// rotationally symmetric comma forms rather than transcribed from the web's beziers; the shape
  /// is a comma either way, and fourteen hand-converted control points would be a worse thing to
  /// keep in step than a stated approximation.
  void _translator(Canvas canvas) {
    _disc(
      canvas,
      material: _linear(
        const [Color(0xFF2F7D7A), Color(0xFF1F5A58), Color(0xFF15413F)],
        const [0, 0.55, 1],
        const Offset(0.2, 0),
        const Offset(0.8, 1),
      ),
      label: const Color(0xFF0F2A2B),
      grooveOpacity: 0.4,
    );
    _rim(canvas, const Color(0xFF7FDED8), alpha: 0.5);
    void comma(Offset at, Color color, {required bool flipped}) {
      canvas
        ..save()
        ..translate(at.dx, at.dy);
      if (flipped) canvas.rotate(math.pi);
      final path = Path()
        ..addArc(const Rect.fromLTWH(-2.2, -2.2, 4.4, 4.4), 0, 2 * math.pi)
        ..moveTo(0.4, 1.9)
        ..quadraticBezierTo(2.2, 3.4, 2.6, 5.2)
        ..lineTo(0.2, 4.6)
        ..close();
      canvas
        ..drawPath(path, Paint()..color = color)
        ..restore();
    }

    comma(const Offset(28.4, 30), const Color(0xFFBFF3EF), flipped: false);
    comma(const Offset(35.6, 34), const Color(0xFF6FC9C3), flipped: true);
  }

  /// First Pressing: warm cream, a sunrise, a bird.
  ///
  /// Matte and paper-like on purpose — it marks being early, not paying, so it must not look like
  /// the premium tiers. Someone who has had it since launch and never subscribed should not appear
  /// to be wearing a lesser gold badge.
  void _earlyBird(Canvas canvas) {
    _disc(
      canvas,
      material: _linear(
        const [Color(0xFFF7ECD8), Color(0xFFE2CDA5)],
        const [0, 1],
        const Offset(0, 0),
        const Offset(0, 1),
      ),
      label: const Color(0xFFF3E6CD),
      grooveOpacity: 0.12,
    );
    _rim(canvas, const Color(0xFFC2A476));
    // The sun rising behind the label's horizon, then the horizon itself.
    canvas
      ..drawPath(
        Path()
          ..moveTo(25, 33.5)
          ..arcToPoint(const Offset(39, 33.5), radius: const Radius.circular(7))
          ..close(),
        Paint()..color = const Color(0xFFE8A13C),
      )
      ..drawLine(
        const Offset(24, 33.6),
        const Offset(40, 33.6),
        Paint()
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFB98A3F),
      )
      // The bird: two strokes, which is all a bird at this size can be.
      ..drawPath(
        Path()
          ..moveTo(28.4, 29.4)
          ..cubicTo(29.3, 28.4, 30.3, 28.4, 31, 29.2)
          ..cubicTo(31.7, 28.4, 32.7, 28.4, 33.6, 29.4),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.15
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF6B5330),
      );
  }

  /// Founding 100: gold foil, a specular sweep, and the rank engraved on the label.
  ///
  /// The number is the point. "Early supporter" is a claim; "7" of a hundred is a fact, and it is
  /// the one thing on any of these badges that can never be earned again.
  void _earlySupporter(Canvas canvas, int rank) {
    _disc(
      canvas,
      material: _linear(
        const [
          Color(0xFFF7E39B),
          Color(0xFFD9A63C),
          Color(0xFFF6DD93),
          Color(0xFFA9761D),
        ],
        const [0, 0.35, 0.62, 1],
        const Offset(0.1, 0),
        const Offset(0.9, 1),
      ),
      label: const Color(0xFF8A6420),
      grooveOpacity: 0.16,
    );
    _rim(canvas, const Color(0xFFFBEEC0), alpha: 0.85);
    // The specular arc: a bright stroke over part of the rim, which is what makes flat gold read
    // as metal. A blur would do it better and cost a raster pass; this is free.
    canvas.drawArc(
      Rect.fromCircle(center: _centre, radius: _discR - 3),
      -math.pi * 0.9,
      math.pi * 0.5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.5),
    );
    _text(
      canvas,
      '$rank',
      fontSize: rank >= 100 ? 8 : 11,
      color: const Color(0xFFFFF3D0),
    );
  }

  /// Brushed silver, with the rim ticked into a waveform in the wearer's own accent.
  void _sonic(Canvas canvas) {
    _disc(
      canvas,
      material: _linear(
        const [
          Color(0xFFE8ECF2),
          Color(0xFFAEB6C2),
          Color(0xFFDFE4EC),
          Color(0xFF8F97A4),
        ],
        const [0, 0.4, 0.7, 1],
        const Offset(0.15, 0),
        const Offset(0.85, 1),
      ),
      label: const Color(0xFF3B3F47),
      grooveOpacity: 0.2,
    );
    _ticks(
      canvas,
      count: 28,
      radius: 24.2,
      length: 2.6,
      color: accent,
      width: 1.3,
    );
    _wave(canvas, accent);
  }

  /// Iridescent, and it grows.
  ///
  /// The glow is three stacked translucent circles rather than a blur, for the reason the whole
  /// family avoids filters: compositing is free, a raster pass is not, and a badge can appear a
  /// dozen times in one list.
  void _superSonic(Canvas canvas, int stage) {
    for (final (radius, colour, alpha) in const [
      (31.0, Color(0xFFA86BFF), 0.10),
      (30.0, Color(0xFFA86BFF), 0.14),
      (29.0, Color(0xFFC46BFF), 0.16),
    ]) {
      canvas.drawCircle(
        _centre,
        radius,
        Paint()..color = colour.withValues(alpha: alpha),
      );
    }
    canvas.drawCircle(
      _centre,
      _discR,
      Paint()
        ..shader = _linear(
          const [
            Color(0xFFFF5CC8),
            Color(0xFF9B6BFF),
            Color(0xFF3FD0E8),
            Color(0xFF6F7DFF),
            Color(0xFFC04CFF),
          ],
          const [0, 0.3, 0.58, 0.8, 1],
          const Offset(0.1, 0.05),
          const Offset(0.9, 0.95),
        ),
    );
    canvas
      ..drawCircle(
        _centre,
        23,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = Colors.white.withValues(alpha: 0.22),
      )
      ..drawCircle(
        _centre,
        19.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = Colors.black.withValues(alpha: 0.14),
      );

    void orbit(double degrees, double alpha) {
      canvas
        ..save()
        ..translate(_centre.dx, _centre.dy)
        ..rotate(degrees * math.pi / 180)
        ..drawOval(
          Rect.fromCenter(center: Offset.zero, width: 53, height: 22),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1
            ..color = Colors.white.withValues(alpha: alpha),
        )
        ..restore();
    }

    // Each stage ADDS to the last: an orbit, a second one crossing it, then a ticked rim.
    if (stage >= 2) orbit(-24, 0.7);
    if (stage >= 3) {
      orbit(28, 0.55);
      for (final spark in const [Offset(8, 24), Offset(56, 40)]) {
        canvas.drawCircle(
          spark,
          1.5,
          Paint()..color = Colors.white.withValues(alpha: 0.9),
        );
      }
    }
    if (stage >= 4) {
      _ticks(
        canvas,
        count: 36,
        radius: 25,
        length: 2.2,
        color: Colors.white,
        width: 1,
        alpha: 0.75,
      );
    }

    canvas.drawCircle(
      _centre,
      _labelR,
      Paint()..color = const Color(0xFF1B1030).withValues(alpha: 0.92),
    );
    if (stage >= 4) {
      // A faceted spindle: two triangles meeting at the waist.
      canvas.drawPath(
        Path()
          ..moveTo(32, 25)
          ..lineTo(38, 29.5)
          ..lineTo(32, 38.5)
          ..lineTo(26, 29.5)
          ..close(),
        Paint()..color = const Color(0xFFEAF6FF).withValues(alpha: 0.95),
      );
      final facet = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFF9FD8F0);
      canvas
        ..drawLine(const Offset(26, 29.5), const Offset(38, 29.5), facet)
        ..drawLine(const Offset(32, 25), const Offset(32, 38.5), facet);
    } else {
      _wave(canvas, Colors.white, width: 2);
    }
  }

  @override
  bool shouldRepaint(_BadgePainter old) =>
      old.badge != badge || old.accent != accent;
}
