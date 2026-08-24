import 'dart:math' as math;

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/tokens.dart';
import '../../catalog/format.dart' show titleCaseGenre;
import '../format.dart';
import 'insights_primitives.dart';

/// A day's worth of milliseconds. Bucket starts arrive already truncated to a local midnight, so
/// every calendar derivation here is arithmetic on that grid rather than a timezone conversion.
const _dayMs = 86400000;

/// The web's fixed categorical series order, `--chart-2` through `--chart-5`
/// (`frontend/src/styles.css:80-83`), converted from oklch to sRGB.
///
/// `--chart-1` is deliberately absent: it *is* the accent, reserved for single-series charts, and
/// spending it on band two of a stack would make one genre change colour every time the listener
/// picks a different accent. These four are fixed hues precisely so a genre keeps its band colour.
const _categorical = [
  Color(0xFF00A7BE),
  Color(0xFF8658E1),
  Color(0xFF00AC6C),
  Color(0xFFDE6F00),
];

/// The five axes, in the order the web plots them (`charts.tsx:1259-1265`). The order is part of
/// the shape: a fingerprint is recognisable because the same measure is always in the same corner.
const _fingerprintAxes = [
  (InsightsKeys.fingerprintAxesConsistency, _FingerprintAxis.consistency),
  (InsightsKeys.fingerprintAxesDiscovery, _FingerprintAxis.discovery),
  (InsightsKeys.fingerprintAxesReplay, _FingerprintAxis.replay),
  (InsightsKeys.fingerprintAxesConcentration, _FingerprintAxis.concentration),
  (InsightsKeys.fingerprintAxesVariance, _FingerprintAxis.variance),
];

enum _FingerprintAxis {
  consistency,
  discovery,
  replay,
  concentration,
  variance,
}

double _axisValue(Fingerprint print, _FingerprintAxis axis) {
  final value = switch (axis) {
    _FingerprintAxis.consistency => print.consistency,
    _FingerprintAxis.discovery => print.discovery,
    _FingerprintAxis.replay => print.replay,
    _FingerprintAxis.concentration => print.concentration,
    _FingerprintAxis.variance => print.variance,
  };
  // The Hub already bounds these to 0..1; clamping is against a future measure that does not,
  // which would otherwise draw a spike outside the grid rather than fail visibly.
  return value < 0 ? 0 : (value > 1 ? 1 : value);
}

/// A whole-number percentage in the reader's locale, for the several charts that speak in shares.
String _percent(double fraction, String locale) =>
    NumberFormat.decimalPercentPattern(
      locale: locale,
      decimalDigits: 0,
    ).format(fraction);

/// The five-axis listening fingerprint.
///
/// Designed to read correctly with only "you" plotted — the hub baseline is optional and never
/// synthesised; when it arrives it draws as a quiet grey polygon underneath, and only then does a
/// legend appear, because a single series is already named by the heading above it.
class FingerprintRadar extends ConsumerWidget {
  const FingerprintRadar({
    required this.you,
    super.key,
    this.average,
    this.youLabel,
  });

  final Fingerprint you;
  final Fingerprint? average;

  /// Names the primary series. Defaults to "You"; a profile passes whose fingerprint it is, so a
  /// legend on somebody else's page does not claim their listening as the reader's.
  final String? youLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;
    final theme = Theme.of(context);
    final baseline = average;
    final mine = youLabel ?? t(InsightsKeys.fingerprintYou);

    // The figure carries no text a screen reader can walk, so the reading of it is spelled out:
    // each axis, its value, and the hub average beside it when there is one.
    final spoken = [
      t(InsightsKeys.fingerprintAriaLabel),
      for (final (key, axis) in _fingerprintAxes)
        baseline == null
            ? '${t(key)} ${_percent(_axisValue(you, axis), locale)}'
            : t(InsightsKeys.fingerprintAxisWithAverage, {
                'axis': '${t(key)} ${_percent(_axisValue(you, axis), locale)}',
                'pct': _percent(_axisValue(baseline, axis), locale),
              }),
    ].join('. ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Semantics(
            label: spoken,
            image: true,
            child: SizedBox(
              height: 250,
              child: CustomPaint(
                painter: _RadarPainter(
                  you: [
                    for (final (_, axis) in _fingerprintAxes)
                      _axisValue(you, axis),
                  ],
                  average: baseline == null
                      ? null
                      : [
                          for (final (_, axis) in _fingerprintAxes)
                            _axisValue(baseline, axis),
                        ],
                  labels: [for (final (key, _) in _fingerprintAxes) t(key)],
                  accent: theme.colorScheme.primary,
                  grid: theme.colorScheme.outlineVariant,
                  muted: theme.colorScheme.onSurfaceVariant,
                  background: theme.colorScheme.surface,
                  labelStyle:
                      theme.textTheme.labelSmall ??
                      const TextStyle(fontSize: 11),
                  textDirection: Directionality.of(context),
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        // A legend only once there are two series to tell apart.
        if (baseline != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _LegendEntry(color: theme.colorScheme.primary, label: mine),
                _LegendEntry(
                  color: theme.colorScheme.onSurfaceVariant,
                  label: t(InsightsKeys.fingerprintAverage),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A swatch and the series it names.
class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter({
    required this.you,
    required this.average,
    required this.labels,
    required this.accent,
    required this.grid,
    required this.muted,
    required this.background,
    required this.labelStyle,
    required this.textDirection,
  });

  final List<double> you;
  final List<double>? average;
  final List<String> labels;
  final Color accent;
  final Color grid;
  final Color muted;
  final Color background;
  final TextStyle labelStyle;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // The margin is what the axis labels live in: the web reserves 56px either side and 28/24
    // top and bottom for exactly the same reason (charts.tsx:1316).
    final radius = math.min(size.width / 2 - 56, size.height / 2 - 26);
    if (radius <= 0) return;

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = grid;

    // Three linear rings plus the spokes: enough to read a level off, few enough not to become a
    // texture behind the data.
    for (var level = 1; level <= 3; level++) {
      canvas.drawPath(
        _polygon(center, radius * level / 3, you.length),
        gridPaint,
      );
    }
    for (var i = 0; i < you.length; i++) {
      canvas.drawLine(
        center,
        _point(center, radius, i, you.length, 1),
        gridPaint,
      );
    }

    if (average case final baseline?) {
      _series(canvas, center, radius, baseline, muted, dots: false);
    }
    _series(canvas, center, radius, you, accent, dots: true);

    for (var i = 0; i < labels.length; i++) {
      _label(canvas, center, radius, i, labels[i]);
    }
  }

  Path _polygon(Offset center, double radius, int axes) {
    final path = Path();
    for (var i = 0; i < axes; i++) {
      final point = _point(center, radius, i, axes, 1);
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  /// Axis `i`'s point at `value` of full scale. Axis zero points straight up, which is what makes
  /// two fingerprints comparable at a glance.
  Offset _point(Offset center, double radius, int i, int axes, double value) {
    final angle = -math.pi / 2 + i * 2 * math.pi / axes;
    return center + Offset(math.cos(angle), math.sin(angle)) * (radius * value);
  }

  void _series(
    Canvas canvas,
    Offset center,
    double radius,
    List<double> values,
    Color color, {
    required bool dots,
  }) {
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final point = _point(center, radius, i, values.length, values[i]);
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas
      ..drawPath(path, Paint()..color = color.withValues(alpha: 0.15))
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      );
    // Dots only on "you" — the grey baseline is context, not a second series to walk point by
    // point, and five more markers on top of it only makes the pair harder to separate.
    if (!dots) return;
    for (var i = 0; i < values.length; i++) {
      final point = _point(center, radius, i, values.length, values[i]);
      canvas
        ..drawCircle(point, 3.5, Paint()..color = color)
        ..drawCircle(
          point,
          3.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = background,
        );
    }
  }

  void _label(Canvas canvas, Offset center, double radius, int i, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: labelStyle.copyWith(color: muted),
      ),
      textDirection: textDirection,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 72);
    final anchor = _point(center, radius + 12, i, labels.length, 1);
    // Anchored by the side of the box that faces the figure, so a label never sits on top of the
    // polygon it belongs to: left of centre pulls its right edge in, and vice versa.
    final dx = anchor.dx < center.dx - 1
        ? anchor.dx - painter.width
        : anchor.dx > center.dx + 1
        ? anchor.dx
        : anchor.dx - painter.width / 2;
    final dy = anchor.dy < center.dy ? anchor.dy - painter.height : anchor.dy;
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.you != you ||
      old.average != average ||
      old.labels != labels ||
      old.accent != accent;
}

/// One ring of the music ratio: what it counts, how many, and how it moved.
@immutable
class RatioItem {
  const RatioItem({
    required this.label,
    required this.value,
    this.compared,
    this.showDelta = true,
  });

  final String label;
  final int value;
  final Compared? compared;
  final bool showDelta;
}

/// Distinct tracks / albums / artists as concentric rings — the "music ratio" at a glance.
///
/// All three rings share one scale (the largest count, tracks, is the full sweep), every share the
/// legend prints is value / tracks — bounded at 100% by construction — and the caption says exactly
/// that, so no number can wander outside the figure or arrive unexplained. One hue at opacity
/// steps: ring position plus the labelled legend carry identity, so no categorical hues are spent.
class MusicRatioRings extends ConsumerWidget {
  const MusicRatioRings({
    required this.items,
    required this.ariaLabel,
    super.key,
  });

  /// Largest (outermost) first; at most three entries.
  final List<RatioItem> items;

  final String ariaLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;
    final theme = Theme.of(context);
    final base = items.isEmpty ? null : items.first;
    // Nothing to scale against: every ring would be a full sweep of zero, which draws as three
    // empty tracks and says less than the stat tiles above already do.
    if (base == null || base.value == 0) return const SizedBox.shrink();

    final accent = theme.colorScheme.primary;
    final ringColors = [
      accent,
      accent.withValues(alpha: 0.6),
      accent.withValues(alpha: 0.35),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Semantics(
                label: ariaLabel,
                image: true,
                child: SizedBox(
                  width: 132,
                  height: 132,
                  child: CustomPaint(
                    painter: _RingsPainter(
                      values: [for (final item in items) item.value],
                      max: base.value,
                      colors: ringColors,
                      track: accent.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (index, item) in items.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: ringColors[index % ringColors.length],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                index == 0
                                    ? item.label
                                    : '${item.label} '
                                          '${t(InsightsKeys.ratioShareOfTracks, {'pct': _percent(item.value / base.value, locale)})}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${item.value}',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (item.showDelta ? item.compared?.change : null
                                case final change?) ...[
                              const SizedBox(width: 6),
                              DeltaLabel(change: change),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // The plain statement of what the rings are, so the figure never needs decoding.
          Text(
            t(InsightsKeys.ratioCaption, {'count': base.value}),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter({
    required this.values,
    required this.max,
    required this.colors,
    required this.track,
  });

  final List<int> values;
  final int max;
  final List<Color> colors;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outer = math.min(size.width, size.height) / 2;
    const stroke = 14.0;
    const gap = 5.0;
    for (var i = 0; i < values.length; i++) {
      final radius = outer - stroke / 2 - i * (stroke + gap);
      if (radius <= stroke / 2) break;
      final rect = Rect.fromCircle(center: center, radius: radius);
      final base = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track;
      // The full circle behind each arc is what makes "17 of 97" legible: the ring is read as a
      // fraction of its own track, not against whichever neighbour happens to sit outside it.
      canvas.drawArc(rect, 0, 2 * math.pi, false, base);
      final sweep = max == 0 ? 0.0 : (values[i] / max).clamp(0.0, 1.0);
      if (sweep == 0) continue;
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = colors[i % colors.length],
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.values != values || old.max != max || old.colors != colors;
}

/// One time bucket of the folded genre trend.
@immutable
class _StreamPoint {
  const _StreamPoint(this.values);

  /// Parallel to the kept-genre list, with a trailing "other" slot when genres folded.
  final List<int> values;
}

/// Genre share over time as a stacked flowing area.
///
/// Band thickness carries plays and the stack is centred, so total volume reads as the stream's
/// width. Series colours are the fixed categorical slots with rank one at the bottom, and the
/// folded tail rides on top in grey. The web labels each band in place where it is thickest; at
/// 375px there is no band thick enough to hold a word, so the legend under the figure carries
/// every name instead.
class GenreFlow extends ConsumerWidget {
  const GenreFlow({
    required this.trend,
    required this.granularity,
    required this.windowStart,
    required this.windowEnd,
    super.key,
  });

  final GenreTrend trend;
  final BucketGranularity granularity;
  final int windowStart;
  final int windowEnd;

  /// Named genre bands, the size of the fixed categorical palette. Genres past this fold into the
  /// grey "other" tail so the legend never implies more hues than the ink shows.
  static const _slots = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final folded = _fold();
    final points = folded.points;
    final hasInk = points.any((p) => p.values.any((v) => v > 0));
    if (!hasInk) {
      return ReportEmpty(title: t(InsightsKeys.genreFlowEmpty));
    }

    final colors = [
      for (var i = 0; i < folded.names.length; i++)
        _categorical[i % _categorical.length],
      if (folded.hasOther) theme.colorScheme.onSurfaceVariant,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Semantics(
            label: t(InsightsKeys.genreFlowAriaLabel),
            image: true,
            child: SizedBox(
              height: 160,
              child: CustomPaint(
                painter: _StreamPainter(points: points, colors: colors),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              for (final (index, name) in folded.names.indexed)
                _LegendEntry(color: colors[index], label: titleCaseGenre(name)),
              if (folded.hasOther)
                _LegendEntry(
                  color: colors.last,
                  label: folded.foldedNamed == 0
                      ? t(InsightsKeys.genreFlowOther)
                      : t(InsightsKeys.genreFlowOtherCount, {
                          'count': folded.foldedNamed,
                        }),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Fold the server's genre trend down to the palette's slots, densified to the whole window.
  ///
  /// Silent stretches have to be explicit zero vectors rather than missing buckets: without them
  /// a fortnight of silence is squeezed out and the stream reads as continuous listening.
  ({
    List<String> names,
    int foldedNamed,
    bool hasOther,
    List<_StreamPoint> points,
  })
  _fold() {
    // The server's genre list ends with its literal "other" entry (plays whose album has no top
    // genre), so the named genres are everything before it.
    final namedCount = math.max(trend.genres.length - 1, 0);
    final keep = math.min(_slots, namedCount);
    final names = trend.genres.take(keep).toList();
    final foldedNamed = namedCount - keep;

    List<int> fold(List<int> plays) => [
      for (var i = 0; i < keep; i++) i < plays.length ? plays[i] : 0,
      plays.skip(keep).fold(0, (sum, v) => sum + v),
    ];

    if (trend.buckets.isEmpty) {
      return (
        names: names,
        foldedNamed: foldedNamed,
        hasOther: false,
        points: [],
      );
    }

    var points = <_StreamPoint>[];
    if (granularity == BucketGranularity.month) {
      final first = _calendarDay(trend.buckets.first.start);
      final last = _calendarDay(windowEnd - _dayMs);
      final months =
          (last.year - first.year) * 12 + (last.month - first.month) + 1;
      points = [
        for (var i = 0; i < math.max(months, 1); i++)
          _StreamPoint(List.filled(keep + 1, 0)),
      ];
      for (final bucket in trend.buckets) {
        final at = _calendarDay(bucket.start);
        final index = (at.year - first.year) * 12 + (at.month - first.month);
        if (index >= 0 && index < points.length) {
          points[index] = _StreamPoint(fold(bucket.plays));
        }
      }
    } else {
      final days = math.max(1, ((windowEnd - windowStart) / _dayMs).round());
      points = [
        for (var i = 0; i < days; i++) _StreamPoint(List.filled(keep + 1, 0)),
      ];
      for (final bucket in trend.buckets) {
        final index = ((bucket.start - windowStart) / _dayMs).round();
        if (index >= 0 && index < points.length) {
          points[index] = _StreamPoint(fold(bucket.plays));
        }
      }
      // A daily series past about nine weeks is spikes rather than flow, so it aggregates to
      // weeks — the same threshold the web uses.
      if (points.length > 66) {
        final weeks = <_StreamPoint>[];
        for (var i = 0; i < points.length; i += 7) {
          final chunk = points.skip(i).take(7);
          final sum = List.filled(keep + 1, 0);
          for (final point in chunk) {
            for (var j = 0; j < sum.length; j++) {
              sum[j] += point.values[j];
            }
          }
          weeks.add(_StreamPoint(sum));
        }
        points = weeks;
      }
    }

    // Drop the tail slot when it never has ink — a legend entry for an invisible band would
    // re-create the very more-names-than-colours confusion this fold exists to fix.
    final hasOther = points.any((p) => p.values[keep] > 0);
    if (!hasOther) {
      points = [
        for (final point in points)
          _StreamPoint(point.values.take(keep).toList()),
      ];
    }
    return (
      names: names,
      foldedNamed: foldedNamed,
      hasOther: hasOther,
      points: points,
    );
  }
}

class _StreamPainter extends CustomPainter {
  const _StreamPainter({required this.points, required this.colors});

  final List<_StreamPoint> points;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final bands = points.first.values.length;
    final totals = [
      for (final point in points) point.values.fold(0, (sum, v) => sum + v),
    ];
    final peak = totals.fold<int>(0, math.max);
    if (peak == 0) return;
    final scale = size.height / peak;
    final step = size.width / (points.length - 1);

    // Rank one at the bottom, so the strongest band sits on the floor of the stream and the tail
    // rides on top: accumulating from the top in reverse order is what puts it there.
    final tops = [
      for (var i = 0; i < points.length; i++) _baseline(totals[i], size, scale),
    ];
    for (var band = bands - 1; band >= 0; band--) {
      final path = Path();
      final upper = <double>[];
      for (var i = 0; i < points.length; i++) {
        upper.add(tops[i]);
        final y = tops[i];
        i == 0 ? path.moveTo(0, y) : path.lineTo(i * step, y);
      }
      for (var i = points.length - 1; i >= 0; i--) {
        tops[i] = upper[i] + points[i].values[band] * scale;
        path.lineTo(i * step, tops[i]);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = colors[band % colors.length]);
    }
  }

  double _baseline(int total, Size size, double scale) =>
      size.height / 2 - total * scale / 2;

  @override
  bool shouldRepaint(_StreamPainter old) =>
      old.points != points || old.colors != colors;
}

/// Local listening intensity across all seven weekdays and 24 hours.
class ClockGridHeatmap extends ConsumerWidget {
  const ClockGridHeatmap({required this.grid, super.key});

  final ClockGrid grid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;
    final theme = Theme.of(context);
    final cells = [
      for (var i = 0; i < 7 * 24; i++)
        i < grid.cells.length ? grid.cells[i] : 0,
    ];
    final total = cells.fold(0, (sum, v) => sum + v);
    if (total == 0) {
      return ReportEmpty(title: t(InsightsKeys.chartNoActivityYet));
    }
    final peak = grid.peak ?? cells.fold<int>(1, math.max);
    final peakIndex = cells.indexOf(peak);
    final ramp = _intensityRamp(theme, const [0.15, 0.3, 0.45, 0.6, 0.8, 1]);
    final hour = DateFormat.j(locale);
    String hourLabel(int of) => hour.format(DateTime(2000, 1, 1, of));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Semantics(
            label: t(InsightsKeys.clockGridAriaLabel, {
              'timezone': grid.timezone,
            }),
            image: true,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 34px of gutter for the weekday names, then whatever is left divided 24 ways —
                // about 13px a cell on a phone, which is the smallest square that still reads as
                // a square rather than as a dotted line.
                const gutter = 34.0;
                final cell = ((constraints.maxWidth - gutter) / 24).clamp(
                  6.0,
                  20.0,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Four hour ticks, not 24: the grid is read for its shape, and a label under
                    // every column at 13px is a grey smear.
                    SizedBox(
                      height: 16,
                      child: Row(
                        children: [
                          const SizedBox(width: gutter),
                          for (final tick in const [0, 6, 12, 18])
                            SizedBox(
                              width: cell * 6,
                              child: Text(
                                hourLabel(tick),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    for (var day = 0; day < 7; day++)
                      Row(
                        children: [
                          SizedBox(
                            width: gutter,
                            child: Text(
                              weekdayLabel(day, t),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          for (var of = 0; of < 24; of++)
                            Padding(
                              padding: const EdgeInsets.all(0.75),
                              child: Container(
                                width: cell - 1.5,
                                height: cell - 1.5,
                                decoration: BoxDecoration(
                                  color:
                                      ramp[_level(
                                        cells[day * 24 + of],
                                        peak,
                                        ramp.length - 1,
                                      )],
                                  borderRadius: ChordiaRadius.markAll,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t(InsightsKeys.clockGridBusiest, {
                    'day': weekdayLabel(peakIndex ~/ 24, t),
                    'hour': hourLabel(peakIndex % 24),
                  }),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              IntensityKey(colors: ramp),
            ],
          ),
        ),
      ],
    );
  }
}

/// A calendar of the window: one column per week, one cell per day, shaded by play count.
///
/// Drawn at a fixed cell size and scrolled sideways when the window outgrows the screen, so a
/// quarter never balloons into giant cells and a year never shrinks its labels into fuzz. This is
/// the view a long window gets instead of the activity bars: 365 stacked rows is a scroll, not a
/// chart, and truncating them to the last 30 answers a question nobody asked.
class CalendarHeatmap extends ConsumerWidget {
  const CalendarHeatmap({
    required this.buckets,
    required this.windowStart,
    required this.windowEnd,
    super.key,
  });

  final List<TimeBucket> buckets;
  final int windowStart;
  final int windowEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;
    final theme = Theme.of(context);
    final days = math.max(1, ((windowEnd - windowStart) / _dayMs).round());

    final plays = List.filled(days, 0);
    var totalPlays = 0;
    var activeDays = 0;
    for (final bucket in buckets) {
      final index = ((bucket.start - windowStart) / _dayMs).round();
      if (index < 0 || index >= days || bucket.plays == 0) continue;
      plays[index] = bucket.plays;
      totalPlays += bucket.plays;
      activeDays += 1;
    }
    if (totalPlays == 0) {
      return ReportEmpty(title: t(InsightsKeys.chartNoActivityPeriod));
    }

    final ramp = _intensityRamp(theme, const [0.25, 0.45, 0.7, 1]);
    final peak = plays.fold<int>(1, math.max);
    // Sunday is row zero, matching the weekday vectors the rest of the reports use.
    final startDow = _calendarDay(windowStart).weekday % 7;
    final weeks = ((startDow + days) / 7).ceil();
    const cell = 13.0;
    const pitch = cell + 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Semantics(
            label: t(InsightsKeys.heatmapAriaLabel),
            image: true,
            child: CustomPaint(
              size: Size(32 + weeks * pitch, 22 + 7 * pitch),
              painter: _CalendarPainter(
                plays: plays,
                peak: peak,
                startDow: startDow,
                windowStart: windowStart,
                ramp: ramp,
                month: DateFormat.MMM(locale),
                weekdays: [for (var d = 0; d < 7; d++) weekdayLabel(d, t)],
                labelStyle:
                    (theme.textTheme.labelSmall ??
                            const TextStyle(fontSize: 11))
                        .copyWith(color: theme.colorScheme.onSurfaceVariant),
                textDirection: Directionality.of(context),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t(InsightsKeys.heatmapSummary, {
                    'count': totalPlays,
                    'days': activeDays,
                  }),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              IntensityKey(colors: ramp),
            ],
          ),
        ),
      ],
    );
  }
}

class _CalendarPainter extends CustomPainter {
  const _CalendarPainter({
    required this.plays,
    required this.peak,
    required this.startDow,
    required this.windowStart,
    required this.ramp,
    required this.month,
    required this.weekdays,
    required this.labelStyle,
    required this.textDirection,
  });

  final List<int> plays;
  final int peak;
  final int startDow;
  final int windowStart;
  final List<Color> ramp;
  final DateFormat month;
  final List<String> weekdays;
  final TextStyle labelStyle;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 13.0;
    const pitch = cell + 2;
    const left = 32.0;
    const top = 22.0;

    // Mon/Wed/Fri only: seven row labels at 13px is noise, and three is enough to orient by.
    for (final dow in const [1, 3, 5]) {
      _text(canvas, weekdays[dow], Offset(0, top + dow * pitch));
    }

    var lastMonth = -1;
    for (var index = 0; index < plays.length; index++) {
      final slot = startDow + index;
      final week = slot ~/ 7;
      final dow = slot % 7;
      final x = left + week * pitch;
      final y = top + dow * pitch;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, cell, cell),
          const Radius.circular(ChordiaRadius.mark),
        ),
        Paint()..color = ramp[_level(plays[index], peak, ramp.length - 1)],
      );
      // One month label per month, printed above the week column the month starts in.
      final day = _calendarDay(windowStart + index * _dayMs);
      if (day.month != lastMonth && (index == 0 || dow == 0)) {
        lastMonth = day.month;
        _text(canvas, month.format(day), Offset(x, 4));
      }
    }
  }

  void _text(Canvas canvas, String text, Offset at) {
    TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: textDirection,
        maxLines: 1,
      )
      ..layout()
      ..paint(canvas, at);
  }

  @override
  bool shouldRepaint(_CalendarPainter old) =>
      old.plays != plays || old.peak != peak || old.ramp != ramp;
}

/// "Less to more" key for a sequential colour ramp, shared by both heatmaps.
class IntensityKey extends ConsumerWidget {
  const IntensityKey({required this.colors, super.key});

  final List<Color> colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Semantics(
      label: t(InsightsKeys.heatmapScaleAriaLabel),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t(InsightsKeys.heatmapLess), style: style),
          const SizedBox(width: 6),
          for (final color in colors)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: ChordiaRadius.markAll,
                ),
              ),
            ),
          const SizedBox(width: 6),
          Text(t(InsightsKeys.heatmapMore), style: style),
        ],
      ),
    );
  }
}

/// The empty step plus an accent-alpha ramp: one hue, light to dark, never a rainbow.
List<Color> _intensityRamp(ThemeData theme, List<double> alphas) => [
  theme.colorScheme.surfaceContainerHigh,
  for (final alpha in alphas)
    alpha >= 1
        ? theme.colorScheme.primary
        : theme.colorScheme.primary.withValues(alpha: alpha),
];

/// Which step of a ramp a count falls on. Zero is always the empty step, and anything above it
/// gets at least step one — a single play must not render as silence.
int _level(int plays, int peak, int steps) {
  if (plays <= 0 || peak <= 0) return 0;
  return math.min((plays / peak * steps).ceil(), steps);
}

/// The calendar day a bucket start belongs to.
///
/// Bucket starts are local midnights the Hub already truncated in the report's timezone, so they
/// are read back as wall-clock values rather than converted again: probing at midday is what keeps
/// a DST hour from moving a day across its boundary.
DateTime _calendarDay(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms + _dayMs ~/ 2, isUtc: true);
