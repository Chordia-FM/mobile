/// One row of the moderation queue.
///
/// Hand-written rather than generated, because the Hub's `ReportRow` is a repository struct rather
/// than a contract type: it is shaped by the SQL that produces it and has never been through
/// `contracts/`, so there is no ts-rs binding and no Dart model for it. The wire keys below are
/// the column aliases in `moderation::list_reports`.
///
/// If this shape ever moves into `contracts/`, delete this class and use the generated one — a
/// hand-written mirror of a server type is a thing that drifts.
class ModerationReport {
  const ModerationReport({
    required this.id,
    required this.reason,
    required this.status,
    required this.createdAtMs,
    this.reporterHandle,
    this.targetHandle,
    this.details,
  });

  final String id;

  /// Why it was filed, as the reporting form's enum value.
  final String reason;

  /// `open` | `resolved` | `dismissed`.
  final String status;
  final int createdAtMs;

  /// Absent when the account that filed it has since been deleted.
  final String? reporterHandle;

  /// Absent for a report about something other than a user.
  final String? targetHandle;

  final String? details;

  factory ModerationReport.fromJson(Map<String, Object?> json) =>
      ModerationReport(
        id: json['id']! as String,
        reason: json['reason']! as String,
        status: json['status']! as String,
        createdAtMs: (json['created_at_ms']! as num).toInt(),
        reporterHandle: json['reporter_handle'] as String?,
        targetHandle: json['target_handle'] as String?,
        details: json['details'] as String?,
      );
}

/// The filters the roster is read with.
///
/// A value object rather than five positional arguments, because it is also the family key of the
/// provider that fetches a page: Riverpod compares family keys by equality, so a record of the
/// filters is what makes "same filters, same page" a cache hit instead of a second request.
class AdminUserQuery {
  const AdminUserQuery({
    this.search = '',
    this.status = 'all',
    this.sort = 'created',
    this.limit = 25,
    this.offset = 0,
  });

  final String search;

  /// `all` | `active` | `suspended`.
  final String status;

  /// `created` | `handle` | `plays` | `last_seen` | `libraries`.
  final String sort;

  final int limit;
  final int offset;

  AdminUserQuery copyWith({
    String? search,
    String? status,
    String? sort,
    int? limit,
    int? offset,
  }) => AdminUserQuery(
    search: search ?? this.search,
    status: status ?? this.status,
    sort: sort ?? this.sort,
    limit: limit ?? this.limit,
    offset: offset ?? this.offset,
  );

  @override
  bool operator ==(Object other) =>
      other is AdminUserQuery &&
      other.search == search &&
      other.status == status &&
      other.sort == sort &&
      other.limit == limit &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(search, status, sort, limit, offset);
}
