import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../widgets/library_states.dart';
import 'library_providers.dart';
import 'reorder.dart';

/// Whether [kind]/[id] is on the pinned shelf right now.
///
/// Reads the shelf that is already loaded rather than asking the Hub: the shelf is the top of the
/// Library tab, so it is in hand by the time anything can offer to pin something.
bool isPinned(WidgetRef ref, PinKind kind, String id) {
  final shelf = ref.watch(pinsProvider).value ?? const <PinnedItem>[];
  return shelf.any((pin) => pin.kind == kind && pin.id == id);
}

/// Pins or unpins [kind]/[id], and answers with what the shelf now says.
///
/// The shelf is re-read rather than patched in place: a pin carries a name and artwork the Hub
/// resolves, and the pin call answers with none of it — so anything assembled here would be a
/// guess at the row the next load replaces.
Future<bool> togglePin(
  BuildContext context,
  WidgetRef ref, {
  required PinKind kind,
  required String id,
}) async {
  final api = ref.read(pinsApiProvider);
  if (api == null) return isPinned(ref, kind, id);
  final pinned = isPinned(ref, kind, id);
  try {
    if (pinned) {
      await api.remove(kind, id);
    } else {
      await api.add(kind, id);
    }
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeError(error, ref.read(translationsProvider).call),
          ),
        ),
      );
    }
    return pinned;
  }
  ref.invalidate(pinsProvider);
  return !pinned;
}

/// Moves the pin at [from] to [to] and sends the whole shelf in its new order.
///
/// The Hub has no "move one pin" call — it sets the order across every kind at once — so the list
/// is permuted here and sent whole. Answers false when the move was refused, having put the shelf
/// back the way the Hub still has it.
Future<bool> movePin(
  BuildContext context,
  WidgetRef ref, {
  required int from,
  required int to,
}) async {
  final api = ref.read(pinsApiProvider);
  final current = ref.read(pinsProvider).value;
  if (api == null || current == null) return false;
  if (from == to ||
      from < 0 ||
      to < 0 ||
      from >= current.length ||
      to >= current.length) {
    return false;
  }
  final next = moveItem(current, from, to);
  try {
    await api.reorder(next);
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeError(error, ref.read(translationsProvider).call),
          ),
        ),
      );
    }
    ref.invalidate(pinsProvider);
    return false;
  }
  ref.invalidate(pinsProvider);
  return true;
}

/// The label a pin toggle wears: "Pin" or "Unpin", matching the web client's menus.
String pinLabel(bool pinned) =>
    pinned ? CommonKeys.actionsUnpin : CommonKeys.actionsPin;
