import '../hub.dart';
import '../json.dart';
import '../models.g.dart';
import 'decode.dart';

/// The listening record.
///
/// [submitScrobbles] is the flush target for the client's offline queue. It is idempotent on each
/// event's `event_id` (a client-generated UUIDv7), which is the whole reason a phone can retry a
/// batch it is not sure landed: duplicates are counted, not stored twice.
///
/// The library-side ingest path (`POST /v1/scrobbles:ingest`) is deliberately absent — it is
/// authenticated with a server API key, for a library forwarding events on its owner's behalf.
extension ScrobbleEndpoints on HubClient {
  Future<ScrobbleBatchResponse> submitScrobbles(ScrobbleBatch batch) => post(
    // The colon is part of the path, not a separator: the Hub spells this action route
    // `scrobbles:batch` so it cannot collide with `/v1/scrobbles/{event_id}`.
    '/v1/scrobbles:batch',
    (json) => ScrobbleBatchResponse.fromJson(asObject(json)),
    body: batch.toJson(),
  );

  /// Re-attributes a play that landed on the wrong track.
  Future<void> editScrobble(String eventId, ScrobbleEdit edit) =>
      patch<void>('/v1/scrobbles/$eventId', discard, body: edit.toJson());

  /// Removes a play outright.
  Future<void> deleteScrobble(String eventId) =>
      delete('/v1/scrobbles/$eventId');
}
