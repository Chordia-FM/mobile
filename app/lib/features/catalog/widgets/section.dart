import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';

/// A section heading, with an optional route to the full list.
class SectionHeader extends ConsumerWidget {
  const SectionHeader({required this.title, super.key, this.onSeeAll});

  final String title;

  /// Shown whenever the section has a page of its own — including when everything already fits.
  /// Hiding it past a threshold on the DATA left a phone showing two of five albums with no route
  /// to the other three.
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            child: Text(ref.t(CommonKeys.actionsSeeAll)),
          ),
      ],
    ),
  );
}

/// The row under a collection's header: a big Play, a Shuffle, and whatever else that page offers.
///
/// Both primary actions are disabled together when there is nothing to play — an empty album, or a
/// build where the player is not wired yet. A control that looks live and does nothing is the
/// failure this avoids.
class CollectionActions extends ConsumerWidget {
  const CollectionActions({
    required this.onPlay,
    required this.onShuffle,
    super.key,
    this.trailing = const [],
  });

  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  /// Extra icon buttons — Radio on an artist, Share anywhere.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(t(CommonKeys.actionsPlay)),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onShuffle,
            icon: const Icon(Icons.shuffle_rounded),
            label: Text(t(CommonKeys.actionsShuffle)),
          ),
          const Spacer(),
          ...trailing,
        ],
      ),
    );
  }
}

/// Text that expands on demand — an artist bio, a label's description.
class ExpandableText extends ConsumerStatefulWidget {
  const ExpandableText({
    required this.text,
    super.key,
    this.collapsedLines = 4,
  });

  final String text;
  final int collapsedLines;

  @override
  ConsumerState<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends ConsumerState<ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final theme = Theme.of(context);
    // Roughly the length at which the collapsed clamp actually bites. Below it the toggle would
    // expand nothing, which is worse than no toggle.
    final expandable = widget.text.length > 240;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _expanded ? null : widget.collapsedLines,
          overflow: _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
            height: 1.45,
          ),
        ),
        if (expandable)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(
              t(
                _expanded
                    ? CommonKeys.actionsShowLess
                    : CommonKeys.actionsShowMore,
              ),
            ),
          ),
      ],
    );
  }
}
