import 'package:flutter/material.dart';

import '../../../widgets/cover_art.dart';
import '../data/formatting.dart';

/// One song, in the shape every list in the Library tab uses.
///
/// Takes plain values rather than a `BrowseTrack` or a `DownloadedTrack`: the same row renders a
/// catalog track, a downloaded file and a playlist entry, and the three carry the same four facts
/// under different field names. Converting at the call site keeps one row instead of three.
class TrackTile extends StatelessWidget {
  const TrackTile({
    required this.title,
    required this.artist,
    required this.durationMs,
    super.key,
    this.coverSha,
    this.leading,
    this.trailing,
    this.onTap,
    this.detail,
    this.dense = false,
  });

  final String title;
  final String artist;
  final int durationMs;
  final String? coverSha;

  /// Replaces the artwork — a drag handle in reorder mode, a position number in a queue.
  final Widget? leading;

  final Widget? trailing;
  final VoidCallback? onTap;

  /// An extra fact after the artist, such as a downloaded file's size.
  final String? detail;

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = detail == null ? artist : '$artist · $detail';
    return ListTile(
      onTap: onTap,
      dense: dense,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading:
          leading ?? CoverArt(sha256: coverSha, size: 48, semanticLabel: title),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            trackClock(durationMs),
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ],
      ),
    );
  }
}
