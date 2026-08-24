import 'package:chordia_api/chordia_api.dart';

/// Collapsing a MusicBrainz discography into the list a person actually wants to read.
///
/// Ported line for line from the web's `lib/manager/releases.ts`, which both the Discover results
/// and the artist page run their release groups through. Without it a prolific artist is a wall of
/// near-duplicates — "X", "X (Deluxe)", "X - Remastered" and "X Era" are four tiles for one album —
/// and the phone was rendering `release_groups` raw.

/// Display order for the release-type filter (`RELEASE_TYPE_ORDER`).
///
/// A fixed order rather than whatever the discography happens to list first: the chips are a
/// navigation control, and one that reorders itself per artist cannot be learned.
const releaseTypeOrder = ['Album', 'EP', 'Single', 'Broadcast', 'Other'];

/// The catalog key naming one release type.
///
/// Derived from the wire value the same way the variant badges are: the keys are literally
/// `manager:discover.type.<PrimaryType>`, so a type MusicBrainz starts sending that this build has
/// no word for renders the key rather than silently reading as something else.
String releaseTypeKey(String type) => 'manager:discover.type.$type';

/// The bracketed and dash-suffixed qualifiers a title picks up per edition.
///
/// `[([{]…[)\]}]` covers "(Deluxe)", "[Remastered]", "{...}"; the second and third strip the same
/// words when they arrive after a dash or on their own at the end.
final _bracketed = RegExp(r'\s*[([{][^)\]}]*[)\]}]\s*');
final _dashSuffix = RegExp(
  r'\s*[-–—:]\s*(deluxe|expanded|remaster(ed)?|special|anniversary|edition|version|era|bonus|reissue).*$',
  caseSensitive: false,
);
final _bareSuffix = RegExp(
  r'\b(deluxe|expanded|remastered|edition|era|version|reissue)\s*$',
  caseSensitive: false,
);
final _whitespace = RegExp(r'\s+');

/// Strips edition/era qualifiers so "X", "X (Deluxe)" and "X Era" collapse to one key.
String baseTitle(String title) => title
    .toLowerCase()
    .replaceAll(_bracketed, ' ')
    .replaceFirst(_dashSuffix, '')
    .replaceFirst(_bareSuffix, '')
    .replaceAll(_whitespace, ' ')
    .trim();

/// Which of two editions of the same album is the one to keep.
///
/// Owned first, then whichever has a cover, then the original — taken to be the shortest title,
/// since every qualifier only ever adds words.
bool _better(DiscoverReleaseGroup a, DiscoverReleaseGroup b) {
  if (a.owned != b.owned) return a.owned;
  final aCover = a.coverUrl != null;
  final bCover = b.coverUrl != null;
  if (aCover != bCover) return aCover;
  return a.title.length < b.title.length;
}

/// Collapses editions and eras of one album to a single entry, newest first.
///
/// The version type is part of the key on purpose: an instrumental or live release shares the
/// studio album's base title, and without it the version card collapses into the studio card and
/// disappears entirely.
List<DiscoverReleaseGroup> groupReleases(List<DiscoverReleaseGroup> releases) {
  final byBase = <String, DiscoverReleaseGroup>{};
  for (final release in releases) {
    final key = [
      release.artistMbid ?? '',
      release.primaryType ?? 'Other',
      release.versionType ?? '',
      baseTitle(release.title),
    ].join('::');
    final current = byBase[key];
    if (current == null || _better(release, current)) byBase[key] = release;
  }
  return byBase.values.toList()..sort(
    // Descending by partial date, compared as text — `YYYY-MM-DD` sorts correctly as a string,
    // and a shorter partial date ("1997") sorts before its own months, which is what we want.
    (a, b) => (b.firstReleaseDate ?? '').compareTo(a.firstReleaseDate ?? ''),
  );
}

/// The types actually present in [releases], in [releaseTypeOrder].
List<String> presentReleaseTypes(List<DiscoverReleaseGroup> releases) {
  final present = {for (final r in releases) r.primaryType ?? 'Other'};
  return [
    for (final type in releaseTypeOrder)
      if (present.contains(type)) type,
  ];
}
