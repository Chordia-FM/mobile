import 'package:flutter/material.dart';

import '../../catalog/widgets/track_row.dart';

/// One song, in the shape every list in the Library tab uses.
///
/// Takes plain values rather than a `BrowseTrack` or a `DownloadedTrack`: the same row renders a
/// catalog track, a downloaded file and a playlist entry, and the three carry the same four facts
/// under different field names. Converting at the call site keeps one row instead of three.
///
/// The row itself is [TrackRowLayout] — the catalog tab's row, which is the web's row. It used to
/// be a `ListTile`, and a `ListTile` in the Library tab beside a ported row in the Catalog tab is
/// two different songs-lists in one app: different height, different title size, different press
/// feedback. There is one now.
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
    this.onLongPress,
    this.detail,
    this.dense = false,
    this.active = false,
  });

  final String title;
  final String artist;
  final int durationMs;
  final String? coverSha;

  /// Replaces the artwork — a drag handle in reorder mode, a position number in a queue.
  final Widget? leading;

  final Widget? trailing;
  final VoidCallback? onTap;

  /// The row's own route to the track menu, so the ⋮ button is not the only one. A long press is
  /// what a right-click is on the web client, and every list here is scrolled with a thumb that is
  /// already on the row.
  final VoidCallback? onLongPress;

  /// An extra fact after the artist, such as a downloaded file's size.
  final String? detail;

  final bool dense;

  /// This row is the track currently playing — the one place the accent lands inside a list.
  /// Opt-in, because these lists carry plain values and only the caller knows the track's id.
  final bool active;

  @override
  Widget build(BuildContext context) => TrackRowLayout(
    title: title,
    durationMs: durationMs,
    coverSha: coverSha,
    leading: leading,
    trailing: trailing,
    onTap: onTap,
    onLongPress: onLongPress,
    dense: dense,
    active: active,
    subtitle: Text(
      detail == null ? artist : '$artist · $detail',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}
