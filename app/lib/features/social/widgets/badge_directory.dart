import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart' show hubClientProvider;
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/surface.dart';
import '../../../widgets/tokens.dart';
import '../../catalog/widgets/catalog_state.dart';
import 'badge_art.dart';

/// Every badge this instance can grant, who holds it, and how it is earned.
///
/// Riverpod 3 retries an errored provider on its own; switched off for the reason every other
/// read-and-retry screen switches it off — the page draws a Retry button, and a background retry
/// contradicts it while leaving a pending timer behind in widget tests.
final badgeCatalogProvider = FutureProvider<List<BadgeCatalogEntry>>((ref) {
  final hub = ref.watch(hubClientProvider);
  if (hub == null) throw StateError('No hub session to read badges from.');
  return hub.badges();
}, retry: (attempt, error) => null);

/// Opens the directory over whatever raised it, landing on [highlightKind] when one is named.
///
/// A plain `MaterialPageRoute`, for the reason `showEntityStats` gives: a badge can be tapped on a
/// profile sitting in ANY of the four tabs, so pushing onto the branch's own navigator keeps that
/// tab's back stack without the route table having to exist four times. The web's equivalent is
/// `/app/badges?kind=…`, deep-linked so the badge you tapped is the one you land on.
Future<void> showBadgeDirectory(
  BuildContext context, {
  String? highlightKind,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => BadgeDirectoryScreen(highlightKind: highlightKind),
  ),
);

/// The badge catalogue: the web's `/app/badges`.
///
/// The phone had the art, the names and the explanations already — worn on profiles — and no page
/// that listed them. Which meant the questions the directory answers ("what else is there", "how
/// would I get one") had no answer at all here, and the badge chips were a dead end.
class BadgeDirectoryScreen extends ConsumerStatefulWidget {
  const BadgeDirectoryScreen({super.key, this.highlightKind});

  /// The kind to ring and scroll to, when this was opened from a badge rather than from a menu.
  final String? highlightKind;

  @override
  ConsumerState<BadgeDirectoryScreen> createState() =>
      _BadgeDirectoryScreenState();
}

class _BadgeDirectoryScreenState extends ConsumerState<BadgeDirectoryScreen> {
  final _highlighted = GlobalKey();

  /// Once, not on every build: this scroll is an arrival gesture, and repeating it would fight the
  /// reader the first time they scrolled away.
  bool _scrolled = false;

  void _revealHighlighted() {
    if (_scrolled) return;
    final target = _highlighted.currentContext;
    if (target == null) return;
    _scrolled = true;
    // Centred, which is safe here in a way it is not inside a tab rail: this element IS the thing
    // the page was opened to show. Instant rather than animated — the reader asked for this card,
    // and a scroll they did not start is disorienting when they can watch it happen.
    Scrollable.ensureVisible(target, alignment: 0.5, duration: Duration.zero);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealHighlighted());

    return Scaffold(
      appBar: AppBar(title: Text(t(SocialKeys.badgesDirectoryTitle))),
      body: CatalogBody<List<BadgeCatalogEntry>>(
        value: ref.watch(badgeCatalogProvider),
        errorTitle: t(SocialKeys.badgesDirectoryTitle),
        onRetry: () => ref.invalidate(badgeCatalogProvider),
        skeleton: const CatalogDetailSkeleton(),
        builder: (context, entries) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              t(SocialKeys.badgesDirectorySubtitle),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            for (final entry in entries)
              // A kind this build has never heard of is skipped rather than drawn: its name, its
              // explanation and its art all come from local tables, so a newer Hub's badge would
              // render as three raw i18n keys under an empty square.
              if (representativeBadge(entry.kind) case final badge?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _BadgeCard(
                    key: entry.kind == widget.highlightKind
                        ? _highlighted
                        : null,
                    entry: entry,
                    art: badge,
                    highlighted: entry.kind == widget.highlightKind,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// A badge, everything known about it, and how it grew.
class _BadgeCard extends ConsumerWidget {
  const _BadgeCard({
    required this.entry,
    required this.art,
    required this.highlighted,
    super.key,
  });

  final BadgeCatalogEntry entry;

  /// The badge as it is worn, with a representative value where one is engraved. Rendered from the
  /// real painter rather than from a picture of it, so a badge cannot look one way in the directory
  /// that explains it and another way on the profile that wears it.
  final ProfileBadge art;

  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Container(
      // The ring the web draws around the deep-linked card. Two pixels are reserved whether or not
      // it is drawn, so an arriving highlight cannot shift the rest of the list sideways.
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: ChordiaRadius.xlAll,
        border: Border.all(
          color: highlighted ? theme.colorScheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: IslandPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BadgeArt(badge: art, size: 72),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t(badgeNameKey(entry.kind)),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _Availability(obtainable: entry.obtainable),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(t(badgeAboutKey(entry.kind)), style: muted),
            const SizedBox(height: 8),
            // "How to get it: …" as one paragraph with the label muted, which is the web's shape
            // (`badges.tsx:120-127`) — the instruction reads as prose, not as a field.
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${t(SocialKeys.badgesDirectoryHowTo)} ',
                    style: muted,
                  ),
                  TextSpan(text: t(badgeEarnKey(entry.kind))),
                ],
              ),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(_counts(entry, ref), style: muted),
            if (entry.kind == 'super_sonic') ...[
              const SizedBox(height: 12),
              const _Stages(),
            ],
            const SizedBox(height: 12),
            _History(entry: entry),
          ],
        ),
      ),
    );
  }

  /// Holders, plus the two facts that only apply to a badge running out: how many are left, and
  /// the date after which nobody else can have one.
  String _counts(BadgeCatalogEntry entry, WidgetRef ref) {
    final t = ref.t;
    final parts = [
      t(SocialKeys.badgesDirectoryHolders, {'count': entry.holders}),
      if (entry.remaining case final remaining?)
        t(SocialKeys.badgesDirectoryRemaining, {'count': remaining}),
      if (entry.availableUntil case final until?)
        t(SocialKeys.badgesDirectoryUntil, {
          'date': DateFormat.yMMMd(
            ref.watch(translationsProvider).locale,
          ).format(DateTime.fromMillisecondsSinceEpoch(until)),
        }),
    ];
    return parts.join(' · ');
  }
}

/// Whether a reader could still go and earn this one.
class _Availability extends ConsumerWidget {
  const _Availability({required this.obtainable});

  final bool obtainable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colour = obtainable
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          obtainable
              ? PhosphorIcons.checkCircle(PhosphorIconsStyle.fill)
              : PhosphorIcons.lockSimple(),
          size: 14,
          color: colour,
        ),
        const SizedBox(width: 4),
        Text(
          ref.t(
            obtainable
                ? SocialKeys.badgesDirectoryOpen
                : SocialKeys.badgesDirectoryClosed,
          ),
          style: theme.textTheme.labelSmall?.copyWith(color: colour),
        ),
      ],
    );
  }
}

/// Every stage of the Super-Sonic badge, with what each one costs in months.
///
/// For the one badge that CHANGES, a single picture answers neither of the directory's questions:
/// somebody holding Orbit had no way to see what Nova looks like, and somebody deciding whether to
/// subscribe could not see that the badge grows at all. Painted at each threshold from the real
/// painter, so a change to the art cannot leave this showing a badge that no longer exists.
class _Stages extends ConsumerWidget {
  const _Stages();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RuledLabel(text: t(SocialKeys.badgesDirectoryStages)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            for (final stage in superSonicStages)
              SizedBox(
                width: 64,
                child: Column(
                  children: [
                    // The threshold itself, not one month past it — this is the badge as it looks
                    // the moment the stage is reached.
                    BadgeArt(
                      badge: ProfileBadgeSuperSonic(
                        since: 0,
                        streakMonths: stage.minMonths,
                      ),
                      size: 44,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t(stageNameKey(stage.key)),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall,
                    ),
                    Text(
                      stage.minMonths == 0
                          ? t(SocialKeys.badgesDirectoryStageFromStart)
                          : t(SocialKeys.badgesDirectoryStageMonths, {
                              'count': stage.minMonths,
                            }),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Cumulative holders over time, or the honest reason there is no line.
class _History extends ConsumerWidget {
  const _History({required this.entry});

  final BadgeCatalogEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final points = entry.history ?? const <BadgeCountPoint>[];
    if (points.length < 2) {
      // Two different answers, and conflating them would be the lie: nobody has earned it yet,
      // versus the instance never recorded when they did. A tier badge stores only when its
      // holder's CURRENT streak began, so it moves when they lapse and rejoin.
      final untracked = entry.kind == 'sonic' || entry.kind == 'super_sonic';
      return Text(
        t(
          untracked
              ? SocialKeys.badgesDirectoryNoHistoryUntracked
              : SocialKeys.badgesDirectoryNoHistoryTooFew,
        ),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RuledLabel(text: t(SocialKeys.badgesDirectoryOverTime)),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          width: double.infinity,
          child: CustomPaint(
            painter: _HoldersPainter(
              points: points,
              colour: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        // The axis, said in words. There is no room at this width for tick labels, and the two
        // dates plus the peak are the whole of what the line says.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              points.first.day,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              points.last.day,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A hairline with a small uppercase label under it — the web's `border-t pt-3` section divider.
class _RuledLabel extends StatelessWidget {
  const _RuledLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 8),
        Text(
          text.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

/// The holders line: stepped, filled, no points.
///
/// A cumulative count only ever steps UP, on the day somebody earned one — so a stepped line is the
/// honest shape. A smoothed curve would imply holders arriving between the days they arrived on,
/// which is the same objection the web's `curve="stepAfter"` records.
class _HoldersPainter extends CustomPainter {
  const _HoldersPainter({required this.points, required this.colour});

  final List<BadgeCountPoint> points;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final peak = points.map((p) => p.holders).reduce((a, b) => a > b ? a : b);
    // The baseline is zero, not the minimum: a count that starts at three and ends at four is a
    // near-flat line, and stretching it to fill the box would draw it as a fourfold rise.
    final span = peak <= 0 ? 1 : peak;
    final stepX = points.length == 1 ? 0.0 : size.width / (points.length - 1);
    double y(int holders) => size.height * (1 - holders / span);

    final line = Path()..moveTo(0, y(points.first.holders));
    for (var i = 1; i < points.length; i++) {
      final x = stepX * i;
      // Along at the old level, then up: the step lands ON the day, not before it.
      line
        ..lineTo(x, y(points[i - 1].holders))
        ..lineTo(x, y(points[i].holders));
    }

    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas
      ..drawPath(area, Paint()..color = colour.withValues(alpha: 0.12))
      ..drawPath(
        line,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_HoldersPainter old) =>
      old.points != points || old.colour != colour;
}

/// A badge's art with no holder behind it.
///
/// The two badges that engrave something holder-specific get a representative value: the founding
/// hundred shows rank 1 and Super-Sonic shows its first stage. Null for a kind this build does not
/// know, which is the honest answer — every string and every stroke that would describe it lives
/// in a local table.
ProfileBadge? representativeBadge(String kind) => switch (kind) {
  'developer' => const ProfileBadgeDeveloper(title: 'Developer'),
  'staff' => const ProfileBadgeStaff(role: StaffRole.admin),
  'translator' => const ProfileBadgeTranslator(),
  'early_bird' => const ProfileBadgeEarlyBird(joinedAt: 0),
  'early_supporter' => const ProfileBadgeEarlySupporter(rank: 1, since: 0),
  'sonic' => const ProfileBadgeSonic(since: 0, streakMonths: 0),
  'super_sonic' => const ProfileBadgeSuperSonic(since: 0, streakMonths: 0),
  _ => null,
};

/// The badge's own name, keyed by wire kind rather than by variant — the directory holds a `kind`
/// string and nothing else.
String badgeNameKey(String kind) => switch (kind) {
  'developer' => SocialKeys.badgesDirectoryNameDeveloper,
  'staff' => SocialKeys.badgesDirectoryNameStaff,
  'translator' => SocialKeys.badgesDirectoryNameTranslator,
  'early_bird' => SocialKeys.badgesDirectoryNameEarlyBird,
  'early_supporter' => SocialKeys.badgesDirectoryNameEarlySupporter,
  'sonic' => SocialKeys.badgesDirectoryNameSonic,
  _ => SocialKeys.badgesDirectoryNameSuperSonic,
};

/// What the badge is for.
String badgeAboutKey(String kind) => switch (kind) {
  'developer' => SocialKeys.badgesAboutDeveloper,
  'staff' => SocialKeys.badgesAboutStaff,
  'translator' => SocialKeys.badgesAboutTranslator,
  'early_bird' => SocialKeys.badgesAboutEarlyBird,
  'early_supporter' => SocialKeys.badgesAboutEarlySupporter,
  'sonic' => SocialKeys.badgesAboutSonic,
  _ => SocialKeys.badgesAboutSuperSonic,
};

/// How somebody would come to have it — the half a profile can never tell you.
String badgeEarnKey(String kind) => switch (kind) {
  'developer' => SocialKeys.badgesDirectoryEarnDeveloper,
  'staff' => SocialKeys.badgesDirectoryEarnStaff,
  'translator' => SocialKeys.badgesDirectoryEarnTranslator,
  'early_bird' => SocialKeys.badgesDirectoryEarnEarlyBird,
  'early_supporter' => SocialKeys.badgesDirectoryEarnEarlySupporter,
  'sonic' => SocialKeys.badgesDirectoryEarnSonic,
  _ => SocialKeys.badgesDirectoryEarnSuperSonic,
};

/// One Super-Sonic stage's name.
String stageNameKey(String key) => switch (key) {
  'spark' => SocialKeys.badgesStageSpark,
  'orbit' => SocialKeys.badgesStageOrbit,
  'nova' => SocialKeys.badgesStageNova,
  _ => SocialKeys.badgesStageDiamond,
};
