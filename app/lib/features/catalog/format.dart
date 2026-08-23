import '../../i18n/keys.g.dart';
import '../../i18n/translations.dart';

/// One track's length as a clock reading — `3:45`, or `1:02:03` past an hour.
///
/// Not localised, and that is on purpose: this is a duration people read as a timecode, the same
/// shape every music player has used for decades, and the web client formats it identically. The
/// runtime of a whole release is the localised one — see [formatRuntime].
String formatTrackLength(int milliseconds) {
  final totalSeconds = (milliseconds / 1000).round();
  final seconds = totalSeconds % 60;
  final minutes = (totalSeconds ~/ 60) % 60;
  final hours = totalSeconds ~/ 3600;
  final body = '$minutes:${seconds.toString().padLeft(2, '0')}';
  return hours > 0 ? '$hours:${body.padLeft(5, '0')}' : body;
}

/// Total runtime of a collection, rounded to whole minutes.
///
/// Rounds rather than truncates so a 47m50s album reads "48 min" rather than "47 min" — this is a
/// header stat, not a seek target. Mirrors the web client's `totalDuration` so the two clients
/// cannot drift apart on the same album.
String formatRuntime(Translations t, int milliseconds) {
  final minutes = (milliseconds / 60000).round();
  if (minutes >= 60) {
    return t(CatalogKeys.albumDurationHrMin, {
      'count': minutes ~/ 60,
      'minutes': minutes % 60,
    });
  }
  return t(CatalogKeys.albumDurationMin, {'minutes': minutes});
}

/// Sum of a list of track lengths, in milliseconds.
int totalDurationMs(Iterable<int> durations) =>
    durations.fold(0, (sum, ms) => sum + ms);

/// The year of a raw MusicBrainz partial date (`YYYY`, `YYYY-MM`, or `YYYY-MM-DD`).
///
/// Sliced rather than parsed: `DateTime.parse` needs a full date, and reading a `YYYY-MM-DD` as a
/// `DateTime` interprets it as UTC, which can shift the year across a time zone at New Year.
String? yearOf(String? partialDate) {
  if (partialDate == null || partialDate.length < 4) return null;
  final year = partialDate.substring(0, 4);
  return int.tryParse(year) == null ? null : year;
}

/// Joins the non-empty parts of a facts line with the separator every Chordia surface uses.
String joinFacts(Iterable<String?> parts) =>
    parts.where((p) => p != null && p.isNotEmpty).join(' · ');

/// Genre tags that read as acronyms rather than Title Case.
const _genreAcronyms = {'edm', 'idm', 'dnb', 'uk', 'us', 'dj', 'mc'};

/// Display casing for a genre tag.
///
/// Genres are stored tag-normalised (lowercase) because that is how they fold — "hip hop",
/// "Hip-Hop" and "hip-hop" are one genre. Casing is therefore a display decision, made here rather
/// than by a text-transform, because no CSS-style rule can know that "EDM" is not "Edm".
///
/// Tokenises on letters and digits, so hyphens, ampersands and "80s" all split naturally, and is
/// Unicode-aware so an accented tag is not mangled.
String titleCaseGenre(String name) => name.replaceAllMapped(
  RegExp(r'[\p{L}\p{N}]+', unicode: true),
  (match) {
    final word = match[0]!;
    if (_genreAcronyms.contains(word.toLowerCase())) return word.toUpperCase();
    return word[0].toUpperCase() + word.substring(1);
  },
);

/// The fold key a genre page is addressed by: lowercase, every run of non-alphanumerics collapsed
/// to one space. Mirrors the Hub's own fold, so every spelling links to the same page.
String genreSlug(String name) =>
    name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), ' ').trim();
