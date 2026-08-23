import 'package:chordia_api/chordia_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_api.dart';
import 'admin_models.dart';

/// Riverpod retries an errored provider on its own, with a backoff. Switched off here for the same
/// reason the catalog switches it off: these screens show a failure with a Retry button, and a
/// silent background retry contradicts that button and leaves a pending timer in widget tests.
Duration? _noAutoRetry(int attempt, Object error) => null;

AdminApi _api(Ref ref) {
  final api = ref.watch(adminApiProvider);
  if (api == null) throw StateError('No hub session to read admin data from.');
  return api;
}

/// Whether the signed-in account may see the admin section at all.
///
/// Read from the Hub's own answer rather than inferred from a badge or a tier: the flag on
/// `/v1/me` is the same one the server's `AdminUser` extractor enforces, so the section a client
/// shows and the routes it can actually call cannot disagree. Every admin route is gated
/// server-side regardless — this only decides what is worth putting on screen.
///
/// Not auto-disposed: it gates an entry point that is rebuilt on every menu open, and re-asking
/// the Hub each time would be a request per navigation.
final isAdminProvider = FutureProvider<bool>((ref) async {
  final api = ref.watch(adminApiProvider);
  // No session is not an error here: signed out simply means no admin section.
  if (api == null) return false;
  return (await api.me()).isAdmin ?? false;
}, retry: _noAutoRetry);

final adminOverviewProvider = FutureProvider.autoDispose
    .family<AdminOverview, int>(
      (ref, days) => _api(ref).overview(days: days),
      retry: _noAutoRetry,
    );

final adminSystemProvider = FutureProvider.autoDispose<AdminSystemHealth>(
  (ref) => _api(ref).system(),
  retry: _noAutoRetry,
);

/// The roster, accumulated page by page under one set of filters.
///
/// Offset paging, because that is what the Hub serves it with: the roster is small, sortable by
/// any column, and stable enough that a page does not shift under the reader. The pages are
/// appended rather than replaced because a phone scrolls rather than clicking "page 3 of 7".
final adminUsersControllerProvider =
    AsyncNotifierProvider.autoDispose<AdminUsersController, AdminUsersState>(
      AdminUsersController.new,
      retry: _noAutoRetry,
    );

/// The rows gathered so far under [query], and how many the filters match in total.
class AdminUsersState {
  const AdminUsersState({
    required this.rows,
    required this.total,
    required this.query,
    this.loadingMore = false,
  });

  final List<AdminUserDetail> rows;

  /// What the filters match on the server, which is what makes "load more" honest about whether
  /// there is more.
  final int total;

  final AdminUserQuery query;
  final bool loadingMore;

  bool get hasMore => rows.length < total;

  AdminUsersState copyWith({List<AdminUserDetail>? rows, bool? loadingMore}) =>
      AdminUsersState(
        rows: rows ?? this.rows,
        total: total,
        query: query,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

class AdminUsersController extends AsyncNotifier<AdminUsersState> {
  AdminUserQuery _query = const AdminUserQuery();

  @override
  Future<AdminUsersState> build() async {
    final page = await _api(ref).users(_query);
    return AdminUsersState(rows: page.rows, total: page.total, query: _query);
  }

  /// Re-reads from the first page under new filters.
  Future<void> applyFilters(AdminUserQuery query) async {
    if (query == _query) return;
    // Offset always resets: keeping it would open a new search on page three of the old one.
    _query = query.copyWith(offset: 0);
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(adminApiProvider)!
          .users(_query.copyWith(offset: current.rows.length));
      state = AsyncData(
        AdminUsersState(
          rows: [...current.rows, ...page.rows],
          total: page.total,
          query: _query,
        ),
      );
    } on Object {
      state = AsyncData(current.copyWith(loadingMore: false));
      rethrow;
    }
  }
}

final adminUserProfileProvider = FutureProvider.autoDispose
    .family<AdminUserProfile, String>(
      (ref, userId) => _api(ref).userProfile(userId),
      retry: _noAutoRetry,
    );

final adminReportsProvider = FutureProvider.autoDispose
    .family<List<ModerationReport>, String>(
      (ref, status) => _api(ref).reports(status),
      retry: _noAutoRetry,
    );

final adminAuditFacetsProvider = FutureProvider.autoDispose<AuditFacets>(
  (ref) => _api(ref).auditFacets(),
  retry: _noAutoRetry,
);

/// The catalog search behind the Content tab. An empty query is an empty result rather than a
/// request — the Hub would answer it with a slice of the whole catalog, which is not a search.
final adminCatalogSearchProvider = FutureProvider.autoDispose
    .family<(List<BrowseArtist>, List<BrowseAlbum>), String>((
      ref,
      query,
    ) async {
      final trimmed = query.trim();
      if (trimmed.length < adminSearchMinLength) {
        return (const <BrowseArtist>[], const <BrowseAlbum>[]);
      }
      final api = _api(ref);
      // Both halves at once: the tab shows one result list, and rendering artists a beat before
      // albums makes a settled page look like it is still loading.
      final results = await Future.wait([
        api.searchArtists(trimmed),
        api.searchAlbums(trimmed),
      ]);
      return (
        results[0] as List<BrowseArtist>,
        results[1] as List<BrowseAlbum>,
      );
    }, retry: _noAutoRetry);

/// The shortest catalog search the Hub is asked for.
const adminSearchMinLength = 2;

/// The audit log, page by page.
///
/// A controller rather than a family read because the log is keyset-paginated: page two is defined
/// by the last id of page one, so the pages have to accumulate somewhere that survives a rebuild.
final auditLogControllerProvider =
    AsyncNotifierProvider.autoDispose<AuditLogController, AuditLogState>(
      AuditLogController.new,
      retry: _noAutoRetry,
    );

/// The rows gathered so far, plus whether the Hub said there are more.
class AuditLogState {
  const AuditLogState({
    required this.rows,
    required this.category,
    this.nextBeforeId,
    this.loadingMore = false,
  });

  final List<AuditEntry> rows;

  /// The category filter these rows were read under, so a stale page cannot be appended to a
  /// freshly filtered list.
  final String category;

  /// Cursor for the page after these. Null means this was the last one.
  final int? nextBeforeId;

  final bool loadingMore;

  bool get hasMore => nextBeforeId != null;

  AuditLogState copyWith({
    List<AuditEntry>? rows,
    String? category,
    int? nextBeforeId,
    bool clearCursor = false,
    bool? loadingMore,
  }) => AuditLogState(
    rows: rows ?? this.rows,
    category: category ?? this.category,
    nextBeforeId: clearCursor ? null : (nextBeforeId ?? this.nextBeforeId),
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

class AuditLogController extends AsyncNotifier<AuditLogState> {
  String _category = '';

  @override
  Future<AuditLogState> build() async {
    final page = await _api(ref).audit(category: _category);
    return AuditLogState(
      rows: page.rows,
      category: _category,
      nextBeforeId: page.nextBeforeId,
    );
  }

  /// Re-reads from the top under a new category filter.
  Future<void> filter(String category) async {
    if (category == _category) return;
    _category = category;
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// Appends the next keyset page.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(adminApiProvider)!
          .audit(category: _category, beforeId: current.nextBeforeId);
      state = AsyncData(
        AuditLogState(
          rows: [...current.rows, ...page.rows],
          category: current.category,
          nextBeforeId: page.nextBeforeId,
        ),
      );
    } on Object {
      // The rows already on screen are still good; only the extra page failed. Dropping them for
      // an error card would throw away what the reader was in the middle of.
      state = AsyncData(current.copyWith(loadingMore: false));
      rethrow;
    }
  }
}
