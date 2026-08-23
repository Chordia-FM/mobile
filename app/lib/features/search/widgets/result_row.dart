import 'package:flutter/material.dart';

import '../../../data/art/art_cache.dart';
import '../../../widgets/cover_art.dart';

/// One search result that is not a track or an artist — those have rows of their own in the catalog
/// feature, and a result list has to look like the lists it links into.
class ResultRow extends StatelessWidget {
  const ResultRow({
    required this.title,
    required this.onTap,
    super.key,
    this.imageUrl,
    this.subtitle,
    this.fallbackIcon = Icons.album_rounded,
  });

  final String title;
  final String? subtitle;

  /// The Hub image reference as the DTO carries it; the hash is taken out here.
  final String? imageUrl;
  final IconData fallbackIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    leading: CoverArt(
      sha256: artHashOf(imageUrl),
      size: 48,
      fallbackIcon: fallbackIcon,
      semanticLabel: title,
    ),
    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}
