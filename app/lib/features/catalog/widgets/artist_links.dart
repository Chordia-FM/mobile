import 'package:chordia_api/chordia_api.dart' show ArtistRef;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../catalog_routes.dart';

/// The credited-artist line, with every credited artist its own tap target.
///
/// The Hub already assembles the display string ("Drake feat. Rihanna") including the join phrases,
/// and `artists` carries the same people in the same order. This renders the LIST, not the string:
/// re-deriving links by splitting the display line on commas would break on "feat.", on "&", and on
/// any artist whose own name contains a comma — and it would silently produce links to the wrong
/// artist rather than failing.
///
/// Falls back to the assembled string when the Hub sent no list, which happens for rows synced
/// before multi-artist support. Then it is one link (to the primary artist) or plain text.
class ArtistLinks extends StatefulWidget {
  const ArtistLinks({
    required this.artists,
    required this.fallbackName,
    super.key,
    this.fallbackId,
    this.style,
    this.linkStyle,
    this.maxLines = 1,
  });

  /// All credited artists, primary first. Null or empty falls back to [fallbackName].
  final List<ArtistRef>? artists;

  /// The Hub's assembled display line, used when there is no per-artist list.
  final String fallbackName;

  final String? fallbackId;
  final TextStyle? style;

  /// Applied to the parts that navigate. Defaults to [style] with the foreground colour, so a
  /// tappable name is distinguishable from the separators around it.
  final TextStyle? linkStyle;

  final int maxLines;

  @override
  State<ArtistLinks> createState() => _ArtistLinksState();
}

class _ArtistLinksState extends State<ArtistLinks> {
  /// One recognizer per link, rebuilt whenever the credits change.
  ///
  /// Held in state because a `TapGestureRecognizer` owns platform resources: leaking one per row of
  /// a scrolling list is how a track list starts dropping frames after a few screens.
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _linkTo(String artistId) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => context.goToArtist(artistId);
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    // The tree is rebuilt from scratch on every build, so the previous generation's recognizers
    // are unreachable the moment this runs.
    _disposeRecognizers();

    final theme = Theme.of(context);
    final base = widget.style ?? theme.textTheme.bodySmall;
    final link =
        widget.linkStyle ?? base?.copyWith(color: theme.colorScheme.onSurface);

    final credits = widget.artists;
    final spans = <InlineSpan>[];
    if (credits == null || credits.isEmpty) {
      final id = widget.fallbackId;
      spans.add(
        TextSpan(
          text: widget.fallbackName,
          style: id == null ? base : link,
          recognizer: id == null ? null : _linkTo(id),
        ),
      );
    } else {
      for (var i = 0; i < credits.length; i++) {
        if (i > 0) spans.add(TextSpan(text: ', ', style: base));
        spans.add(
          TextSpan(
            text: credits[i].name,
            style: link,
            recognizer: _linkTo(credits[i].id),
          ),
        );
      }
    }

    return Text.rich(
      TextSpan(children: spans),
      style: base,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
