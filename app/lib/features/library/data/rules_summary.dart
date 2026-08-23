import 'package:chordia_api/chordia_api.dart';

import '../../../i18n/keys.g.dart';
import 'formatting.dart';

/// One line saying what a smart playlist matches, for the slot a hand-built playlist gives its
/// description.
///
/// A port of `frontend/src/lib/playlists/rules-summary.ts`, and it exists for the reason that file
/// gives: a smart playlist has no description and never will — what it holds is decided by its
/// rules, so a sentence about it could only go stale. Rendering the rules themselves cannot.
///
/// Deliberately lossy about sort and limit, which say how the result is ordered and trimmed rather
/// than what qualifies for it.
String summariseSmartRules(SmartRules rules, Translate t) {
  final parts = [
    for (final condition in rules.conditions ?? const <SmartCondition>[])
      _describeCondition(condition, t),
  ].where((part) => part.isNotEmpty);
  if (parts.isEmpty) return '';

  // The joiner IS the match mode. A prefixed "all of:" leaves an "any" list looking identical to
  // an "all" list the moment the prefix scrolls off a truncated line, and that is the one
  // distinction a reader here cannot afford to lose.
  final joiner = rules.matchMode == SmartMatch.any
      ? t(PlaylistsKeys.smartOr)
      : t(PlaylistsKeys.smartAnd);
  return parts.join(' $joiner ');
}

/// What kind of thing a rule's value is, which is what decides how it reads.
///
/// Derived from the field AND the operator, not the field alone: "added in the last 30 days" and
/// "added before 2024-01-01" are the same field asking for a count and a date respectively.
enum SmartValueKind {
  text,
  count,
  year,
  duration,
  date,
  days,
  boolean,
  variant,
}

SmartValueKind smartValueKind(SmartField field, SmartOp op) {
  if (field == SmartField.liked || field == SmartField.explicit) {
    return SmartValueKind.boolean;
  }
  if (field == SmartField.versionType) return SmartValueKind.variant;
  if (field == SmartField.year) return SmartValueKind.year;
  if (field == SmartField.duration) return SmartValueKind.duration;
  if (field == SmartField.plays || field == SmartField.myPlays) {
    return SmartValueKind.count;
  }
  if (_dateFields.contains(field)) {
    return op == SmartOp.inLast || op == SmartOp.notInLast
        ? SmartValueKind.days
        : SmartValueKind.date;
  }
  return SmartValueKind.text;
}

const _dateFields = {
  SmartField.addedAt,
  SmartField.lastPlayed,
  SmartField.firstPlayed,
  SmartField.releaseDate,
};

/// The values a rule holds, as a list, whichever of the two shapes it was written in.
///
/// `value` is kept in sync with the first entry of `values` by every writer, so a rule saved
/// before lists existed and one saved after both resolve to something sensible here.
List<String> smartValuesOf(SmartCondition condition) {
  final list = condition.valuesValue;
  if (list != null && list.isNotEmpty) return list;
  return condition.value.trim().isEmpty ? const [] : [condition.value];
}

String _describeCondition(SmartCondition condition, Translate t) {
  final kind = smartValueKind(condition.field, condition.op);

  // A boolean rule is already a complete phrase in every language the catalogs carry ("liked",
  // "not liked", "explicit", "clean"); putting "Liked is" in front would only make it worse.
  if (kind == SmartValueKind.boolean) {
    final on = condition.value != 'false';
    if (condition.field == SmartField.explicit) {
      return t(
        on
            ? PlaylistsKeys.smartBoolExplicitTrue
            : PlaylistsKeys.smartBoolExplicitFalse,
      );
    }
    return t(
      on ? PlaylistsKeys.smartBoolLikedTrue : PlaylistsKeys.smartBoolLikedFalse,
    );
  }

  final value = _describeValue(condition, kind, t);
  if (value.isEmpty) return '';
  final field = t('playlists:smart.field.${condition.field.wire}');
  final op = t('playlists:smart.op.${condition.op.wire}');
  // The window goes last: "My plays is at least 5 in the last 30 days" is the order the sentence
  // is read in, and it keeps the field beside its operator.
  final period = condition.period == null
      ? ''
      : ' ${_describePeriod(condition.period!, t)}';
  return '$field $op $value$period';
}

String _describeValue(
  SmartCondition condition,
  SmartValueKind kind,
  Translate t,
) {
  String one(String raw) => kind == SmartValueKind.duration
      ? trackClock(int.tryParse(raw) ?? 0)
      : raw;

  if (condition.op == SmartOp.between) {
    return '${one(condition.value)}–${one(condition.value2 ?? '')}';
  }
  if (kind == SmartValueKind.days) {
    return '${condition.value} ${t(PlaylistsKeys.smartUnitDays)}';
  }
  // Text rules accept a list and every entry matters, so all of them are named. A summary reading
  // "Artist is Bjork" when the rule also matches two other artists is worse than no summary.
  final values = smartValuesOf(condition);
  if (values.length > 1) return values.join(', ');
  return one(values.isEmpty ? condition.value : values.first);
}

String _describePeriod(SmartPeriod period, Translate t) => switch (period) {
  SmartPeriodMonth(:final month) => t(PlaylistsKeys.smartPeriodMonth, {
    'month': month,
  }),
  SmartPeriodYear(:final year) => t(PlaylistsKeys.smartPeriodYear, {
    'year': year,
  }),
  SmartPeriodRolling(:final days) => t(PlaylistsKeys.smartPeriodRolling, {
    'count': days,
  }),
};

/// "Every 30 minutes" / "Every 6 hours" / "Every day" — whole units only, so never "1.5 hours".
///
/// Mirrors `frontend/src/lib/playlists/refresh.ts`. `0` is the contract's explicit "never", and
/// the Hub clamps anything out of its accepted range rather than rejecting it, so a drift here
/// shows up as a schedule that does not match its label.
String smartRefreshLabel(int minutes, Translate t) {
  if (minutes == 0) return t(PlaylistsKeys.smartRefreshNever);
  if (minutes % 10080 == 0) {
    return t(PlaylistsKeys.smartRefreshEveryWeek, {'count': minutes ~/ 10080});
  }
  if (minutes % 1440 == 0) {
    return t(PlaylistsKeys.smartRefreshEveryDay, {'count': minutes ~/ 1440});
  }
  if (minutes % 60 == 0) {
    return t(PlaylistsKeys.smartRefreshEveryHour, {'count': minutes ~/ 60});
  }
  return t(PlaylistsKeys.smartRefreshEveryMinute, {'count': minutes});
}
