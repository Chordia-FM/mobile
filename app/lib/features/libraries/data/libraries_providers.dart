import 'package:chordia_api/chordia_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'libraries_api.dart';
import 'pairing_transport.dart';

/// The Hub-backed library-management calls, or null while there is no signed-in hub.
final librariesApiProvider = Provider<LibrariesApi?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : HubLibrariesApi(hub);
});

final overridesApiProvider = Provider<OverridesApi?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : HubOverridesApi(hub);
});

/// How the phone talks to a library server that is not in the directory yet.
///
/// Built on the app's shared client factory, so pairing is not a second way onto the network —
/// which matters more here than anywhere else, since this is the one exchange that happens before
/// a pin exists.
final pairingTransportProvider = Provider<PairingTransport>(
  (ref) => HttpPairingTransport(ref.watch(httpClientFactoryProvider)),
);

/// Exact per-library counts.
///
/// The Hub has no "count the albums in this library" endpoint; the Manager's coverage report is
/// where those totals are computed, so the detail screen reads them from there rather than
/// counting a page of browse results and printing a number that is quietly capped at fifty.
final libraryCoverageProvider = FutureProvider<Map<String, LibraryCoverage>>((
  ref,
) async {
  final api = ref.watch(librariesApiProvider);
  if (api == null) return const {};
  final coverage = await api.coverage();
  return {for (final row in coverage.perLibrary) row.libraryId: row};
});

/// The caller's accepted friends — the only people a library can be shared with.
final shareCandidatesProvider = FutureProvider<List<PublicUser>>((ref) async {
  final api = ref.watch(librariesApiProvider);
  return api == null ? const [] : api.friends();
});

/// Everything one library's owner has corrected about its metadata.
final libraryOverridesProvider =
    FutureProvider.family<List<LibraryOverrideSummary>, String>((
      ref,
      libraryId,
    ) async {
      final api = ref.watch(overridesApiProvider);
      return api == null ? const [] : api.list(libraryId);
    });
