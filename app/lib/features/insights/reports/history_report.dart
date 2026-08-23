import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../social/data/social_messages.dart';
import '../../social/widgets/person_row.dart' show showSocialMessage;
import '../data/insights_providers.dart';
import '../format.dart';
import '../widgets/insights_primitives.dart';

/// The History tab: every play, newest first, a page at a time.
///
/// A "Load more" button rather than infinite scroll, because this list lives inside the profile's
/// single scroll view — a nested scroller would steal the page's gesture, and an auto-loading list
/// inside a page that also scrolls has no bottom for the reader to reach.
class HistoryReport extends ConsumerWidget {
  const HistoryReport({required this.handle, super.key, this.own = false});

  final String? handle;

  /// Whether the report is about the reader, which is what the catalogs' `person` select needs.
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final feed = ref.watch(historyControllerProvider(handle));

    return ReportBody<HistoryFeed>(
      value: feed,
      onRetry: () => ref.invalidate(historyControllerProvider(handle)),
      builder: (context, value) => value.entries.isEmpty
          ? ReportEmpty(
              title: t(InsightsKeys.emptyHistoryTitle),
              body: t(InsightsKeys.emptyHistoryBody, personArg(own: own)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in value.entries)
                  PlayRow(
                    key: ValueKey(entry.eventId),
                    title: entry.title,
                    artist: entry.artist,
                    playedAt: entry.playedAt,
                    imageUrl: entry.imageUrl,
                    trackId: entry.trackId,
                    footnote: entry.album,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  child: value.next == null
                      // Not a disabled button: reaching the first play on record is an answer, and
                      // a greyed control invites a tap that can never do anything.
                      ? Text(
                          t(InsightsKeys.historyBeginning),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        )
                      : OutlinedButton(
                          onPressed: value.loadingMore
                              ? null
                              : () => _loadMore(context, ref),
                          child: Text(
                            t(
                              value.loadingMore
                                  ? CommonKeys.statesLoading
                                  : SocialKeys.profileLoadMore,
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Future<void> _loadMore(BuildContext context, WidgetRef ref) async {
    final t = ref.read(translationsProvider).call;
    try {
      await ref.read(historyControllerProvider(handle).notifier).loadMore();
    } on Object catch (error) {
      if (!context.mounted) return;
      showSocialMessage(context, describeSocialError(error, t));
    }
  }
}
