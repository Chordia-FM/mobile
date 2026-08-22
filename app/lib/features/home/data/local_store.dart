import 'package:chordia_db/open.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

/// Hub JSON kept for the next cold start.
///
/// The other accessors on the app database already have providers in `app/providers.dart`; this
/// one lives here because discovery is the only feature that reads it, and it belongs beside them
/// the moment a second one does.
final responseCacheDaoProvider = Provider<ResponseCacheDao>(
  (ref) => ref.watch(databaseProvider).responseCacheDao,
);
