import 'dart:async';
import 'dart:convert';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import 'semver.dart';

/// One file on a release.
class ReleaseDownload {
  const ReleaseDownload({
    required this.filename,
    required this.url,
    required this.sizeBytes,
  });

  final String filename;
  final String url;
  final int sizeBytes;

  Map<String, Object?> toJson() => {
    'filename': filename,
    'url': url,
    'size_bytes': sizeBytes,
  };
}

/// What `GET /v1/mobile/latest` says the newest Android build is.
///
/// Read by hand rather than through the generated `DesktopRelease` model, and that is deliberate:
/// this is the one component in the app that has to keep working on installs nobody has updated in
/// a year. The generated model rejects a `platform` value it does not know, so the day the release
/// feed grows a variant, every old install would start throwing here — in the exact code path whose
/// job is to tell those installs there is something newer. This reads the three fields the prompt
/// draws and ignores everything else, including `platform`: the Hub already orders the APKs so the
/// universal build, the one that installs on any device, comes first.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.notesUrl,
    this.download,
  });

  /// `0.2.0`, without a leading `v`.
  final String version;

  /// The GitHub release page, for the notes.
  final String notesUrl;

  /// The APK to offer, or null on a release that carries none.
  final ReleaseDownload? download;

  static AppRelease? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.cast<String, Object?>();
    final version = json['version'];
    final notes = json['notes_url'];
    if (version is! String || notes is! String) return null;

    final downloads = json['downloads'];
    ReleaseDownload? first;
    if (downloads is List) {
      for (final entry in downloads) {
        if (entry is! Map) continue;
        final row = entry.cast<String, Object?>();
        final url = row['url'];
        final filename = row['filename'];
        if (url is! String || filename is! String) continue;
        if (!filename.toLowerCase().endsWith('.apk')) continue;
        final size = row['size_bytes'];
        first = ReleaseDownload(
          filename: filename,
          url: url,
          sizeBytes: size is int ? size : 0,
        );
        break;
      }
    }
    return AppRelease(version: version, notesUrl: notes, download: first);
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'notes_url': notesUrl,
    'downloads': [if (download != null) download!.toJson()],
  };
}

/// Where the release feed comes from. A function so the Hub client, which comes and goes with the
/// active server, is read at call time rather than held.
typedef ReleaseFeed = Future<AppRelease?> Function();

/// Reads the feed off a Hub.
///
/// Unauthenticated on purpose: the endpoint is public, and an update check that only worked while
/// signed in would go quiet for exactly the person whose session has expired because their build is
/// too old to refresh it.
ReleaseFeed hubReleaseFeed(HubClient hub) =>
    () =>
        hub.get('/v1/mobile/latest', AppRelease.fromJson, authenticated: false);

/// Decides whether to prompt, and remembers what has been said no to.
///
/// Pure but for the two callbacks, so the rules — how often to ask GitHub, what counts as newer,
/// what a dismissal covers — are testable without a database, a Hub or a widget.
class UpdateChecker {
  UpdateChecker({
    required this.currentVersion,
    required this.fetch,
    required this.read,
    required this.write,
    required this.now,
    this.interval = const Duration(hours: 24),
  });

  /// What this install reports itself as, from `package_info_plus`.
  final String currentVersion;

  final ReleaseFeed fetch;
  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;

  /// Epoch milliseconds. Injected so a test can move time without sleeping.
  final int Function() now;

  /// How long a fetched answer stands before the feed is asked again.
  final Duration interval;

  /// The last answer from the feed, so a launch inside [interval] still knows about a pending
  /// update instead of going quiet until tomorrow.
  static const latestKey = 'update.latest';

  /// When the feed was last read, epoch milliseconds.
  static const checkedAtKey = 'update.checked_at';

  /// The newest version the user has said no to.
  static const dismissedKey = 'update.dismissed';

  /// The release to offer, or null when there is nothing to say.
  ///
  /// [force] skips the interval — what a "check now" control would call.
  Future<AppRelease?> check({bool force = false}) async {
    var release = AppRelease.fromJson(_decode(await read(latestKey)));

    final checkedAt = int.tryParse(await read(checkedAtKey) ?? '') ?? 0;
    if (force || now() - checkedAt >= interval.inMilliseconds) {
      try {
        final fetched = await fetch();
        if (fetched != null) {
          release = fetched;
          await write(latestKey, jsonEncode(fetched.toJson()));
          // Stamped only on a successful read. A Hub that is unreachable — which on a phone is the
          // normal case, not the exception — is retried on the next launch rather than locked out
          // for a day by its own failure.
          await write(checkedAtKey, now().toString());
        }
      } on Object {
        // Nothing to report and nothing to say: an update check is the one background errand that
        // must never surface an error at somebody. The cached answer, if there is one, still
        // stands.
      }
    }

    if (release == null) return null;
    if (!isNewer(candidate: release.version, current: currentVersion)) {
      return null;
    }

    // A dismissal covers that version and everything up to it, never what comes after. Storing the
    // version rather than a flag is what makes "never nag" and "still tell me about the next one"
    // the same rule.
    final dismissed = await read(dismissedKey);
    if (dismissed != null &&
        !isNewer(candidate: release.version, current: dismissed)) {
      return null;
    }
    return release;
  }

  /// Records that this version was declined.
  Future<void> dismiss(String version) => write(dismissedKey, version);

  static Object? _decode(String? raw) {
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      // A half-written or older-shaped cache entry is simply not an answer. Returning null puts
      // the checker back on the fetch path, which overwrites it.
      return null;
    }
  }
}

/// This install's version name — `0.2.0`, or `0.2.0-dev` on the dev flavour.
///
/// A provider rather than a direct call so tests, which have no platform channel to answer
/// `PackageInfo`, can say what is running.
final appVersionProvider = FutureProvider<String>(
  (ref) async => (await PackageInfo.fromPlatform()).version,
);

/// The release feed of the active hub, or null when there is no hub to ask.
final releaseFeedProvider = Provider<ReleaseFeed?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : hubReleaseFeed(hub);
});

/// Opens a URL in the browser. Overridden in tests, which have no browser.
final openExternalUrlProvider = Provider<Future<void> Function(Uri)>(
  (ref) => (url) async {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  },
);

/// The update to offer right now, or null.
///
/// Built when the gate first watches it, which is on launch; the once-a-day rule lives in
/// [UpdateChecker] rather than in a timer, because a phone app is launched far more often than it
/// is left running for a day.
final updateProvider = AsyncNotifierProvider<UpdateController, AppRelease?>(
  UpdateController.new,
);

class UpdateController extends AsyncNotifier<AppRelease?> {
  UpdateChecker? _checker;

  @override
  Future<AppRelease?> build() async {
    final feed = ref.watch(releaseFeedProvider);
    if (feed == null) return null;

    final kv = ref.watch(kvDaoProvider);
    final checker = UpdateChecker(
      currentVersion: await ref.watch(appVersionProvider.future),
      fetch: feed,
      read: kv.read,
      write: kv.write,
      now: () => DateTime.now().millisecondsSinceEpoch,
    );
    _checker = checker;
    return checker.check();
  }

  /// Takes the prompt off screen for this launch without recording a refusal.
  ///
  /// What a swipe or a tap on Download means: the release is still newer, and the next launch
  /// should say so again.
  void hide() => state = const AsyncData(null);

  /// Says no to the offered version, for good — until a newer one exists.
  Future<void> dismiss() async {
    final release = state.value;
    if (release == null) return;
    // Off screen first: the sheet closes on the frame the tap is handled, not when the write
    // lands. The write cannot fail in a way the user could act on anyway.
    state = const AsyncData(null);
    await _checker?.dismiss(release.version);
  }
}
