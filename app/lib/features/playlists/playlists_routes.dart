import 'package:go_router/go_router.dart';

import 'smart_rules_screen.dart';

/// Playlist editing that needs a screen of its own.
///
/// Almost everything else here is a sheet raised over whatever raised it — creating a playlist,
/// picking one to add to, editing collaborators — because those are momentary and should not put
/// an entry in the back stack. The rule builder is the exception: it is long enough to leave and
/// come back to.
List<RouteBase> playlistsRoutes() => [
  GoRoute(
    path: 'smart/new',
    builder: (context, state) =>
        SmartRulesScreen(seedName: state.extra as String?),
  ),
];
