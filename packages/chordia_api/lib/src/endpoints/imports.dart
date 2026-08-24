import '../hub.dart';
import '../json.dart';
import '../models.g.dart';
import 'images.dart';

/// Importing listening history from Spotify or Last.fm.
extension ImportEndpoints on HubClient {
  /// What `POST /v1/me/imports` refuses above — mirrors `MAX_UPLOAD_BYTES` in
  /// backend/src/import/mod.rs.
  ///
  /// Checked client-side as well as there because a Spotify extended history routinely runs to
  /// tens of megabytes: pushing one over a mobile uplink only to be told no wastes the whole
  /// upload, and the caller can split the export instead. The server is still the authority; this
  /// only saves the wait.
  static const maxUploadBytes = 64 * 1024 * 1024;

  /// Uploads an export file and starts importing it, answering with the job to poll.
  ///
  /// The upload is a **job**, not a request: the Hub sniffs the format, files a `pending` row and
  /// returns immediately, so what comes back has counted nothing yet — [importJob] is where the
  /// progress is.
  ///
  /// [source] is a claim the Hub checks rather than trusts. Detection runs on the CONTENT either
  /// way and a stated source that contradicts the bytes is a 400, so leaving it null (`auto`) is
  /// the safe choice and naming one only ever narrows.
  Future<ImportJob> startImport(
    List<int> bytes, {
    ImportSource? source,
    String contentType = 'application/octet-stream',
  }) => postBytes(
    '/v1/me/imports',
    (json) => ImportJob.fromJson(asObject(json)),
    bytes: bytes,
    contentType: contentType,
    query: {'source': source?.wire},
  );

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
