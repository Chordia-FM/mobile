import 'package:flutter/material.dart';

import '../../../widgets/tokens.dart';
import '../catalog_routes.dart';
import '../format.dart';

/// A row of genre tags, each opening its own page.
///
/// Links rather than a joined string, for the same reason the credited-artist line is: a genre on
/// an album header is a route to everything else tagged that way, and flattening it to text throws
/// that away.
class GenreChips extends StatelessWidget {
  const GenreChips({required this.genres, super.key});

  final List<String> genres;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final genre in genres)
          InkWell(
            borderRadius: ChordiaRadius.pill,
            onTap: () => context.goToGenre(genreSlug(genre)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: ChordiaRadius.pill,
              ),
              child: Text(
                titleCaseGenre(genre),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A label name that opens the label's page, or plain text when the album is only labelled by an
/// override with no label entity behind it.
class LabelLink extends StatelessWidget {
  const LabelLink({required this.name, super.key, this.labelId, this.style});

  final String name;
  final String? labelId;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final id = labelId;
    final theme = Theme.of(context);
    final text = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style:
          style ??
          theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
    );
    if (id == null) return text;
    return InkWell(onTap: () => context.goToLabel(id), child: text);
  }
}
