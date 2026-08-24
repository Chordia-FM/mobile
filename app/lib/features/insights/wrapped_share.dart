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
import '../catalog/format.dart' show titleCaseGenre;
import '../social/data/social_messages.dart';
import '../social/widgets/person_row.dart' show showSocialMessage;
import 'format.dart';
import 'wrapped_card.dart';

/// Thumbnail width asked of the art cache for the card.
///
/// The card draws them at 72px; 96 is the smallest rung on the Hub's width ladder that covers that,
/// and asking for anything off the ladder gets the **original** back — which on a fanart.tv source
/// is several megabytes for a 72px square.
const _cardThumbWidth = 96;

/// Builds the card's content from a report, fetching the covers it needs.
///
/// Cover reads are allowed to fail individually: [WrappedCardEntry] treats a null as "draw a tinted
/// tile", so an artist the Hub has no picture for costs one thumbnail rather than the whole card.
Future<WrappedCardData> buildWrappedCardData({
  required WrappedReport report,
  required ArtCache art,
  required Translate t,
  required String locale,
  required String handle,
}) async {
  final numbers = NumberFormat.decimalPattern(locale);

  Future<List<WrappedCardEntry>> entries(List<TopItem> items) =>
      Future.wait([for (final item in items.take(5)) _entryFor(item, art)]);

  final artists = await entries(report.topArtists);
  final tracks = await entries(report.topTracks);

  return WrappedCardData(
    heading: t(InsightsKeys.rotationHeading),
    subheading: rotationPeriodTitle(report.period, t),
    handle: handle.isEmpty ? '' : '@$handle',
    heroValue: numbers.format((report.totalMsPlayed / 60000).round()),
    heroLabel: t(InsightsKeys.rotationMinutesListened),
    statLine: t(InsightsKeys.rotationStatLine, {
      'artists': report.uniqueArtists,
      'tracks': report.uniqueTracks,
    }),
    topArtistsLabel: t(InsightsKeys.rotationTopArtists),
    topArtists: artists,
    topTracksLabel: t(InsightsKeys.rotationTopTracks),
    topTracks: tracks,
    topGenreLabel: report.topGenres.isEmpty
        ? null
        : t(InsightsKeys.rotationTopGenre),
    topGenre: report.topGenres.isEmpty
        ? null
        : titleCaseGenre(report.topGenres.first.name),
    footer: t(CommonKeys.appName),
  );
}

Future<WrappedCardEntry> _entryFor(TopItem item, ArtCache art) async {
  final hash = artHashOf(item.imageUrl);
  if (hash == null) return WrappedCardEntry(name: item.name);
  try {
    final file = await art.file(hash, width: _cardThumbWidth);
    return WrappedCardEntry(
      name: item.name,
      cover: file == null ? null : await file.readAsBytes(),
    );
  } on Object {
    // A cover that will not come off disk is a missing cover, not a failed share.
    return WrappedCardEntry(name: item.name);
  }
}

/// Shows the card, then shares it as a PNG.
///
/// A preview rather than a straight-to-share-sheet: this image carries somebody's listening under
/// their handle, and seeing what is about to leave the phone is the difference between a share and
/// a surprise. It also means the covers are decoded and painted before the capture, which is what
/// makes the PNG contain artwork rather than five empty squares.
Future<void> shareWrappedCard(
  BuildContext context,
  WidgetRef ref,
  WrappedReport report, {
  required String handle,
}) async {
  final translations = ref.read(translationsProvider);
  final t = translations.call;
  final data = await buildWrappedCardData(
    report: report,
    art: ref.read(artCacheProvider),
    t: t,
    locale: translations.locale,
    handle: handle,
  );
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _WrappedPreview(data: data),
  );
}

class _WrappedPreview extends ConsumerStatefulWidget {
  const _WrappedPreview({required this.data});

  final WrappedCardData data;

  @override
  ConsumerState<_WrappedPreview> createState() => _WrappedPreviewState();
}

class _WrappedPreviewState extends ConsumerState<_WrappedPreview> {
  final _boundary = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    final t = ref.read(translationsProvider).call;
    setState(() => _sharing = true);
    try {
      final png = await captureWrappedCard(_boundary);
      final file = await _writeCard(png);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          subject: t(InsightsKeys.rotationHeading),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      showSocialMessage(context, describeSocialError(error, t));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Written to the cache directory rather than kept in memory: the share sheet takes a file, and
  /// an OS storage sweep is welcome to take this copy back once it has been shared.
  Future<File> _writeCard(Uint8List png) async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}chordia-rotation.png',
    );
    return file.writeAsBytes(png);
  }

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
                // Scales the painted card down to the sheet. The card still LAYS OUT at its own
                // pixel size, which is what keeps the capture 1080×1350 on every device.
                child: WrappedCard(data: widget.data, boundaryKey: _boundary),
              ),
            ),
            const SizedBox(height: 16),
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
}
