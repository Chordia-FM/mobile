import 'package:chordia_api/chordia_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'admin_models.dart';

/// Everything the admin screens ask the Hub for.
///
/// An interface for the same reason every other feature has one: `HubClient`'s call surface is a
/// set of **extension** methods, which dispatch statically and cannot be mocked, so without this
/// seam a widget test for "the admin section is hidden from a non-admin" would need a live server.
///
/// The calls are spelled out against raw paths here rather than through `chordia_api`, because the
/// `admin` OpenAPI tag is one of the groups that package deliberately does not cover yet (see the
/// "Not covered here" list in `endpoints/endpoints.dart`). When an `endpoints/admin.dart` lands,
/// [HubAdminApi] becomes a one-line delegate per method and nothing above it changes.
///
/// **Not here on purpose**: backups and the data explorer. They are operator-at-a-desk surfaces —
/// long-running jobs and very wide tables — and the phone says so rather than pretending they were
/// forgotten.
abstract interface class AdminApi {
  /// The caller's own profile, which is where the admin flag comes from.
  Future<UserProfile> me();

  Future<AdminOverview> overview({int days});

  Future<AdminSystemHealth> system();

  Future<AdminUserPage> users(AdminUserQuery query);

  Future<AdminUserProfile> userProfile(String userId);

  /// The moderation queue. [status] is `open` | `resolved` | `dismissed` | `all`.
  Future<List<ModerationReport>> reports(String status);

  /// Closes one report. [action] is `resolved` or `dismissed`.
  Future<void> resolveReport(String reportId, String action);

  /// One keyset page of the privileged-action log. [beforeId] continues from a previous page.
  Future<AuditPage> audit({String? category, int? beforeId, int limit});

  /// The distinct actions, categories and actors present in the log.
  Future<AuditFacets> auditFacets();

  Future<List<BrowseArtist>> searchArtists(String query);

  Future<List<BrowseAlbum>> searchAlbums(String query);
}

/// [AdminApi] over the real Hub.
class HubAdminApi implements AdminApi {
  const HubAdminApi(this._hub);

  final HubClient _hub;

  @override
  Future<UserProfile> me() => _hub.me();

  @override
  Future<AdminOverview> overview({int days = 30}) => _hub.get(
    '/v1/admin/overview',
    (json) => AdminOverview.fromJson(_object(json)),
    query: {'days': days},
  );

  @override
  Future<AdminSystemHealth> system() => _hub.get(
    '/v1/admin/system',
    (json) => AdminSystemHealth.fromJson(_object(json)),
  );

  @override
  Future<AdminUserPage> users(AdminUserQuery query) => _hub.get(
    '/v1/admin/users/page',
    (json) => AdminUserPage.fromJson(_object(json)),
    query: {
      'q': query.search,
      'status': query.status,
      'sort': query.sort,
      'limit': query.limit,
      'offset': query.offset,
    },
  );

  @override
  Future<AdminUserProfile> userProfile(String userId) => _hub.get(
    '/v1/admin/users/${Uri.encodeComponent(userId)}/profile',
    (json) => AdminUserProfile.fromJson(_object(json)),
  );

  @override
  Future<List<ModerationReport>> reports(String status) => _hub.get(
    '/v1/admin/reports',
    (json) => _list(json, ModerationReport.fromJson),
    query: {'status': status},
  );

  @override
  Future<void> resolveReport(String reportId, String action) => _hub.post<void>(
    '/v1/admin/reports/${Uri.encodeComponent(reportId)}/resolve',
    (_) {},
    body: {'action': action},
  );

  @override
  Future<AuditPage> audit({String? category, int? beforeId, int limit = 50}) =>
      _hub.get(
        '/v1/admin/audit',
        (json) => AuditPage.fromJson(_object(json)),
        query: {
          if (category != null && category.isNotEmpty) 'category': category,
          'before_id': ?beforeId,
          'limit': limit,
        },
      );

  @override
  Future<AuditFacets> auditFacets() => _hub.get(
    '/v1/admin/audit/facets',
    (json) => AuditFacets.fromJson(_object(json)),
  );

  @override
  Future<List<BrowseArtist>> searchArtists(String query) => _hub.get(
    '/v1/admin/catalog/artists/search',
    (json) => _list(json, BrowseArtist.fromJson),
    query: {'q': query},
  );

  @override
  Future<List<BrowseAlbum>> searchAlbums(String query) => _hub.get(
    '/v1/admin/catalog/albums/search',
    (json) => _list(json, BrowseAlbum.fromJson),
    query: {'q': query},
  );
}

/// A decoded JSON object, or a shape failure naming what arrived instead.
///
/// `chordia_api` keeps its own `asObject`/`listOf` private to the package, so the two shapes these
/// raw calls need are re-stated here rather than the package's surface being widened for one
/// feature.
Map<String, Object?> _object(Object? json) => json is Map<String, Object?>
    ? json
    : throw JsonShapeException('an object', json);

List<T> _list<T>(Object? json, T Function(Map<String, Object?>) fromJson) =>
    json is List
    ? [for (final item in json) fromJson(_object(item))]
    : throw JsonShapeException('a list', json);

/// The admin slice of the Hub, or null when there is no session to speak through.
final adminApiProvider = Provider<AdminApi?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : HubAdminApi(hub);
});
