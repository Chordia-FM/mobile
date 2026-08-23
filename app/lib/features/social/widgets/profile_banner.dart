import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/art/art_cache.dart';

/// The wide image across the top of a profile.
///
/// **The box is reserved before the image resolves, and that is the whole point.** On the web this
/// carries the comment that `scroll-mt` was not enough on its own: the banner's box had no height
/// until the image decoded, so a restored scroll position was measured against a shorter page and
/// the profile landed part-scrolled. `aspect-[3/1]` reserves the height up front. Here the same
/// hazard is a list that jumps a third of the screen width downwards the moment the file comes off
/// disk, so the [AspectRatio] is built as soon as the hash is known — synchronously, from the URL —
/// and the picture fades into a box that was already the right size.
///
/// 3:1 is the web's below-`md` ratio. Its 4:1 is the desktop one and has no place on a phone.
class ProfileBanner extends ConsumerStatefulWidget {
  const ProfileBanner({required this.bannerUrl, super.key});

  /// The Hub image reference exactly as the DTO carries it, or null for an account with no banner.
  final String? bannerUrl;

  @override
  ConsumerState<ProfileBanner> createState() => _ProfileBannerState();
}

class _ProfileBannerState extends ConsumerState<ProfileBanner> {
  File? _file;

  /// The request in flight, so a late answer for a profile we have navigated away from cannot
  /// paint over the one now on screen.
  Object? _token;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(ProfileBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bannerUrl != widget.bannerUrl) _load();
  }

  Future<void> _load() async {
    final hash = artHashOf(widget.bannerUrl);
    if (hash == null) {
      setState(() => _file = null);
      return;
    }
    final token = Object();
    _token = token;
    final size = MediaQuery.sizeOf(context);
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    // The biggest asset on the page, so it is asked for at the width it will be drawn at rather
    // than at whatever the original upload was — the web resizes it to 512 for the same reason.
    final file = await ref
        .read(artCacheProvider)
        .file(hash, width: (size.width * ratio).ceil());
    if (!mounted || !identical(_token, token)) return;
    setState(() => _file = file);
  }

  @override
  Widget build(BuildContext context) {
    // No banner is no box: the web renders the whole block only when `banner_url` is set, and an
    // empty third-of-the-screen gap above the avatar is worse than no picture.
    if (artHashOf(widget.bannerUrl) == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final file = _file;

    return AspectRatio(
      aspectRatio: 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: scheme.surfaceContainerHighest),
          if (file != null)
            Image.file(
              file,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          // The soft bottom wash, so the banner fades into the page instead of ending on a hard
          // photo edge above the identity block.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  scheme.surface,
                  scheme.surface.withValues(alpha: 0.5),
                  Colors.transparent,
                ],
                stops: const [0, 0.35, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
