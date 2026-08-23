import 'package:chordia_api/chordia_api.dart';

import '../../../i18n/keys.g.dart';

/// Everything the smart-playlist builder knows about rules, with no Flutter in it.
///
/// A port of `frontend/src/lib/playlists/smart-model.ts`, and deliberately a port rather than a
/// re-derivation: the contract carries sixteen fields and twelve operators, and which pairs are
/// legal is a real relation. Encoding it twice, differently, is how a phone ends up offering
/// "Liked contains …" — a rule the Hub rejects on save, after the person has typed it.
///
/// The rule that makes this file worth having: the editor is a RENDERING of these tables. Nothing
/// below asks a widget what it may show; widgets ask here.

/// What kind of thing a rule's value is, which is what decides the widget.
///
/// Derived from the field AND the operator, not the field alone: "added in the last 30 days" and
/// "added before 2024-01-01" are the same field asking for a count and a date respectively.
enum ValueKind {
  text,
  count,
  year,
  duration,
  date,
  days,
  boolean,

  /// A fixed list of recording kinds. Not [text]: the values are an enum the Hub stores, and a
  /// free-text box would let somebody type "Live" and match nothing.
  variant,
}

/// Recording kinds, in the order the Hub sorts them: how much the marker changes the recording, so
/// the ones somebody actually reaches for ("not live", "not instrumental") come first.
const versionTypes = <String>[
  'live',
  'acoustic',
  'instrumental',
  'remix',
  'demo',
  'cover',
  'karaoke',
  'extended',
  'radio_edit',
  'single_version',
  'remaster',
  'bonus',
  'deluxe',
];

/// Fields whose value is a moment in time.
const _dateFields = <SmartField>{
  SmartField.addedAt,
  SmartField.lastPlayed,
  SmartField.firstPlayed,
  SmartField.releaseDate,
};

/// Fields that name something in the catalog, so free text is the right input.
const _textFields = <SmartField>{
  SmartField.artist,
  SmartField.title,
  SmartField.album,
  SmartField.genre,
  SmartField.label,
};

ValueKind valueKindOf(SmartField field, SmartOp op) {
  if (field == SmartField.liked || field == SmartField.explicit) {
    return ValueKind.boolean;
  }
  if (field == SmartField.versionType) return ValueKind.variant;
  if (field == SmartField.year) return ValueKind.year;
  if (field == SmartField.duration) return ValueKind.duration;
  if (field == SmartField.plays || field == SmartField.myPlays) {
    return ValueKind.count;
  }
  if (_dateFields.contains(field)) {
    return op == SmartOp.inLast || op == SmartOp.notInLast
        ? ValueKind.days
        : ValueKind.date;
  }
  return ValueKind.text;
}

/// The operators each field accepts, the first being the default.
///
/// Order is menu order, and it is "most useful first" rather than alphabetical — for a date field
/// that is "in the last N days", which is what nearly every date rule someone writes turns out to
/// be. Nothing outside this list is offered, which is what makes an unsendable rule unbuildable.
List<SmartOp> opsFor(SmartField field) {
  if (field == SmartField.liked || field == SmartField.explicit) {
    return const [SmartOp.isValue];
  }
  // `is not` FIRST, deliberately. The request this field exists for is exclusion — "a hundred
  // tracks that are not live and not instrumental" — so the default is the one almost everybody
  // wants rather than the one that happens to read first.
  if (field == SmartField.versionType) {
    return const [SmartOp.notEquals, SmartOp.equals];
  }
  // Each text operator beside its negation, so "is not" is one tap from "is". A rule about what a
  // playlist should EXCLUDE is at least as common as one about what it should include.
  if (_textFields.contains(field)) {
    return const [
      SmartOp.contains,
      SmartOp.notContains,
      SmartOp.equals,
      SmartOp.notEquals,
    ];
  }
  if (field == SmartField.year) {
    return const [
      SmartOp.gte,
      SmartOp.lte,
      SmartOp.between,
      SmartOp.equals,
      SmartOp.notEquals,
    ];
  }
  if (field == SmartField.duration) {
    return const [SmartOp.gte, SmartOp.lte, SmartOp.between];
  }
  if (field == SmartField.plays || field == SmartField.myPlays) {
    return const [
      SmartOp.gte,
      SmartOp.lte,
      SmartOp.equals,
      SmartOp.notEquals,
      SmartOp.between,
    ];
  }
  return const [
    SmartOp.inLast,
    SmartOp.notInLast,
    SmartOp.before,
    SmartOp.after,
    SmartOp.between,
  ];
}

/// Whether a rule on this field takes a LIST of values rather than one.
///
/// Every text field does. "Artist is Ariana Grande or Dua Lipa" is one rule about one field, and
/// without this the only way to write it is a `match any` whose other rows then cannot be ANDed
/// with anything.
bool supportsValueList(SmartField field) => _textFields.contains(field);

/// The values a row holds, as a list, whichever of the two shapes it was written in.
List<String> valuesOf(SmartCondition c) {
  final list = c.valuesValue;
  if (list != null && list.isNotEmpty) return list;
  return c.value.trim().isEmpty ? const [] : [c.value];
}

/// Whether a rule on this field can be scoped to a window of listening history.
bool supportsPeriod(SmartField field) => field == SmartField.myPlays;

/// Whether an operator takes a second, upper-bound value.
bool isRange(SmartOp op) => op == SmartOp.between;

/// Whether a sort reads [SmartRules.sortPeriod]. Only one does, and a window left on any other
/// sort is a field the server would have to decide how to ignore.
bool sortUsesPeriod(SmartSort sort) => sort == SmartSort.myPlaysInPeriod;

/// A group of fields in menu order.
///
/// The grouping is the point. Sixteen fields in one flat list is a wall; split into "what the
/// track is", "how it got into your library" and "how you listen to it", each group answers a
/// different question and somebody looking for "on repeat" knows which third to read.
class FieldGroup {
  const FieldGroup({required this.labelKey, required this.fields});

  final String labelKey;
  final List<SmartField> fields;
}

const fieldGroups = <FieldGroup>[
  FieldGroup(
    labelKey: PlaylistsKeys.smartGroupTrack,
    fields: [
      SmartField.artist,
      SmartField.title,
      SmartField.album,
      SmartField.genre,
      SmartField.label,
      SmartField.year,
      SmartField.releaseDate,
      SmartField.duration,
      SmartField.explicit,
      SmartField.versionType,
    ],
  ),
  FieldGroup(
    labelKey: PlaylistsKeys.smartGroupLibrary,
    fields: [SmartField.addedAt, SmartField.liked],
  ),
  FieldGroup(
    labelKey: PlaylistsKeys.smartGroupListening,
    fields: [
      SmartField.myPlays,
      SmartField.lastPlayed,
      SmartField.firstPlayed,
      SmartField.plays,
    ],
  ),
];

/// Every field the builder offers, in menu order.
final allSmartFields = <SmartField>[
  for (final group in fieldGroups) ...group.fields,
];

/// Sorts offered in the footer, in menu order.
const smartSorts = <SmartSort>[
  SmartSort.title,
  SmartSort.addedAt,
  SmartSort.lastPlayed,
  SmartSort.releaseDate,
  SmartSort.duration,
  SmartSort.myPlays,
  SmartSort.myPlaysInPeriod,
  SmartSort.plays,
  SmartSort.random,
];

/// The default value for a field, so switching field never leaves a rule unsendable.
String defaultValueFor(SmartField field, SmartOp op) => switch (valueKindOf(
  field,
  op,
)) {
  ValueKind.boolean => 'true',
  // A real value, not the empty string every other unseeded kind gets: the picker shows the
  // first entry regardless, so an empty stored value would look like a finished rule and then
  // be dropped on save as incomplete.
  ValueKind.variant => versionTypes.first,
  ValueKind.days => '30',
  ValueKind.count => field == SmartField.myPlays ? '3' : '10',
  _ => '',
};

/// A fresh condition for a field, with its default operator and value.
SmartCondition conditionFor(SmartField field) {
  final op = opsFor(field).first;
  // No period: `my_plays` with no window means all time, which is what "my plays" says. Defaulting
  // to a rolling month made "my plays is 0" mean "not played in the last 30 days" — a narrower
  // rule than the one it reads as.
  return SmartCondition(
    field: field,
    op: op,
    value: defaultValueFor(field, op),
  );
}

/// Re-derives a condition after its field changes.
///
/// Keeps the value only when the new field wants the same kind of value, so Artist → Album keeps
/// what was typed while Artist → Liked does not leave the word "Radiohead" sitting in a boolean.
SmartCondition retargetField(SmartCondition c, SmartField field) {
  if (field == c.field) return c;
  final next = conditionFor(field);
  if (valueKindOf(field, next.op) != valueKindOf(c.field, c.op) ||
      c.value.isEmpty) {
    return next;
  }
  final list = c.valuesValue;
  return SmartCondition(
    field: next.field,
    op: next.op,
    value: c.value,
    // Artist → Album keeps the whole list; Artist → Liked keeps nothing, because a boolean has
    // nowhere to put three artist names.
    valuesValue: supportsValueList(field) && list != null && list.isNotEmpty
        ? list
        : null,
  );
}

/// Re-derives a condition after its operator changes, keeping the value when the kind is unchanged.
SmartCondition retargetOp(SmartCondition c, SmartOp op) {
  if (op == c.op) return c;
  final kindChanged = valueKindOf(c.field, op) != valueKindOf(c.field, c.op);
  return SmartCondition(
    field: c.field,
    op: op,
    value: kindChanged ? defaultValueFor(c.field, op) : c.value,
    period: c.period,
    // `value2` means something only to a range operator, and a stale one would send an upper bound
    // the person cannot see and did not ask for.
    value2: isRange(op) ? c.value2 : null,
    valuesValue: kindChanged ? null : c.valuesValue,
  );
}

/// Whether a condition is complete enough to send.
///
/// A blank rule is dropped rather than rejected: somebody who adds a row and then changes their
/// mind should still be able to save, and an empty row is unambiguously "I did not finish this
/// one". Booleans always count — their value is a choice between two, never absent.
bool isComplete(SmartCondition c) {
  if (valueKindOf(c.field, c.op) == ValueKind.boolean) return true;
  final list = c.valuesValue;
  if (list != null && list.isNotEmpty) return true;
  if (c.value.trim().isEmpty) return false;
  if (isRange(c.op) && (c.value2 ?? '').trim().isEmpty) return false;
  return true;
}

/// The parts of a saved smart playlist the editor works from.
///
/// The Hub answers with two shapes — a summary in a list, a hydrated detail on its own page — and
/// both can be edited. This is the intersection, so the editor takes one type instead of choosing
/// between fabricating the fields a summary has and a detail does not, or the reverse.
class SmartSource {
  const SmartSource({
    required this.id,
    required this.name,
    required this.rules,
    this.refreshIntervalMinutes,
    this.refreshOnComplete,
  });

  factory SmartSource.ofSummary(SmartPlaylist playlist) => SmartSource(
    id: playlist.id,
    name: playlist.name,
    rules: playlist.rules,
    refreshIntervalMinutes: playlist.refreshIntervalMinutes,
    refreshOnComplete: playlist.refreshOnComplete,
  );

  factory SmartSource.ofDetail(SmartPlaylistDetail playlist) => SmartSource(
    id: playlist.id,
    name: playlist.name,
    rules: playlist.rules,
    refreshIntervalMinutes: playlist.refreshIntervalMinutes,
    refreshOnComplete: playlist.refreshOnComplete,
  );

  final String id;
  final String name;
  final SmartRules rules;
  final int? refreshIntervalMinutes;
  final bool? refreshOnComplete;
}

/// A condition plus a stable local key, so a `ListView` can tell two identical rows apart while
/// one of them is being edited. [id] never reaches the contract.
class RuleRow {
  RuleRow(this.condition) : id = 'r${_nextRowId++}';

  RuleRow._(this.id, this.condition);

  static int _nextRowId = 0;

  final String id;
  final SmartCondition condition;

  RuleRow withCondition(SmartCondition next) => RuleRow._(id, next);
}

/// Strips the editor's bookkeeping and drops unfinished rules.
///
/// [sortPeriod] is cleared unless the sort actually uses it, and [limit] is omitted when null so
/// the Hub applies its own default rather than being told "no limit" by a client that simply had
/// nothing to say.
SmartRules rulesFrom({
  required SmartMatch matchMode,
  required List<RuleRow> rows,
  required SmartSort sort,
  SmartSortDir? sortDir,
  SmartPeriod? sortPeriod,
  int? limit,
}) => SmartRules(
  matchMode: matchMode,
  conditions: [
    for (final row in rows)
      if (isComplete(row.condition)) normalizeCondition(row.condition),
  ],
  sort: sort,
  sortDir: sortDir,
  sortPeriod: sortUsesPeriod(sort)
      ? (sortPeriod ?? const SmartPeriodRolling(days: 30))
      : null,
  limit: limit,
);

/// One row as the contract wants it, with the two value shapes reconciled.
///
/// `value` is always the first of the list rather than being left behind, because the server falls
/// back to it for rules written before lists existed. `values` is omitted below two entries: a
/// one-item list and a plain value are the same rule, and storing both spellings would mean every
/// comparison of two rule sets had to know that.
///
/// Blank entries are dropped here as well as server-side. They compile to `%%`, which matches
/// every track.
SmartCondition normalizeCondition(SmartCondition c) {
  if (!supportsValueList(c.field)) {
    return SmartCondition(
      field: c.field,
      op: c.op,
      value: c.value,
      period: supportsPeriod(c.field) ? c.period : null,
      value2: isRange(c.op) ? c.value2 : null,
    );
  }
  final list = [
    for (final value in valuesOf(c))
      if (value.trim().isNotEmpty) value.trim(),
  ];
  return SmartCondition(
    field: c.field,
    op: c.op,
    value: list.isEmpty ? '' : list.first,
    value2: isRange(c.op) ? c.value2 : null,
    valuesValue: list.length > 1 ? list : null,
  );
}

/// The rows an existing rule set opens as. Unknown fields cannot appear — the contract enum falls
/// back to `artist` for a variant this build does not know — but an operator the field no longer
/// accepts can, if a rule was written by a newer client, so it is snapped to a legal one rather
/// than left to fail on save.
List<RuleRow> rowsFrom(SmartRules rules) => [
  for (final condition in rules.conditions ?? const <SmartCondition>[])
    RuleRow(
      opsFor(condition.field).contains(condition.op)
          ? condition
          : retargetOp(condition, opsFor(condition.field).first),
    ),
];

/// `YYYY-MM` for a date, in local time — the same calendar month the person is living in.
String monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// Milliseconds → `m:ss`, for the duration input.
String msToClock(String ms) {
  final n = int.tryParse(ms);
  if (n == null || n <= 0) return '';
  final total = (n / 1000).round();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// `m:ss` (or a bare number of seconds) → milliseconds as a string.
///
/// Returns `''` for anything unparseable rather than `0`: a half-typed "3:" must read as an
/// incomplete rule the save path drops, not as a rule matching everything longer than nothing.
String clockToMs(String text) {
  final t = text.trim();
  if (t.isEmpty) return '';
  final m = RegExp(r'^(\d+):([0-5]?\d)$').firstMatch(t);
  if (m != null) {
    return '${(int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!)) * 1000}';
  }
  if (RegExp(r'^\d+$').hasMatch(t)) return '${int.parse(t) * 1000}';
  return '';
}

/// A starting point somebody picks instead of assembling five dropdowns.
///
/// Presets are ordinary rules, not a server-side playlist type: picking one fills the editor in
/// and every part of it stays editable. That is the whole design — a preset teaches what the rules
/// can express by showing it, where a black-boxed "Top tracks" would teach nothing and then be
/// impossible to adjust.
class SmartPreset {
  const SmartPreset({
    required this.id,
    required this.labelKey,
    required this.descriptionKey,
    required this.nameKey,
    required this.build,
  });

  final String id;
  final String labelKey;
  final String descriptionKey;

  /// The suggested name, as an i18n key. Some take `{month}` or `{year}`.
  final String nameKey;

  final SmartPresetDraft Function(DateTime now) build;
}

/// What a preset fills the editor with.
class SmartPresetDraft {
  const SmartPresetDraft({required this.rules, this.nameArgs = const {}});

  final SmartRules rules;
  final Map<String, Object?> nameArgs;
}

SmartRules _base(
  List<SmartCondition> conditions,
  SmartSort sort, {
  SmartSortDir? sortDir,
  SmartPeriod? sortPeriod,
  int limit = 100,
}) => SmartRules(
  matchMode: SmartMatch.all,
  conditions: conditions,
  limit: limit,
  sort: sort,
  sortDir: sortDir,
  sortPeriod: sortPeriod,
);

final smartPresets = <SmartPreset>[
  SmartPreset(
    id: 'top_month',
    labelKey: PlaylistsKeys.smartPresetsTopMonthLabel,
    descriptionKey: PlaylistsKeys.smartPresetsTopMonthDescription,
    nameKey: PlaylistsKeys.smartPresetsTopMonthName,
    build: (now) {
      final month = monthKey(now);
      final period = SmartPeriodMonth(month: month);
      return SmartPresetDraft(
        rules: _base(
          [
            SmartCondition(
              field: SmartField.myPlays,
              op: SmartOp.gte,
              value: '2',
              period: period,
            ),
          ],
          SmartSort.myPlaysInPeriod,
          sortDir: SmartSortDir.desc,
          sortPeriod: period,
        ),
        nameArgs: {'month': month},
      );
    },
  ),
  SmartPreset(
    id: 'top_year',
    labelKey: PlaylistsKeys.smartPresetsTopYearLabel,
    descriptionKey: PlaylistsKeys.smartPresetsTopYearDescription,
    nameKey: PlaylistsKeys.smartPresetsTopYearName,
    build: (now) {
      final period = SmartPeriodYear(year: now.year);
      return SmartPresetDraft(
        rules: _base(
          [
            SmartCondition(
              field: SmartField.myPlays,
              op: SmartOp.gte,
              value: '5',
              period: period,
            ),
          ],
          SmartSort.myPlaysInPeriod,
          sortDir: SmartSortDir.desc,
          sortPeriod: period,
        ),
        nameArgs: {'year': now.year},
      );
    },
  ),
  SmartPreset(
    id: 'on_repeat',
    labelKey: PlaylistsKeys.smartPresetsOnRepeatLabel,
    descriptionKey: PlaylistsKeys.smartPresetsOnRepeatDescription,
    nameKey: PlaylistsKeys.smartPresetsOnRepeatName,
    build: (now) => const SmartPresetDraft(
      rules: SmartRules(
        matchMode: SmartMatch.all,
        conditions: [
          SmartCondition(
            field: SmartField.myPlays,
            op: SmartOp.gte,
            value: '3',
            period: SmartPeriodRolling(days: 30),
          ),
        ],
        limit: 50,
        sort: SmartSort.myPlaysInPeriod,
        sortDir: SmartSortDir.desc,
        sortPeriod: SmartPeriodRolling(days: 30),
      ),
    ),
  ),
  SmartPreset(
    id: 'forgotten',
    labelKey: PlaylistsKeys.smartPresetsForgottenLabel,
    descriptionKey: PlaylistsKeys.smartPresetsForgottenDescription,
    nameKey: PlaylistsKeys.smartPresetsForgottenName,
    build: (now) => SmartPresetDraft(
      rules: _base(const [
        SmartCondition(
          field: SmartField.liked,
          op: SmartOp.isValue,
          value: 'true',
        ),
        SmartCondition(
          field: SmartField.lastPlayed,
          op: SmartOp.notInLast,
          value: '90',
        ),
      ], SmartSort.random),
    ),
  ),
  SmartPreset(
    id: 'recently_added',
    labelKey: PlaylistsKeys.smartPresetsRecentlyAddedLabel,
    descriptionKey: PlaylistsKeys.smartPresetsRecentlyAddedDescription,
    nameKey: PlaylistsKeys.smartPresetsRecentlyAddedName,
    build: (now) => SmartPresetDraft(
      rules: _base(
        const [
          SmartCondition(
            field: SmartField.addedAt,
            op: SmartOp.inLast,
            value: '30',
          ),
        ],
        SmartSort.addedAt,
        sortDir: SmartSortDir.desc,
      ),
    ),
  ),
  SmartPreset(
    id: 'never_played',
    labelKey: PlaylistsKeys.smartPresetsNeverPlayedLabel,
    descriptionKey: PlaylistsKeys.smartPresetsNeverPlayedDescription,
    nameKey: PlaylistsKeys.smartPresetsNeverPlayedName,
    build: (now) => SmartPresetDraft(
      rules: _base(
        const [
          SmartCondition(
            field: SmartField.myPlays,
            op: SmartOp.equals,
            value: '0',
          ),
        ],
        SmartSort.addedAt,
        sortDir: SmartSortDir.desc,
      ),
    ),
  ),
  SmartPreset(
    id: 'liked_oldest',
    labelKey: PlaylistsKeys.smartPresetsLikedOldestLabel,
    descriptionKey: PlaylistsKeys.smartPresetsLikedOldestDescription,
    nameKey: PlaylistsKeys.smartPresetsLikedOldestName,
    build: (now) => SmartPresetDraft(
      rules: _base(
        const [
          SmartCondition(
            field: SmartField.liked,
            op: SmartOp.isValue,
            value: 'true',
          ),
        ],
        SmartSort.addedAt,
        sortDir: SmartSortDir.asc,
      ),
    ),
  ),
];

/// The i18n key naming a field, an operator or a sort.
///
/// Spelled out rather than derived from `.wire`, because the generated key constants are what the
/// catalogs are checked against — a key built by string concatenation is one nobody can grep for
/// and the i18n tooling cannot see.
String smartFieldKey(SmartField field) => switch (field) {
  SmartField.artist => PlaylistsKeys.smartFieldArtist,
  SmartField.title => PlaylistsKeys.smartFieldTitle,
  SmartField.album => PlaylistsKeys.smartFieldAlbum,
  SmartField.genre => PlaylistsKeys.smartFieldGenre,
  SmartField.year => PlaylistsKeys.smartFieldYear,
  SmartField.plays => PlaylistsKeys.smartFieldPlays,
  SmartField.liked => PlaylistsKeys.smartFieldLiked,
  SmartField.duration => PlaylistsKeys.smartFieldDuration,
  SmartField.addedAt => PlaylistsKeys.smartFieldAddedAt,
  SmartField.lastPlayed => PlaylistsKeys.smartFieldLastPlayed,
  SmartField.firstPlayed => PlaylistsKeys.smartFieldFirstPlayed,
  SmartField.myPlays => PlaylistsKeys.smartFieldMyPlays,
  SmartField.releaseDate => PlaylistsKeys.smartFieldReleaseDate,
  SmartField.label => PlaylistsKeys.smartFieldLabel,
  SmartField.explicit => PlaylistsKeys.smartFieldExplicit,
  SmartField.versionType => PlaylistsKeys.smartFieldVersionType,
};

String smartOpKey(SmartOp op) => switch (op) {
  SmartOp.contains => PlaylistsKeys.smartOpContains,
  SmartOp.equals => PlaylistsKeys.smartOpEquals,
  SmartOp.gte => PlaylistsKeys.smartOpGte,
  SmartOp.lte => PlaylistsKeys.smartOpLte,
  SmartOp.isValue => PlaylistsKeys.smartOpIs,
  SmartOp.before => PlaylistsKeys.smartOpBefore,
  SmartOp.after => PlaylistsKeys.smartOpAfter,
  SmartOp.inLast => PlaylistsKeys.smartOpInLast,
  SmartOp.notInLast => PlaylistsKeys.smartOpNotInLast,
  SmartOp.between => PlaylistsKeys.smartOpBetween,
  SmartOp.notContains => PlaylistsKeys.smartOpNotContains,
  SmartOp.notEquals => PlaylistsKeys.smartOpNotEquals,
};

String smartSortKey(SmartSort sort) => switch (sort) {
  SmartSort.title => PlaylistsKeys.smartSortTitle,
  SmartSort.plays => PlaylistsKeys.smartSortPlays,
  SmartSort.random => PlaylistsKeys.smartSortRandom,
  SmartSort.myPlays => PlaylistsKeys.smartSortMyPlays,
  SmartSort.myPlaysInPeriod => PlaylistsKeys.smartSortMyPlaysInPeriod,
  SmartSort.addedAt => PlaylistsKeys.smartSortAddedAt,
  SmartSort.lastPlayed => PlaylistsKeys.smartSortLastPlayed,
  SmartSort.releaseDate => PlaylistsKeys.smartSortReleaseDate,
  SmartSort.duration => PlaylistsKeys.smartSortDuration,
};

/// The i18n key naming one recording kind.
///
/// Falls back to the raw wire value for a variant this build's catalogs do not carry, which is
/// what a server that gains one looks like from here — an untranslated slug reads badly, but it
/// reads, where a lookup miss would print `playlists:smart.variant.xyz` to the user.
String smartVariantLabel(String variant, String Function(String key) t) {
  final key = switch (variant) {
    'live' => PlaylistsKeys.smartVariantLive,
    'acoustic' => PlaylistsKeys.smartVariantAcoustic,
    'instrumental' => PlaylistsKeys.smartVariantInstrumental,
    'remix' => PlaylistsKeys.smartVariantRemix,
    'demo' => PlaylistsKeys.smartVariantDemo,
    'cover' => PlaylistsKeys.smartVariantCover,
    'karaoke' => PlaylistsKeys.smartVariantKaraoke,
    'extended' => PlaylistsKeys.smartVariantExtended,
    'radio_edit' => PlaylistsKeys.smartVariantRadioEdit,
    'single_version' => PlaylistsKeys.smartVariantSingleVersion,
    'remaster' => PlaylistsKeys.smartVariantRemaster,
    'bonus' => PlaylistsKeys.smartVariantBonus,
    'deluxe' => PlaylistsKeys.smartVariantDeluxe,
    _ => null,
  };
  return key == null ? variant : t(key);
}

/// The value hint for a text field, or null for the kinds whose widget is not a text box.
String? smartValueHintKey(SmartField field) => switch (field) {
  SmartField.artist => PlaylistsKeys.smartValueHintArtist,
  SmartField.title => PlaylistsKeys.smartValueHintTitle,
  SmartField.album => PlaylistsKeys.smartValueHintAlbum,
  SmartField.genre => PlaylistsKeys.smartValueHintGenre,
  SmartField.label => PlaylistsKeys.smartValueHintLabel,
  _ => null,
};
