import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import 'badge_art.dart';

/// Somebody's picture, or their initial.
///
/// Uploaded avatars are Hub-hosted (`/v1/images/{hash}`) and go through [CoverArt], which fetches
/// once at a width the Hub derives and then reads off disk. An avatar that is an **external**
/// address — a Discord CDN URL on a Discord-linked account — has no content hash, so there is
/// nothing to cache it by and no pinned client that should be opening a socket to a third party;
/// those fall back to the monogram, exactly as every other external image in this app does.
class UserAvatar extends StatelessWidget {
  const UserAvatar({required this.user, super.key, this.size = 40});

  final PublicUser user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hash = artHashOf(user.avatarUrl);
    if (hash != null) {
      return CoverArt(
        sha256: hash,
        size: size,
        shape: BoxShape.circle,
        fallbackIcon: Icons.person_rounded,
        semanticLabel: user.displayName,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    // By rune, not by index: `substring(0, 1)` cuts an emoji or an astral character in half and
    // renders a replacement glyph.
    final initial = user.displayName.runes.isEmpty
        ? '?'
        : String.fromCharCode(user.displayName.runes.first).toUpperCase();
    return Semantics(
      label: user.displayName,
      image: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primaryContainer,
        ),
        child: Text(
          initial,
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.42,
          ),
        ),
      ),
    );
  }
}

/// A display name, painted in the account's flair when it has one.
///
/// Flair is a paid cosmetic, so the one place it is meant to be visible is wherever a name is —
/// rendering the raw string here would make the feature invisible. Colours arrive as CSS strings
/// the Hub never normalises; anything this parser does not understand falls back to the ordinary
/// text colour rather than to a guess.
class DisplayName extends StatelessWidget {
  const DisplayName({
    required this.name,
    super.key,
    this.flair,
    this.style,
    this.maxLines = 1,
  });

  final String name;
  final UserFlair? flair;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final stops = <Color>[
      for (final raw in flair?.gradient ?? const <String>[])
        if (parseCssColor(raw) case final Color colour) colour,
    ];
    final accent = parseCssColor(flair?.accent);

    final text = Text(
      name,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: stops.length >= 2 ? base : base.copyWith(color: accent),
    );
    if (stops.length < 2) return text;

    // A gradient name is drawn by tinting the glyphs rather than by stacking coloured spans, so it
    // still ellipsises and still lays out as one run of text.
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) =>
          LinearGradient(colors: stops).createShader(bounds),
      child: text,
    );
  }
}

/// A CSS colour string as a Flutter colour, or null when this build cannot read it.
///
/// Handles the two notations the Hub actually stores — `#rgb`/`#rrggbb`/`#rrggbbaa` and
/// `rgb()`/`rgba()`. Anything else (a named colour, `oklch()`, a var reference) returns null so the
/// caller can fall back, which is the honest outcome: inventing a colour for an unreadable flair
/// would show a paying user a flair they did not choose.
Color? parseCssColor(String? value) {
  if (value == null) return null;
  final raw = value.trim().toLowerCase();
  if (raw.startsWith('#')) {
    var hex = raw.substring(1);
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length == 6) hex = 'ff$hex';
    if (hex.length != 8) return null;
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }
  final match = RegExp(
    r'^rgba?\(\s*([\d.]+)[\s,]+([\d.]+)[\s,]+([\d.]+)\s*(?:[,/]\s*([\d.]+%?)\s*)?\)$',
  ).firstMatch(raw);
  if (match == null) return null;
  final channels = [
    for (var i = 1; i <= 3; i++) double.tryParse(match.group(i)!),
  ];
  if (channels.any((c) => c == null)) return null;
  return Color.from(
    alpha: _parseAlpha(match.group(4)),
    red: channels[0]!.clamp(0, 255).toDouble() / 255,
    green: channels[1]!.clamp(0, 255).toDouble() / 255,
    blue: channels[2]!.clamp(0, 255).toDouble() / 255,
  );
}

/// The alpha channel of an `rgba()`, which CSS writes either as `0..1` or as a percentage.
double _parseAlpha(String? text) {
  if (text == null) return 1;
  final percent = text.endsWith('%');
  final number = double.tryParse(
    percent ? text.substring(0, text.length - 1) : text,
  );
  if (number == null) return 1;
  return (percent ? number / 100 : number).clamp(0, 1).toDouble();
}

/// Display order, most specific first.
///
/// Identity before status: who someone IS on this instance (developer, staff) reads before what
/// they have done (early, supporting). The tier badges come last because they are the only ones
/// that can change every month, and a row whose leading item moves is a row that never looks
/// settled. The Hub sends them in whatever order it stored them, so without this a profile's
/// badges reshuffle between reads.
const _badgeOrder = [
  'developer',
  'staff',
  'translator',
  'early_supporter',
  'early_bird',
  'super_sonic',
  'sonic',
];

/// The badges an account carries, as a row of records.
///
/// Shown even on a withheld profile: a badge is identity, like the handle, and hiding it would make
/// a moderator unrecognisable on exactly the profile where knowing they are staff matters.
///
/// Tapping one explains it. The web hovers for that, which does not exist on a phone, and the
/// chip it replaced answered a tap with silence — so the detail the web puts in its hover card is
/// a sheet here, and it is the badge's only action.
class BadgeRow extends ConsumerWidget {
  const BadgeRow({
    required this.badges,
    super.key,
    this.alignment = WrapAlignment.start,
  });

  final List<ProfileBadge>? badges;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final held = [...?badges]
      ..sort(
        (a, b) =>
            _badgeOrder.indexOf(a.kind).compareTo(_badgeOrder.indexOf(b.kind)),
      );
    if (held.isEmpty) return const SizedBox.shrink();
    final t = ref.t;
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: alignment,
      children: [
        for (final badge in held)
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => showBadgeDetail(context, badge),
            child: Padding(
              // The badge art is 28px, which is below the touch minimum on its own; the padding is
              // what makes the whole chip the target rather than the disc.
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BadgeArt(badge: badge, size: 28),
                  const SizedBox(width: 6),
                  Text(
                    _badgeLabel(badge, t),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One badge, at a size where it can actually be read, beside what it means.
///
/// A badge at 28px is an identifier — you recognise which one it is, you cannot read it. This is
/// where the engraving, the rank number and the Super-Sonic stage rings are legible, and where the
/// three questions a badge on a stranger's profile raises get answered: which one is it, since
/// when, and why does this person have it.
Future<void> showBadgeDetail(BuildContext context, ProfileBadge badge) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _BadgeDetail(badge: badge),
    );

class _BadgeDetail extends ConsumerWidget {
  const _BadgeDetail({required this.badge});

  final ProfileBadge badge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final locale = ref.watch(translationsProvider).locale;
    final stage = badge is ProfileBadgeSuperSonic
        ? stageFor((badge as ProfileBadgeSuperSonic).streakMonths)
        : null;
    final detail = _badgeDetail(badge, t, locale);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                BadgeArt(badge: badge, size: 96),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _badgeLabel(badge, t),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (stage != null)
                        Text(
                          '${stage.stage}. ${t(_stageKey(stage.key))}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      if (detail != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          detail,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // What the badge is FOR. The title says which one it is and the detail says since
            // when; neither answers "why does this person have it".
            Text(
              t(_aboutKey(badge)),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _stageKey(String key) => switch (key) {
  'spark' => SocialKeys.badgesStageSpark,
  'orbit' => SocialKeys.badgesStageOrbit,
  'nova' => SocialKeys.badgesStageNova,
  _ => SocialKeys.badgesStageDiamond,
};

String _aboutKey(ProfileBadge badge) => switch (badge) {
  ProfileBadgeDeveloper() => SocialKeys.badgesAboutDeveloper,
  ProfileBadgeStaff() => SocialKeys.badgesAboutStaff,
  ProfileBadgeTranslator() => SocialKeys.badgesAboutTranslator,
  ProfileBadgeEarlyBird() => SocialKeys.badgesAboutEarlyBird,
  ProfileBadgeEarlySupporter() => SocialKeys.badgesAboutEarlySupporter,
  ProfileBadgeSonic() => SocialKeys.badgesAboutSonic,
  ProfileBadgeSuperSonic() => SocialKeys.badgesAboutSuperSonic,
};

/// The line under the title.
///
/// Every badge answers "since when", because that is the question a badge on a stranger's profile
/// actually raises, and because for the two premium ones the answer is the thing being rewarded.
String? _badgeDetail(
  ProfileBadge badge,
  String Function(String, [Map<String, Object?>]) t,
  String locale,
) {
  String date(int ms) =>
      DateFormat.yMMMd(locale).format(DateTime.fromMillisecondsSinceEpoch(ms));
  return switch (badge) {
    ProfileBadgeDeveloper(:final tagline) => tagline,
    ProfileBadgeStaff() => t(SocialKeys.badgesStaffDetail),
    // The languages ARE the detail, and the badge is not granted without them.
    ProfileBadgeTranslator(:final languages) => languages,
    // The position is the interesting half — "since June" is a fact, "the 41st account here" is
    // the claim. Falls back to the date alone when the Hub could not resolve a position.
    ProfileBadgeEarlyBird(:final joinedAt, :final position) =>
      position == null || position <= 0
          ? t(SocialKeys.badgesEarlyBirdDetail, {'date': date(joinedAt)})
          : t(SocialKeys.badgesEarlyBirdDetailRanked, {
              'position': position,
              'date': date(joinedAt),
            }),
    ProfileBadgeEarlySupporter(:final rank, :final since) => t(
      SocialKeys.badgesEarlySupporterDetail,
      {'rank': rank, 'date': date(since)},
    ),
    // The streak, not the total. It resets if a subscription actually lapses and survives
    // everything else — switching tier, switching interval, cancelling and coming back before the
    // period runs out. That distinction is the whole meaning of the number.
    ProfileBadgeSonic(:final streakMonths, :final since) ||
    ProfileBadgeSuperSonic(:final streakMonths, :final since) => t(
      SocialKeys.badgesPremiumDetail,
      {'count': streakMonths, 'date': date(since)},
    ),
  };
}

/// The badge's own name — the staff badge says which role, because "Staff" alone is the one label
/// that leaves the reader with the question the badge exists to answer.
String _badgeLabel(
  ProfileBadge badge,
  String Function(String, [Map<String, Object?>]) t,
) => switch (badge) {
  ProfileBadgeDeveloper() => t(SocialKeys.badgesDirectoryNameDeveloper),
  ProfileBadgeStaff(:final role) => t(switch (role) {
    StaffRole.admin => SocialKeys.badgesStaffAdmin,
    StaffRole.moderator => SocialKeys.badgesStaffModerator,
    StaffRole.support => SocialKeys.badgesStaffSupport,
  }),
  ProfileBadgeTranslator() => t(SocialKeys.badgesDirectoryNameTranslator),
  ProfileBadgeEarlyBird() => t(SocialKeys.badgesDirectoryNameEarlyBird),
  ProfileBadgeEarlySupporter() => t(
    SocialKeys.badgesDirectoryNameEarlySupporter,
  ),
  ProfileBadgeSonic() => t(SocialKeys.badgesDirectoryNameSonic),
  ProfileBadgeSuperSonic() => t(SocialKeys.badgesDirectoryNameSuperSonic),
};
