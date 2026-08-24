import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../widgets/surface.dart';

/// One number with its label, as the overview and system tabs stack them.
class AdminStat extends StatelessWidget {
  const AdminStat({
    required this.label,
    required this.value,
    super.key,
    this.caption,
  });

  final String label;
  final String value;

  /// A second line under the number, for the figure that gives it meaning.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The admin overview and system tabs render the web's `StatTile`
    // (`admin/overview.tsx:83`, `admin/system.tsx:51`), which is `island-shell rounded-xl p-4`.
    // The 14px corner and the 14px padding this carried are on no scale at all.
    return IslandPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A grid of [AdminStat]s that reflows rather than overflowing on a narrow phone.
class AdminStatGrid extends StatelessWidget {
  const AdminStatGrid({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Two columns wherever there is room for them, one where there is not — a fixed count
        // either wastes half a tablet or clips a 320px phone.
        final columns = constraints.maxWidth >= 480 ? 3 : 2;
        final spacing = 8.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    ),
  );
}

/// A titled group inside an admin tab.
class AdminSection extends StatelessWidget {
  const AdminSection({
    required this.title,
    super.key,
    this.description,
    this.trailing,
  });

  final String title;
  final String? description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A date and time an operator can act on, in their own locale.
///
/// Timestamps on the wire are epoch **milliseconds**, so they are read as such — a value divided
/// by a thousand somewhere along the way lands in 1970 and reads as a data-loss bug.
String formatAdminMoment(int epochMs, String locale) => DateFormat.yMMMd(
  locale,
).add_jm().format(DateTime.fromMillisecondsSinceEpoch(epochMs));

/// A date alone, for a column where the time of day is noise.
String formatAdminDay(int epochMs, String locale) => DateFormat.yMMMd(
  locale,
).format(DateTime.fromMillisecondsSinceEpoch(epochMs));

/// Thousands-separated in the reader's locale, because a seven-digit play count is unreadable
/// without them and the separator is not the same character everywhere.
String formatAdminCount(int value, String locale) =>
    NumberFormat.decimalPattern(locale).format(value);

/// Milliseconds of listening as whole hours — the unit every listening total on these screens uses.
int listeningHours(int msPlayed) => (msPlayed / 3600000).round();

/// The Hub's own words for a refusal, already in the reader's language, or a generic failure when
/// the request never reached it.
String describeAdminFailure(
  Object error,
  String Function(String, [Map<String, Object?>]) t,
  String fallbackKey,
) => error is ApiException && !error.isNetworkFailure
    ? error.title
    : t(fallbackKey);
