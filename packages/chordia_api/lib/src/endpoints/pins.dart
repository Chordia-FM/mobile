import '../hub.dart';
import '../models.g.dart';
import 'decode.dart';

/// The caller's pinned shelf — the sidebar's top section.
///
/// Pins are a mixed list keyed by `(kind, id)` rather than four separate collections, which is why
/// [PinKind] travels in the path and why ordering is one call over the whole set.
extension PinEndpoints on HubClient {
  Future<List<PinnedItem>> pins() =>
      get('/v1/me/pins', (json) => listOf(json, PinnedItem.fromJson));

  Future<void> addPin(PinKind kind, String id) =>
      put<void>('/v1/me/pins/${kind.wire}/$id', discard);

  Future<void> removePin(PinKind kind, String id) =>
      delete('/v1/me/pins/${kind.wire}/$id');

  /// Sets the order top-to-bottom across every kind at once. Entries the Hub does not recognise are
  /// ignored rather than rejected, so an older client cannot fail on a pin kind it has never heard
  /// of.
  Future<void> reorderPins(ReorderBody order) =>
      put<void>('/v1/me/pins/order', discard, body: order.toJson());
}
