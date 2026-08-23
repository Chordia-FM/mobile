import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/catalog_state.dart';
import '../social/data/social_providers.dart';
import '../social/profile_screen.dart';

/// Insights, which is the signed-in listener's **own profile**.
///
/// The web makes this literal: `/app/insights` and each of its report URLs `redirect` to
/// `/app/u/{your handle}` (`routes/_authed/app/insights/*.tsx`). Your own report is your own
/// profile, so there is no second surface to keep in step — and the entry points that say
/// "Insights" keep working without any of them having to know your handle.
///
/// This renders the profile rather than redirecting to it. A redirect out of a shell branch's root
/// would push the profile onto the tab and leave a back button pointing at an empty forwarder;
/// rendering it is the same page, in the place the tab already is.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewer = ref.watch(viewerProvider);
    final handle = viewer.value?.handle;
    if (handle != null) return ProfileScreen(handle: handle);

    // Nothing to show a profile *of* yet. The account read is the same one every social surface
    // makes, so this is normally one frame.
    return Scaffold(
      appBar: AppBar(title: Text(ref.t(InsightsKeys.title))),
      body: viewer.hasError
          ? CatalogError(
              title: ref.t(SocialKeys.profileLoadError),
              error: viewer.error,
              onRetry: () => ref.invalidate(viewerProvider),
            )
          : const CatalogDetailSkeleton(circularArt: true),
    );
  }
}
