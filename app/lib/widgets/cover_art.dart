import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

/// Album, artist or playlist artwork.
///
/// Reads through [ArtCache], so a cover is fetched once at a width the Hub actually derives and
/// then comes off disk — which is also what puts a `file://` path within reach of the media
/// notification, whose native side cannot use our pinned HTTP client.
class CoverArt extends ConsumerStatefulWidget {
  const CoverArt({
    required this.sha256,
    required this.size,
    super.key,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.fallbackIcon = Icons.music_note_rounded,
    this.semanticLabel,
  });

  /// The Hub content address, or null for an entity with no artwork.
  final String? sha256;

  /// Logical size. The pixel width actually requested is this times the device pixel ratio,
  /// snapped up to the Hub's ladder.
  final double size;

  final BorderRadius? borderRadius;

  /// Circular for artists, rectangular for everything else.
  final BoxShape shape;
  final IconData fallbackIcon;
  final String? semanticLabel;

  @override
  ConsumerState<CoverArt> createState() => _CoverArtState();
}

class _CoverArtState extends ConsumerState<CoverArt> {
  File? _file;
  bool _resolved = false;

  /// The request in flight, so a late answer for a cover we have navigated away from cannot
  /// overwrite the one now on screen.
  Object? _token;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(CoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sha256 != widget.sha256 || oldWidget.size != widget.size) {
      _load();
    }
  }

  Future<void> _load() async {
    final sha = widget.sha256;
    if (sha == null || sha.isEmpty) {
      setState(() {
        _file = null;
        _resolved = true;
      });
      return;
    }

    final token = Object();
    _token = token;

    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final file = await ref
        .read(artCacheProvider)
        .file(sha, width: (widget.size * ratio).ceil());

    if (!mounted || !identical(_token, token)) return;
    setState(() {
      _file = file;
      _resolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.shape == BoxShape.circle
        ? null
        : (widget.borderRadius ?? BorderRadius.circular(widget.size * 0.08));

    final file = _file;
    final child = file == null
        ? _Placeholder(
            size: widget.size,
            icon: widget.fallbackIcon,
            // Only shimmer while there is still something to wait for; a cover the Hub does not
            // have would otherwise pulse forever as if it were about to arrive.
            settled: _resolved,
          )
        : Image.file(
            file,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _Placeholder(
              size: widget.size,
              icon: widget.fallbackIcon,
              settled: true,
            ),
          );

    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: ClipPath(
          clipper: ShapeBorderClipper(
            shape: widget.shape == BoxShape.circle
                ? const CircleBorder()
                : RoundedRectangleBorder(borderRadius: radius!),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.size,
    required this.icon,
    required this.settled,
  });

  final double size;
  final IconData icon;
  final bool settled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: settled
          ? Center(
              child: Icon(
                icon,
                size: size * 0.4,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            )
          : const SizedBox.expand(),
    );
  }
}
