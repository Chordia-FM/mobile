import 'package:chordia_api/chordia_api.dart';

/// How complete [owned] of [total] is, as a whole percent — or **null** when there is nothing to
/// be a percentage of.
///
/// Zero of zero is not 0%. A library that has not finished syncing, or an artist whose
/// discography has never been fetched, has no denominator: the Hub sends `0.0` for the percentage
/// in that case because a float has no way to say "unknown", and rendering that as "0%" claims a
/// completeness figure nobody computed. Every caller here treats null as "say nothing yet" and
/// shows the empty state instead.
int? coveragePercent(int owned, int total) {
  if (total <= 0) return null;
  return ((owned / total) * 100).round().clamp(0, 100);
}

/// Album-level completeness for a summary, or null when no release-groups are known yet.
///
/// Computed from the counts rather than read from [CoverageSummary.albumPct], so the percentage
/// and the "{owned} of {total}" line printed beside it are provably the same division — the Hub
/// derives its float the same way, and two independently rounded renderings of one number are a
/// mismatch waiting to be reported as a bug.
int? albumCoveragePercent(CoverageSummary summary) =>
    coveragePercent(summary.ownedRgs, summary.totalRgs);

/// Artist-level completeness: artists fully owned over artists tracked, or null when none are.
int? artistCoveragePercent(CoverageSummary summary) =>
    coveragePercent(summary.completeArtists, summary.touchedArtists);

/// True when the Hub has nothing to report yet — no tracked artist, no release-group.
///
/// The distinction that matters: this is "we have not measured anything", not "you own nothing".
/// The screens render the `manager:coverage.empty` sentence for it rather than a row of zeroes,
/// which would read as a verdict on the user's library.
bool coverageIsUnmeasured(CoverageSummary summary) =>
    summary.touchedArtists == 0 && summary.totalRgs == 0;

/// One artist's completeness, or null when there is no discography to measure against.
///
/// Two ways to have nothing to say, and both must render as "unknown" rather than 0%: the artist
/// has no MusicBrainz match at all (nothing to diff), or the cache holds neither an owned album
/// nor a missing one (the fetch has not landed). The Hub sends `0.0` in both cases.
int? artistCoveragePercentOf(ArtistCoverage coverage) {
  final mbid = coverage.artistMbid;
  if (mbid == null || mbid.isEmpty) return null;
  if (coverage.owned.isEmpty && coverage.missing.isEmpty) return null;
  return coverage.coveragePct.round().clamp(0, 100);
}

/// The libraries counted toward coverage, after [excluded] is applied.
///
/// Both halves of the summary carry the exclusion set — the flat [CoverageSummary.excludedLibraryIds]
/// and the per-row [LibraryCoverage.excluded] — so an optimistic toggle has to move both or the
/// checkbox and the counts disagree for as long as the write is in flight.
CoverageSummary withExclusions(CoverageSummary summary, Set<String> excluded) =>
    CoverageSummary(
      albumPct: summary.albumPct,
      artistPct: summary.artistPct,
      completeArtists: summary.completeArtists,
      excludedLibraryIds: excluded.toList()..sort(),
      includeShared: summary.includeShared,
      ownedRgs: summary.ownedRgs,
      pendingArtists: summary.pendingArtists,
      perLibrary: [
        for (final library in summary.perLibrary)
          LibraryCoverage(
            albumCount: library.albumCount,
            artistCount: library.artistCount,
            excluded: excluded.contains(library.libraryId),
            libraryId: library.libraryId,
            name: library.name,
            owned: library.owned,
            trackCount: library.trackCount,
          ),
      ],
      totalRgs: summary.totalRgs,
      touchedArtists: summary.touchedArtists,
    );

/// The year of a raw MusicBrainz partial date (`YYYY`, `YYYY-MM`, `YYYY-MM-DD`).
///
/// Sliced rather than parsed: `DateTime.parse` needs a full date, and reading `YYYY-MM-DD` as a
/// `DateTime` treats it as UTC, which can shift the year across a time zone at New Year.
String? releaseYear(String? partialDate) {
  if (partialDate == null || partialDate.length < 4) return null;
  final year = partialDate.substring(0, 4);
  return int.tryParse(year) == null ? null : year;
}
