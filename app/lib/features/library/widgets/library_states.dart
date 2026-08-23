import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
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

/// Grey blocks in the shape of the rows that are coming.
///
/// Sized to the real row so the list does not jump when the data lands — a spinner in the middle
/// of the screen costs a full re-layout at exactly the moment the reader starts scanning.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 6, this.height = 64});

  final int rows;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Column(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
      ],
    );
  }
}

/// A failure, with the one thing worth offering: another go.
class ErrorRetry extends ConsumerWidget {
  const ErrorRetry({required this.error, required this.onRetry, super.key});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            describeError(error, t),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: Text(t(CommonKeys.actionsTryAgain)),
          ),
        ],
      ),
    );
  }
}

/// An empty list that says what would fill it.
///
/// Never a bare "Nothing here": the catalogs carry a sentence per collection naming the action
/// that puts something in it, and that sentence is the entire value of the state.
class EmptyNote extends StatelessWidget {
  const EmptyNote({required this.message, super.key, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
