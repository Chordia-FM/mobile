import '../../../i18n/keys.g.dart';

/// A bound `ref.t`, so the pure helpers below can localise without reaching for a `WidgetRef`.
typedef Translate = String Function(String key, [Map<String, Object?> args]);

/// Total runtime of a collection, rounded to whole minutes.
///
/// Rounds rather than truncates, matching the web client: a 47m50s album reads "48 min" instead
/// of "47 min", and the number is a header stat rather than a seek target. Stops at hours — the
/// days tier belongs to listening totals, which are a different namespace and a different unit.
String totalDuration(int ms, Translate t) {
  final minutes = (ms / 60000).round();
  return minutes >= 60
      ? t(CatalogKeys.albumDurationHrMin, {
          'count': minutes ~/ 60,
          'minutes': minutes % 60,
        })
      : t(CatalogKeys.albumDurationMin, {'minutes': minutes});
}

/// One track's length as `m:ss`, the form a row shows beside its title.
String trackClock(int ms) {
  final seconds = (ms / 1000).round();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Bytes as a short human string, mirroring the web client's ladder exactly so the same download
/// does not read as "1.0 MB" on the phone and "1,024 KB" in the browser.
///
/// Not localised: the numerals come from the platform's own digit rendering and the units are the
/// SI-style symbols every locale in the catalogs uses untranslated.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final mb = bytes / (1024 * 1024);
  if (mb < 1) return '${(bytes / 1024).round()} KB';
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}
