import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/states.dart';
import '../data/formatting.dart';

/// What to say about a failure.
///
/// The Hub sends RFC 7807 problems whose `title` is already in the reader's language, so it is
/// better copy than anything this client could write — but a transport failure has no title worth
/// showing, and "SocketException: …" tells a listener nothing they can act on.
String describeError(Object error, Translate t) {
  if (error is ApiException && !error.isNetworkFailure) return error.title;
  return t(ErrorsKeys.failedToLoad);
}

/// Blocks in the shape of the rows that are coming.
///
/// Sized to the real row so the list does not jump when the data lands — a spinner in the middle
/// of the screen costs a full re-layout at exactly the moment the reader starts scanning.
///
/// The rows are drawn as the web's `TrackListSkeleton` does (cover + two bars) rather than as one
/// solid slab per row: a slab is the shape of nothing in the app, so it reads as a rendering fault
/// on a slow connection.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 6, this.height = 64});

  final int rows;

  /// Kept so callers can still reserve their own row height; the silhouette inside is fixed.
  final double height;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < rows; i++)
        SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                const ShimmerBox(width: 40, height: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // A little variation per row, so a list of identical bars does not read as
                      // one wide element that failed to split.
                      ShimmerBox(width: 180 - (i % 3) * 30, height: 12),
                      const SizedBox(height: 6),
                      const ShimmerBox(width: 110, height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

/// A failure, with the one thing worth offering: another go.
class ErrorRetry extends ConsumerWidget {
  const ErrorRetry({required this.error, required this.onRetry, super.key});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return ErrorState(
      title: describeError(error, t),
      actionLabel: t(CommonKeys.actionsTryAgain),
      onRetry: onRetry,
    );
  }
}

/// An empty list that says what would fill it.
///
/// Never a bare "Nothing here": the catalogs carry a sentence per collection naming the action
/// that puts something in it, and that sentence is the entire value of the state.
class EmptyNote extends StatelessWidget {
  const EmptyNote({required this.message, super.key, this.icon, this.hint});

  final String message;
  final IconData? icon;

  /// The muted second line, where a collection has one.
  final String? hint;

  @override
  Widget build(BuildContext context) =>
      EmptyState(message: message, hint: hint, icon: icon);
}
