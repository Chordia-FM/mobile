import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/providers.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/data/playback/adaptive.dart';
import 'package:chordia_mobile/features/catalog/data/catalog_providers.dart';
import 'package:chordia_mobile/features/lyrics/data/lyrics_providers.dart';
import 'package:chordia_mobile/features/lyrics/data/lyrics_repository.dart';
import 'package:chordia_mobile/features/lyrics/lyrics_screen.dart';
import 'package:chordia_mobile/features/player/now_playing_detail.dart';
import 'package:chordia_mobile/features/player/quality_sheet.dart';
import 'package:chordia_mobile/features/player/queue_panel.dart';
import 'package:chordia_mobile/features/settings/data/settings_controller.dart';
import 'package:chordia_mobile/features/settings/data/settings_patch.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_player/chordia_player.dart' show QueueController;
import 'package:chordia_sync/chordia_sync.dart' show PlayerTrack, TrackArtist;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loaded once, in real async: `testWidgets` runs inside a fake-async zone where an asset read
/// never completes, so the catalogs have to be in hand before the first pump.
late Translations translations;

PlayerTrack _track(String id, {String? albumId, int? plays}) => PlayerTrack(
  id: id,
  title: 'Title $id',
  artist: 'Drake feat. Rihanna',
  artistId: 'ar-1',
  artists: const [
    TrackArtist(id: 'ar-1', name: 'Drake'),
    TrackArtist(id: 'ar-2', name: 'Rihanna'),
  ],
  album: 'Take Care',
  albumId: albumId,
  plays: plays,
  durationMs: 210000,
  libraryId: 'lib-1',
  trackRef: 'ref-$id',
  contentHash: 'hash-$id',
);

const _status = QualityStatus(
  chosen: QualityProfile.high,
  ceiling: QualityProfile.high,
  playing: QualityProfile.high,
  fixed: false,
);

QualityControl _control([QualityStatus status = _status]) =>
    QualityControl(status: ValueNotifier(status), restore: () async {});

/// The app frame around one widget under test.
///
/// The [ProviderScope] is left to the call site rather than folded in here: Riverpod 3 does not
/// export the `Override` type, so a helper cannot declare a parameter to take a list of them.
Widget _screen(Widget child) => MaterialApp(
  theme: buildChordiaTheme(),
  home: Scaffold(body: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    translations = await Translations.load('en', bundle: rootBundle);
  });

  group('the queue panel remembers what was played', () {
    test('the panel can see the history the queue controller already kept', () {
      // The engine has recorded this since the queue was written; what was missing was any way for
      // the UI layer to read it. Cut the provider's subscription and this test goes back to
      // reporting an empty list forever, which is exactly the bug it stands for.
      final queue = QueueController();
      final container = ProviderContainer(
        overrides: [queueControllerProvider.overrideWithValue(queue)],
      );
      addTearDown(container.dispose);

      expect(container.read(playerHistoryProvider), isEmpty);

      queue.playQueue([_track('a'), _track('b'), _track('c')]);
      expect(container.read(playerHistoryProvider), isEmpty);

      queue.next();
      expect(container.read(playerHistoryProvider).map((t) => t.id), ['a']);
      queue.next();
      // Most recent first, which is the order the list is read in.
      expect(container.read(playerHistoryProvider).map((t) => t.id), [
        'b',
        'a',
      ]);
    });

    testWidgets('"Recently played" lists it, and every row can replay', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            translationsProvider.overrideWithValue(translations),
            playerStateProvider.overrideWith(_EmptyQueue.new),
            playerHistoryProvider.overrideWith(
              () => _FixedHistory([_track('a'), _track('b')]),
            ),
          ],
          child: _screen(const QueuePanel()),
        ),
      );
      await tester.pump();

      // The panel opens on "Next up" — the history is the other half of a segmented control, and
      // without that control there is no way to reach it at all.
      expect(find.text(translations(PlayerKeys.queueRecentlyPlayed)), findsOne);
      expect(find.text('Title a'), findsNothing);

      await tester.tap(find.text(translations(PlayerKeys.queueRecentlyPlayed)));
      await tester.pump();

      expect(find.text('Title a'), findsOne);
      expect(find.text('Title b'), findsOne);
      expect(
        find.text(translations(PlayerKeys.queueNothingPlayed)),
        findsNothing,
      );
      // Each row plays that track again. A history you can only look at is half the feature.
      for (final row in tester.widgetList<QueueRow>(find.byType(QueueRow))) {
        expect(row.onPlay, isNotNull);
      }
    });

    testWidgets('an empty history says so rather than showing nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            translationsProvider.overrideWithValue(translations),
            playerStateProvider.overrideWith(_EmptyQueue.new),
            playerHistoryProvider.overrideWith(() => _FixedHistory(const [])),
          ],
          child: _screen(const QueuePanel()),
        ),
      );
      await tester.pump();
      await tester.tap(find.text(translations(PlayerKeys.queueRecentlyPlayed)));
      await tester.pump();

      expect(find.text(translations(PlayerKeys.queueNothingPlayed)), findsOne);
    });
  });

  group('the now-playing detail below the transport', () {
    Future<void> pumpDetail(
      WidgetTester tester, {
      required PlayerTrack track,
      AudioProperties? audio,
      ArtistDetail? artist,
      int? freshPlays,
      bool normalize = false,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            translationsProvider.overrideWithValue(translations),
            qualityControlProvider.overrideWithValue(_control()),
            playbackPreferencesProvider.overrideWithValue(
              PlaybackPreferences(normalizeVolume: normalize),
            ),
            trackDetailProvider(track.id).overrideWith(
              (ref) async => _browseTrack(track, plays: freshPlays),
            ),
            for (final id in ['ar-1', 'ar-2'])
              artistDetailProvider(id).overrideWith((ref) async {
                if (artist == null || artist.id != id) {
                  throw StateError('no artist $id');
                }
                return artist;
              }),
            currentAudioProvider(track).overrideWith((ref) async => audio),
          ],
          child: _screen(
            SingleChildScrollView(child: NowPlayingDetail(track: track)),
          ),
        ),
      );
      // One frame to build, one for the three reads to land.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
    }

    testWidgets('names the album and the fresh play count', (tester) async {
      await pumpDetail(
        tester,
        track: _track('a', albumId: 'al-1', plays: 3),
        freshPlays: 41,
      );

      // A link, not a caption: the album was reachable only from the player's overflow menu, and
      // the web puts it here as a link precisely because that is where it is looked for.
      expect(
        find.ancestor(
          of: find.text('Take Care'),
          matching: find.byType(InkWell),
        ),
        findsOne,
      );
      // The queue entry says 3; the catalog read says 41. The panel exists to show the current
      // number, so taking the stale one back would be the regression.
      expect(
        find.text(translations(PlayerKeys.plays, {'count': 41})),
        findsOne,
      );
    });

    testWidgets('carries an About-the-artist card per credited artist', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        track: _track('a'),
        artist: _artist('ar-2', 'Rihanna'),
      );

      // Only the artist that resolved: a card that cannot be filled draws nothing rather than an
      // error box under the transport.
      expect(
        find.text(
          translations(PlayerKeys.nowPlayingAboutArtist, {'name': 'Rihanna'}),
        ),
        findsOne,
      );
      expect(
        find.text(
          translations(PlayerKeys.nowPlayingAboutArtist, {'name': 'Drake'}),
        ),
        findsNothing,
      );
      expect(
        find.text(translations(PlayerKeys.monthlyListeners, {'count': 90210})),
        findsOne,
      );
      expect(find.text('pop · r&b'), findsOne);
      expect(find.textContaining('Barbadian'), findsOne);
    });

    testWidgets('reads out the source format and the measured loudness', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        track: _track('a'),
        audio: const AudioProperties(
          bitDepth: 24,
          channels: 2,
          codec: 'flac',
          lossless: true,
          sampleRateHz: 96000,
          spatial: false,
          gainDb: -6.25,
        ),
        normalize: true,
      );

      expect(find.text(translations(PlayerKeys.qualitySource)), findsOne);
      // Bit depth, sample rate and codec, in the order the web writes them for a lossless file.
      expect(find.text('24-bit · 96 kHz · FLAC'), findsOne);
      // The tier actually arriving, not the one in settings.
      expect(
        find.textContaining(translations(SettingsKeys.qualityHighLabel)),
        findsOne,
      );
      expect(find.text('-6.3 dB'), findsOne);
    });

    testWidgets('says nothing about loudness when nothing applies it', (
      tester,
    ) async {
      // The gain is measured either way; with normalisation off it is not applied, so reporting it
      // would claim a loudness nothing is doing anything about.
      await pumpDetail(
        tester,
        track: _track('a'),
        audio: const AudioProperties(
          bitDepth: 16,
          channels: 2,
          codec: 'mp3',
          lossless: false,
          sampleRateHz: 44100,
          spatial: false,
          gainDb: -6.25,
        ),
      );

      expect(find.text(translations(PlayerKeys.qualityLoudness)), findsNothing);
      // A lossy source states its codec and rate, and no bit depth — that number describes the
      // decoder's output, not the file.
      expect(find.text('MP3 · 44.1 kHz'), findsOne);
    });
  });

  group('the quality sheet', () {
    testWidgets('changes the tier in place instead of only reporting it', (
      tester,
    ) async {
      final settings = _RecordingSettings();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            translationsProvider.overrideWithValue(translations),
            qualityControlProvider.overrideWithValue(_control()),
            settingsControllerProvider.overrideWith(() => settings),
          ],
          child: _screen(const QualitySheet()),
        ),
      );
      await tester.pump();

      await tester.tap(
        find.text(translations(SettingsKeys.qualityDataSaverLabel)),
      );
      await tester.pump();

      // Persisted through the same call the settings screen makes — the reason the rows were inert
      // was a belief that a tap here could not stick, and it can.
      expect(settings.patches, hasLength(1));
      expect(
        settings.patches.single.streamingQuality,
        QualityProfile.dataSaver,
      );
    });

    testWidgets('the tier already chosen is not a tap that does nothing', (
      tester,
    ) async {
      final settings = _RecordingSettings();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            translationsProvider.overrideWithValue(translations),
            qualityControlProvider.overrideWithValue(_control()),
            settingsControllerProvider.overrideWith(() => settings),
          ],
          child: _screen(const QualitySheet()),
        ),
      );
      await tester.pump();

      await tester.tap(find.text(translations(SettingsKeys.qualityHighLabel)));
      await tester.pump();

      expect(settings.patches, isEmpty);
    });
  });

  group('lyrics are set at display size', () {
    /// `LyricsView.tsx:219` — `font-bold text-3xl leading-snug`, which is 30px at 700 on a phone.
    void expectDisplayType(TextStyle? style) {
      expect(style?.fontSize, 30);
      expect(style?.fontWeight, FontWeight.w700);
    }

    Future<void> pumpLyrics(WidgetTester tester, Lyrics lyrics) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            translationsProvider.overrideWithValue(translations),
            lyricsRepositoryProvider.overrideWithValue(
              LyricsRepository(fetch: (_) async => lyrics),
            ),
            playerPositionProvider.overrideWith(
              (ref) => Stream.value(Duration.zero),
            ),
          ],
          child: _screen(LyricsBody(track: _track('a'))),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
    }

    testWidgets('synced lines, current and not', (tester) async {
      await pumpLyrics(
        tester,
        const Lyrics(
          trackId: 'a',
          syncType: LyricsSyncType.lineSYNCED,
          lines: [
            LyricsLine(text: 'I know you say you know me', startMs: 0),
            LyricsLine(text: 'But I know you better', startMs: 4000),
          ],
        ),
      );

      for (final text in [
        'I know you say you know me',
        'But I know you better',
      ]) {
        expectDisplayType(
          tester
              .widget<AnimatedDefaultTextStyle>(
                find
                    .ancestor(
                      of: find.text(text),
                      matching: find.byType(AnimatedDefaultTextStyle),
                    )
                    .first,
              )
              .style,
        );
      }
    });

    testWidgets('an untimed document reads at the same size', (tester) async {
      await pumpLyrics(
        tester,
        const Lyrics(
          trackId: 'a',
          syncType: LyricsSyncType.unsynced,
          lines: [LyricsLine(text: 'No timing on this one')],
        ),
      );

      expectDisplayType(
        tester.widget<Text>(find.text('No timing on this one')).style,
      );
    });
  });
}

/// Nothing queued, so the "Next up" half draws its empty state instead of reaching for the audio
/// handler — which no test binding can start.
class _EmptyQueue extends PlayerStateNotifier {
  @override
  PlayerSnapshot build() => PlayerSnapshot.empty;
}

/// The queue's history, frozen — the widget tests are about what the panel draws, and the wire from
/// the controller to this provider has its own test above.
class _FixedHistory extends PlayerHistoryNotifier {
  _FixedHistory(this._history);

  final List<PlayerTrack> _history;

  @override
  List<PlayerTrack> build() => _history;
}

/// Records what was written instead of reaching a Hub.
class _RecordingSettings extends SettingsController {
  final patches = <SettingsPatch>[];

  @override
  Future<UserSettings> build() async => const UserSettings(
    streamingQuality: QualityProfile.high,
    normalizeVolume: false,
    autoplay: true,
    crossfadeSeconds: 0,
    preloadCount: 2,
    accent: 'pink',
    scrobble: true,
    scrobblePrivacy: ScrobblePrivacy.friends,
    eq: EqConfig(bands: [], enabled: true, preamp: 0),
  );

  @override
  Future<bool> patch(SettingsPatch change) async {
    patches.add(change);
    return true;
  }
}

BrowseTrack _browseTrack(PlayerTrack track, {int? plays}) => BrowseTrack(
  id: track.id,
  title: track.title,
  artist: track.artist,
  album: track.album,
  albumId: track.albumId,
  artistId: track.artistId,
  contentHash: track.contentHash,
  durationMs: track.durationMs,
  libraryId: track.libraryId,
  trackRef: track.trackRef,
  plays: plays,
);

ArtistDetail _artist(String id, String name) => ArtistDetail(
  id: id,
  name: name,
  albums: const [],
  topTracks: const [],
  monthlyListeners: 90210,
  genres: const ['pop', 'r&b', 'dancehall'],
  bio: 'Barbadian singer, and the guest verse you just heard.',
);
