import 'dart:convert';

import 'package:chordia_db/chordia_db.dart';
import 'package:chordia_mobile/app/providers.dart';
import 'package:chordia_mobile/features/update/semver.dart';
import 'package:chordia_mobile/features/update/update_check.dart';
import 'package:chordia_mobile/features/update/update_sheet.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loaded once, in real async: `testWidgets` runs inside a fake-async zone where an asset read
/// never completes, so the catalogs have to be in hand before the first pump.
late Translations translations;

/// A day, in the milliseconds the checker counts in.
const _day = 24 * 60 * 60 * 1000;

AppRelease release(String version) => AppRelease(
  version: version,
  notesUrl: 'https://example.invalid/releases/v$version',
  download: const ReleaseDownload(
    filename: 'chordia-universal.apk',
    url: 'https://example.invalid/chordia-universal.apk',
    sizeBytes: 41000000,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    translations = await Translations.load('en', bundle: rootBundle);
  });

  group('version precedence', () {
    test('the ordinary case is a numeric comparison, field by field', () {
      expect(isNewer(candidate: '0.2.0', current: '0.1.9'), isTrue);
      expect(isNewer(candidate: '0.10.0', current: '0.9.0'), isTrue);
      // Not a string comparison: '0.10.0' sorts before '0.9.0' as text, and a version check that
      // got this wrong would stop offering updates the moment a minor hit double digits.
      expect(isNewer(candidate: '0.9.0', current: '0.10.0'), isFalse);
      expect(isNewer(candidate: '1.0.0', current: '0.99.99'), isTrue);
    });

    test('a pre-release ranks below the release it leads to', () {
      // The dev flavour ships `versionNameSuffix = "-dev"`, so this is the shape a developer's
      // phone actually reports — and 0.2.0 really is newer than 0.2.0-dev.
      expect(isNewer(candidate: '0.2.0', current: '0.2.0-dev'), isTrue);
      expect(isNewer(candidate: '0.2.0-dev', current: '0.2.0'), isFalse);
      expect(isNewer(candidate: '0.2.0-rc.1', current: '0.1.9'), isTrue);
    });

    test('pre-release identifiers compare by the spec, not alphabetically', () {
      // Numeric identifiers compare numerically, so rc.10 follows rc.9. As text it would not.
      expect(isNewer(candidate: '1.0.0-rc.10', current: '1.0.0-rc.9'), isTrue);
      expect(isNewer(candidate: '1.0.0-rc.9', current: '1.0.0-rc.10'), isFalse);
      // A numeric identifier ranks below an alphanumeric one at the same position.
      expect(isNewer(candidate: '1.0.0-alpha', current: '1.0.0-1'), isTrue);
      // Where one list runs out first, the shorter ranks lower.
      expect(
        isNewer(candidate: '1.0.0-alpha.1', current: '1.0.0-alpha'),
        isTrue,
      );
      expect(
        isNewer(candidate: '1.0.0-beta', current: '1.0.0-alpha.99'),
        isTrue,
      );
    });

    test('build metadata takes no part in precedence', () {
      // Same version, different builds: neither is newer, in either direction. A checker that
      // compared the metadata would prompt on every CI rebuild of the same release.
      expect(isNewer(candidate: '1.0.0+2', current: '1.0.0+1'), isFalse);
      expect(isNewer(candidate: '1.0.0+1', current: '1.0.0+2'), isFalse);
      expect(SemVer.tryParse('1.0.0+build.5'), SemVer.tryParse('1.0.0'));
      // Metadata is stripped before the pre-release split, so it cannot leak into an identifier.
      expect(
        SemVer.tryParse('1.0.0-rc.1+build.5'),
        SemVer.tryParse('1.0.0-rc.1'),
      );
      expect(isNewer(candidate: '1.0.1+1', current: '1.0.0+9'), isTrue);
    });

    test('a leading v and a missing patch are read, junk is not', () {
      // The two sides come from different places — a GitHub tag and Android's versionName — and
      // only one of them has ever carried a `v`.
      expect(SemVer.tryParse('v1.2.3'), SemVer.tryParse('1.2.3'));
      expect(SemVer.tryParse('1.2'), SemVer.tryParse('1.2.0'));
      for (final junk in ['', '   ', 'latest', '1.x.0', '1.2.3.4', '1.2.3-']) {
        expect(SemVer.tryParse(junk), isNull, reason: junk);
      }
      // Unparseable on either side means no prompt, never a prompt on a guess.
      expect(isNewer(candidate: '', current: '1.0.0'), isFalse);
      expect(isNewer(candidate: '2.0.0', current: 'not-a-version'), isFalse);
    });
  });

  group('what gets prompted', () {
    test('an older or equal release says nothing', () {
      final store = _Store();
      for (final version in ['0.9.0', '1.0.0', '1.0.0+7']) {
        expect(
          store.checker(current: '1.0.0', feed: release(version)).check(),
          completion(isNull),
          reason: version,
        );
      }
    });

    test('a newer release is offered, once the feed has been read', () async {
      final store = _Store();
      final found = await store
          .checker(current: '1.0.0', feed: release('1.1.0'))
          .check();

      expect(found?.version, '1.1.0');
      expect(found?.download?.url, endsWith('chordia-universal.apk'));
      // Cached, so the next launch knows about it without spending another GitHub request.
      expect(store.values[UpdateChecker.latestKey], isNotNull);
      expect(store.values[UpdateChecker.checkedAtKey], isNotNull);
    });

    test(
      'a dismissed version stays dismissed, and a newer one still prompts',
      () async {
        final store = _Store();
        final checker = store.checker(current: '1.0.0', feed: release('1.1.0'));

        expect((await checker.check())?.version, '1.1.0');
        await checker.dismiss('1.1.0');

        // Same release, a day later, a fresh checker — the phone was relaunched. The point of
        // storing the version rather than a flag is that this stays quiet indefinitely.
        store.clock += _day * 30;
        final again = store.checker(current: '1.0.0', feed: release('1.1.0'));
        expect(await again.check(), isNull);

        // The next release is not covered by that refusal.
        store.clock += _day;
        final next = store.checker(current: '1.0.0', feed: release('1.2.0'));
        expect((await next.check())?.version, '1.2.0');

        // And a *pre-release* of the dismissed version is not newer than it, so it stays quiet —
        // the comparison is precedence, not string inequality.
        store.clock += _day;
        final pre = store.checker(
          current: '1.0.0',
          feed: release('1.1.0-rc.2'),
        );
        expect(await pre.check(), isNull);
      },
    );

    test(
      'the feed is read once a day, and the cached answer covers the rest',
      () async {
        final store = _Store();
        var reads = 0;
        UpdateChecker build() => store.checker(
          current: '1.0.0',
          feed: release('1.1.0'),
          onFetch: () => reads++,
        );

        expect((await build().check())?.version, '1.1.0');
        expect(reads, 1);

        // Two more launches inside the day. The prompt still appears — a pending update does not go
        // quiet until tomorrow just because the feed was already read — but GitHub is not asked
        // again, which is the whole reason the interval exists.
        store.clock += 60 * 60 * 1000;
        expect((await build().check())?.version, '1.1.0');
        store.clock += 60 * 60 * 1000;
        expect((await build().check())?.version, '1.1.0');
        expect(reads, 1);

        store.clock += _day;
        expect((await build().check())?.version, '1.1.0');
        expect(reads, 2);

        // `force` is what a "check now" control calls, and it ignores the interval.
        await build().check(force: true);
        expect(reads, 3);
      },
    );

    test(
      'a feed that fails is silent, and is retried on the next launch',
      () async {
        final store = _Store();
        var attempts = 0;
        Future<AppRelease?> failing() {
          attempts++;
          throw const SocketExceptionStandIn();
        }

        final checker = UpdateChecker(
          currentVersion: '1.0.0',
          fetch: failing,
          read: store.read,
          write: store.write,
          now: () => store.clock,
        );
        expect(await checker.check(), isNull);
        expect(attempts, 1);
        // No timestamp was written, so the failure does not lock the check out for a day. A phone
        // is offline far more often than a server is, and the common case must not cost a day.
        expect(store.values[UpdateChecker.checkedAtKey], isNull);

        expect(await checker.check(), isNull);
        expect(attempts, 2);
      },
    );

    test('a corrupt cache entry is ignored rather than thrown', () async {
      final store = _Store()..values[UpdateChecker.latestKey] = '{not json';
      // Half a write survived a process death. The checker has to treat that as "no cached
      // answer" — throwing here would take out the launch path it runs on.
      final checker = store.checker(current: '1.0.0', feed: release('1.1.0'));
      expect((await checker.check())?.version, '1.1.0');
    });
  });

  group('the release the Hub sends', () {
    test('the first APK is the one offered, and other assets are skipped', () {
      final parsed = AppRelease.fromJson(
        jsonDecode('''
        {
          "version": "0.2.0",
          "notes_url": "https://example.invalid/notes",
          "published_at": 1787039385000,
          "checksums_url": "https://example.invalid/SHA256SUMS",
          "downloads": [
            {"platform": "android_apk", "filename": "chordia-0.2.0-universal.apk",
             "url": "https://example.invalid/u.apk", "size_bytes": 41000000},
            {"platform": "android_apk", "filename": "chordia-0.2.0-arm64-v8a.apk",
             "url": "https://example.invalid/a.apk", "size_bytes": 23000000}
          ]
        }
        '''),
      );

      expect(parsed?.version, '0.2.0');
      expect(parsed?.download?.url, 'https://example.invalid/u.apk');
      expect(parsed?.download?.sizeBytes, 41000000);
    });

    test('a platform value this build has never heard of is not an error', () {
      // The reason this model is hand-read: an install from a year ago has to survive the release
      // feed growing a variant, because it is the build that most needs to be told to update.
      final parsed = AppRelease.fromJson(
        jsonDecode('''
        {
          "version": "9.0.0",
          "notes_url": "https://example.invalid/notes",
          "downloads": [
            {"platform": "android_aab_someday", "filename": "chordia.apk",
             "url": "https://example.invalid/x.apk", "size_bytes": 1}
          ]
        }
        '''),
      );
      expect(parsed?.download?.url, 'https://example.invalid/x.apk');
    });

    test('an empty feed is nothing to say, not something to prompt', () async {
      // What the Hub serves when GitHub is unreachable: a well-formed release with no version.
      final store = _Store();
      final checker = store.checker(
        current: '1.0.0',
        feed: const AppRelease(
          version: '',
          notesUrl: 'https://example.invalid',
        ),
      );
      expect(await checker.check(), isNull);
    });
  });

  group('the prompt on screen', () {
    testWidgets('it offers the notes and the download, and closes on Not now', (
      tester,
    ) async {
      final database = ChordiaDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final opened = <Uri>[];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            translationsProvider.overrideWithValue(translations),
            databaseProvider.overrideWithValue(database),
            appVersionProvider.overrideWith((ref) async => '1.0.0'),
            releaseFeedProvider.overrideWithValue(() async => release('1.1.0')),
            openExternalUrlProvider.overrideWithValue((url) async {
              opened.add(url);
            }),
          ],
          child: const MaterialApp(
            home: UpdateGate(child: Scaffold(body: Text('behind'))),
          ),
        ),
      );
      // Fixed frames rather than `pumpAndSettle`: the provider resolves across a few microtasks,
      // and settling waits for an animation clock that never goes quiet in this app.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.text('Chordia 1.1.0 is out'), findsOneWidget);
      expect(find.text("You're on 1.0.0."), findsOneWidget);
      // The size is on screen because this is a 40 MB download somebody may be on mobile data for.
      expect(find.textContaining('39.1 MB'), findsOneWidget);
      // The app behind it is still there: the prompt is stacked, not pushed.
      expect(find.text('behind'), findsOneWidget);

      await tester.tap(find.text("What's new"));
      await tester.pump();
      expect(opened.single.toString(), contains('/releases/v1.1.0'));

      await tester.tap(find.text('Not now'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Chordia 1.1.0 is out'), findsNothing);
      // Recorded, so the next launch does not ask again.
      expect(await database.kvDao.read(UpdateChecker.dismissedKey), '1.1.0');
    });

    testWidgets('nothing is drawn when the running build is current', (
      tester,
    ) async {
      final database = ChordiaDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            translationsProvider.overrideWithValue(translations),
            databaseProvider.overrideWithValue(database),
            appVersionProvider.overrideWith((ref) async => '1.1.0'),
            releaseFeedProvider.overrideWithValue(() async => release('1.1.0')),
          ],
          child: const MaterialApp(
            home: UpdateGate(child: Scaffold(body: Text('behind'))),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.text('behind'), findsOneWidget);
      expect(find.textContaining('is out'), findsNothing);
    });
  });
}

/// The key-value store the checker persists through, in memory.
class _Store {
  final Map<String, String> values = {};

  /// Epoch milliseconds, moved by hand. Starts well past zero so "never checked" (0) is not
  /// accidentally inside the interval.
  int clock = 1787000000000;

  Future<String?> read(String key) async => values[key];

  Future<void> write(String key, String value) async => values[key] = value;

  UpdateChecker checker({
    required String current,
    required AppRelease feed,
    void Function()? onFetch,
  }) => UpdateChecker(
    currentVersion: current,
    fetch: () async {
      onFetch?.call();
      return feed;
    },
    read: read,
    write: write,
    now: () => clock,
  );
}

/// A transport failure, without dragging `dart:io` in for one throw.
class SocketExceptionStandIn implements Exception {
  const SocketExceptionStandIn();
}
