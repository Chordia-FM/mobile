import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../../catalog/catalog_routes.dart';
import '../../catalog/widgets/catalog_state.dart';
import '../data/insights_providers.dart';
import '../format.dart';

/// The reporting-window pills.
///
/// A horizontal strip rather than a wrap: seven localised labels stack to three lines at 375px,
/// which puts a 108px control above the chart it is meant to sit beside.
class PeriodSelector extends ConsumerWidget {
  const PeriodSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final selected = ref.watch(insightsPeriodProvider);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final period in insightsPeriods)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: ChoiceChip(
                label: Text(periodLabel(period, t)),
                selected: period == selected,
                onSelected: (_) =>
                    ref.read(insightsPeriodProvider.notifier).set(period),
              ),
            ),
        ],
      ),
    );
  }
}

/// A section heading inside a report.
class ReportHeading extends StatelessWidget {
  const ReportHeading({required this.title, super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// One headline number, with the change against the previous window under it.
class StatTile extends ConsumerWidget {
  const StatTile({
    required this.label,
    required this.value,
    super.key,
    this.compared,
    this.showDelta = true,
  });

  final String label;
  final String value;
  final Compared? compared;

  /// False for a window that has no predecessor to compare against.
  final bool showDelta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final change = showDelta ? compared?.change : null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (change != null) _Delta(change: change),
        ],
      ),
    );
  }
}

/// "+18%" / "−7%" / "No change", against the previous window.
class _Delta extends ConsumerWidget {
  const _Delta({required this.change});

  final double change;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final percent = (change * 100).round();
    if (percent == 0) {
      return Text(
        t(InsightsKeys.deltaFlat),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    final up = percent > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          size: 12,
          color: up ? theme.colorScheme.primary : theme.colorScheme.error,
        ),
        Text(
          '${percent.abs()}%',
          semanticsLabel: t(
            up ? InsightsKeys.deltaUpAria : InsightsKeys.deltaDownAria,
            {'pct': '${percent.abs()}%'},
          ),
          style: theme.textTheme.labelSmall?.copyWith(
            color: up ? theme.colorScheme.primary : theme.colorScheme.error,
          ),
        ),
      ],
    );
  }
}

/// A grid of [StatTile]s that reflows to the width it is given.
class StatGrid extends StatelessWidget {
  const StatGrid({required this.tiles, super.key});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Two columns on a phone, three once there is room — chosen from the width rather than
        // from a breakpoint so the same grid works inside a narrow sheet.
        final columns = constraints.maxWidth >= 520 ? 3 : 2;
        const gap = 8.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    ),
  );
}

/// A ranked list of entities: rank, artwork, name, plays and time.
///
/// Rows link into the catalog where the entity has a page there. Genres are not catalog entities,
/// so they carry no artwork and no destination — passing a null [kind] is what says so, and it also
/// stops the row rendering a cover slot that could only ever be empty.
class TopList extends ConsumerWidget {
  const TopList({required this.items, super.key, this.kind, this.limit});

  final List<TopItem> items;
  final EntityKind? kind;

  /// Rows to show. Null shows everything the report returned.
  final int? limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final shown = limit == null ? items : items.take(limit!).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      children: [
        for (final (index, item) in shown.indexed)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: SizedBox(
              width: kind == null ? 24 : 68,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${index + 1}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (kind != null) ...[
                    const SizedBox(width: 4),
                    CoverArt(
                      sha256: artHashOf(item.imageUrl),
                      size: 40,
                      shape: kind == EntityKind.artist
                          ? BoxShape.circle
                          : BoxShape.rectangle,
                      semanticLabel: item.name,
                    ),
                  ],
                ],
              ),
            ),
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${t(InsightsKeys.topPlaysCount, {'count': item.plays})} · '
              '${msToTime(item.msPlayed, t)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: kind == null ? null : () => _open(context, kind!, item.id),
          ),
      ],
    );
  }

  void _open(BuildContext context, EntityKind kind, String id) =>
      switch (kind) {
        EntityKind.artist => context.goToArtist(id),
        EntityKind.album => context.goToAlbum(id),
        EntityKind.track => context.goToTrack(id),
      };
}

/// One play in a feed: cover, title, who by, and how long ago.
class PlayRow extends ConsumerWidget {
  const PlayRow({
    required this.title,
    required this.artist,
    required this.playedAt,
    super.key,
    this.imageUrl,
    this.trackId,
    this.footnote,
  });

  final String title;
  final String artist;
  final int playedAt;
  final String? imageUrl;

  /// Set when the scrobble matched the catalog, which is what makes the row openable.
  final String? trackId;

  /// An extra fact after the timestamp — whose play this was, on a shared feed.
  final String? footnote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final when = relativePlayTime(
      playedAt,
      t,
      locale: ref.watch(translationsProvider).locale,
    );
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: CoverArt(sha256: artHashOf(imageUrl), size: 44),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        footnote == null ? '$artist · $when' : '$artist · $when · $footnote',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: trackId == null ? null : () => context.goToTrack(trackId!),
    );
  }
}

/// A horizontal bar chart, drawn as rows rather than as axes.
///
/// A phone is 375px wide: twenty-four labelled columns become unreadable slivers, while rows stack
/// and each keeps a full-width label and value. Bars are proportional to the largest value, so a
/// quiet week still reads as a shape.
class BarChart extends StatelessWidget {
  const BarChart({required this.bars, super.key, this.maxRows});

  final List<BarDatum> bars;

  /// Rows to draw. Null draws them all.
  final int? maxRows;

  @override
  Widget build(BuildContext context) {
    final shown = maxRows == null ? bars : bars.take(maxRows!).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final peak = shown.fold<int>(
      0,
      (best, bar) => bar.value > best ? bar.value : best,
    );
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final bar in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Semantics(
                label: '${bar.label}: ${bar.value}',
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        bar.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          // Zero everywhere is a real answer (a window with no plays), and dividing
                          // by it would paint every bar full instead of empty.
                          value: peak == 0 ? 0 : bar.value / peak,
                          minHeight: 12,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHigh,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${bar.value}',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One bar: what it is called and how many plays it holds.
@immutable
class BarDatum {
  const BarDatum(this.label, this.value);

  final String label;
  final int value;
}

/// "Nothing to report yet" — a statement, not a failure.
class ReportEmpty extends StatelessWidget {
  const ReportEmpty({required this.title, super.key, this.body});

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          if (body != null) ...[
            const SizedBox(height: 4),
            Text(
              body!,
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

/// Renders one asynchronous report: skeleton, failure with a retry, or the content.
///
/// The catalog's [CatalogBody] with report-shaped defaults, so a stats page and an album page fail
/// the same way — a page that shows its own spinner beside a neighbour's skeleton reads as two
/// different apps.
class ReportBody<T> extends ConsumerWidget {
  const ReportBody({
    required this.value,
    required this.onRetry,
    required this.builder,
    super.key,
  });

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(BuildContext context, T value) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) => CatalogBody<T>(
    value: value,
    errorTitle: ref.t(ErrorsKeys.insightsLoadStatsFailed),
    onRetry: onRetry,
    skeleton: const ReportSkeleton(),
    builder: builder,
  );
}

/// The skeleton every report shows while its first read is in flight.
class ReportSkeleton extends StatelessWidget {
  const ReportSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(child: SkeletonBox(height: 72)),
            SizedBox(width: 8),
            Expanded(child: SkeletonBox(height: 72)),
          ],
        ),
        const SizedBox(height: 24),
        const SkeletonBox(width: 140, height: 16),
        const SizedBox(height: 16),
        for (var i = 0; i < 5; i++) ...[
          Row(
            children: [
              const SkeletonBox(width: 40, height: 40),
              const SizedBox(width: 12),
              Expanded(
                child: SkeletonBox(height: 14, width: 180 - (i % 3) * 30),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ],
    ),
  );
}
