import 'package:chordia_api/chordia_api.dart' show StationKind;
import 'package:chordia_mobile/app/router.dart';
import 'package:chordia_mobile/features/home/data/station.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Every path the app builds by hand, walked against the route table it builds by hand.
///
/// These two halves are written in different files and joined by string concatenation at the
/// moment somebody taps something, so nothing but a test can hold them together. It did come
/// apart: `radio/artist/{id}` — pushed by every "Made for you" card, every daily mix and every
/// radio pin — was never registered, so the entire shelf landed on GoRouter's error page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The tabs of the stateful shell. Every screen below is pushed RELATIVE to whichever one the
  /// listener is standing in, so a route registered under a single tab is broken from the other
  /// three — which is a thing that looks fine in a screenshot and is a dead end in the hand.
  const tabs = ['/home', '/search', '/library', '/insights'];

  /// What `CatalogNavigation`, `DiscoveryNavigation` and `SocialNavigation` push, with sample ids
  /// standing in for the path parameters. Keep this list in step with those three extensions:
  /// a `goTo…` with no line here is a link nothing checks.
  const pushedFromAnyTab = [
    'artists/ar-1',
    'artists/ar-1/discography',
    'albums/al-1',
    'tracks/tr-1',
    'genres',
    'genres/shoegaze',
    'labels',
    'labels/lb-1',
    'labels/unlabeled',
    'playlists/pl-1',
    'friends',
    'u/kanin',
    'albums/al-1/stats',
    'artists/ar-1/stats',
    'tracks/tr-1/stats',
    // A daily mix is its own destination, and pointedly not `radio/artist/{id}`: the Hub weaves the
    // two from different endpoints under different titles.
    'daily-mix/mx-1',
    'jump-back-in',
    'made-for-you',
    'radio/artist/ar-1',
    'radio/track/tr-1',
    'radio/album/al-1',
    'radio/genre/shoegaze',
    'radio/playlist/pl-1',
    // Everything the nav drawer offers. It is opened from whichever tab the listener is standing
    // in and pushes onto that tab, so a row of it registered under one branch is dead from three.
    'settings',
    'insights',
    'friends',
    'admin',
    'admin/users/us-1',
    'manager',
    'manager/artists/ar-1',
    'manager/discover/artists/mb-1',
    'manager/releases/rg-1',
    'libraries',
    'libraries/pair',
    'libraries/lib-1',
    'libraries/lib-1/overrides',
    'smart/new',
    // The sidebar block the nav drawer grew. These are screens the Library tab used to push
    // imperatively; the drawer sits above every branch navigator and can only push a route.
    'liked',
    'downloads',
    'smart/sp-1',
    'library/lib-1',
  ];

  late GoRouter router;
  setUp(() => router = buildRouter());
  tearDown(() => router.dispose());

  bool resolves(String location) =>
      !router.configuration.findMatch(Uri.parse(location)).isError;

  test('every screen the app links to is reachable from every tab', () {
    final dead = <String>[
      for (final tab in tabs)
        for (final suffix in pushedFromAnyTab)
          if (!resolves('$tab/$suffix')) '$tab/$suffix',
    ];
    expect(dead, isEmpty, reason: 'these pushes land on the error page');
  });

  test('the tab that used to own a screen no longer exists', () {
    // The invented "You" tab is gone: its Insights row is the Insights tab (which lands on your own
    // profile, as the web's `/app/insights` redirect does) and everything else it held is in the
    // nav drawer. Nothing may keep linking to it.
    expect(resolves('/you'), isFalse);
    expect(resolves('/you/settings'), isFalse);
  });

  test('the roots and the auth screens resolve', () {
    for (final location in [...tabs, '/', '/sign-in', '/register']) {
      expect(resolves(location), isTrue, reason: location);
    }
  });

  test('a path nobody registered still errors', () {
    // Without this the checks above would pass just as happily against a router that matched
    // everything, which is the shape a routing test usually rots into.
    expect(resolves('/home/nothing-here/at-all'), isFalse);
    expect(resolves('/home/radio'), isFalse);
  });

  group('a link somebody shared from the web client', () {
    /// The paths a copied Chordia link actually carries.
    ///
    /// The long form is what `/app/...` pages are; the short form is what the web's `shareUrl()`
    /// writes, having dropped the `/app` prefix — both are served, so both arrive. Keep this list
    /// in step with the App Link filter in `android/app/src/main/AndroidManifest.xml`: a path
    /// registered there and missing here is one nobody checks can be opened.
    const shared = [
      '/app',
      '/app/albums/al-1',
      '/app/artists/ar-1',
      '/app/artists/ar-1/discography',
      '/app/albums/al-1/stats',
      '/app/artists/ar-1/stats',
      '/app/tracks/tr-1/stats',
      '/app/tracks/tr-1',
      '/app/playlists/pl-1',
      '/app/smart/sp-1',
      '/app/genres',
      '/app/genres/shoegaze',
      '/app/labels',
      '/app/labels/lb-1',
      '/app/u/kanin',
      '/app/daily-mix/mx-1',
      '/app/radio/artist/ar-1',
      '/app/jump-back-in',
      '/app/made-for-you',
      '/app/liked',
      '/app/downloads',
      '/app/friends',
      '/app/settings',
      '/app/manager',
      '/app/search',
      '/app/insights',
      '/app/library',
      '/app/library/lib-1',
      // The short forms, exactly as `shareUrl()` emits them.
      '/albums/al-1',
      '/artists/ar-1',
      '/tracks/tr-1',
      '/playlists/pl-1',
      '/genres/shoegaze',
      '/labels/lb-1',
      '/smart/sp-1',
      '/u/kanin',
    ];

    test('lands on the screen it names rather than on the error page', () {
      // The whole point of registering an App Link. Opening the app onto GoRouter's error page is
      // strictly worse than letting the browser have the link, so every path the manifest claims
      // has to translate into one this router knows.
      final dead = <String>[];
      for (final link in shared) {
        final translated = webLocationToTabLocation(Uri.parse(link));
        if (translated == null || !resolves(translated)) dead.add(link);
      }
      expect(dead, isEmpty, reason: 'these shared links open onto nothing');
    });

    test('keeps its query string', () {
      // `/app/badges?kind=` is the web's badge deep link. Its screen is still owed here, so this
      // asserts the translation only — but the query is what the destination is FOR, and dropping
      // it silently is the sort of thing only noticed once something reads one.
      expect(
        webLocationToTabLocation(Uri.parse('/app/badges?kind=super-sonic')),
        '/home/badges?kind=super-sonic',
      );
    });

    test('a path of this client\'s own is left alone', () {
      // The rewrite runs on every navigation, so anything it touches that it should not is a loop
      // or a wrong destination on an ordinary tap.
      for (final location in [
        '/home',
        '/search',
        '/library',
        '/insights',
        '/home/albums/al-1',
        '/library/liked',
        '/sign-in',
        '/',
      ]) {
        expect(
          webLocationToTabLocation(Uri.parse(location)),
          isNull,
          reason: location,
        );
      }
    });

    test('the web\'s two "library" pages do not collide', () {
      // The web's Library tab is the server directory; this client's is its collections hub. The
      // short-link set deliberately excludes `library` so `/library/lib-1` stays the tab's own.
      expect(
        webLocationToTabLocation(Uri.parse('/app/library')),
        '/home/libraries',
      );
      expect(
        webLocationToTabLocation(Uri.parse('/app/library/lib-1')),
        '/home/library/lib-1',
      );
      expect(webLocationToTabLocation(Uri.parse('/library/lib-1')), isNull);
    });
  });

  group('a station kind off the URL', () {
    test('is only accepted when it is one', () {
      for (final kind in StationKind.values) {
        expect(stationKindFromSegment(kind.wire), kind);
      }
    });

    test('is rejected rather than guessed at', () {
      // `StationKind.fromWire` falls back to `artist`, which is right for a payload from a newer
      // server and wrong here: it would send the Hub looking for an artist under a typo.
      expect(stationKindFromSegment('atrist'), isNull);
      expect(stationKindFromSegment(''), isNull);
    });
  });
}
