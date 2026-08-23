/// Pure index arithmetic for reordering a list.
///
/// A port of `frontend/src/components/catalog/playlist-reorder.ts`, and it lives apart from the
/// widgets for the same reason it does there: an off-by-one here silently moves the WRONG track,
/// which is the kind of bug that survives a refactor unnoticed.
///
/// SERVER SEMANTICS THIS LEANS ON (backend `playlists::reorder`): the ids sent to
/// `PUT /v1/playlists/{id}/tracks/order` are permuted into the positions those ids ALREADY
/// occupy, and a track absent from the body keeps its exact place. `PlaylistDetail.tracks` is
/// filtered to what the viewer can play, so the list being reordered here may be a SUBSET of the
/// playlist — under those semantics sending the reordered subset expresses exactly the user's
/// intent: reorder what I can see among themselves, touch nothing else.
library;

/// A copy of [list] with the element at [from] moved to [to].
///
/// [to] is a position in the list AFTER the moved element is taken out, which is what
/// `ReorderableListView.onReorderItem` reports — the older `onReorder` handed over the drop slot
/// counted before the removal, one too high on a downward drag, and was deprecated for exactly
/// that trap.
///
/// An out-of-range or no-op move returns an unchanged copy rather than throwing: the callers are
/// a drag gesture and a menu item, and neither has anything useful to do with an exception.
List<T> moveItem<T>(List<T> list, int from, int to) {
  final next = List<T>.of(list);
  if (from == to ||
      from < 0 ||
      to < 0 ||
      from >= list.length ||
      to >= list.length) {
    return next;
  }
  next.insert(to, next.removeAt(from));
  return next;
}
