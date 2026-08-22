import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../social/social_routes.dart';
import '../../social/widgets/friends_listening.dart';
import '../data/insights_providers.dart';
import '../widgets/insights_primitives.dart';

/// The Social tab: what friends are playing, how a listener's taste compares with the viewer's, and
/// the friends' recent-plays feed.
///
/// Live data rather than period-scoped, so there is no period selector here — a taste-compatibility
/// score and a "listening now" strip are not statements about a window.
class SocialReport extends ConsumerStatefulWidget {
  const SocialReport({super.key});

  @override
  ConsumerState<SocialReport> createState() => _SocialReportState();
}

class _SocialReportState extends ConsumerState<SocialReport> {
  final _handle = TextEditingController();

  /// The handle currently being compared, or null before anybody asked.
  String? _comparing;

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final activity = ref.watch(friendsActivityProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FriendsListening(),

        ReportHeading(title: t(InsightsKeys.compatibilityTitle)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _handle,
                  autocorrect: false,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixText: '@',
                    hintText: t(InsightsKeys.compatibilityHandlePlaceholder),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _compare(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _compare,
                child: Text(t(InsightsKeys.compatibilityCompare)),
              ),
            ],
          ),
        ),
        if (_comparing case final handle?) _Compatibility(handle: handle),

        ReportHeading(title: t(InsightsKeys.socialFriendActivity)),
        ReportBody<List<FriendScrobble>>(
          value: activity,
          onRetry: () => ref.invalidate(friendsActivityProvider),
          builder: (context, value) => value.isEmpty
              ? ReportEmpty(
                  title: t(InsightsKeys.emptySocialTitle),
                  body: t(InsightsKeys.emptySocialBody),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final play in value)
                      PlayRow(
                        // A friend can play the same track twice, and two friends can play it at
                        // once, so identity is the person plus the instant plus the title.
                        key: ValueKey(
                          '${play.userId}:${play.playedAt}:${play.title}',
                        ),
                        title: play.title,
                        artist: play.artist,
                        playedAt: play.playedAt,
                        imageUrl: play.imageUrl,
                        footnote: play.displayName,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  void _compare() {
    final typed = _handle.text.trim();
    final handle = typed.startsWith('@') ? typed.substring(1) : typed;
    if (handle.isEmpty) return;
    setState(() => _comparing = handle);
  }
}

/// Taste overlap between the viewer and one other listener.
class _Compatibility extends ConsumerWidget {
  const _Compatibility({required this.handle});

  final String handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final result = ref.watch(compatibilityProvider(handle));

    return ReportBody<Compatibility>(
      value: result,
      onRetry: () => ref.invalidate(compatibilityProvider(handle)),
      builder: (context, value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(
              t(InsightsKeys.compatibilityYouAnd, {'name': value.displayName}),
            ),
            subtitle: Text('@${value.handle}'),
            trailing: Text(
              t(InsightsKeys.compatibilityPercent, {
                'pct': (value.score * 100).round(),
              }),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
            ),
            onTap: () => context.goToProfile(value.handle),
          ),
          if (value.sharedArtists.isNotEmpty) ...[
            ReportHeading(title: t(InsightsKeys.compatibilitySharedArtists)),
            TopList(
              items: value.sharedArtists,
              kind: EntityKind.artist,
              limit: 10,
            ),
          ],
          if (value.summary case final summary?)
            _TasteSummary(summary: summary),
        ],
      ),
    );
  }
}

/// The deeper overlap the Hub computes when both listeners have enough history: the decades and
/// the hours of the day each side listens in.
class _TasteSummary extends ConsumerWidget {
  const _TasteSummary({required this.summary});

  final TasteSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary.decades.any((split) => split.you + split.them > 0)) ...[
          ReportHeading(title: t(InsightsKeys.panelsDecades)),
          // Both sides on one axis: the interesting fact is where the two overlap, and two charts
          // side by side on a 375px screen is two unreadable charts.
          BarChart(
            bars: [
              for (final split in summary.decades)
                BarDatum(
                  t(InsightsKeys.decadesLabel, {'decade': split.decade}),
                  split.you + split.them,
                ),
            ],
          ),
        ],
        if (summary.sharedTracks.isNotEmpty) ...[
          ReportHeading(title: t(InsightsKeys.topTracks)),
          TopList(
            items: summary.sharedTracks,
            kind: EntityKind.track,
            limit: 10,
          ),
        ],
      ],
    );
  }
}
