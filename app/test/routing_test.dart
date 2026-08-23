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
