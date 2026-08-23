import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/catalog_state.dart';
import '../social/data/social_providers.dart';
import '../social/profile_screen.dart';
import 'nav_drawer.dart';

/// The Insights tab lands on the listener's OWN PROFILE, because that is what the web does.
///
/// `src/routes/_authed/app/insights/index.tsx` is a redirect to `/app/u/{handle}` and nothing else:
/// "Insights folded into the profile: your own report is your own profile, so there is no second
/// surface to keep in step." The reports are tabs inside that profile, under the banner, avatar,
/// badges, stat row, bio and shelves — a separate stats screen is exactly the thing the owner
/// asked us to stop building.
///
/// The handle comes from [viewerProvider] rather than from `authControllerProvider`, whose `user`
/// is only populated when the session was established in this run of the app.
class OwnProfileScreen extends ConsumerWidget {
  const OwnProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewer = ref.watch(viewerProvider);
    final handle = viewer.value?.handle;
    if (handle != null) return ProfileScreen(handle: handle);

    // No handle yet: the profile cannot be named, so this stands in until it can. The web's
    // equivalent renders nothing for the same beat and then forwards.
    return Scaffold(
      appBar: AppBar(
        leading: const NavMenuButton(),
        title: Text(ref.t(CommonKeys.navInsights)),
      ),
      body: viewer.hasError
          ? CatalogError(
              title: ref.t(SocialKeys.profileLoadError),
              error: viewer.error,
              onRetry: () => ref.invalidate(viewerProvider),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

/// `insights` under a tab root, forwarding to the same place the tab itself lands.
///
/// The web keeps its `/app/insights` URL alive as a forward rather than deleting it, "because the
/// entry points that point here — the user menu, the command palette, the `g i` chord, any
/// bookmark — need no knowledge of your handle to keep working". `context.goToInsights()` is this
/// client's version of those entry points, so the path stays registered in every tab.
List<RouteBase> insightsTabRoutes() => [
  GoRoute(
    path: 'insights',
    builder: (context, state) => const OwnProfileScreen(),
  ),
];
