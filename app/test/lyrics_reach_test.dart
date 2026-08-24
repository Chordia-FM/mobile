import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/providers.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/data/playback/adaptive.dart';
import 'package:chordia_mobile/features/lyrics/data/lyrics_providers.dart';
import 'package:chordia_mobile/features/lyrics/data/lyrics_repository.dart';
import 'package:chordia_mobile/features/player/full_player.dart';
import 'package:chordia_mobile/features/player/quality_sheet.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_sync/chordia_sync.dart'
    show PlayerTrack, RepeatMode, TrackArtist;
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loaded once, in real async: `testWidgets` runs inside a fake-async zone where an asset read
/// never completes, so the catalogs have to be in hand before the first pump.
late Translations translations;

/// A track with two credited artists and no artwork.
///
/// No cover on purpose: `CoverArt` short-circuits on a null hash, so the player draws without a
/// platform art directory behind it.
const _track = PlayerTrack(
  id: 'track-1',
  title: 'Take Care',
  artist: 'Drake feat. Rihanna',
  artistId: 'ar-1',
  artists: [
    TrackArtist(id: 'ar-1', name: 'Drake'),
    TrackArtist(id: 'ar-2', name: 'Rihanna'),
  ],
  album: 'Take Care',
  durationMs: 210000,
  libraryId: 'lib-1',
  trackRef: 'ref-1',
  contentHash: 'hash-1',
  advisory: 'explicit',
);

const _snapshot = PlayerSnapshot(
  current: _track,
  queue: [_track],
  currentIndex: 0,
  playing: true,
  buffering: false,
  shuffle: false,
  repeat: RepeatMode.off,
  sleepTimer: null,
  context: null,
);

/// The queue and the transport, frozen. The real notifier subscribes to the audio handler, which
/// no test binding can start.
class _FixedPlayerState extends PlayerStateNotifier {
  @override
  PlayerSnapshot build() => _snapshot;
}

const _lyrics = Lyrics(
  trackId: 'track-1',
  syncType: LyricsSyncType.lineSYNCED,
  lines: [
    LyricsLine(text: 'I know you say you know me', startMs: 0),
    LyricsLine(text: 'But I know you better', startMs: 4000),
  ],
);

/// A 404, as the Hub answers for a track with no lyrics.
const _missing = ApiException(
  status: 404,
  title: 'Not found',
  method: 'GET',
  path: '/v1/lyrics/track-1',
);

Widget _player({required LyricsFetcher fetch}) => ProviderScope(
  overrides: [
    translationsProvider.overrideWithValue(translations),
    playerStateProvider.overrideWith(_FixedPlayerState.new),
    // The playhead is a stream off the audio handler; one fixed sample keeps the scrubber honest
    // without an engine.
    playerPositionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
    lyricsRepositoryProvider.overrideWithValue(LyricsRepository(fetch: fetch)),
    // The quality readout is the player's other route to the engine: it reads the adaptive
    // controller, which reads the stream cache, which needs the cache directory only `bootstrap`
    // sets. A fixed status keeps the button on screen — it sits in the same row as the lyrics
    // control, so removing it would change the very layout under test.
    qualityControlProvider.overrideWithValue(
      QualityControl(
        status: ValueNotifier(
          const QualityStatus(
            chosen: QualityProfile.high,
            ceiling: QualityProfile.high,
            playing: QualityProfile.high,
            fixed: false,
          ),
        ),
        restore: () async {},
      ),
    ),
  ],
  child: MaterialApp(
    theme: buildChordiaTheme(),
    home: const FullPlayerScreen(),
  ),
);

/// Two frames: one to build, one for the lyrics answer to land. `pumpAndSettle` is not usable here
/// — the player's own tickers never settle.
Future<void> _open(WidgetTester tester, {required LyricsFetcher fetch}) async {
  await tester.pumpWidget(_player(fetch: fetch));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
}

/// The lyrics tab's tap target. Disabled when its `onTap` is null.
InkWell _lyricsControl(WidgetTester tester) => tester.widget<InkWell>(
  find
      .ancestor(
        of: find.text(translations(PlayerKeys.expandedLyrics)),
        matching: find.byType(InkWell),
      )
      .first,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    translations = await Translations.load('en', bundle: rootBundle);
  });

  testWidgets('the player carries a lyrics control that opens the lyrics', (
    tester,
  ) async {
    await _open(tester, fetch: (_) async => _lyrics);

    // An icon and a label in the player's own tab bar — not a text button in a row of three, which
    // is what made this feature unfindable.
    expect(find.byIcon(Icons.mic_external_on_rounded), findsOneWidget);
    expect(_lyricsControl(tester).onTap, isNotNull);

    await tester.tap(find.text(translations(PlayerKeys.expandedLyrics)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('I know you say you know me'), findsOneWidget);
    // The header keeps the song named while the words are on screen.
    expect(find.text('Take Care'), findsOneWidget);
  });

  testWidgets('a track with no lyrics disables the control and says why', (
    tester,
  ) async {
    await _open(tester, fetch: (_) async => throw _missing);

    // Present, so the feature is never silently absent; inert, so the tap does not open a view
    // whose only content is an apology.
    expect(find.byIcon(Icons.mic_external_on_rounded), findsOneWidget);
    expect(_lyricsControl(tester).onTap, isNull);
    expect(find.byTooltip(translations(PlayerKeys.lyricsNone)), findsOneWidget);
  });

  testWidgets('a read that failed leaves the control reachable', (
    tester,
  ) async {
    // Status 0 is a transport failure, which says nothing about the song. Disabling on it would
    // hide the lyrics of every track played in a tunnel until the app restarted.
    await _open(
      tester,
      fetch: (_) async => throw const ApiException(
        status: 0,
        title: 'Network unreachable',
        method: 'GET',
        path: '/v1/lyrics/track-1',
      ),
    );

    expect(_lyricsControl(tester).onTap, isNotNull);
  });

  testWidgets('the now-playing tab credits each artist as its own link', (
    tester,
  ) async {
    await _open(tester, fetch: (_) async => _lyrics);

    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere((text) => text.textSpan != null);
    final spans = [
      for (final span
          in (rendered.textSpan! as TextSpan).children ?? const <InlineSpan>[])
        if (span is TextSpan && span.recognizer != null) span,
    ];

    // Two links, not one string. The Hub's assembled "Drake feat. Rihanna" is the fallback, and
    // rendering it instead is exactly the regression this covers.
    expect(spans.map((span) => span.text), ['Drake', 'Rihanna']);
    // And the markers that qualify the recording, drawn beside the title as the catalog draws them.
    expect(
      find.text(translations(CatalogKeys.trackExplicitShort)),
      findsOneWidget,
    );
  });
}
