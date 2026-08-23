import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/router.dart';
import 'package:chordia_mobile/features/admin/data/admin_providers.dart';
import 'package:chordia_mobile/features/nav/insights_tab.dart';
import 'package:chordia_mobile/features/nav/nav_drawer.dart';
import 'package:chordia_mobile/features/nav/nav_tabs.dart';
import 'package:chordia_mobile/features/social/data/social_providers.dart';
import 'package:chordia_mobile/features/social/profile_screen.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_mobile/i18n/translations_provider.dart';
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

  group('the nav drawer', () {
    testWidgets('lists exactly the web\'s destinations, in order', (
      tester,
    ) async {
      await _pumpDrawer(tester, admin: false);

      expect(_labels(tester), <String>[
        // Above the rule the web hosts its whole sidebar. Everything in it is the Library tab on
        // this client except the Manager, which would otherwise have nowhere to be opened from.
        translations(ManagerKeys.nav),
        // Below the rule: `MobileNavDrawer.tsx`, entry for entry, in its order.
        translations(CommonKeys.navFriends),
        translations(CommonKeys.navAllLibraries),
        translations(CatalogKeys.genresTitle),
        translations(CatalogKeys.labelsTitle),
        translations(SettingsKeys.equalizerTitle),
        translations(CommonKeys.navSettings),
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

Future<void> _pumpDrawer(WidgetTester tester, {required bool admin}) async {
  // Tall enough that the whole list is laid out: a `ListView` builds what fits, and a row that was
  // never built is indistinguishable from a row that is missing.
  tester.view.physicalSize = const Size(600, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_drawerApp(admin: admin));
  tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
  // Fixed frames rather than `pumpAndSettle`: this app's player ticks twice a second, and a settle
  // in a suite that ever mounts it never returns.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Widget _drawerApp({required bool admin}) => ProviderScope(
  overrides: [
    translationsProvider.overrideWithValue(translations),
    isAdminProvider.overrideWith((ref) => admin),
  ],
  child: const MaterialApp(
    home: Scaffold(drawer: NavDrawer(), body: SizedBox.shrink()),
  ),
);

Widget _app(Widget home) => ProviderScope(
  overrides: [
    translationsProvider.overrideWithValue(translations),
    viewerProvider.overrideWith(
      (ref) => const UserProfile(
        createdAt: 0,
        displayName: 'Kanin',
        handle: 'kanin',
        id: 'kanin-id',
      ),
    ),
  ],
  child: MaterialApp(home: home),
);
