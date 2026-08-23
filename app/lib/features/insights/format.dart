import 'package:chordia_api/chordia_api.dart';
import 'package:intl/intl.dart';

import '../../i18n/keys.g.dart';
import '../social/data/social_messages.dart' show Translate;

/// Compact duration for a listening total: "3d 4h", "2h 41m", "15m", "40s".
///
/// Seconds only appear under a minute — a single short play should read "40s", not the
/// broken-looking "0m" — and minutes are dropped once days are involved. Mirrors the web client's
/// `msToTime` so the same total reads the same on both.
String msToTime(int ms, Translate t) {
  final totalSeconds = ms ~/ 1000;
  if (totalSeconds < 60) {
    return t(InsightsKeys.durationSeconds, {'seconds': totalSeconds});
  }
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  if (hours >= 24) {
    final days = hours ~/ 24;
    final remainder = hours % 24;
    return remainder > 0
        ? t(InsightsKeys.durationDaysHours, {'days': days, 'hours': remainder})
        : t(InsightsKeys.durationDays, {'days': days});
  }
  if (hours > 0) {
    return t(InsightsKeys.durationHoursMinutes, {
      'hours': hours,
      'minutes': minutes,
    });
  }
  return t(InsightsKeys.durationMinutes, {'minutes': minutes});
}

/// How long ago a play was: "just now", "12m ago", "yesterday", then a short date.
///
/// The date is formatted here rather than inside the catalog string, which is this app's
/// convention: `Translations` passes arguments straight to ICU, and every dated string in the
/// catalogs therefore takes an already-formatted value.
///
/// [now] is injectable so a test asserting on the wording is not measuring the machine's clock.
String relativePlayTime(
  int epochMs,
  Translate t, {
  required String locale,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final difference = current.millisecondsSinceEpoch - epochMs;
  if (difference < 60000) return t(InsightsKeys.relativeJustNow);
  if (difference < 3600000) {
    return t(InsightsKeys.relativeMinutesAgo, {'minutes': difference ~/ 60000});
  }
  if (difference < 86400000) {
    return t(InsightsKeys.relativeHoursAgo, {'hours': difference ~/ 3600000});
  }
  final at = DateTime.fromMillisecondsSinceEpoch(epochMs);
  if (_sameDay(at, current)) return t(InsightsKeys.relativeToday);
  if (_sameDay(at, current.subtract(const Duration(days: 1)))) {
    return t(InsightsKeys.relativeYesterday);
  }
  return t(InsightsKeys.relativeShortDate, {
    'date': DateFormat.MMMd(locale).format(at),
  });
}

/// The catalogs' `{person, select, …}` argument: the same sentence is written twice, once about the
/// reader and once about somebody else, and picking the wrong one has a report telling you about
/// "their" listening on your own page.
Map<String, Object?> personArg({required bool own}) => {
  'person': own ? 'you' : 'them',
};

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The label for one reporting window.
String periodLabel(Period period, Translate t) => t(switch (period) {
  Period.day => InsightsKeys.periodDay,
  Period.week => InsightsKeys.periodWeek,
  Period.month => InsightsKeys.periodMonth,
  Period.quarter => InsightsKeys.periodQuarter,
  Period.halfYear => InsightsKeys.periodHalfYear,
  Period.year => InsightsKeys.periodYear,
  Period.overall => InsightsKeys.periodOverall,
});

/// The Wrapped card's subheading for one window ("Your year in music").
String rotationPeriodTitle(Period period, Translate t) => t(switch (period) {
  // The card has no day-window copy of its own: a single day is the one window whose headline is
  // the same sentence as a week's, and the web client's set starts at `week`.
  Period.day || Period.week => InsightsKeys.rotationPeriodTitleWeek,
  Period.month => InsightsKeys.rotationPeriodTitleMonth,
  Period.quarter => InsightsKeys.rotationPeriodTitleQuarter,
  Period.halfYear => InsightsKeys.rotationPeriodTitleHalfYear,
  Period.year => InsightsKeys.rotationPeriodTitleYear,
  Period.overall => InsightsKeys.rotationPeriodTitleOverall,
});

/// The weekday name for a `ListeningCharts.weekday` index (0 = Sunday).
String weekdayLabel(int index, Translate t) => t(switch (index % 7) {
  0 => InsightsKeys.weekdaySun,
  1 => InsightsKeys.weekdayMon,
  2 => InsightsKeys.weekdayTue,
  3 => InsightsKeys.weekdayWed,
  4 => InsightsKeys.weekdayThu,
  5 => InsightsKeys.weekdayFri,
  _ => InsightsKeys.weekdaySat,
});

/// Whether a window can be compared with the one before it.
///
/// "All time" has no previous window, and a bounded window whose predecessor was empty produces a
/// page of "New" chips that say nothing — the report collapses both into one "first window on
/// record" line instead.
bool comparable(WrappedReport report) =>
    report.period != Period.overall && report.totalPlaysCompared.change != null;
