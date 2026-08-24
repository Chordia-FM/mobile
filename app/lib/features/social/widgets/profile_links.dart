import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../catalog/widgets/list_row.dart';

/// Platform slug → icon, label and display order.
///
/// The slugs and the order are `ArtistLinkBar`'s (`components/catalog/ArtistLinkBar.tsx`) — the
/// same fourteen the Hub validates for both `ArtistLink.kind` and `ProfileLink.kind`, which is why
/// one map serves an artist page and a listener's profile on both clients.
///
/// The **icons** are `ArtistLinkBar`'s too, glyph for glyph, now that both clients draw Phosphor.
/// Eleven of the fourteen have a real brand mark in the set and use it. The three Phosphor has no
/// mark for are the same three the web hand-draws in `components/ui/brand-icons`; a hand-drawn
/// path is not portable to a font glyph, so those carry a neutral stand-in and lean on the named
/// list beside them — which is the reason the web's below-`md` shape names every destination in
/// the first place.
final _platforms = <String, ({IconData icon, String label, int order})>{
  'website': (icon: PhosphorIcons.globeSimple(), label: 'Website', order: 0),
  'spotify': (icon: PhosphorIcons.spotifyLogo(), label: 'Spotify', order: 1),
  'apple_music': (
    icon: PhosphorIcons.appleLogo(),
    label: 'Apple Music',
    order: 2,
  ),
  'youtube_music': (
    icon: PhosphorIcons.youtubeLogo(),
    label: 'YouTube Music',
    order: 3,
  ),
  'youtube': (icon: PhosphorIcons.youtubeLogo(), label: 'YouTube', order: 4),
  'soundcloud': (
    icon: PhosphorIcons.soundcloudLogo(),
    label: 'SoundCloud',
    order: 5,
  ),
  // No Phosphor mark: `BandcampIcon` on the web.
  'bandcamp': (icon: PhosphorIcons.vinylRecord(), label: 'Bandcamp', order: 6),
  'tidal': (icon: PhosphorIcons.tidalLogo(), label: 'Tidal', order: 7),
  // No Phosphor mark: `DeezerIcon` on the web.
  'deezer': (icon: PhosphorIcons.waveform(), label: 'Deezer', order: 8),
  'instagram': (
    icon: PhosphorIcons.instagramLogo(),
    label: 'Instagram',
    order: 9,
  ),
  'twitter': (icon: PhosphorIcons.xLogo(), label: 'X', order: 10),
  'tiktok': (icon: PhosphorIcons.tiktokLogo(), label: 'TikTok', order: 11),
  'facebook': (
    icon: PhosphorIcons.facebookLogo(),
    label: 'Facebook',
    order: 12,
  ),
  // No Phosphor mark: `WikipediaIcon` on the web.
  'wikipedia': (
    icon: PhosphorIcons.bookOpenText(),
    label: 'Wikipedia',
    order: 13,
  ),
};

/// A profile's external links, as the one button the web shows below `md`.
///
/// A profile carries up to eight of these across fourteen platforms, and at the 44px every tap
/// target has to be on touch that is three wrapped rows of anonymous glyphs. The web collapses
/// them to a single button that opens a named list for exactly that reason, and the named list is
/// also the only shape that says where each link actually goes.
///
/// A slug this build does not know is dropped rather than shown generically — the web does the
/// same, on the grounds that a link whose destination cannot be named is a link nobody should be
/// tapping.
class ProfileLinkBar extends ConsumerWidget {
  const ProfileLinkBar({required this.links, super.key});

  final List<ProfileLink> links;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = _shown(links);
    if (shown.isEmpty) return const SizedBox.shrink();
    final t = ref.t;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: Icon(PhosphorIcons.linkSimple(), size: 18),
          label: Text(t(SocialKeys.followLinksOpen)),
          onPressed: () => _open(context, ref, shown),
        ),
      ),
    );
  }

  void _open(BuildContext context, WidgetRef ref, List<_Shown> shown) {
    final t = ref.t;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                t(CatalogKeys.artistLinksTitle),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final link in shown)
              ListRow(
                leading: Icon(link.icon),
                title: Text(link.label),
                trailing: Icon(PhosphorIcons.arrowSquareOut(), size: 18),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _launch(link.url);
                },
              ),
          ],
        ),
      ),
    );
  }

  static void _launch(String raw) {
    final url = Uri.tryParse(raw);
    // Free text on somebody else's profile: anything that is not a parseable web address is not
    // something this app hands to the platform browser.
    if (url == null || !url.hasScheme) return;
    launchUrl(url, mode: LaunchMode.externalApplication).ignore();
  }

  static List<_Shown> _shown(List<ProfileLink> links) {
    final shown = [
      for (final link in links)
        if (_platforms[link.kind] case final meta?)
          _Shown(
            url: link.url,
            icon: meta.icon,
            label: meta.label,
            order: meta.order,
          ),
    ]..sort((a, b) => a.order.compareTo(b.order));
    return shown;
  }
}

class _Shown {
  const _Shown({
    required this.url,
    required this.icon,
    required this.label,
    required this.order,
  });

  final String url;
  final IconData icon;
  final String label;
  final int order;
}
