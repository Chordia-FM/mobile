import 'dart:io';
import 'dart:typed_data';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/tokens.dart';
import '../social/data/social_messages.dart';
import '../social/widgets/person_row.dart' show showSocialMessage;
import 'wrapped_card.dart' show captureWrappedCard;

/// One tile of the collage: a cover, and the caption that can be drawn over it.
@immutable
class ShareGridTile {
  const ShareGridTile({
    required this.name,
    required this.playsLabel,
    this.cover,
  });

  final String name;

  /// Already-formatted second caption line ("128 plays").
  final String playsLabel;

  /// Decoded cover bytes, or null for an entity the Hub has no artwork for. A missing cover
  /// degrades to an accent-tinted monogram: it must read as a designed tile, never as a hole.
  final Uint8List? cover;
}

/// Everything the collage draws, already translated and formatted.
@immutable
class ShareGridData {
  const ShareGridData({
    required this.tiles,
    required this.size,
    required this.showInfo,
    required this.borders,
    required this.footerLeft,
    required this.footerRight,
  });

  /// Row-major, exactly [size] × [size] entries.
  final List<ShareGridTile> tiles;

  /// Grid side length: 3 is a 3x3.
  final int size;

  final bool showInfo;
  final bool borders;

  /// "@handle · Jun 26 - Jul 26, 2026".
  final String footerLeft;

  /// The app name.
  final String footerRight;

  ShareGridData copyWith({bool? showInfo, bool? borders}) => ShareGridData(
    tiles: tiles,
    size: size,
    showInfo: showInfo ?? this.showInfo,
    borders: borders ?? this.borders,
    footerLeft: footerLeft,
    footerRight: footerRight,
  );
}

/// Pixels per tile. A 3x3 lands at 1200 square, which is a comfortable share size — the same
/// number the web's canvas exporter uses, so the two clients produce the same artifact.
const _tile = 400.0;
const _footerHeight = 84.0;

/// Per-tile inset when borders are on, so adjacent covers are separated by twice this.
const _borderInset = 7.0;

/// The width asked of the art cache. A 400px tile wants 512 off the Hub's ladder; asking for
/// anything off the ladder gets the ORIGINAL back, which on a fanart.tv source is megabytes.
const _gridThumbWidth = 512;

/// The shareable cover collage: the period's top covers as a square grid over an identity footer.
///
/// The Last.fm collage form, ported from `frontend/src/lib/insights/share-grid.ts`. Laid out in the
/// artifact's own pixel units so the capture is 1:1 whatever the phone's density is — scaling for
/// display is the caller's job (a `FittedBox`), which changes how it paints but not the size it
/// lays out at, and therefore not the size of the PNG.
class ShareGridCard extends StatelessWidget {
  const ShareGridCard({required this.data, super.key, this.boundaryKey});

  final ShareGridData data;
  final Key? boundaryKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final side = data.size * _tile;
    return RepaintBoundary(
      key: boundaryKey,
      child: SizedBox(
        width: side,
        height: side + _footerHeight,
        child: ColoredBox(
          // The same dark base the Rotation card sits on, so the two exports read as one set.
          color: scheme.surface,
          child: Column(
            children: [
              SizedBox(
                width: side,
                height: side,
                child: Column(
                  children: [
                    for (var row = 0; row < data.size; row++)
                      Row(
                        children: [
                          for (var column = 0; column < data.size; column++)
                            _Tile(
                              tile: data.tiles[row * data.size + column],
                              showInfo: data.showInfo,
                              borders: data.borders,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          data.footerLeft,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 26,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        data.footerRight,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.tile,
    required this.showInfo,
    required this.borders,
  });

  final ShareGridTile tile;
  final bool showInfo;
  final bool borders;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = tile.cover;
    // "Include borders" rounds every tile on every side and separates them, so the grid reads as a
    // set of records rather than as one sliced image.
    final radius = borders ? ChordiaRadius.xlAll : BorderRadius.zero;
    return Padding(
      padding: EdgeInsets.all(borders ? _borderInset : 0),
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: _tile - (borders ? _borderInset * 2 : 0),
          height: _tile - (borders ? _borderInset * 2 : 0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (bytes == null)
                ColoredBox(
                  color: scheme.primary.withValues(alpha: 0.35),
                  child: Center(
                    child: Text(
                      _initial(tile.name),
                      style: TextStyle(
                        fontSize: _tile * 0.4,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                )
              else
                Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
              if (showInfo)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 120,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    alignment: Alignment.bottomLeft,
                    // Transparent to near-black, tall enough that white text clears any artwork.
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xCC000000)],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tile.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        if (tile.playsLabel.isNotEmpty)
                          Text(
                            tile.playsLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 19,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _initial(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }
}

/// The control that opens the collage, pinned over a hero card's artwork.
///
/// A share artifact rather than a section of the report: it lives behind a small control on the
/// top-artist and top-album cards, so the Overview is not interrupted by a second, larger copy of
/// covers it already shows.
class ShareGridButton extends ConsumerStatefulWidget {
  const ShareGridButton({
    required this.kind,
    required this.items,
    required this.handle,
    required this.period,
    required this.windowStart,
    required this.windowEnd,
    super.key,
  });

  /// Only varies the copy and which entity the tiles are — the grid renders identically either
  /// way, because a circular crop cut the bottom off every caption.
  final EntityKind kind;

  /// That kind's top entities, in rank order.
  final List<TopItem> items;

  /// Whoever the grid is ABOUT, without the `@` — not necessarily the reader.
  final String handle;

  final Period period;
  final int windowStart;

  /// Exclusive end of the window (epoch millis).
  final int windowEnd;

  @override
  ConsumerState<ShareGridButton> createState() => _ShareGridButtonState();
}

class _ShareGridButtonState extends ConsumerState<ShareGridButton> {
  bool _loading = false;

  /// Only complete squares — a ragged last row reads as broken, not as a collage. 3x3 when the top
  /// list can fill it (the Hub sends up to ten), else 2x2.
  int get _size => widget.items.length >= 9 ? 3 : 2;

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final title = t(
      widget.kind == EntityKind.album
          ? InsightsKeys.shareGridAlbumTitle
          : InsightsKeys.shareGridArtistTitle,
    );
    return Semantics(
      button: true,
      label: title,
      child: Material(
        // Over artwork, so the surface under the glyph is a fixed scrim rather than a theme colour.
        color: Colors.black.withValues(alpha: 0.7),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _loading ? null : _open,
          child: SizedBox(
            // A full touch target: this sits over the cover's own tap area, so a near-miss opens
            // the entity page instead of the collage.
            width: ChordiaControl.sm,
            height: ChordiaControl.sm,
            child: Icon(
              PhosphorIcons.gridFour(),
              size: 20,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open() async {
    final translations = ref.read(translationsProvider);
    final t = translations.call;
    setState(() => _loading = true);
    try {
      final data = await _build(t, translations.locale);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _ShareGridPreview(data: data, kind: widget.kind),
      );
    } on Object catch (error) {
      if (!mounted) return;
      showSocialMessage(context, describeSocialError(error, t));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<ShareGridData> _build(Translate t, String locale) async {
    final art = ref.read(artCacheProvider);
    final chosen = widget.items.take(_size * _size).toList();
    final tiles = await Future.wait([
      for (final item in chosen) _tileFor(item, art, t),
    ]);
    final date = DateFormat.yMMMd(locale);
    final range = widget.period == Period.overall
        ? t(InsightsKeys.periodOverall)
        // `windowEnd` is exclusive; step inside it so the range reads as the last included day.
        : '${date.format(DateTime.fromMillisecondsSinceEpoch(widget.windowStart))}'
              ' - '
              '${date.format(DateTime.fromMillisecondsSinceEpoch(widget.windowEnd - 1))}';
    return ShareGridData(
      tiles: tiles,
      size: _size,
      showInfo: true,
      borders: false,
      footerLeft: widget.handle.isEmpty ? range : '@${widget.handle} · $range',
      footerRight: t(CommonKeys.appName),
    );
  }

  Future<ShareGridTile> _tileFor(
    TopItem item,
    ArtCache art,
    Translate t,
  ) async {
    final label = t(InsightsKeys.chartPlays, {'count': item.plays});
    final hash = artHashOf(item.imageUrl);
    if (hash == null) {
      return ShareGridTile(name: item.name, playsLabel: label);
    }
    try {
      final file = await art.file(hash, width: _gridThumbWidth);
      return ShareGridTile(
        name: item.name,
        playsLabel: label,
        cover: file == null ? null : await file.readAsBytes(),
      );
    } on Object {
      // A cover that will not come off disk is a missing cover, not a failed export.
      return ShareGridTile(name: item.name, playsLabel: label);
    }
  }
}

/// The preview: the artifact leads, the options that shape it sit under it.
///
/// What you toggle is what you share — the preview and the capture are one widget, not two
/// renderings that can drift.
class _ShareGridPreview extends ConsumerStatefulWidget {
  const _ShareGridPreview({required this.data, required this.kind});

  final ShareGridData data;
  final EntityKind kind;

  @override
  ConsumerState<_ShareGridPreview> createState() => _ShareGridPreviewState();
}

class _ShareGridPreviewState extends ConsumerState<_ShareGridPreview> {
  final _boundary = GlobalKey();
  late ShareGridData _data = widget.data;
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: FittedBox(
                child: Semantics(
                  label: t(
                    widget.kind == EntityKind.album
                        ? InsightsKeys.shareGridAlbumAriaLabel
                        : InsightsKeys.shareGridArtistAriaLabel,
                  ),
                  image: true,
                  child: ShareGridCard(data: _data, boundaryKey: _boundary),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _Toggle(
              label: t(
                widget.kind == EntityKind.album
                    ? InsightsKeys.shareGridAlbumInfoToggle
                    : InsightsKeys.shareGridArtistInfoToggle,
              ),
              value: _data.showInfo,
              onChanged: (value) =>
                  setState(() => _data = _data.copyWith(showInfo: value)),
            ),
            _Toggle(
              label: t(InsightsKeys.shareGridBordersToggle),
              value: _data.borders,
              onChanged: (value) =>
                  setState(() => _data = _data.copyWith(borders: value)),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _sharing ? null : _share,
              icon: Icon(PhosphorIcons.export()),
              label: Text(
                t(
                  _sharing
                      ? InsightsKeys.rotationSharing
                      : InsightsKeys.rotationShareButton,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share() async {
    final t = ref.read(translationsProvider).call;
    setState(() => _sharing = true);
    try {
      final png = await captureWrappedCard(_boundary);
      final directory = await getTemporaryDirectory();
      final file = await File(
        '${directory.path}${Platform.pathSeparator}chordia-grid.png',
      ).writeAsBytes(png);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          subject: t(
            widget.kind == EntityKind.album
                ? InsightsKeys.shareGridAlbumTitle
                : InsightsKeys.shareGridArtistTitle,
          ),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      showSocialMessage(context, t(InsightsKeys.shareGridFailed));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

/// The web's `<label>` around a checkbox: the label is the hit area, so it — not the box — is what
/// has to clear the touch minimum.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: ChordiaRadius.smAll,
      onTap: () => onChanged(!value),
      child: SizedBox(
        height: ChordiaControl.sm,
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: (next) => onChanged(next ?? false),
            ),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
