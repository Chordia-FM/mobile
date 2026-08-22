import 'package:chordia_api/chordia_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'coverage_format.dart';
import 'manager_api.dart';

/// Riverpod retries an errored provider on its own, with a backoff.
///
/// Switched off for every read here, exactly as the catalog does it: these screens already show a
/// failure with a Retry button, and a silent background retry both contradicts that button and
/// leaves a pending timer behind in widget tests.
Duration? _noAutoRetry(int attempt, Object error) => null;

ManagerApi _api(Ref ref) {
  final api = ref.watch(managerApiProvider);
  if (api == null) throw StateError('No hub session to read the Manager from.');
  return api;
}

/// The coverage dashboard, and the writes that change what it counts.
///
/// A controller rather than a plain read because the exclusion list is editable from the same
/// screen that displays it: a toggle has to move the checkbox now and the counts once the Hub has
/// recomputed them, which is two states of one value.
final coverageControllerProvider =
    AsyncNotifierProvider<CoverageController, CoverageSummary>(
      CoverageController.new,
    );

class CoverageController extends AsyncNotifier<CoverageSummary> {
  /// Why the last write was refused, for the screen to say out loud.
  ///
  /// Every write here is optimistic, so a failure has already been undone on screen by the time
  /// the caller sees `false` — without the reason the revert looks like a tap that never landed.
  Object? failure;

  @override
  Future<CoverageSummary> build() => _api(ref).coverage();

  /// Includes or excludes one library from the coverage maths.
  ///
  /// The stored set, not the sent one, is what lands: the Hub drops ids the caller cannot see, so
  /// adopting the request would leave the screen claiming an exclusion that does not exist.
  Future<bool> setExcluded(String libraryId, {required bool excluded}) async {
    final before = state.value;
    if (before == null) return false;
    failure = null;

    final wanted = {...before.excludedLibraryIds};
    if (excluded) {
      wanted.add(libraryId);
    } else {
      wanted.remove(libraryId);
    }

    state = AsyncData(withExclusions(before, wanted));
    try {
      final api = ref.read(managerApiProvider)!;
      final stored = await api.setExclusions(wanted.toList()..sort());
      // Re-read rather than patch: excluding a library changes every count on the page, not just
      // one checkbox, and the summary is the only thing that knows the new totals.
      final refreshed = await api.coverage();
      state = AsyncData(withExclusions(refreshed, stored.toSet()));
      return true;
    } on Object catch (error) {
      failure = error;
      state = AsyncData(before);
      return false;
    }
  }
}

/// Whether shared-with-me libraries count toward coverage.
///
/// A separate document from the exclusion list on the Hub, and kept separate here: excluding one
/// library and opting out of every shared library at once are different decisions, and folding
/// them into one state would make the second silently clear the first.
final managerPrefsControllerProvider =
    AsyncNotifierProvider<ManagerPrefsController, ManagerPrefs>(
      ManagerPrefsController.new,
    );

class ManagerPrefsController extends AsyncNotifier<ManagerPrefs> {
  Object? failure;

  @override
  Future<ManagerPrefs> build() => _api(ref).prefs();

  Future<bool> setIncludeShared({required bool include}) async {
    final before = state.value;
    if (before == null) return false;
    failure = null;

    state = AsyncData(
      ManagerPrefs(
        defaultLibraryId: before.defaultLibraryId,
        includeShared: include,
      ),
    );
    try {
      final api = ref.read(managerApiProvider)!;
      state = AsyncData(await api.setPrefs(state.requireValue));
      // The scope changed, so every number on the coverage page is stale.
      ref.invalidate(coverageControllerProvider);
      return true;
    } on Object catch (error) {
      failure = error;
      state = AsyncData(before);
      return false;
    }
  }
}

/// The artists the caller owns, as the way into a per-artist coverage page.
final ownedArtistsProvider = FutureProvider.autoDispose<List<BrowseArtist>>(
  (ref) => _api(ref).ownedArtists(),
  retry: _noAutoRetry,
);

final artistCoverageProvider = FutureProvider.autoDispose
    .family<ArtistCoverage, String>(
      (ref, artistId) => _api(ref).artistCoverage(artistId),
      retry: _noAutoRetry,
    );

final releaseGroupCoverageProvider = FutureProvider.autoDispose
    .family<AlbumTrackCoverage, String>(
      (ref, mbid) => _api(ref).releaseGroupCoverage(mbid),
      retry: _noAutoRetry,
    );

/// The shortest query the Hub is asked to search for.
///
/// One character matches a large fraction of a MusicBrainz mirror, so the screen says so rather
/// than sending a request whose result nobody could use.
const minDiscoverQueryLength = 2;

final discoverProvider = FutureProvider.autoDispose
    .family<DiscoverResults, String>((ref, query) {
      final trimmed = query.trim();
      if (trimmed.length < minDiscoverQueryLength) {
        return const DiscoverResults(artists: [], releaseGroups: []);
      }
      return _api(ref).discover(trimmed);
    }, retry: _noAutoRetry);

final discoverArtistProvider = FutureProvider.autoDispose
    .family<ExtArtistDetail, String>(
      (ref, mbid) => _api(ref).discoverArtist(mbid),
      retry: _noAutoRetry,
    );

/// The artists followed for new-release notifications.
///
/// Not auto-disposed: the follow button on a discovery card needs to know the current set, and
/// re-fetching the whole list on every navigation is the cost this avoids.
final followsControllerProvider =
    AsyncNotifierProvider<FollowsController, List<FollowedArtist>>(
      FollowsController.new,
    );

class FollowsController extends AsyncNotifier<List<FollowedArtist>> {
  Object? failure;

  @override
  Future<List<FollowedArtist>> build() => _api(ref).follows();

  bool isFollowing(String artistMbid) =>
      state.value?.any((f) => f.artistMbid == artistMbid) ?? false;

  Future<bool> follow(String artistMbid, {String? name}) async {
    final before = state.value;
    if (before == null || isFollowing(artistMbid)) return false;
    failure = null;

    state = AsyncData([
      // Optimistically at the top, where the Hub's newest-first list will also put it.
      FollowedArtist(
        artistMbid: artistMbid,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        name: name,
      ),
      ...before,
    ]);
    try {
      final api = ref.read(managerApiProvider)!;
      await api.follow(artistMbid, name: name);
      // The Hub fills in the artist's image and default monitor types, which the placeholder above
      // has no way to guess.
      state = AsyncData(await api.follows());
      return true;
    } on Object catch (error) {
      failure = error;
      state = AsyncData(before);
      return false;
    }
  }

  Future<bool> unfollow(String artistMbid) async {
    final before = state.value;
    if (before == null) return false;
    failure = null;

    state = AsyncData([
      for (final follow in before)
        if (follow.artistMbid != artistMbid) follow,
    ]);
    try {
      // Idempotent on the Hub: unfollowing somebody who is not followed is a success, not a 404.
      await ref.read(managerApiProvider)!.unfollow(artistMbid);
      return true;
    } on Object catch (error) {
      failure = error;
      state = AsyncData(before);
      return false;
    }
  }
}
