import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../data/insights_providers.dart';
import '../format.dart';
import '../widgets/insights_primitives.dart';

/// The Records tab: streaks, the window's day records, the longest sessions, milestones, and what
/// this listener was playing on today's date in past years.
class RecordsReport extends ConsumerWidget {
  const RecordsReport({required this.handle, super.key, this.own = false});

  final String? handle;

  /// Whether the report is about the reader, which is what the catalogs' `person` select needs.
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final query = ref.watch(insightsQueryProvider(handle));
    final records = ref.watch(listeningRecordsProvider(query));

    return ReportBody<ListeningRecords>(
      value: records,
      onRetry: () => ref.invalidate(listeningRecordsProvider(query)),
      builder: (context, value) =>
          value.activeDays == 0 && value.milestones.isEmpty
          ? ReportEmpty(
              title: t(InsightsKeys.recordsEmptyTitle),
              body: t(InsightsKeys.recordsEmptyBody, personArg(own: own)),
            )
          : _Records(records: value, handle: handle, own: own),
    );
  }
}

class _Records extends ConsumerWidget {
  const _Records({
    required this.records,
    required this.handle,
    required this.own,
  });

  final ListeningRecords records;
  final String? handle;
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;
    final date = DateFormat.yMMMd(locale);
    final windowDays = ((records.windowEnd - records.windowStart) / 86400000)
        .round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        StatGrid(
          tiles: [
            StatTile(
              label: t(InsightsKeys.recordsTilesActiveDays),
              value: '${records.activeDays}',
            ),
            StatTile(
              label: t(InsightsKeys.recordsTilesPlaysPerDay),
              value: records.avgPlaysPerDay.toStringAsFixed(1),
              compared: records.avgPlaysPerDayCompared,
              showDelta: records.period != Period.overall,
            ),
            StatTile(
              label: t(InsightsKeys.recordsTilesBiggestDay),
              value: '${records.biggestDay?.plays ?? 0}',
              compared: records.biggestDayCompared,
              showDelta: records.period != Period.overall,
            ),
            StatTile(
              label: t(InsightsKeys.recordsTilesActiveDaysOf, {
                'count': windowDays,
              }),
              value: windowDays == 0
                  ? '0%'
                  : '${(records.activeDays * 100 / windowDays).round()}%',
            ),
          ],
        ),

        // The UTC report is served from a daily rollup, and a Hub whose aggregator has never
        // finished a pass has no rollup to read. Saying so beats rendering a zero-day history as
        // if it were a fact.
        if (records.dayStatsPending ?? false)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              t(InsightsKeys.chartNoActivityYet),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),

        ReportHeading(title: t(InsightsKeys.recordsStreaksCurrent)),
        if (records.currentStreak case final streak?)
          _StreakTile(streak: streak, date: date, longest: false)
        else
          ReportEmpty(
            title: t(InsightsKeys.recordsStreaksNoCurrentTitle),
            body: t(
              InsightsKeys.recordsStreaksNoCurrentBody,
              personArg(own: own),
            ),
          ),
        if (records.longestStreak case final streak?) ...[
          ReportHeading(title: t(InsightsKeys.recordsStreaksLongest)),
          _StreakTile(streak: streak, date: date, longest: true),
        ],

        if (records.topSessions.isNotEmpty) ...[
          ReportHeading(title: t(InsightsKeys.recordsSessionsTitle)),
          for (final session in records.topSessions)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: const Icon(Icons.timelapse_rounded),
              title: Text(msToTime(session.msPlayed, t)),
              subtitle: Text(
                [
                  session.topArtist == null
                      ? t(InsightsKeys.recordsSessionsMeta, {
                          'tracks': session.tracks,
                        })
                      : t(InsightsKeys.recordsSessionsMetaWithArtist, {
                          'tracks': session.tracks,
                          'artist': session.topArtist,
                        }),
                  date.format(
                    DateTime.fromMillisecondsSinceEpoch(session.startedAt),
                  ),
                ].join(' · '),
                maxLines: 2,
              ),
            ),
        ],

        ReportHeading(title: t(InsightsKeys.recordsMilestonesTitle)),
        if (records.milestones.isEmpty && records.firstScrobble == null)
          ReportEmpty(
            title: t(
              InsightsKeys.recordsMilestonesBeginning,
              personArg(own: own),
            ),
          )
        else ...[
          if (records.firstScrobble case final first?)
            _MilestoneTile(
              milestone: first,
              label: t(InsightsKeys.recordsMilestonesFirst),
              date: date,
            ),
          for (final milestone in records.milestones)
            _MilestoneTile(
              milestone: milestone,
              label: t(InsightsKeys.recordsMilestonesOrdinal, {
                'ordinal': milestone.ordinal,
              }),
              date: date,
            ),
        ],

        _OnThisDay(handle: handle, own: own),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _StreakTile extends ConsumerWidget {
  const _StreakTile({
    required this.streak,
    required this.date,
    required this.longest,
  });

  final Streak streak;
  final DateFormat date;
  final bool longest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(
        longest
            ? Icons.emoji_events_rounded
            : Icons.local_fire_department_rounded,
      ),
      title: Text(t(InsightsKeys.recordsStreaksDays, {'count': streak.days})),
      subtitle: Text(
        t(InsightsKeys.recordsStreaksDetail, {
          'range': '${streak.startDay} – ${streak.endDay}',
          'plays': streak.plays,
        }),
      ),
      trailing: streak.active
          ? Text(
              t(InsightsKeys.recordsStreaksLive),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : null,
    );
  }
}

class _MilestoneTile extends StatelessWidget {
  const _MilestoneTile({
    required this.milestone,
    required this.label,
    required this.date,
  });

  final Milestone milestone;
  final String label;
  final DateFormat date;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    leading: const Icon(Icons.flag_rounded),
    title: Text(label, style: Theme.of(context).textTheme.labelMedium),
    subtitle: Text(
      '${milestone.title} · ${milestone.artist}\n'
      '${date.format(DateTime.fromMillisecondsSinceEpoch(milestone.playedAt))}',
    ),
    isThreeLine: true,
  );
}

/// What was playing on today's date in earlier years.
class _OnThisDay extends ConsumerWidget {
  const _OnThisDay({required this.handle, required this.own});

  final String? handle;
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final query = ref.watch(insightsQueryProvider(handle));
    final onThisDay = ref.watch(onThisDayProvider(query)).value;
    if (onThisDay == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportHeading(title: t(InsightsKeys.recordsOnThisDayTitle)),
        if (onThisDay.years.isEmpty)
          ReportEmpty(
            title: t(InsightsKeys.recordsOnThisDayEmpty, personArg(own: own)),
          )
        else
          for (final year in onThisDay.years) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                t(InsightsKeys.recordsOnThisDayYearsAgo, {
                  'count': DateTime.now().year - year.year,
                }),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            for (final entry in year.entries.take(3))
              PlayRow(
                key: ValueKey(entry.eventId),
                title: entry.title,
                artist: entry.artist,
                playedAt: entry.playedAt,
                imageUrl: entry.imageUrl,
                trackId: entry.trackId,
              ),
          ],
      ],
    );
  }
}
