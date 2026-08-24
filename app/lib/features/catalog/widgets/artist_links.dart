import 'package:chordia_api/chordia_api.dart' show ArtistRef;
import 'package:chordia_sync/chordia_sync.dart' show TrackArtist;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The credits on a queue entry, in the catalog's own reference type.
///
/// `PlayerTrack.artists` carries `chordia_sync`'s [TrackArtist], which is the identical wire shape
/// and cannot be [ArtistRef]: `chordia_api` depends on `chordia_sync`, so the dependency only runs
/// one way. Converting here is what lets the player, the queue and every catalog row draw their
/// credits through the one widget instead of the player re-implementing it as a string.
List<ArtistRef>? playerArtistRefs(List<TrackArtist>? artists) => artists
    ?.map((a) => ArtistRef(id: a.id, name: a.name, imageUrl: a.imageUrl))
    .toList(growable: false);

/// Opens an artist from a credited name, from wherever that name is drawn.
///
/// Deliberately not `CatalogNavigation.goToArtist`, which reads the tab out of
/// `GoRouterState.of(context)`. Two things break that over the player. The full player and its
/// tabs are pushed onto the ROOT navigator by hand, and route state only resolves under a route the
/// router itself built — there it throws. And even where it resolved, the artist page would open
/// *behind* a full-screen player, which reads as the tap having done nothing.
void openArtistLink(BuildContext context, String artistId) {
  final router = GoRouter.of(context);
  // The tab, from the router's own configuration rather than from this subtree: an imperative push
  // does not change that configuration, so it still names the branch the listener is browsing.
  final segments = router.state.uri.pathSegments;
  if (segments.isEmpty) return;
  // Everything above the topmost page-backed route was pushed by hand — the player, a dialog — and
  // has to come off before the destination is visible. Page-backed routes belong to the router.
  Navigator.of(
    context,
    rootNavigator: true,
  ).popUntil((route) => route.settings is Page || route.isFirst);
  router.push('/${segments.first}/artists/$artistId');
}

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
      ..onTap = () => openArtistLink(context, artistId);
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
