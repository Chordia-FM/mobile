import 'dart:async';

/// Applies a change locally, persists it, and puts it back if the server refuses.
///
/// A port of `frontend/src/lib/app/optimistic.ts`. On a phone the round trip is long enough that
/// waiting for it before redrawing makes every edit feel broken, and long enough that a silent
/// failure would leave the screen confidently showing something the server never accepted — so
/// the revert and the message are part of the contract, not an afterthought.
///
/// Never throws: the caller is a gesture handler with nothing useful to do with an exception.
/// The boolean says whether the change stuck.
Future<bool> optimistic({
  required void Function() apply,
  required void Function() revert,
  required Future<void> Function() server,
  required void Function(Object error) onFailure,
}) async {
  apply();
  try {
    await server();
    return true;
  } on Object catch (error) {
    revert();
    onFailure(error);
    return false;
  }
}
