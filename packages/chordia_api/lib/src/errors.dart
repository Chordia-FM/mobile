import 'json.dart';

/// A failure returned by the Hub or a library server.
///
/// Both speak RFC 7807 problem documents, so one type covers them. [status] 0 means the request
/// never got an answer — no network, DNS failure, a refused connection, or a certificate that did
/// not match its pin — which callers distinguish from a real HTTP status when deciding whether to
/// retry or to tell the user the server is unreachable.
class ApiException implements Exception {
  const ApiException({
    required this.status,
    required this.title,
    required this.method,
    required this.path,
    this.type,
    this.detail,
    this.cause,
  });

  final int status;

  /// Short, human-readable summary. Already localised by the server when the request carried an
  /// `Accept-Language` it understands.
  final String title;

  final String method;
  final String path;

  /// The problem type URI, which is the stable identifier to branch on — never [title], which is
  /// prose and changes with the reader's language.
  final String? type;
  final String? detail;

  /// The transport error behind a [status] of 0.
  final Object? cause;

  bool get isNetworkFailure => status == 0;
  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;
  bool get isNotFound => status == 404;

  /// The library server is offline, so the Hub declined to mint a capability token for it.
  bool get isServerOffline => status == 409;

  static ApiException fromProblem({
    required int status,
    required String method,
    required String path,
    required Object? body,
    required String fallbackTitle,
  }) {
    if (body is Map) {
      final map = body.cast<String, Object?>();
      return ApiException(
        status: status,
        title: asStringOrNull(map['title']) ?? fallbackTitle,
        method: method,
        path: path,
        type: asStringOrNull(map['type']),
        detail: asStringOrNull(map['detail']),
      );
    }
    return ApiException(
      status: status,
      title: fallbackTitle,
      method: method,
      path: path,
    );
  }

  @override
  String toString() =>
      'ApiException($status $title) on $method $path'
      '${detail == null ? '' : ' — $detail'}';
}
