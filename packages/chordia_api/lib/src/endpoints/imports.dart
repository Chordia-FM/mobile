import '../hub.dart';
import '../json.dart';
import '../models.g.dart';

/// Importing listening history from Spotify or Last.fm.
///
/// Only the read half is here. Starting an import (`POST /v1/me/imports`) uploads the export file
/// as `application/octet-stream`, and [HubClient] speaks JSON bodies only — modelling it as a JSON
/// call would compile and then fail against a real Hub. It wants a byte-body path on the transport
/// first.
extension ImportEndpoints on HubClient {
  /// The caller's recent import jobs, newest first.
  Future<ImportJobsResponse> imports() => get(
    '/v1/me/imports',
    (json) => ImportJobsResponse.fromJson(asObject(json)),
  );

  /// One job, for the progress poll.
  Future<ImportJob> importJob(String jobId) => get(
    '/v1/me/imports/$jobId',
    (json) => ImportJob.fromJson(asObject(json)),
  );
}
