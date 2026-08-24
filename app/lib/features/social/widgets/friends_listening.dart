import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../../catalog/widgets/list_row.dart';
import '../data/social_providers.dart';
import '../social_routes.dart';

/// What friends are playing right now.
///
/// Absent rather than empty when nobody is listening: a heading over an empty box says "this is
/// broken", while nothing at all says "nobody is playing anything", which is the truth. A friend
/// whose scrobble privacy is private never appears in the Hub's answer at all, so there is no
/// half-blank row for them either.
class FriendsListening extends ConsumerWidget {
  const FriendsListening({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(friendsListeningProvider).value ?? const [];
    if (live.isEmpty) return const SizedBox.shrink();
    final t = ref.t;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              const _LivePip(),
              const SizedBox(width: 8),
              Text(
                t(InsightsKeys.socialListeningNow),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        for (final entry in live) _NowPlayingRow(entry: entry),
      ],
    );
  }
}

class _NowPlayingRow extends ConsumerWidget {
  const _NowPlayingRow({required this.entry});

  final FriendNowPlaying entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListRow(
    leading: CoverArt(sha256: artHashOf(entry.imageUrl), size: 44),
    title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      '${entry.artist} · ${entry.displayName}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: () => context.goToProfile(entry.handle),
  );
}

/// The pulsing dot that marks live data.
class _LivePip extends StatefulWidget {
  const _LivePip();

  @override
  State<_LivePip> createState() => _LivePipState();
}

class _LivePipState extends State<_LivePip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colour = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 10,
      height: 10,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The halo expands and fades on a loop; the dot underneath stays put, so the whole thing
          // reads as a signal rather than as a control that might be tappable.
          FadeTransition(
            opacity: Tween<double>(begin: 0.6, end: 0).animate(_controller),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.6, end: 1.8).animate(_controller),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colour,
                ),
                child: const SizedBox(width: 10, height: 10),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
            child: const SizedBox(width: 6, height: 6),
          ),
        ],
      ),
    );
  }
}
