import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/router.dart';
import 'package:chordia_mobile/features/admin/data/admin_providers.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/features/library/data/library_providers.dart';
import 'package:chordia_mobile/features/nav/account_menu.dart';
import 'package:chordia_mobile/features/nav/insights_tab.dart';
import 'package:chordia_mobile/features/nav/mobile_tab_bar.dart';
import 'package:chordia_mobile/features/nav/nav_drawer.dart';
import 'package:chordia_mobile/features/nav/nav_tabs.dart';
import 'package:chordia_mobile/features/social/data/social_providers.dart';
import 'package:chordia_mobile/features/social/profile_screen.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_mobile/i18n/translations_provider.dart';
import 'package:chordia_mobile/widgets/cover_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The navigation shell, against the web client it is a port of.
///
/// The web renders a mobile tree below its `md` breakpoint — `MobileTabBar.tsx`, `MobileNavDrawer.tsx`
/// and the top bar's hamburger — and this client's job is to be that tree, not a second opinion
/// about it. So the assertions here are deliberately literal: the four tabs, in order, with the web's
/// i18n keys; the drawer's list, in order, with the web's labels; and the Insights tab landing on the
/// listener's own profile the way `/app/insights` redirects to `/app/u/{handle}`.
///
/// Loaded once, in real async: `testWidgets` runs inside a fake-async zone where an asset read never
/// completes, so the catalogs have to be in hand before the first pump.
late Translations translations;

const _viewer = UserProfile(
  createdAt: 0,
  displayName: 'Kanin',
  handle: 'kanin',
  id: 'kanin-id',
);

const _mine = LibrarySummary(
  createdAt: 0,
  id: 'lib-1',
  name: 'Mine',
  ownerId: 'kanin-id',
  serverId: 'srv-1',
  trackCount: 900,
);

const _theirs = LibrarySummary(
  createdAt: 0,
  id: 'lib-2',
  name: 'Theirs',
  ownerId: 'dee-id',
  serverId: 'srv-2',
  trackCount: 40,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    translations = await Translations.load('en', bundle: rootBundle);
  });

  group('the tab bar', () {
    test('is the web\'s four tabs, in the web\'s order', () {
      expect(NavTab.values.map((tab) => tab.labelKey).toList(), <String>[
        CommonKeys.navHome,
        CommonKeys.navSearch,
        CommonKeys.navLibrary,
        CommonKeys.navInsights,
      ]);
      // "You" was invented by this client. The web has no such destination, and the things it held
      // moved to the drawer and to the Insights tab — see the drawer test below.
      expect(
        NavTab.values.map((tab) => tab.labelKey),
        isNot(contains(CommonKeys.navYou)),
      );
    });

    test('every tab resolves to a route', () {
      final router = _router();
      for (final tab in NavTab.values) {
        expect(
          router.configuration.findMatch(Uri.parse(tab.path)).isError,
          isFalse,
          reason: '${tab.name} (${tab.path}) does not resolve',
        );
      }
    });

    test('the branches are declared in tab order', () {
      // The shell reads `NavTab.values[shell.currentIndex]`, so a branch inserted out of order
      // labels one tab and navigates to another.
      final shell = _router().configuration.routes
          .whereType<StatefulShellRoute>()
          .single;
      expect(
        shell.branches
            .map((branch) => (branch.routes.single as GoRoute).path)
            .toList(),
        NavTab.values.map((tab) => tab.path).toList(),
      );
    });
  });

  group('the tab bar is drawn, not inherited', () {
    Future<void> pumpBar(WidgetTester tester, {int selected = 0}) =>
        tester.pumpWidget(
          ProviderScope(
            overrides: [translationsProvider.overrideWithValue(translations)],
            child: MaterialApp(
              theme: buildChordiaTheme(),
              home: Scaffold(
                body: MobileTabBar(currentIndex: selected, onSelected: (_) {}),
              ),
            ),
          ),
        );

    testWidgets("is not Material's NavigationBar", (tester) async {
      // The whole reason this widget exists. `NavigationBar` brings an indicator pill behind the
      // selected icon, its own height and its own ripple; the web's bar has none of the three, and
      // a phone wearing Material's shape in this app's colours is the complaint in miniature.
      await pumpBar(tester);
      expect(find.byType(MobileTabBar), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationDestination), findsNothing);
    });

    testWidgets('marks the selected tab in the accent, on icon and label', (
      tester,
    ) async {
      await pumpBar(tester, selected: 2);
      final context = tester.element(find.byType(MobileTabBar));
      final accent = context.surfaces.accent;
      final muted = Theme.of(context).colorScheme.onSurfaceVariant;

      Color iconColour(String label) => tester
          .widget<Icon>(
            find.descendant(
              of: find
                  .ancestor(of: find.text(label), matching: find.byType(Column))
                  .first,
              matching: find.byType(Icon),
            ),
          )
          .color!;
      Color textColour(String label) =>
          tester.widget<Text>(find.text(label)).style!.color!;

      final selected = translations(CommonKeys.navLibrary);
      final other = translations(CommonKeys.navHome);

      // `text-primary` on the web colours the glyph AND the word. Colouring only the icon is what
      // makes a tab bar look half-lit.
      expect(iconColour(selected), accent);
      expect(textColour(selected), accent);
      expect(iconColour(other), muted);
      expect(textColour(other), muted);
    });

    testWidgets('keeps the labels off the home-indicator inset', (
      tester,
    ) async {
      // `pb-(--safe-b)`: the inset is padding UNDER the bar's own height, not a slice taken out of
      // it, so a gesture-bar phone gets a taller bar rather than squashed labels.
      const inset = 34.0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [translationsProvider.overrideWithValue(translations)],
          child: MaterialApp(
            theme: buildChordiaTheme(),
            home: MediaQuery(
              data: const MediaQueryData(
                viewPadding: EdgeInsets.only(bottom: inset),
              ),
              // Loose constraints, the way a `Scaffold` gives its bottom bar. As `home` it would be
              // handed the whole screen tight and report the screen's height, measuring nothing.
              child: Align(
                alignment: Alignment.bottomCenter,
                child: MobileTabBar(currentIndex: 0, onSelected: (_) {}),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(MobileTabBar)).height,
        MobileTabBar.barHeight + inset,
      );
    });
  });

  group('the nav drawer', () {
    testWidgets('lists exactly the web\'s destinations, in order', (
      tester,
    ) async {
      await _pumpDrawer(tester, admin: false);

      expect(_labels(tester), <String>[
        translations(ManagerKeys.nav),
        // `MobileNavDrawer.tsx`, entry for entry, in its order.
        translations(CommonKeys.navFriends),
        translations(CommonKeys.navAllLibraries),
        translations(CatalogKeys.genresTitle),
        translations(CatalogKeys.labelsTitle),
        translations(SettingsKeys.equalizerTitle),
        translations(CommonKeys.navSettings),
        // Then the sidebar block's fixed rows — the web's system rows, minus Search (a tab here)
        // and minus the Manager (already above). Everything after these is the listener's own
        // content, which is a `NavDrawerEntityRow` and is asserted separately.
        translations(LibraryKeys.likedSongs),
        translations(LibraryKeys.downloadsNavLabel),
      ]);
      // The web's keybinds-help entry is deliberately absent: it lists chords a phone cannot type.
      expect(
        _labels(tester),
        isNot(contains(translations(CommonKeys.keybindsHelp))),
      );
    });

    testWidgets('keeps Admin out of an ordinary listener\'s drawer', (
      tester,
    ) async {
      await _pumpDrawer(tester, admin: false);
      expect(_labels(tester), isNot(contains(translations(AdminKeys.title))));
    });

    testWidgets('offers Admin to an admin, as the web does', (tester) async {
      await _pumpDrawer(tester, admin: true);
      expect(_labels(tester), contains(translations(AdminKeys.title)));
    });

    testWidgets('carries the sidebar block: the listener\'s own things', (
      tester,
    ) async {
      // The web's phone drawer hosts `<Sidebar variant="drawer" />`, and its tab bar is only four
      // entries BECAUSE of that ("Everything the rail carries ... lives in that drawer"). Leaving
      // it out sent anybody wanting a named playlist through the Library tab and a list.
      await _pumpDrawer(
        tester,
        admin: false,
        pins: const [
          PinnedItem(id: 'p1', kind: PinKind.artist, name: 'Pinned artist'),
        ],
        smart: const [
          SmartPlaylist(
            createdAt: 0,
            id: 's1',
            name: 'Auto mix',
            rules: SmartRules(),
            trackCount: 12,
          ),
        ],
        playlists: const [
          Playlist(createdAt: 0, id: 'pl1', name: 'Late night', trackCount: 30),
        ],
        libraries: const [_mine],
        shared: const [_theirs],
      );

      // Pins, smart playlists and hand-built playlists are entity rows: artwork and a name, the
      // shape the web's sidebar gives them.
      expect(_entityRows(tester), <String>[
        'Pinned artist',
        'Auto mix',
        'Late night',
      ]);
      // Libraries are icon rows, so they land in the destination list rather than beside the
      // artwork — same split the web draws.
      expect(_labels(tester), containsAllInOrder(<String>['Mine', 'Theirs']));
    });

    testWidgets('shows nothing of the block that has nothing in it', (
      tester,
    ) async {
      // A drawer opened before five requests land — or by an account with no playlists at all —
      // must not be a column of empty headings.
      await _pumpDrawer(tester, admin: false);

      expect(_entityRows(tester), isEmpty);
      expect(
        find.text(translations(LibraryKeys.sidebarPlaylists).toUpperCase()),
        findsNothing,
      );
      expect(
        find.text(translations(LibraryKeys.sidebarSharedWithYou).toUpperCase()),
        findsNothing,
      );
    });

    testWidgets('carries the account menu the web keeps in its top bar', (
      tester,
    ) async {
      // `UserMenu` is ungated on the web — it is on every /app page including a phone — and this
      // client had no equivalent anywhere, which is why signing out was four levels down.
      await _pumpDrawer(tester, admin: false);

      expect(find.byType(NavAccountButton), findsOneWidget);
      expect(find.byType(CoverArt), findsWidgets);
    });

    test('every destination it offers resolves from every tab', () {
      final router = _router();
      // The drawer pushes onto the CURRENT tab, so a destination registered under one branch only
      // is a dead row from the other three.
      const destinations = [
        'manager',
        'friends',
        'libraries',
        'genres',
        'labels',
        'settings',
        'admin',
        'insights',
        // The sidebar block. These were screens the Library tab pushed by hand; the drawer is built
        // above every branch navigator, so a route is the only thing it can push.
        'liked',
        'downloads',
        'smart/sp-1',
        'library/lib-1',
        'playlists/pl-1',
        'albums/al-1',
        'artists/ar-1',
        'radio/artist/ar-1',
        // The account menu's own list.
        'u/kanin',
      ];
      for (final tab in NavTab.values) {
        for (final destination in destinations) {
          final location = '${tab.path}/$destination';
          expect(
            router.configuration.findMatch(Uri.parse(location)).isError,
            isFalse,
            reason: '$location does not resolve',
          );
        }
      }
    });
  });

  group('the Insights tab', () {
    testWidgets('lands on the signed-in listener\'s own profile', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const OwnProfileScreen()));
      await tester.pump();
      await tester.pump();

      // Not a stats screen: the same profile route anybody else's handle opens, which is what
      // carries the banner, avatar, badges, bio and shelves with the reports as tabs inside it.
      expect(
        tester.widget<ProfileScreen>(find.byType(ProfileScreen)).handle,
        'kanin',
      );
    });

    test('the tab and the forwarding path both point at it', () {
      final router = _router();
      for (final location in ['/insights', '/home/insights']) {
        expect(
          router.configuration.findMatch(Uri.parse(location)).isError,
          isFalse,
          reason: '$location does not resolve',
        );
      }
    });
  });

  test('no registered route lands on the error page', () {
    final router = _router();
    final paths = _walk(router.configuration.routes, '');
    // A guard against the walk silently finding nothing and passing.
    expect(paths.length, greaterThan(40));

    for (final path in paths) {
      final location = path
          .split('/')
          .map((segment) => segment.startsWith(':') ? 'x' : segment)
          .join('/');
      expect(
        router.configuration.findMatch(Uri.parse(location)).isError,
        isFalse,
        reason: '$location lands on GoRouter\'s error page',
      );
    }
  });
}

GoRouter _router() {
  final router = buildRouter();
  addTearDown(router.dispose);
  return router;
}

/// Every path the router knows, as a location.
///
/// `StatefulShellRoute.routes` is the flattened set of its branches' routes, so a shell needs no
/// special case: only its branch roots are absolute, and everything under them is relative.
List<String> _walk(List<RouteBase> routes, String prefix) {
  final found = <String>[];
  for (final route in routes) {
    var here = prefix;
    if (route is GoRoute) {
      here = route.path.startsWith('/') ? route.path : '$prefix/${route.path}';
      found.add(here);
    }
    found.addAll(_walk(route.routes, here));
  }
  return found;
}

List<String> _labels(WidgetTester tester) => tester
    .widgetList<NavDrawerRow>(find.byType(NavDrawerRow))
    .map((row) => row.label)
    .toList();

/// Pumps the drawer over an empty page.
///
/// The sidebar block's five lists are taken as VALUES rather than as provider overrides, because
/// Riverpod 3 does not export the `Override` type and a helper cannot declare a parameter holding
/// them. Every one of them is supplied on every pump, empty by default: the real providers throw
/// without a hub, and Riverpod would retry that on a timer the test then outlives.
Future<void> _pumpDrawer(
  WidgetTester tester, {
  required bool admin,
  List<PinnedItem> pins = const [],
  List<SmartPlaylist> smart = const [],
  List<Playlist> playlists = const [],
  List<LibrarySummary> libraries = const [],
  List<LibrarySummary> shared = const [],
}) async {
  // Tall enough that the whole list is laid out: a `ListView` builds what fits, and a row that was
  // never built is indistinguishable from a row that is missing.
  tester.view.physicalSize = const Size(600, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        translationsProvider.overrideWithValue(translations),
        isAdminProvider.overrideWith((ref) => admin),
        viewerProvider.overrideWith((ref) => _viewer),
        pinsProvider.overrideWith((ref) => pins),
        smartPlaylistsProvider.overrideWith((ref) => smart),
        playlistsProvider.overrideWith((ref) => playlists),
        myLibrariesProvider.overrideWith((ref) => libraries),
        sharedLibrariesProvider.overrideWith((ref) => shared),
      ],
      child: const MaterialApp(
        home: Scaffold(drawer: NavDrawer(), body: SizedBox.shrink()),
      ),
    ),
  );
  tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
  // Fixed frames rather than `pumpAndSettle`: this app's player ticks twice a second, and a settle
  // in a suite that ever mounts it never returns.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The listener's own things, as the drawer draws them.
List<String> _entityRows(WidgetTester tester) => tester
    .widgetList<NavDrawerEntityRow>(find.byType(NavDrawerEntityRow))
    .map((row) => row.name)
    .toList();

Widget _app(Widget home) => ProviderScope(
  overrides: [
    translationsProvider.overrideWithValue(translations),
    viewerProvider.overrideWith((ref) => _viewer),
  ],
  child: MaterialApp(home: home),
);
