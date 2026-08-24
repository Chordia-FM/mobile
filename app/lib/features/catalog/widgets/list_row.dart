import 'package:flutter/material.dart';

import '../../../widgets/surface.dart';
import '../../../widgets/tokens.dart';

/// A row in a list, for everything that is not a song.
///
/// [TrackRowLayout] ported the web's row properly and then nothing else used it: artist rows,
/// playlist rows, library rows and every settings row stayed `ListTile`, which brings Material's
/// own 56/72px heights, its own 16px insets, its own `bodyLarge`-over-`bodyMedium` type scale and
/// its own ink ripple. A ported row on one screen beside a Material row on the next is exactly the
/// "looks like a completely different app" complaint, one list at a time — `widgets/tokens.dart`
/// documents that mismatch as the reason [ChordiaType] exists, and it had been applied to one row.
///
/// Every number here is the web's list row (`components/catalog/TrackList.tsx:602-820`), the same
/// source [TrackRowLayout] reads from, so the two are the same row with different contents:
///
/// - `rounded-md px-3 py-1.5 transition-none hover:bg-accent/50` — [ChordiaRadius.md], an instant
///   fill, no ripple (see [PressFill]);
/// - `gap-3` after the leading slot;
/// - `font-medium text-sm` title over a `text-muted-foreground text-xs` second line.
///
/// The one thing that is NOT from the web is [minHeight]: a row on a phone has to clear the 44px
/// target the coarse-pointer block sets ([ChordiaControl.xs]), which the web's own rows get from
/// the `IconButton`s inside them and a bare two-line row here would not.
class ListRow extends StatelessWidget {
  const ListRow({
    required this.title,
    super.key,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.destructive = false,
    this.gutter = 8,
    this.subtitleMaxLines = 2,
  });

  /// The first line. A widget rather than a string for the rows whose title carries a badge.
  final Widget title;

  /// The second line, in the muted `text-xs` the whole app uses for it.
  final Widget? subtitle;

  /// Artwork, an avatar, an icon, a checkbox.
  final Widget? leading;

  /// A chevron, a switch, a badge, a menu button.
  final Widget? trailing;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// A row that is present but cannot be acted on — dimmed, and its tap dropped.
  final bool enabled;

  /// Destructive rows put the error colour on the title and the leading icon, which is the only
  /// signal separating "Sign out" from "Appearance" in a column of identical rows.
  final bool destructive;

  /// The margin OUTSIDE the fill. 8 puts the content on the page gutter while the highlight still
  /// stops short of the screen edge; a row inside a card passes 0, because the card is the edge.
  final double gutter;

  /// How far the second line may run before it ellipses.
  ///
  /// Two by default, which is what a name-plus-counts row needs. The rows that stack three facts
  /// under one heading — a plan's tier, a session's dates — say so, because `ListTile` expressed
  /// that as `isThreeLine` and silently clipping the third line loses a date nobody can get back.
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = destructive ? scheme.error : scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    final tappable = enabled && (onTap != null || onLongPress != null);

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: ChordiaControl.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            if (leading case final lead?) ...[
              IconTheme.merge(
                data: IconThemeData(color: destructive ? scheme.error : null),
                child: lead,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle.merge(
                    style: ChordiaType.sm.copyWith(
                      fontWeight: ChordiaType.medium,
                      color: ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: title,
                  ),
                  if (subtitle case final second?)
                    DefaultTextStyle.merge(
                      style: ChordiaType.xs.copyWith(color: muted),
                      maxLines: subtitleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      child: second,
                    ),
                ],
              ),
            ),
            if (trailing case final tail?) ...[
              const SizedBox(width: 8),
              DefaultTextStyle.merge(
                style: ChordiaType.sm.copyWith(color: muted),
                child: IconTheme.merge(
                  data: IconThemeData(color: muted, size: 20),
                  child: tail,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: tappable
            ? PressFill(
                onTap: enabled ? onTap : null,
                onLongPress: enabled ? onLongPress : null,
                borderRadius: ChordiaRadius.mdAll,
                fill: scheme.rowHighlight,
                child: row,
              )
            : row,
      ),
    );
  }
}

/// The chevron a row that leads somewhere else carries.
///
/// A constant rather than an `Icon(...)` at each call site so the size stays one decision: 20px is
/// what [ListRow] gives its trailing slot, and a 24px chevron beside a 20px badge in the next row
/// is the sort of drift these primitives exist to prevent.
const listRowChevron = Icon(Icons.chevron_right_rounded);
