import 'package:chordia_api/chordia_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../catalog/data/catalog_api.dart';

/// Which station: what it was seeded from, and by which id.
///
/// A record rather than a class because the family key only has to compare equal, and a record
/// already does — a hand-written `==` here would be four lines that can only be wrong.
typedef StationSeed = ({StationKind kind, String seed});

/// Riverpod 3 retries an errored provider on its own; switched off for the reason the catalog's
/// providers switch it off — the screen already draws a Retry button, and a background retry both
/// contradicts it and leaves a pending timer behind in widget tests.
Duration? _noAutoRetry(int attempt, Object error) => null;

/// One generated station, seeded by anything.
///
/// Auto-disposed: a station is woven fresh per day and per listener, so a copy held from an
/// earlier visit is stale by construction.
final stationProvider = FutureProvider.autoDispose.family<Station, StationSeed>(
  (ref, seed) => ref.watch(catalogApiProvider).station(seed.kind, seed.seed),
  retry: _noAutoRetry,
);

/// Narrows a URL segment to a station kind.
///
/// A path parameter is an arbitrary string until something proves otherwise, and
/// [StationKind.fromWire] deliberately falls back to `artist` for a value it does not know — which
/// is right for a wire payload from a newer server and wrong for a typo in a link, where it would
/// send the Hub looking for an artist whose id is "atrist".
StationKind? stationKindFromSegment(String segment) =>
    StationKind.tryFromWire(segment);

/// The composed title for a station of this kind, e.g. "{name} Radio".
///
/// One key per kind even though every English value is identical today. A language that inflects
/// the noun differently after a song title than after an artist name cannot say so through a
/// shared key, and keys that have been merged cannot be split again without re-translating every
/// locale. Mirrors `STATION_TITLE_KEY` in the web client.
String stationTitleKey(StationKind kind) => switch (kind) {
  StationKind.artist => DiscoveryKeys.stationArtistRadio,
  StationKind.track => DiscoveryKeys.stationTrackRadio,
  StationKind.album => DiscoveryKeys.stationAlbumRadio,
  StationKind.genre => DiscoveryKeys.stationGenreRadio,
  StationKind.playlist => DiscoveryKeys.stationPlaylistRadio,
};

/// The small kicker above the title ("Song Radio").
String stationLabelKey(StationKind kind) => switch (kind) {
  StationKind.artist => DiscoveryKeys.stationKindArtist,
  StationKind.track => DiscoveryKeys.stationKindTrack,
  StationKind.album => DiscoveryKeys.stationKindAlbum,
  StationKind.genre => DiscoveryKeys.stationKindGenre,
  StationKind.playlist => DiscoveryKeys.stationKindPlaylist,
};
