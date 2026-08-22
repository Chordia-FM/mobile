import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/foundation.dart';

import 'playlists_api.dart';
import 'smart_model.dart';

/// The rule builder's working copy of a smart playlist.
///
/// It holds the draft, keeps the live preview in step with it, and turns the draft into the two
/// contract shapes on save. Rules are only ever assembled through [smart_model.dart], so a
/// combination the Hub would refuse cannot be reached from here — the editor never invents a
/// condition, it asks for one.
///
/// The preview is debounced rather than fired per keystroke: it is a full catalog query, and a
/// phone typing "Radiohead" would otherwise ask the Hub nine times for eight answers nobody sees.
class SmartDraft extends ChangeNotifier {
  SmartDraft({
    required SmartPlaylistsApi api,
    required void Function(Object error) onFailure,
    SmartSource? existing,
    this.debounce = const Duration(milliseconds: 400),
  }) : _api = api,
       _onFailure = onFailure,
       playlistId = existing?.id,
       name = existing?.name ?? '',
       _matchMode = existing?.rules.matchMode ?? SmartMatch.all,
       _rows = existing == null ? [] : rowsFrom(existing.rules),
       _sort = existing?.rules.sort ?? SmartSort.title,
       _sortDir = existing?.rules.sortDir,
       _sortPeriod = existing?.rules.sortPeriod,
       _limit = existing?.rules.limit,
       _refreshIntervalMinutes = existing?.refreshIntervalMinutes,
       _refreshOnComplete = existing?.refreshOnComplete ?? false;

  final SmartPlaylistsApi _api;
  final void Function(Object error) _onFailure;
  final Duration debounce;

  /// Null while this is a playlist that does not exist yet.
  final String? playlistId;

  bool get isNew => playlistId == null;

  String name;

  SmartMatch _matchMode;
  List<RuleRow> _rows;
  SmartSort _sort;
  SmartSortDir? _sortDir;
  SmartPeriod? _sortPeriod;
  int? _limit;
  int? _refreshIntervalMinutes;
  bool _refreshOnComplete;

  SmartMatch get matchMode => _matchMode;
  List<RuleRow> get rows => List.unmodifiable(_rows);
  SmartSort get sort => _sort;
  SmartSortDir? get sortDir => _sortDir;
  SmartPeriod? get sortPeriod => _sortPeriod;
  int? get limit => _limit;
  int? get refreshIntervalMinutes => _refreshIntervalMinutes;
  bool get refreshOnComplete => _refreshOnComplete;

  SmartPreview? _preview;
  bool _previewing = false;
  Object? _previewError;
  Timer? _debounce;

  /// Increments on every scheduled preview, so an answer to a rule set the person has already
  /// edited past is dropped instead of overwriting the newer one.
  int _previewGeneration = 0;
  bool _disposed = false;

  SmartPreview? get preview => _preview;
  bool get previewing => _previewing;
  Object? get previewError => _previewError;

  /// The draft as the contract wants it. Unfinished rows are dropped, not rejected.
  SmartRules get rules => rulesFrom(
    matchMode: _matchMode,
    rows: _rows,
    sort: _sort,
    sortDir: _sortDir,
    sortPeriod: _sortPeriod,
    limit: _limit,
  );

  /// Whether the draft can be saved. A name is the only hard requirement — a smart playlist with
  /// no rules is legal and matches everything, which is a thing people deliberately build before
  /// narrowing it down.
  bool get canSave => name.trim().isNotEmpty;

  void setName(String value) {
    name = value;
    notifyListeners();
  }

  void setMatchMode(SmartMatch mode) {
    _matchMode = mode;
    _changed();
  }

  void addRule(SmartField field) {
    _rows = [..._rows, RuleRow(conditionFor(field))];
    _changed();
  }

  void removeRuleAt(int index) {
    if (index < 0 || index >= _rows.length) return;
    _rows = [..._rows]..removeAt(index);
    _changed();
  }

  /// Retargets a row onto a different field, keeping the typed value when the new field wants the
  /// same kind of value.
  void setRuleField(int index, SmartField field) =>
      _updateRow(index, (c) => retargetField(c, field));

  /// Only operators [opsFor] offers reach this: the picker is built from that list, so an
  /// operator the field does not support is not a state the editor can be put into.
  void setRuleOp(int index, SmartOp op) =>
      _updateRow(index, (c) => retargetOp(c, op));

  void setRuleValue(int index, String value) => _updateRow(
    index,
    (c) => SmartCondition(
      field: c.field,
      op: c.op,
      value: value,
      period: c.period,
      value2: c.value2,
    ),
  );

  void setRuleValues(int index, List<String> values) => _updateRow(
    index,
    (c) => SmartCondition(
      field: c.field,
      op: c.op,
      value: values.isEmpty ? '' : values.first,
      period: c.period,
      value2: c.value2,
      valuesValue: values.length > 1 ? values : null,
    ),
  );

  void setRuleUpperValue(int index, String value) => _updateRow(
    index,
    (c) => SmartCondition(
      field: c.field,
      op: c.op,
      value: c.value,
      period: c.period,
      value2: value,
      valuesValue: c.valuesValue,
    ),
  );

  /// Scopes a rule to a window of listening history. Null is "all time", which is what the field
  /// means with no window at all — and is why the picker must be able to clear it again.
  void setRulePeriod(int index, SmartPeriod? period) => _updateRow(
    index,
    (c) => SmartCondition(
      field: c.field,
      op: c.op,
      value: c.value,
      period: supportsPeriod(c.field) ? period : null,
      value2: c.value2,
      valuesValue: c.valuesValue,
    ),
  );

  void setSort(SmartSort sort) {
    _sort = sort;
    // A sort that reads a window needs one; every other sort must not carry a leftover.
    if (sortUsesPeriod(sort)) {
      _sortPeriod ??= const SmartPeriodRolling(days: 30);
    } else {
      _sortPeriod = null;
    }
    _changed();
  }

  void setSortDir(SmartSortDir? dir) {
    _sortDir = dir;
    _changed();
  }

  void setSortPeriod(SmartPeriod period) {
    if (!sortUsesPeriod(_sort)) return;
    _sortPeriod = period;
    _changed();
  }

  void setLimit(int? limit) {
    _limit = limit;
    _changed();
  }

  void setRefreshIntervalMinutes(int? minutes) {
    _refreshIntervalMinutes = minutes;
    notifyListeners();
  }

  void setRefreshOnComplete({required bool value}) {
    _refreshOnComplete = value;
    notifyListeners();
  }

  /// Fills the editor in from a starting point. Everything stays editable afterwards — that is the
  /// whole reason presets are rules rather than a server-side playlist type.
  void applyPreset(
    SmartPreset preset,
    DateTime now,
    String Function(Map<String, Object?> args) suggestedName,
  ) {
    final draft = preset.build(now);
    name = suggestedName(draft.nameArgs);
    _matchMode = draft.rules.matchMode ?? SmartMatch.all;
    _rows = rowsFrom(draft.rules);
    _sort = draft.rules.sort ?? SmartSort.title;
    _sortDir = draft.rules.sortDir;
    _sortPeriod = draft.rules.sortPeriod;
    _limit = draft.rules.limit;
    _changed();
  }

  /// Runs the preview now, skipping the debounce. Called once when the editor opens so an existing
  /// playlist shows what its rules match before anything is touched.
  Future<void> refreshPreview() => _runPreview(++_previewGeneration);

  /// Saves the draft and answers with the playlist's id, or null when the Hub refused.
  Future<String?> save({String? coverHash}) async {
    if (!canSave) return null;
    final body = SmartBody(
      name: name.trim(),
      coverHash: coverHash,
      // A PUT replaces the whole body, so the schedule goes up every time rather than being
      // omitted — omitting it on update means "leave alone", which would silently discard the
      // change the person just made in this editor.
      refreshIntervalMinutes: _refreshIntervalMinutes,
      refreshOnComplete: _refreshOnComplete,
      rules: rules,
    );
    try {
      final id = playlistId;
      if (id == null) return (await _api.create(body)).id;
      await _api.update(id, body);
      return id;
    } on Object catch (error) {
      _onFailure(error);
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }

  void _updateRow(int index, SmartCondition Function(SmartCondition c) change) {
    if (index < 0 || index >= _rows.length) return;
    final row = _rows[index];
    final next = change(row.condition);
    _rows = [..._rows]..[index] = row.withCondition(next);
    _changed();
  }

  /// Redraw now, re-query shortly. Every edit reaches this, which is why the preview can never
  /// drift from the rules on screen.
  void _changed() {
    notifyListeners();
    _debounce?.cancel();
    final generation = ++_previewGeneration;
    _debounce = Timer(debounce, () => _runPreview(generation));
  }

  Future<void> _runPreview(int generation) async {
    _previewing = true;
    _notify();
    try {
      final result = await _api.preview(rules);
      if (_disposed || generation != _previewGeneration) return;
      _preview = result;
      _previewError = null;
    } on Object catch (error) {
      if (_disposed || generation != _previewGeneration) return;
      // Not routed to `onFailure`: a preview that fails is a panel that says so, not a snack bar
      // interrupting somebody mid-edit. The save path reports its own failures.
      _previewError = error;
    } finally {
      if (generation == _previewGeneration) {
        _previewing = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
