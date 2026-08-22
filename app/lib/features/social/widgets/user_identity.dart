import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';

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

/// The badges an account carries, as a row of chips.
///
/// Shown even on a withheld profile: a badge is identity, like the handle, and hiding it would make
/// a moderator unrecognisable on exactly the profile where knowing they are staff matters.
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
    final held = badges ?? const <ProfileBadge>[];
    if (held.isEmpty) return const SizedBox.shrink();
    final t = ref.t;
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: alignment,
      children: [
        for (final badge in held)
          Chip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(_badgeIcon(badge), size: 16),
            label: Text(_badgeLabel(badge, t)),
            labelStyle: theme.textTheme.labelSmall,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
      ],
    );
  }
}

IconData _badgeIcon(ProfileBadge badge) => switch (badge) {
  ProfileBadgeDeveloper() => Icons.code_rounded,
  ProfileBadgeStaff() => Icons.shield_rounded,
  ProfileBadgeTranslator() => Icons.translate_rounded,
  ProfileBadgeEarlyBird() => Icons.album_rounded,
  ProfileBadgeEarlySupporter() => Icons.workspace_premium_rounded,
  ProfileBadgeSonic() => Icons.graphic_eq_rounded,
  ProfileBadgeSuperSonic() => Icons.auto_awesome_rounded,
};

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
